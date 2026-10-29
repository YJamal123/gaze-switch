import CoreGraphics

/// Smooths a noisy signal: heavy smoothing when it holds still, little lag when it moves fast.
/// See Casiez et al., "1€ Filter" (CHI 2012).
public struct OneEuroFilter {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double
    private var previous: Double?
    private var previousDerivative = 0.0
    private var previousTime = 0.0

    public init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func filter(_ x: Double, at t: Double) -> Double {
        guard let prev = previous else {
            previous = x
            previousTime = t
            return x
        }
        let dt = t - previousTime
        guard dt > 0 else { return prev }
        let derivative = Self.lowpass((x - prev) / dt, previousDerivative, Self.alpha(derivativeCutoff, dt))
        let cutoff = minCutoff + beta * abs(derivative)
        let result = Self.lowpass(x, prev, Self.alpha(cutoff, dt))
        previous = result
        previousDerivative = derivative
        previousTime = t
        return result
    }

    public mutating func reset() {
        previous = nil
        previousDerivative = 0
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    private static func lowpass(_ x: Double, _ prev: Double, _ alpha: Double) -> Double {
        alpha * x + (1 - alpha) * prev
    }
}

/// A 1€ filter for each axis of a point.
public struct PointFilter {
    private var x: OneEuroFilter
    private var y: OneEuroFilter

    public init(minCutoff: Double, beta: Double) {
        x = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        y = OneEuroFilter(minCutoff: minCutoff, beta: beta)
    }

    public mutating func filter(_ p: CGPoint, at t: Double) -> CGPoint {
        CGPoint(x: x.filter(p.x, at: t), y: y.filter(p.y, at: t))
    }

    public mutating func reset() {
        x.reset()
        y.reset()
    }
}
