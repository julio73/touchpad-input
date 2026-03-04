// Tests/TouchpadInputCoreTests/TouchInputSessionTests.swift
import XCTest
import Foundation
import Combine
import TouchpadInputCore

// MARK: - Test helper

func makeContact(
    id: Int32,
    x: Float = 0.5,
    y: Float = 0.5,
    pressure: Float = 0.5,
    size: Float = 0.0,
    state: Int32 = 4,
    vx: Float = 0,
    vy: Float = 0
) -> MTContact {
    let posVec = MTVector(x: x, y: y)
    let velVec = MTVector(x: vx, y: vy)
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
        size: size,
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
            let session = TouchInputSession()
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
            let session = TouchInputSession()
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
            let session = TouchInputSession()
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
            let session = TouchInputSession()
            let contact1 = makeContact(id: 1, x: 0.5, y: 0.5)
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
            let session = TouchInputSession()
            let contact = makeContact(id: 42)
            session.update(mtContacts: [contact], timestamp: 1.0)

            XCTAssertEqual(session.liveFingers.count, 1)
            XCTAssertEqual(session.liveFingers[0].label, "#1")
        }
    }

    func testSecondContactGetsLabel2() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
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
            let session = TouchInputSession()
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
            let session = TouchInputSession()
            let contact = makeContact(id: 1)
            session.update(mtContacts: [contact], timestamp: 1.0)

            session.clearAll()

            XCTAssertTrue(session.liveFingers.isEmpty, "liveFingers should be empty after clearAll")
            XCTAssertTrue(session.eventLog.isEmpty, "eventLog should be empty after clearAll")

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
            let session = TouchInputSession()

            for i in 0..<600 {
                let x = Float(i) * 0.001
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
        let zone = grid.zone(at: 0.05, y: 0.80)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, "q")
    }

    func testHomeRowLookup() {
        let zone = grid.zone(at: 0.05, y: 0.50)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, "a")
    }

    func testBottomRowLookup() {
        let zone = grid.zone(at: 0.05, y: 0.20)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, "z")
    }

    func testSpaceBarLookup() {
        let zone = grid.zone(at: 0.50, y: 0.04)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone?.character, " ")
    }

    func testMarginMiss() {
        let zone = grid.zone(at: 0.01, y: 0.50)
        XCTAssertNil(zone, "Touch in left margin should not match any zone")
    }
}

// MARK: - CharacterEmitterTests

final class CharacterEmitterTests: XCTestCase {

    let emitter = CharacterEmitter()

    func testLowPressureEmitsNil() {
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.10)
        XCTAssertNil(ch, "Pressure below threshold should emit nil")
    }

    func testNormalPressureEmitsLowercase() {
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.40)
        XCTAssertEqual(ch, "q")
    }

    func testFirmPressureEmitsUppercase() {
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.75)
        XCTAssertEqual(ch, "Q")
    }

    func testMissZoneEmitsNil() {
        let ch = emitter.characterForTouch(at: 0.01, y: 0.50, pressure: 0.50)
        XCTAssertNil(ch, "Touch outside any zone should emit nil")
    }
}

// MARK: - ForcePressTests

final class ForcePressTests: XCTestCase {

    let emitter = CharacterEmitter()

    func testForcePressEmitsAltChar() {
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.90)
        XCTAssertEqual(ch, "1")
    }

    func testForcePressSpaceEmitsNewline() {
        let ch = emitter.characterForTouch(at: 0.50, y: 0.04, pressure: 0.90)
        XCTAssertEqual(ch, "\n")
    }

    func testForcePressHomeRowAlt() {
        let ch = emitter.characterForTouch(at: 0.05, y: 0.50, pressure: 0.88)
        XCTAssertEqual(ch, "!")
    }

    func testBoundaryJustBelowForcePressIsUppercase() {
        let ch = emitter.characterForTouch(at: 0.05, y: 0.80, pressure: 0.84)
        XCTAssertEqual(ch, "Q")
    }
}

// MARK: - ModifierHoldTests

@MainActor
final class ModifierHoldTests: XCTestCase {

    func testShiftHoldForcesUppercase() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            let shiftFinger = makeContact(id: 1, x: 0.02, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [shiftFinger], timestamp: 1.0)
            XCTAssertTrue(session.outputBuffer.isEmpty, "Shift zone tap should not emit a char")

            let qFinger = makeContact(id: 2, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [shiftFinger, qFinger], timestamp: 2.0)

            XCTAssertEqual(session.outputBuffer, "Q",
                           "Shift-hold should force uppercase despite low pressure")
            XCTAssertTrue(session.activeModifiers.contains(.shift))
        }
    }

    func testDeleteHoldRemovesLastChar() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            let qFinger = makeContact(id: 1, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [qFinger], timestamp: 1.0)
            XCTAssertEqual(session.outputBuffer, "q")

            let delFinger = makeContact(id: 2, x: 0.97, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [delFinger], timestamp: 2.0)
            XCTAssertEqual(session.outputBuffer, "q", "Delete zone tap alone should not remove char yet")

            let anyFinger = makeContact(id: 3, x: 0.50, y: 0.50, pressure: 0.40)
            session.update(mtContacts: [delFinger, anyFinger], timestamp: 3.0)

            XCTAssertEqual(session.outputBuffer, "",
                           "Delete-hold + any tap should remove last char")
            XCTAssertTrue(session.activeModifiers.contains(.delete))
        }
    }

    func testModifierZoneTapDoesNotEmitChar() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            let shiftFinger = makeContact(id: 1, x: 0.02, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [shiftFinger], timestamp: 1.0)
            XCTAssertTrue(session.outputBuffer.isEmpty,
                          "Tapping a modifier zone should not emit any character")
        }
    }

    func testClearAllResetsModifiers() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            let shiftFinger = makeContact(id: 1, x: 0.02, y: 0.05, pressure: 0.5)
            session.update(mtContacts: [shiftFinger], timestamp: 1.0)
            session.update(mtContacts: [shiftFinger], timestamp: 2.0)
            XCTAssertTrue(session.activeModifiers.contains(.shift))

            session.clearAll()
            XCTAssertTrue(session.activeModifiers.isEmpty, "clearAll should reset activeModifiers")
        }
    }
}

