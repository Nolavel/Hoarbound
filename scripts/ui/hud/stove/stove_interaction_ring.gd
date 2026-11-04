class_name StoveInteractionRing
extends Control

## Three separate arcs of one ring at the bottom centre of the screen: fuel on top (a tick per log
## of the firebox's real capacity), tinder lower left, fire lower right. Display only: every frame it reads the
## feed and its HeatSource; refusals arrive as feed_refused and flash the arc they concern.

enum ArcState { INACTIVE, AVAILABLE, ACTIVE, DONE, SPENT }
enum Arc { FUEL, TINDER, FIRE }

## The pickup marker's palette (PickupMarkerUI): cream line, red refusal; fire burns orange.
const LINE := Color(1.0, 0.95, 0.82, 1.0)
const REFUSAL := Color(0.86, 0.22, 0.18, 1.0)
const FIRE := Color(1.0, 0.56, 0.18, 1.0)
const SHADOW := Color(0.06, 0.04, 0.03, 0.55)
## Arc centres in screen angles (0 = right, clockwise) as on the pickup marker: top, lower right, lower left.
const CENTRE_DEG: Dictionary = {Arc.FUEL: -90.0, Arc.FIRE: 30.0, Arc.TINDER: 150.0}
const ARC_SPAN_DEG: float = 96.0
const TICK_GAP_DEG: float = 5.0
const REFUSAL_SECONDS: float = 0.8
const FADE_RATE: float = 6.0
const FILL_RATE: float = 8.0
const FONT_PX: int = 12
const HINT_PX: int = 11

@export var ring_radius_px: float = 50.0
@export var arc_width_px: float = 5.0
## Ring centre below the screen centre, px (owner: centre and 100 px down).
@export var center_drop_px: float = 100.0

var _feed: HeatSourceFeed
var _cooktop: CooktopInteractionController
var _shown: bool = false
var _alpha: float = 0.0
var _refusal_left: Dictionary = {}
var _refusal_text: String = ""
var _shown_fill: Dictionary = {Arc.FUEL: 0.0, Arc.TINDER: 0.0, Arc.FIRE: 0.0}
var _font: Font
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	visible = false


func bind(feed: HeatSourceFeed) -> void:
	_feed = feed
	if _feed != null and not _feed.feed_refused.is_connected(_on_refused):
		_feed.feed_refused.connect(_on_refused)
		_feed.state_changed.connect(queue_redraw)


func bind_cooktop(controller: CooktopInteractionController) -> void:
	_cooktop = controller
	_feed = null
	queue_redraw()


func set_shown(shown: bool) -> void:
	_shown = shown
	if shown:
		visible = true


func is_shown() -> bool:
	return _shown and visible


## What one arc shows now: its state, fill 0..1 and tick count (fuel only); read from the game.
func describe(arc: Arc) -> Dictionary:
	if is_instance_valid(_cooktop):
		return _cooktop_arc(arc)
	var source: HeatSource = _feed.heat_source if _feed != null else null
	if source == null:
		return {"state": ArcState.INACTIVE, "fill": 0.0, "ticks": 0}
	match arc:
		Arc.FUEL:
			var capacity: int = source.get_log_capacity()
			var loaded: int = source.get_loaded_log_count()
			var state: ArcState = ArcState.INACTIVE
			var partial: float = 0.0
			if _feed.get_act() == HeatSourceFeed.Act.FUEL:
				state = ArcState.ACTIVE
				partial = 0.0 if _feed.did_commit_transfer() else _feed.get_act_progress()
			elif loaded >= capacity and capacity > 0:
				state = ArcState.DONE
			elif _feed.get_fuel_refusal() == HeatSourceFeed.Refusal.NONE:
				state = ArcState.AVAILABLE
			var fill: float = (float(loaded) + partial) / float(maxi(capacity, 1))
			return {"state": state, "fill": clampf(fill, 0.0, 1.0), "ticks": capacity, "loaded": loaded}
		Arc.TINDER:
			if source.is_burning():
				return {"state": ArcState.SPENT, "fill": 1.0, "ticks": 0}
			if source.is_tinder_prepared():
				return {"state": ArcState.DONE, "fill": 1.0, "ticks": 0}
			if _feed.get_act() == HeatSourceFeed.Act.TINDER:
				return {"state": ArcState.ACTIVE, "fill": _feed.get_act_progress(), "ticks": 0}
			var tinder_ok: bool = _feed.get_tinder_refusal() == HeatSourceFeed.Refusal.NONE
			return {"state": ArcState.AVAILABLE if tinder_ok else ArcState.INACTIVE, "fill": 0.0, "ticks": 0}
		_:
			if source.is_burning():
				return {"state": ArcState.DONE, "fill": 1.0, "ticks": 0, "intensity": source.get_intensity()}
			if _feed.get_stage() == HeatSourceFeed.Stage.HOLDING:
				return {"state": ArcState.ACTIVE, "fill": _feed.get_light_progress(), "ticks": 0}
			var lighter_ok: bool = _feed.is_lighter_ready() or _feed.get_lighter_refusal() == HeatSourceFeed.Refusal.NONE
			return {"state": ArcState.AVAILABLE if lighter_ok else ArcState.INACTIVE, "fill": 0.0, "ticks": 0}


