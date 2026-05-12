// Tests/TouchpadInputCoreTests/CharacterEmitterZoneIDTests.swift
import XCTest
import TouchpadInputCore

// MARK: - CharacterEmitterZoneIDTests

final class CharacterEmitterZoneIDTests: XCTestCase {

    let emitter = CharacterEmitter()

    func testBelowPressureFloorReturnsNil() {
        let ch = emitter.character(forZoneID: "q",
                                   pressure: 0.10,
                                   modifiers: [],
                                   pressureFloor: 0.30,
                                   forcePressThreshold: 0.95)
        XCTAssertNil(ch, "Pressure below pressureFloor should return nil")
    }

    func testUnknownZoneIDReturnsNil() {
        let ch = emitter.character(forZoneID: "Ω",
                                   pressure: 0.50,
                                   modifiers: [],
                                   pressureFloor: 0.30,
                                   forcePressThreshold: 0.95)
        XCTAssertNil(ch, "Zone ID that doesn't match any zone should return nil")
    }

    func testNormalPressureNoModifiersReturnsLowercase() {
        let ch = emitter.character(forZoneID: "q",
                                   pressure: 0.50,
                                   modifiers: [],
                                   pressureFloor: 0.30,
                                   forcePressThreshold: 0.95)
        XCTAssertEqual(ch, "q")
    }

    func testShiftModifierReturnsUppercase() {
        let ch = emitter.character(forZoneID: "q",
                                   pressure: 0.50,
                                   modifiers: [.shift],
                                   pressureFloor: 0.30,
                                   forcePressThreshold: 0.95)
        XCTAssertEqual(ch, "Q", "Shift modifier should force uppercase")
    }

    func testForcePressReturnsAltCharacter() {
        // 'q' has altCharacter '1'
        let ch = emitter.character(forZoneID: "q",
                                   pressure: 0.96,
                                   modifiers: [],
                                   pressureFloor: 0.30,
                                   forcePressThreshold: 0.95)
        XCTAssertEqual(ch, "1", "Force-press on 'q' should emit its altCharacter")
    }

    func testForcePressFallsBackToUppercaseWhenNoAlt() {
        // Build a custom grid with a zone that has no altCharacter
        let zone = KeyZone(character: "z", altCharacter: nil,
                           xMin: 0.0, xMax: 1.0, yMin: 0.0, yMax: 1.0)
        let customEmitter = CharacterEmitter(grid: KeyGrid(zones: [zone]))
        let ch = customEmitter.character(forZoneID: "z",
                                         pressure: 0.96,
                                         modifiers: [],
                                         pressureFloor: 0.30,
                                         forcePressThreshold: 0.95)
        XCTAssertEqual(ch, "Z", "With no altCharacter, force-press should fall back to uppercase")
    }
}
