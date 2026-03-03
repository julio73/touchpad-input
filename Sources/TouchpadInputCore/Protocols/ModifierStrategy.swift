// Sources/TouchpadInputCore/Protocols/ModifierStrategy.swift

/// Type-erased modifier kind. Built-in values are `.shift` and `.delete`;
/// third-party plugins may define additional kinds via custom `rawValue` strings.
public struct AnyModifierKind: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let shift  = AnyModifierKind(rawValue: "shift")
    public static let delete = AnyModifierKind(rawValue: "delete")
}

/// Maps touch positions to modifier actions (e.g. hold-to-shift, hold-to-delete).
public protocol ModifierStrategy: Sendable {
    /// Returns the modifier kind active at the given normalized position, or nil.
    func modifierKind(at x: Float, y: Float) -> AnyModifierKind?
    /// Human-readable labels for modifier zones (used by the UI overlay).
    var zoneLabels: [AnyModifierKind: String] { get }
}
