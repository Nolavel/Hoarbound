class_name TpsRigComposition
extends TpsRigBehaviour

## Tight-space composition (Grossman, NZGDC 2025): in cramped rooms Henry sits low at the
## side of the frame, on the distance the camera really has, so a pressed camera keeps him.

## 0 in the open, 1 with the tight-space composition fully on.
var _composition: float = 0.0


func get_composition() -> float:
	return _composition


## Eases the composition to the room's tightness and moves frame.side toward Grossman's
## framing, plus the player's lean. `shoulder` is the shoulder offset after the auto swap.
func frame_side(frame: TpsRigFrame, shoulder: float) -> void:
	var goal: float = 1.0 - smoothstep(0.0, rig.composition_open_share, pow(rig.get_room(), rig.openness_exponent))
	_composition = goal if not rig.is_placed() else lerpf(_composition, goal, TpsCamera.damp(rig.composition_rate, frame.delta))
	var shoulder_sign: float = clampf(shoulder / maxf(rig.shoulder_offset, 0.01), -1.0, 1.0)
	## A doorway owns its framing: the composition gives way to it.
	frame.framing = _composition * (1.0 - rig.get_passage_blend())
	## Grossman's framing on the distance the camera really has (walls applied last frame), so a
	## camera pressed in keeps Henry on his spot instead of pushing him out of the frame.
	frame.side = lerpf(frame.side, shoulder_sign * rig.get_boom_length() * rig.get_boom_share() * _composition_tan_x(), frame.framing) \
			+ rig.get_lean() * rig.lean_camera_offset


## Raises the pivot along the camera's up axis so the eyes sit at composition_eye_screen_y;
## pitch-driven like Grossman's curves, so looking up Henry already drops in the frame.
func rise(frame: TpsRigFrame) -> void:
	var cam_up: Vector3 = Basis.from_euler(Vector3(deg_to_rad(frame.orbit_pitch), frame.orbit_yaw, 0.0)).y
	var look_up: float = smoothstep(-10.0, 25.0, frame.view_pitch)
	frame.pivot += cam_up * _composition_up(frame.pivot, cam_up, frame.want) * frame.framing * (1.0 - frame.lift) * (1.0 - look_up)


## Rise along the camera's up axis that puts Henry's eyes at composition_eye_screen_y, on the
## distance the camera really has; the shoulder sweep still owns the ceiling.
func _composition_up(pivot: Vector3, cam_up: Vector3, want: float) -> float:
	var eye_up: float = (rig.get_eye_position() - pivot).dot(cam_up)
	var target_ndc: float = 1.0 - 2.0 * rig.composition_eye_screen_y
	return clampf(eye_up - target_ndc * want * rig.get_boom_share() * rig.half_tangents().y, -0.1, 0.4)


## Lateral offset per metre of boom that puts the eyes at composition_eye_screen_x:
## it scales with the boom, so the framing holds at any distance (Grossman, NZGDC 2025).
func _composition_tan_x() -> float:
	return (1.0 - 2.0 * rig.composition_eye_screen_x) * rig.half_tangents().x
