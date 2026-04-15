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
    private var tapThread: Thread?

    /// Opaque pointer produced by `Unmanaged.passRetained(self)` in `start()`.
    /// Stored here so both `stop()` and `deinit` can release it exactly once.
    private var selfRetainPointer: UnsafeMutableRawPointer?

    /// System uptime at the moment `start()` was called; used to produce
    /// recording-relative timestamps.
    private var startTime: TimeInterval = 0

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
    public func addEvent(timestamp: TimeInterval, globalPoint: CGPoint, type: CursorEventType) {
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
    ///
    /// A `DispatchSemaphore` ensures the background run-loop is up and `runLoop`
    /// is stored before this method returns, eliminating the race window between
    /// `start()` and `stop()`.
    public func start() {
        guard eventTap == nil else { return }

        // Record the reference time for relative timestamps.
        startTime = ProcessInfo.processInfo.systemUptime

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        // Retain self so the C callback can reach it. Store the opaque pointer
        // so we can release it exactly once from stop() or deinit.
        let userInfo = Unmanaged.passRetained(self).toOpaque()
        selfRetainPointer = userInfo

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
            selfRetainPointer = nil
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        // Semaphore ensures the background thread has stored `runLoop` in the
        // lock-protected property before `start()` returns, so `stop()` cannot
        // observe a nil runLoop after `start()` has been called.
        let readySemaphore = DispatchSemaphore(value: 0)

        let bgThread = Thread { [weak self] in
            guard let source, let self else { return }
            let rl = CFRunLoopGetCurrent()
            self.lock.withLock { self.runLoop = rl }
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            readySemaphore.signal()
            CFRunLoopRun()
        }
        bgThread.name = "com.capso.cursortelemetry"
        bgThread.qualityOfService = .userInteractive
        bgThread.start()
        tapThread = bgThread

        // Block until the run loop is running and `runLoop` is set.
        readySemaphore.wait()
    }

    /// Stops the event tap and releases the retained self reference taken in `start()`.
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        // Access runLoop under the lock to avoid a data race with the background thread.
        let rl = lock.withLock { runLoop }
        if let rl { CFRunLoopStop(rl) }

        // Release the retain taken in start() — guarded to only happen once.
        if let ptr = selfRetainPointer {
            Unmanaged<CursorTelemetry>.fromOpaque(ptr).release()
            selfRetainPointer = nil
        }

        eventTap = nil
        runLoopSource = nil
        lock.withLock { runLoop = nil }
        tapThread = nil
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
        // Timestamp is relative to when start() was called, not absolute uptime.
        let timestamp = ProcessInfo.processInfo.systemUptime - startTime

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
        // Use the lock-protected accessor to avoid reading runLoop on an arbitrary thread.
        let rl = lock.withLock { runLoop }
        if let rl { CFRunLoopStop(rl) }

        // Release the retain taken in start() if stop() was never called.
        if let ptr = selfRetainPointer {
            Unmanaged<CursorTelemetry>.fromOpaque(ptr).release()
            selfRetainPointer = nil
        }
    }
}
