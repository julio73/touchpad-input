import SwiftUI
import TouchpadInputCore

struct KeyGridOverlay: View {
    var zones: [KeyZone]
    var activeModifiers: Set<AnyModifierKind> = []

    private let modZones = ModifierZone.all

    var body: some View {
        GeometryReader { geo in
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
            ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                let cx = CGFloat((zone.xMin + zone.xMax) / 2) * geo.size.width
                let cy = (1.0 - CGFloat((zone.yMin + zone.yMax) / 2)) * geo.size.height
                Text(zone.character == " " ? "spc" : String(zone.character).uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.55))
                    .position(x: cx, y: cy)
            }
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
