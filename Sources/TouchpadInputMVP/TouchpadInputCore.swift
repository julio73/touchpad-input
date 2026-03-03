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
    private nonisolated(unsafe) var keyMonitor: Any?
    private nonisolated(unsafe) var lastControlPressTime: TimeInterval = 0
    private nonisolated(unsafe) var devices: [AnyObject] = []

    private let lib = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LAZY
    )

    // Call from onAppear — double-tap either Control key toggles capture
    func setupDoubleControlToggle(for session: TouchDiagnosticSession) {
        self.session = session
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            // keyCode 59 = left ctrl, 62 = right ctrl; only fire on key-down (flag present)
            guard (event.keyCode == 59 || event.keyCode == 62),
                  event.modifierFlags.contains(.control) else { return }
            let now = event.timestamp
            if now - self.lastControlPressTime < 0.35 {
                self.lastControlPressTime = 0
                DispatchQueue.main.async {
                    guard let s = self.session else { return }
                    if s.isActive { self.stop() } else { self.start(session: s) }
                }
            } else {
                self.lastControlPressTime = now
            }
        }
    }

    // Call from onDisappear
    func teardownDoubleControlToggle() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        lastControlPressTime = 0
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

// MARK: - Key Grid

struct KeyZone {
    let character: Character
    let altCharacter: Character?   // force-press (zDensity ≥ 0.85); nil = fall back to uppercase
    let xMin, xMax: Float
    let yMin, yMax: Float
}

struct KeyGrid {
    let zones: [KeyZone]

    func zone(at x: Float, y: Float) -> KeyZone? {
        zones.first { z in x >= z.xMin && x < z.xMax && y >= z.yMin && y < z.yMax }
    }

    static let `default`: KeyGrid = {
        // 10 columns: xMin for column i = 0.020 + i * 0.096, width 0.096
        let cols: [(xMin: Float, xMax: Float)] = (0..<10).map { i in
            let xMin: Float = 0.020 + Float(i) * 0.096
            return (xMin, xMin + 0.096)
        }

        let topRow:    [Character] = ["q","w","e","r","t","y","u","i","o","p"]
        let homeRow:   [Character] = ["a","s","d","f","g","h","j","k","l",";"]
        let bottomRow: [Character] = ["z","x","c","v","b","n","m",",",".","/"]

        // Force-press alternates: number row, shifted symbols, programmer punctuation
        let topAlt:    [Character] = ["1","2","3","4","5","6","7","8","9","0"]
        let homeAlt:   [Character] = ["!","@","#","$","%","^","&","*","(",")"]
        let bottomAlt: [Character] = ["-","_","+","=","[","]","{","}","`","~"]

        var zones: [KeyZone] = []

        for (i, (ch, alt)) in zip(topRow, topAlt).enumerated() {
            zones.append(KeyZone(character: ch, altCharacter: alt,
                                 xMin: cols[i].xMin, xMax: cols[i].xMax,
                                 yMin: 0.65, yMax: 1.0))
        }
        for (i, (ch, alt)) in zip(homeRow, homeAlt).enumerated() {
            zones.append(KeyZone(character: ch, altCharacter: alt,
                                 xMin: cols[i].xMin, xMax: cols[i].xMax,
                                 yMin: 0.30, yMax: 0.65))
        }
        for (i, (ch, alt)) in zip(bottomRow, bottomAlt).enumerated() {
            zones.append(KeyZone(character: ch, altCharacter: alt,
                                 xMin: cols[i].xMin, xMax: cols[i].xMax,
                                 yMin: 0.08, yMax: 0.30))
        }
        // Space bar → newline on force-press
        zones.append(KeyZone(character: " ", altCharacter: "\n",
                             xMin: 0.02, xMax: 0.98,
                             yMin: 0.00, yMax: 0.08))

        return KeyGrid(zones: zones)
    }()
}

// MARK: - Modifier Zones

enum ModifierKind: Hashable {
    case shift   // thumb held here → force uppercase on next tap(s)
    case delete  // thumb held here → next tap removes last output char
}

struct ModifierZone {
    let kind: ModifierKind
    let label: String
    let xMin, xMax: Float
    let yMin, yMax: Float

