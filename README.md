# gaze-switch
Use your webcam to switch monitors with your eyes. Look at a screen to focus it, no click required. Runs locally on macOS.

Look at a window to activate it, including either half of a split screen. Then scroll it by pinching and moving your hand, or by looking at its top or bottom edge. Your mouse stays yours: looking only changes which window is active.

Nothing leaves your Mac. Video is processed on-device with Apple's Vision framework and is never saved.

## Requirements

- macOS 14 or later
- Xcode or the Xcode Command Line Tools (for `swift build`)
- A webcam. The built-in camera works; Continuity Camera and USB cameras work too.

## Build

```bash
swift build -c release
```

The program is then at `.build/release/gaze-switch`. All the commands below run from the repo folder.

## Use it

**1. Check the camera can see you**

```bash
.build/release/gaze-switch track
```

This prints live head, eye and hand readings. Turn your head and watch the numbers move. The first run asks for camera access for your terminal app.

**2. Calibrate**

```bash
.build/release/gaze-switch calibrate
```

Dots appear on each screen in turn, 9 per screen. Look at each one until it shrinks away, turning your head the way you normally would. It takes about 20 seconds per screen. At the end it reports how accurate the result is. Calibrate again whenever you change your screens, your seat or the camera position.

Check the result with a dot that follows your gaze:

```bash
.build/release/gaze-switch track --show-gaze
```

**3. Run it**

```bash
.build/release/gaze-switch run
```

The first run asks for Accessibility access, which it needs to activate windows and scroll. Turn it on for your terminal app in System Settings → Privacy & Security → Accessibility.

- **Switch windows:** look at a window for a moment and it becomes active.
- **Scroll with your hand:** pinch your thumb and index finger in front of the camera, then move your hand up or down, as if dragging the page.
- **Scroll with your eyes:** run with `--scroll eyes` or `--scroll both`, then look near the top or bottom edge of a window.
- **Turn it on and off:** press `⌃⌥⌘G`, or hold an open palm up to the camera for a second and a half.
- **See what it sees:** add `--show-gaze` for the gaze dot and `--verbose` for a live readout.

Press Ctrl-C to quit.

## Settings

Settings live in `~/Library/Application Support/gaze-switch/config.json`, which is created on the first run. Run `gaze-switch config` to see them.

| Setting | Default | What it does |
| --- | --- | --- |
| `scrollMode` | `hands` | `hands`, `eyes`, `both` or `off` |
| `hotkey` | `ctrl+option+cmd+g` | Shortcut that turns it on and off |
| `gestureToggle` | `true` | Hold up an open palm to turn it on and off |
| `dwellMs` | `350` | How long to look at a window before it activates |
| `handScrollSpeed` | `1` | Multiplier for hand scrolling |
| `invertHandScroll` | `false` | Flip the hand-scroll direction |
| `eyeScrollSpeed` | `1` | Multiplier for eye scrolling |
| `eyeScrollEdge` | `0.18` | Height of the edge bands that trigger eye scrolling, as a share of the window |
| `eyeScrollDwellMs` | `600` | How long to look at an edge before scrolling starts |
| `awayMargin` | `0.2` | How far past a screen's edge a look still counts |
| `camera` | built-in | Part of a camera's name; see `gaze-switch cameras` |
| `startEnabled` | `true` | Start switched on |
| `sounds` | `true` | Play a sound when turning on and off |
| `showGaze` | `false` | Always show the gaze dot |

## How it works

Each camera frame goes through Vision's face-landmark and hand-pose detection. Gaze comes from two signals combined: which way your head points (nose position relative to your eyes, plus Vision's head yaw and pitch) and where your pupils sit within your eyes. Calibration fits a linear model from those signals to screen positions. One model across all screens picks the screen, then a model per screen places the point within it. A 1€ filter smooths the result, and a short dwell stops passing glances from switching windows.

macOS sends scroll events to the window under the mouse pointer. So while you scroll, gaze-switch parks the pointer in the window you're looking at, then puts it back when you stop.

## Tips and limits

- Light your face from the front. Strong light behind you makes eye tracking much worse.
- Telling split-screen halves apart works best side by side. Top and bottom halves are harder because webcams read up-and-down eye movement less precisely.
- Glasses with strong reflections can hide your pupils. Head direction still works, but small eye-only glances count for less.
- Because it runs from Terminal, macOS grants camera and Accessibility access to your terminal app, so other programs you run from it get the same access.

## Development

```bash
swift test
```

The pure logic (gaze model, filters, gestures, eye scrolling, settings) lives in `Sources/GazeSwitchCore` and has unit tests. The camera, Vision, windows and UI code is in `Sources/gaze-switch`.
