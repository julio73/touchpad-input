import AppKit
import SwiftUI
import Darwin

// MARK: - MultitouchSupport private framework types
// Layout mirrors the C struct in MultitouchSupport.framework.
// If finger dots appear in wrong positions the struct layout has drifted —
// file an issue and we'll adjust the padding/field order.

struct MTVector { var x, y: Float }
struct MTPoint  { var position, velocity: MTVector }
struct MTContact {
    var frame:          Int32   // offset 0
    var timestamp:      Double  // offset 8  (4 bytes padding after frame)
    var identifier:     Int32   // offset 16 — stable ID for this touch session
    var state:          Int32   // offset 20 — raw hardware state
    var fingerId:       Int32   // offset 24
    var handId:         Int32   // offset 28
    var normalized:     MTPoint // offset 32 — position + velocity, each 0…1
    var size:           Float   // offset 48 — contact area
    var unknown1:       Int32   // offset 52
    var angle:          Float   // offset 56
    var majorAxis:      Float   // offset 60
    var minorAxis:      Float   // offset 64
    var absoluteVector: MTPoint // offset 68
    var unknown2:       (Int32, Int32) // offset 84
    var zDensity:       Float   // offset 92 — pressure-like value
}

// C callback — cannot capture Swift context, routes through the singleton.
// All parameters must be plain C types; use UnsafeRawPointer and rebind inside.
private typealias MTCallbackFn = @convention(c) (
    UnsafeRawPointer?,   // device (unused)
    UnsafeRawPointer?,   // contacts array (rebound to MTContact inside)
    Int32,               // count
    Double,              // timestamp
    Int32                // frame number (unused)
) -> Void

private let mtFrameCallback: MTCallbackFn = { _, rawPtr, count, timestamp, _ in
    guard let rawPtr, count > 0 else { return }
    let n = Int(count)
    let contacts = rawPtr.withMemoryRebound(to: MTContact.self, capacity: n) { ptr in
        Array(UnsafeBufferPointer(start: ptr, count: n))
    }
    DispatchQueue.main.async {
        MultitouchCapture.shared.session?.update(mtContacts: contacts, timestamp: timestamp)
    }
}

// MARK: - MultitouchCapture

final class MultitouchCapture: @unchecked Sendable {
    static let shared = MultitouchCapture()

    nonisolated(unsafe) weak var session: TouchDiagnosticSession?
    private nonisolated(unsafe) var capsLockMonitor: Any?
    private nonisolated(unsafe) var devices: [AnyObject] = []

    private let lib = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LAZY
    )

    // Call from onAppear — sets up CapsLock as the mode toggle
    func setupCapsLockToggle(for session: TouchDiagnosticSession) {
        self.session = session
        capsLockMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard event.keyCode == 57, let self else { return }
            let active = event.modifierFlags.contains(.capsLock)
            DispatchQueue.main.async {
                guard let session = self.session else { return }
                if active { self.start(session: session) } else { self.stop() }
            }
        }
    }

    // Call from onDisappear
    func teardownCapsLockToggle() {
        if let monitor = capsLockMonitor {
            NSEvent.removeMonitor(monitor)
            capsLockMonitor = nil
        }
        stop()
    }

    func start(session: TouchDiagnosticSession) {
        stopDevices()
        self.session = session

        guard let lib else {
            print("[MT] could not open MultitouchSupport.framework")
            return
        }

        typealias CreateListFn = @convention(c) () -> CFArray
        typealias RegisterFn   = @convention(c) (UnsafeRawPointer, MTCallbackFn) -> Void
        typealias StartFn      = @convention(c) (UnsafeRawPointer, Int32) -> Void

        guard
            let cs = dlsym(lib, "MTDeviceCreateList"),
            let rs = dlsym(lib, "MTRegisterContactFrameCallback"),
            let ss = dlsym(lib, "MTDeviceStart")
        else {
            print("[MT] could not resolve symbols")
            return
        }

        let createList  = unsafeBitCast(cs, to: CreateListFn.self)
        let registerCb  = unsafeBitCast(rs, to: RegisterFn.self)
        let startDevice = unsafeBitCast(ss, to: StartFn.self)

        devices = createList() as [AnyObject]
        for device in devices {
            let raw = Unmanaged.passUnretained(device).toOpaque()
            registerCb(raw, mtFrameCallback)
            startDevice(raw, 0)
        }
        session.isActive = true
    }

    func stop() {
        session?.isActive = false
        session?.liveFingers = []
        stopDevices()
    }

    private func stopDevices() {
        defer { devices = [] }
        guard let lib, !devices.isEmpty else { return }
        typealias StopFn = @convention(c) (UnsafeRawPointer) -> Void
        guard let sym = dlsym(lib, "MTDeviceStop") else { return }
        let stopDevice = unsafeBitCast(sym, to: StopFn.self)
        for device in devices {
            stopDevice(Unmanaged.passUnretained(device).toOpaque())
        }
    }
}

