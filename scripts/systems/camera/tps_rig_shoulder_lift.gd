class_name TpsRigShoulderLift
extends TpsRigBehaviour

## Over the shoulder: with little level room behind Henry the camera rises over him and tilts
## down, and the view keeps his eyes inside the frame's lower edge.

## 0 with room behind Henry, 1 with the camera fully over his shoulder.
var _lift: float = 0.0
var _lift_hold: float = 0.0


func get_lift() -> float:
	return _lift


## Lifts the frame: tilts the view and the orbit down and raises the pivot, by the lift share
## a doorway leaves. Sets frame.lift.
func apply(frame: TpsRigFrame) -> void:
	frame.lift = _update_lift(frame.delta, frame.safe, frame.view_yaw) * (1.0 - rig.get_passage_blend())
	frame.view_pitch = clampf(frame.view_pitch - frame.lift * rig.shoulder_lift_view_deg, rig.pitch_min_deg, rig.pitch_max_deg)
	frame.orbit_pitch = clampf(frame.orbit_pitch - frame.lift * rig.shoulder_lift_pitch_deg, -85.0, rig.pitch_max_deg)
	frame.pivot += Vector3.UP * frame.lift * _lift_rise(frame.pivot)


## After the camera is placed: tilts the view down as far as Henry's eyes need to stay inside
## the frame, by how lifted or pressed the camera is.
func keep_eyes(frame: TpsRigFrame) -> void:
	frame.view_pitch = _keep_eyes_in_frame(frame.view_pitch, frame.camera, smoothstep(0.0, 0.2, maxf(frame.lift, pressed())))


## 0 with the camera outside guard_soft_distance of Henry's eyes, 1 at guard_eye_distance.
func pressed() -> float:
	return clampf(inverse_lerp(rig.guard_soft_distance, rig.guard_eye_distance, rig.get_last_eye_distance()), 0.0, 1.0)


## Eases the shoulder lift to how little level room is behind Henry along the view. Cast from
## inside him, so the lift never changes the room it reads (no feedback across frames).
func _update_lift(delta: float, safe: Vector3, view_yaw: float) -> float:
	var room: float = rig.get_probe().sweep(safe, TpsCamera.back_dir(view_yaw, 0.0) * maxf(rig.get_boom_length(), rig.shoulder_lift_free_room))
	var goal: float = 1.0 - smoothstep(rig.shoulder_lift_full_room, rig.shoulder_lift_free_room, room)
	## Pressed towards Henry by walking (the mouse guard cannot help), the lift climbs up to 4x faster.
	var rate: float = rig.shoulder_lift_in_rate * (1.0 + 3.0 * pressed()) if goal > _lift else rig.shoulder_lift_out_rate
	if goal > _lift:
		_lift_hold = 0.0
	else:
		_lift_hold += delta
		if _lift_hold < rig.collision_hold_time:
			rate = 0.0
	_lift = goal if not rig.is_placed() else lerpf(_lift, goal, TpsCamera.damp(rate, delta))
	return _lift


## Over the shoulder, tilts the view down as far as Henry's eyes need to stay
## shoulder_lift_frame_margin_deg inside the frame's lower edge, from where they really are.
func _keep_eyes_in_frame(view_pitch: float, camera: Vector3, lift: float) -> float:
	if lift <= 0.001:
		return view_pitch
	var to_eye: Vector3 = rig.get_eye_position() - camera
	if to_eye.length_squared() < 1e-6:
		return view_pitch
	var below_deg: float = rad_to_deg(asin(clampf(-to_eye.normalized().y, -1.0, 1.0)))
	var limit: float = -(below_deg - (rig.half_fov_deg(false) - rig.shoulder_lift_frame_margin_deg))
	return clampf(lerpf(view_pitch, minf(view_pitch, limit), lift), rig.pitch_min_deg, rig.pitch_max_deg)


## Pivot rise at full lift: shoulder_lift_rise, or what the ceiling leaves above the pivot.
func _lift_rise(pivot: Vector3) -> float:
	var clearance: float = rig.collision_radius + rig.collision_surface_margin
	var room: float = rig.get_probe().ray(pivot, Vector3.UP * (rig.shoulder_lift_rise + clearance)) - clearance
	return clampf(room, 0.0, rig.shoulder_lift_rise)
