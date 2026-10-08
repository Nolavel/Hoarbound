class_name MouseCursorUI
extends Control

## ADT's centre ring, brightening over interactables, carrying this project's
## movement dot, stamina-coloured sprint arcs and jump arc around it.

@export var player: CharacterBody3D
@export var cursor_radius: float = 8.0
@export var cursor_thickness: float = 2.0
## Brush Enso replaces only the centre ring. Sprint/jump stamina arcs keep
## their existing geometry and behaviour.
@export var cursor_enso_scale: float = 1.10
## Nothing under the ring.
@export var cursor_color_idle: Color = Color(0.62, 0.64, 0.66, 0.75)
## An interactable under the ring.
@export var cursor_color_target: Color = Color(1.0, 1.0, 1.0, 0.95)
## Not instant: a highlight that snaps in reads as a flicker.
@export var cursor_color_speed: float = 10.0

@export_group("Interaction morph")
## ADT-derived interruptible circle -> bracket morph. The brackets first tear
## from the Enso, then travel outward to make room for the ink prompt.
@export_range(0.12, 0.7, 0.01) var interaction_morph_duration: float = 0.34
@export_range(1.0, 4.0, 0.1) var interaction_morph_ease_power: float = 2.4
@export_range(0.0, 0.8, 0.01) var interaction_split_delay: float = 0.16
@export_range(1.0, 1.35, 0.01) var interaction_morph_punch: float = 1.10
@export_range(0.0, 0.35, 0.01) var interaction_morph_overshoot: float = 0.12
@export_range(0.0, 1.2, 0.05) var interaction_morph_glow: float = 0.40
@export var interaction_bracket_offset: float = 250.0
@export var interaction_bracket_radius: float = 24.0
@export var interaction_bracket_thickness: float = 2.6
## One continuous yellow gradient lives under the entire key/action block.
## Centre stays denser under F + action text; both ends soften toward brackets.
@export var interaction_gradient_color: Color = Color(1.0, 0.823529, 0.0, 1.0)
@export_range(0.0, 1.0, 0.01) var interaction_gradient_center_alpha: float = 0.44
## Final profile: a compact fully-dense centre, then one continuous fade
## on each side all the way to alpha=0 at the ends. No alpha "steps".
@export var interaction_gradient_core_width: float = 20.0
## Slightly tighter than the first pass: enough room for F + action/detail,
## but no longer reaching as far toward the brackets.
@export var interaction_gradient_width: float = 420.0
@export var interaction_gradient_height: float = 38.0
@export var prompt_content_size: Vector2 = Vector2(360.0, 150.0)

@export_group("Movement and stamina")
@export var movement_controller: MovementController
@export var stamina_manager: StaminaManager
@export var movement_dot_color: Color = Color.GRAY
@export var movement_dot_bright_color: Color = Color.WHITE
@export var sprint_arc_thickness: float = 4.0
@export var sprint_arc_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export var sprint_animation_speed: float = 2.0
## Below this speed Henry counts as standing still, m/s.
@export var stationary_speed: float = 0.05

const RING_SEGMENTS: int = 32
const JUMP_ARC_COLOR: Color = Color(0.4, 0.8, 1.0)
const CURSOR_ENSO_PATH := "res://assets/ui/hud/dynamic_cursor/enso_cursor_ring.svg"
const GROUP_INTERACTION_PROMPT: StringName = &"interaction_cursor_prompt"
const MORPH_CIRCLE_SEGMENTS: int = 32
const MORPH_BRACKET_SEGMENTS: int = 10
const MORPH_BRACKET_HALF_ANGLE: float = 0.62
const MORPH_OPEN_PATH_THRESHOLD: float = 0.035

