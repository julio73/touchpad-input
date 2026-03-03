// Sources/TouchpadInputCore/DefaultImplementations/CornerModifierStrategy.swift

// MARK: - ModifierZone (concrete type for UI drawing)

public struct ModifierZone: Sendable {
    public let kind: AnyModifierKind
    public let label: String
    public let xMin, xMax: Float
    public let yMin, yMax: Float

    public init(kind: AnyModifierKind, label: String,
                xMin: Float, xMax: Float, yMin: Float, yMax: Float) {
        self.kind = kind; self.label = label
        self.xMin = xMin; self.xMax = xMax
        self.yMin = yMin; self.yMax = yMax
    }

    public func contains(x: Float, y: Float) -> Bool {
        x >= xMin && x < xMax && y >= yMin && y < yMax
    }

    /// Bottom-left corner = Shift hold; bottom-right corner = Delete hold.
    /// 15% wide × 15% tall — large enough for a thumb to rest reliably.
    public static let all: [ModifierZone] = [
        ModifierZone(kind: .shift,  label: "⇧",
                     xMin: 0.00, xMax: 0.15, yMin: 0.00, yMax: 0.15),
        ModifierZone(kind: .delete, label: "⌫",
                     xMin: 0.85, xMax: 1.00, yMin: 0.00, yMax: 0.15),
    ]
}

// MARK: - CornerModifierStrategy

/// Default modifier strategy: bottom-left corner = Shift, bottom-right corner = Delete.
public struct CornerModifierStrategy: ModifierStrategy {
    public static let `default` = CornerModifierStrategy()

    public init() {}

    public func modifierKind(at x: Float, y: Float) -> AnyModifierKind? {
        for zone in ModifierZone.all {
            if zone.contains(x: x, y: y) { return zone.kind }
        }
        return nil
    }

    public var zoneLabels: [AnyModifierKind: String] {
        Dictionary(uniqueKeysWithValues: ModifierZone.all.map { ($0.kind, $0.label) })
    }
}
