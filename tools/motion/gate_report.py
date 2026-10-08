"""Gate summary across clips: one row per clip and variant, upper body, legs, limit breaks.

Usage: python3 tools/motion/gate_report.py DUMP.json [VARIANT ...]
Prints a Markdown table (source row first) for docs/motion_matching/gate_c.md.
"""

import json
import sys

import numpy as np

import layer_report

COLUMNS = (
    ("arm abd", ("l_arm_abd", "r_arm_abd"), "median"),
    ("elbow", ("l_elbow_flex",), "median"),
    ("wrist", ("l_wrist_bend",), "median"),
    ("hand twist |p95|", ("l_hand_twist", "r_hand_twist"), "abs95"),
    ("neck rel", ("neck_pitch_fwd_rel",), "median"),
    ("lean rel", ("trunk_lean_fwd_rel",), "median"),
    ("knee p95", ("l_knee_flex", "r_knee_flex"), "p95"),
    ("knee plane p95 L/R", ("l_knee_plane", "r_knee_plane"), "pair95"),
    ("thigh roll", ("l_thigh_twist", "r_thigh_twist"), "range"),
    ("calf roll", ("l_calf_twist", "r_calf_twist"), "range"),
)


def cell(metrics, names, stat):
    values = [np.asarray(metrics[n], dtype=float) for n in names if n in metrics]
    values = [v[np.isfinite(v)] for v in values]
    if not values or any(v.size == 0 for v in values):
        return "—"
    if stat == "pair95":
        return " / ".join("%.0f" % np.percentile(v, 95) for v in values)
    if stat == "abs95":
        return "%.0f" % max(np.percentile(np.abs(v), 95) for v in values)
    if stat == "range":
        return "%.0f" % max(np.percentile(v, 95) - np.percentile(v, 5) for v in values)
    func = {"median": np.median, "p95": lambda v: np.percentile(v, 95)}[stat]
    return "%.0f" % np.mean([func(v) for v in values])


def breaks(metrics):
    fails = layer_report.anatomy.failures(metrics)
    knees = fails["l_knee_backward"] + fails["r_knee_backward"]
    elbows = fails["l_elbow_backward"] + fails["r_elbow_backward"]
    return "%d / %d" % (knees, elbows)


def main():
    dump = json.load(open(sys.argv[1]))
    variants = sys.argv[2:]
    neutral = layer_report.henry_neutral()
    henry_rest = np.array(dump["henry_rest_rotations"]).reshape(-1, 4)
    header = ["clip", "variant"] + [c[0] for c in COLUMNS] + ["back knees / elbows"]
    print("| " + " | ".join(header) + " |")
    print("|" + " --- |" * len(header))
    for key, clip in dump["clips"].items():
        _, source, layers = layer_report.clip_report(key, clip, dump["henry_bones"], henry_rest, neutral)
        rows = [("source", source)] + [(v, layers[v]) for v in (variants or layers.keys()) if v in layers]
        for name, metrics in rows:
            print("| %s | %s | " % (key.split(":")[1], name) + " | ".join(cell(metrics, n, s) for _, n, s in COLUMNS)
                  + " | %s |" % breaks(metrics))


if __name__ == "__main__":
    main()
