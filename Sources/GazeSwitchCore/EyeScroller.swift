import CoreGraphics

/// Scrolls while you look near the top or bottom edge of a window, after a short dwell.
public struct EyeScroller {
    /// The height of each edge band, as a share of the window's height.
    public var edgeFraction = 0.18
    public var dwell = 0.6
    /// Pixels per second at the very edge.
    public var maxSpeed = 900.0

    private var direction = 0
    private var since = 0.0
    private var lastTime: Double?

    public init() {}

    /// Returns this frame's scroll-wheel delta in pixels; positive moves toward the top of the document.
    /// `gaze` and `window` are in global display coordinates, where y grows downward.
    public mutating func update(gaze: CGPoint?, window: CGRect?, at t: Double) -> Double {
        defer { lastTime = t }
        guard let gaze, let window, window.contains(gaze) else {
            direction = 0
            return 0
        }
        let band = window.height * edgeFraction
        var newDirection = 0
        var depth = 0.0
        if gaze.y < window.minY + band {
            newDirection = 1
            depth = (window.minY + band - gaze.y) / band
        } else if gaze.y > window.maxY - band {
            newDirection = -1
            depth = (gaze.y - (window.maxY - band)) / band
        }
        if newDirection != direction {
            direction = newDirection
            since = t
            return 0
        }
        guard direction != 0, t - since >= dwell, let last = lastTime else { return 0 }
        let dt = min(t - last, 0.1)
        let speed = maxSpeed * (0.25 + 0.75 * min(depth, 1))
        return Double(direction) * speed * dt
    }
}
