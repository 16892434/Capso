// Packages/EditorKit/Sources/EditorKit/AutoZoomDetector.swift

import Foundation
import EffectsKit

/// Detects "interesting moments" in cursor telemetry and proposes zoom segments.
///
/// Two independent candidate streams are built:
///   1. Clicks (left / right) — each click produces a candidate at its position.
///   2. Dwells — contiguous runs where the cursor is nearly stationary produce
///      a candidate at the centroid of the run.
///
/// Candidates are ranked by a "significance" strength (in ms-equivalent units),
/// then a greedy spacing filter drops any two candidates whose center times are
/// within `minSpacing`. Segments are built (with click pre-roll / dwell length
/// rules) and any overlapping segments are merged with a weighted focus.
public enum AutoZoomDetector {

    // MARK: - Tuning constants

    /// Minimum stillness required to count as a dwell.
    static let minDwellDuration: TimeInterval = 0.45
    /// Minimum gap between accepted candidates' center times. Prevents suggestions
    /// from clumping.
    static let minSpacing: TimeInterval = 1.80
    /// Merge two adjacent segments if the gap between them is ≤ this.
    static let mergeGap: TimeInterval = 1.50
    /// Zoom-in starts this far before a click (so it settles on the click).
    static let clickPreRoll: TimeInterval = 1.0
    /// Time spent zoomed after a click (shows the result).
    static let clickPostRoll: TimeInterval = 2.0
    /// Padding each side of a dwell run when computing segment length.
    static let dwellBuffer: TimeInterval = 0.5
    static let defaultZoomLevel: Double = 1.5
    static let defaultDuration: TimeInterval = 3.0
    /// Cap on the duration of any single auto-generated segment.
    /// Cursor telemetry is captured via CGEventTap which only fires on actual
    /// mouse movement — stillness produces NO events — so a natural "user is
    /// reading" pause looks like one long dwell run. Without this cap, a 20s
    /// reading pause would produce a 20s zoom. Merged segments may still
    /// exceed this length.
    static let maxSegmentDuration: TimeInterval = 5.0

    // MARK: - Candidate model (internal)

    private enum CandidateKind {
        case click
        case dwell(duration: TimeInterval)
    }

    private struct Candidate {
        let kind: CandidateKind
        let centerTime: TimeInterval
        let focus: (x: Double, y: Double)
        /// Ranking strength in ms-equivalent units. Clicks = 1000, dwells = duration*1000.
        let strength: Double
    }

    // MARK: - Public entry

    public static func detect(
        events: [CursorEvent],
        duration: TimeInterval
    ) -> [ZoomSegment] {
        guard duration > 0 else { return [] }

        // Step A: build candidates
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let clickCandidates = buildClickCandidates(from: sortedEvents)
        let dwellCandidates = buildDwellCandidates(from: sortedEvents)
        let all = clickCandidates + dwellCandidates

        // Step B: rank and filter by spacing
        let accepted = filterBySpacing(candidates: all)

        // Step C: build segments
        let segments = accepted.map { makeSegment(from: $0, videoDuration: duration) }
            .compactMap { $0 }
            .sorted { $0.startTime < $1.startTime }

        // Step D: merge overlaps
        return mergeOverlapping(segments: segments)
    }

    // MARK: - Step A: candidates

    private static func buildClickCandidates(from events: [CursorEvent]) -> [Candidate] {
        events.compactMap { event in
            guard event.type == .leftClick || event.type == .rightClick else { return nil }
            return Candidate(
                kind: .click,
                centerTime: event.timestamp,
                focus: (event.x, event.y),
                strength: 1000.0
            )
        }
    }

