import AppKit
import GazeSwitchCore

/// Loads the saved calibration and warns about anything that would make it inaccurate.
func loadModel(required: Bool) -> GazeModel? {
    let model: GazeModel?
    do { model = try Storage.loadCalibration() } catch {
        fail("Couldn't read \(Storage.calibrationURL.path): \(error)\nRun 'gaze-switch calibrate' to make a new one.")
    }
    guard let model, model.isCompatible else {
        if required { fail("Not calibrated yet. Run 'gaze-switch calibrate' first.") }
        return nil
    }
    if !Displays.match(model.displays) {
        print("Warning: your screens have changed since calibration. Run 'gaze-switch calibrate' again.")
    }
    return model
}

func describe(_ p: GazeModel.Prediction?, model: GazeModel, windows: [WindowInfo]) -> String {
    guard let p else { return "→ away from the screens" }
    let display = model.displays.first { $0.id == p.displayID }?.name ?? "?"
    let window = topWindow(at: p.point, in: windows)?.label ?? "desktop"
    return "→ \(display) · \(window)"
}

/// Step 1: shows live what the camera sees and, once calibrated, where you're looking.
final class TrackCommand {
    private let config: Config
    private let model: GazeModel?
    private let pipeline = CameraPipeline(tracksHands: true)
    private let overlay: GazeOverlay?
    private let windows = WindowCache()
    private let status = StatusLine()
    private var filter = PointFilter(minCutoff: 0.5, beta: 0.005)

    init(config: Config, showGaze: Bool) {
        self.config = config
        model = loadModel(required: false)
        overlay = showGaze && model != nil ? GazeOverlay() : nil
    }

    func start() {
        if model == nil { print("Not calibrated yet, so this shows raw head and eye readings. Turn your head and watch them change.") }
        print("Press Ctrl-C to stop.")
        pipeline.start(cameraName: config.camera) { [weak self] in self?.handle($0) }
    }

    private func handle(_ frame: FrameResult) {
        var parts: [String] = []
        if let f = frame.face {
            parts.append(String(format: "head yaw %+5.1f° pitch %+5.1f°", f.yaw * 180 / .pi, f.pitch * 180 / .pi))
            parts.append(String(format: "nose %+.2f %+.2f", f.noseX, f.noseY))
            parts.append(f.eyesOpen ? String(format: "eyes %+.2f %+.2f", f.eyeX, f.eyeY) : "eyes closed")
            if let model, f.eyesOpen {
                var p = model.predict(f.vector, awayMargin: config.awayMargin)
                if let raw = p { p?.point = filter.filter(raw.point, at: frame.time) } else { filter.reset() }
                parts.append(describe(p, model: model, windows: windows.get(at: frame.time)))
                overlay?.show(at: p?.point, color: .systemGreen)
            }
        } else {
            parts.append("no face")
            overlay?.show(at: nil, color: .systemGreen)
        }
        parts.append("hand: " + (frame.hand.map { HandGestureRecognizer.pose(of: $0).rawValue } ?? "–"))
        status.update(parts.joined(separator: "  |  "), at: frame.time)
    }
}

/// Step 2: records where you look on each display and saves the fitted model.
final class CalibrateCommand {
    private let config: Config
    private let pipeline = CameraPipeline(tracksHands: false)
    private var controller: CalibrationController?

    init(config: Config) {
        self.config = config
    }

    func start() {
        let displays = Displays.current()
        print("Calibrating \(displays.count) screen\(displays.count == 1 ? "" : "s"): \(displays.map(\.name).joined(separator: ", "))")
        let controller = CalibrationController(displays: displays) { model, skipped in
            Self.finish(model: model, skipped: skipped)
        }
        self.controller = controller
        pipeline.start(cameraName: config.camera) { [weak controller] in controller?.handle($0) }
        controller.start()
    }

    private static func finish(model: GazeModel?, skipped: Int) {
        guard skipped >= 0 else { fail("Calibration cancelled.") }
        guard let model else { fail("Not enough data to calibrate. Check that the camera can see your face and try again.") }
        do { try Storage.saveCalibration(model) } catch { fail("Couldn't save calibration: \(error)") }
        print("Saved to \(Storage.calibrationURL.path)")
        if skipped > 0 { print("\(skipped) dot\(skipped == 1 ? " was" : "s were") skipped because your face wasn't visible.") }
        for a in model.accuracy() {
            let name = model.displays.first { $0.id == a.displayID }?.name ?? "?"
            print(String(format: "  %@: right screen %.0f%% of the time, off by about %.0f%% across and %.0f%% up/down",
                         name, a.displayHitRate * 100, a.horizontalError * 100, a.verticalError * 100))
            // Side-by-side halves are a quarter of the screen's width away from the split line.
            if a.horizontalError > 0.15 { print("    That's too loose to tell split-screen windows apart; try calibrating again.") }
        }
        print("Try it with 'gaze-switch track --show-gaze', then 'gaze-switch run'.")
        exit(0)
    }
}

/// Steps 3–6: activates the window you look at and scrolls it with hand gestures or your eyes.
final class RunCommand {
    private enum ScrollSource { case none, hands, eyes }

