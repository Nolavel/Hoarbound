"""glTF (.glb) skin and animation sampler with forward kinematics (numpy).

Reads Henry/UAL rigs and offline retarget bakes directly, without Godot, so the
same metrics run on every backend's output.
"""

import json
import struct

import numpy as np

_COMPONENTS = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
_WIDTH = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def quat_to_matrix(q):
    """[..., 4] xyzw -> [..., 3, 3]."""
    q = q / np.linalg.norm(q, axis=-1, keepdims=True)
    x, y, z, w = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    m = np.empty(q.shape[:-1] + (3, 3))
    m[..., 0, 0] = 1 - 2 * (y * y + z * z)
    m[..., 0, 1] = 2 * (x * y - z * w)
    m[..., 0, 2] = 2 * (x * z + y * w)
    m[..., 1, 0] = 2 * (x * y + z * w)
    m[..., 1, 1] = 1 - 2 * (x * x + z * z)
    m[..., 1, 2] = 2 * (y * z - x * w)
    m[..., 2, 0] = 2 * (x * z - y * w)
    m[..., 2, 1] = 2 * (y * z + x * w)
    m[..., 2, 2] = 1 - 2 * (x * x + y * y)
    return m


def _slerp(a, b, t):
    dot = np.sum(a * b, axis=-1, keepdims=True)
    b = np.where(dot < 0, -b, b)
    dot = np.abs(dot)
    theta = np.arccos(np.clip(dot, -1, 1))
    small = theta < 1e-5
    s = np.sin(theta)
    wa = np.where(small, 1 - t, np.sin((1 - t) * theta) / np.where(small, 1, s))
    wb = np.where(small, t, np.sin(t * theta) / np.where(small, 1, s))
    q = wa * a + wb * b
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


class GLB:
    def __init__(self, path):
        data = open(path, "rb").read()
        length = struct.unpack("<I", data[12:16])[0]
        self.json = json.loads(data[20:20 + length])
        rest = data[20 + length:]
        self.bin = rest[8:8 + struct.unpack("<I", rest[0:4])[0]] if rest else b""
        skin = self.json["skins"][0]
        self.joints = skin["joints"]
        self.names = [self.json["nodes"][j]["name"] for j in self.joints]
        node_parent = {}
        for i, node in enumerate(self.json["nodes"]):
            for c in node.get("children", []):
                node_parent[c] = i
        self.node_parent = node_parent
        joint_of = {n: k for k, n in enumerate(self.joints)}
        self.parents = [joint_of.get(node_parent.get(n, -1), -1) for n in self.joints]
        # Transform of the skeleton's parent chain above the first joint.
        self.root_chain = []
        n = node_parent.get(self.joints[0], -1)
        while n >= 0:
            self.root_chain.append(n)
            n = node_parent.get(n, -1)
        self.animations = {a["name"]: a for a in self.json.get("animations", [])}

    def accessor(self, index):
        acc = self.json["accessors"][index]
        view = self.json["bufferViews"][acc["bufferView"]]
        dtype = _COMPONENTS[acc["componentType"]]
        width = _WIDTH[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        count = acc["count"]
        stride = view.get("byteStride", 0)
        item = np.dtype(dtype).itemsize * width
        if stride and stride != item:
            raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * count, offset=start)
            return np.stack([np.frombuffer(raw[i * stride:i * stride + item].tobytes(), dtype=dtype) for i in range(count)])
        return np.frombuffer(self.bin, dtype=dtype, count=count * width, offset=start).reshape(count, width).astype(np.float64)

    def rest_trs(self, node_index):
        node = self.json["nodes"][node_index]
        t = np.array(node.get("translation", [0, 0, 0]), dtype=float)
        r = np.array(node.get("rotation", [0, 0, 0, 1]), dtype=float)
        s = np.array(node.get("scale", [1, 1, 1]), dtype=float)
        return t, r, s

    def _node_matrix(self, node_index):
        t, r, s = self.rest_trs(node_index)
        m = np.eye(4)
        m[:3, :3] = quat_to_matrix(r) * s
        m[:3, 3] = t
        return m

    def duration(self, name):
        anim = self.animations[name]
        return max(self.accessor(s["input"])[-1, 0] for s in anim["samplers"])

    def sample(self, name, times):
        """Per-joint local (t [n,j,3], r [n,j,4]) at the given times; rest where not animated."""
        n = len(times)
        count = len(self.joints)
        t = np.zeros((n, count, 3))
        r = np.zeros((n, count, 4))
        s = np.ones((n, count, 3))
        for k, node in enumerate(self.joints):
            rt, rr, rs = self.rest_trs(node)
            t[:, k], r[:, k], s[:, k] = rt, rr, rs
        if name is None:
            return t, r, s
        joint_of = {node: k for k, node in enumerate(self.joints)}
        anim = self.animations[name]
        for channel in anim["channels"]:
            node = channel["target"].get("node")
            if node not in joint_of:
                continue
            sampler = anim["samplers"][channel["sampler"]]
            keys = self.accessor(sampler["input"])[:, 0]
            values = self.accessor(sampler["output"])
            if sampler.get("interpolation", "LINEAR") == "CUBICSPLINE":
                values = values[1::3]
            idx = np.clip(np.searchsorted(keys, times, side="right") - 1, 0, len(keys) - 1)
            nxt = np.clip(idx + 1, 0, len(keys) - 1)
            span = np.where(nxt > idx, keys[nxt] - keys[idx], 1.0)
            u = np.clip((times - keys[idx]) / span, 0, 1)[:, None]
            if sampler.get("interpolation") == "STEP":
                u = u * 0
            path = channel["target"]["path"]
            k = joint_of[node]
            if path == "rotation":
                r[:, k] = _slerp(values[idx], values[nxt], u)
            elif path == "translation":
                t[:, k] = values[idx] * (1 - u) + values[nxt] * u
            elif path == "scale":
                s[:, k] = values[idx] * (1 - u) + values[nxt] * u
        return t, r, s

    def positions(self, name, times, include_root_chain=True):
        """Joint world positions [n, joints, 3]."""
        t, r, s = self.sample(name, np.asarray(times, dtype=float))
        n, count = t.shape[:2]
        world = np.zeros((n, count, 4, 4))
        base = np.eye(4)
        if include_root_chain:
            for node in reversed(self.root_chain):
                base = base @ self._node_matrix(node)
        for k in range(count):
            local = np.zeros((n, 4, 4))
            local[:, :3, :3] = quat_to_matrix(r[:, k]) * s[:, k, None, :]
            local[:, :3, 3] = t[:, k]
            local[:, 3, 3] = 1
            p = self.parents[k]
            world[:, k] = (base[None] if p < 0 else world[:, p]) @ local
        return world[:, :, :3, 3]
