class_name ActionPrompt3D
extends Node3D

## Contextual HFN interaction prompt, adapted from ADT's world-space HoldPrompt
## and KeyHints ink choreography.
##
## Visual contract:
##   target acquired -> multiple ink blobs assemble -> key/action fade in
##   target lost     -> key/action fade out -> blobs dissolve
##   F performed     -> key fill warms yellow -> key/action fade out -> blobs dissolve
##
## There is NO rectangular banner/card. The same eight-blob shader used by
## KeyHintsPanel is the entire backing shape.

const GROUP_ACTION_PROMPT: StringName = &"action_prompt_3d"
const BLOT_SHADER: Shader = preload("res://shaders/ui/key_hints_blot.gdshader")

enum Phase {
	HIDDEN,
	APPEARING,
	VISIBLE,
	CONFIRMING,
	HIDING,
}

@export_group("World placement")
## Transparent canvas is deliberately larger than the visible content.
## The extra room is what prevents the ink from reading as a clipped card.
@export var canvas_size: Vector2i = Vector2i(560, 260)
@export var content_size: Vector2i = Vector2i(360, 150)
@export var content_origin: Vector2 = Vector2(150.0, 55.0)
@export var billboard_pixel_size: float = 0.00155
@export var risen_offset: Vector3 = Vector3(0.0, 0.60, 0.0)

@export_group("Ink shape")
## Logical UV margin around the shared ADT blob field. KeyHints keeps the
## shader default (0); only this world prompt asks for breathing room.
@export var ink_canvas_padding: float = 0.20

@export_group("ADT choreography")
@export var ink_appear_duration: float = 0.48
@export var content_fade_in_duration: float = 0.22
@export var ink_settle_duration: float = 0.55
@export var content_fade_out_duration: float = 0.18
@export var ink_dissolve_duration: float = 0.30
@export var confirm_in_duration: float = 0.07
@export var confirm_hold_duration: float = 0.11

var _viewport: SubViewport
var _ink: ColorRect
var _ink_material: ShaderMaterial
var _face: ActionPromptFace
var _billboard: Sprite3D

var _interact: InteractComponent
var _target: InteractiveArea
var _follow_target: InteractiveArea
var _suppressed_after_press: InteractiveArea
var _refresh_left: float = 0.0
var _phase: Phase = Phase.HIDDEN
var _transition: Tween


func _ready() -> void:
	add_to_group(GROUP_ACTION_PROMPT)


func on_world_ready(context: WorldContext) -> void:
	if context == null or context.player == null:
		return
	_interact = context.player.get_node_or_null(^"InteractComponent") as InteractComponent
	if _interact == null:
		return
	_activate_render_surface()
	if not _interact.interaction_performed.is_connected(_on_interaction_performed):
		_interact.interaction_performed.connect(_on_interaction_performed)


func _activate_render_surface() -> void:
	if _viewport != null:
		return

	_viewport = SubViewport.new()
	_viewport.name = "Face"
	_viewport.transparent_bg = true
	_viewport.size = canvas_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_ink = ColorRect.new()
	_ink.name = "Ink"
	_ink.position = Vector2.ZERO
	_ink.size = Vector2(canvas_size)
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = BLOT_SHADER
	_ink_material.set_shader_parameter("progress", 0.0)
	_ink_material.set_shader_parameter("stagger", 0.7)
	_ink_material.set_shader_parameter("entrance_seed", 0.31)
	_ink_material.set_shader_parameter("blob_color", Color(0.015, 0.012, 0.009, 0.92))
	_ink_material.set_shader_parameter("radius_scale", 0.0)
	_ink_material.set_shader_parameter("edge_ragged", 0.052)
	_ink_material.set_shader_parameter("warp_scale", 4.5)
	_ink_material.set_shader_parameter("rect_size", _ink.size)
	_ink_material.set_shader_parameter("idle_drift", 0.0)
	_ink_material.set_shader_parameter("canvas_padding", ink_canvas_padding)
	_ink.material = _ink_material
	_viewport.add_child(_ink)

	_face = ActionPromptFace.new()
	_face.name = "Prompt"
	_face.position = content_origin
	_face.size = Vector2(content_size)
	_face.modulate.a = 0.0
	_viewport.add_child(_face)

	_billboard = Sprite3D.new()
	_billboard.name = "Billboard"
	_billboard.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_billboard.no_depth_test = true
	_billboard.shaded = false
	_billboard.transparent = true
	_billboard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_billboard.pixel_size = billboard_pixel_size
	_billboard.texture = _viewport.get_texture()
	_billboard.visible = false
	add_child(_billboard)


func _process(delta: float) -> void:
	if _interact == null or _viewport == null or _face == null or _billboard == null:
		return

	var raw_candidate: InteractiveArea = null
	if is_instance_valid(_interact.current_target):
		raw_candidate = _interact.current_target

	if _suppressed_after_press != null:
		if raw_candidate != _suppressed_after_press:
			_suppressed_after_press = null
		else:
			raw_candidate = null

	# Let the confirmation sequence finish without a new target interrupting it.
	if _phase == Phase.CONFIRMING:
		_update_world_position()
		return

	var candidate: InteractiveArea = null
	if (
		raw_candidate != null
		and raw_candidate.prompt_shown
		and raw_candidate.can_interact()
	):
		candidate = raw_candidate

	if candidate != null:
		if candidate != _target:
			_target = candidate
			_follow_target = candidate
			_sync_prompt()
			_begin_appear()
		else:
			_refresh_left = maxf(_refresh_left - delta, 0.0)
			if _refresh_left <= 0.0:
				_refresh_left = 0.12
				_sync_prompt()
	elif _target != null:
		_target = null
		if _phase != Phase.HIDDEN and _phase != Phase.HIDING:
			_begin_hide()

	_update_world_position()


