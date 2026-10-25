"""Monitor geometry, sorted left to right.

On macOS, NSScreen frames use a bottom-left origin. They are converted
to top-left coordinates here so they match pyautogui positions.

On other platforms, screeninfo is used if available, otherwise tkinter.
Phase 1 only needs horizontal order for side-by-side monitors, but the
full rectangle is kept so cursor warping can be checked against it.
"""

from dataclasses import dataclass


@dataclass
class Display:
    index: int
    x: int
    y: int
    width: int
    height: int
    is_main: bool = False

    def contains(self, px, py):
        return self.x <= px < self.x + self.width and self.y <= py < self.y + self.height

    def center(self):
        return (self.x + self.width // 2, self.y + self.height // 2)


def _from_macos():
    from AppKit import NSScreen

    screens = NSScreen.screens()
    if not screens:
        return []
    # Total virtual height, in bottom-left coordinates.
    total_height = 0
    raw = []
    for screen in screens:
        frame = screen.frame()
        raw.append((int(frame.origin.x), int(frame.origin.y),
                    int(frame.size.width), int(frame.size.height)))
        total_height = max(total_height, int(frame.origin.y) + int(frame.size.height))
    displays = []
    for i, (x, y_bottom, width, height) in enumerate(raw):
        y_top = total_height - y_bottom - height
        displays.append(Display(index=i, x=x, y=y_top, width=width,
                                height=height, is_main=(i == 0)))
    displays.sort(key=lambda d: d.x)
    for i, display in enumerate(displays):
        display.index = i
    return displays


def _from_screeninfo():
    from screeninfo import get_monitors

    displays = []
    for monitor in sorted(get_monitors(), key=lambda m: m.x):
        displays.append(Display(index=len(displays), x=monitor.x, y=monitor.y,
                                width=monitor.width, height=monitor.height,
                                is_main=monitor.is_primary))
    return displays


def _from_tkinter():
    import tkinter as tk

    root = tk.Tk()
    root.withdraw()
    width = root.winfo_screenwidth()
    height = root.winfo_screenheight()
    root.destroy()
    return [Display(index=0, x=0, y=0, width=width, height=height, is_main=True)]


def get_displays():
    """Return displays sorted left to right, or raise if none found."""
    import sys

    if sys.platform == "darwin":
        try:
            displays = _from_macos()
            if displays:
                return displays
        except Exception:
            pass
    try:
        displays = _from_screeninfo()
        if displays:
            return displays
    except Exception:
        pass
    return _from_tkinter()


def display_at_point(displays, px, py):
    for display in displays:
        if display.contains(px, py):
            return display
    return displays[0] if displays else None