    func contains(x: Float, y: Float) -> Bool {
        x >= xMin && x < xMax && y >= yMin && y < yMax
    }

    // Bottom-left corner = Shift hold; bottom-right corner = Delete hold.
    // 15 % wide × 15 % tall — large enough for a thumb to rest reliably.
    // Overlaps slightly with the outermost key columns at y ∈ [0.08, 0.15);
    // isInModifierZone is checked first so those key sub-areas are silenced.
    static let all: [ModifierZone] = [
        ModifierZone(kind: .shift,  label: "⇧",
                     xMin: 0.00, xMax: 0.15, yMin: 0.00, yMax: 0.15),
        ModifierZone(kind: .delete, label: "⌫",
                     xMin: 0.85, xMax: 1.00, yMin: 0.00, yMax: 0.15),
    ]
}

// MARK: - Character Emitter

final class CharacterEmitter {
    let grid: KeyGrid

    init(grid: KeyGrid = .default) {
        self.grid = grid
    }

    /// Returns a character for a "began" touch, or nil if outside a zone or below pressure threshold.
    /// - pressure < 0.30  → nil
    /// - pressure 0.30–0.69 → lowercase character
    /// - pressure 0.70–0.84 → uppercase character
    /// - pressure ≥ 0.85  → altCharacter (or uppercase if no alt defined)
    func characterForTouch(at x: Float, y: Float, pressure: Float) -> Character? {
        guard pressure >= 0.30 else { return nil }
        guard let zone = grid.zone(at: x, y: y) else { return nil }
        if pressure >= 0.85 {
            return zone.altCharacter ?? Character(String(zone.character).uppercased())
        } else if pressure >= 0.70 {
            return Character(String(zone.character).uppercased())
        } else {
            return zone.character
        }
    }
}

final class TouchDiagnosticSession: ObservableObject {
    @Published var liveFingers: [FingerState] = []
    @Published var eventLog: [TouchLogEntry] = []
    @Published var isActive: Bool = false
    @Published var outputBuffer: String = ""
    @Published var activeModifiers: Set<ModifierKind> = []

    private let emitter = CharacterEmitter()
    private let modifierZones = ModifierZone.all
    private var fingerLabels: [String: String] = [:]
    private var fingerLastTime: [String: TimeInterval] = [:]
    private var labelCounter = 0
    private let maxLogEntries = 500

