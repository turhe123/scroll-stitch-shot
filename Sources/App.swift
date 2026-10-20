import SwiftUI

/// Entry point: a menu-bar-only app with a MenuBarExtra and a Settings window.
@main
struct ScrollStitchShotApp: App {
    @StateObject private var controller = CaptureController.shared

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra("ScrollStitchShot", systemImage: "arrow.down.doc") {
            MenuContent(controller: controller)
        }
        Settings {
            SettingsView()
        }
    }
}

/// The items shown in the menu bar dropdown.
struct MenuContent: View {
    @ObservedObject var controller: CaptureController
    @AppStorage(Keys.lastCapturePath) private var lastCapturePath = ""
    @AppStorage(Keys.hotKeyLabel) private var hotKeyLabel = Prefs.defaultHotKeyLabel

    var body: some View {
        Button("Capture Scrolling Region (\(hotKeyLabel))") { controller.start(mode: .auto) }
            .disabled(controller.isRunning)
        Button("Capture Manually (Scroll by Hand)") { controller.start(mode: .manual) }
            .disabled(controller.isRunning)
        Divider()
        if lastCapturePath.isEmpty {
            Text("No recent captures yet")
        } else {
            Button("Open Last Capture") { openLastCapture() }
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Support / Donate ❤️") {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
        }
        Divider()
        Button("Quit ScrollStitchShot") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openLastCapture() {
        let url = URL(fileURLWithPath: lastCapturePath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSSound.beep()
            lastCapturePath = ""
        }
    }
}
