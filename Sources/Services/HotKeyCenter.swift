import AppKit
import Carbon

/// Registers the single global hotkey with the Carbon Event Manager and forwards presses to `onPress`.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func registerFromDefaults() {
        let defaults = UserDefaults.standard
        register(keyCode: UInt32(defaults.integer(forKey: Keys.hotKeyCode)),
                 modifiers: UInt32(defaults.integer(forKey: Keys.hotKeyModifiers)))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyCenter.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        let id = EventHotKeyID(signature: OSType(0x5353_5348), id: 1) // "SSSH"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Converts AppKit modifier flags into Carbon modifier bits.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        return UInt32(result)
    }

    /// Human-readable label such as "⌃⇧S".
    static func label(_ flags: NSEvent.ModifierFlags, key: String) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }
}
