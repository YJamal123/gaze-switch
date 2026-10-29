import CoreGraphics
import Foundation
import XCTest
@testable import GazeSwitchCore

final class LinearModelTests: XCTestCase {
    func testRecoversLinearRelation() throws {
        let inputs = (0..<50).map { i in [Double(i % 7), Double(i % 5) * 2] }
        let outputs = inputs.map { [3 + 2 * $0[0] - $0[1]] }
        let model = try XCTUnwrap(LinearModel.fit(inputs: inputs, outputs: outputs, lambda: 0))
        XCTAssertEqual(model.predict([4, 6])[0], 5, accuracy: 1e-3)
    }

    func testConstantFeatureDoesNotBreakFit() throws {
        let inputs = (0..<20).map { [Double($0), 1.0] }
        let model = try XCTUnwrap(LinearModel.fit(inputs: inputs, outputs: inputs.map { [$0[0] * 10] }, lambda: 0))
        XCTAssertEqual(model.predict([3, 1])[0], 30, accuracy: 1e-3)
    }

    func testNeedsMoreSamplesThanFeatures() {
        XCTAssertNil(LinearModel.fit(inputs: [[1, 2]], outputs: [[1]]))
    }
}

final class GazeModelTests: XCTestCase {
    let left = DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600), name: "Left")
    let right = DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 600), name: "Right")

    /// Synthetic features where head yaw maps straight to x and pitch to y.
    func features(for p: CGPoint) -> [Double] {
        [p.x / 1000, p.y / 1000, p.x / 2000, 0, 0, 0]
    }

    func model() throws -> GazeModel {
        var samples: [CalibrationSample] = []
        for d in [left, right] {
            for fx in [0.1, 0.5, 0.9] {
                for fy in [0.1, 0.5, 0.9] {
                    let p = CGPoint(x: d.frame.minX + fx * d.frame.width, y: d.frame.minY + fy * d.frame.height)
                    for _ in 0..<3 { samples.append(CalibrationSample(features: features(for: p), target: p, displayID: d.id)) }
                }
            }
        }
        return try XCTUnwrap(GazeModel.fit(samples: samples, displays: [left, right], lambda: 0))
    }

    func testPicksDisplayAndPoint() throws {
        let m = try model()
        let p = try XCTUnwrap(m.predict(features(for: CGPoint(x: 1250, y: 300))))
        XCTAssertEqual(p.displayID, 2)
        XCTAssertEqual(p.point.x, 1250, accuracy: 1)
        XCTAssertEqual(p.point.y, 300, accuracy: 1)
    }

    func testJustPastTheEdgeStillCounts() throws {
        let p = try XCTUnwrap(try model().predict(features(for: CGPoint(x: 500, y: 650))))
        XCTAssertEqual(p.displayID, 1)
        XCTAssertEqual(p.point.y, 599)
    }

    func testFarBelowIsAway() throws {
        XCTAssertNil(try model().predict(features(for: CGPoint(x: 500, y: 1200))))
    }

    func testAccuracyOnCleanData() throws {
        for a in try model().accuracy() {
            XCTAssertEqual(a.displayHitRate, 1)
            XCTAssertLessThan(a.horizontalError, 0.01)
        }
    }

    func testRoundTripsThroughJSON() throws {
        let m = try model()
        let decoded = try JSONDecoder().decode(GazeModel.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(decoded.predict(features(for: CGPoint(x: 300, y: 200))), m.predict(features(for: CGPoint(x: 300, y: 200))))
    }
}

final class FocusTests: XCTestCase {
    func testTopWindowPrefersFront() {
        let back = WindowInfo(id: 1, pid: 1, owner: "A", title: "", frame: CGRect(x: 0, y: 0, width: 800, height: 800))
        let front = WindowInfo(id: 2, pid: 2, owner: "B", title: "", frame: CGRect(x: 400, y: 0, width: 400, height: 800))
        XCTAssertEqual(topWindow(at: CGPoint(x: 500, y: 10), in: [front, back])?.id, 2)
        XCTAssertEqual(topWindow(at: CGPoint(x: 100, y: 10), in: [front, back])?.id, 1)
        XCTAssertNil(topWindow(at: CGPoint(x: 900, y: 10), in: [front, back]))
    }

    func testDwellCommitsOnlyAfterSteadyLook() {
        var dwell = DwellSelector<Int>(dwell: 0.3)
        XCTAssertNil(dwell.update(1, at: 0))
        XCTAssertNil(dwell.update(1, at: 0.2))
        XCTAssertEqual(dwell.update(1, at: 0.31), 1)
        XCTAssertNil(dwell.update(1, at: 0.5), "already current")
        XCTAssertNil(dwell.update(2, at: 0.6))
        XCTAssertNil(dwell.update(nil, at: 0.7), "looking away resets the glance")
        XCTAssertNil(dwell.update(2, at: 0.8))
        XCTAssertNil(dwell.update(2, at: 1.0))
        XCTAssertEqual(dwell.update(2, at: 1.1), 2)
    }

    func testOneEuroSettlesOnConstantInput() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0)
        var y = 0.0
        for i in 0..<200 { y = f.filter(i == 0 ? 0 : 10, at: Double(i) / 30) }
        XCTAssertEqual(y, 10, accuracy: 0.01)
    }
}

