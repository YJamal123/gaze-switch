import AppKit
import ApplicationServices
import GazeSwitchCore

enum Displays {
    /// Active displays in global coordinates, left to right. Mirrored copies are left out.
    static func current() -> [DisplaySnapshot] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { DisplaySnapshot(id: $0, frame: CGDisplayBounds($0), name: name(of: $0)) }
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// Whether the displays are arranged the way they were during calibration.
    static func match(_ snapshot: [DisplaySnapshot]) -> Bool {
        let now = current()
        return now.count == snapshot.count && zip(now, snapshot).allSatisfy { $0.id == $1.id && $0.frame == $1.frame }
    }

    static func name(of id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
        return screen?.localizedName ?? "Display \(id)"
    }

    /// Converts global display coordinates (origin top-left, y down) to AppKit's (origin bottom-left, y up).
    static func toAppKit(_ r: CGRect) -> NSRect {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum Windows {
    /// Normal app windows on screen, front to back. Our own windows are left out.
    static func onScreen() -> [WindowInfo] {
        let me = getpid()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != me,
                  let bounds = d[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 80, frame.height >= 60,
                  ((d[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05
            else { return nil }
            return WindowInfo(id: id, pid: pid,
                              owner: d[kCGWindowOwnerName as String] as? String ?? "?",
                              title: d[kCGWindowName as String] as? String ?? "",
                              frame: frame)
        }
    }

    static func isFocused(_ window: WindowInfo) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid,
              let focused = attribute(application(window.pid), kAXFocusedWindowAttribute) else { return false }
        return windowID(of: focused as! AXUIElement) == window.id
    }

    /// Brings the window's app to the front and raises the window. Needs Accessibility permission.
    @discardableResult
    static func activate(_ window: WindowInfo) -> Bool {
        let app = application(window.pid)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard let element = axWindow(for: window, in: app) else { return false }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        // Don't hang on an app that has stopped responding.
        AXUIElementSetMessagingTimeout(app, 0.5)
        return app
    }

    private static func axWindow(for window: WindowInfo, in app: AXUIElement) -> AXUIElement? {
        guard let list = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return list.first { windowID(of: $0) == window.id } ?? list.first { frame(of: $0) == window.frame }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}

/// The on-screen window list, re-read at most every quarter second.
final class WindowCache {
    private var windows: [WindowInfo] = []
    private var fetchedAt = -Double.infinity

    func get(at t: Double) -> [WindowInfo] {
        if t - fetchedAt > 0.25 {
            windows = Windows.onScreen()
            fetchedAt = t
        }
        return windows
    }

    func invalidate() {
        fetchedAt = -Double.infinity
    }
}

/// Scroll events go to the window under the cursor, so the cursor is parked in the target window
/// for the length of a scroll gesture and put back afterwards.
final class Scroller {
    private(set) var isActive = false
    private var restore: CGPoint?
    private var parked: CGPoint?
    private var remainder = 0.0

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// `point` is where in the window to scroll, usually where you're looking.
    func begin(in window: WindowInfo, at point: CGPoint?) {
        guard !isActive else { return }
        isActive = true
        remainder = 0
        let cursor = Self.cursor
        if topWindow(at: cursor, in: Windows.onScreen())?.id == window.id { return }
        let inset = window.frame.insetBy(dx: 20, dy: 40)
        let target = (point ?? CGPoint(x: window.frame.midX, y: window.frame.midY))
        let clamped = CGPoint(x: min(max(target.x, inset.minX), inset.maxX), y: min(max(target.y, inset.minY), inset.maxY))
        restore = cursor
        parked = clamped
        move(to: clamped)
    }

    /// Positive pixels scroll toward the top of the document.
    func scroll(_ pixels: Double) {
        guard isActive else { return }
        remainder += pixels
        let whole = remainder.rounded(.towardZero)
        guard whole != 0 else { return }
        remainder -= whole
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: Int32(clamping: Int(whole)), wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    func end() {
        guard isActive else { return }
        isActive = false
        // If you grabbed the mouse mid-scroll, leave it where you put it.
        if let restore, let parked, hypot(Self.cursor.x - parked.x, Self.cursor.y - parked.y) < 3 {
            move(to: restore)
        }
        restore = nil
        parked = nil
    }

    private func move(to p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

enum Permissions {
    /// Asks macOS to show the Accessibility prompt if needed, then waits until access is granted.
    static func waitForAccessibility(then done: @escaping () -> Void) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return done() }
        print("""
        gaze-switch needs Accessibility access to switch windows and scroll.
        Open System Settings → Privacy & Security → Accessibility and turn on your terminal app.
        Waiting…
        """)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            print("Accessibility access granted.")
            done()
        }
    }
}
