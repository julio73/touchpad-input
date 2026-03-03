import SwiftUI
import TouchpadInputCore

struct EventLogPanel: View {
    let entries: [TouchLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Event Log")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) events")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { entry in
                            EventLogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .onChange(of: entries.count) { _ in
                    if let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(height: 190)
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct EventLogRow: View {
    let entry: TouchLogEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(formattedTime)
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(entry.phase)
                .foregroundColor(phaseColor)
                .frame(width: 65, alignment: .leading)
            Text(entry.fingerLabel)
                .frame(width: 28, alignment: .leading)
            Text(String(format: "x=%.5f", entry.x))
                .frame(width: 98, alignment: .leading)
            Text(String(format: "y=%.5f", entry.y))
                .frame(width: 98, alignment: .leading)
            Text(String(format: "p=%.2f", entry.pressure))
                .frame(width: 55, alignment: .leading)
            if entry.rawState >= 0 {
                Text("s\(entry.rawState)")
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .leading)
            }
            if let delta = entry.deltaMs {
                Text("Δ\(delta)ms")
                    .foregroundColor(.orange)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
    }

    private var formattedTime: String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: entry.timestamp)
        let ms = (comps.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d",
            comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0, ms)
    }

    private var phaseColor: Color {
        switch entry.phase {
        case "began":     return .green
        case "ended":     return .red
        case "moved":     return .blue
        case "cancelled": return .orange
        default:          return .primary
        }
    }
}
