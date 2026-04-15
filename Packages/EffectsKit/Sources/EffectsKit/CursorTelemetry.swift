// Packages/EffectsKit/Sources/EffectsKit/CursorTelemetry.swift

@preconcurrency import Foundation
import CoreGraphics

/// Records cursor movement and click events during a screen recording session.
///
/// Events are captured via a CGEvent tap on a dedicated background thread and
/// stored as normalized coordinates relative to the recording area. The data can
/// be exported and serialized to JSON for post-processing in the recording editor.
///
/// - Note: `CursorTelemetry` is separate from `ClickMonitor` by design.
///   `ClickMonitor` drives real-time visual effects during recording; `CursorTelemetry`
///   accumulates data for offline editor use.
public final class CursorTelemetry: @unchecked Sendable {

    // MARK: - Private state

    private let recordingRect: CGRect
    private let lock = NSLock()
    private var events: [CursorEvent] = []

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    // MARK: - Init

    /// Creates a new telemetry recorder for the given recording area.
    /// - Parameter recordingRect: The region being recorded, in global display coordinates
    ///   (flipped or un-flipped — must match the coordinate system of the CGEvent location
    ///   values that will be reported by the event tap on the target display).
    public init(recordingRect: CGRect) {
        self.recordingRect = recordingRect
    }

    // MARK: - Coordinate normalization

    /// Converts a global display point to normalized coordinates [0, 1] clamped to the
    /// recording area.
    ///
    /// - Parameter globalPoint: A point in global display coordinates.
    /// - Returns: `(x, y)` in [0, 1] × [0, 1], clamped if the point is outside the rect.
    public func normalize(globalPoint: CGPoint) -> (x: Double, y: Double) {
        let w = recordingRect.width
        let h = recordingRect.height

        guard w > 0, h > 0 else { return (0, 0) }

        let rawX = (globalPoint.x - recordingRect.minX) / w
        let rawY = (globalPoint.y - recordingRect.minY) / h

        let clampedX = min(max(Double(rawX), 0.0), 1.0)
        let clampedY = min(max(Double(rawY), 0.0), 1.0)
        return (clampedX, clampedY)
    }

    // MARK: - Manual event injection (primarily for testing)

    /// Appends an event directly. Use this for testing or synthetic event injection.
    /// The coordinates are normalized and clamped relative to the recording area.
    public func addEvent(timestamp: Double, globalPoint: CGPoint, type: CursorEventType) {
        let (nx, ny) = normalize(globalPoint: globalPoint)
        let event = CursorEvent(timestamp: timestamp, x: nx, y: ny, type: type)
        lock.withLock { events.append(event) }
    }

    // MARK: - CGEvent tap lifecycle

    /// Starts capturing cursor events via a CGEvent tap on a background thread.
    ///
    /// Captures: `.mouseMoved`, `.leftMouseDragged`, `.rightMouseDragged`,
    /// `.leftMouseDown`, `.rightMouseDown`.
    /// The tap runs in listen-only mode (`.listenOnly`) at `.cghidEventTap`.
    public func start() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        // Retain self so the C callback can reach it.
        let userInfo = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let telemetry = Unmanaged<CursorTelemetry>.fromOpaque(userInfo).takeUnretainedValue()
                telemetry.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            // tapCreate failed; release the retained self to avoid leak.
            Unmanaged<CursorTelemetry>.fromOpaque(userInfo).release()
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        let bgThread = Thread { [weak self] in
            guard let source, let self else { return }
            let rl = CFRunLoopGetCurrent()
            self.runLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        bgThread.name = "com.capso.cursortelemetry"
        bgThread.start()
        self.thread = bgThread
    }

    /// Stops the event tap and frees the retained self reference.
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let rl = runLoop {
            CFRunLoopStop(rl)
        }
        // Release the retain taken in start().
        if eventTap != nil {
            Unmanaged.passUnretained(self).release()
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        thread = nil
    }

    // MARK: - Export & persistence

    /// Returns a snapshot of all events collected so far, thread-safely.
    public func exportData() -> CursorTelemetryData {
        let snapshot = lock.withLock { events }
        return CursorTelemetryData(
            recordingAreaWidth: Double(recordingRect.width),
            recordingAreaHeight: Double(recordingRect.height),
            events: snapshot
        )
    }

    /// Encodes the telemetry data as JSON and writes it to the given URL.
    public func save(to url: URL) throws {
        let data = exportData()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url, options: .atomic)
    }

    /// Reads and decodes `CursorTelemetryData` from a JSON file.
    public static func load(from url: URL) throws -> CursorTelemetryData {
        let jsonData = try Data(contentsOf: url)
        return try JSONDecoder().decode(CursorTelemetryData.self, from: jsonData)
    }

    // MARK: - Private helpers

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        let location = event.location
        let timestamp = ProcessInfo.processInfo.systemUptime

        let eventType: CursorEventType
        switch type {
        case .leftMouseDown:
            eventType = .leftClick
        case .rightMouseDown:
            eventType = .rightClick
        default:
            eventType = .move
        }

        let (nx, ny) = normalize(globalPoint: CGPoint(x: location.x, y: location.y))
        let cursorEvent = CursorEvent(timestamp: timestamp, x: nx, y: ny, type: eventType)
        lock.withLock { events.append(cursorEvent) }
    }

    // MARK: - Deinit

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let rl = runLoop {
            CFRunLoopStop(rl)
        }
    }
}