var is_over_target: bool = false
var _color: Color = Color.WHITE
var _stamina_ratio: float = 1.0
var _sprint_progress: float = 0.0
var _was_sprinting: bool = false
var _dot_alpha: float = 0.0
var _arcs_alpha: float = 0.0
var _arc_angle: float = 0.0
var _jump_charging: bool = false
var _jump_time: float = 0.0
var _jump_alpha: float = 0.0
var _jump_progress: float = 0.0
var _jump_tween: Tween
var _arcs_tween: Tween
var _cursor_enso_texture: Texture2D
var _interact_component: InteractComponent
var _interaction_target: InteractiveArea
var _interaction_morph_progress: float = 0.0
var _interaction_morph_from: float = 0.0
var _interaction_morph_target: float = 0.0
var _interaction_morph_elapsed: float = 0.0
var _interaction_gradient: TextureRect
var _prompt_face: ActionPromptFace
var _confirm_tween: Tween


func _ready() -> void:
	add_to_group(GROUP_INTERACTION_PROMPT)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The Enso is rendered far below its source resolution. Linear filtering is
	# required here; project-default nearest filtering turns the brush edge into
	# visible square pixels.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_color = cursor_color_idle
	_cursor_enso_texture = load(CURSOR_ENSO_PATH) as Texture2D
	if _cursor_enso_texture == null:
		push_warning("[MouseCursorUI] Enso cursor texture failed to load")
	if player == null:
		player = get_parent() as CharacterBody3D
	if player != null and movement_controller == null:
		movement_controller = player.get_node_or_null(^"MovementController") as MovementController
	if player != null:
		_interact_component = player.get_node_or_null(^"InteractComponent") as InteractComponent
	_build_interaction_prompt()
	if _interact_component != null and not _interact_component.interaction_performed.is_connected(_on_interaction_performed):
		_interact_component.interaction_performed.connect(_on_interaction_performed)
	if movement_controller != null and stamina_manager == null:
		stamina_manager = movement_controller.get_node_or_null(^"StaminaManager") as StaminaManager
	if stamina_manager != null:
		stamina_manager.stamina_changed.connect(_on_stamina_changed)
		stamina_manager.jump_performed.connect(_on_jump_performed)


func _process(delta: float) -> void:
	visible = not _is_paused()
	if not visible:
		return
	var focused := _focused_prompt_target()
	is_over_target = focused != null
	var wanted: Color = cursor_color_target if is_over_target else cursor_color_idle
	_color = _color.lerp(wanted, clampf(cursor_color_speed * delta, 0.0, 1.0))
	_update_interaction_target(focused)
	if focused != null:
		_sync_prompt(focused)
	_update_interaction_morph(delta)
	_update_prompt_visuals()
	_update_movement(delta)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = get_viewport_rect().size * 0.5
	_draw_interaction_cursor(center, _color)
	var inner: Color = _color
	inner.a *= 0.3 * (1.0 - _interaction_morph_progress)
	if inner.a > 0.005:
		draw_circle(center, cursor_radius * 0.3, inner)
	if _dot_alpha > 0.01:
		var dot: Color = movement_dot_color.lerp(movement_dot_bright_color, _dot_alpha)
		dot.a *= _dot_alpha
		draw_circle(center + Vector2(0.0, cursor_radius + 8.5), 1.5, dot)
	if _arcs_alpha > 0.01:
		_draw_sprint_arcs(center)
	if _jump_alpha > 0.01:
		_draw_jump_arc(center)


func _update_movement(delta: float) -> void:
	if player == null or movement_controller == null:
		return
	var planar_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var moving: bool = planar_speed > stationary_speed
	var sprinting: bool = movement_controller.is_currently_sprinting(player.velocity)
	_sprint_progress = clampf(movement_controller.get_sprint_blend(), 0.0, 1.0)
	if stamina_manager != null:
		_stamina_ratio = stamina_manager.get_stamina_ratio()
	_dot_alpha = lerpf(_dot_alpha, 1.0 if moving else 0.0, clampf(8.0 * delta, 0.0, 1.0))
	if sprinting != _was_sprinting:
		_fade_arcs(sprinting)
	_was_sprinting = sprinting
	if not (_arcs_tween and _arcs_tween.is_running()):
		var target: float = _sprint_progress * _stamina_ratio
		_arcs_alpha = lerpf(_arcs_alpha, target, clampf(6.0 * delta, 0.0, 1.0))
	if sprinting:
		_arc_angle = wrapf(_arc_angle + sprint_animation_speed * delta * (0.5 + _sprint_progress * 0.5), 0.0, TAU)
	else:
		_arc_angle = lerp_angle(_arc_angle, 0.0, clampf(4.0 * delta, 0.0, 1.0))
	## Player reports a held jump on the floor; the arc charges under the ring.
	var charging: bool = bool(player.get(&"cam_jump_hold_active"))
	if charging and not _jump_charging:
		_jump_alpha = 0.6
	elif not charging and _jump_charging and player.is_on_floor():
		_jump_alpha = 0.0
	_jump_charging = charging
	_jump_time = _jump_time + delta if charging else 0.0


