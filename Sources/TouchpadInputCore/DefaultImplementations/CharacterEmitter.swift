// Sources/TouchpadInputCore/DefaultImplementations/CharacterEmitter.swift

/// Converts zone IDs and pressure values into characters using the QWERTY pressure model:
/// - pressure < pressureFloor → nil
/// - pressureFloor…0.69 → lowercase
/// - 0.70…0.84 → uppercase
/// - ≥ 0.85 → altCharacter (or uppercase if none defined)
public struct CharacterEmitter: CharacterResolver {
    public let grid: KeyGrid

    public init(grid: KeyGrid = .default) { self.grid = grid }

    // MARK: CharacterResolver

    public func character(forZoneID id: String, pressure: Float,
                          modifiers: Set<AnyModifierKind>, pressureFloor: Float) -> Character? {
        guard pressure >= pressureFloor else { return nil }
        guard let zone = grid.zones.first(where: { String($0.character) == id }) else { return nil }
        return resolve(zone: zone, pressure: pressure)
    }

    // MARK: Legacy coordinate-based API (kept for direct-use tests)

    public func characterForTouch(at x: Float, y: Float,
                                  pressure: Float, pressureFloor: Float = 0.30) -> Character? {
        guard pressure >= pressureFloor else { return nil }
        guard let zone = grid.zone(at: x, y: y) else { return nil }
        return resolve(zone: zone, pressure: pressure)
    }

    // MARK: Private

    private func resolve(zone: KeyZone, pressure: Float) -> Character {
        if pressure >= 0.85 {
            return zone.altCharacter ?? Character(String(zone.character).uppercased())
        } else if pressure >= 0.70 {
            return Character(String(zone.character).uppercased())
        } else {
            return zone.character
        }
    }
}
