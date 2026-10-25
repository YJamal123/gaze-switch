"""Tests for gaze zone classification. No camera needed."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from gaze_switch.zones import classify_score, thresholds_for_centers


def test_thresholds_are_midpoints():
    assert thresholds_for_centers([0.0, 1.0, 3.0]) == [0.5, 2.0]


def test_ascending_centers():
    centers = [0.0, 1.0]
    assert classify_score(-1.0, centers) == 0
    assert classify_score(0.4, centers) == 0
    assert classify_score(0.6, centers) == 1


def test_descending_centers():
    centers = [1.0, 0.0]
    assert classify_score(1.5, centers) == 0
    assert classify_score(0.4, centers) == 1


def test_single_monitor():
    assert classify_score(99.0, [0.5]) == 0
