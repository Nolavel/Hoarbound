"""Anatomical pose metrics from joint positions only, in a per-frame body frame.

Local bone axes are never read, so any skeleton (CMU, UAL, FBX families, Blender
bakes) is measured the same way once its joints are named (see JOINT_MAPS).
Angles are degrees. Body frame: up = world up, left = hips + shoulders across
vector made horizontal, forward = left x up.
"""

import numpy as np

# Canonical joint -> skeleton joint name. "_end" names are BVH End Sites.
JOINT_MAPS = {
    "UAL": {
        "hips": "pelvis", "chest": "spine_03", "neck": "neck_01", "head": "Head",
        "l_shoulder": "upperarm_l", "l_elbow": "lowerarm_l", "l_wrist": "hand_l",
        "l_index": "index_01_l", "l_thumb": "thumb_01_l",
        "r_shoulder": "upperarm_r", "r_elbow": "lowerarm_r", "r_wrist": "hand_r",
        "r_index": "index_01_r", "r_thumb": "thumb_01_r",
        "l_hip": "thigh_l", "l_knee": "calf_l", "l_ankle": "foot_l", "l_ball": "ball_l", "l_toe": "ball_leaf_l",
        "r_hip": "thigh_r", "r_knee": "calf_r", "r_ankle": "foot_r", "r_ball": "ball_r", "r_toe": "ball_leaf_r",
    },
    "CMU": {
        "hips": "Hips", "chest": "Spine1", "neck": "Neck1", "head": "Head",
        "l_shoulder": "LeftArm", "l_elbow": "LeftForeArm", "l_wrist": "LeftHand",
        "l_index": "LeftHandIndex1_end", "l_thumb": "LThumb_end",
        "r_shoulder": "RightArm", "r_elbow": "RightForeArm", "r_wrist": "RightHand",
        "r_index": "RightHandIndex1_end", "r_thumb": "RThumb_end",
        "l_hip": "LeftUpLeg", "l_knee": "LeftLeg", "l_ankle": "LeftFoot", "l_ball": "LeftToeBase", "l_toe": "LeftToeBase_end",
        "r_hip": "RightUpLeg", "r_knee": "RightLeg", "r_ankle": "RightFoot", "r_ball": "RightToeBase", "r_toe": "RightToeBase_end",
    },
}

JOINT_MAPS["CMU_V2"] = JOINT_MAPS["CMU"]
JOINT_MAPS["100STYLE"] = {
    "hips": "Hips", "chest": "Chest4", "neck": "Neck", "head": "Head",
    "l_shoulder": "LeftShoulder", "l_elbow": "LeftElbow", "l_wrist": "LeftWrist", "l_index": "LeftWrist_end",
    "r_shoulder": "RightShoulder", "r_elbow": "RightElbow", "r_wrist": "RightWrist", "r_index": "RightWrist_end",
    "l_hip": "LeftHip", "l_knee": "LeftKnee", "l_ankle": "LeftAnkle", "l_ball": "LeftToe", "l_toe": "LeftToe_end",
    "r_hip": "RightHip", "r_knee": "RightKnee", "r_ankle": "RightAnkle", "r_ball": "RightToe", "r_toe": "RightToe_end",
}

UP = np.array([0.0, 1.0, 0.0])
# A hinge bent less than this has no measurable bend plane.
PLANE_MIN_FLEX = 15.0
# Metrics that depend on where a rig puts its joints; also reported relative to
# the rig's own neutral pose (suffix _rel) so different skeletons compare.
RIG_DEPENDENT = ("trunk_lean_fwd", "neck_pitch_fwd", "spine_bend", "l_foot_pitch", "r_foot_pitch",
                 "l_ball_bend", "r_ball_bend", "l_wrist_bend", "r_wrist_bend")


def canonical(positions, names, family):
    """[n, joints, 3] + joint names -> {canonical: [n, 3]} for the joints present."""
    mapping = JOINT_MAPS[family]
    index = {name: i for i, name in enumerate(names)}
    return {key: positions[:, index[name]] for key, name in mapping.items() if name in index}


def _unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


def _dot(a, b):
    return np.sum(a * b, axis=-1)


def _angle(a, b):
    return np.degrees(np.arccos(np.clip(_dot(_unit(a), _unit(b)), -1, 1)))


def _reject(v, axis):
    """Component of v perpendicular to the (unit) axis."""
    return v - _dot(v, axis)[..., None] * axis


def body_frame(j):
    across = _unit(j["l_hip"] - j["r_hip"]) + _unit(j["l_shoulder"] - j["r_shoulder"])
    left = _unit(_reject(across, UP))
    forward = _unit(np.cross(left, UP))
    return left, forward


def _signed_plane_angle(v, reference, axis):
    """Angle from reference to v around axis, both projected onto the axis plane."""
    a = _unit(_reject(reference, axis))
    b = _unit(_reject(v, axis))
    return np.degrees(np.arctan2(_dot(np.cross(a, b), axis), _dot(a, b)))


