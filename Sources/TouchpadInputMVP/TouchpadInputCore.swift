import AppKit
import SwiftUI

// MARK: - Data Model

struct FingerState: Identifiable {
    let id: String           // raw NSTouch identity string
    let label: String        // short display label: #1, #2, …
    let x: CGFloat           // normalized trackpad position, 0…1
    let y: CGFloat           // normalized trackpad position, 0…1
    let pressure: CGFloat
    let phase: String
    let lastEventTime: TimeInterval
    let deltaMsFromPrev: Int?
}

struct TouchLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let fingerLabel: String
    let phase: String
    let x: CGFloat
    let y: CGFloat
    let pressure: CGFloat
    let deltaMs: Int?        // nil for first event from a finger
}

final class TouchDiagnosticSession: ObservableObject {
    @Published var liveFingers: [FingerState] = []
    @Published var eventLog: [TouchLogEntry] = []
    @Published var livePressure: CGFloat = 0

    private var fingerLabels: [String: String] = [:]
    private var fingerLastTime: [String: TimeInterval] = [:]
    private var labelCounter = 0
    private let maxLogEntries = 500

    func update(touches: [NSTouch], timestamp: TimeInterval) {
        var liveLookup: [String: FingerState] = Dictionary(
            uniqueKeysWithValues: liveFingers.map { ($0.id, $0) }
        )

        for touch in touches {
            let rawID = String(describing: touch.identity)

            if fingerLabels[rawID] == nil {
                labelCounter += 1
                fingerLabels[rawID] = "#\(labelCounter)"
            }
            let label = fingerLabels[rawID]!

            let deltaMs: Int?
            if let prev = fingerLastTime[rawID] {
                deltaMs = max(0, Int((timestamp - prev) * 1000))
            } else {
                deltaMs = nil
            }

            let x = touch.normalizedPosition.x
            let y = touch.normalizedPosition.y
            let phaseStr = phaseString(touch.phase)

            // Skip logging stationary events — too noisy; live table still shows them
            if touch.phase != .stationary {
                appendLog(TouchLogEntry(
                    timestamp: Date(),
                    fingerLabel: label,
                    phase: phaseStr,
                    x: x,
                    y: y,
                    pressure: livePressure,
                    deltaMs: deltaMs
                ))
            }

            if touch.phase == .ended || touch.phase == .cancelled {
                liveLookup.removeValue(forKey: rawID)
                fingerLastTime.removeValue(forKey: rawID)
            } else {
                fingerLastTime[rawID] = timestamp
                liveLookup[rawID] = FingerState(
                    id: rawID,
                    label: label,
                    x: x,
                    y: y,
                    pressure: livePressure,
                    phase: phaseStr,
                    lastEventTime: timestamp,
                    deltaMsFromPrev: deltaMs
                )
            }
        }

        liveFingers = Array(liveLookup.values).sorted { $0.label < $1.label }
    }

    func updatePressure(_ pressure: CGFloat) {
        livePressure = pressure
    }

    func clearAll() {
        eventLog = []
        liveFingers = []
        fingerLabels = [:]
        fingerLastTime = [:]
        labelCounter = 0
        livePressure = 0
    }

    private func appendLog(_ entry: TouchLogEntry) {
        eventLog.append(entry)
        if eventLog.count > maxLogEntries {
            eventLog.removeFirst(eventLog.count - maxLogEntries)
        }
    }

    private func phaseString(_ phase: NSTouch.Phase) -> String {
        switch phase {
        case .began:      return "began"
        case .moved:      return "moved"
        case .stationary: return "stationary"
        case .ended:      return "ended"
        case .cancelled:  return "cancelled"
        default:          return "unknown"
        }
    }
}

// MARK: - SwiftUI Views

#if canImport(SwiftUI)

struct ContentView: View {
    @StateObject private var session = TouchDiagnosticSession()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                trackpadPanel
                Divider()
                FingerTablePanel(fingers: session.liveFingers, pressure: session.livePressure)
                    .frame(width: 340)
            }
            Divider()
            EventLogPanel(entries: session.eventLog)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Touchpad Diagnostics")
                .font(.system(size: 18, weight: .semibold))
            Text("Phase 1 — Raw Signal")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(6)
            Spacer()
            Button("Clear") { session.clearAll() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var trackpadPanel: some View {
        ZStack {
            TrackpadSurface(fingers: session.liveFingers)
            TouchCaptureRepresentable(session: session)
        }
        .padding(16)
    }
}

