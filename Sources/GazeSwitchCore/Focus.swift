import CoreGraphics

/// An on-screen window, in global display coordinates.
public struct WindowInfo: Equatable {
    public var id: UInt32
    public var pid: Int32
    public var owner: String
    public var title: String
    public var frame: CGRect

    public init(id: UInt32, pid: Int32, owner: String, title: String, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.owner = owner
        self.title = title
        self.frame = frame
    }

    public var label: String { title.isEmpty ? owner : "\(owner) — \(title)" }
}

/// The frontmost window containing `point`. `windows` must be ordered front to back.
public func topWindow(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
    windows.first { $0.frame.contains(point) }
}

/// Commits to a new value only after it has been seen for `dwell` seconds without interruption,
/// so a passing glance doesn't switch focus.
public struct DwellSelector<Value: Equatable> {
    public var dwell: Double
    public private(set) var current: Value?
    private var candidate: Value?
    private var candidateSince = 0.0

    public init(dwell: Double) {
        self.dwell = dwell
    }

    /// Returns the value at the moment it is committed, and nil otherwise.
    public mutating func update(_ value: Value?, at t: Double) -> Value? {
        guard let value, value != current else {
            candidate = nil
            return nil
        }
        if value != candidate {
            candidate = value
            candidateSince = t
        }
        guard t - candidateSince >= dwell else { return nil }
        current = value
        candidate = nil
        return value
    }

    public mutating func reset() {
        current = nil
        candidate = nil
    }
}