def _hinge(top, mid, low, front):
    """Flexion of a hinge (0 = straight), signed: negative bends against `front`.

    Also returns the bend-plane deviation: angle between where the joint points
    and `front`, around the top-low axis (0 = bends exactly toward front).
    """
    flex = 180.0 - _angle(top - mid, low - mid)
    axis = _unit(low - top)
    bend = _reject(mid - top, axis)
    sign = np.where(_dot(bend, front) >= 0, 1.0, -1.0)
    deviation = np.abs(_signed_plane_angle(bend, front, axis))
    deviation = np.where(flex >= PLANE_MIN_FLEX, deviation, np.nan)
    return flex * sign, deviation


def frame_metrics(j, neutral=None):
    """Per-frame metric arrays {name: [n]}; `neutral` is one frame of the rig's
    own neutral pose (rest T-pose, reference frame) for the _rel metrics."""
    m = _absolute_metrics(j)
    if neutral is not None:
        base = _absolute_metrics(neutral)
        for name in RIG_DEPENDENT:
            if name in m and name in base:
                m[name + "_rel"] = m[name] - base[name][0]
    return m


def _absolute_metrics(j):
    left, forward = body_frame(j)
    m = {}
    trunk = j["neck"] - j["hips"]
    m["trunk_lean_fwd"] = np.degrees(np.arctan2(_dot(trunk, forward), _dot(trunk, UP)))
    m["trunk_lean_side"] = np.degrees(np.arctan2(_dot(trunk, left), _dot(trunk, UP)))
    neck = j["head"] - j["neck"]
    m["neck_pitch_fwd"] = np.degrees(np.arctan2(_dot(neck, forward), _dot(neck, UP)))
    hip_line = j["l_hip"] - j["r_hip"]
    shoulder_line = j["l_shoulder"] - j["r_shoulder"]
    m["pelvis_list"] = np.degrees(np.arcsin(np.clip(_dot(_unit(hip_line), UP), -1, 1)))
    m["trunk_twist"] = _signed_plane_angle(shoulder_line, hip_line, UP)
    lower = j["chest"] - j["hips"]
    upper = j["head"] - j["chest"]
    m["spine_bend"] = _angle(lower, upper)
    for side, outward_sign in (("l", 1.0), ("r", -1.0)):
        outward = left * outward_sign
        hip, knee, ankle = j[side + "_hip"], j[side + "_knee"], j[side + "_ankle"]
        ball = j[side + "_ball"]
        foot = ball - ankle
        m[side + "_knee_flex"], m[side + "_knee_plane"] = _hinge(hip, knee, ankle, forward)
        thigh = knee - hip
        m[side + "_hip_flex"] = np.degrees(np.arctan2(_dot(thigh, forward), -_dot(thigh, UP)))
        m[side + "_hip_abd"] = np.degrees(np.arctan2(_dot(thigh, outward), -_dot(thigh, UP)))
        knee_bend = _reject(knee - hip, _unit(ankle - hip))
        m[side + "_knee_dir"] = _signed_plane_angle(knee_bend, forward, UP) * outward_sign
        m[side + "_foot_progression"] = _signed_plane_angle(foot, forward, UP) * outward_sign
        m[side + "_foot_pitch"] = np.degrees(np.arcsin(np.clip(_dot(_unit(foot), UP), -1, 1)))
        if side + "_toe" in j:
            m[side + "_ball_bend"] = _angle(foot, j[side + "_toe"] - ball)
        shoulder, elbow, wrist = j[side + "_shoulder"], j[side + "_elbow"], j[side + "_wrist"]
        upper_arm = elbow - shoulder
        m[side + "_arm_flex"] = np.degrees(np.arctan2(_dot(upper_arm, forward), -_dot(upper_arm, UP)))
        m[side + "_arm_abd"] = np.degrees(np.arctan2(_dot(upper_arm, outward), -_dot(upper_arm, UP)))
        m[side + "_elbow_flex"], m[side + "_elbow_plane"] = _hinge(shoulder, elbow, wrist, -forward)
        hip_half = _dot(hip - j["hips"], outward)
        m[side + "_hand_clear"] = _dot(wrist - j["hips"], outward) - hip_half
        forearm = _unit(wrist - elbow)
        if side + "_thumb" in j:
            thumb = j[side + "_thumb"] - wrist
            m[side + "_forearm_roll"] = _signed_plane_angle(thumb, forward, forearm) * outward_sign
        if side + "_index" in j:
            m[side + "_wrist_bend"] = _angle(forearm, j[side + "_index"] - wrist)
    return m


def summary(metrics):
    """Robust per-metric statistics."""
    out = {}
    for name, values in metrics.items():
        v = np.asarray(values, dtype=float)
        v = v[np.isfinite(v)]
        if v.size == 0:
            continue
        out[name] = {
            "p5": float(np.percentile(v, 5)), "median": float(np.median(v)),
            "p95": float(np.percentile(v, 95)), "range": float(np.percentile(v, 95) - np.percentile(v, 5)),
        }
    return out