func _fade_arcs(starting: bool) -> void:
	if _arcs_tween:
		_arcs_tween.kill()
	_arcs_tween = create_tween()
	if starting:
		_arcs_tween.tween_property(self, ^"_arcs_alpha", 1.0, 0.2)
	else:
		_arcs_tween.tween_property(self, ^"_arcs_alpha", 0.0, 0.4)


## Stamina colour: pale blue when full, through yellow and orange to red.
func _stamina_color(base: Color) -> Color:
	var r: float = _stamina_ratio
	if r > 0.5:
		return base.lerp(Color(1.0, 1.0, 0.0), (1.0 - r) * 2.0)
	if r > 0.25:
		return Color(1.0, 1.0, 0.0).lerp(Color(1.0, 0.5, 0.0), (0.5 - r) * 4.0)
	return Color(1.0, 0.5, 0.0).lerp(Color(1.0, 0.0, 0.0), (0.25 - r) * 4.0)


## Four quarter arcs that shrink with stamina and spin while sprinting.
func _draw_sprint_arcs(center: Vector2) -> void:
	var color: Color = _stamina_color(sprint_arc_color)
	color.a *= _stamina_ratio * _arcs_alpha
	var length: float = PI * 0.5 * _sprint_progress * _stamina_ratio
	for i: int in range(4):
		var start: float = float(i) * PI * 0.5 + _arc_angle
		draw_arc(center, cursor_radius + 4.0, start, start + length, 12, color, sprint_arc_thickness, true)


## Charging: a pulsing arc under the ring. Released: it closes to a circle.
func _draw_jump_arc(center: Vector2) -> void:
	var color: Color = _stamina_color(JUMP_ARC_COLOR)
	color.a = _jump_alpha
	var radius: float = cursor_radius + 12.0
	if _jump_charging:
		var length: float = PI * 0.2 + sin(_jump_time * 20.0) * 0.1 + PI * 0.3 * _jump_progress
		draw_arc(center, radius, PI * 0.5 - length * 0.5, PI * 0.5 + length * 0.5, 16, color, 2.0, true)
		return
	var half: float = PI * clampf(_jump_progress, 0.0, 1.0)
	if half >= PI:
		_draw_ring(center, radius, color, 2.0)
	elif half > 0.0:
		draw_arc(center, radius, PI * 1.5 - half, PI * 1.5 + half, 24, color, 2.0, true)


func _focused_prompt_target() -> InteractiveArea:
	var placement := get_tree().get_first_node_in_group(&"active_board_placement") as BreachBoardUp
	if is_instance_valid(placement) and placement.is_placing_board():
		return placement
	if _interact_component == null or not is_instance_valid(_interact_component.current_target):
		return null
	var target := _interact_component.current_target
	if not target.can_interact() or not target.prompt_shown:
		return null
	return target


func _update_interaction_target(target: InteractiveArea) -> void:
	if target == _interaction_target:
		return
	_interaction_target = target
	_interaction_morph_from = _interaction_morph_progress
	_interaction_morph_target = 1.0 if target != null else 0.0
	_interaction_morph_elapsed = 0.0
	if target != null:
		_sync_prompt(target)


