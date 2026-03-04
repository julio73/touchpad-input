// Sources/TouchpadInputCore/Protocols/OutputTarget.swift

/// Receives emitted characters from a touch input session.
/// Built-ins: `BufferOutputTarget` (in-app buffer), `CGEventOutputTarget` (system-wide injection).
@MainActor
public protocol OutputTarget: AnyObject {
    func emit(character: Character)
    func deleteLastCharacter()
    func clear()
}