// MARK: - StabilityTests

@MainActor
final class StabilityTests: XCTestCase {

    func testSmallContactDoesNotEmit() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            session.minContactSize = 0.30
            let contact = makeContact(id: 1, x: 0.05, y: 0.80, pressure: 0.40, size: 0.10)
            session.update(mtContacts: [contact], timestamp: 1.0)
            XCTAssertTrue(session.outputBuffer.isEmpty, "Contact below min size should not emit")
        }
    }

    func testLargeContactEmits() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            session.minContactSize = 0.30
            let contact = makeContact(id: 1, x: 0.05, y: 0.80, pressure: 0.40, size: 0.50)
            session.update(mtContacts: [contact], timestamp: 1.0)
            XCTAssertEqual(session.outputBuffer, "q", "Contact above min size should emit")
        }
    }

    func testZoneCooldownPreventsRapidRepeat() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            session.zoneCooldownMs = 200.0

            let c1 = makeContact(id: 1, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [c1], timestamp: 1.000)
            session.update(mtContacts: [], timestamp: 1.050)

            let c2 = makeContact(id: 2, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [c2], timestamp: 1.100)

            XCTAssertEqual(session.outputBuffer, "q",
                           "Second tap within cooldown should be suppressed")
        }
    }

    func testZoneCooldownAllowsAfterExpiry() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()
            session.zoneCooldownMs = 100.0

            let c1 = makeContact(id: 1, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [c1], timestamp: 1.000)
            session.update(mtContacts: [], timestamp: 1.050)

            let c2 = makeContact(id: 2, x: 0.05, y: 0.80, pressure: 0.40)
            session.update(mtContacts: [c2], timestamp: 1.200)

            XCTAssertEqual(session.outputBuffer, "qq",
                           "Second tap after cooldown expiry should emit")
        }
    }
}

// MARK: - SwipeDeleteTests

@MainActor
final class SwipeDeleteTests: XCTestCase {

    func testTwoFingerSwipeLeftDeletesCurrentWord() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()

            // Type "hello wo" via taps (individual single-finger contacts)
            for (i, ch) in "hello wo".enumerated() {
                guard let zone = KeyGrid.default.zones.first(where: { $0.character == ch }) else { continue }
                let cx = (zone.xMin + zone.xMax) / 2
                let cy = (zone.yMin + zone.yMax) / 2
                let c = makeContact(id: Int32(100 + i), x: cx, y: cy, pressure: 0.45)
                session.update(mtContacts: [c], timestamp: Double(i) * 0.5)
                session.update(mtContacts: [], timestamp: Double(i) * 0.5 + 0.1)
            }
            XCTAssertEqual(session.outputBuffer, "hello wo")

            // Two-finger swipe left: both fingers have velocity well below threshold (-1.5)
            let swipe1 = makeContact(id: 10, x: 0.4, y: 0.5, pressure: 0.1, vx: -3.0)
            let swipe2 = makeContact(id: 11, x: 0.6, y: 0.5, pressure: 0.1, vx: -3.0)
            session.update(mtContacts: [swipe1, swipe2], timestamp: 10.0)

            XCTAssertEqual(session.outputBuffer, "hello ",
                           "Swipe-left should delete the partial word 'wo', leaving 'hello '")
        }
    }

    func testTwoFingerSwipeLeftCooldownPreventsDoubleDelete() {
        MainActor.assumeIsolated {
            let session = TouchInputSession()

            // Type "hello world"
            for (i, ch) in "hello world".enumerated() {
                guard let zone = KeyGrid.default.zones.first(where: { $0.character == ch }) else { continue }
                let cx = (zone.xMin + zone.xMax) / 2
                let cy = (zone.yMin + zone.yMax) / 2
                let c = makeContact(id: Int32(100 + i), x: cx, y: cy, pressure: 0.45)
                session.update(mtContacts: [c], timestamp: Double(i) * 0.5)
                session.update(mtContacts: [], timestamp: Double(i) * 0.5 + 0.1)
            }
            XCTAssertEqual(session.outputBuffer, "hello world")

            // First swipe frame
            let s1 = makeContact(id: 10, x: 0.4, y: 0.5, pressure: 0.1, vx: -3.0)
            let s2 = makeContact(id: 11, x: 0.6, y: 0.5, pressure: 0.1, vx: -3.0)
            session.update(mtContacts: [s1, s2], timestamp: 10.0)
            XCTAssertEqual(session.outputBuffer, "hello ")

            // Second swipe frame 50ms later — within 300ms cooldown, should NOT fire again
            session.update(mtContacts: [s1, s2], timestamp: 10.050)
            XCTAssertEqual(session.outputBuffer, "hello ",
                           "Swipe within cooldown window should not fire a second deleteWord")
        }
    }
}
