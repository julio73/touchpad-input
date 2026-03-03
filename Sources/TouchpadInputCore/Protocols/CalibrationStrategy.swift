// Sources/TouchpadInputCore/Protocols/CalibrationStrategy.swift

/// Drives a calibration flow that records user taps and builds a UserCalibration.
@MainActor
public protocol CalibrationStrategy: AnyObject {
    var isActive: Bool { get }
    func recordTap(x: Float, y: Float)
    func buildCalibration() -> UserCalibration
}
