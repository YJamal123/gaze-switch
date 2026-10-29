import CoreGraphics
import Foundation

public enum HandJoint: String, CaseIterable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

/// Hand joint positions in camera-frame units: y runs bottom to top from 0 to 1, and x uses the same scale.
public struct HandSample {
    public var joints: [HandJoint: CGPoint]

    public init(joints: [HandJoint: CGPoint]) {
        self.joints = joints
    }

    public subscript(_ joint: HandJoint) -> CGPoint? { joints[joint] }
}

public enum HandPose: String {
    case pinch
    case openPalm = "open palm"
    case other
}

public enum GestureEvent: Equatable {
    case scrollBegan
    /// A scroll-wheel delta in pixels; positive moves toward the top of the document.
    case scrolled(Double)
    case scrollEnded
    case toggle
}

/// Pinch and drag to scroll, like grabbing the page. Hold an open palm to toggle gaze-switch.
public struct HandGestureRecognizer {
    /// Pinch thresholds, as thumb-to-index distance over hand size, with hysteresis so the pinch doesn't flicker.
    public var pinchEnter = 0.28
    public var pinchExit = 0.40
    /// Scroll pixels per full frame height of hand travel.
    public var scrollGain = 3000.0
    /// Ignore the first moments of a pinch, while the fingers are still closing.
    public var settleTime = 0.12
    public var toggleHold = 1.5
    public var toggleCooldown = 2.0
    /// How long the hand can drop out of view before a gesture ends.
    public var lostGrace = 0.25

    public private(set) var isScrolling = false
    private var pinching = false
    private var pinchStart: Double?
    private var lastY = 0.0
    private var yFilter = OneEuroFilter(minCutoff: 2.0, beta: 2.0)
    private var palmSince: Double?
    private var palmLatched = false
    private var lastToggle = -Double.infinity
    private var lastSeen = -Double.infinity

    public init() {}

    public static func pose(of hand: HandSample, pinchThreshold: Double = 0.28) -> HandPose {
        guard let size = handSize(hand), let ratio = pinchRatio(hand, size: size) else { return .other }
        if ratio < pinchThreshold { return .pinch }
        return isOpenPalm(hand, size: size) ? .openPalm : .other
    }

    public mutating func update(_ hand: HandSample?, at t: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []
        guard let hand, let size = Self.handSize(hand), let ratio = Self.pinchRatio(hand, size: size) else {
            if t - lastSeen > lostGrace {
                if isScrolling { events.append(.scrollEnded) }
                endPinch()
                palmSince = nil
                palmLatched = false
            }
            return events
        }
        lastSeen = t
        pinching = pinching ? ratio < pinchExit : ratio < pinchEnter

        if pinching {
            palmSince = nil
            let y = yFilter.filter((hand[.thumbTip]!.y + hand[.indexTip]!.y) / 2, at: t)
            if let start = pinchStart {
                if isScrolling {
                    let delta = -(y - lastY) * scrollGain
                    if delta != 0 { events.append(.scrolled(delta)) }
                } else if t - start >= settleTime {
                    isScrolling = true
                    events.append(.scrollBegan)
                }
            } else {
                pinchStart = t
            }
            lastY = y
            return events
        }

        if isScrolling { events.append(.scrollEnded) }
        endPinch()
        if Self.isOpenPalm(hand, size: size) {
            let since = palmSince ?? t
            palmSince = since
            if !palmLatched, t - since >= toggleHold, t - lastToggle >= toggleCooldown {
                palmLatched = true
                lastToggle = t
                events.append(.toggle)
            }
        } else {
            palmSince = nil
            palmLatched = false
        }
        return events
    }

    private mutating func endPinch() {
        isScrolling = false
        pinching = false
        pinchStart = nil
        yFilter.reset()
    }

    static func handSize(_ hand: HandSample) -> Double? {
        guard let wrist = hand[.wrist], let mcp = hand[.middleMCP] else { return nil }
        let size = distance(wrist, mcp)
        return size > 0.01 ? size : nil
    }

    static func pinchRatio(_ hand: HandSample, size: Double) -> Double? {
        guard let thumb = hand[.thumbTip], let index = hand[.indexTip] else { return nil }
        return distance(thumb, index) / size
    }

    static func isOpenPalm(_ hand: HandSample, size: Double) -> Bool {
        guard let wrist = hand[.wrist] else { return false }
        let fingers: [(HandJoint, HandJoint)] = [(.indexPIP, .indexTip), (.middlePIP, .middleTip), (.ringPIP, .ringTip), (.littlePIP, .littleTip)]
        for (pip, tip) in fingers {
            guard let p = hand[pip], let q = hand[tip], distance(wrist, q) > 1.3 * distance(wrist, p) else { return false }
        }
        guard let thumb = hand[.thumbTip], let indexBase = hand[.indexMCP] else { return false }
        return distance(thumb, indexBase) / size > 0.5
    }
}

func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}
