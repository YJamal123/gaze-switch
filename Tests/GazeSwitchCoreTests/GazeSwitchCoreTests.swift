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

    func testNoiseFloorDampsBarelyMovingFeatures() throws {
        // The second feature barely moves in training; without a floor a later jump in it would swing the output.
        let inputs = (0..<30).map { [Double($0), 1 + Double($0 % 2) * 1e-4] }
        let outputs = inputs.map { [$0[0] + ($0[1] - 1) * 1e4] }
        let model = try XCTUnwrap(LinearModel.fit(inputs: inputs, outputs: outputs, lambda: 0.05, minScale: [0, 0.1]))
        XCTAssertLessThan(abs(model.predict([10, 2])[0] - model.predict([10, 1])[0]), 50)
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
        [p.x / 1000, p.y / 1000, p.x / 2000, 0, 0, 0, 0, 0, 0, 0]
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

final class EyeTests: XCTestCase {
    /// A bright eye opening with a dark iris at `iris`, in a 60×30 image.
    func withEye(iris: CGPoint, _ body: (GrayImage, [CGPoint]) -> Void) {
        let width = 60, height = 30
        var pixels = [UInt8](repeating: 40, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let inEye = pow((Double(x) - 30) / 25, 2) + pow((Double(y) - 15) / 10, 2) <= 1
                let inIris = hypot(Double(x) + 0.5 - iris.x, Double(y) + 0.5 - iris.y) <= 6
                if inEye { pixels[y * width + x] = inIris ? 30 : 220 }
            }
        }
        let contour = (0..<16).map { i -> CGPoint in
            let a = Double(i) / 16 * 2 * .pi
            return CGPoint(x: 30 + 25 * cos(a), y: 15 + 10 * sin(a))
        }
        pixels.withUnsafeBufferPointer { buffer in
            body(GrayImage(width: width, height: height, rowBytes: width, pixels: buffer.baseAddress!), contour)
        }
    }

    func testFindsTheIris() {
        for iris in [CGPoint(x: 30, y: 15), CGPoint(x: 18, y: 14), CGPoint(x: 41, y: 17)] {
            withEye(iris: iris) { image, contour in
                let found = IrisLocator.locate(in: image, contour: contour)
                XCTAssertEqual(found?.x ?? 0, iris.x, accuracy: 1.5)
                XCTAssertEqual(found?.y ?? 0, iris.y, accuracy: 1.5)
            }
        }
    }

    func testPolygonContainment() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertTrue(IrisLocator.contains(square, CGPoint(x: 5, y: 5)))
        XCTAssertFalse(IrisLocator.contains(square, CGPoint(x: 15, y: 5)))
    }

    func testLookingDownIsNotABlink() {
        var blinks = BlinkDetector()
        for _ in 0..<60 { _ = blinks.eyesOpen(opening: 0.30) }
        XCTAssertTrue(blinks.eyesOpen(opening: 0.21), "lids drop about a third when looking down")
        XCTAssertFalse(blinks.eyesOpen(opening: 0.08), "a blink nearly closes them")
        XCTAssertTrue(blinks.eyesOpen(opening: 0.30))
    }

    func testClicksCorrectDrift() {
        let display = DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 600), name: "")
        var drift = DriftCorrector()
        let raw = GazeModel.Prediction(point: CGPoint(x: 500, y: 300), displayID: 1)
        // You keep clicking 60px right of where the model thinks you're looking.
        for _ in 0..<15 {
            drift.learn(click: CGPoint(x: 560, y: 300), gaze: drift.apply(raw, displays: [display]), displays: [display])
        }
        XCTAssertEqual(drift.apply(raw, displays: [display]).point.x, 560, accuracy: 2)
        XCTAssertFalse(drift.learn(click: CGPoint(x: 990, y: 590), gaze: raw, displays: [display]), "far-off clicks are ignored")
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

    func testMouseUseBlocksSwitching() {
        var policy = SwitchPolicy(dwell: 0.35)
        XCTAssertEqual(policy.requiredDwell(for: 1, at: 10), 0.35)
        policy.pointerUsed(at: 10)
        XCTAssertNil(policy.requiredDwell(for: 1, at: 11), "blocked right after using the mouse")
        XCTAssertEqual(policy.requiredDwell(for: 1, at: 11.6), 0.35)
    }

    func testTypingAndGoingBackNeedLongerLooks() {
        var policy = SwitchPolicy(dwell: 0.35)
        policy.keyPressed(at: 10)
        XCTAssertEqual(policy.requiredDwell(for: 1, at: 10.5), 1.0, "typing asks for a longer look")
        XCTAssertEqual(policy.requiredDwell(for: 1, at: 12), 0.35)
        policy.switched(from: 7, at: 20)
        XCTAssertEqual(policy.requiredDwell(for: 7, at: 21), 0.7, "going straight back takes a firmer look")
        XCTAssertEqual(policy.requiredDwell(for: 8, at: 21), 0.35)
        XCTAssertEqual(policy.requiredDwell(for: 7, at: 23), 0.35)
    }

    func testDwellOverride() {
        var dwell = DwellSelector<Int>(dwell: 0.3)
        XCTAssertNil(dwell.update(1, at: 0, dwell: 1))
        XCTAssertNil(dwell.update(1, at: 0.5, dwell: 1))
        XCTAssertEqual(dwell.update(1, at: 1.0, dwell: 1), 1)
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
