// Tests/TouchpadInputCoreTests/UserCalibrationTests.swift
import XCTest
import TouchpadInputCore

// MARK: - UserCalibrationTests

final class UserCalibrationTests: XCTestCase {

    let grid = KeyGrid.default

    // MARK: refine

    func testRefineFirstTapCreatesOffsetWithSampleCountOne() {
        var cal = UserCalibration.empty
        guard let zone = grid.zones.first(where: { $0.character == "q" }) else {
            return XCTFail("Expected 'q' zone in default grid")
        }
        let cx = (zone.xMin + zone.xMax) / 2
        let cy = (zone.yMin + zone.yMax) / 2
        let tapX = cx + 0.01
        let tapY = cy - 0.02

        cal.refine(character: "q", tapX: tapX, tapY: tapY, in: grid)

        let stored = cal.offsets["q"]
        XCTAssertNotNil(stored, "First refine for a key should create an Offset entry")
        XCTAssertEqual(stored?.sampleCount, 1)
        XCTAssertEqual(stored?.dx ?? 0, tapX - cx, accuracy: 1e-6)
        XCTAssertEqual(stored?.dy ?? 0, tapY - cy, accuracy: 1e-6)
    }

    func testRefineConvergesViaEMA() {
        var cal = UserCalibration.empty
        guard let zone = grid.zones.first(where: { $0.character == "f" }) else {
            return XCTFail("Expected 'f' zone in default grid")
        }
        let cx = (zone.xMin + zone.xMax) / 2
        let cy = (zone.yMin + zone.yMax) / 2

        // Seed with a tap at center so first-tap shortcut puts dx=dy=0,
        // then EMA can converge from 0 toward the true offset over many taps.
        cal.refine(character: "f", tapX: cx, tapY: cy, in: grid)
        XCTAssertEqual(cal.offsets["f"]?.dx ?? -1, 0, accuracy: 1e-6)

        let trueDx: Float = 0.03
        let trueDy: Float = -0.02
        for _ in 0..<200 {
            cal.refine(character: "f", tapX: cx + trueDx, tapY: cy + trueDy, in: grid)
        }

        let stored = cal.offsets["f"]
        XCTAssertNotNil(stored)
        // (1 - 0.95^200) ≈ 0.99996 → well within 1e-3 tolerance
        XCTAssertEqual(stored?.dx ?? 0, trueDx, accuracy: 1e-3)
        XCTAssertEqual(stored?.dy ?? 0, trueDy, accuracy: 1e-3)
        XCTAssertEqual(stored?.sampleCount, 201)
    }

    func testRefineIsNoOpForUnknownCharacter() {
        var cal = UserCalibration.empty
        // '~' exists only as an altCharacter on the bottom row; not a primary zone character
        cal.refine(character: "§", tapX: 0.5, tapY: 0.5, in: grid)
        XCTAssertTrue(cal.offsets.isEmpty,
                      "Refining a character that isn't a zone primary should be a no-op")
    }

    // MARK: globalOffset

    func testGlobalOffsetEmptyReturnsZero() {
        let cal = UserCalibration.empty
        let off = cal.globalOffset
        XCTAssertEqual(off.dx, 0, accuracy: 1e-6)
        XCTAssertEqual(off.dy, 0, accuracy: 1e-6)
    }

    func testGlobalOffsetReturnsMedianOfThree() {
        // 3 keys → median index = 1 (after sort). Use unambiguous distinct values.
        let cal = UserCalibration(offsets: [
            "a": .init(dx: -0.05, dy: -0.05, sampleCount: 1),
            "s": .init(dx:  0.02, dy:  0.01, sampleCount: 1),
            "d": .init(dx:  0.10, dy:  0.10, sampleCount: 1),
        ])
        let off = cal.globalOffset
        XCTAssertEqual(off.dx, 0.02, accuracy: 1e-6,
                       "globalOffset.dx should be the middle of the three sorted dx values")
        XCTAssertEqual(off.dy, 0.01, accuracy: 1e-6,
                       "globalOffset.dy should be the middle of the three sorted dy values")
    }
}