// MARK: - Data Model

struct FingerState: Identifiable {
    let id: String           // String(MTContact.identifier)
    let label: String        // #1, #2, …
    let x: CGFloat           // normalized 0…1
    let y: CGFloat           // normalized 0…1
    let pressure: CGFloat    // from zDensity, clamped 0…1
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
    let deltaMs: Int?
    let rawState: Int32      // raw MTContact.state — useful during Phase 1 exploration
}

final class TouchDiagnosticSession: ObservableObject {
    @Published var liveFingers: [FingerState] = []
    @Published var eventLog: [TouchLogEntry] = []
    @Published var isActive: Bool = false

    private var fingerLabels: [String: String] = [:]
    private var fingerLastTime: [String: TimeInterval] = [:]
    private var labelCounter = 0
    private let maxLogEntries = 500

    func update(mtContacts contacts: [MTContact], timestamp: Double) {
        let currentIDs = Set(contacts.map { String($0.identifier) })
        var liveLookup: [String: FingerState] = Dictionary(
            uniqueKeysWithValues: liveFingers.map { ($0.id, $0) }
        )

        // Synthesize "ended" for fingers that disappeared from the frame
        for id in Set(liveLookup.keys).subtracting(currentIDs) {
            if let prev = liveLookup[id] {
                appendLog(TouchLogEntry(
                    timestamp: Date(), fingerLabel: prev.label,
                    phase: "ended", x: prev.x, y: prev.y,
                    pressure: prev.pressure, deltaMs: nil, rawState: -1
                ))
            }
            liveLookup.removeValue(forKey: id)
            fingerLastTime.removeValue(forKey: id)
        }

        // Update active contacts
        for contact in contacts {
            let rawID = String(contact.identifier)
            let isNew = liveLookup[rawID] == nil

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

            let x = CGFloat(contact.normalized.position.x)
            let y = CGFloat(contact.normalized.position.y)
            let pressure = CGFloat(min(max(contact.zDensity, 0), 1))

            let phase: String
            if isNew {
                phase = "began"
            } else if let prev = liveLookup[rawID],
                      abs(prev.x - x) < 0.0005 && abs(prev.y - y) < 0.0005 {
                phase = "stationary"
            } else {
                phase = "moved"
            }

            if phase != "stationary" {
                appendLog(TouchLogEntry(
                    timestamp: Date(), fingerLabel: label,
                    phase: phase, x: x, y: y,
                    pressure: pressure, deltaMs: deltaMs,
                    rawState: contact.state
                ))
            }

            fingerLastTime[rawID] = timestamp
            liveLookup[rawID] = FingerState(
                id: rawID, label: label,
                x: x, y: y, pressure: pressure,
                phase: phase, lastEventTime: timestamp,
                deltaMsFromPrev: deltaMs
            )
        }

        liveFingers = Array(liveLookup.values).sorted { $0.label < $1.label }
    }

    func clearAll() {
        eventLog = []
        liveFingers = []
        fingerLabels = [:]
        fingerLastTime = [:]
        labelCounter = 0
    }

    private func appendLog(_ entry: TouchLogEntry) {
        eventLog.append(entry)
        if eventLog.count > maxLogEntries {
            eventLog.removeFirst(eventLog.count - maxLogEntries)
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
                TrackpadSurface(fingers: session.liveFingers, isActive: session.isActive)
                    .padding(16)
                Divider()
                FingerTablePanel(fingers: session.liveFingers)
                    .frame(width: 340)
            }
            Divider()
            EventLogPanel(entries: session.eventLog)
        }
        .onAppear  { MultitouchCapture.shared.setupCapsLockToggle(for: session) }
        .onDisappear { MultitouchCapture.shared.teardownCapsLockToggle() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Touchpad Diagnostics")
                .font(.system(size: 18, weight: .semibold))
            modePill
            Spacer()
            Button("Clear") { session.clearAll() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modePill: some View {
        Group {
            if session.isActive {
                Text("● CAPTURING")
                    .foregroundColor(.white)
                    .background(Color.green)
            } else {
                Text("○ OFF  —  press CapsLock")
                    .foregroundColor(.secondary)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Trackpad Surface

struct TrackpadSurface: View {
    let fingers: [FingerState]
    let isActive: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? Color.green.opacity(0.4) : Color.secondary.opacity(0.25),
                        lineWidth: isActive ? 1.5 : 1
                    )

                if fingers.isEmpty {
                    Text(isActive ? "Place fingers on trackpad" : "Press CapsLock to start")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                ForEach(fingers) { finger in
                    // trackpad y=0 is bottom; SwiftUI y=0 is top
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

#endif // canImport(SwiftUI)