## Seconds of refusal flash left on an arc (tests read it).
func get_refusal_left(arc: Arc) -> float:
	return float(_refusal_left.get(arc, 0.0))


func _process(delta: float) -> void:
	_time += delta
	_alpha = move_toward(_alpha, 1.0 if _shown else 0.0, FADE_RATE * delta)
	if not _shown and _alpha <= 0.001:
		visible = false
		return
	for arc: Arc in _refusal_left.keys():
		_refusal_left[arc] = maxf(0.0, float(_refusal_left[arc]) - delta)
	for arc: Arc in [Arc.FUEL, Arc.TINDER, Arc.FIRE]:
		var goal: float = float(describe(arc)["fill"])
		## Fills only animate forward smoothly; a reset (a cancelled act) drops at once.
		_shown_fill[arc] = goal if goal < float(_shown_fill[arc]) else move_toward(float(_shown_fill[arc]), goal, FILL_RATE * delta)
	queue_redraw()


func _draw() -> void:
	if (_feed == null and not is_instance_valid(_cooktop)) or _alpha <= 0.001:
		return
	var centre: Vector2 = _anchor()
	if is_instance_valid(_cooktop):
		_draw_cooktop_menu(centre)
		return
	for arc: Arc in [Arc.FUEL, Arc.TINDER, Arc.FIRE]:
		_draw_arc(centre, arc, describe(arc))
	if is_instance_valid(_cooktop):
		var label: String = "PLATE A" if _cooktop.get_selected_index() == 0 else "PLATE B"
		_text(centre, label, FONT_PX, Color(LINE, _alpha), true)
		_text(centre + Vector2(0.0, ring_radius_px + 59.0), "LMB: ACT   RMB: SWITCH   F: EXIT", HINT_PX, Color(LINE, 0.83 * _alpha), true)
	if _refusal_text != "" and _any_refusal():
		_text(centre + Vector2(0.0, ring_radius_px + 46.0), _refusal_text, FONT_PX, Color(REFUSAL, _alpha), true)


func _draw_arc(centre: Vector2, arc: Arc, info: Dictionary) -> void:
	var span: Vector2 = _span(arc)
	var state: ArcState = info["state"]
	var flash: float = clampf(get_refusal_left(arc) / REFUSAL_SECONDS, 0.0, 1.0)
	var base: Color = FIRE if arc == Arc.FIRE else LINE
	var track_alpha: float = {ArcState.INACTIVE: 0.16, ArcState.AVAILABLE: 0.42, ArcState.ACTIVE: 0.3,
		ArcState.DONE: 0.3, ArcState.SPENT: 0.2}[state]
	var fill: float = float(_shown_fill[arc])
	if arc == Arc.FUEL and int(info["ticks"]) > 0:
		_draw_ticks(centre, span, int(info["ticks"]), fill, base, track_alpha, state)
	else:
		if state == ArcState.INACTIVE:
			_dashed(centre, span, Color(base, track_alpha * _alpha))
		else:
			_line(centre, span, Color(base, track_alpha * _alpha), arc_width_px)
		if fill > 0.001:
			var fill_alpha: float = 0.45 if state == ArcState.SPENT else 1.0
			var colour := Color(base, fill_alpha * _alpha)
			if arc == Arc.FIRE and state == ArcState.DONE:
				colour = Color(FIRE.lerp(Color(1.0, 0.85, 0.5), 0.3 + 0.15 * sin(_time * 7.0)), _alpha)
			_line(centre, Vector2(span.x, lerpf(span.x, span.y, fill)), colour, arc_width_px)
	if flash > 0.0:
		_line(centre, span, Color(REFUSAL, flash * _alpha), arc_width_px + 2.0)
	_draw_label(centre, arc, state, flash)


