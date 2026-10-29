import CoreGraphics
import Foundation

/// What one camera frame says about where the face and eyes point.
public struct GazeFeatures: Equatable {
    /// Head turn and tilt in radians, as reported by Vision.
    public var yaw: Double
    public var pitch: Double
    /// Nose offset from the midpoint between the eyes, in units of eye-to-eye distance.
    /// This tracks head turn more smoothly than Vision's yaw and pitch.
    public var noseX: Double
    public var noseY: Double
    /// Pupil offset from the center of the eye, in units of half the eye's width.
    public var eyeX: Double
    public var eyeY: Double
    /// False while blinking, when the pupil positions are unreliable.
    public var eyesOpen: Bool

    public static let vectorCount = 6

    public init(yaw: Double, pitch: Double, noseX: Double, noseY: Double, eyeX: Double, eyeY: Double, eyesOpen: Bool) {
        self.yaw = yaw
        self.pitch = pitch
        self.noseX = noseX
        self.noseY = noseY
        self.eyeX = eyeX
        self.eyeY = eyeY
        self.eyesOpen = eyesOpen
    }

    public var vector: [Double] { [yaw, pitch, noseX, noseY, eyeX, eyeY] }
}

/// A display and where it sits, in global display coordinates (origin at the top-left of the main display).
public struct DisplaySnapshot: Codable, Equatable {
    public var id: UInt32
    public var frame: CGRect
    public var name: String

    public init(id: UInt32, frame: CGRect, name: String) {
        self.id = id
        self.frame = frame
        self.name = name
    }
}

public struct CalibrationSample: Codable, Equatable {
    public var features: [Double]
    public var target: CGPoint
    public var displayID: UInt32

    public init(features: [Double], target: CGPoint, displayID: UInt32) {
        self.features = features
        self.target = target
        self.displayID = displayID
    }
}

/// Maps gaze features to a point on screen. A model across all displays picks the display,
/// then that display's own model places the point within it.
public struct GazeModel: Codable {
    public struct LocalModel: Codable {
        public var displayID: UInt32
        public var model: LinearModel
    }

    public struct Prediction: Equatable {
        public var point: CGPoint
        public var displayID: UInt32

        public init(point: CGPoint, displayID: UInt32) {
            self.point = point
            self.displayID = displayID
        }
    }

    public struct Accuracy: Equatable {
        public var displayID: UInt32
        /// Share of samples placed on the right display.
        public var displayHitRate: Double
        /// Mean error as a share of the display's width and height.
        public var horizontalError: Double
        public var verticalError: Double
    }

    public var createdAt: Date
    public var displays: [DisplaySnapshot]
    public var global: LinearModel
    public var local: [LocalModel]
    public var samples: [CalibrationSample]

    public static func fit(samples: [CalibrationSample], displays: [DisplaySnapshot], lambda: Double = 0.05) -> GazeModel? {
        func fit(_ s: [CalibrationSample]) -> LinearModel? {
            LinearModel.fit(inputs: s.map(\.features), outputs: s.map { [$0.target.x, $0.target.y] }, lambda: lambda)
        }
        guard let global = fit(samples) else { return nil }
        let local = displays.compactMap { d in
            fit(samples.filter { $0.displayID == d.id }).map { LocalModel(displayID: d.id, model: $0) }
        }
        return GazeModel(createdAt: Date(), displays: displays, global: global, local: local, samples: samples)
    }

    /// Whether this model was built from the current feature set.
    public var isCompatible: Bool { global.mean.count == GazeFeatures.vectorCount }

    /// Returns nil when the gaze falls well outside every display, such as when looking at the keyboard.
    /// `awayMargin` is how far past a display's edge still counts, as a share of its size.
    public func predict(_ features: [Double], awayMargin: Double = 0.2) -> Prediction? {
        let g = global.predict(features)
        guard let display = Self.display(near: CGPoint(x: g[0], y: g[1]), in: displays, margin: awayMargin) else { return nil }
        var point = CGPoint(x: g[0], y: g[1])
        if let lm = local.first(where: { $0.displayID == display.id }) {
            let l = lm.model.predict(features)
            point = CGPoint(x: l[0], y: l[1])
        }
        return Prediction(point: point.clamped(to: display.frame), displayID: display.id)
    }

    /// How well the model fits its own calibration dots.
    public func accuracy() -> [Accuracy] {
        displays.map { d in
            let s = samples.filter { $0.displayID == d.id }
            var hits = 0
            var dx = 0.0, dy = 0.0
            for sample in s {
                guard let p = predict(sample.features, awayMargin: 10) else { continue }
                if p.displayID == d.id { hits += 1 }
                dx += abs(p.point.x - sample.target.x)
                dy += abs(p.point.y - sample.target.y)
            }
            let n = Double(max(s.count, 1))
            return Accuracy(displayID: d.id, displayHitRate: Double(hits) / n,
                            horizontalError: dx / n / d.frame.width, verticalError: dy / n / d.frame.height)
        }
    }

    static func display(near p: CGPoint, in displays: [DisplaySnapshot], margin: Double) -> DisplaySnapshot? {
        if let inside = displays.first(where: { $0.frame.contains(p) }) { return inside }
        var best: (DisplaySnapshot, CGFloat)?
        for d in displays {
            let f = d.frame
            let dx = max(f.minX - p.x, 0, p.x - f.maxX) / f.width
            let dy = max(f.minY - p.y, 0, p.y - f.maxY) / f.height
            guard dx <= margin, dy <= margin else { continue }
            let distance = max(dx, dy)
            if best == nil || distance < best!.1 { best = (d, distance) }
        }
        return best?.0
    }
}

extension CGPoint {
    func clamped(to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(x, r.minX), r.maxX - 1), y: min(max(y, r.minY), r.maxY - 1))
    }
}
