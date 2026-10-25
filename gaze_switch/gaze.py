"""Webcam gaze score from MediaPipe Face Mesh with iris landmarks.

The score is a heuristic, not a calibrated 3D gaze ray. It combines:

- iris offset: where each iris sits inside its eye, normalized by eye width
- head yaw proxy: where the nose sits relative to the midpoint of the eyes,
  normalized by eye width

Head yaw matters because when you turn toward a side monitor your eyes
recenter. Iris position alone would then look like you are still looking
straight ahead.

Calibration learns what score means for each monitor on your setup, so
the exact scale does not matter as long as it moves monotonically when
you look from one monitor to another.
"""

import numpy as np

# MediaPipe Face Mesh landmark indices.
LEFT_EYE_CORNERS = (33, 133)
RIGHT_EYE_CORNERS = (362, 263)
LEFT_IRIS = range(468, 473)
RIGHT_IRIS = range(473, 478)
NOSE_TIP = 1


def _point(landmarks, index):
    landmark = landmarks[index]
    return np.array([landmark.x, landmark.y], dtype=float)


def _mean_point(landmarks, indices):
    points = [_point(landmarks, i) for i in indices]
    return np.mean(points, axis=0)


def gaze_score(landmarks):
    """Return a single horizontal gaze score, or None if landmarks are bad.

    Positive and negative signs depend on camera placement. Calibration
    handles either direction; do not assume a sign here.
    """
    try:
        left_center = _mean_point(landmarks, LEFT_EYE_CORNERS)
        right_center = _mean_point(landmarks, RIGHT_EYE_CORNERS)
        left_iris = _mean_point(landmarks, LEFT_IRIS)
        right_iris = _mean_point(landmarks, RIGHT_IRIS)
        nose = _point(landmarks, NOSE_TIP)
    except (IndexError, AttributeError):
        return None

    eye_distance = np.linalg.norm(right_center - left_center)
    if eye_distance == 0:
        return None

    left_width = abs(left_center[0] - _point(landmarks, LEFT_EYE_CORNERS[0])[0])
    right_width = abs(right_center[0] - _point(landmarks, RIGHT_EYE_CORNERS[0])[0])
    # Eye width here is half the corner-to-center distance, times two
    # would be the full width. Using the corner distances directly keeps
    # the math simple because calibration absorbs the scale.
    left_offset = (left_iris[0] - left_center[0]) / max(left_width, 1e-6)
    right_offset = (right_iris[0] - right_center[0]) / max(right_width, 1e-6)
    iris_offset = (left_offset + right_offset) / 2.0

    eye_midpoint = (left_center + right_center) / 2.0
    head_yaw = (nose[0] - eye_midpoint[0]) / eye_distance

    # Iris offset is a smaller, noisier signal than head movement, so it
    # gets a larger weight. The sum is still just a score for calibration.
    return float(iris_offset * 2.0 + head_yaw)


class GazeTracker:
    """Wraps MediaPipe Face Mesh so callers only see scores."""

    def __init__(self):
        import mediapipe as mp

        self._face_mesh = mp.solutions.face_mesh.FaceMesh(
            max_num_faces=1,
            refine_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )

    def score_for_frame(self, frame_bgr):
        """Return a gaze score for a BGR OpenCV frame, or None."""
        import cv2

        frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        result = self._face_mesh.process(frame_rgb)
        if not result.multi_face_landmarks:
            return None
        landmarks = result.multi_face_landmarks[0].landmark
        if len(landmarks) < 478:
            return None
        return gaze_score(landmarks)

    def close(self):
        self._face_mesh.close()
