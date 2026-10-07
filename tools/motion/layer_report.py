"""Retarget layer report: oracle check, anatomy of source / Henry layers / UAL.

Usage: python3 tools/motion/layer_report.py DUMP.json [OUT.json]
DUMP.json comes from tools/runtime/dump_retarget_layers.gd.
"""

import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anatomy  # noqa: E402
import bvh_fk  # noqa: E402
import gltf_fk  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CMU_DIR = os.path.join(ROOT, "tests", "motion_matching", "_runtime_cmu")
HENRY_GLB = os.path.join(ROOT, "assets", "characters", "henry", "henry_outfit.glb")
UAL_CLIPS = ("Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Idle_Loop")
# Metrics printed in the table, with the statistic that tells the story.
TABLE = (
    ("trunk_lean_fwd", "median"), ("trunk_lean_side", "range"), ("neck_pitch_fwd", "median"),
    ("trunk_twist", "range"), ("pelvis_list", "range"),
    ("l_arm_abd", "median"), ("r_arm_abd", "median"), ("l_arm_flex", "range"), ("r_arm_flex", "range"),
    ("l_elbow_flex", "median"), ("l_elbow_plane", "p95"), ("l_hand_clear", "median"), ("r_hand_clear", "median"),
    ("l_forearm_roll", "median"), ("l_wrist_bend", "median"),
    ("l_knee_flex", "p5"), ("l_knee_flex", "p95"), ("r_knee_flex", "p5"), ("l_knee_plane", "p95"),
    ("l_knee_dir", "median"), ("l_foot_progression", "median"), ("l_foot_pitch", "p5"), ("l_foot_pitch", "p95"),
    ("l_ball_bend", "p95"), ("l_hip_flex", "range"),
    ("trunk_lean_fwd_rel", "median"), ("neck_pitch_fwd_rel", "median"), ("spine_bend_rel", "median"),
    ("l_foot_pitch_rel", "p5"), ("l_foot_pitch_rel", "p95"), ("l_ball_bend_rel", "p95"), ("l_wrist_bend_rel", "median"),
    ("l_upperarm_twist", "range"), ("l_lowerarm_twist", "range"), ("l_hand_twist", "p5"), ("l_hand_twist", "p95"),
    ("r_hand_twist", "p5"), ("r_hand_twist", "p95"), ("l_thigh_twist", "range"), ("l_calf_twist", "range"),
    ("l_foot_twist", "range"),
)


def henry_neutral():
    glb = gltf_fk.GLB(HENRY_GLB)
    return anatomy.canonical(glb.positions(None, [0.0]), glb.names, "UAL")


def ual_envelope(neutral):
    glb = gltf_fk.GLB(HENRY_GLB)
    rest = np.array([glb.rest_trs(node)[1] for node in glb.joints])
    out = {}
    for name in UAL_CLIPS:
        times = np.arange(0.0, glb.duration(name), 1.0 / 30.0)
        joints = anatomy.canonical(glb.positions(name, times), glb.names, "UAL")
        out[name] = anatomy.frame_metrics(joints, neutral)
        out[name].update(anatomy.bone_twist(glb.sample(name, times)[1], rest, glb.names))
    return out


def clip_report(key, clip, henry_bones, henry_rest, neutral):
    dataset, name = key.split(":")
    bvh = bvh_fk.BVH(os.path.join(CMU_DIR, name + ".bvh"), clip["units_to_meters"])
    oracle = bvh.positions(clip["source_frames"])
    godot = np.array(clip["source"]).reshape(len(clip["source_frames"]), -1, 3)
    shared = [bvh.index(n) for n in clip["source_bones"]]
    oracle_error = float(np.max(np.linalg.norm(oracle[:, shared] - godot, axis=-1)))
    reference = anatomy.canonical(bvh.positions([0]), bvh.names, dataset)
    source = anatomy.frame_metrics(anatomy.canonical(oracle, bvh.names, dataset), reference)
    layers = {}
    for layer, data in clip["layers"].items():
        positions = np.array(data["frames"]).reshape(len(data["frames"]), -1, 3)
        layers[layer] = anatomy.frame_metrics(anatomy.canonical(positions, henry_bones, "UAL"), neutral)
        rotations = np.array(data["rotations"]).reshape(len(data["rotations"]), -1, 4)
        layers[layer].update(anatomy.bone_twist(rotations, henry_rest, henry_bones))
    return oracle_error, source, layers


def _cell(metrics, name, stat):
    if name not in metrics:
        return "—"
    return "%.1f" % anatomy.summary({name: metrics[name]})[name][stat]


def print_table(columns):
    names = list(columns.keys())
    print("%-24s" % "metric" + "".join("%11s" % n[:11] for n in names))
    for metric, stat in TABLE:
        label = "%s %s" % (metric, stat)
        print("%-24s" % label[:24] + "".join("%11s" % _cell(columns[n], metric, stat) for n in names))


def main():
    dump = json.load(open(sys.argv[1]))
    neutral = henry_neutral()
    envelope = ual_envelope(neutral)
    henry_rest = np.array(dump["henry_rest_rotations"]).reshape(-1, 4)
    result = {"ual": {k: anatomy.summary(v) for k, v in envelope.items()}, "clips": {}}
    for key, clip in dump["clips"].items():
        if "error" in clip:
            print(key, "ERROR", clip["error"])
            continue
        oracle_error, source, layers = clip_report(key, clip, dump["henry_bones"], henry_rest, neutral)
        print("\n== %s  (%d frames, oracle vs BVHClip max %.2f mm)" % (key, len(clip["times"]), oracle_error * 1000))
        columns = {"L0_source": source}
        columns.update(layers)
        columns["UAL_walk"] = envelope["Walk_Loop"]
        columns["UAL_jog"] = envelope["Jog_Fwd_Loop"]
        print_table(columns)
        print("failures:", {n: anatomy.failures(m) for n, m in columns.items()})
        diffs = {layer: anatomy.difference(m, source) for layer, m in layers.items()}
        result["clips"][key] = {
            "oracle_error_m": oracle_error,
            "source": anatomy.summary(source),
            "layers": {layer: anatomy.summary(m) for layer, m in layers.items()},
            "difference_to_source": diffs,
            "failures": {n: anatomy.failures(m) for n, m in columns.items()},
        }
        print("median |layer - source| (deg; hand_clear cm):")
        worst = sorted(diffs["L4_full"].items(), key=lambda kv: -kv[1]["median"])[:12]
        for metric, _ in worst:
            print("  %-22s" % metric + "".join("  %s %5.1f" % (layer[:2], diffs[layer][metric]["median"]) for layer in diffs))
    if len(sys.argv) > 2:
        json.dump(result, open(sys.argv[2], "w"), indent=1)


if __name__ == "__main__":
    main()
