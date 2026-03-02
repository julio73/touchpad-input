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

    private var fingerLabels: [String: String] = [:]
    private var fingerLastTime: [String: TimeInterval] = [:]
    private var labelCounter = 0
    private let maxLogEntries = 500

    func update(mtContacts contacts: [MTContact], timestamp: Double) {
        let currentIDs = Set(contacts.map { String($0.identifier) })
        var liveLookup: [String: FingerState] = Dictionary(
            uniqueKeysWithValues: liveFingers.map { ($0.id, $0) }
        )

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
    }

    func clearAll() {
        eventLog = []
        liveFingers = []
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
