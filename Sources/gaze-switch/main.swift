import AppKit
import GazeSwitchCore

let usage = """
gaze-switch: look at a window to activate it, then scroll it with your hand or eyes.

Usage:
  gaze-switch track [--show-gaze]   Show live head, eye and hand readings, and where you're looking
  gaze-switch calibrate             Look at dots on each screen so it learns your setup
  gaze-switch run [options]         Switch windows by looking at them

Options for run:
  --scroll hands|eyes|both|off      How to scroll (default from config: hands)
  --show-gaze                       Show a dot where it thinks you're looking
  --verbose                         Print where you're looking, live

Other:
  gaze-switch cameras               List cameras
  gaze-switch config                Show the settings file and its values
  --camera NAME                     Use the camera whose name contains NAME
"""

var arguments = Array(CommandLine.arguments.dropFirst())
// Opened from Finder or the Dock: running inside a .app bundle with no command.
let appMode = Bundle.main.bundlePath.hasSuffix(".app") && arguments.allSatisfy { $0.hasPrefix("-psn_") }
/// Who macOS gives camera and Accessibility access to.
let permissionHolder = appMode ? "gaze-switch" : "your terminal app"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    if appMode {
        let alert = NSAlert()
        alert.messageText = "gaze-switch can't continue"
        alert.informativeText = message
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    exit(1)
}

if appMode {
    // There's no terminal to print to, so keep a log instead.
    let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/gaze-switch.log").path
    freopen(log, "a", stdout)
    freopen(log, "a", stderr)
}
setvbuf(stdout, nil, _IOLBF, 0)

let command = appMode ? "app" : arguments.isEmpty ? "help" : arguments.removeFirst()

func flag(_ name: String) -> Bool { arguments.contains(name) }
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

var config: Config
do { config = try Storage.loadConfig() } catch { fail("Couldn't read \(Storage.configURL.path): \(error)") }
if let camera = option("--camera") { config.camera = camera }
if let mode = option("--scroll") {
    guard let scrollMode = ScrollMode(rawValue: mode) else { fail("--scroll must be one of: hands, eyes, both, off") }
    config.scrollMode = scrollMode
}

let app = NSApplication.shared
app.setActivationPolicy(appMode ? .regular : .accessory)

// Commands live here for the life of the process.
var running: AnyObject?
var interrupt: DispatchSourceSignal?

switch command {
case "app":
    let controller = AppController(config: config)
    app.delegate = controller
    running = controller
case "track":
    let track = TrackCommand(config: config, showGaze: flag("--show-gaze"))
    track.start()
    running = track
case "calibrate":
    let calibrate = CalibrateCommand(config: config)
    calibrate.start()
    running = calibrate
case "run":
    let run = RunCommand(config: config, showGaze: flag("--show-gaze") || config.showGaze, verbose: flag("--verbose"))
    run.start()
    running = run
    // Put the cursor back if Ctrl-C lands mid-scroll.
    signal(SIGINT, SIG_IGN)
    interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt?.setEventHandler {
        run.stop()
        print("")
        exit(0)
    }
    interrupt?.resume()
case "cameras":
    for device in Camera.all { print("\(device.localizedName)\(device.deviceType == .builtInWideAngleCamera ? "  (built-in)" : "")") }
    exit(0)
case "config":
    print(Storage.configURL.path)
    print((try? String(contentsOf: Storage.configURL, encoding: .utf8)) ?? "")
    exit(0)
case "help", "-h", "--help":
    print(usage)
    exit(0)
default:
    fail(usage)
}

app.run()
