// Sources/TouchpadInputCore/Calibration/UserCalibration.swift
import Foundation

/// Stores per-zone centroid offsets learned from how the user actually taps.
/// Persisted to UserDefaults as JSON. Refined incrementally after every emission.
public struct UserCalibration: Codable, Sendable {
    public struct Offset: Codable, Sendable {
        public var dx: Float
        public var dy: Float
        public var sampleCount: Int

        public init(dx: Float, dy: Float, sampleCount: Int) {
            self.dx = dx; self.dy = dy; self.sampleCount = sampleCount
        }
    }

    public var offsets: [String: Offset]  // key = String(zone.character)

    public static let empty = UserCalibration(offsets: [:])

    /// Median per-axis offset across all calibrated keys. Applied to the raw tap coordinate
    /// before zone lookup so the grid boundaries stay intact (no overlap / gaps).
    public var globalOffset: (dx: Float, dy: Float) {
        guard !offsets.isEmpty else { return (0, 0) }
        let dxs = offsets.values.map { $0.dx }.sorted()
        let dys = offsets.values.map { $0.dy }.sorted()
        let mid = offsets.count / 2
        return (dxs[mid], dys[mid])
    }

    public init(offsets: [String: Offset]) { self.offsets = offsets }

    private static let defaultsKey = "userCalibration"

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    public static func load() -> UserCalibration {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let cal = try? JSONDecoder().decode(UserCalibration.self, from: data)
        else { return .empty }
        return cal
    }

    /// EMA refinement called after every real tap. α ≈ 0.05 so ~20 taps meaningfully shift a zone.
    public mutating func refine(character: Character, tapX: Float, tapY: Float, in grid: KeyGrid) {
        guard let zone = grid.zones.first(where: { $0.character == character }) else { return }
        let cx = (zone.xMin + zone.xMax) / 2
        let cy = (zone.yMin + zone.yMax) / 2
        let key = String(zone.character)
        let newDx = tapX - cx
        let newDy = tapY - cy
        let alpha: Float = 0.05
        if var existing = offsets[key] {
            existing.dx = (1 - alpha) * existing.dx + alpha * newDx
            existing.dy = (1 - alpha) * existing.dy + alpha * newDy
            existing.sampleCount += 1
            offsets[key] = existing
        } else {
            offsets[key] = Offset(dx: newDx, dy: newDy, sampleCount: 1)
        }
    }
}