final class HandGestureTests: XCTestCase {
    /// A hand with the wrist at the bottom; `pinch` closes the thumb onto the index fingertip.
    func hand(pinch: Bool, openFingers: Bool = true, raisedBy dy: CGFloat = 0) -> HandSample {
        var j: [HandJoint: CGPoint] = [.wrist: CGPoint(x: 0.5, y: 0.2), .middleMCP: CGPoint(x: 0.5, y: 0.4), .indexMCP: CGPoint(x: 0.45, y: 0.4)]
        let fingers: [(CGFloat, HandJoint, HandJoint)] = [(0.45, .indexPIP, .indexTip), (0.5, .middlePIP, .middleTip), (0.55, .ringPIP, .ringTip), (0.6, .littlePIP, .littleTip)]
        for (x, pip, tip) in fingers {
            j[pip] = CGPoint(x: x, y: 0.5)
            j[tip] = CGPoint(x: x, y: openFingers ? 0.62 : 0.42)
        }
        j[.thumbTip] = pinch ? CGPoint(x: 0.455, y: 0.62) : CGPoint(x: 0.3, y: 0.35)
        return HandSample(joints: j.mapValues { CGPoint(x: $0.x, y: $0.y + dy) })
    }

    func testPoses() {
        XCTAssertEqual(HandGestureRecognizer.pose(of: hand(pinch: true)), .pinch)
        XCTAssertEqual(HandGestureRecognizer.pose(of: hand(pinch: false)), .openPalm)
        XCTAssertEqual(HandGestureRecognizer.pose(of: hand(pinch: false, openFingers: false)), .other)
    }

    func testPinchAndRaiseScrollsDown() {
        var r = HandGestureRecognizer()
        var events: [GestureEvent] = []
        for i in 0..<30 {
            let t = Double(i) / 30
            events += r.update(hand(pinch: true, raisedBy: t > 0.3 ? CGFloat(t - 0.3) * 0.3 : 0), at: t)
        }
        events += r.update(hand(pinch: false, openFingers: false), at: 1.1)
        XCTAssertEqual(events.first, .scrollBegan)
        XCTAssertEqual(events.last, .scrollEnded)
        let total = events.reduce(0.0) { if case .scrolled(let d) = $1 { return $0 + d }; return $0 }
        // Moving the hand up reveals content further down, like dragging the page.
        XCTAssertLessThan(total, -50)
    }

    func testLosingTheHandEndsTheScroll() {
        var r = HandGestureRecognizer()
        _ = r.update(hand(pinch: true), at: 0)
        XCTAssertEqual(r.update(hand(pinch: true), at: 0.2), [.scrollBegan])
        XCTAssertEqual(r.update(nil, at: 0.3), [], "brief dropouts are tolerated")
        XCTAssertEqual(r.update(nil, at: 0.6), [.scrollEnded])
    }

    func testHeldPalmTogglesOnce() {
        var r = HandGestureRecognizer()
        var toggles = 0
        for i in 0..<120 {
            toggles += r.update(hand(pinch: false), at: Double(i) / 30).filter { $0 == .toggle }.count
        }
        XCTAssertEqual(toggles, 1, "holding the palm doesn't keep toggling")
    }
}

final class EyeScrollerTests: XCTestCase {
    let window = CGRect(x: 0, y: 0, width: 800, height: 1000)

    func run(at y: CGFloat, for seconds: Double) -> Double {
        var s = EyeScroller()
        var total = 0.0
        for i in 0...Int(seconds * 30) { total += s.update(gaze: CGPoint(x: 400, y: y), window: window, at: Double(i) / 30) }
        return total
    }

    func testScrollsOnlyAfterDwellAtEdges() {
        XCTAssertEqual(run(at: 950, for: 0.5), 0, "still within the dwell")
        XCTAssertLessThan(run(at: 950, for: 2), 0, "bottom edge scrolls down")
        XCTAssertGreaterThan(run(at: 20, for: 2), 0, "top edge scrolls up")
        XCTAssertEqual(run(at: 500, for: 2), 0, "middle doesn't scroll")
    }
}

final class SettingsTests: XCTestCase {
    func testHotkeyParsing() {
        XCTAssertEqual(HotkeySpec.parse("ctrl+option+cmd+g"),
                       HotkeySpec(keyCode: 5, modifiers: HotkeySpec.control | HotkeySpec.option | HotkeySpec.command))
        XCTAssertEqual(HotkeySpec.parse("Shift + F5")?.keyCode, 96)
        XCTAssertNil(HotkeySpec.parse("g"), "needs a modifier")
        XCTAssertNil(HotkeySpec.parse("cmd+g+h"), "only one key")
        XCTAssertNil(HotkeySpec.parse("cmd+banana"))
    }

    func testPartialConfigKeepsDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"scrollMode": "both", "dwellMs": 500}"#.utf8))
        XCTAssertEqual(config.scrollMode, .both)
        XCTAssertEqual(config.dwellMs, 500)
        XCTAssertEqual(config.hotkey, Config().hotkey)
        XCTAssertTrue(config.scrollMode.usesHands && config.scrollMode.usesEyes)
    }
}
