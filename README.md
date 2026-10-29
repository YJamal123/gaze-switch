# gaze-switch
Use your webcam to switch monitors with your eyes. Look at a screen to focus it, no click required. Runs locally on macOS.

Look at a window to activate it, including either half of a split screen. Then scroll it by pinching and moving your hand, or by looking at its top or bottom edge. Your mouse stays yours: looking only changes which window is active.

Nothing leaves your Mac. Video is processed on-device with Apple's Vision framework and is never saved.

## Requirements

- macOS 14 or later
- Xcode or the Xcode Command Line Tools (for `swift build`)
- A webcam. The built-in camera works; Continuity Camera and USB cameras work too.

## The app

First, once, make a local signing certificate. This lets macOS remember gaze-switch's permissions across rebuilds:

```bash
./scripts/make-signing-cert.sh
```

Then build and install:

```bash
./scripts/build-app.sh --install
```

This builds `gaze-switch.app` and copies it to `/Applications`. Leave off `--install` to only build it into `build/`. Open it like any other app:

1. macOS asks for camera access, then Accessibility access. Both go to gaze-switch alone, not to your terminal.
2. The first time, it walks you through calibration.
3. Then a **How to Scroll** window shows the hand and eye gestures. The window is also a practice area: look at it and scroll it, and a live status line tells you what the camera sees, such as "Pinch seen" or "Scrolling with your hand".
4. After that it runs in the Dock. Its menu, in the menu bar or from right-clicking the Dock icon, turns it on and off, shows the gaze dot, picks how to scroll, reopens How to Scroll and recalibrates.

If your screens change, it offers to recalibrate the next time it opens. Messages go to `~/Library/Logs/gaze-switch.log`. Changes made in the settings file apply the next time the app opens.

Without the certificate, the app is "ad-hoc" signed, so macOS treats each rebuild as a new app. Its old entry in the Accessibility list still looks turned on, but it no longer counts. The certificate fixes that. You can also set `SIGN_IDENTITY` to another certificate's name.

### If it doesn't switch or scroll

- **Is there a "!" on the Dock icon?** Accessibility access is off, and macOS quietly blocks switching and scrolling without it. Choose **Turn On Accessibility Access…** from the gaze-switch menu. If gaze-switch is already listed and turned on, select it, click **−**, then open gaze-switch again and allow it.
- **Open How to Scroll** from the menu. Its status line shows live what the camera sees and whether a scroll started.
- **Check the log** at `~/Library/Logs/gaze-switch.log`. It records each window switch, each scroll and any window it couldn't switch to.

## Command line

```bash
swift build -c release
```

The program is then at `.build/release/gaze-switch`. All the commands below run from the repo folder. From the command line, macOS gives camera and Accessibility access to your terminal app instead.

## Use it from the command line

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

Each camera frame goes through Vision's face, face-landmark and hand-pose detection. Gaze combines several signals:

- **Head direction:** Vision's head yaw and pitch, the nose's position relative to the eyes, and the nose's position between the edges of the jaw.
- **Eye direction:** the iris position relative to the eye's corners. gaze-switch finds each iris itself as the darkest iris-sized patch of the eye, in the 1080p frame.
- **Eyelid opening:** your upper lid drops when you look down, which helps with up and down.
- **Head position** in the frame, so leaning or shifting is accounted for.

Blinks are told apart from looking down by comparing against your usual eye opening. Calibration fits a linear model from those signals to screen positions. One model across all screens picks the screen, then a model per screen places the point within it. A 1€ filter smooths the result, and a short dwell stops passing glances from switching windows. Following [Focus](https://github.com/OshOEz/focus), it also holds off switching for 1.5 seconds after you move, click or scroll the mouse. While you're typing, a look must last a full second, and going straight back to the window you just left takes twice as long a look. Each mouse click also nudges the estimate toward where you clicked, since you're usually looking there, which corrects drift when you shift in your seat. Clicks far from where it thinks you're looking are ignored.

macOS sends scroll events to the window under the mouse pointer. So while you scroll, gaze-switch parks the pointer in the window you're looking at, then puts it back when you stop.

## Tips and limits

- Light your face from the front. Strong light behind you makes eye tracking much worse.
- Telling split-screen halves apart works best side by side. Top and bottom halves are harder because webcams read up-and-down eye movement less precisely.
- Glasses with strong reflections can hide your pupils. Head direction still works, but small eye-only glances count for less.
- From the command line, macOS grants camera and Accessibility access to your terminal app, so other programs you run from it get the same access. Use the app to avoid that.

## Development

```bash
swift test
```

The pure logic (gaze model, filters, gestures, eye scrolling, settings) lives in `Sources/GazeSwitchCore` and has unit tests. The camera, Vision, windows and UI code is in `Sources/gaze-switch`.
