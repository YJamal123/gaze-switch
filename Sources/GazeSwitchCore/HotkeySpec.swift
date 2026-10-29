import Foundation

/// A global shortcut such as "ctrl+option+cmd+g", in Carbon key code and modifier terms.
public struct HotkeySpec: Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    // Carbon modifier masks (cmdKey, shiftKey, optionKey, controlKey).
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Needs at least one modifier and exactly one key.
    public static func parse(_ text: String) -> HotkeySpec? {
        var modifiers: UInt32 = 0
        var key: UInt32?
        for part in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command", "⌘": modifiers |= command
            case "shift", "⇧": modifiers |= shift
            case "opt", "option", "alt", "⌥": modifiers |= option
            case "ctrl", "control", "⌃": modifiers |= control
            default:
                guard key == nil, let code = keyCodes[part] else { return nil }
                key = code
            }
        }
        guard let key, modifiers != 0 else { return nil }
        return HotkeySpec(keyCode: key, modifiers: modifiers)
    }

    /// ANSI keyboard virtual key codes.
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
