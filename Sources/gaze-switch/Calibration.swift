import AppKit
import GazeSwitchCore

/// Shows dots on each display in turn and records what the camera sees while you look at them.
final class CalibrationController {
    private struct Target {
        let displayID: UInt32
        let point: CGPoint
    }

    private enum Phase {
        case countdown(until: Double)
        case target(index: Int, since: Double)
        case done
    }

    // Seconds to let the eyes land on a dot, then to record it.
    private let settle = 1.0
    private let record = 1.2
    private let maxRecord = 4.0
    private let minSamples = 12

    private let displays: [DisplaySnapshot]
    private let targets: [Target]
    private var views: [UInt32: CalibrationView] = [:]
    private var windows: [NSWindow] = []
    private var phase = Phase.countdown(until: 0)
    private var pending: [CalibrationSample] = []
    private var samples: [CalibrationSample] = []
    private var skipped = 0
    private var lastFaceAt = -Double.infinity
    private var timer: Timer?
    private var keyMonitor: Any?
    private let onFinish: (GazeModel?, _ skipped: Int) -> Void

    init(displays: [DisplaySnapshot], onFinish: @escaping (GazeModel?, Int) -> Void) {
        self.displays = displays
        self.onFinish = onFinish
        // A 3×3 grid per display, so it can tell apart windows side by side or stacked.
        let fractions: [CGFloat] = [0.1, 0.5, 0.9]
        targets = displays.flatMap { d in
            fractions.flatMap { fy in
                fractions.map { fx in
                    Target(displayID: d.id, point: CGPoint(x: d.frame.minX + fx * d.frame.width, y: d.frame.minY + fy * d.frame.height))
                }
            }
        }
    }

    func start() {
        for d in displays {
            let window = CalibrationWindow(contentRect: Displays.toAppKit(d.frame), styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = NSColor.black.withAlphaComponent(0.88)
            window.isOpaque = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = CalibrationView(displayFrame: d.frame)
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views[d.id] = view
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(cancelled: true) } // Esc
            return nil
        }
        phase = .countdown(until: now + 4)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Feed every camera frame here.
    func handle(_ frame: FrameResult) {
        if frame.face != nil { lastFaceAt = frame.time }
        guard case .target(let index, let since) = phase, frame.time - since >= settle,
              let face = frame.face, face.eyesOpen else { return }
        let target = targets[index]
        pending.append(CalibrationSample(features: face.vector, target: target.point, displayID: target.displayID))
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private func tick() {
        let t = now
        let faceVisible = t - lastFaceAt < 0.5
        switch phase {
        case .countdown(let until):
            let remaining = Int((until - t).rounded(.up))
            let text = faceVisible
                ? "Look at each dot until it disappears.\nTurn your head the way you normally would.\n\nStarting in \(max(remaining, 1))…   (Esc to cancel)"
                : "Can't see your face yet.\nSit where you normally do, facing the screens."
            for view in views.values { view.show(dot: nil, progress: 0, message: text) }
            if t >= until && faceVisible { advance(to: 0, at: t) }
        case .target(let index, let since):
            let target = targets[index]
            let elapsed = t - since
            let recording = max(elapsed - settle, 0)
            for (id, view) in views {
                if id == target.displayID {
                    view.show(dot: target.point, progress: min(recording / record, 1),
                              message: faceVisible ? nil : "Can't see your face")
                } else {
                    view.show(dot: nil, progress: 0, message: nil)
                }
            }
            if recording >= record && pending.count >= minSamples {
                samples += pending
                advance(to: index + 1, at: t)
            } else if recording >= maxRecord {
                // Keep what we got if it's enough to be useful; skip the dot otherwise.
                if pending.count >= 5 { samples += pending } else { skipped += 1 }
                advance(to: index + 1, at: t)
            }
        case .done:
            break
        }
    }

    private func advance(to index: Int, at t: Double) {
        pending = []
        if index < targets.count {
            phase = .target(index: index, since: t)
        } else {
            finish(cancelled: false)
        }
    }

    private func finish(cancelled: Bool) {
        if case .done = phase { return }
        phase = .done
        timer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        windows.forEach { $0.orderOut(nil) }
        onFinish(cancelled ? nil : GazeModel.fit(samples: samples, displays: displays), cancelled ? -1 : skipped)
    }
}

private final class CalibrationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class CalibrationView: NSView {
    private let displayFrame: CGRect
    private var dot: CGPoint?
    private var progress = 0.0
    private var message: String?

    init(displayFrame: CGRect) {
        self.displayFrame = displayFrame
        super.init(frame: NSRect(origin: .zero, size: displayFrame.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(dot: CGPoint?, progress: Double, message: String?) {
        guard dot != self.dot || progress != self.progress || message != self.message else { return }
        self.dot = dot
        self.progress = progress
        self.message = message
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let dot {
            // Global display coordinates have y pointing down; the view's y points up.
            let center = CGPoint(x: dot.x - displayFrame.minX, y: displayFrame.maxY - dot.y)
            let radius = 26 - 16 * progress
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)).fill()
        }
        if let message {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let text = NSAttributedString(string: message, attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style,
            ])
            let size = text.boundingRect(with: NSSize(width: bounds.width - 80, height: bounds.height), options: [.usesLineFragmentOrigin]).size
            text.draw(in: NSRect(x: 40, y: (bounds.height - size.height) / 2, width: bounds.width - 80, height: size.height))
        }
    }
}