    private let config: Config
    private let model: GazeModel
    private let pipeline: CameraPipeline
    private let overlay: GazeOverlay?
    private let verbose: Bool
    private let windows = WindowCache()
    private let scroller = Scroller()
    private let status = StatusLine()
    private var hotkey: GlobalHotkey?
    private var enabled: Bool
    private var filter = PointFilter(minCutoff: 0.5, beta: 0.005)
    private var dwell: DwellSelector<UInt32>
    private var gestures = HandGestureRecognizer()
    private var eyeScroller = EyeScroller()
    private var gaze: GazeModel.Prediction?
    private var scrollSource = ScrollSource.none
    private var lastEyeScroll = 0.0

    init(config: Config, showGaze: Bool, verbose: Bool) {
        self.config = config
        self.verbose = verbose
        model = loadModel(required: true)!
        enabled = config.startEnabled
        pipeline = CameraPipeline(tracksHands: config.scrollMode.usesHands || config.gestureToggle)
        overlay = showGaze ? GazeOverlay() : nil
        dwell = DwellSelector(dwell: config.dwellMs / 1000)
        gestures.scrollGain *= config.handScrollSpeed * (config.invertHandScroll ? -1 : 1)
        eyeScroller.maxSpeed *= config.eyeScrollSpeed
        eyeScroller.edgeFraction = config.eyeScrollEdge
        eyeScroller.dwell = config.eyeScrollDwellMs / 1000
    }

    func start() {
        Permissions.waitForAccessibility { [self] in
            if let spec = HotkeySpec.parse(config.hotkey) {
                hotkey = GlobalHotkey(spec) { [weak self] in self?.toggle() }
                if hotkey == nil { print("Couldn't register the shortcut \(config.hotkey); another app may be using it.") }
            } else {
                print("Couldn't understand the shortcut \"\(config.hotkey)\" in \(Storage.configURL.path).")
            }
            var toggles = ["\(config.hotkey) to turn on/off"]
            if config.gestureToggle { toggles.append("hold up an open palm") }
            print("gaze-switch is \(enabled ? "on" : "off"). \(toggles.joined(separator: ", or ")). Scrolling: \(config.scrollMode.rawValue).")
            if config.scrollMode.usesHands { print("Pinch your thumb and index finger, then move your hand up or down to scroll.") }
            if config.scrollMode.usesEyes { print("Look near the top or bottom edge of a window to scroll it.") }
            print("Press Ctrl-C to quit.")
            pipeline.start(cameraName: config.camera) { [weak self] in self?.handle($0) }
        }
    }

    func stop() {
        scroller.end()
    }

    private func toggle() {
        enabled.toggle()
        endScroll()
        dwell.reset()
        Feedback.play(enabled ? "Tink" : "Bottle", enabled: config.sounds)
        Feedback.log("gaze-switch \(enabled ? "on" : "off")")
    }

    private func handle(_ frame: FrameResult) {
        let t = frame.time
        let windowList = windows.get(at: t)
        updateGaze(frame)

        // Gestures run even while off, so the palm toggle can turn it back on.
        for event in gestures.update(frame.hand, at: t) { handle(event, windows: windowList) }

        defer {
            let color: NSColor = !enabled ? .systemGray : scroller.isActive ? .systemBlue : .systemGreen
            overlay?.show(at: gaze?.point, color: color)
            if verbose { status.update(describe(gaze, model: model, windows: windowList), at: t) }
        }
        guard enabled else { return }

        let looking = gaze.flatMap { topWindow(at: $0.point, in: windowList) }
        // Hold focus still while scrolling, so the window doesn't change mid-gesture.
        if !scroller.isActive, let id = dwell.update(looking?.id, at: t), let window = windowList.first(where: { $0.id == id }) {
            if !Windows.isFocused(window) {
                if Windows.activate(window) {
                    if verbose { status.finish() }
                    Feedback.log("→ \(window.label)")
                }
                windows.invalidate()
            }
        }

        if config.scrollMode.usesEyes && scrollSource != .hands {
            let delta = eyeScroller.update(gaze: gaze?.point, window: looking?.frame, at: t)
            if delta != 0, let looking {
                if scrollSource == .none {
                    scroller.begin(in: looking, at: gaze?.point)
                    scrollSource = .eyes
                }
                scroller.scroll(delta)
                lastEyeScroll = t
            } else if scrollSource == .eyes && t - lastEyeScroll > 0.4 {
                endScroll()
            }
        }
    }

    private func updateGaze(_ frame: FrameResult) {
        guard let face = frame.face else {
            gaze = nil
            filter.reset()
            return
        }
        // Mid-blink the pupils can't be read, so keep the last gaze.
        guard face.eyesOpen else { return }
        if let p = model.predict(face.vector, awayMargin: config.awayMargin) {
            gaze = GazeModel.Prediction(point: filter.filter(p.point, at: frame.time), displayID: p.displayID)
        } else {
            gaze = nil
            filter.reset()
        }
    }

    private func handle(_ event: GestureEvent, windows windowList: [WindowInfo]) {
        switch event {
        case .toggle:
            if config.gestureToggle { toggle() }
        case .scrollBegan:
            guard enabled, config.scrollMode.usesHands else { return }
            endScroll()
            // Eyes pick the window; fall back to the frontmost one when you're looking away.
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard let target = gaze.flatMap({ topWindow(at: $0.point, in: windowList) }) ?? windowList.first(where: { $0.pid == frontPID }) else { return }
            scroller.begin(in: target, at: gaze?.point)
            scrollSource = .hands
        case .scrolled(let pixels):
            if scrollSource == .hands { scroller.scroll(pixels) }
        case .scrollEnded:
            if scrollSource == .hands { endScroll() }
        }
    }

    private func endScroll() {
        scroller.end()
        scrollSource = .none
    }
}