## The fuel arc as one tick per log the firebox holds; laid logs solid, the one going in filling.
func _draw_ticks(centre: Vector2, span: Vector2, ticks: int, fill: float, base: Color, track_alpha: float, state: ArcState) -> void:
	var step: float = (span.y - span.x) / float(ticks)
	for i: int in range(ticks):
		var tick := Vector2(span.x + step * i + TICK_GAP_DEG * 0.5, span.x + step * (i + 1) - TICK_GAP_DEG * 0.5)
		if state == ArcState.INACTIVE:
			_dashed(centre, tick, Color(base, track_alpha * _alpha))
		else:
			_line(centre, tick, Color(base, track_alpha * _alpha), arc_width_px)
		var share: float = clampf(fill * ticks - i, 0.0, 1.0)
		if share > 0.001:
			_line(centre, Vector2(tick.x, lerpf(tick.x, tick.y, share)), Color(base, _alpha), arc_width_px)


func _draw_label(centre: Vector2, arc: Arc, state: ArcState, flash: float) -> void:
	var mid: float = deg_to_rad(float(CENTRE_DEG[arc]))
	var out: Vector2 = Vector2(cos(mid), sin(mid))
	var at: Vector2 = centre + out * (ring_radius_px + 18.0)
	var names: Dictionary = {Arc.FUEL: "STOVE_RING_FUEL", Arc.TINDER: "STOVE_RING_TINDER", Arc.FIRE: "STOVE_RING_FIRE"}
	var alpha: float = (0.45 if state == ArcState.INACTIVE else 0.95) * _alpha
	var colour: Color = Color(REFUSAL, _alpha).lerp(Color(LINE, alpha), 1.0 - flash) if flash > 0.0 else Color(LINE, alpha)
	var label: String = tr(names[arc]) if not is_instance_valid(_cooktop) else {Arc.FUEL: "PAN", Arc.TINDER: "EGG", Arc.FIRE: "TAKE"}[arc]
	var mark: String = ""
	if flash > 0.0:
		mark = " ✕"
	elif state == ArcState.DONE:
		mark = " ✓"
	if arc == Arc.FUEL and _feed != null:
		var source: HeatSource = _feed.heat_source
		label += "  %d/%d" % [source.get_loaded_log_count(), source.get_log_capacity()]
	_text(at, label + mark, FONT_PX, colour, true)
	var hint: String = ""
	if _feed != null and (state == ArcState.AVAILABLE or (state == ArcState.ACTIVE and arc == Arc.FIRE)):
		hint = {Arc.FUEL: "STOVE_RING_RMB", Arc.TINDER: "STOVE_RING_LMB", Arc.FIRE: "STOVE_RING_HOLD"}[arc]
	if hint != "":
		_text(at + Vector2(0.0, FONT_PX + 3.0), tr(hint), HINT_PX, Color(LINE, 0.7 * _alpha), true)


func _span(arc: Arc) -> Vector2:
	var mid: float = float(CENTRE_DEG[arc])
	return Vector2(mid - ARC_SPAN_DEG * 0.5, mid + ARC_SPAN_DEG * 0.5)


func _line(centre: Vector2, span: Vector2, colour: Color, width: float) -> void:
	if span.y - span.x <= 0.05 or colour.a <= 0.003:
		return
	draw_arc(centre + Vector2(0.0, 1.5), ring_radius_px, deg_to_rad(span.x), deg_to_rad(span.y), 32,
		Color(SHADOW, SHADOW.a * colour.a), width + 1.5, true)
	draw_arc(centre, ring_radius_px, deg_to_rad(span.x), deg_to_rad(span.y), 32, colour, width, true)


## Inactive arcs are dotted, so the state reads without colour.
func _dashed(centre: Vector2, span: Vector2, colour: Color) -> void:
	var at: float = span.x
	while at < span.y:
		_line(centre, Vector2(at, minf(at + 4.0, span.y)), colour, arc_width_px * 0.6)
		at += 9.0


func _text(at: Vector2, text: String, size: int, colour: Color, centred: bool) -> void:
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := Vector2(at.x - (width * 0.5 if centred else 0.0), at.y + size * 0.35)
	draw_string(_font, origin + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SHADOW, colour.a * 0.8))
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


## Screen centre, center_drop_px lower.
func _anchor() -> Vector2:
	var size: Vector2 = get_viewport_rect().size
	return Vector2(size.x * 0.5, size.y * 0.5 + center_drop_px)


func _any_refusal() -> bool:
	for arc: Arc in _refusal_left.keys():
		if float(_refusal_left[arc]) > 0.0:
			return true
	return false


