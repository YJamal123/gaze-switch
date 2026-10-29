import AppKit
import Carbon
import GazeSwitchCore

/// A system-wide keyboard shortcut. Carbon hotkeys need no extra permissions.
final class GlobalHotkey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private let id: UInt32
    private var ref: EventHotKeyRef?

    init?(_ spec: HotkeySpec, action: @escaping () -> Void) {
        Self.installHandler()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: 0x475A_5357, id: id) // 'GZSW'
        guard RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        Self.actions[id] = action
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            GlobalHotkey.actions[hotKeyID.id]?()
            return noErr
        }, 1, &type, nil, nil)
    }
}

/// A dot that follows your gaze, drawn above everything and ignoring the mouse.
final class GazeOverlay {
    private static let size: CGFloat = 28
    private let window: NSWindow
    private let dot = DotView(frame: NSRect(x: 0, y: 0, width: GazeOverlay.size, height: GazeOverlay.size))

    init() {
        window = NSWindow(contentRect: dot.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = dot
    }

    func show(at point: CGPoint?, color: NSColor) {
        guard let point else { return window.orderOut(nil) }
        let s = Self.size
        window.setFrame(Displays.toAppKit(CGRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s)), display: false)
        dot.color = color
        window.orderFrontRegardless()
    }
}

private final class DotView: NSView {
    var color = NSColor.systemGreen {
        didSet { if color != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        color.withAlphaComponent(0.55).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

enum Feedback {
    static func play(_ name: String, enabled: Bool) {
        if enabled { NSSound(named: NSSound.Name(name))?.play() }
    }

    static func log(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(time)] \(message)")
    }
}

/// Prints one line in place, at most ten times a second.
final class StatusLine {
    private var lastPrint = -Double.infinity

    func update(_ text: String, at t: Double) {
        guard t - lastPrint >= 0.1 else { return }
        lastPrint = t
        print("\r\u{1B}[K" + text, terminator: "")
        fflush(stdout)
    }

    func finish() {
        print("")
    }
}
