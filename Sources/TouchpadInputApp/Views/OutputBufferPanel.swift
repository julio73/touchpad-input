import SwiftUI
import TouchpadInputCore

struct OutputBufferPanel: View {
    let text: String
    var activeModifiers: Set<AnyModifierKind> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Output")
                    .font(.headline)
                if activeModifiers.contains(.shift) {
                    Text("⇧ SHIFT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 4))
                }
                if activeModifiers.contains(.delete) {
                    Text("⌫ DEL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text.isEmpty ? "Start typing…" : text)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(text.isEmpty ? .secondary : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 80)
        .background(Color(NSColor.textBackgroundColor))
    }
}
