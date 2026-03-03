import SwiftUI

struct AutocompleteBar: View {
    let completions: [String]
    let onAccept: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Suggestions:")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            ForEach(Array(completions.enumerated()), id: \.offset) { _, word in
                Button(word) { onAccept(word) }
                    .buttonStyle(.bordered)
                    .font(.system(size: 12))
            }
            Spacer()
            Text("2-finger tap to accept first")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
