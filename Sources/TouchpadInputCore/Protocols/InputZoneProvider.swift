// Sources/TouchpadInputCore/Protocols/InputZoneProvider.swift

/// Provides a logical zone identifier for a touch coordinate.
/// Conforming types map normalized (0…1) trackpad positions to opaque zone IDs.
public protocol InputZoneProvider: Sendable {
    /// Returns the zone identifier for the given normalized position, or nil if outside all zones.
    func zoneID(at x: Float, y: Float) -> String?
    /// Returns a human-readable label for the given zone ID, or nil if unknown.
    func label(forZoneID id: String) -> String?
}
