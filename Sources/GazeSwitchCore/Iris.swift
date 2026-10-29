import CoreGraphics

/// An 8-bit grayscale image, such as the brightness plane of a camera frame. Row 0 is the top.
public struct GrayImage {
    public let width: Int
    public let height: Int
    public let rowBytes: Int
    public let pixels: UnsafePointer<UInt8>

    public init(width: Int, height: Int, rowBytes: Int, pixels: UnsafePointer<UInt8>) {
        self.width = width
        self.height = height
        self.rowBytes = rowBytes
        self.pixels = pixels
    }

    @inline(__always) func value(_ x: Int, _ y: Int) -> UInt8 { pixels[y * rowBytes + x] }
}

public enum IrisLocator {
    /// Finds the iris as the darkest iris-sized patch of the eye opening, so scattered dark pixels
    /// along the lids and corners don't drag it off.
    /// `contour` outlines the eye in pixel coordinates with the origin at the top-left.
    public static func locate(in image: GrayImage, contour: [CGPoint]) -> CGPoint? {
        guard contour.count >= 3 else { return nil }
        let xs = contour.map(\.x), ys = contour.map(\.y)
        let minX = max(Int(xs.min()!.rounded(.down)), 0), maxX = min(Int(xs.max()!.rounded(.up)), image.width - 1)
        let minY = max(Int(ys.min()!.rounded(.down)), 0), maxY = min(Int(ys.max()!.rounded(.up)), image.height - 1)
        guard maxX > minX, maxY > minY else { return nil }
        let w = maxX - minX + 1, h = maxY - minY + 1

        // Summed-area tables of brightness and pixel count over just the pixels inside the eye.
        var sum = [Double](repeating: 0, count: (w + 1) * (h + 1))
        var count = [Double](repeating: 0, count: (w + 1) * (h + 1))
        var inside = [Bool](repeating: false, count: w * h)
        var values: [UInt8] = []
        for y in 0..<h {
            for x in 0..<w {
                let isInside = contains(contour, CGPoint(x: Double(minX + x) + 0.5, y: Double(minY + y) + 0.5))
                let v = isInside ? Double(image.value(minX + x, minY + y)) : 0
                if isInside {
                    inside[y * w + x] = true
                    values.append(UInt8(v))
                }
                let i = (y + 1) * (w + 1) + (x + 1)
                sum[i] = v + sum[i - 1] + sum[i - w - 1] - sum[i - w - 2]
                count[i] = (isInside ? 1 : 0) + count[i - 1] + count[i - w - 1] - count[i - w - 2]
            }
        }
        guard values.count >= 20 else { return nil }
        func box(_ table: [Double], _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Double {
            table[(y1 + 1) * (w + 1) + (x1 + 1)] - table[y0 * (w + 1) + (x1 + 1)] - table[(y1 + 1) * (w + 1) + x0] + table[y0 * (w + 1) + x0]
        }

        // The visible iris spans most of the eye's height.
        let r = max(1, Int((Double(h) * 0.3).rounded()))
        var best: (x: Int, y: Int, mean: Double)?
        for y in 0..<h {
            for x in 0..<w where inside[y * w + x] {
                let x0 = max(x - r, 0), x1 = min(x + r, w - 1), y0 = max(y - r, 0), y1 = min(y + r, h - 1)
                let n = box(count, x0, y0, x1, y1)
                // Skip patches that are mostly outside the eye.
                guard n >= Double((2 * r + 1) * (2 * r + 1)) * 0.6 else { continue }
                let mean = box(sum, x0, y0, x1, y1) / n
                if best == nil || mean < best!.mean { best = (x, y, mean) }
            }
        }
        guard let best else { return nil }

        // Refine: centroid of the dark pixels near that patch, darker ones weighted more.
        let median = Double(values.sorted()[values.count / 2])
        let threshold = (best.mean + median) / 2
        let reach = Double(r) * 1.6
        var sx = 0.0, sy = 0.0, total = 0.0
        for y in 0..<h {
            for x in 0..<w where inside[y * w + x] && hypot(Double(x - best.x), Double(y - best.y)) <= reach {
                let v = Double(image.value(minX + x, minY + y))
                guard v <= threshold else { continue }
                let weight = threshold - v + 1
                sx += weight * (Double(minX + x) + 0.5)
                sy += weight * (Double(minY + y) + 0.5)
                total += weight
            }
        }
        return total > 0 ? CGPoint(x: sx / total, y: sy / total) : CGPoint(x: Double(minX + best.x) + 0.5, y: Double(minY + best.y) + 0.5)
    }

    /// Even-odd ray casting.
    static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

/// Tells blinks apart from looking down. Both make the eye opening smaller, but a blink closes it
/// much further than your usual opening.
public struct BlinkDetector {
    public var closedShare = 0.55
    private var baseline: Double?

    public init() {}

    public mutating func eyesOpen(opening: Double) -> Bool {
        guard let base = baseline else {
            baseline = opening
            return true
        }
        let open = opening > base * closedShare
        // Track your usual opening slowly, and only from frames that aren't blinks.
        if opening > base * 0.65 { baseline = base * 0.97 + opening * 0.03 }
        return open
    }
}

/// Learns a per-display offset from mouse clicks, on the idea that you look at what you click.
/// This corrects drift when you shift in your seat after calibrating.
public struct DriftCorrector {
    public var learningRate = 0.3
    /// The largest correction, as a share of the display's size.
    public var maxOffset = 0.2
    /// How far a click can be from where we think you're looking and still count, as a share of the display's size.
    /// A click further away probably means you were looking somewhere else.
    public var acceptWidth = 0.3
    public var acceptHeight = 0.35
    public private(set) var offsets: [UInt32: CGVector] = [:]

    public init() {}

    public func apply(_ p: GazeModel.Prediction, displays: [DisplaySnapshot]) -> GazeModel.Prediction {
        guard let o = offsets[p.displayID], let d = displays.first(where: { $0.id == p.displayID }) else { return p }
        return GazeModel.Prediction(point: CGPoint(x: p.point.x + o.dx, y: p.point.y + o.dy).clamped(to: d.frame), displayID: p.displayID)
    }

    /// `gaze` is the already-corrected point. Returns whether the click was used.
    @discardableResult
    public mutating func learn(click: CGPoint, gaze: GazeModel.Prediction, displays: [DisplaySnapshot]) -> Bool {
        guard let d = displays.first(where: { $0.id == gaze.displayID }), d.frame.contains(click) else { return false }
        let ex = click.x - gaze.point.x, ey = click.y - gaze.point.y
        guard abs(ex) <= d.frame.width * acceptWidth, abs(ey) <= d.frame.height * acceptHeight else { return false }
        let o = offsets[d.id] ?? CGVector()
        let limitX = d.frame.width * maxOffset, limitY = d.frame.height * maxOffset
        offsets[d.id] = CGVector(dx: min(max(o.dx + learningRate * ex, -limitX), limitX),
                                 dy: min(max(o.dy + learningRate * ey, -limitY), limitY))
        return true
    }
}