def difference(metrics_a, metrics_b):
    """Per-metric |a - b| statistics over frames present in both."""
    out = {}
    for name in metrics_a:
        if name not in metrics_b:
            continue
        d = np.abs(np.asarray(metrics_a[name], dtype=float) - np.asarray(metrics_b[name], dtype=float))
        d = d[np.isfinite(d)]
        if d.size == 0:
            continue
        if name.endswith("hand_clear"):
            d = d * 100.0  # centimetres
        out[name] = {"median": float(np.median(d)), "p95": float(np.percentile(d, 95)), "max": float(np.max(d))}
    return out


# Anatomical limits (degrees) that no normal walking pose crosses.
LIMITS = {
    "knee_hyperextension": -5.0,  # signed knee flexion below this bends backwards
    "knee_plane": 45.0,  # bend direction this far from body forward, while flexed > 15
    "elbow_hyperextension": -5.0,
}


def failures(metrics):
    """Frame counts that break anatomical limits, per side."""
    out = {}
    for side in ("l", "r"):
        flex = np.asarray(metrics[side + "_knee_flex"])
        plane = np.asarray(metrics[side + "_knee_plane"])
        out[side + "_knee_backward"] = int(np.sum(flex < LIMITS["knee_hyperextension"]))
        out[side + "_knee_off_plane"] = int(np.sum(np.nan_to_num(plane) > LIMITS["knee_plane"]))
        out[side + "_elbow_backward"] = int(np.sum(np.asarray(metrics[side + "_elbow_flex"]) < LIMITS["elbow_hyperextension"]))
    return out


# UAL bones whose twist (roll about the bone's own +Y axis, relative to rest) is
# measured; a large hand twist with no forearm twist is the candy-wrapper wrist.
TWIST_BONES = ("upperarm", "lowerarm", "hand", "thigh", "calf", "foot")


def _quat_multiply(a, b):
    ax, ay, az, aw = np.moveaxis(a, -1, 0)
    bx, by, bz, bw = np.moveaxis(b, -1, 0)
    return np.stack([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ], axis=-1)


def bone_twist(local, rest, names):
    """local [n, bones, 4] and rest [bones, 4] xyzw quaternions (UAL rig) ->
    {side_bone_twist: degrees about the bone's +Y, relative to rest}."""
    local = np.asarray(local, dtype=float)
    rest = np.asarray(rest, dtype=float)
    out = {}
    for side in ("l", "r"):
        for bone in TWIST_BONES:
            k = names.index("%s_%s" % (bone, side))
            inverse = rest[k] * np.array([-1.0, -1.0, -1.0, 1.0])
            delta = _quat_multiply(np.broadcast_to(inverse, local[:, k].shape), local[:, k])
            angle = 2.0 * np.degrees(np.arctan2(delta[:, 1], delta[:, 3]))
            out["%s_%s_twist" % (side, bone)] = (angle + 180.0) % 360.0 - 180.0
    return out


def matrix_twist(relative, axis):
    """Twist (degrees) of rotation matrices [n, 3, 3] about a unit axis in their frame."""
    m = relative
    w = np.sqrt(np.maximum(1.0 + m[:, 0, 0] + m[:, 1, 1] + m[:, 2, 2], 1e-12)) / 2.0
    x = (m[:, 2, 1] - m[:, 1, 2]) / (4.0 * w)
    y = (m[:, 0, 2] - m[:, 2, 0]) / (4.0 * w)
    z = (m[:, 1, 0] - m[:, 0, 1]) / (4.0 * w)
    along = x * axis[0] + y * axis[1] + z * axis[2]
    angle = 2.0 * np.degrees(np.arctan2(along, w))
    return (angle + 180.0) % 360.0 - 180.0


# Source limb joint -> child joint, for the source's own axial roll (100STYLE names).
SOURCE_TWIST = {
    "100STYLE": {"thigh": ("LeftHip", "LeftKnee", "RightHip", "RightKnee"),
                 "calf": ("LeftKnee", "LeftAnkle", "RightKnee", "RightAnkle")},
}


def source_twist(bvh, frames, family, reference_local=None):
    """Axial roll of source thigh and calf relative to their parents, from the reference
    pose, about the segment axis: the same quantity bone_twist measures on Henry."""
    if family not in SOURCE_TWIST:
        return {}
    local = bvh.local_rotations(frames)
    out = {}
    for bone, (left, left_child, right, right_child) in SOURCE_TWIST[family].items():
        for side, joint, child in (("l", left, left_child), ("r", right, right_child)):
            j = bvh.index(joint)
            axis = bvh.offsets[bvh.index(child)]
            axis = axis / np.linalg.norm(axis)
            ref = np.eye(3) if reference_local is None else reference_local[j]
            relative = np.einsum("ji,njk->nik", ref, local[:, j])
            out["%s_%s_twist" % (side, bone)] = matrix_twist(relative, axis)
    return out
