// Sources/TouchpadInputCore/Drawing/DrawingSession.swift
import AppKit

// MARK: - DrawingStroke

public struct DrawingStroke: Identifiable, Sendable {
    public let id: UUID
    public var points: [CGPoint]   // normalized: x 0…1 left→right, y 0…1 bottom→top (hardware space)
    public var color: CGColor
    public var lineWidth: CGFloat

    public init(color: CGColor = CGColor(gray: 0, alpha: 1), lineWidth: CGFloat = 2.5) {
        self.id = UUID()
        self.points = []
        self.color = color
        self.lineWidth = lineWidth
    }
}

// MARK: - DrawingSession

@MainActor
public final class DrawingSession: ObservableObject, @preconcurrency TouchEventReceiver {

    @Published public var isActive: Bool = false
    @Published public var liveFingers: [FingerState] = []
    @Published public var strokes: [DrawingStroke] = []

    public var currentColor: CGColor = CGColor(gray: 0, alpha: 1)
    public var currentLineWidth: CGFloat = 2.5

    // Map touch identifier → index in strokes
    private var activeIdx: [Int32: Int] = [:]
    private var prevIDs: Set<Int32> = []

    public init() {}

    public func update(mtContacts: [MTContact], timestamp: Double) {
        var currentIDs = Set<Int32>()
        var fingers: [FingerState] = []

        for contact in mtContacts {
            let touchID = contact.identifier
            currentIDs.insert(touchID)

            let nx = CGFloat(contact.normalized.position.x)
            let ny = CGFloat(contact.normalized.position.y) // 0=bottom, 1=top (hardware space)
            let pt = CGPoint(x: nx, y: ny)

            if prevIDs.contains(touchID), let idx = activeIdx[touchID] {
                strokes[idx].points.append(pt)
            } else {
                var stroke = DrawingStroke(color: currentColor, lineWidth: currentLineWidth)
                stroke.points.append(pt)
                activeIdx[touchID] = strokes.count
                strokes.append(stroke)
            }

            let phase = prevIDs.contains(touchID) ? "moved" : "began"
            fingers.append(FingerState(
                id: String(touchID),
                label: "#\(touchID)",
                x: nx,
                y: ny,
                pressure: CGFloat(min(max(contact.zDensity, 0), 1)),
                size: CGFloat(contact.size),
                phase: phase,
                lastEventTime: timestamp,
                deltaMsFromPrev: nil
            ))
        }

        for endedID in prevIDs.subtracting(currentIDs) {
            activeIdx.removeValue(forKey: endedID)
        }

        prevIDs = currentIDs
        liveFingers = fingers
    }

    public func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }

    public func clear() {
        strokes = []
        activeIdx = [:]
        prevIDs = []
    }

    /// Renders all strokes to an NSImage of the given size.
    public func renderToImage(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath.fill(CGRect(origin: .zero, size: size))
        for stroke in strokes {
            renderStroke(stroke, canvasSize: size)
        }
        image.unlockFocus()
        return image
    }

    // NSImage lockFocus uses AppKit coords: y=0 at bottom, y=height at top.
    // Our stroke y is hardware-space (0=bottom, 1=top), so no flip needed here.
    private func renderStroke(_ stroke: DrawingStroke, canvasSize: CGSize) {
        guard stroke.points.count >= 2 else { return }
        (NSColor(cgColor: stroke.color) ?? .black).setStroke()
        let path = NSBezierPath()
        path.lineWidth = stroke.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let pts = stroke.points.map {
            CGPoint(x: $0.x * canvasSize.width, y: $0.y * canvasSize.height)
        }
        path.move(to: pts[0])
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                              y: (pts[i].y + pts[i + 1].y) / 2)
            path.curve(to: mid, controlPoint1: pts[i], controlPoint2: mid)
        }
        path.line(to: pts[pts.count - 1])
        path.stroke()
    }
}
