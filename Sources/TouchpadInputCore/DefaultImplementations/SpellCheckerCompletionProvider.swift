// Sources/TouchpadInputCore/DefaultImplementations/SpellCheckerCompletionProvider.swift
import AppKit

/// Uses NSSpellChecker to generate word completions for partial input.
public struct SpellCheckerCompletionProvider: CompletionProvider, @unchecked Sendable {
    public init() {}

    public func completions(forPartial partial: String, maxCount: Int) -> [String] {
        guard !partial.isEmpty else { return [] }
        let range = NSRange(location: 0, length: (partial as NSString).length)
        let all: [String] = NSSpellChecker.shared.completions(
            forPartialWordRange: range,
            in: partial,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []
        return Array(all.prefix(maxCount))
    }
}
