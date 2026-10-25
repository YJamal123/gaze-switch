"""Calibration: look at each monitor center, record a gaze score.

Calibration is saved as JSON so `run` can load it later:

    {
      "displays": [{"x": 0, "width": 2560, ...}, ...],
      "centers": [0.12, -0.45]
    }

Centers are in the same left-to-right order as the displays list.
"""

import json
import os
import statistics
import time

import cv2

from .displays import get_displays
from .gaze import GazeTracker

CONFIG_PATH = os.path.expanduser("~/.config/gaze-switch/calibration.json")


def load_calibration(path=CONFIG_PATH):
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    centers = data["centers"]
    if not centers:
        raise ValueError("calibration file has no centers")
    return centers


def save_calibration(centers, displays, path=CONFIG_PATH):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = {
        "centers": centers,
        "displays": [
            {"x": d.x, "y": d.y, "width": d.width, "height": d.height}
            for d in displays
        ],
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
    return path


def run_calibration(camera_index=0, samples=60):
    displays = get_displays()
    print(f"Found {len(displays)} monitor(s), left to right:")
    for display in displays:
        print(f"  {display.index}: x={display.x} width={display.width} "
              f"height={display.height}")

    cap = cv2.VideoCapture(camera_index)
    if not cap.isOpened():
        print(f"Could not open camera {camera_index}.")
        return 1
    tracker = GazeTracker()
    centers = []
    try:
        for display in displays:
            input(f"\nLook at the CENTER of monitor {display.index}, "
                  "then press Enter. Keep your head still.")
            print("Recording... keep looking at the center.")
            collected = []
            start = time.time()
            while len(collected) < samples and time.time() - start < 15:
                ok, frame = cap.read()
                if not ok:
                    continue
                score = tracker.score_for_frame(frame)
                if score is not None:
                    collected.append(score)
            if len(collected) < 10:
                print("Too few face samples. Check light and camera angle, "
                      "then recalibrate.")
                return 1
            center = statistics.median(collected)
            centers.append(center)
            print(f"Monitor {display.index}: center score {center:.3f} "
                  f"from {len(collected)} samples.")
        if len(centers) >= 2:
            diffs = [centers[i + 1] - centers[i] for i in range(len(centers) - 1)]
            if any(d == 0 for d in diffs):
                print("Warning: two monitors got the same center score. "
                      "Recalibrate with your head turned more clearly.")
    finally:
        tracker.close()
        cap.release()

    path = save_calibration(centers, displays)
    print(f"\nSaved calibration to {path}")
    print("Run it with: python run.py run")
    return 0
