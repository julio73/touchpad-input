// Tests/TouchpadInputCoreTests/DrawingSessionTests.swift
import XCTest
import AppKit
import TouchpadInputCore

// MARK: - DrawingSessionTests

@MainActor
final class DrawingSessionTests: XCTestCase {

    func testNewTouchStartsStroke() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let contact = makeContact(id: 1, x: 0.3, y: 0.4)

            session.update(mtContacts: [contact], timestamp: 1.0)

            XCTAssertEqual(session.strokes.count, 1, "New touchID should start a new stroke")
            XCTAssertEqual(session.strokes[0].points.count, 1)
            XCTAssertEqual(session.liveFingers.count, 1)
            XCTAssertEqual(session.liveFingers[0].phase, "began")
        }
    }

    func testExistingTouchAppendsPoints() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let c1 = makeContact(id: 1, x: 0.3, y: 0.4)
            let c2 = makeContact(id: 1, x: 0.4, y: 0.5)
            let c3 = makeContact(id: 1, x: 0.5, y: 0.6)

            session.update(mtContacts: [c1], timestamp: 1.0)
            session.update(mtContacts: [c2], timestamp: 2.0)
            session.update(mtContacts: [c3], timestamp: 3.0)

            XCTAssertEqual(session.strokes.count, 1, "Same touchID should keep one stroke")
            XCTAssertEqual(session.strokes[0].points.count, 3,
                           "Each frame should append one point to the active stroke")
            XCTAssertEqual(session.liveFingers[0].phase, "moved")
        }
    }

    func testTwoFingersCreateTwoStrokes() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let c1 = makeContact(id: 1, x: 0.3, y: 0.5)
            let c2 = makeContact(id: 2, x: 0.7, y: 0.5)

            session.update(mtContacts: [c1, c2], timestamp: 1.0)

            XCTAssertEqual(session.strokes.count, 2, "Two distinct touchIDs should create two strokes")
            XCTAssertEqual(session.liveFingers.count, 2)
        }
    }

    func testLiftedFingerEndsStrokeAndNewTouchStartsNewStroke() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let c1 = makeContact(id: 1, x: 0.3, y: 0.4)

            session.update(mtContacts: [c1], timestamp: 1.0)
            session.update(mtContacts: [], timestamp: 2.0)

            XCTAssertEqual(session.strokes.count, 1, "Lifting fingers should not remove the stroke")
            XCTAssertTrue(session.liveFingers.isEmpty, "liveFingers should empty when contacts disappear")

            // Reusing same id starts a new stroke (because prevIDs no longer contains it)
            let c2 = makeContact(id: 1, x: 0.7, y: 0.7)
            session.update(mtContacts: [c2], timestamp: 3.0)

            XCTAssertEqual(session.strokes.count, 2,
                           "Touch reappearing after a lift should create a new stroke")
        }
    }

    func testUndoRemovesLastStroke() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let c1 = makeContact(id: 1, x: 0.3, y: 0.4)
            session.update(mtContacts: [c1], timestamp: 1.0)
            session.update(mtContacts: [], timestamp: 2.0)
            let c2 = makeContact(id: 2, x: 0.6, y: 0.6)
            session.update(mtContacts: [c2], timestamp: 3.0)
            session.update(mtContacts: [], timestamp: 4.0)
            XCTAssertEqual(session.strokes.count, 2)

            session.undo()
            XCTAssertEqual(session.strokes.count, 1, "undo should remove the last stroke")

            session.undo()
            XCTAssertEqual(session.strokes.count, 0)
        }
    }

    func testUndoEmptyIsNoOp() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            session.undo()
            XCTAssertTrue(session.strokes.isEmpty, "undo on empty session should be a no-op")
        }
    }

    func testClearEmptiesStrokesAndActiveState() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let c1 = makeContact(id: 1, x: 0.3, y: 0.4)
            session.update(mtContacts: [c1], timestamp: 1.0)
            XCTAssertEqual(session.strokes.count, 1)

            session.clear()
            XCTAssertTrue(session.strokes.isEmpty, "clear should remove all strokes")

            // After clear, even with the same touchID still present, a new stroke starts
            let c2 = makeContact(id: 1, x: 0.4, y: 0.4)
            session.update(mtContacts: [c2], timestamp: 2.0)
            XCTAssertEqual(session.strokes.count, 1,
                           "Continuing touchID after clear should start a fresh stroke")
            XCTAssertEqual(session.strokes[0].points.count, 1,
                           "New stroke after clear should have only the current point")
        }
    }

    func testEndActiveStrokesKeepsStrokesButResetsActiveState() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let c1 = makeContact(id: 1, x: 0.3, y: 0.4)
            session.update(mtContacts: [c1], timestamp: 1.0)
            XCTAssertEqual(session.strokes.count, 1)
            XCTAssertEqual(session.strokes[0].points.count, 1)

            session.endActiveStrokes()

            XCTAssertEqual(session.strokes.count, 1,
                           "endActiveStrokes should keep existing strokes")

            // Same touchID continues — should be treated as a brand-new stroke
            let c2 = makeContact(id: 1, x: 0.35, y: 0.45)
            session.update(mtContacts: [c2], timestamp: 2.0)

            XCTAssertEqual(session.strokes.count, 2,
                           "After endActiveStrokes, same touchID should start a new stroke")
            XCTAssertEqual(session.strokes[1].points.count, 1)
        }
    }

    func testRenderToImageReturnsRequestedSize() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            // Add a stroke with at least 2 points so the renderer exercises its draw path
            let c1 = makeContact(id: 1, x: 0.2, y: 0.2)
            let c2 = makeContact(id: 1, x: 0.8, y: 0.8)
            session.update(mtContacts: [c1], timestamp: 1.0)
            session.update(mtContacts: [c2], timestamp: 2.0)

            let size = CGSize(width: 200, height: 100)
            let image = session.renderToImage(size: size)

            XCTAssertEqual(image.size.width, size.width, accuracy: 0.001)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.001)
        }
    }

    func testRenderToImageWithNoStrokesStillReturnsImage() {
        MainActor.assumeIsolated {
            let session = DrawingSession()
            let size = CGSize(width: 50, height: 50)
            let image = session.renderToImage(size: size)

            XCTAssertEqual(image.size.width, size.width, accuracy: 0.001)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.001)
        }
    }
}
