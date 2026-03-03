// Sources/TouchpadInputCore/DefaultImplementations/MultiOutputTarget.swift

/// Fan-out OutputTarget that forwards all events to multiple targets.
@MainActor
public final class MultiOutputTarget: OutputTarget {
    private let targets: [any OutputTarget]

    public init(_ targets: [any OutputTarget]) { self.targets = targets }

    public func emit(character: Character) {
        targets.forEach { $0.emit(character: character) }
    }

    public func deleteLastCharacter() {
        targets.forEach { $0.deleteLastCharacter() }
    }

    public func clear() {
        targets.forEach { $0.clear() }
    }
}
