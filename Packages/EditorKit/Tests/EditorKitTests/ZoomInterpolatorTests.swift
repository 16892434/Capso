// Packages/EditorKit/Tests/EditorKitTests/ZoomInterpolatorTests.swift

import Testing
import CoreGraphics
@testable import EditorKit

@Suite("ZoomInterpolator")
struct ZoomInterpolatorTests {

    // MARK: - Helpers

    private static let frameSize = CGSize(width: 1920, height: 1080)

    private func makeInterpolator(segments: [ZoomSegment]) -> ZoomInterpolator {
        ZoomInterpolator(segments: segments, frameSize: Self.frameSize)
    }

    // MARK: - Tests

    @Test("No zoom segments returns identity transform")
    func noSegmentsReturnsIdentity() {
        let interp = makeInterpolator(segments: [])
        let t = interp.transform(at: 5.0, cursorPosition: (x: 0.5, y: 0.5))
        #expect(t == .identity)
    }

    @Test("Inside zoom segment at full strength returns full zoom")
    func insideSegmentFullStrength() {
        // Zoom-in ends at 2.0 + 0.8 = 2.8 s
        // Hold phase: 2.8 – 8.0 s  (endTime = 8.0)
        // At t = 5.0 we are well inside the hold phase → scale == zoomLevel
        let segment = ZoomSegment(
            startTime: 2.0,
            endTime: 8.0,
            zoomLevel: 2.0,
            focusMode: .manual(x: 0.5, y: 0.5)
        )
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 5.0, cursorPosition: nil)
        #expect(abs(t.scale - 2.0) < 1e-9)
    }

    @Test("Before zoom segment returns identity")
    func beforeSegmentReturnsIdentity() {
        let segment = ZoomSegment(startTime: 5.0, endTime: 10.0, zoomLevel: 2.0)
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 1.0, cursorPosition: (x: 0.5, y: 0.5))
        #expect(t == .identity)
    }

    @Test("After zoom segment returns identity")
    func afterSegmentReturnsIdentity() {
        // Segment 2.0–5.0. Zoom-out ends at 5.0 + 0.6 = 5.6 s.
        // At t = 8.0 we are well past the zoom-out phase → identity.
        let segment = ZoomSegment(startTime: 2.0, endTime: 5.0, zoomLevel: 2.0)
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 8.0, cursorPosition: (x: 0.5, y: 0.5))
        #expect(abs(t.scale - 1.0) < 1e-9)
        #expect(abs(t.translateX) < 1e-9)
        #expect(abs(t.translateY) < 1e-9)
    }

    @Test("Zoom-in transition is gradual")
    func zoomInTransitionIsGradual() {
        // Zoom-in phase: startTime = 2.0, ends at 2.8 s
        let segment = ZoomSegment(
            startTime: 2.0,
            endTime: 8.0,
            zoomLevel: 2.0,
            focusMode: .manual(x: 0.5, y: 0.5)
        )
        let interp = makeInterpolator(segments: [segment])

        // Just slightly after start — scale should be between 1.0 and 2.0
        let earlyTransform = interp.transform(at: 2.1, cursorPosition: nil)
        #expect(earlyTransform.scale > 1.0)
        #expect(earlyTransform.scale < 2.0)

        // A bit later — scale should be larger than the early value
        let laterTransform = interp.transform(at: 2.5, cursorPosition: nil)
        #expect(laterTransform.scale > earlyTransform.scale)
    }

    @Test("Manual focus offsets the viewport")
    func manualFocusOffsetsViewport() {
        // Focus at (0.2, 0.8) → after edge-snap the focus is left-of-center (x < 0.5)
        // and below-center (y > 0.5).
        // translateX = (0.5 - focusX) * (scale - 1) * frameWidth  → positive when focusX < 0.5
        // translateY = (0.5 - focusY) * (scale - 1) * frameHeight → negative when focusY > 0.5
        let segment = ZoomSegment(
            startTime: 0.0,
            endTime: 10.0,
            zoomLevel: 2.0,
            focusMode: .manual(x: 0.2, y: 0.8)
        )
        let interp = makeInterpolator(segments: [segment])
        // Query inside the hold phase so strength == 1.0
        let t = interp.transform(at: 5.0, cursorPosition: nil)
        #expect(t.translateX > 0)
        #expect(t.translateY < 0)
    }

    @Test("Follow cursor mode uses cursor position")
    func followCursorUsesCursorPosition() {
        let segment = ZoomSegment(
            startTime: 0.0,
            endTime: 10.0,
            zoomLevel: 2.0,
            focusMode: .followCursor
        )
        let interp = makeInterpolator(segments: [segment])

        // Two different cursor positions at the same timestamp should produce different translations
        let t1 = interp.transform(at: 5.0, cursorPosition: (x: 0.3, y: 0.5))
        let t2 = interp.transform(at: 5.0, cursorPosition: (x: 0.7, y: 0.5))

        #expect(t1.translateX != t2.translateX)
    }

    @Test("Edge snap prevents viewport from exceeding frame bounds")
    func edgeSnapClampsViewport() {
        // Focus at (0.0, 0.0) corner with 2× zoom — without snapping the viewport would go
        // out of bounds. After snapping, translateX and translateY should be non-negative so
        // the left/top edge of the frame is not exposed.
        //
        // viewportHalf = 0.5 / 2.0 = 0.25
        // focusX clamped to 0.25, focusY clamped to 0.25
        // translateX = (0.5 - 0.25) * 1 * 1920 = 0.25 * 1920 = 480 > 0 ✓
        let segment = ZoomSegment(
            startTime: 0.0,
            endTime: 10.0,
            zoomLevel: 2.0,
            focusMode: .manual(x: 0.0, y: 0.0)
        )
        let interp = makeInterpolator(segments: [segment])
        let t = interp.transform(at: 5.0, cursorPosition: nil)

        // Both translations should be positive (frame shifted right/down, clamping top-left corner)
        #expect(t.translateX >= 0)
        #expect(t.translateY >= 0)

        // Verify the exact clamped value
        let expectedTranslateX = (0.5 - 0.25) * (2.0 - 1.0) * 1920.0
        let expectedTranslateY = (0.5 - 0.25) * (2.0 - 1.0) * 1080.0
        #expect(abs(t.translateX - expectedTranslateX) < 1e-9)
        #expect(abs(t.translateY - expectedTranslateY) < 1e-9)
    }
}
