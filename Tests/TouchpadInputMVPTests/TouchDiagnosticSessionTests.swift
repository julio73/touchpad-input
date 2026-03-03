// Tests/TouchpadInputMVPTests/TouchDiagnosticSessionTests.swift
// No AppKit or SwiftUI — Foundation + Combine are sufficient on macOS.

import XCTest
import Foundation
import Combine

// MARK: - Test-local type redefinitions (copied from TouchpadInputCore.swift)
// These mirror the production types exactly, without any UI framework imports.

struct MTVector { var x, y: Float }
struct MTPoint  { var position, velocity: MTVector }
struct MTContact {
    var frame:          Int32
    var timestamp:      Double
    var identifier:     Int32
    var state:          Int32
    var fingerId:       Int32
    var handId:         Int32
    var normalized:     MTPoint
    var size:           Float
    var unknown1:       Int32
    var angle:          Float
    var majorAxis:      Float
    var minorAxis:      Float
    var absoluteVector: MTPoint
    var unknown2:       (Int32, Int32)
    var zDensity:       Float
}

struct KeyZone {
    let character: Character
    let altCharacter: Character?
    let xMin, xMax: Float
    let yMin, yMax: Float
}

struct KeyGrid {
    let zones: [KeyZone]

    func zone(at x: Float, y: Float) -> KeyZone? {
        zones.first { z in x >= z.xMin && x < z.xMax && y >= z.yMin && y < z.yMax }
    }

    static let `default`: KeyGrid = {
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
        zones.append(KeyZone(character: " ", altCharacter: "\n",
                             xMin: 0.02, xMax: 0.98,
                             yMin: 0.00, yMax: 0.08))
        return KeyGrid(zones: zones)
    }()
}

enum ModifierKind: Hashable { case shift, delete }

struct ModifierZone {
    let kind: ModifierKind
    let label: String
    let xMin, xMax: Float
    let yMin, yMax: Float

    func contains(x: Float, y: Float) -> Bool {
        x >= xMin && x < xMax && y >= yMin && y < yMax
    }

    static let all: [ModifierZone] = [
        ModifierZone(kind: .shift,  label: "⇧", xMin: 0.00, xMax: 0.15, yMin: 0.00, yMax: 0.15),
        ModifierZone(kind: .delete, label: "⌫", xMin: 0.85, xMax: 1.00, yMin: 0.00, yMax: 0.15),
    ]
}

final class CharacterEmitter {
    let grid: KeyGrid

    init(grid: KeyGrid = .default) { self.grid = grid }

    func characterForTouch(at x: Float, y: Float, pressure: Float) -> Character? {
        guard pressure >= 0.30 else { return nil }
        guard let zone = grid.zone(at: x, y: y) else { return nil }
        if pressure >= 0.85 {
            return zone.altCharacter ?? Character(String(zone.character).uppercased())
        } else if pressure >= 0.70 {
            return Character(String(zone.character).uppercased())
        } else {
            return zone.character
        }
    }
}

struct FingerState: Identifiable {
    let id: String
    let label: String
    let x: CGFloat
    let y: CGFloat
    let pressure: CGFloat
    let phase: String
    let lastEventTime: TimeInterval
    let deltaMsFromPrev: Int?
}

struct TouchLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let fingerLabel: String
    let phase: String
    let x: CGFloat
    let y: CGFloat
    let pressure: CGFloat
    let deltaMs: Int?
    let rawState: Int32
}

@MainActor
final class TouchDiagnosticSession: ObservableObject {
    @Published var liveFingers: [FingerState] = []
    @Published var eventLog: [TouchLogEntry] = []
    @Published var isActive: Bool = false
    @Published var outputBuffer: String = ""
    @Published var activeModifiers: Set<ModifierKind> = []

    private let emitter = CharacterEmitter()
    private let modifierZones = ModifierZone.all
    private var fingerLabels: [String: String] = [:]
    private var fingerLastTime: [String: TimeInterval] = [:]
    private var labelCounter = 0
    private let maxLogEntries = 500

