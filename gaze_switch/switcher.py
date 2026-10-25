"""Camera loop for Phase 1 gaze monitor switching.

State machine, in plain terms:

- Smooth the gaze score so one noisy frame cannot switch monitors.
- Classify the smoothed score into a monitor zone.
- If the zone is different from the active zone, start a dwell timer.
- If the zone is still different when the timer passes the dwell
  time, switch: save the current cursor position for the old monitor,
  activate the frontmost window on the new monitor, and restore the
  new monitor's last cursor position (unless --no-warp-cursor).

Press q or Esc to quit, p to pause or resume.
"""

import time

import cv2

from .calibration import load_calibration
from .displays import display_at_point, get_displays
from .focus import focus_frontmost_window_on_display
from .zones import classify_score


def _cursor_position():
    try:
        import pyautogui

        point = pyautogui.position()
        return (point.x, point.y)
    except Exception:
        return None


def _move_cursor(x, y):
    try:
        import pyautogui

        pyautogui.moveTo(x, y, duration=0)
        return True
    except Exception:
        return False


def run_switcher(camera_index=0, dwell_seconds=0.4, do_focus=True,
                 warp_cursor=True, show_debug=True):
    displays = get_displays()
    try:
        centers = load_calibration()
    except Exception as exc:
        print(f"Could not load calibration: {exc}")
        print("Run this first: python run.py calibrate")
        return 1
    if len(centers) != len(displays):
        print(f"Warning: calibration has {len(centers)} monitor(s) but "
              f"{len(displays)} monitor(s) were found now. Recalibrate "
              "if zones look wrong.")

    cap = cv2.VideoCapture(camera_index)
    if not cap.isOpened():
        print(f"Could not open camera {camera_index}.")
        return 1

    from .gaze import GazeTracker

    tracker = GazeTracker()
    smoothed = None
    active_zone = None
    pending_zone = None
    pending_since = None
    paused = False
    # Last cursor position per monitor index.
    last_cursor = {}

    print("Running. Look at another monitor to switch.")
    print("Press q or Esc to quit, p to pause or resume.")
    if not do_focus:
        print("Focus mode is off: zone changes will only be logged.")

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                continue
            score = tracker.score_for_frame(frame)
            if score is not None:
                if smoothed is None:
                    smoothed = score
                else:
                    smoothed = 0.3 * score + 0.7 * smoothed
                zone = classify_score(smoothed, centers)
            else:
                zone = None

            if zone is not None and active_zone is None:
                active_zone = zone
                print(f"Starting on monitor {zone}.")

            if zone is not None and not paused and zone != active_zone:
                if pending_zone != zone:
                    pending_zone = zone
                    pending_since = time.time()
                elif time.time() - pending_since >= dwell_seconds:
                    old_zone = active_zone
                    # Save cursor position for the monitor we leave.
                    current_cursor = _cursor_position()
                    if current_cursor is not None and old_zone is not None:
                        last_cursor[old_zone] = current_cursor
                    print(f"Switching monitor {old_zone} -> {zone}")
                    if do_focus:
                        focused = focus_frontmost_window_on_display(displays[zone])
                        if not focused:
                            print("Could not find a window to focus on "
                                  f"monitor {zone}.")
                    if warp_cursor and do_focus:
                        target = last_cursor.get(zone, displays[zone].center())
                        _move_cursor(target[0], target[1])
                    active_zone = zone
                    pending_zone = None
                    pending_since = None
            elif zone == active_zone:
                pending_zone = None
                pending_since = None

            if show_debug:
                label = f"zone={active_zone} pending={pending_zone} "
                label += f"score={smoothed:.3f} " if smoothed is not None else "score=? "
                label += "paused" if paused else "running"
                if zone is None:
                    label += " | no face"
                cv2.putText(frame, label, (10, 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)
                cv2.imshow("gaze-switch (q to quit, p to pause)", frame)
                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), 27):
                    break
                if key == ord("p"):
                    paused = not paused
                    print("Paused." if paused else "Resumed.")
            else:
                # Without a debug window there is no key handling, so
                # Ctrl-C is the way out.
                time.sleep(0.01)
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        tracker.close()
        cap.release()
        if show_debug:
            cv2.destroyAllWindows()
    return 0
