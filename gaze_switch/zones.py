"""Pure gaze-zone classification.

This module has no camera or OS dependencies, so it is easy to test.

Calibration gives one gaze score per monitor, in left-to-right monitor
order. Classification compares a live score to the midpoints between
consecutive calibrated centers.

If the calibrated centers decrease from left to right (which depends on
camera placement and score sign), the scores are flipped internally so
the midpoint logic still works.
"""


def thresholds_for_centers(centers):
    """Return midpoint thresholds between consecutive centers.

    Returns an empty list for fewer than two centers.
    """
    if len(centers) < 2:
        return []
    flipped = centers[-1] < centers[0]
    values = [-c for c in centers] if flipped else list(centers)
    return [(values[i] + values[i + 1]) / 2.0 for i in range(len(values) - 1)]


def classify_score(score, centers):
    """Return the monitor index for a gaze score.

    Centers are in left-to-right monitor order. With one center, the
    answer is always monitor 0.
    """
    if not centers:
        raise ValueError("centers must not be empty")
    if len(centers) == 1:
        return 0
    flipped = centers[-1] < centers[0]
    value = -score if flipped else score
    thresholds = thresholds_for_centers(centers)
    for index, threshold in enumerate(thresholds):
        if value < threshold:
            return index
    return len(centers) - 1
