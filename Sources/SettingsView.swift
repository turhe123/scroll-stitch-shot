import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window: hotkey, output, scrolling and trimming options, launch at login and support.
struct SettingsView: View {
    @AppStorage(Keys.saveFolder) private var saveFolder = ""
    @AppStorage(Keys.scrollStep) private var scrollStep = 0.0
    @AppStorage(Keys.stepDelayMs) private var stepDelayMs = 250.0
    @AppStorage(Keys.trimHeader) private var trimHeader = 0.0
    @AppStorage(Keys.trimFooter) private var trimFooter = 0.0
    @AppStorage(Keys.copyToClipboard) private var copyToClipboard = true
    @AppStorage(Keys.playSound) private var playSound = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Capture hotkey") { HotKeyRecorder() }
            }
            Section("Output") {
                LabeledContent("Save folder") {
                    HStack {
                        Text(Saver.folder(saveFolder).path)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Toggle("Copy to clipboard", isOn: $copyToClipboard)
                Toggle("Play sound when done", isOn: $playSound)
            }
            Section("Auto-scroll") {
                TextField("Scroll step (pt, 0 = 70% of region)", value: $scrollStep, format: .number)
                TextField("Delay between steps (ms)", value: $stepDelayMs, format: .number)
            }
            Section {
                TextField("Trim fixed header (pt)", value: $trimHeader, format: .number)
                TextField("Trim fixed footer (pt)", value: $trimFooter, format: .number)
            } header: {
                Text("Sticky Header & Footer")
            } footer: {
                Text("Cropped from repeated frames so sticky bars appear only once.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = Saver.folder(saveFolder)
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url.path }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control for the global hotkey; requires at least one of ⌘, ⌃ or ⌥.
struct HotKeyRecorder: View {
    @AppStorage(Keys.hotKeyCode) private var keyCode = Prefs.defaultHotKeyCode
    @AppStorage(Keys.hotKeyModifiers) private var modifiers = Prefs.defaultHotKeyModifiers
    @AppStorage(Keys.hotKeyLabel) private var label = Prefs.defaultHotKeyLabel
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut… (Esc to cancel)" : label) {
            recording ? stopRecording() : startRecording()
        }
        .monospacedDigit()
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recording = true
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 {
                stopRecording()
            } else if flags.isDisjoint(with: [.command, .control, .option]) {
                NSSound.beep()
            } else {
                keyCode = Int(event.keyCode)
                modifiers = Int(HotKeyCenter.carbonModifiers(flags))
                label = HotKeyCenter.label(flags, key: event.charactersIgnoringModifiers ?? "?")
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyCenter.shared.register(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }
}
