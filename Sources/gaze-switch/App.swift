import AppKit
import GazeSwitchCore

/// gaze-switch as a Dock app: calibrates on first launch, then switches windows until you quit.
final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var config: Config
    private let pipeline = CameraPipeline(tracksHands: true)
    private var switcher: Switcher?
    private var calibration: CalibrationController?
    /// Ignore the camera while an alert is up, so a window switch doesn't bury it.
    private var paused = false

    init(config: Config) {
        self.config = config
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = NSImage(systemSymbolName: "eye.circle.fill", accessibilityDescription: "gaze-switch")?
            .withSymbolConfiguration(.init(pointSize: 256, weight: .regular).applying(.init(paletteColors: [.white, .systemBlue])))
        NSApp.mainMenu = mainMenu()
        pipeline.start(cameraName: config.camera) { [weak self] in self?.handle($0) }
        Permissions.waitForAccessibility { [weak self] in self?.startUp() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        switcher?.stop()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.items = commandItems()
        return menu
    }

    private func startUp() {
        guard let model = loadModel() else {
            alert("Let's calibrate", "Dots will appear on each screen. Look at each one until it disappears, turning your head the way you normally would.")
            return calibrate()
        }
        if !Displays.match(model.displays),
           alert("Your screens have changed", "Calibrate again so gaze-switch knows where they are.", buttons: ["Calibrate", "Use Old Calibration"]) == .alertFirstButtonReturn {
            return calibrate()
        }
        startSwitching(model)
    }

    private func handle(_ frame: FrameResult) {
        guard !paused else { return }
        if let calibration { calibration.handle(frame) } else { switcher?.handle(frame) }
    }

    private func startSwitching(_ model: GazeModel) {
        switcher?.stop()
        let switcher = Switcher(config: config, model: model, showGaze: config.showGaze)
        if let problem = switcher.registerHotkey() { alert("Shortcut not available", problem) }
        self.switcher = switcher
    }

    @objc private func calibrate() {
        guard calibration == nil else { return }
        switcher?.stop()
        let controller = CalibrationController(displays: Displays.current()) { [weak self] model, skipped in
            self?.calibrationFinished(model, skipped: skipped)
        }
        calibration = controller
        controller.start()
    }

    private func calibrationFinished(_ model: GazeModel?, skipped: Int) {
        calibration = nil
        switch finishCalibration(model, skipped: skipped) {
        case .saved(let model, let summary):
            alert("Calibration saved", summary)
            startSwitching(model)
        case .failed:
            if alert("Couldn't calibrate", "Make sure the camera can see your face, then try again.", buttons: ["Try Again", "Quit"]) == .alertFirstButtonReturn {
                calibrate()
            } else {
                NSApp.terminate(nil)
            }
        case .cancelled:
            // Keep using the previous calibration if there is one.
            if switcher == nil { NSApp.terminate(nil) }
        }
    }

    @objc private func toggle() {
        switcher?.toggle()
    }

    @objc private func toggleGazeDot() {
        config.showGaze.toggle()
        switcher?.showGaze = config.showGaze
        saveConfig()
    }

    @objc private func setScrollMode(_ sender: NSMenuItem) {
        guard let mode = (sender.representedObject as? String).flatMap(ScrollMode.init(rawValue:)) else { return }
        config.scrollMode = mode
        switcher?.scrollMode = mode
        saveConfig()
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(Storage.configURL)
    }

    private func saveConfig() {
        do { try Storage.saveConfig(config) } catch { alert("Couldn't save settings", "\(error)") }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggle):
            item.title = switcher?.enabled == true ? "Turn Off  (\(config.hotkey))" : "Turn On  (\(config.hotkey))"
            return switcher != nil && calibration == nil
        case #selector(toggleGazeDot):
            item.state = config.showGaze ? .on : .off
        case #selector(setScrollMode(_:)):
            item.state = (item.representedObject as? String) == config.scrollMode.rawValue ? .on : .off
        case #selector(calibrate):
            return calibration == nil
        default:
            break
        }
        return true
    }

    private func mainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.items = commandItems() + [
            .separator(),
            NSMenuItem(title: "Quit gaze-switch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }

    /// Items shared by the menu bar and the Dock menu.
    private func commandItems() -> [NSMenuItem] {
        let scrollMenu = NSMenu()
        for mode in ScrollMode.allCases {
            let item = NSMenuItem(title: mode.rawValue.capitalized, action: #selector(setScrollMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            scrollMenu.addItem(item)
        }
        let scrollItem = NSMenuItem(title: "Scroll With", action: nil, keyEquivalent: "")
        scrollItem.submenu = scrollMenu

        let items = [
            NSMenuItem(title: "Turn Off", action: #selector(toggle), keyEquivalent: ""),
            NSMenuItem(title: "Show Gaze Dot", action: #selector(toggleGazeDot), keyEquivalent: ""),
            scrollItem,
            .separator(),
            NSMenuItem(title: "Calibrate…", action: #selector(calibrate), keyEquivalent: ""),
            NSMenuItem(title: "Open Settings File", action: #selector(openSettings), keyEquivalent: ""),
        ]
        for item in items where item.action != nil { item.target = self }
        return items
    }

    @discardableResult
    private func alert(_ title: String, _ message: String, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        paused = true
        defer { paused = false }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
