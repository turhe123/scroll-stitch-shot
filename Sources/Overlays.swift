import AppKit
import SwiftUI

/// The region chosen by the user, in global AppKit coordinates, and the screen it lies on.
struct Selection {
    let rect: CGRect
    let screen: NSScreen
}

/// Borderless window that can become key so the overlay receives Return / Escape.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Full-screen transparent overlay on the display under the cursor for dragging out the capture rectangle.
final class RegionSelector {
    private var window: NSWindow?
    private let completion: (Selection?) -> Void

    init(completion: @escaping (Selection?) -> Void) {
        self.completion = completion
    }

    func begin() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            completion(nil)
            return
        }
        let window = KeyableWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)
        let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] local in
            let selection = local.map { Selection(rect: $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), screen: screen) }
            DispatchQueue.main.async { self?.finish(selection) }
        }
        window.contentView = view
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.crosshair.set()
        self.window = window
    }

    private func finish(_ selection: Selection?) {
        window?.orderOut(nil)
        window = nil
        NSCursor.arrow.set()
        completion(selection)
    }
}

/// Draws the dimmed backdrop, the selection rectangle, its size label and instructions.
private final class SelectionView: NSView {
    static let minSide: CGFloat = 100
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?
    private var hint: String?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y)).integral
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        hint = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        if let rect = selection, !isLargeEnough(rect) {
            hint = "Region too small — drag at least 100 × 100 pt."
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onFinish?(nil)
        case 36, 76:
            if let rect = selection, isLargeEnough(rect) {
                onFinish?(rect)
            } else {
                hint = "Drag a region of at least 100 × 100 pt first."
                NSSound.beep()
                needsDisplay = true
            }
        default: super.keyDown(with: event)
        }
    }

    private func isLargeEnough(_ rect: CGRect) -> Bool {
        rect.width >= Self.minSide && rect.height >= Self.minSide
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if let rect = selection {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
            drawLabel("\(Int(rect.width)) × \(Int(rect.height)) pt",
                      at: CGPoint(x: rect.minX, y: min(rect.maxY + 6, bounds.maxY - 28)))
        }
        let text = hint ?? "Drag over the scrollable area, then press Return  ·  Esc to cancel"
        let size = (text as NSString).size(withAttributes: Self.attributes)
        drawLabel(text, at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 80))
    }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private func drawLabel(_ text: String, at point: CGPoint) {
        let size = (text as NSString).size(withAttributes: Self.attributes)
        let box = CGRect(x: point.x, y: point.y, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 8, y: box.minY + 4), withAttributes: Self.attributes)
    }
}

/// Thin click-through frame drawn just outside the region while capturing.
final class RegionBorderWindow: NSWindow {
    init(around rect: CGRect) {
        super.init(contentRect: rect.insetBy(dx: -4, dy: -4), styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = BorderView()
    }

    private final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 3
            path.setLineDash([8, 4], count: 2, phase: 0)
            path.stroke()
        }
    }
}

/// Observable state for the floating capture pill.
final class HUDModel: ObservableObject {
    @Published var frames = 0
    @Published var manual = false
    @Published var message: String?
    @Published var symbol = "checkmark.circle.fill"
    @Published var resultURL: URL?
    var onStop: () -> Void = {}
}

/// Small pill that shows progress with a Stop button, then the result.
struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            if let message = model.message {
                Image(systemName: model.symbol)
                Text(message).lineLimit(2)
                if let url = model.resultURL {
                    Button("Open") { NSWorkspace.shared.open(url) }
                }
            } else {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(model.manual ? "Scroll by hand…" : "Auto-scrolling…")
                Text("\(model.frames) frame\(model.frames == 1 ? "" : "s")").monospacedDigit().foregroundStyle(.secondary)
                Button("Stop") { model.onStop() }.keyboardShortcut(.cancelAction)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Non-activating floating panel that hosts `HUDView` near the top of a screen.
final class HUDPanel: NSPanel {
    init(model: HUDModel) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 560, height: 64),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: HUDView(model: model))
    }

    func show(on screen: NSScreen) {
        let visible = screen.visibleFrame
        setFrameOrigin(CGPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 8))
        orderFrontRegardless()
    }
}