    func update(mtContacts contacts: [MTContact], timestamp: Double) {
        // Detect modifiers held from the *previous* frame before any new contacts are processed.
        let heldModifiers: Set<ModifierKind> = Set(
            modifierZones.compactMap { mz in
                liveFingers.contains { mz.contains(x: Float($0.x), y: Float($0.y)) }
                    ? mz.kind : nil
            }
        )

        let currentIDs = Set(contacts.map { String($0.identifier) })
        var liveLookup: [String: FingerState] = Dictionary(
            uniqueKeysWithValues: liveFingers.map { ($0.id, $0) }
        )
        var emittedZoneKeys: Set<String> = []

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

            if phase == "began" {
                let fx = Float(x), fy = Float(y)
                let isInModifierZone = modifierZones.contains { $0.contains(x: fx, y: fy) }
                if !isInModifierZone {
                    if heldModifiers.contains(.delete) {
                        // Delete-hold: any tap outside modifier zones removes last char
                        if !outputBuffer.isEmpty { outputBuffer.removeLast() }
                    } else if let zone = emitter.grid.zone(at: fx, y: fy) {
                        let key = "\(zone.xMin)-\(zone.yMin)"
                        if !emittedZoneKeys.contains(key) {
                            emittedZoneKeys.insert(key)
                            // Shift-hold bumps pressure into uppercase range if below it
                            var effectivePressure = Float(pressure)
                            if heldModifiers.contains(.shift),
                               effectivePressure >= 0.30, effectivePressure < 0.70 {
                                effectivePressure = 0.70
                            }
                            if let ch = emitter.characterForTouch(at: fx, y: fy, pressure: effectivePressure) {
                                outputBuffer.append(ch)
                            }
                        }
                    }
                }
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
        activeModifiers = heldModifiers
    }

    func clearAll() {
        eventLog = []
        liveFingers = []
        outputBuffer = ""
        activeModifiers = []
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
                TrackpadSurface(fingers: session.liveFingers, isActive: session.isActive,
                                activeModifiers: session.activeModifiers)
                    .padding(16)
                Divider()
                FingerTablePanel(fingers: session.liveFingers)
                    .frame(width: 340)
            }
            Divider()
            OutputBufferPanel(text: session.outputBuffer, activeModifiers: session.activeModifiers)
            Divider()
            EventLogPanel(entries: session.eventLog)
        }
        .onAppear  { MultitouchCapture.shared.setupDoubleControlToggle(for: session) }
        .onDisappear { MultitouchCapture.shared.teardownDoubleControlToggle() }
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
                Text("● CAPTURING  —  double ctrl to stop")
                    .foregroundColor(.white)
                    .background(Color.green)
            } else {
                Text("○ OFF  —  double ctrl to start")
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

// MARK: - Output Buffer Panel

struct OutputBufferPanel: View {
    let text: String
    var activeModifiers: Set<ModifierKind> = []

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

// MARK: - Key Grid Overlay

struct KeyGridOverlay: View {
    var activeModifiers: Set<ModifierKind> = []

    private let zones = KeyGrid.default.zones
    private let modZones = ModifierZone.all

    var body: some View {
        GeometryReader { geo in
            // Key zone outlines + modifier zone fills
            Canvas { ctx, size in
                for zone in zones {
                    let rect = CGRect(
                        x: CGFloat(zone.xMin) * size.width,
                        y: (1.0 - CGFloat(zone.yMax)) * size.height,
                        width: CGFloat(zone.xMax - zone.xMin) * size.width,
                        height: CGFloat(zone.yMax - zone.yMin) * size.height
                    )
                    ctx.stroke(Path(rect), with: .color(.secondary.opacity(0.20)), lineWidth: 0.5)
                }
                for mz in modZones {
                    let rect = CGRect(
                        x: CGFloat(mz.xMin) * size.width,
                        y: (1.0 - CGFloat(mz.yMax)) * size.height,
                        width: CGFloat(mz.xMax - mz.xMin) * size.width,
                        height: CGFloat(mz.yMax - mz.yMin) * size.height
                    )
                    let isActive = activeModifiers.contains(mz.kind)
                    let fillColor: GraphicsContext.Shading = isActive
                        ? (mz.kind == .shift ? .color(.blue.opacity(0.30)) : .color(.orange.opacity(0.30)))
                        : (mz.kind == .shift ? .color(.blue.opacity(0.08))  : .color(.orange.opacity(0.08)))
                    ctx.fill(Path(rect), with: fillColor)
                    ctx.stroke(Path(rect), with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
                }
            }
            // Key labels
            ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                let cx = CGFloat((zone.xMin + zone.xMax) / 2) * geo.size.width
                let cy = (1.0 - CGFloat((zone.yMin + zone.yMax) / 2)) * geo.size.height
                Text(zone.character == " " ? "spc" : String(zone.character).uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.55))
                    .position(x: cx, y: cy)
            }
            // Modifier zone labels
            ForEach(Array(modZones.enumerated()), id: \.offset) { _, mz in
                let cx = CGFloat((mz.xMin + mz.xMax) / 2) * geo.size.width
                let cy = (1.0 - CGFloat((mz.yMin + mz.yMax) / 2)) * geo.size.height
                let isActive = activeModifiers.contains(mz.kind)
                Text(mz.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isActive
                        ? (mz.kind == .shift ? .blue : .orange)
                        : .secondary.opacity(0.45))
                    .position(x: cx, y: cy)
            }
        }
    }
}

// MARK: - Trackpad Surface

struct TrackpadSurface: View {
    let fingers: [FingerState]
    let isActive: Bool
    var activeModifiers: Set<ModifierKind> = []

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

                KeyGridOverlay(activeModifiers: activeModifiers)

                if !isActive {
                    Text("Double-tap ctrl to start")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