    private static func buildDwellCandidates(from events: [CursorEvent]) -> [Candidate] {
        // Dwell = a gap between consecutive move events whose length is
        // >= minDwellDuration. CGEventTap fires when the cursor moves, not
        // when it is still — so real stillness shows up as a silence in the
        // event stream, not as a cluster of close-in-position samples.
        // The cursor was sitting at `moves[i].position` during the gap, so
        // we use that position as the focus.
        let moves = events.filter { $0.type == .move }
        guard moves.count >= 2 else { return [] }
        var out: [Candidate] = []

        for i in 0..<(moves.count - 1) {
            let gap = moves[i + 1].timestamp - moves[i].timestamp
            guard gap >= minDwellDuration else { continue }
            let centerTime = moves[i].timestamp + gap / 2.0
            out.append(Candidate(
                kind: .dwell(duration: gap),
                centerTime: centerTime,
                focus: (moves[i].x, moves[i].y),
                strength: gap * 1000.0
            ))
        }
        return out
    }

    // MARK: - Step B: spacing filter

    private static func filterBySpacing(candidates: [Candidate]) -> [Candidate] {
        // Sort by strength descending; ties broken by earlier centerTime.
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            return lhs.centerTime < rhs.centerTime
        }

        var accepted: [Candidate] = []
        for candidate in sorted {
            let conflicts = accepted.contains { other in
                abs(candidate.centerTime - other.centerTime) < minSpacing
            }
            if !conflicts {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    // MARK: - Step C: segment construction

    private static func makeSegment(
        from candidate: Candidate,
        videoDuration: TimeInterval
    ) -> ZoomSegment? {
        let (rawStart, rawEnd): (TimeInterval, TimeInterval)
        switch candidate.kind {
        case .click:
            rawStart = candidate.centerTime - clickPreRoll
            rawEnd = candidate.centerTime + clickPostRoll
        case .dwell(let dwellDuration):
            // Cap at maxSegmentDuration so long reading pauses don't produce
            // equally long zooms; the segment stays centered on the dwell midpoint.
            let desired = min(maxSegmentDuration,
                              max(defaultDuration, dwellDuration + 2 * dwellBuffer))
            let half = desired / 2.0
            rawStart = candidate.centerTime - half
            rawEnd = candidate.centerTime + half
        }

        // Shift (don't squish) to stay within [0, videoDuration].
        let segDuration = rawEnd - rawStart
        var start = rawStart
        var end = rawEnd
        if start < 0 {
            start = 0
            end = min(videoDuration, segDuration)
        } else if end > videoDuration {
            end = videoDuration
            start = max(0, end - segDuration)
        }

        guard end > start else { return nil }

        return ZoomSegment(
            startTime: start,
            endTime: end,
            zoomLevel: defaultZoomLevel,
            focusMode: .manual(x: candidate.focus.x, y: candidate.focus.y),
            source: .auto
        )
    }

    // MARK: - Step D: merge overlapping

    /// Merge segments whose gap is within `mergeGap` into a single segment whose
    /// focus is a duration-weighted average. Runs pair-wise in time order, so
    /// a chain A+B+C merges as (A+B) then +C — not a three-way centroid.
    private static func mergeOverlapping(segments: [ZoomSegment]) -> [ZoomSegment] {
        guard !segments.isEmpty else { return [] }
        var merged: [ZoomSegment] = [segments[0]]

        for next in segments.dropFirst() {
            let prev = merged[merged.count - 1]
            if next.startTime <= prev.endTime + mergeGap {
                // Weighted focus by each segment's own duration
                let prevDur = prev.duration
                let nextDur = next.duration
                let total = prevDur + nextDur
                let (px, py) = focusComponents(prev.focusMode)
                let (nx, ny) = focusComponents(next.focusMode)
                let mx = (px * prevDur + nx * nextDur) / total
                let my = (py * prevDur + ny * nextDur) / total

                merged[merged.count - 1] = ZoomSegment(
                    id: prev.id,
                    startTime: prev.startTime,
                    endTime: max(prev.endTime, next.endTime),
                    zoomLevel: defaultZoomLevel,
                    focusMode: .manual(x: mx, y: my),
                    source: .auto
                )
            } else {
                merged.append(next)
            }
        }
        return merged
    }

    private static func focusComponents(_ mode: ZoomFocusMode) -> (Double, Double) {
        if case .manual(let x, let y) = mode { return (x, y) }
        // All auto segments are built with .manual focus mode, so this branch
        // is unreachable. Fall back to frame center if somehow encountered.
        return (0.5, 0.5)
    }
}
