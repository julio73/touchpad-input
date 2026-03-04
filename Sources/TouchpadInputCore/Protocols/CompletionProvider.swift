// Sources/TouchpadInputCore/Protocols/CompletionProvider.swift

/// Provides word completions for a partial string (e.g. autocomplete suggestions).
public protocol CompletionProvider: Sendable {
    func completions(forPartial partial: String, maxCount: Int) -> [String]
}
