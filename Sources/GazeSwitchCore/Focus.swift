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
    /// `dwell` overrides the usual dwell for this look, such as to ask for a longer one while typing.
    public mutating func update(_ value: Value?, at t: Double, dwell: Double? = nil) -> Value? {
        guard let value, value != current else {
            candidate = nil
            return nil
        }
        if value != candidate {
            candidate = value
            candidateSince = t
        }
        guard t - candidateSince >= dwell ?? self.dwell else { return nil }
        current = value
        candidate = nil
        return value
    }

    public mutating func reset() {
        current = nil
        candidate = nil
    }
}

/// How long a look must last before switching, depending on what you're doing.
/// Modeled on Focus (github.com/OshOEz/focus): mouse use blocks switching, typing asks for a longer look,
/// and going straight back to the window you just left asks for a firmer one.
public struct SwitchPolicy {
    public var dwell: Double
    /// No switching for this long after you move, click or scroll the mouse.
    public var pointerGrace = 1.5
    /// While you've typed within `typingWindow` seconds, a look must last at least this long.
    public var typingDwell = 1.0
    public var typingWindow = 1.5
    /// Going back to the window you left within `returnWindow` seconds takes this many times the usual dwell.
    public var returnFactor = 2.0
    public var returnWindow = 2.0

    public private(set) var lastPointer = -Double.infinity
    public private(set) var lastKey = -Double.infinity
    private var lastSwitch = -Double.infinity
    private var previous: UInt32?

    public init(dwell: Double) {
        self.dwell = dwell
    }

    public mutating func pointerUsed(at t: Double) { lastPointer = t }
    public mutating func keyPressed(at t: Double) { lastKey = t }

    public mutating func switched(from old: UInt32?, at t: Double) {
        previous = old
        lastSwitch = t
    }

    /// Nil while switching is blocked; otherwise how long a look at `candidate` must last.
    public func requiredDwell(for candidate: UInt32?, at t: Double) -> Double? {
        guard t - lastPointer >= pointerGrace else { return nil }
        var d = t - lastKey < typingWindow ? max(dwell, typingDwell) : dwell
        if let candidate, candidate == previous, t - lastSwitch < returnWindow { d *= returnFactor }
        return d
    }
}