    func update(mtContacts contacts: [MTContact], timestamp: Double) {
        let heldModifiers: Set<ModifierKind> = Set(
            modifierZones.compactMap { mz in
                liveFingers.contains { mz.contains(x: Float($0.x), y: Float($0.y)) }
                    ? mz.kind : nil
            }
        )

        let currentIDs = Set(contacts.map { String($0.identifier) })
        var liveLookup: [String: FingerState] = Dictionary(
            uniqueKeysWithValues: liveFingers.map { ($0.id, $0) }
        )
        var emittedZoneKeys: Set<String> = []

        // Synthesize "ended" for fingers that disappeared from the frame
        for id in Set(liveLookup.keys).subtracting(currentIDs) {
            if let prev = liveLookup[id] {
                appendLog(TouchLogEntry(
                    timestamp: Date(), fingerLabel: prev.label,
                    phase: "ended", x: prev.x, y: prev.y,
                    pressure: prev.pressure, deltaMs: nil, rawState: -1
                ))
            }
            liveLookup.removeValue(forKey: id)
            fingerLastTime.removeValue(forKey: id)
        }

        // Update active contacts
        for contact in contacts {
            let rawID = String(contact.identifier)
            let isNew = liveLookup[rawID] == nil

            if fingerLabels[rawID] == nil {
                labelCounter += 1
                fingerLabels[rawID] = "#\(labelCounter)"
            }
            let label = fingerLabels[rawID]!

            let deltaMs: Int?
            if let prev = fingerLastTime[rawID] {
                deltaMs = max(0, Int((timestamp - prev) * 1000))
            } else {
                deltaMs = nil
            }

            let x = CGFloat(contact.normalized.position.x)
            let y = CGFloat(contact.normalized.position.y)
            let pressure = CGFloat(min(max(contact.zDensity, 0), 1))

            let phase: String
            if isNew {
                phase = "began"
            } else if let prev = liveLookup[rawID],
                      abs(prev.x - x) < 0.0005 && abs(prev.y - y) < 0.0005 {
                phase = "stationary"
            } else {
                phase = "moved"
            }

            if phase == "began" {
                let fx = Float(x), fy = Float(y)
                let isInUnheldModifierZone = modifierZones.contains { mz in
                    !heldModifiers.contains(mz.kind) && mz.contains(x: fx, y: fy)
                }
                if !isInUnheldModifierZone {
                    if heldModifiers.contains(.delete) {
                        if !outputBuffer.isEmpty { outputBuffer.removeLast() }
                    } else if let zone = emitter.grid.zone(at: fx, y: fy) {
                        let key = "\(zone.xMin)-\(zone.yMin)"
                        if !emittedZoneKeys.contains(key) {
                            emittedZoneKeys.insert(key)
                            var effectivePressure = Float(pressure)
                            if heldModifiers.contains(.shift),
                               effectivePressure >= 0.30, effectivePressure < 0.70 {
                                effectivePressure = 0.70
                            }
                            if let ch = emitter.characterForTouch(at: fx, y: fy, pressure: effectivePressure) {
                                outputBuffer.append(ch)
                            }
                        }
                    }
                }
            }

            if phase != "stationary" {
                appendLog(TouchLogEntry(
                    timestamp: Date(), fingerLabel: label,
                    phase: phase, x: x, y: y,
                    pressure: pressure, deltaMs: deltaMs,
                    rawState: contact.state
                ))
            }

            fingerLastTime[rawID] = timestamp
            liveLookup[rawID] = FingerState(
                id: rawID, label: label,
                x: x, y: y, pressure: pressure,
                phase: phase, lastEventTime: timestamp,
                deltaMsFromPrev: deltaMs
            )
        }

        liveFingers = Array(liveLookup.values).sorted { $0.label < $1.label }
        activeModifiers = heldModifiers
    }

    func clearAll() {
        eventLog = []
        liveFingers = []
        outputBuffer = ""
        activeModifiers = []
        fingerLabels = [:]
        fingerLastTime = [:]
        labelCounter = 0
    }

    private func appendLog(_ entry: TouchLogEntry) {
        eventLog.append(entry)
        if eventLog.count > maxLogEntries {
            eventLog.removeFirst(eventLog.count - maxLogEntries)
        }
    }
}

