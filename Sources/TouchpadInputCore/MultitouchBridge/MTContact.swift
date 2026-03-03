// Sources/TouchpadInputCore/MultitouchBridge/MTContact.swift
// C-layout struct mirroring MultitouchSupport.framework.
// If finger dots appear in wrong positions the struct layout has drifted —
// file an issue and we'll adjust the padding/field order.

public struct MTVector: Sendable {
    public var x, y: Float
    public init(x: Float, y: Float) { self.x = x; self.y = y }
}

public struct MTPoint: Sendable {
    public var position, velocity: MTVector
    public init(position: MTVector, velocity: MTVector) {
        self.position = position; self.velocity = velocity
    }
}

public struct MTContact: Sendable {
    public var frame:          Int32   // offset 0
    public var timestamp:      Double  // offset 8  (4 bytes padding after frame)
    public var identifier:     Int32   // offset 16 — stable ID for this touch session
    public var state:          Int32   // offset 20 — raw hardware state
    public var fingerId:       Int32   // offset 24
    public var handId:         Int32   // offset 28
    public var normalized:     MTPoint // offset 32 — position + velocity, each 0…1
    public var size:           Float   // offset 48 — contact area
    public var unknown1:       Int32   // offset 52
    public var angle:          Float   // offset 56
    public var majorAxis:      Float   // offset 60
    public var minorAxis:      Float   // offset 64
    public var absoluteVector: MTPoint // offset 68
    public var unknown2:       (Int32, Int32) // offset 84
    public var zDensity:       Float   // offset 92 — pressure-like value

    public init(frame: Int32, timestamp: Double, identifier: Int32, state: Int32,
                fingerId: Int32, handId: Int32, normalized: MTPoint, size: Float,
                unknown1: Int32, angle: Float, majorAxis: Float, minorAxis: Float,
                absoluteVector: MTPoint, unknown2: (Int32, Int32), zDensity: Float) {
        self.frame = frame
        self.timestamp = timestamp
        self.identifier = identifier
        self.state = state
        self.fingerId = fingerId
        self.handId = handId
        self.normalized = normalized
        self.size = size
        self.unknown1 = unknown1
        self.angle = angle
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.absoluteVector = absoluteVector
        self.unknown2 = unknown2
        self.zDensity = zDensity
    }
}
