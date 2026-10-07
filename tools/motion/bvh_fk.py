"""Independent BVH parser and forward kinematics (numpy), End Sites included.

Oracle for BVHClip: same file, separate code. Positions in the file's own model
space, scaled to meters by `units_to_meters`.
"""

import numpy as np


def _axis_matrix(axis, degrees):
    a = np.radians(degrees)
    c, s = np.cos(a), np.sin(a)
    n = a.shape[0]
    m = np.zeros((n, 3, 3))
    if axis == "X":
        m[:, 0, 0] = 1
        m[:, 1, 1], m[:, 1, 2], m[:, 2, 1], m[:, 2, 2] = c, -s, s, c
    elif axis == "Y":
        m[:, 1, 1] = 1
        m[:, 0, 0], m[:, 0, 2], m[:, 2, 0], m[:, 2, 2] = c, s, -s, c
    else:
        m[:, 2, 2] = 1
        m[:, 0, 0], m[:, 0, 1], m[:, 1, 0], m[:, 1, 1] = c, -s, s, c
    return m


class BVH:
    def __init__(self, path, units_to_meters=1.0):
        text = open(path).read()
        head, motion = text.split("MOTION", 1)
        tokens = head.split()
        self.names, self.parents, self.offsets, self.channels = [], [], [], []
        self.is_end = []
        stack, i, pending = [], 0, None
        while i < len(tokens):
            t = tokens[i]
            if t in ("ROOT", "JOINT"):
                pending = tokens[i + 1]
                i += 2
            elif t == "End":
                pending = self.names[stack[-1]] + "_end"
                i += 2
            elif t == "{":
                self.names.append(pending)
                self.parents.append(stack[-1] if stack else -1)
                self.offsets.append(np.zeros(3))
                self.channels.append([])
                self.is_end.append(pending.endswith("_end") and pending[:-4] in self.names[:-1])
                stack.append(len(self.names) - 1)
                i += 1
            elif t == "}":
                stack.pop()
                i += 1
            elif t == "OFFSET":
                self.offsets[stack[-1]] = np.array([float(x) for x in tokens[i + 1:i + 4]])
                i += 4
            elif t == "CHANNELS":
                n = int(tokens[i + 1])
                self.channels[stack[-1]] = tokens[i + 2:i + 2 + n]
                i += 2 + n
            else:
                i += 1
        lines = [l for l in motion.strip().split("\n") if l.strip()]
        self.frame_count = int(lines[0].split(":")[1])
        self.frame_time = float(lines[1].split(":")[1])
        self.values = np.array([[float(x) for x in l.split()] for l in lines[2:2 + self.frame_count]])
        self.offsets = np.array(self.offsets) * units_to_meters
        self.units = units_to_meters

    def index(self, name):
        return self.names.index(name)

    def rest_positions(self):
        """Joint positions of the zero-rotation pose (offsets only), [1, joints, 3]."""
        saved = self.values
        self.values = np.zeros((1, saved.shape[1]))
        try:
            return self.positions([0])
        finally:
            self.values = saved

    def local_rotations(self, frames=None):
        """Joint local rotation matrices [frames, joints, 3, 3] (channel order)."""
        rows = self.values if frames is None else self.values[np.asarray(frames)]
        n = rows.shape[0]
        result = np.repeat(np.repeat(np.eye(3)[None, None], n, axis=0), len(self.names), axis=1)
        column = 0
        for j, channels in enumerate(self.channels):
            for channel in channels:
                if channel.endswith("rotation"):
                    result[:, j] = result[:, j] @ _axis_matrix(channel[0], rows[:, column])
                column += 1
        return result

    def positions(self, frames=None):
        """World joint positions [frames, joints, 3] in meters."""
        rows = self.values if frames is None else self.values[np.asarray(frames)]
        n = rows.shape[0]
        count = len(self.names)
        rot = np.zeros((n, count, 3, 3))
        pos = np.zeros((n, count, 3))
        column = 0
        for j in range(count):
            local_r = np.repeat(np.eye(3)[None], n, axis=0)
            local_t = np.repeat(self.offsets[j][None], n, axis=0).copy()
            for channel in self.channels[j]:
                v = rows[:, column]
                column += 1
                if channel.endswith("position"):
                    local_t[:, "XYZ".index(channel[0])] += v * self.units
                else:
                    local_r = local_r @ _axis_matrix(channel[0], v)
            p = self.parents[j]
            if p < 0:
                rot[:, j], pos[:, j] = local_r, local_t
            else:
                rot[:, j] = rot[:, p] @ local_r
                pos[:, j] = pos[:, p] + np.einsum("nij,nj->ni", rot[:, p], local_t)
        return pos
