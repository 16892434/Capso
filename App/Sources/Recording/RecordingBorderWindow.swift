// App/Sources/Recording/RecordingBorderWindow.swift
import AppKit

@MainActor
final class RecordingBorderWindow: NSPanel {
    init(frame: CGRect, screen: NSScreen) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Prevent ScreenCaptureKit from capturing this window (macOS 14.2+)
        self.sharingType = .none

        let borderView = RecordingBorderView(frame: NSRect(origin: .zero, size: frame.size))
        self.contentView = borderView
    }

    func show() { makeKeyAndOrderFront(nil) }
    func hide() { orderOut(nil) }
}

private class RecordingBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let borderWidth: CGFloat = 3
        let inset = borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(borderWidth)
        context.stroke(rect)
    }
}
