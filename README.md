# gaze-switch

Use your webcam to switch monitors with your eyes. Look at a screen to focus it, no click required. Runs locally on macOS.

Phase 1 prototype: use your webcam to switch which monitor is active.

Look at another monitor for a short dwell time, and gaze-switch focuses
the frontmost window on that monitor and moves the cursor back to where
you last left it on that monitor. Your normal mouse and keyboard keep
working. Hand tracking for cursor movement, clicks, and scrolling is
planned for Phase 2 and Phase 3, not built yet.

This is intentionally coarse. A normal webcam is good enough to tell
left monitor from right monitor. It is not good enough to reliably click
a small button with your eyes alone, so this project does not try.

All video processing is local. No frames are uploaded or saved.

## How it works

1. Calibration: look at the center of each monitor in turn. The program
   records a simple gaze score for each monitor.
2. Gaze score: a combination of iris position inside the eyes and head
   yaw. Head pose matters because when you turn to a side monitor your
   eyes recenter, so iris position alone is not enough.
3. Zone classification: the score is compared to midpoints between the
   calibrated monitor centers. That gives the current monitor zone.
4. Switching: if the zone stays on a different monitor for the dwell
   time (default 0.4 seconds), gaze-switch activates the frontmost
   window on that monitor and restores that monitor's last cursor
   position. A pause key stops switching while you type or look away.

## Requirements

- macOS with one or more external monitors arranged side by side
- A built-in or USB webcam facing you
- Python 3.10 or newer

On macOS you must grant:

- Camera access for the terminal or app running this program
- Accessibility access, so it can move the cursor and activate windows

If Accessibility is not granted, run with `--no-focus` to test gaze
zones only. Nothing will be focused or moved in that mode.

## Setup

```bash
cd gaze-switch
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

On macOS, the Quartz and Cocoa bindings come from the
`pyobjc-framework-*` lines in `requirements.txt`. They are marked for
macOS only and are skipped on other platforms.

## Calibrate

Sit where you normally sit, with even light on your face. Do not move
the webcam between calibration and use.

```bash
python run.py calibrate
```

Follow the prompts: look at the center of each monitor until it says
done. Calibration is saved to `~/.config/gaze-switch/calibration.json`.

If your monitors are not in left-to-right order in the prompt, check
System Settings > Displays. The program sorts monitors by their
horizontal position, so it should match that arrangement.

Recalibrate if you move the camera, change monitors, or change where
you sit.

## Run

```bash
python run.py run
```

Useful options:

```bash
python run.py run --dwell 0.6 --no-warp-cursor
python run.py run --no-focus   # log zone changes only, move nothing
python run.py run --camera 1   # use a different webcam
```

Keys while running:

- `q` or Esc: quit
- `p`: pause or resume switching

The debug window shows the current zone, gaze score, and dwell
progress. Close it or press `q` to stop. Ctrl-C also stops the program.

## Project layout

- `run.py`: command line entry point
- `gaze_switch/zones.py`: pure zone classification, no camera code
- `gaze_switch/gaze.py`: MediaPipe Face Mesh plus iris landmarks
- `gaze_switch/displays.py`: monitor geometry
- `gaze_switch/focus.py`: macOS window activation
- `gaze_switch/calibration.py`: calibration prompts and storage
- `gaze_switch/switcher.py`: camera loop, dwell, and switching
- `tests/test_zones.py`: tests for zone classification

## Troubleshooting

- No face found: move closer, face the camera directly, and avoid a
  bright window behind you.
- Zones flip a lot: recalibrate, increase `--dwell`, and keep your head
  still for a second during calibration for each monitor.
- Cursor does not move: check Accessibility permission, then try
  `--no-focus` to confirm gaze zones are correct first.
- Focus does not change: this is macOS only in Phase 1. On Linux or
  Windows, `--no-focus` mode still lets you test gaze zones.
- Glasses or low light: both make iris tracking worse. This is a known
  limitation of a single webcam, not a bug in calibration alone.

## Roadmap

- Phase 1 (this repo): gaze monitor switching, calibration, dwell,
  per-monitor cursor memory.
- Phase 2: hand tracking for cursor movement in relative mode.
- Phase 3: pinch click, pinch-drag, two-finger scroll, and a pause
  gesture. Pinch is planned instead of finger distance to the camera,
  because single-camera depth is noisy and moving your hand forward
  also moves the cursor.

## Safety

This program moves your cursor and activates windows. Keep the debug
window visible while testing, know the `q` key quits, and do not run
it while doing anything where an accidental window switch would be
costly. It is a prototype, not an accessibility-certified tool.