// MARK: - Helper

/// Constructs an MTContact with zero-filled fields except the ones specified.
func makeContact(
    id: Int32,
    x: Float = 0.5,
    y: Float = 0.5,
    pressure: Float = 0.5,
    state: Int32 = 4
) -> MTContact {
    let posVec = MTVector(x: x, y: y)
    let velVec = MTVector(x: 0, y: 0)
    let normalized = MTPoint(position: posVec, velocity: velVec)
    let absVec = MTVector(x: 0, y: 0)
    let absoluteVector = MTPoint(position: absVec, velocity: absVec)
    return MTContact(
        frame: 0,
        timestamp: 0,
        identifier: id,
        state: state,
        fingerId: 0,
        handId: 0,
        normalized: normalized,
        size: 0,
        unknown1: 0,
        angle: 0,
        majorAxis: 0,
        minorAxis: 0,
        absoluteVector: absoluteVector,
        unknown2: (0, 0),
        zDensity: pressure
    )
}

// MARK: - PhaseDetectionTests

@MainActor
final class PhaseDetectionTests: XCTestCase {

    func testNewContactIsBeganPhase() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact = makeContact(id: 1, x: 0.3, y: 0.4)
            session.update(mtContacts: [contact], timestamp: 1.0)

            XCTAssertEqual(session.liveFingers.count, 1)
            XCTAssertEqual(session.liveFingers[0].phase, "began")

            let beganEntries = session.eventLog.filter { $0.phase == "began" }
            XCTAssertEqual(beganEntries.count, 1, "Expected exactly one 'began' log entry")
        }
    }

    func testSamePositionIsStationary() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact = makeContact(id: 1, x: 0.5, y: 0.5)

            session.update(mtContacts: [contact], timestamp: 1.0)
            let logCountAfterFirst = session.eventLog.count

            session.update(mtContacts: [contact], timestamp: 2.0)

            XCTAssertEqual(session.liveFingers.count, 1)
            XCTAssertEqual(session.liveFingers[0].phase, "stationary")
            XCTAssertEqual(
                session.eventLog.count, logCountAfterFirst,
                "Stationary phase should not add a log entry"
            )
        }
    }

    func testMovedPosition() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact1 = makeContact(id: 1, x: 0.5, y: 0.5)
            let contact2 = makeContact(id: 1, x: 0.51, y: 0.5)

            session.update(mtContacts: [contact1], timestamp: 1.0)
            session.update(mtContacts: [contact2], timestamp: 2.0)

            XCTAssertEqual(session.liveFingers[0].phase, "moved")
            let movedEntries = session.eventLog.filter { $0.phase == "moved" }
            XCTAssertEqual(movedEntries.count, 1, "Expected exactly one 'moved' log entry")
        }
    }

    func testSmallMovementIsStationary() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact1 = makeContact(id: 1, x: 0.5, y: 0.5)
            // 0.0001 < 0.0005 threshold
            let contact2 = makeContact(id: 1, x: 0.5001, y: 0.5)

            session.update(mtContacts: [contact1], timestamp: 1.0)
            let logCountAfterFirst = session.eventLog.count

            session.update(mtContacts: [contact2], timestamp: 2.0)

            XCTAssertEqual(session.liveFingers[0].phase, "stationary")
            XCTAssertEqual(
                session.eventLog.count, logCountAfterFirst,
                "Sub-threshold movement should not add a log entry"
            )
        }
    }
}

// MARK: - FingerLifecycleTests

@MainActor
final class FingerLifecycleTests: XCTestCase {

    func testFirstContactGetsLabel1() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact = makeContact(id: 42)
            session.update(mtContacts: [contact], timestamp: 1.0)

