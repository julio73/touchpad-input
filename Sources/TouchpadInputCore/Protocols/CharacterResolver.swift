// Sources/TouchpadInputCore/Protocols/CharacterResolver.swift

/// Converts a zone ID + pressure into a character to emit.
public protocol CharacterResolver: Sendable {
    /// Returns the character for the given zone and pressure level, or nil if no character should be emitted.
    func character(forZoneID id: String, pressure: Float,
                   modifiers: Set<AnyModifierKind>, pressureFloor: Float) -> Character?
}
