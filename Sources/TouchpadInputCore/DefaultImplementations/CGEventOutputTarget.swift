// Sources/TouchpadInputCore/DefaultImplementations/CGEventOutputTarget.swift
import AppKit
import CoreGraphics

/// Injects characters into the frontmost app via CGEvent keyboard events.
/// Requires Accessibility permission — call `requestAccessibilityPermission()` at launch.
///
/// **v1 limitation:** keycode table covers US QWERTY only.
/// v2 will use `TISCopyCurrentKeyboardInputSource` to build a runtime map.
@MainActor
public final class CGEventOutputTarget: OutputTarget {
    public init() {}

    // MARK: OutputTarget

    public func emit(character: Character) {
        guard AXIsProcessTrusted() else { return }
        guard let (keyCode, flags) = Self.keyCode(for: character) else { return }
        Self.post(keyCode: keyCode, flags: flags, keyDown: true)
        Self.post(keyCode: keyCode, flags: flags, keyDown: false)
    }

    public func deleteLastCharacter() {
        guard AXIsProcessTrusted() else { return }
        Self.post(keyCode: 51, flags: [], keyDown: true)   // 51 = Backspace
        Self.post(keyCode: 51, flags: [], keyDown: false)
    }

    public func clear() {}   // no-op; can't clear an external app safely

    // MARK: Accessibility permission

    /// Prompts the user for Accessibility permission if not already granted.
    /// Returns true if permission is currently granted.
    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        // Use the string literal directly to avoid Swift 6 shared-mutable-state warning
        // on kAXTrustedCheckOptionPrompt (a C global). The value is stable and well-documented.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Private helpers

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags, keyDown: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func keyCode(for character: Character) -> (CGKeyCode, CGEventFlags)? {
        keyCodes[character]
    }

    // US QWERTY keycode table.
    private static let keyCodes: [Character: (CGKeyCode, CGEventFlags)] = [
        // Lowercase letters
        "a": (0, []), "b": (11, []), "c": (8, []), "d": (2, []), "e": (14, []),
        "f": (3, []), "g": (5, []), "h": (4, []), "i": (34, []), "j": (38, []),
        "k": (40, []), "l": (37, []), "m": (46, []), "n": (45, []), "o": (31, []),
        "p": (35, []), "q": (12, []), "r": (15, []), "s": (1, []), "t": (17, []),
        "u": (32, []), "v": (9, []), "w": (13, []), "x": (7, []), "y": (16, []),
        "z": (6, []),
        // Uppercase letters
        "A": (0, .maskShift), "B": (11, .maskShift), "C": (8, .maskShift), "D": (2, .maskShift),
        "E": (14, .maskShift), "F": (3, .maskShift), "G": (5, .maskShift), "H": (4, .maskShift),
        "I": (34, .maskShift), "J": (38, .maskShift), "K": (40, .maskShift), "L": (37, .maskShift),
        "M": (46, .maskShift), "N": (45, .maskShift), "O": (31, .maskShift), "P": (35, .maskShift),
        "Q": (12, .maskShift), "R": (15, .maskShift), "S": (1, .maskShift), "T": (17, .maskShift),
        "U": (32, .maskShift), "V": (9, .maskShift), "W": (13, .maskShift), "X": (7, .maskShift),
        "Y": (16, .maskShift), "Z": (6, .maskShift),
        // Digits
        "0": (29, []), "1": (18, []), "2": (19, []), "3": (20, []), "4": (21, []),
        "5": (23, []), "6": (22, []), "7": (26, []), "8": (28, []), "9": (25, []),
        // Common symbols
        " ": (49, []), "\n": (36, []),
        "-": (27, []), "=": (24, []), "[": (33, []), "]": (30, []),
        ";": (41, []), "'": (39, []), "`": (50, []), ",": (43, []), ".": (47, []), "/": (44, []),
        // Shifted symbols
        "!": (18, .maskShift), "@": (19, .maskShift), "#": (20, .maskShift), "$": (21, .maskShift),
        "%": (23, .maskShift), "^": (22, .maskShift), "&": (26, .maskShift), "*": (28, .maskShift),
        "(": (25, .maskShift), ")": (29, .maskShift),
        "_": (27, .maskShift), "+": (24, .maskShift), "{": (33, .maskShift), "}": (30, .maskShift),
    ]
}