func _update_interaction_morph(delta: float) -> void:
	if is_equal_approx(_interaction_morph_progress, _interaction_morph_target):
		return
	_interaction_morph_elapsed += maxf(delta, 0.0)
	var raw := clampf(
		_interaction_morph_elapsed / maxf(interaction_morph_duration, 0.001),
		0.0, 1.0
	)
	var eased := _morph_ease_in_out(raw, interaction_morph_ease_power)
	_interaction_morph_progress = lerpf(_interaction_morph_from, _interaction_morph_target, eased)
	if raw >= 1.0:
		_interaction_morph_progress = _interaction_morph_target


func _build_interaction_prompt() -> void:
	_interaction_gradient = _build_interaction_gradient()

	_prompt_face = ActionPromptFace.new()
	_prompt_face.name = "InteractionPrompt"
	_prompt_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_face.size = prompt_content_size
	_prompt_face.modulate.a = 1.0
	_prompt_face.visible = false
	add_child(_prompt_face)


func _build_interaction_gradient() -> TextureRect:
	var gradient := Gradient.new()
	var transparent := interaction_gradient_color
	transparent.a = 0.0
	var center_color := interaction_gradient_color
	center_color.a = interaction_gradient_center_alpha

	# Keep only four control points: transparent edge -> dense core ->
	# dense core -> transparent edge. Gradient interpolates continuously between
	# them, so there are no discrete alpha bands to read as a staircase.
	var final_width := maxf(interaction_gradient_width, interaction_gradient_core_width + 2.0)
	var half_core := clampf(
		(interaction_gradient_core_width * 0.5) / final_width,
		0.001,
		0.49
	)
	gradient.offsets = PackedFloat32Array([
		0.0,
		0.5 - half_core,
		0.5 + half_core,
		1.0,
	])
	gradient.colors = PackedColorArray([
		transparent,
		center_color,
		center_color,
		transparent,
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	# Oversample the 420 px UI strip so the alpha ramp remains visually smooth
	# while the TextureRect is stretching during the morph.
	texture.width = 1024
	texture.height = 64
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var strip := TextureRect.new()
	strip.name = "InteractionGradient"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.texture = texture
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.show_behind_parent = true
	strip.visible = false
	add_child(strip)
	return strip


func _sync_prompt(target: InteractiveArea) -> void:
	if _prompt_face == null or not is_instance_valid(target):
		return
	var data := target.get_interaction_prompt_data()
	_prompt_face.set_prompt(
		"",
		String(data.get("key", "F")),
		String(data.get("action", tr("INTERACT_USE"))),
		String(data.get("detail", ""))
	)


func _update_prompt_visuals() -> void:
	if _prompt_face == null:
		return
	var center := get_viewport_rect().size * 0.5
	_prompt_face.position = center - prompt_content_size * 0.5
	_prompt_face.size = prompt_content_size

	var t := clampf(_interaction_morph_progress, 0.0, 1.0)

	# UI juice is deliberately staged instead of fading the whole prompt at once:
	# 1) the yellow field stretches out from screen centre while the Enso splits,
	# 2) the physical key fades in,
	# 3) action copy follows,
	# 4) target detail lands last.
	var key_reveal := _smoothstep01((t - 0.52) / 0.18)
	var text_reveal := _smoothstep01((t - 0.66) / 0.18)
	var detail_reveal := _smoothstep01((t - 0.76) / 0.16)
	_prompt_face.visible = maxf(key_reveal, maxf(text_reveal, detail_reveal)) > 0.001
	_prompt_face.set_reveal_amounts(key_reveal, text_reveal, detail_reveal)
	_update_interaction_edge_fades(center, t)


func _update_interaction_edge_fades(center: Vector2, t: float) -> void:
	if _interaction_gradient == null:
		return

	# Stretch from the exact centre instead of popping in at final width.
	# Its expansion overlaps the bracket morph so both motions read as one event.
	var stretch := _smoothstep01((t - 0.34) / 0.44)
	var reveal := _smoothstep01((t - 0.30) / 0.24)
	var width := maxf(8.0, interaction_gradient_width * stretch)
	var height_scale := lerpf(0.72, 1.0, stretch)
	var size := Vector2(width, interaction_gradient_height * height_scale)
	_interaction_gradient.position = center - size * 0.5
	_interaction_gradient.size = size
	_interaction_gradient.modulate.a = reveal
	_interaction_gradient.visible = stretch > 0.001 and reveal > 0.001


func _on_interaction_performed(target: InteractiveArea) -> void:
	if _prompt_face == null or target != _interaction_target:
		return
	# A consumed pickup is already queued for deletion here. There is no target
	# to morph back from, so clear F/copy/gradient/spread brackets immediately.
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.can_interact():
		_dismiss_interaction_prompt_immediately()
		return
	if _confirm_tween != null:
		_confirm_tween.kill()
	_prompt_face.set_confirm_amount(1.0)
	_confirm_tween = create_tween()
	_confirm_tween.tween_method(_prompt_face.set_confirm_amount, 1.0, 0.0, 0.22)


func _dismiss_interaction_prompt_immediately() -> void:
	_interaction_target = null
	_interaction_morph_progress = 0.0
	_interaction_morph_from = 0.0
	_interaction_morph_target = 0.0
	_interaction_morph_elapsed = 0.0
	if _confirm_tween != null:
		_confirm_tween.kill()
		_confirm_tween = null
	if _prompt_face != null:
		_prompt_face.set_confirm_amount(0.0)
		_prompt_face.set_reveal_amounts(0.0, 0.0, 0.0)
		_prompt_face.visible = false
	if _interaction_gradient != null:
		_interaction_gradient.modulate.a = 0.0
		_interaction_gradient.visible = false
	queue_redraw()


func _draw_interaction_cursor(center: Vector2, color: Color) -> void:
	var t := clampf(_interaction_morph_progress, 0.0, 1.0)
	var enso_color := color
	enso_color.a *= 1.0 - _smoothstep01(t / 0.28)
	if enso_color.a > 0.005:
		_draw_cursor_enso(center, enso_color)
	if t <= 0.001:
		return
	_draw_interaction_morph_shape(center, t, color)


## Ported from ADT's DynamicCursor morph, adapted so the bracket geometry is
## born near the Enso and then the two halves travel apart around HFN's ink.
func _draw_interaction_morph_shape(center: Vector2, t: float, color: Color) -> void:
	var shape_t := clampf(t / 0.62, 0.0, 1.0)
	var eased := _morph_ease_in_out(shape_t, interaction_morph_ease_power)
	var base_radius := lerpf(cursor_radius, interaction_bracket_radius, eased)
	var stretch_in := _morph_ease_in_out(minf(shape_t / 0.55, 1.0), 1.8)
	var stretch_out_raw := maxf((shape_t - 0.55) / 0.45, 0.0)
	var stretch_out := _morph_ease_in_out(minf(stretch_out_raw, 1.0), 1.8)
	var stretch_weight := stretch_in * (1.0 - stretch_out)
	var stretch_factor := lerpf(1.0, 1.50, stretch_weight)
	var radius_x := base_radius * stretch_factor
	var radius_y := base_radius / sqrt(maxf(stretch_factor, 0.001))
	var open := (PI * 0.5 - MORPH_BRACKET_HALF_ANGLE) * _morph_gap_curve(shape_t)
	var punch_scale := _morph_scale_curve(shape_t)
	var paths := _build_morph_paths(center, radius_x, radius_y, open, punch_scale)

	var spread_t := _smoothstep01((t - 0.50) / 0.50)
	var spread := maxf(interaction_bracket_offset - interaction_bracket_radius, 0.0) * spread_t
	if paths.size() == 2:
		for i: int in range(paths[0].size()):
			paths[0][i].x += spread
		for i: int in range(paths[1].size()):
			paths[1][i].x -= spread

	var alpha := _smoothstep01(t / 0.18)
	var shape_color := color
	shape_color.a *= alpha
	var juice := sin(shape_t * PI)
	if juice > 0.001 and interaction_morph_glow > 0.0:
		_draw_morph_paths(
			paths,
			_color_with_alpha(shape_color, 0.10 * interaction_morph_glow * juice),
			interaction_bracket_thickness * 3.0
		)
	_draw_morph_paths(paths, shape_color, interaction_bracket_thickness)


func _build_morph_paths(
		center: Vector2, radius_x: float, radius_y: float, open: float, shape_scale: float
	) -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	if open < MORPH_OPEN_PATH_THRESHOLD:
		paths.append(_build_ellipse_arc(
			center, radius_x, radius_y, 0.0, TAU, shape_scale, MORPH_CIRCLE_SEGMENTS
		))
		return paths
	paths.append(_build_ellipse_arc(
		center, radius_x, radius_y,
		-PI * 0.5 + open, PI * 0.5 - open,
		shape_scale, MORPH_BRACKET_SEGMENTS
	))
	paths.append(_build_ellipse_arc(
		center, radius_x, radius_y,
		PI * 0.5 + open, PI * 1.5 - open,
		shape_scale, MORPH_BRACKET_SEGMENTS
	))
	return paths


func _build_ellipse_arc(
		center: Vector2,
		radius_x: float,
		radius_y: float,
		start_angle: float,
		end_angle: float,
		shape_scale: float,
		segments: int
	) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(segments + 1):
		var weight := float(i) / float(segments)
		var angle := lerpf(start_angle, end_angle, weight)
		var offset := Vector2(cos(angle) * radius_x, sin(angle) * radius_y) * shape_scale
		points.append(center + offset)
	return points


func _draw_morph_paths(paths: Array[PackedVector2Array], color: Color, width: float) -> void:
	for points: PackedVector2Array in paths:
		if points.size() > 1:
			draw_polyline(points, color, width, true)


func _morph_gap_curve(t: float) -> float:
	var span := maxf(1.0 - interaction_split_delay, 0.001)
	var delayed := clampf((t - interaction_split_delay) / span, 0.0, 1.0)
	return _morph_ease_in_out(delayed, 2.1)


func _morph_scale_curve(t: float) -> float:
	var pulse := sin(t * PI)
	var settle := 1.0 if t < 0.7 else 0.4
	var peak := interaction_morph_punch + interaction_morph_overshoot * sin(t * PI * 1.4) * settle
	return 1.0 + (peak - 1.0) * pulse


static func _morph_ease_in_out(t: float, power: float) -> float:
	var clamped := clampf(t, 0.0, 1.0)
	if clamped < 0.5:
		return pow(2.0 * clamped, power) * 0.5
	return 1.0 - pow(2.0 * (1.0 - clamped), power) * 0.5


static func _smoothstep01(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _color_with_alpha(color: Color, alpha_scale: float) -> Color:
	var result := color
	result.a *= clampf(alpha_scale, 0.0, 1.0)
	return result


func get_interaction_morph_progress() -> float:
	return _interaction_morph_progress


func has_center_interaction_prompt() -> bool:
	return _prompt_face != null


func _draw_cursor_enso(center: Vector2, color: Color) -> void:
	# The texture is authored with the brush opening at six o'clock. Tinting
	# preserves the old idle/target highlight behaviour without touching stamina.
	var diameter := cursor_radius * 2.0 * cursor_enso_scale
	var size := Vector2.ONE * diameter
	var rect := Rect2(center - size * 0.5, size)
	if _cursor_enso_texture != null:
		draw_texture_rect(_cursor_enso_texture, rect, false, color, false)
	else:
		_draw_ring(center, cursor_radius, color, cursor_thickness)


func _draw_ring(center: Vector2, radius: float, color: Color, thickness: float) -> void:
	var points := PackedVector2Array()
	for i: int in range(RING_SEGMENTS + 1):
		var angle: float = TAU * float(i) / float(RING_SEGMENTS)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(points, color, thickness, true)


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_ratio = current / maxf(maximum, 0.001)


func _on_jump_performed() -> void:
	if _jump_tween:
		_jump_tween.kill()
	_jump_tween = create_tween().set_parallel(true)
	_jump_tween.tween_property(self, ^"_jump_progress", 1.0, 0.15)
	_jump_tween.tween_property(self, ^"_jump_progress", 0.0, 0.25).set_delay(0.15)
	_jump_tween.tween_property(self, ^"_jump_alpha", 0.0, 0.4).from(0.8)


func _is_paused() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_paused"))
