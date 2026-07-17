import AppKit
import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon's RegisterEventHotKey — works without the
/// Accessibility permission, unlike NSEvent global monitors.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32 = 0, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x5645_5253), id: id) // 'VERS'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }
}

/// Parses Electron accelerator strings ("F9", "Alt+Space", "Control+Shift+D")
/// into Carbon key code + modifier flags, so settings.json keeps working.
enum Accelerator {
    static func parse(_ accelerator: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        var modifiers: UInt32 = 0
        var key: String?
        for part in accelerator.split(separator: "+").map(String.init) {
            switch part.lowercased() {
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "alt", "option": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "command", "cmd", "super", "meta": modifiers |= UInt32(cmdKey)
            default: key = part
            }
        }
        guard let key, let keyCode = keyCode(for: key) else { return nil }
        return (keyCode, modifiers)
    }

    static func label(_ accelerator: String) -> String {
        accelerator
            .replacingOccurrences(of: "Control", with: "⌃")
            .replacingOccurrences(of: "Alt", with: "⌥")
            .replacingOccurrences(of: "Shift", with: "⇧")
            .replacingOccurrences(of: "Command", with: "⌘")
            .replacingOccurrences(of: "+", with: "")
    }

    /// Builds an Electron-format accelerator from a key event, for the
    /// shortcut recorder in Settings. Returns nil for unusable combos
    /// (plain letters without a modifier, unknown keys).
    static func string(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String? {
        guard let name = keyName(for: Int(keyCode)) else { return nil }
        var parts: [String] = []
        if flags.contains(.control) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        if flags.contains(.command) { parts.append("Command") }

        let isFunctionKey = name.hasPrefix("F") && name.count > 1
        if parts.isEmpty && !isFunctionKey { return nil }
        parts.append(name)
        return parts.joined(separator: "+")
    }

    /// NSMenuItem key-equivalent representation, for right-aligned shortcut
    /// display in the status item menu.
    static func keyEquivalent(_ accelerator: String) -> (String, NSEvent.ModifierFlags)? {
        var mask: NSEvent.ModifierFlags = []
        var key: String?
        for part in accelerator.split(separator: "+").map(String.init) {
            switch part.lowercased() {
            case "control", "ctrl": mask.insert(.control)
            case "alt", "option": mask.insert(.option)
            case "shift": mask.insert(.shift)
            case "command", "cmd", "super", "meta": mask.insert(.command)
            default: key = part
            }
        }
        guard let key else { return nil }

        let upper = key.uppercased()
        if upper.hasPrefix("F"), let number = Int(upper.dropFirst()),
           (1...12).contains(number),
           let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) {
            mask.insert(.function)
            return (String(scalar), mask)
        }
        switch key.lowercased() {
        case "space": return (" ", mask)
        case "return", "enter": return ("\r", mask)
        default: break
        }
        if key.count == 1 {
            return (key.lowercased(), mask)
        }
        return nil
    }

    private static let namedKeys: [String: Int] = [
        "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4,
        "F5": kVK_F5, "F6": kVK_F6, "F7": kVK_F7, "F8": kVK_F8,
        "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
        "Space": kVK_Space, "Escape": kVK_Escape, "Return": kVK_Return,
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
        "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
        "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
        "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
        "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    private static func keyName(for keyCode: Int) -> String? {
        namedKeys.first { $0.value == keyCode }?.key
    }

    private static func keyCode(for key: String) -> UInt32? {
        let normalized: String
        switch key.lowercased() {
        case "space": normalized = "Space"
        case "escape", "esc": normalized = "Escape"
        case "return", "enter": normalized = "Return"
        default: normalized = key.uppercased()
        }
        guard let code = namedKeys[normalized] else { return nil }
        return UInt32(code)
    }
}
