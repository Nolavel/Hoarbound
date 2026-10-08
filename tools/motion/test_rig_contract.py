"""Henry rig contract the retarget relies on: python3 tools/motion/test_rig_contract.py

Twist split and leg-plane stages rotate limb bones about their local +Y. That is
only a roll of the bone if its child joint lies on +Y in the bone's rest frame.
"""

import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gltf_fk  # noqa: E402

HENRY_GLB = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "characters", "henry", "henry_outfit.glb")
# Bone -> child joint that must sit on the bone's +Y axis.
LIMB_AXES = {
    "upperarm": "lowerarm", "lowerarm": "hand", "thigh": "calf", "calf": "foot",
}
MAX_DEGREES = 0.1


class RigContractTest(unittest.TestCase):
    def test_child_joint_on_local_y(self):
        glb = gltf_fk.GLB(HENRY_GLB)
        for side in ("l", "r"):
            for bone, child in LIMB_AXES.items():
                node = glb.joints[glb.names.index("%s_%s" % (child, side))]
                offset = glb.rest_trs(node)[0]
                angle = np.degrees(np.arccos(np.clip(offset[1] / np.linalg.norm(offset), -1, 1)))
                self.assertLess(angle, MAX_DEGREES, "%s_%s: child %s is %.3f deg off +Y" % (bone, side, child, angle))


if __name__ == "__main__":
    unittest.main()
