import Carbon
import Foundation

/// UserDefaults keys shared by `@AppStorage` views and the capture services.
enum Keys {
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyLabel = "hotKeyLabel"
    static let saveFolder = "saveFolder"
    static let scrollStep = "scrollStep"
    static let stepDelayMs = "stepDelayMs"
    static let trimHeader = "trimHeader"
    static let trimFooter = "trimFooter"
    static let copyToClipboard = "copyToClipboard"
    static let playSound = "playSound"
    static let lastCapturePath = "lastCapturePath"
}

/// Typed read access to user preferences, plus their default values.
struct Prefs {
    static let defaultHotKeyCode = kVK_ANSI_8
    static let defaultHotKeyModifiers = cmdKey | shiftKey
    static let defaultHotKeyLabel = "⇧⌘8"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.hotKeyCode: defaultHotKeyCode,
            Keys.hotKeyModifiers: defaultHotKeyModifiers,
            Keys.hotKeyLabel: defaultHotKeyLabel,
            Keys.saveFolder: "",
            Keys.scrollStep: 0.0,
            Keys.stepDelayMs: 250.0,
            Keys.trimHeader: 0.0,
            Keys.trimFooter: 0.0,
            Keys.copyToClipboard: true,
            Keys.playSound: true,
        ])
    }

    private let defaults = UserDefaults.standard

    /// Scroll step in points; 0 means "70% of the region height".
    var scrollStep: Double { max(0, defaults.double(forKey: Keys.scrollStep)) }
    var stepDelayMs: Double { min(5000, max(50, defaults.double(forKey: Keys.stepDelayMs))) }
    var trimHeader: Double { max(0, defaults.double(forKey: Keys.trimHeader)) }
    var trimFooter: Double { max(0, defaults.double(forKey: Keys.trimFooter)) }
    var copyToClipboard: Bool { defaults.bool(forKey: Keys.copyToClipboard) }
    var playSound: Bool { defaults.bool(forKey: Keys.playSound) }
    var saveFolder: String { defaults.string(forKey: Keys.saveFolder) ?? "" }
}
