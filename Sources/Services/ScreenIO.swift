import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay, nothingCaptured, encodeFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Couldn't find the display for this region."
        case .nothingCaptured: return "Nothing was captured."
        case .encodeFailed: return "Couldn't encode the PNG."
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Captures one region of one display with ScreenCaptureKit, excluding this app's own windows.
struct FrameGrabber {
    private let filter: SCContentFilter
    private let config: SCStreamConfiguration

    /// `rect` is in global AppKit coordinates (bottom-left origin) and must lie on `screen`.
    init(rect: CGRect, screen: NSScreen) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
            throw CaptureError.noDisplay
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
        config.width = Int((rect.width * scale).rounded())
        config.height = Int((rect.height * scale).rounded())
        config.showsCursor = false
        self.config = config
    }

    func capture() async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// Posts synthetic scroll-wheel events (requires Accessibility permission).
enum Scroller {
    /// Converts a global AppKit point to the Quartz global space (top-left origin of the primary display).
    static func quartzPoint(_ p: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func moveCursor(to p: CGPoint) {
        CGWarpMouseCursorPosition(quartzPoint(p))
    }

    /// Scrolls content down by `points`, split into small pixel-unit wheel events at `p`.
    static func scrollDown(points: CGFloat, at p: CGPoint) {
        let location = quartzPoint(p)
        var remaining = Int32(points.rounded())
        while remaining > 0 {
            let chunk = min(remaining, 40)
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                   wheel1: -chunk, wheel2: 0, wheel3: 0) {
                event.location = location
                event.post(tap: .cghidEventTap)
            }
            remaining -= chunk
        }
    }
}

/// Writes stitched images as PNG files, falling back to the Desktop if the chosen folder is missing.
enum Saver {
    static func folder(_ path: String) -> URL {
        var isDir: ObjCBool = false
        if !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    static func save(_ images: [CGImage], to folderPath: String) throws -> [URL] {
        let folder = folder(folderPath)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "ScrollStitch \(formatter.string(from: Date()))"
        var urls: [URL] = []
        for (index, image) in images.enumerated() {
            let suffix = images.count > 1 ? " (part \(index + 1) of \(images.count))" : ""
            let url = folder.appendingPathComponent(base + suffix).appendingPathExtension("png")
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CaptureError.encodeFailed
            }
            try data.write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }
}