func _on_refused(reason: HeatSourceFeed.Refusal) -> void:
	var arc: Arc = Arc.FUEL
	match reason:
		HeatSourceFeed.Refusal.NO_TINDER, HeatSourceFeed.Refusal.TINDER_READY:
			arc = Arc.TINDER
		HeatSourceFeed.Refusal.NO_LIGHTER, HeatSourceFeed.Refusal.NEED_TINDER, HeatSourceFeed.Refusal.ALREADY_BURNING:
			arc = Arc.FIRE
		HeatSourceFeed.Refusal.BUSY:
			arc = Arc.FIRE if _feed.get_stage() == HeatSourceFeed.Stage.HOLDING else Arc.FUEL
	_refusal_left[arc] = REFUSAL_SECONDS
	_refusal_text = tr(HeatSourceFeed.describe_refusal(reason))
	queue_redraw()


## Cooktop: sector count and text derive from the actual enabled physical actions.
func _draw_cooktop_menu(centre: Vector2) -> void:
	var actions: Array[Dictionary] = _cooktop.get_actions()
	var size: int = actions.size()
	if size <= 0:
		return
	var active: StringName = _cooktop.get_selected_action()
	var segment: float = 360.0 / float(size)
	for i: int in range(size):
		var action: Dictionary = actions[i]
		var id: StringName = StringName(action.get("id", &""))
		var available: bool = bool(action.get("enabled", false))
		var selected: bool = available and id == active
		var mid: float = -90.0 + float(i) * segment
		var span := Vector2(mid - segment * 0.43, mid + segment * 0.43)
		var color: Color = FIRE if selected else LINE
		_line(centre, span, Color(color, _alpha * (1.0 if selected else (0.48 if available else 0.15))), arc_width_px + (2.0 if selected else 0.0))
		var radius: float = ring_radius_px + 20.0
		var pos: Vector2 = centre + Vector2(cos(deg_to_rad(mid)), sin(deg_to_rad(mid))) * radius
		_text(pos, str(action.get("label", "")), HINT_PX, Color(color, _alpha * (1.0 if selected else (0.7 if available else 0.25))), true)
	var warmer: StoveWarmer = _cooktop.get_selected_warmer()
	var count: int = warmer.get_egg_count() if warmer != null else 0
	_text(centre + Vector2(0.0, -6.0), "PLATE A" if _cooktop.get_selected_index() == 0 else "PLATE B", FONT_PX, Color(LINE, _alpha), true)
	_text(centre + Vector2(0.0, 12.0), "%d / 3 EGGS" % count, HINT_PX, Color(LINE, _alpha), true)
	_text(centre + Vector2(0.0, ring_radius_px + 62.0), "WHEEL CHOOSE   LMB APPLY   RMB PLATE   F EXIT", HINT_PX, Color(LINE, 0.83 * _alpha), true)


## Shared stove ring, older describe(arc) compatibility for regression tests.
func _cooktop_arc(arc: Arc) -> Dictionary:
	var warmer: StoveWarmer = _cooktop.get_selected_warmer()
	var inventory: InventoryComponent = _cooktop.get_inventory()
	if warmer == null:
		return {"state": ArcState.INACTIVE, "fill": 0.0, "ticks": 0}
	var has_pan: bool = warmer.has_pan()
	var egg: int = int(warmer.get_egg_state())
	var burning: bool = warmer.source != null and warmer.source.is_burning()
	match arc:
		Arc.FUEL:
			return {"state": ArcState.DONE if has_pan else (ArcState.AVAILABLE if inventory != null and inventory.has_item(&"frying_pan") else ArcState.INACTIVE), "fill": 1.0 if has_pan else 0.0, "ticks": 0}
		Arc.TINDER:
			if egg == StoveWarmer.EggState.COOKING:
				return {"state": ArcState.ACTIVE, "fill": warmer.get_egg_progress_h() / StoveWarmer.EGG_COOK_HOURS, "ticks": 0}
			if egg == StoveWarmer.EggState.READY:
				return {"state": ArcState.DONE, "fill": 1.0, "ticks": 0}
			return {"state": ArcState.AVAILABLE if has_pan and burning and inventory != null and inventory.has_item(&"egg_raw") else ArcState.INACTIVE, "fill": 0.0, "ticks": 0}
		_:
			return {"state": ArcState.AVAILABLE if has_pan and egg == StoveWarmer.EggState.READY else ArcState.INACTIVE, "fill": 0.0, "ticks": 0}