            XCTAssertEqual(session.liveFingers.count, 1)
            XCTAssertEqual(session.liveFingers[0].label, "#1")
        }
    }

    func testSecondContactGetsLabel2() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact1 = makeContact(id: 1, x: 0.3, y: 0.5)
            let contact2 = makeContact(id: 2, x: 0.7, y: 0.5)
            session.update(mtContacts: [contact1, contact2], timestamp: 1.0)

            XCTAssertEqual(session.liveFingers.count, 2)
            let labels = Set(session.liveFingers.map { $0.label })
            XCTAssertTrue(labels.contains("#1"), "Expected label #1")
            XCTAssertTrue(labels.contains("#2"), "Expected label #2")
        }
    }

    func testDisappearedContactSynthesizesEnded() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact = makeContact(id: 1)

            session.update(mtContacts: [contact], timestamp: 1.0)
            session.update(mtContacts: [], timestamp: 2.0)

            let endedEntries = session.eventLog.filter { $0.phase == "ended" }
            XCTAssertEqual(endedEntries.count, 1, "Expected one 'ended' entry when contact disappears")
            XCTAssertTrue(session.liveFingers.isEmpty)
        }
    }

    func testClearAllResetsState() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            let contact = makeContact(id: 1)
            session.update(mtContacts: [contact], timestamp: 1.0)

            session.clearAll()

            XCTAssertTrue(session.liveFingers.isEmpty, "liveFingers should be empty after clearAll")
            XCTAssertTrue(session.eventLog.isEmpty, "eventLog should be empty after clearAll")

            // After clearAll, a new contact should receive label "#1" again
            let newContact = makeContact(id: 99)
            session.update(mtContacts: [newContact], timestamp: 2.0)
            XCTAssertEqual(session.liveFingers[0].label, "#1", "Label counter should reset to #1 after clearAll")
        }
    }
}

// MARK: - LogCapTests

@MainActor
final class LogCapTests: XCTestCase {

    func testLogCappedAt500() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()

            // First call — "began" (logged)
            // Subsequent 599 calls — move x by a small but above-threshold amount each time
            // so every call after the first produces a "moved" entry.
            // Total logged = 1 (began) + 599 (moved) = 600, but capped at 500.
            for i in 0..<600 {
                let x = Float(i) * 0.001          // each step is 0.001 > 0.0005 threshold
                let contact = makeContact(id: 1, x: min(x, 0.999), y: 0.5)
                session.update(mtContacts: [contact], timestamp: Double(i))
            }

            XCTAssertEqual(session.eventLog.count, 500, "Event log should be capped at 500 entries")
        }
    }
}

// MARK: - KeyGridTests

final class KeyGridTests: XCTestCase {

    let grid = KeyGrid.default

    func testTopRowLookup() {
        // x=0.05 → column 0 [0.020, 0.116); y=0.80 → top row [0.65, 1.0) → Q
        let zone = grid.zone(at: 0.05, y: 0.80)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, "q")
    }

    func testHomeRowLookup() {
        // x=0.05 → column 0; y=0.50 → home row [0.30, 0.65) → A
        let zone = grid.zone(at: 0.05, y: 0.50)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, "a")
    }

    func testBottomRowLookup() {
        // x=0.05 → column 0; y=0.20 → bottom row [0.08, 0.30) → Z
        let zone = grid.zone(at: 0.05, y: 0.20)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, "z")
    }

    func testSpaceBarLookup() {
        // x=0.50 ∈ [0.02, 0.98); y=0.04 ∈ [0.00, 0.08) → space
        let zone = grid.zone(at: 0.50, y: 0.04)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, " ")
    }

    func testMarginMiss() {
        // x=0.01 < 0.020 left margin → no zone
        let zone = grid.zone(at: 0.01, y: 0.50)
        XCTAssertNil(zone, "Touch in left margin should not match any zone")
    }
}

// MARK: - CharacterEmitterTests

final class CharacterEmitterTests: XCTestCase {

    let emitter = CharacterEmitter()

    func testLowPressureEmitsNil() {
        // pressure < 0.30 → below threshold
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.10)
        XCTAssertNil(ch, "Pressure below threshold should emit nil")
    }

    func testNormalPressureEmitsLowercase() {
        // pressure=0.40 at Q zone → "q"
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.40)
        XCTAssertEqual(ch, "q")
    }

    func testFirmPressureEmitsUppercase() {
        // pressure=0.75 at Q zone → "Q"
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.75)
        XCTAssertEqual(ch, "Q")
    }

    func testMissZoneEmitsNil() {
        // x=0.01 is in left margin → no zone → nil regardless of pressure
        let ch = emitter.characterForTouch(at: 0.01, y: 0.50, pressure: 0.50)
        XCTAssertNil(ch, "Touch outside any zone should emit nil")
    }
}

