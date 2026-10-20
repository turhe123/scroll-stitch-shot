import AppKit
import ApplicationServices
import CoreGraphics

/// Checks Screen Recording and Accessibility permissions and guides the user to System Settings when missing.
enum Permissions {
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let proceed = explain(
            title: "Screen Recording Permission Needed",
            message: "ScrollStitchShot needs Screen Recording access to capture the region you select. Everything stays on your Mac.\n\nEnable ScrollStitchShot in System Settings › Privacy & Security › Screen Recording, then relaunch the app.")
        if proceed {
            if CGRequestScreenCaptureAccess() { return true }
            openPane("Privacy_ScreenCapture")
        }
        return false
    }

    static func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        let proceed = explain(
            title: "Accessibility Permission Needed",
            message: "Automatic mode scrolls the page for you by sending scroll-wheel events, which requires Accessibility access.\n\nEnable ScrollStitchShot in System Settings › Privacy & Security › Accessibility. (Manual mode works without it.)")
        if proceed {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if AXIsProcessTrustedWithOptions(options) { return true }
            openPane("Privacy_Accessibility")
        }
        return false
    }

    /// Shows a friendly explanation; returns true if the user chose to open System Settings.
    private static func explain(title: String, message: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func openPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
