import AppKit
import SwiftUI

enum CaptureMode { case auto, manual }

/// Runs a capture session: permissions, region selection, frame grabbing, scrolling, stitching and saving.
@MainActor
final class CaptureController: ObservableObject {
    static let shared = CaptureController()

    static let maxAutoFrames = 40
    static let maxManualFrames = 300
    static let manualInterval: UInt64 = 300_000_000

    @Published private(set) var isRunning = false
    private let hud = HUDModel()
    private lazy var hudPanel = HUDPanel(model: hud)
    private var selector: RegionSelector?
    private var border: RegionBorderWindow?
    private var stopRequested = false
    private var keyMonitors: [Any] = []
    private var hudToken = 0

    private init() {
        hud.onStop = { [weak self] in self?.stop() }
        HotKeyCenter.shared.onPress = { [weak self] in self?.start(mode: .auto) }
        HotKeyCenter.shared.registerFromDefaults()
    }

    func start(mode: CaptureMode) {
        guard !isRunning, selector == nil else { return }
        guard Permissions.ensureScreenRecording() else { return }
        if mode == .auto, !Permissions.ensureAccessibility() { return }
        let selector = RegionSelector { [weak self] selection in
            guard let self else { return }
            self.selector = nil
            guard let selection else { return }
            Task { await self.run(mode: mode, selection: selection) }
        }
        self.selector = selector
        selector.begin()
    }

    func stop() { stopRequested = true }

    private func run(mode: CaptureMode, selection: Selection) async {
        isRunning = true
        stopRequested = false
        beginChrome(mode: mode, selection: selection)
        defer {
            endChrome()
            isRunning = false
        }

        let prefs = Prefs()
        let rect = selection.rect
        let scale = selection.screen.backingScaleFactor
        let stitcher = Stitcher(headerPx: Int(prefs.trimHeader * scale), footerPx: Int(prefs.trimFooter * scale))
        do {
            let grabber = try await FrameGrabber(rect: rect, screen: selection.screen)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if mode == .auto { Scroller.moveCursor(to: center) }
            _ = stitcher.add(try await grabber.capture(), expectedShift: nil)
            hud.frames = stitcher.frameCount

            if mode == .auto {
                let step = prefs.scrollStep > 0 ? CGFloat(prefs.scrollStep) : rect.height * 0.7
                let delay = UInt64(prefs.stepDelayMs * 1_000_000)
                while !stopRequested, stitcher.frameCount < Self.maxAutoFrames {
                    Scroller.scrollDown(points: step, at: center)
                    try await Task.sleep(nanoseconds: delay)
                    if stopRequested { break }
                    let result = stitcher.add(try await grabber.capture(), expectedShift: Int(step * scale))
                    if result == .identical { break } // bottom reached
                    hud.frames = stitcher.frameCount
                }
            } else {
                while !stopRequested, stitcher.frameCount < Self.maxManualFrames {
                    try await Task.sleep(nanoseconds: Self.manualInterval)
                    if stopRequested { break }
                    _ = stitcher.add(try await grabber.capture(), expectedShift: nil)
                    hud.frames = stitcher.frameCount
                }
            }
            try finish(stitcher, prefs: prefs)
        } catch {
            showResult("Capture failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill", url: nil)
        }
    }

    private func finish(_ stitcher: Stitcher, prefs: Prefs) throws {
        border?.orderOut(nil)
        let images = stitcher.render()
        guard let first = images.first else { throw CaptureError.nothingCaptured }
        let urls = try Saver.save(images, to: prefs.saveFolder)
        UserDefaults.standard.set(urls.first?.path ?? "", forKey: Keys.lastCapturePath)

        if prefs.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(images.map { NSImage(cgImage: $0, size: .zero) })
        }
        if prefs.playSound { NSSound(named: "Glass")?.play() }

        let totalHeight = images.reduce(0) { $0 + $1.height }
        var message = images.count == 1
            ? "Saved \(first.width) × \(totalHeight) px from \(stitcher.frameCount) frames"
            : "Saved \(images.count) files (\(totalHeight) px tall)"
        if stitcher.possiblyMisaligned { message += " · possibly misaligned" }
        showResult(message, symbol: stitcher.possiblyMisaligned ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                   url: urls.first)
    }

    // MARK: - On-screen chrome

    private func beginChrome(mode: CaptureMode, selection: Selection) {
        hudToken += 1
        hud.message = nil
        hud.resultURL = nil
        hud.frames = 0
        hud.manual = mode == .manual
        hudPanel.show(on: selection.screen)
        border = RegionBorderWindow(around: selection.rect)
        border?.orderFrontRegardless()

        let escape: (NSEvent) -> Void = { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.stop() } }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: escape) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { escape($0); return $0 }) {
            keyMonitors.append(local)
        }
    }

    private func endChrome() {
        border?.orderOut(nil)
        border = nil
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
    }

    private func showResult(_ message: String, symbol: String, url: URL?) {
        hud.message = message
        hud.symbol = symbol
        hud.resultURL = url
        hudToken += 1
        let token = hudToken
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if token == hudToken { hudPanel.orderOut(nil) }
        }
    }
}
