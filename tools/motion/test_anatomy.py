"""Synthetic-chain checks for anatomy.py: python3 tools/motion/test_anatomy.py"""

import sys
import unittest

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import anatomy  # noqa: E402


def standing(knee_deg=0.0, elbow_deg=0.0, arm_abd=0.0, lean=0.0):
    """One frame facing +Z, left +X. Knee bends toward +Z, elbow bends toward -Z."""
    j = {"hips": [0, 1.0, 0], "chest": [0, 1.35, 0], "neck": [0, 1.5, 0], "head": [0, 1.62, 0]}
    lean_r = np.radians(lean)
    for key in ("chest", "neck", "head"):
        h = j[key][1] - 1.0
        j[key] = [0, 1.0 + h * np.cos(lean_r), h * np.sin(lean_r)]
    for side, x in (("l", 0.1), ("r", -0.1)):
        k = np.radians(knee_deg) / 2
        j[side + "_hip"] = [x, 1.0, 0]
        j[side + "_knee"] = [x, 1.0 - 0.45 * np.cos(k), 0.45 * np.sin(k)]
        j[side + "_ankle"] = [x, 1.0 - 0.9 * np.cos(k), 0]
        j[side + "_ball"] = [x, j[side + "_ankle"][1] - 0.05, 0.12]
        j[side + "_toe"] = [x, j[side + "_ankle"][1] - 0.06, 0.2]
        sx = 0.2 if side == "l" else -0.2
        out = 1.0 if side == "l" else -1.0
        a = np.radians(arm_abd)
        shoulder = np.array([sx, 1.45, 0])
        elbow = shoulder + 0.3 * np.array([out * np.sin(a), -np.cos(a), 0])
        e = np.radians(elbow_deg)
        wrist = elbow + 0.27 * np.array([out * np.sin(a) * np.cos(e), -np.cos(a) * np.cos(e), np.sin(e)])
        j[side + "_shoulder"], j[side + "_elbow"], j[side + "_wrist"] = shoulder, elbow, wrist
    return {key: np.array([value], dtype=float) for key, value in j.items()}


class AnatomyTest(unittest.TestCase):
    def test_straight_and_bent_knee(self):
        m = anatomy.frame_metrics(standing(knee_deg=40.0))
        self.assertAlmostEqual(m["l_knee_flex"][0], 40.0, places=3)
        self.assertLess(m["l_knee_plane"][0], 1.0)
        self.assertEqual(anatomy.failures(m)["l_knee_backward"], 0)

    def test_backward_knee_is_negative(self):
        m = anatomy.frame_metrics(standing(knee_deg=-20.0))
        self.assertAlmostEqual(m["r_knee_flex"][0], -20.0, places=3)
        self.assertEqual(anatomy.failures(m)["r_knee_backward"], 1)

    def test_elbow_and_arm_abduction(self):
        m = anatomy.frame_metrics(standing(elbow_deg=30.0, arm_abd=12.0))
        self.assertAlmostEqual(m["l_elbow_flex"][0], 30.0, places=3)
        self.assertAlmostEqual(m["l_arm_abd"][0], 12.0, places=3)
        self.assertAlmostEqual(m["r_arm_abd"][0], 12.0, places=3)

    def test_trunk_lean(self):
        m = anatomy.frame_metrics(standing(lean=10.0))
        self.assertAlmostEqual(m["trunk_lean_fwd"][0], 10.0, places=3)
        self.assertAlmostEqual(m["trunk_lean_side"][0], 0.0, places=3)

    def test_rotation_invariance(self):
        j = standing(knee_deg=25.0, elbow_deg=40.0, arm_abd=8.0, lean=6.0)
        yaw = np.radians(73.0)
        rot = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
        turned = {k: v @ rot.T + np.array([3.0, 0.0, -2.0]) for k, v in j.items()}
        a, b = anatomy.frame_metrics(j), anatomy.frame_metrics(turned)
        for name in a:
            self.assertAlmostEqual(float(a[name][0]), float(b[name][0]), places=6, msg=name)


if __name__ == "__main__":
    unittest.main()
