// Sources/TouchpadInputCore/DefaultImplementations/KeyGrid.swift

// MARK: - KeyZone

public struct KeyZone: Sendable {
    public let character: Character
    public let altCharacter: Character?   // force-press (zDensity ≥ 0.85); nil = uppercase fallback
    public let xMin, xMax: Float
    public let yMin, yMax: Float

    public init(character: Character, altCharacter: Character?,
                xMin: Float, xMax: Float, yMin: Float, yMax: Float) {
        self.character = character
        self.altCharacter = altCharacter
        self.xMin = xMin; self.xMax = xMax
        self.yMin = yMin; self.yMax = yMax
    }
}

// MARK: - KeyGrid

public struct KeyGrid: Sendable {
    public let zones: [KeyZone]

    public init(zones: [KeyZone]) { self.zones = zones }

    public func zone(at x: Float, y: Float) -> KeyZone? {
        zones.first { z in x >= z.xMin && x < z.xMax && y >= z.yMin && y < z.yMax }
    }

    /// Looks up a zone after correcting for the user's global hand-position offset.
    /// Adjusting the tap coordinate (rather than shifting zone boundaries) keeps the grid
    /// perfectly tiled with no overlaps or gaps.
    public func zone(at x: Float, y: Float, calibration: UserCalibration) -> KeyZone? {
        let off = calibration.globalOffset
        return zone(at: x - off.dx, y: y - off.dy)
    }

    public static let `default`: KeyGrid = {
        // 10 columns: xMin for column i = 0.020 + i * 0.096, width 0.096
        let cols: [(xMin: Float, xMax: Float)] = (0..<10).map { i in
            let xMin: Float = 0.020 + Float(i) * 0.096
            return (xMin, xMin + 0.096)
        }

        let topRow:    [Character] = ["q","w","e","r","t","y","u","i","o","p"]
        let homeRow:   [Character] = ["a","s","d","f","g","h","j","k","l",";"]
        let bottomRow: [Character] = ["z","x","c","v","b","n","m",",",".","/"]

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

// MARK: - InputZoneProvider conformance

extension KeyGrid: InputZoneProvider {
    public func zoneID(at x: Float, y: Float) -> String? {
        guard let z = zone(at: x, y: y) else { return nil }
        return String(z.character)
    }

    public func zoneID(at x: Float, y: Float, calibration: UserCalibration) -> String? {
        guard let z = zone(at: x, y: y, calibration: calibration) else { return nil }
        return String(z.character)
    }

    public func label(forZoneID id: String) -> String? { id }
}
