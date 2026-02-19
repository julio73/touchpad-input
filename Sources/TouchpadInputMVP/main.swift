import AppKit
import SwiftUI

@main
struct TouchpadInputMVPApp: App {
    var body: some Scene {
        WindowGroup("Touchpad Input MVP") {
            ContentView()
                .frame(minWidth: 900, minHeight: 560)
        }
    }
}

final class InputSession: ObservableObject {
    @Published var outputText: String = ""
    @Published var activeTouches: [TouchPoint] = []
    @Published var lastKey: String = "-"
    @Published var pressure: Double = 0

    func appendCharacter(_ value: String) {
        outputText += value
        lastKey = value == " " ? "SPACE" : value
    }

    func deleteBackward() {
        guard !outputText.isEmpty else { return }
        outputText.removeLast()
        lastKey = "DELETE"
    }

    func clear() {
        outputText = ""
        lastKey = "CLEAR"
    }
}

struct TouchPoint: Identifiable {
    let id: String
    let x: CGFloat
    let y: CGFloat
}

struct KeyRegion: Identifiable {
    let id: String
    let label: String
    let frame: CGRect
}

struct ContentView: View {
    @StateObject private var session = InputSession()
    private let layout = KeyboardLayout.defaultLayout

    var body: some View {
        VStack(spacing: 16) {
            header
            TouchCaptureRepresentable(layout: layout, session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    debugOverlay
                        .padding(12)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            outputArea
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            Text("Touchpad Input MVP")
                .font(.system(size: 22, weight: .bold))
            Spacer()
            Button("Clear Output") { session.clear() }
        }
    }

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Touches: \(session.activeTouches.count)")
            Text("Last Key: \(session.lastKey)")
            Text("Pressure: \(String(format: "%.2f", session.pressure))")
        }
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)
            TextEditor(text: $session.outputText)
                .font(.system(size: 15, design: .monospaced))
                .frame(height: 180)
                .border(Color.secondary.opacity(0.3))
        }
    }
}

struct TouchCaptureRepresentable: NSViewRepresentable {
    let layout: KeyboardLayout
    @ObservedObject var session: InputSession

    func makeNSView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView(frame: .zero)
        view.layout = layout
        view.session = session
        return view
    }

    func updateNSView(_ nsView: TouchCaptureView, context: Context) {
        nsView.layout = layout
        nsView.session = session
    }
}

final class TouchCaptureView: NSView {
    var layout: KeyboardLayout = .defaultLayout
    weak var session: InputSession?

    private var emittedForTouch: Set<AnyHashable> = []
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
        if let observer = pressureObserver {
            NSEvent.removeMonitor(observer)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        allowedTouchTypes = [.direct, .indirect]
        acceptsTouchEvents = true

        pressureObserver = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] event in
            self?.handlePressure(event)
            return event
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawKeyboardGrid()
        drawTouchMarkers()
    }

    override func touchesBegan(with event: NSEvent) {
        processTouches(event)
    }

    override func touchesMoved(with event: NSEvent) {
        processTouches(event)
    }

    override func touchesEnded(with event: NSEvent) {
        processTouches(event, resetEndedTouches: true)
    }

    override func touchesCancelled(with event: NSEvent) {
        processTouches(event, resetEndedTouches: true)
    }

    private func handlePressure(_ event: NSEvent) {
        session?.pressure = Double(event.pressure)
        if event.pressure > 0.9 {
            session?.deleteBackward()
        }
    }

    private func processTouches(_ event: NSEvent, resetEndedTouches: Bool = false) {
        let touches = event.touches(matching: .touching, in: self)
        if resetEndedTouches {
            emittedForTouch = emittedForTouch.intersection(touches.map { $0.identity })
        }

        var points: [TouchPoint] = []
        for touch in touches {
            let location = convertFromNormalized(touch.normalizedPosition)
            let touchID = AnyHashable(touch.identity)
            points.append(TouchPoint(id: String(describing: touchID), x: location.x, y: location.y))

            if !emittedForTouch.contains(touchID), let key = keyLabel(at: location) {
                emittedForTouch.insert(touchID)
                emitKey(key)
            }
        }

        session?.activeTouches = points
        needsDisplay = true
    }

    private func convertFromNormalized(_ point: NSPoint) -> NSPoint {
        NSPoint(x: bounds.width * point.x, y: bounds.height * point.y)
    }

    private func keyLabel(at point: NSPoint) -> String? {
        layout.keyRegions(in: bounds).first(where: { $0.frame.contains(point) })?.label
    }

    private func emitKey(_ key: String) {
        switch key {
        case "SPACE":
            session?.appendCharacter(" ")
        case "DEL":
            session?.deleteBackward()
        default:
            session?.appendCharacter(key.lowercased())
        }
    }

    private func drawKeyboardGrid() {
        NSColor.gridColor.withAlphaComponent(0.5).setStroke()
        for region in layout.keyRegions(in: bounds) {
            let path = NSBezierPath(roundedRect: region.frame.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            path.lineWidth = 1
            path.stroke()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let text = NSAttributedString(string: region.label, attributes: attributes)
            let textSize = text.size()
            let textOrigin = NSPoint(
                x: region.frame.midX - textSize.width / 2,
                y: region.frame.midY - textSize.height / 2
            )
            text.draw(at: textOrigin)
        }
    }

    private func drawTouchMarkers() {
        NSColor.systemBlue.withAlphaComponent(0.8).setFill()
        for point in session?.activeTouches ?? [] {
            let marker = NSBezierPath(ovalIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
            marker.fill()
        }
    }
}

struct KeyboardLayout {
    let rows: [[String]]

    static let defaultLayout = KeyboardLayout(rows: [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", "DEL"],
        ["Z", "X", "C", "V", "B", "N", "M", "SPACE"]
    ])

    func keyRegions(in bounds: CGRect) -> [KeyRegion] {
        var regions: [KeyRegion] = []
        guard !rows.isEmpty else { return regions }

        let totalRows = CGFloat(rows.count)
        let rowHeight = bounds.height / totalRows

        for (rowIndex, row) in rows.enumerated() {
            guard !row.isEmpty else { continue }

            let y = bounds.height - (CGFloat(rowIndex + 1) * rowHeight)
            let totalWeight = row.reduce(0.0) { partial, key in
                partial + keyWidthWeight(key)
            }

            var x: CGFloat = 0
            for key in row {
                let width = bounds.width * (keyWidthWeight(key) / totalWeight)
                let frame = CGRect(x: x, y: y, width: width, height: rowHeight)
                regions.append(KeyRegion(id: "\(rowIndex)-\(key)", label: key, frame: frame))
                x += width
            }
        }

        return regions
    }

    private func keyWidthWeight(_ key: String) -> CGFloat {
        if key == "SPACE" { return 3.0 }
        if key == "DEL" { return 1.5 }
        return 1.0
    }
}
