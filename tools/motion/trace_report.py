"""In-game pose trace report: anatomy, limit breaks and twitch per program segment.

Usage: python3 tools/motion/trace_report.py NAME=TRACE.json [NAME=TRACE.json ...]
Traces come from capture_motion_matching_player.gd with MM_POSE_TRACE=<path>.
"""

import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anatomy  # noqa: E402
import layer_report  # noqa: E402

SEGMENT_METRICS = (
    ("trunk_lean_fwd_rel", "median"), ("neck_pitch_fwd_rel", "median"),
    ("l_arm_abd", "median"), ("l_arm_flex", "range"), ("l_elbow_flex", "median"),
    ("l_hand_twist", "range"), ("l_lowerarm_twist", "range"),
    ("l_knee_flex", "p5"), ("l_knee_flex", "p95"), ("l_hip_flex", "range"),
)
# Second difference of a joint angle per frame at 30 Hz; above this it reads as a snap.
TWITCH_DEG = 6.0


def load(path, neutral):
    trace = json.load(open(path))
    names = list(trace["bones"])
    frames = trace["frames"]
    positions = np.array([f["positions"] for f in frames]).reshape(len(frames), -1, 3)
    rotations = np.array([f["rotations"] for f in frames]).reshape(len(frames), -1, 4)
    rest = np.array(trace["rest_rotations"]).reshape(-1, 4)
    metrics = anatomy.frame_metrics(anatomy.canonical(positions, names, "UAL"), neutral)
    metrics.update(anatomy.bone_twist(rotations, rest, names))
    info = {
        "label": np.array([f["label"] for f in frames]),
        "weight": np.array([f["weight"] for f in frames]),
        "speed": np.array([f["speed"] for f in frames]),
        "switched": np.array([bool(f.get("switched", False)) for f in frames]),
        "clip": [f.get("clip", "") for f in frames],
    }
    return metrics, info


def twitch(metrics, mask):
    out = {}
    for name in ("l_knee_flex", "r_knee_flex", "l_hip_flex", "r_hip_flex", "l_elbow_flex", "l_arm_flex", "trunk_lean_fwd"):
        v = np.asarray(metrics[name], dtype=float)
        second = np.abs(v[2:] - 2 * v[1:-1] + v[:-2])
        m = mask[1:-1]
        out[name] = {"p99": float(np.percentile(second[m], 99)) if m.any() else 0.0,
                     "snaps": int(np.sum(second[m] > TWITCH_DEG))}
    return out


def main():
    neutral = layer_report.henry_neutral()
    runs = {}
    for argument in sys.argv[1:]:
        name, path = argument.split("=", 1)
        runs[name] = load(path, neutral)
    labels = []
    for _, info in runs.values():
        for label in info["label"]:
            if label not in labels:
                labels.append(label)
    print("%-40s %-10s" % ("segment / metric", "run") + "".join("%9s" % m[:9] for m, _ in SEGMENT_METRICS))
    for label in labels:
        for name, (metrics, info) in runs.items():
            mask = info["label"] == label
            if not mask.any():
                continue
            cells = []
            for metric, stat in SEGMENT_METRICS:
                v = np.asarray(metrics[metric])[mask]
                s = anatomy.summary({metric: v}).get(metric)
                cells.append("%9.1f" % s[stat] if s else "%9s" % "—")
            print("%-40s %-10s" % (label[:40], name) + "".join(cells))
    print()
    for name, (metrics, info) in runs.items():
        moving = info["speed"] > 0.2
        fails = anatomy.failures({k: np.asarray(v)[moving] for k, v in metrics.items()})
        print("%-10s moving frames %d, limit breaks %s" % (name, int(moving.sum()), fails))
        print("           twitch (2nd diff deg/frame p99 / frames > %.0f): %s" % (
            TWITCH_DEG, {k: "%.1f/%d" % (v["p99"], v["snaps"]) for k, v in twitch(metrics, moving).items()}))
        knee_bad = np.where((np.asarray(metrics["l_knee_flex"]) < -5) | (np.asarray(metrics["r_knee_flex"]) < -5))[0]
        if knee_bad.size:
            print("           knee backward at t =", [round(float(i) / 30.0, 2) for i in knee_bad[:20]],
                  "segments", sorted(set(info["label"][knee_bad])))


if __name__ == "__main__":
    main()
