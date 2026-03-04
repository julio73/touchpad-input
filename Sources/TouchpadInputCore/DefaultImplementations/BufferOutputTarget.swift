// Sources/TouchpadInputCore/DefaultImplementations/BufferOutputTarget.swift
import Foundation
import Combine

/// In-memory string buffer that accumulates emitted characters.
/// Useful for in-app display or third-party integrations that read the buffer reactively.
@MainActor
public final class BufferOutputTarget: OutputTarget, ObservableObject {
    @Published public var buffer: String = ""

    public init() {}

    public func emit(character: Character) { buffer.append(character) }
    public func deleteLastCharacter() { if !buffer.isEmpty { buffer.removeLast() } }
    public func clear() { buffer = "" }
}
