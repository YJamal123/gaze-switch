"""Command line entry point for gaze-switch.

Usage:
    python run.py calibrate
    python run.py run [--dwell 0.4] [--no-focus] [--no-warp-cursor]
"""

import argparse
import sys

def main(argv=None):
    # Imports are lazy so `run.py --help` works before dependencies
    # like OpenCV are installed.
    parser = argparse.ArgumentParser(prog="gaze-switch")
    sub = parser.add_subparsers(dest="command", required=True)

    calibrate_parser = sub.add_parser("calibrate", help="Calibrate gaze zones")
    calibrate_parser.add_argument("--camera", type=int, default=0)
    calibrate_parser.add_argument("--samples", type=int, default=60)

    run_parser = sub.add_parser("run", help="Run gaze monitor switching")
    run_parser.add_argument("--camera", type=int, default=0)
    run_parser.add_argument("--dwell", type=float, default=0.4)
    run_parser.add_argument("--no-focus", action="store_true")
    run_parser.add_argument("--no-warp-cursor", action="store_true")
    run_parser.add_argument("--no-debug", action="store_true")

    args = parser.parse_args(argv)

    if args.command == "calibrate":
        from gaze_switch.calibration import run_calibration

        return run_calibration(camera_index=args.camera, samples=args.samples)
    if args.command == "run":
        from gaze_switch.switcher import run_switcher

        return run_switcher(
            camera_index=args.camera,
            dwell_seconds=args.dwell,
            do_focus=not args.no_focus,
            warp_cursor=not args.no_warp_cursor,
            show_debug=not args.no_debug,
        )
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