// MARK: - ForcePressTests

final class ForcePressTests: XCTestCase {

    let emitter = CharacterEmitter()

    func testForcePressEmitsAltChar() {
        // Q zone (x=0.05, y=0.80), force-press → alt char "1"
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.90)
        XCTAssertEqual(ch, "1")
    }

    func testForcePressSpaceEmitsNewline() {
        // Space zone (x=0.50, y=0.04), force-press → "\n"
        let ch = emitter.characterForTouch(at: 0.50, y: 0.04, pressure: 0.90)
        XCTAssertEqual(ch, "\n")
    }

    func testForcePressHomeRowAlt() {
        // A zone (x=0.05, y=0.50), force-press → "!"
        let ch = emitter.characterForTouch(at: 0.05, y: 0.50, pressure: 0.88)
        XCTAssertEqual(ch, "!")
    }

    func testBoundaryJustBelowForcePressIsUppercase() {
        // pressure=0.84 is still uppercase range, not force-press → "Q"
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.84)
        XCTAssertEqual(ch, "Q")
    }
}

// MARK: - ModifierHoldTests

@MainActor
final class ModifierHoldTests: XCTestCase {

    func testShiftHoldForcesUppercase() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            // Frame 1: place finger in shift zone (bottom-left: x=0.02, y=0.05)
            let shiftFinger = makeContact(id: 1, x: 0.02, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [shiftFinger], timestamp: 1.0)
            XCTAssertTrue(session.outputBuffer.isEmpty, "Shift zone tap should not emit a char")

            // Frame 2: shift finger stationary + low-pressure tap at Q (x=0.05, y=0.80)
            let qFinger = makeContact(id: 2, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [shiftFinger, qFinger], timestamp: 2.0)

            XCTAssertEqual(session.outputBuffer, "Q",
                           "Shift-hold should force uppercase despite low pressure")
            XCTAssertTrue(session.activeModifiers.contains(.shift))
        }
    }

    func testDeleteHoldRemovesLastChar() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            // Frame 1: type "q"
            let qFinger = makeContact(id: 1, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [qFinger], timestamp: 1.0)
            XCTAssertEqual(session.outputBuffer, "q")

            // Frame 2: release q, place finger in delete zone (bottom-right: x=0.97, y=0.05)
            let delFinger = makeContact(id: 2, x: 0.97, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [delFinger], timestamp: 2.0)
            XCTAssertEqual(session.outputBuffer, "q", "Delete zone tap alone should not remove char yet")

            // Frame 3: delete finger stationary + new tap anywhere → should remove "q"
            let anyFinger = makeContact(id: 3, x: 0.50, y: 0.50, pressure: 0.40)
            session.update(mtContacts: [delFinger, anyFinger], timestamp: 3.0)

            XCTAssertEqual(session.outputBuffer, "",
                           "Delete-hold + any tap should remove last char")
            XCTAssertTrue(session.activeModifiers.contains(.delete))
        }
    }

    func testModifierZoneTapDoesNotEmitChar() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            // Touching the shift zone directly should not produce output
            let shiftFinger = makeContact(id: 1, x: 0.02, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [shiftFinger], timestamp: 1.0)
            XCTAssertTrue(session.outputBuffer.isEmpty,
                          "Tapping a modifier zone should not emit any character")
        }
    }

    func testClearAllResetsModifiers() {
        MainActor.assumeIsolated {
            let session = TouchDiagnosticSession()
            // Simulate modifier being active by placing finger in shift zone for two frames
            let shiftFinger = makeContact(id: 1, x: 0.02, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [shiftFinger], timestamp: 1.0)
            session.update(mtContacts: [shiftFinger], timestamp: 2.0)
            XCTAssertTrue(session.activeModifiers.contains(.shift))

            session.clearAll()
            XCTAssertTrue(session.activeModifiers.isEmpty, "clearAll should reset activeModifiers")
        }
    }
}