func _update_world_position() -> void:
	if _billboard == null or not _billboard.visible:
		return
	if not is_instance_valid(_follow_target):
		return
	_billboard.global_position = _follow_target.global_position + risen_offset


func _sync_prompt() -> void:
	if not is_instance_valid(_target) or _face == null:
		return
	var data := _target.get_interaction_prompt_data()
	var detail: String = String(data.get("detail", ""))
	## Several close objects: show where interact_cycle stands, e.g. "[R] 2/3".
	var place: Vector2i = _interact.get_cluster_position()
	if place != Vector2i.ZERO:
		var cycle: String = "[%s] %d/%d" % [InteractiveArea.action_key_label(&"interact_cycle"), place.x, place.y]
		detail = cycle if detail == "" else "%s · %s" % [detail, cycle]
	_face.set_prompt(
		tr("PROMPT_HEADER_INTERACT"),
		String(data.get("key", "F")),
		String(data.get("action", tr("INTERACT_USE"))),
		detail
	)


func _begin_appear() -> void:
	if _ink_material == null or _face == null:
		return
	_kill_transition()
	_phase = Phase.APPEARING
	_billboard_visible(true)
	_face.modulate.a = 0.0
	_face.set_confirm_amount(0.0)
	_set_blot_progress(0.0)
	_set_blot_radius_scale(0.0)
	_set_blot_entrance_seed(randf())

	_transition = create_tween()
	_transition.tween_method(
		_set_blot_progress, 0.0, 1.0, ink_appear_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.parallel().tween_method(
		_set_blot_radius_scale, 0.0, 0.82, ink_appear_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# ADT order: all blobs first, content second.
	_transition.tween_property(
		_face, "modulate:a", 1.0, content_fade_in_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_method(
		_set_blot_radius_scale, 0.82, 1.0, ink_settle_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_transition.tween_callback(func() -> void:
		_phase = Phase.VISIBLE
	)


func _begin_hide() -> void:
	if _phase == Phase.HIDDEN:
		return
	_kill_transition()
	_phase = Phase.HIDING
	_transition = create_tween()
	# Reverse contract: content fully disappears before the ink starts dissolving.
	_transition.tween_property(
		_face, "modulate:a", 0.0, content_fade_out_duration
	)
	_transition.tween_method(
		_set_blot_progress, _blot_progress(), 0.0, ink_dissolve_duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_transition.parallel().tween_method(
		_set_blot_radius_scale, _blot_radius_scale(), 0.72, ink_dissolve_duration
	)
	_transition.tween_callback(_finish_hidden)


func _on_interaction_performed(target: InteractiveArea) -> void:
	if target != _follow_target or _phase == Phase.HIDDEN:
		return
	_suppressed_after_press = null
	_target = null
	_kill_transition()
	_phase = Phase.CONFIRMING

	_transition = create_tween()
	# A short warmer-yellow key fill is the acknowledgement of the actual press.
	_transition.tween_method(
		_set_confirm_amount, _face.get_confirm_amount(), 1.0, confirm_in_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_transition.tween_interval(confirm_hold_duration)
	# Then the exact same exit order: content first, blobs second.
	_transition.tween_property(
		_face, "modulate:a", 0.0, content_fade_out_duration
	)
	_transition.tween_method(
		_set_blot_progress, _blot_progress(), 0.0, ink_dissolve_duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_transition.parallel().tween_method(
		_set_blot_radius_scale, _blot_radius_scale(), 0.72, ink_dissolve_duration
	)
	_transition.tween_callback(_finish_hidden)


func _finish_hidden() -> void:
	_phase = Phase.HIDDEN
	_face.modulate.a = 0.0
	_face.set_confirm_amount(0.0)
	_set_blot_progress(0.0)
	_set_blot_radius_scale(0.0)
	_billboard_visible(false)
	_follow_target = null


func _set_confirm_amount(value: float) -> void:
	if _face != null:
		_face.set_confirm_amount(value)


func _blot_progress() -> float:
	if _ink_material == null:
		return 0.0
	return float(_ink_material.get_shader_parameter("progress"))


func _set_blot_progress(value: float) -> void:
	if _ink_material != null:
		_ink_material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))


func _blot_radius_scale() -> float:
	if _ink_material == null:
		return 0.0
	return float(_ink_material.get_shader_parameter("radius_scale"))


func _set_blot_radius_scale(value: float) -> void:
	if _ink_material != null:
		_ink_material.set_shader_parameter("radius_scale", clampf(value, 0.0, 2.0))


func _set_blot_entrance_seed(value: float) -> void:
	if _ink_material != null:
		_ink_material.set_shader_parameter("entrance_seed", value)


func _billboard_visible(on: bool) -> void:
	if _billboard == null or _viewport == null:
		return
	_billboard.visible = on
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	)


func _kill_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null


func _exit_tree() -> void:
	_kill_transition()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _billboard != null:
		_billboard.visible = false
		_billboard.texture = null