// MARK: - Trackpad Surface

struct TrackpadSurface: View {
    let fingers: [FingerState]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)

                if fingers.isEmpty {
                    Text("Place fingers on trackpad")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                ForEach(fingers) { finger in
                    // trackpad y=0 is bottom; SwiftUI y=0 is top, so flip
                    let x = finger.x * geo.size.width
                    let y = (1.0 - finger.y) * geo.size.height
                    ZStack {
                        Circle()
                            .fill(dotColor(finger.phase).opacity(0.75))
                            .frame(width: 38, height: 38)
                        Text(finger.label)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .position(x: x, y: y)
                }
            }
        }
    }

    private func dotColor(_ phase: String) -> Color {
        switch phase {
        case "began": return .green
        case "ended": return .red
        default:      return .blue
        }
    }
}

// MARK: - Finger Table Panel

struct FingerTablePanel: View {
    let fingers: [FingerState]
    let pressure: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Live Fingers")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            columnHeaders
            Divider()
            fingerRows

            Spacer()
            Divider()

            HStack(spacing: 6) {
                Text("Pressure")
                    .foregroundColor(.secondary)
                Text(String(format: "%.3f", pressure))
                    .foregroundColor(pressure > 0.5 ? .orange : .primary)
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(16)
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("ID")   .frame(width: 36,  alignment: .leading)
            Text("X")    .frame(width: 88,  alignment: .trailing)
            Text("Y")    .frame(width: 88,  alignment: .trailing)
            Text("P")    .frame(width: 52,  alignment: .trailing)
            Text("Phase").frame(width: 72,  alignment: .leading).padding(.leading, 12)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var fingerRows: some View {
        if fingers.isEmpty {
            Text("— no active touches")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        } else {
            ForEach(fingers) { f in
                HStack(spacing: 0) {
                    Text(f.label)
                        .frame(width: 36, alignment: .leading)
                    Text(String(format: "%.5f", f.x))
                        .frame(width: 88, alignment: .trailing)
                    Text(String(format: "%.5f", f.y))
                        .frame(width: 88, alignment: .trailing)
                    Text(String(format: "%.2f", f.pressure))
                        .frame(width: 52, alignment: .trailing)
                    Text(f.phase)
                        .frame(width: 72, alignment: .leading)
                        .padding(.leading, 12)
                        .foregroundColor(phaseColor(f.phase))
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "began": return .green
        case "ended": return .red
        case "moved": return .blue
        default:      return .primary
        }
    }
}

// MARK: - Event Log Panel

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

// MARK: - Touch Capture NSView Bridge

struct TouchCaptureRepresentable: NSViewRepresentable {
    let session: TouchDiagnosticSession

    func makeNSView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: TouchCaptureView, context: Context) {
        nsView.session = session
    }
}

#endif // canImport(SwiftUI)

// MARK: - Touch Capture NSView

final class TouchCaptureView: NSView {
    weak var session: TouchDiagnosticSession?
    private var pressureObserver: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        if let obs = pressureObserver { NSEvent.removeMonitor(obs) }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        allowedTouchTypes = [.indirect]   // trackpad only

        pressureObserver = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] event in
            self?.session?.updatePressure(CGFloat(event.pressure))
            return event
        }
    }

    override func touchesBegan(with event: NSEvent)     { processEvent(event) }
    override func touchesMoved(with event: NSEvent)     { processEvent(event) }
    override func touchesEnded(with event: NSEvent)     { processEvent(event) }
    override func touchesCancelled(with event: NSEvent) { processEvent(event) }

    private func processEvent(_ event: NSEvent) {
        let allPhases: NSTouch.Phase = [.touching, .ended, .cancelled]
        let touches = Array(event.touches(matching: allPhases, in: self))
        session?.update(touches: touches, timestamp: event.timestamp)
    }
}
