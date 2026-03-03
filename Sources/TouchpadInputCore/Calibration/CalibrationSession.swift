// Sources/TouchpadInputCore/Calibration/CalibrationSession.swift
import Foundation

/// Drives the first-run calibration flow. Presents one target character at a time;
/// records where the user actually taps; builds UserCalibration offsets when complete.
@MainActor
public final class CalibrationSession: ObservableObject, CalibrationStrategy {
    // 32 unique characters covering the full grid.
    public static let sentence = "pack my box with five dozen liquor jugs"
    public static let calibrationTargets: [Character] =
        Array(sentence.filter { !$0.isWhitespace })

    @Published public var currentIndex: Int = 0
    @Published public var isComplete: Bool = false

    private(set) public var samples: [(target: Character, x: Float, y: Float)] = []

    public var targets: [Character] { Self.calibrationTargets }
    public var progress: Double { Double(currentIndex) / Double(targets.count) }
    public var currentTarget: Character? {
        currentIndex < targets.count ? targets[currentIndex] : nil
    }

    // CalibrationStrategy
    public var isActive: Bool { !isComplete && currentIndex < targets.count }

    public init() {}

    public func recordTap(x: Float, y: Float) {
        guard currentIndex < targets.count else { return }
        samples.append((targets[currentIndex], x, y))
        currentIndex += 1
        if currentIndex >= targets.count { isComplete = true }
    }

    public func reset() {
        currentIndex = 0
        isComplete = false
        samples = []
    }

    /// Computes per-zone centroid offsets from recorded samples.
    public func buildCalibration() -> UserCalibration {
        let grid = KeyGrid.default
        var accumulator: [String: [(Float, Float)]] = [:]
        for sample in samples {
            guard let zone = grid.zones.first(where: { $0.character == sample.target }) else { continue }
            let cx = (zone.xMin + zone.xMax) / 2
            let cy = (zone.yMin + zone.yMax) / 2
            let key = String(zone.character)
            accumulator[key, default: []].append((sample.x - cx, sample.y - cy))
        }
        var offsets: [String: UserCalibration.Offset] = [:]
        for (key, diffs) in accumulator {
            let meanDx = diffs.map { $0.0 }.reduce(0, +) / Float(diffs.count)
            let meanDy = diffs.map { $0.1 }.reduce(0, +) / Float(diffs.count)
            offsets[key] = UserCalibration.Offset(dx: meanDx, dy: meanDy, sampleCount: diffs.count)
        }
        return UserCalibration(offsets: offsets)
    }
}
