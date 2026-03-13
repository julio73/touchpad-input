// Sources/TouchpadInputApp/Views/DrawingCanvasView.swift
import SwiftUI
import TouchpadInputCore
import AppKit

struct DrawingCanvasView: View {
    @ObservedObject var session: DrawingSession

    @State private var selectedColor: Color = .black
    @State private var lineWidth: CGFloat = 2.5
    private let widthOptions: [CGFloat] = [1.5, 2.5, 4.0, 7.0]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Drawing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Divider().frame(height: 18)

            // Color swatches
            ForEach([Color.black, .blue, .red, .green, .orange], id: \.self) { color in
                colorSwatch(color)
            }

            Divider().frame(height: 18)

            // Line width picker
            Picker("Width", selection: $lineWidth) {
                ForEach(widthOptions, id: \.self) { w in
                    Text(widthLabel(w)).tag(w)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .onChange(of: lineWidth) { w in
                session.currentLineWidth = w
            }

            Spacer()

            Button("Undo") { session.undo() }
                .disabled(session.strokes.isEmpty)
                .keyboardShortcut("z", modifiers: .command)

            Button("Clear") { session.clear() }
                .disabled(session.strokes.isEmpty)

            Button("Export PNG") { exportPNG() }
                .disabled(session.strokes.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func colorSwatch(_ color: Color) -> some View {
        Button(action: {
            selectedColor = color
            session.currentColor = NSColor(color).cgColor
        }) {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.borderless)
    }

    private func widthLabel(_ w: CGFloat) -> String {
        switch w {
        case 1.5: return "Fine"
        case 2.5: return "Med"
        case 4.0: return "Thick"
        case 7.0: return "Bold"
        default:  return String(format: "%.0f", w)
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        session.isActive ? Color.green.opacity(0.4) : Color.secondary.opacity(0.2),
                        lineWidth: session.isActive ? 1.5 : 1
                    )

                // Strokes canvas
                Canvas { ctx, size in
                    for stroke in session.strokes {
                        drawStroke(stroke, in: ctx, size: size)
                    }
                }

                // Live finger dots
                ForEach(session.liveFingers) { finger in
                    Circle()
                        .fill(selectedColor.opacity(0.4))
                        .frame(width: 14, height: 14)
                        .position(
                            x: finger.x * geo.size.width,
                            y: (1 - finger.y) * geo.size.height
                        )
                }

                if !session.isActive {
                    Text("Double-tap ctrl to start drawing")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // Stroke y is hardware-space (0=bottom, 1=top); Canvas y is screen-space (0=top).
    private func drawStroke(_ stroke: DrawingStroke, in ctx: GraphicsContext, size: CGSize) {
        guard stroke.points.count >= 2 else { return }

        let pts = stroke.points.map {
            CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height)
        }

        var path = Path()
        path.move(to: pts[0])
        if pts.count == 2 {
            path.addLine(to: pts[1])
        } else {
            for i in 1..<pts.count - 1 {
                let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                                  y: (pts[i].y + pts[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i])
            }
            path.addLine(to: pts[pts.count - 1])
        }

        let color = Color(cgColor: stroke.color)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(
            lineWidth: stroke.lineWidth,
            lineCap: .round,
            lineJoin: .round
        ))
    }

    // MARK: - Export

    private func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "signature.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let size = CGSize(width: 1200, height: 800)
            let image = session.renderToImage(size: size)
            guard
                let tiff = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff),
                let pngData = bitmap.representation(using: .png, properties: [:])
            else { return }
            try? pngData.write(to: url)
        }
    }
}
