"""macOS window activation for a target display.

Phase 1 uses horizontal overlap only. That matches the side-by-side
monitor case and avoids depending on vertical coordinate conventions
between Quartz window bounds and display frames.

On non-macOS platforms this is a no-op that returns False, so gaze
zones can still be tested with --no-focus.
"""

import subprocess
import sys


def focus_frontmost_window_on_display(display):
    """Activate the app owning the frontmost window on this display.

    Returns True if an activation was attempted, False otherwise.
    """
    if sys.platform != "darwin":
        return False
    try:
        from Quartz import CGWindowListCopyWindowInfo, kCGNullWindowID, kCGWindowListOptionOnScreenOnly
    except Exception:
        return False

    windows = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID)
    best = None
    best_overlap = 0
    for window in windows:
        if window.get("kCGWindowLayer", 0) != 0:
            continue
        bounds = window.get("kCGWindowBounds", {})
        x = bounds.get("X", 0)
        width = bounds.get("Width", 0)
        # Horizontal overlap with the target display.
        overlap = min(x + width, display.x + display.width) - max(x, display.x)
        if overlap > best_overlap:
            best_overlap = overlap
            best = window
    if best is None or best_overlap <= 0:
        return False

    owner = best.get("kCGWindowOwnerName")
    if not owner:
        return False
    # Escape double quotes in the app name for AppleScript.
    safe_owner = owner.replace('"', '\\"')
    script = f'tell application "{safe_owner}" to activate'
    subprocess.run(["osascript", "-e", script], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True
