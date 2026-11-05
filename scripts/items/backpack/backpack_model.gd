class_name BackpackModel
extends Node3D

## A front-loading backpack (#260): a canvas shell, a front panel on a two-slider zip that folds out
## where the sliders have passed, slots for what it carries, a pocket and a carabiner either side and a
## bedroll under it. The canvas takes its shape from the contents (backpack_canvas.gdshader).
## Pack space: origin at the bottom of the back face, +Y up, +Z out to the front, +X to the right.

signal opened_changed(open: bool)

const CANVAS_SHADER: Shader = preload("res://shaders/items/backpack_canvas.gdshader")
const BEDROLL_PACKED: PackedScene = preload("res://assets/items/bedroll/bedroll_packed.scn")
const MAX_ITEMS: int = 16
## Outer size of the main body (width, height, depth) and the rounding of its edges, metres.
const BODY: Vector3 = Vector3(0.34, 0.52, 0.22)
const ROUND_M: float = 0.06
## Grid steps along each face; enough vertices for a can or a flask to show as a bulge.
const STEPS: Vector3i = Vector3i(14, 26, 10)
## The open front panel hangs this far past flat, degrees.
const OPEN_DEG: float = 104.0
## Panel swing and droop springs: frequency (Hz) and damping (under 1 overshoots a little).
const SWING_HZ: float = 1.6
const SWING_DAMPING: float = 0.62
const DROOP_HZ: float = 2.2
const DROOP_DAMPING: float = 0.35
## How far the free top of the panel sags when it lies flat.
const DROOP_FLAT_M: float = 0.07
## Litres the main body holds when full: fill is the share the contents take up.
const CAPACITY_L: float = 24.0
const FILL_HZ: float = 1.2
## Longest step a spring takes in one frame, seconds (stable for every spring here).
const MAX_SPRING_STEP_S: float = 0.05
## Contact points on a clipped item: one per cell this size, metres.
const CONTACT_CELL_M: float = 0.02
## Slots: name -> [centre, half size] in pack space. Shelf on top, three columns below.
const SLOTS: Dictionary = {
	&"shelf": [Vector3(0.0, 0.42, 0.11), Vector3(0.145, 0.055, 0.08)],
	&"low_left": [Vector3(-0.09, 0.13, 0.11), Vector3(0.055, 0.11, 0.08)],
	&"low_mid": [Vector3(0.0, 0.17, 0.11), Vector3(0.04, 0.15, 0.08)],
	&"low_right": [Vector3(0.095, 0.17, 0.11), Vector3(0.05, 0.15, 0.08)],
	&"side_left": [Vector3(-POCKET_X - POCKET_SLOT_OUT_M, 0.15, 0.11), Vector3(0.035, 0.11, 0.06)],
	&"side_right_front": [Vector3(POCKET_X + POCKET_SLOT_OUT_M, 0.15, 0.1425), Vector3(0.035, 0.11, 0.03)],
	&"side_right_back": [Vector3(POCKET_X + POCKET_SLOT_OUT_M, 0.15, 0.0775), Vector3(0.035, 0.11, 0.03)],
}
## Which faces of a rounded box to build: every one, all but the front, or the front alone.
const FACES_ALL: int = 0
const FACES_SHELL: int = 1
const FACES_FRONT: int = 2
const FACES_OPEN_TOP: int = 3
const FACES_OPEN_ENDS: int = 4
## Side-pocket sleeves, one item each: the left pocket whole, then the right pocket's front and back
## halves, split by a dark divider at SLEEVE_SPLIT_Z and open at the bottom (a tool's handle hangs
## through, its head on the rim). Which pocket mesh (0 left, 1 right) each sleeve belongs to.
const SLEEVE_SLOTS: Array[StringName] = [&"side_left", &"side_right_front", &"side_right_back"]
const SLEEVE_POCKET: Array[int] = [0, 1, 1]
const SLEEVE_SPLIT_Z: float = 0.11
const DIVIDER_COLOUR: Color = Color(0.05, 0.05, 0.06)
## The clipped mug's dull knock on the tool handles or the pack, and the strike rate (rad/s) that
## plays it at full loudness; softer strikes are quieter, down to KNOCK_QUIET_DB.
const KNOCK_EVENT: SoundEvent = preload("res://data/audio/backpack/mug_knock.tres")
const KNOCK_FULL_RATE: float = 4.0
const KNOCK_QUIET_DB: float = -14.0
const SOUND_SYSTEM_SCRIPT: GDScript = preload("res://core/audio/sound_system.gd")
## Side pockets: open-topped pouches either side, sized for a bottle that stands out of them.
const POCKET_X: float = 0.205
## What stands in a pocket sits this far outboard of its middle, clear of the body's wall.
const POCKET_SLOT_OUT_M: float = 0.01
const POCKET_HALF: Vector3 = Vector3(0.04, 0.07, 0.065)
## Pocket mesh centre height; its rim, and the floor what it holds stands on (inside the lining).
const POCKET_CENTRE_Y: float = POCKET_HALF.y + 0.03
const POCKET_RIM_Y: float = POCKET_CENTRE_Y + POCKET_HALF.y
const POCKET_FLOOR_Y: float = POCKET_CENTRE_Y - POCKET_HALF.y + 0.004
## Pushing something into a pocket: it starts with its bottom this far above the rim and goes in
## fast in the air, slower while its foot stretches the hem, then eases onto the floor, m and m/s.
const INSERT_START_M: float = 0.05
const INSERT_SPEED_FREE: float = 0.6
const INSERT_SPEED_HEM: float = 0.28
const INSERT_SPEED_IN: float = 0.5
const INSERT_HEM_ENTRY_M: float = 0.035
const INSERT_EASE_M: float = 0.025
## The hem (top band of the pocket): its height, how far the entering foot flares it open, how far
## friction drags it down per m/s of push and over what depth, and its spring (Hz, damping).
const HEM_BAND_M: float = 0.02
const HEM_FLARE_M: float = 0.009
const HEM_DRAG_PER_MPS: float = 0.03
const HEM_DRAG_FALL_M: float = 0.08
const HEM_HZ: float = 4.5
const HEM_DAMPING: float = 0.28
## Cloth under an item still going in stays the empty pouch, blending over this height.
const POCKET_FUNNEL_M: float = 0.035
const CANVAS: Color = Color(0.30, 0.32, 0.34)
const STRAP: Color = Color(0.22, 0.23, 0.25)
## Zip: each slider runs from the top centre to a top corner and down its side to the bottom rounding
## (ZIP_FULL_M = BODY.x / 2 + BODY.y - ROUND_M), at ZIP_SPEED m/s.
const ZIP_FULL_M: float = 0.63
const ZIP_SPEED: float = 0.9
const SLIDER_HALF_M: float = 0.013
## The panel's top lifts this far between sliders still on the top edge; the walls by the open
## seam give this far once the panel folds out.
const MOUTH_M: float = 0.022
const SIDE_GIVE_M: float = 0.014
## Canvas and lining between a carried item and the outer face, and the most the canvas bulges out
## over an item (backpack_canvas.gdshader lining_m, max_stretch_m), metres.
const CANVAS_LINING_M: float = 0.012
const CANVAS_STRETCH_M: float = 0.02
## The bulge feathers over this distance (backpack_canvas.gdshader soft_m), metres.
const CANVAS_SOFT_M: float = 0.03
## The empty slump in backpack_canvas.gdshader, for parts that ride on the canvas.
const SLUMP_TOP_M: float = 0.07
const SLUMP_WALL_M: float = 0.018
## Webbing loop sewn at the middle of each side pocket's outer cloth (height, depth), clear of the
## hem: it hangs out and down at LOOP_DROP_DEG for LOOP_LENGTH_M, the carabiner in its lower end.
const LOOP_SEW_Y: float = POCKET_CENTRE_Y
const LOOP_Z: float = BODY.z * 0.5
const LOOP_LENGTH_M: float = 0.032
const LOOP_DROP_DEG: float = 60.0
## Where along the loop the carabiner's ring rests: just inside its lower end.
const LOOP_HOLD_M: float = 0.028
## The pocket's cloth (backpack_canvas.gdshader): its lining over an item, the empty fold's depth.
const POCKET_LINING_M: float = 0.004  # POCKET_FLOOR_Y sits this far above the mesh bottom
const POCKET_FLAT_M: float = 0.003
## Empty pocket: its outer layer spreads this share of the pocket's depth off the inner one.
const POCKET_FOLD_SPREAD: float = 0.03
const ZIP_METAL: Color = Color(0.16, 0.16, 0.17)
## Loose contents: their floor inside the main body and the gap they keep from its walls.
const LOOSE_FLOOR_M: float = 0.02
const LOOSE_MARGIN_M: float = 0.03
## The grab handle's foot on the top, behind its middle where the top is flat (pack space, at rest).
const HANDLE_AT: Vector3 = Vector3(0.0, 0.514, 0.03)
## The lengthwise-folded mat rests across the canvas top, in front of the handle.
const BEDROLL_AT: Vector3 = Vector3(0.0, 0.52, 0.14)
## The maker's patch on the front panel, as the panel's UV rect (up its height, across its width).
const PATCH_RECT: Vector4 = Vector4(0.55, 0.33, 0.67, 0.67)
## How far inside the mug handle's outer edge a carabiner rod rests, metres.
const MUG_HANDLE_GRIP_M: float = 0.012
## The rod rests this far below the top of the mug, in the handle's upper bend.
const MUG_HANDLE_TOP_M: float = 0.022
## What is clipped on swings slower than the carabiner (longer, heavier) and wider, Hz/degrees.
## The frying pan's hanging eye in its own model (Codex's capture), and how far the eye's top sits below the rod.
const PAN_EYE: Vector3 = Vector3(0.250, 0.045, 0.0)
const PAN_EYE_SAG_M: float = 0.005
## Clipping back on: the item starts this far above its seat on the rod, drops onto it in CLIP_ON_S, and the
## knock sets it swinging (rad/s).
const CLIP_ON_LIFT_M: float = 0.07
const CLIP_ON_S: float = 0.28
const CLIP_ON_KNOCK: float = 1.6
const CLIPPED_SWING_HZ: float = 1.8
const CLIPPED_SWING_DAMPING: float = 0.65
const CLIPPED_MAX_SWING_DEG: float = 60.0

## The floor's height (world) that what hangs off the pack may not go through, or -INF for none (the pack is
## worn or held up: PackFrontHold sets it where the pack stands by a container).
var hang_floor_y: float = -INF
var _shell_material: ShaderMaterial
var _panel_material: ShaderMaterial
var _pocket_materials: Array[ShaderMaterial] = []
var _strap_material: ShaderMaterial
var _hinge: Node3D
var _hinge_at: Vector3 = Vector3.ZERO
var _panel: MeshInstance3D
var _sliders: Array[Node3D] = []
var _tabs: Array[Node3D] = []
var _carabiners: Array[Carabiner] = []
var _loops: Array[Node3D] = []
var _zip: float = 0.0
var _zip_target: float = 0.0
var _hung: Array[Node3D] = []
var _main_count: int = 0
## Per sleeve (SLEEVE_SLOTS): what it holds is lifted this far above its seat while being
## pushed in, at this speed; the hem's flare and drag and their rates (springs).
var _pocket_rise: Array[float] = [0.0, 0.0, 0.0]
var _interior_boxes: Array[AABB] = []
## The main body's item boxes the canvas bulges over (as sent to the shader).
var _main_proxies: Array[AABB] = []
var _side_give: float = 0.0
var _pocket_push: Array[float] = [0.0, 0.0, 0.0]
var _hem_open: Array[float] = [0.0, 0.0, 0.0]
var _hem_open_speed: Array[float] = [0.0, 0.0, 0.0]
var _hem_drag: Array[float] = [0.0, 0.0, 0.0]
var _hem_drag_speed: Array[float] = [0.0, 0.0, 0.0]
var _divider: MeshInstance3D
var _quick_anchors: Dictionary = {}
## The tool handles hanging below the sleeves this frame, for contact: Vector4(axis x, axis z, low y,
## radius) in pack space.
var _handle_capsules: Array[Vector4] = []
## What a clipped item rests against, set each frame: world to pack and back (basis), each side
## pocket's outer cloth |x|.
var _to_pack: Transform3D = Transform3D.IDENTITY
var _side_face: Array[float] = [0.0, 0.0]
var _from_pack_basis: Basis = Basis.IDENTITY
var _handle: Node3D
var _bedroll: Node3D
var _items: Array[Dictionary] = []
var _contents: Node3D
var _open: bool = false
var _swing: float = 0.0
var _swing_speed: float = 0.0
var _droop: float = 0.0
var _droop_speed: float = 0.0
var _fill: float = 0.0
var _fill_speed: float = 0.0
var _open_deg: float = 0.0
## Fill from the carried weight (0..1) when the pack is worn; below 0 the slotted items decide.
var load_fill: float = -1.0
## Knocks the clipped item has made (the stand counts them).
var knock_count: int = 0
## Render layers given to what is clipped on a carabiner (the worn pack draws in the portrait too).
var layers_for_contents: int = 1


func _ready() -> void:
	build()


## Builds the shell, panel, pocket, bedroll and straps. Safe to call once.
func build() -> void:
	if _hinge != null:
		return
	_shell_material = _canvas_material(Vector4.ZERO)
	_shell_material.set_shader_parameter(&"zipper_on", true)
	_panel_material = _canvas_material(Vector4(0.1, 0.15, 0.55, 0.85))
	_panel_material.set_shader_parameter(&"zipper_on", true)
	_panel_material.set_shader_parameter(&"is_panel", true)
	_panel_material.set_shader_parameter(&"patch_rect", PATCH_RECT)
	## Each side pocket is its own cloth: flat on the wall when empty, wrapped round what it holds.
	for side: float in [-1.0, 1.0]:
		var pocket: ShaderMaterial = _canvas_material(Vector4.ZERO)
		pocket.set_shader_parameter(&"is_pocket", true)
		pocket.set_shader_parameter(&"pocket_wall_x", side * BODY.x * 0.5)
		pocket.set_shader_parameter(&"lining_m", POCKET_LINING_M)
		pocket.set_shader_parameter(&"wall_lining_m", CANVAS_LINING_M)
		pocket.set_shader_parameter(&"pocket_flat_m", POCKET_FLAT_M)
		pocket.set_shader_parameter(&"pocket_fold_spread", POCKET_FOLD_SPREAD)
		pocket.set_shader_parameter(&"rim_y", POCKET_RIM_Y)
		pocket.set_shader_parameter(&"body_half", BODY * 0.5)
		pocket.set_shader_parameter(&"body_round", ROUND_M)
		pocket.set_shader_parameter(&"slump_wall_m", SLUMP_WALL_M)
		pocket.set_shader_parameter(&"hem_band_m", HEM_BAND_M)
		pocket.set_shader_parameter(&"hem_drag_fall_m", HEM_DRAG_FALL_M)
		pocket.set_shader_parameter(&"funnel_m", POCKET_FUNNEL_M)
		_pocket_materials.append(pocket)
	_strap_material = _canvas_material(Vector4.ZERO)
	_strap_material.set_shader_parameter(&"canvas_colour", STRAP)
	_strap_material.set_shader_parameter(&"lining_colour", STRAP)
	_strap_material.set_shader_parameter(&"roughness_value", 0.7)
	_strap_material.set_shader_parameter(&"leather_on", false)
	## Shell and panel are one rounded box split at the front: each owns half of the front edge,
	## so the closed panel meets the shell with no seam.
	var centre := Vector3(0.0, BODY.y * 0.5, BODY.z * 0.5)
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = _rounded_box(BODY * 0.5, centre, ROUND_M, STEPS, FACES_SHELL, true)
	shell.material_override = _shell_material
	add_child(shell)
	var panel_mesh: ArrayMesh = _rounded_box(BODY * 0.5, centre, ROUND_M, STEPS, FACES_FRONT, true)
	_hinge_at = _hinge_point(panel_mesh)
	## The panel folds in the shader round the line the sliders reached; the node stays put.
	_hinge = Node3D.new()
	_hinge.name = "PanelHinge"
	_hinge.position = _hinge_at
	add_child(_hinge)
	_panel = MeshInstance3D.new()
	_panel.name = "FrontPanel"
	_panel.mesh = panel_mesh
	_panel.position = -_hinge_at
	_panel.material_override = _panel_material
	_hinge.add_child(_panel)
	_panel_material.set_shader_parameter(&"bend_z", _hinge_at.z)
	_panel_material.set_shader_parameter(&"top_y", BODY.y)
	for side: float in [-1.0, 1.0]:
		var pocket := MeshInstance3D.new()
		pocket.name = "SidePocketLeft" if side < 0.0 else "SidePocketRight"
		pocket.mesh = _rounded_box(POCKET_HALF, Vector3(side * POCKET_X, POCKET_CENTRE_Y, BODY.z * 0.5), 0.03, Vector3i(8, 14, 12),
			FACES_OPEN_TOP if side < 0.0 else FACES_OPEN_ENDS)
		pocket.material_override = _pocket_materials[0 if side < 0.0 else 1]
		add_child(pocket)
	_pocket_materials[1].set_shader_parameter(&"sleeve_split_z", SLEEVE_SPLIT_Z)
	## Where Quick Access pins the cards of what sits outside the pack (pack-space points).
	var anchors: Dictionary = {&"pack_side_left": Vector3(-(POCKET_X + POCKET_HALF.x), POCKET_CENTRE_Y, BODY.z * 0.5),
		&"pack_side_right_front": Vector3(POCKET_X + POCKET_HALF.x, POCKET_RIM_Y, 0.1425),
		&"pack_side_right_back": Vector3(POCKET_X + POCKET_HALF.x, POCKET_RIM_Y, 0.0775)}
	for pocket_id: StringName in anchors:
		var marker := Marker3D.new()
		marker.name = "QuickAnchor_%s" % pocket_id
		marker.position = anchors[pocket_id]
		add_child(marker)
		_quick_anchors[pocket_id] = marker
	_divider = MeshInstance3D.new()
	_divider.name = "SleeveDivider"
	_divider.mesh = ImmediateMesh.new()
	var divider_material: StandardMaterial3D = _plain(DIVIDER_COLOUR)
	divider_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	divider_material.roughness = 0.95
	_divider.material_override = divider_material
	add_child(_divider)
	_add_bedroll()
	_add_straps()
	_add_sliders()
	_add_carabiners()
	_contents = Node3D.new()
	_contents.name = "Contents"
	add_child(_contents)
	_refresh_proxies()


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	set_open_degrees(OPEN_DEG if open else 0.0)


## Fully unzips and folds the panel to degrees (0 closes it); see set_opening().
func set_open_degrees(degrees: float) -> void:
	set_opening(ZIP_FULL_M if degrees > 0.0 else 0.0, degrees)


## Each slider runs zip_m from the top centre (0 closed, ZIP_FULL_M at the bottom), and the panel
## folds out by degrees round the line they reached. Closing folds it back before the sliders return.
func set_opening(zip_m: float, degrees: float) -> void:
	_zip_target = clampf(zip_m, 0.0, ZIP_FULL_M)
	_open_deg = clampf(degrees, 0.0, OPEN_DEG) if _zip_target > 0.0 else 0.0
	var open: bool = _zip_target > 0.0
	if open != _open:
		_open = open
		opened_changed.emit(open)


## How far each slider has run from the top centre, metres.
func get_zip() -> float:
	return _zip


## The panel's current fold, degrees.
func get_fold_degrees() -> float:
	return rad_to_deg(_swing)


## The carabiner on the left (0) or right (1) side, for things clipped on later.
## Where Quick Access pins the card of pack pocket `pocket_id` that sits outside the pack (the side
## pockets and sleeves, and the right carabiner the mug clips on); null for the rest.
## Follows the deformed cloth top; UI reads its position but lives in GameplayUI.
func get_load_anchor() -> Node3D:
	build()
	return _handle


func get_quick_anchor(pocket_id: StringName) -> Node3D:
	if pocket_id == &"pack_carabiner":
		return get_carabiner(1)
	return _quick_anchors.get(pocket_id) as Node3D


func get_carabiner(index: int) -> Carabiner:
	build()
	return _carabiners[index] if index >= 0 and index < _carabiners.size() else null


## Puts item_id in the named slot (see SLOTS); its proxy shapes the canvas. False if taken.
## insert: a side-pocket item is pushed in from above the rim instead of appearing seated.
func add_item(item_id: StringName, slot: StringName, along: float = 0.0, insert: bool = false) -> bool:
	if not SLOTS.has(slot) or _items.size() >= MAX_ITEMS:
		return false
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = _local_bounds(visual)
	if box.size == Vector3.ZERO:
		return false
	var rest: Array = SLOTS[slot]
	var centre: Vector3 = rest[0]
	var half: Vector3 = rest[1]
	## Stand it on the slot floor; on the shelf it lies along X; in a side pocket its flat side
	## lies against the pack's wall. A tool in a sleeve hangs by its head from the rim, blade or
	## face forward (tool X to pack +Z).
	var sleeve: int = SLEEVE_SLOTS.find(slot)
	var head_bottom: float = float(visual.get_meta(&"head_bottom", -1.0))
	var basis := Basis(Vector3.FORWARD, PI * 0.5) if slot == &"shelf" and box.size.y > box.size.x else Basis()
	if sleeve >= 0 and head_bottom >= 0.0:
		basis = Basis(Vector3.UP, -PI * 0.5)
	elif sleeve >= 0 and box.size.x > box.size.z:
		basis = Basis(Vector3.UP, PI * 0.5)
	var placed: AABB = Transform3D(basis, Vector3.ZERO) * box
	var floor_y: float = POCKET_FLOOR_Y if sleeve >= 0 else centre.y - half.y
	var at := Vector3(centre.x + along, floor_y - placed.position.y, centre.z)
	var ellipse := Vector2.ZERO
	var axis := Vector2(at.x, at.z)
	if sleeve >= 0:
		## Its section where the sleeve holds it, pack x and z halves, and its axis there.
		var bow: float = float(visual.get_meta(&"handle_bow", 0.0))
		if visual.has_meta(&"handle_half"):
			var handle: Vector2 = visual.get_meta(&"handle_half")
			ellipse = Vector2(handle.y, handle.x)
		elif visual.has_meta(&"round_radius"):
			ellipse = Vector2.ONE * float(visual.get_meta(&"round_radius"))
		else:
			ellipse = Vector2(placed.size.x, placed.size.z) * 0.5
		var side: float = signf(centre.x)
		if head_bottom >= 0.0:
			at.y = POCKET_RIM_Y + 0.002 - head_bottom
		at.x = side * (body_side_x(POCKET_RIM_Y, centre.z, false) + POCKET_LINING_M + ellipse.x)
		## Clear of the pack's wall as a full pack pushes it out, and of the other sleeve's item.
		var whole: AABB = Transform3D(basis, at) * box
		at.x += side * maxf(body_side_x(POCKET_RIM_Y, centre.z, false) + 0.001 - (whole.position.x if side > 0.0 else -whole.end.x), 0.0)
		for other: Dictionary in _items:
			if SLEEVE_SLOTS.has(other["slot"]) and other["slot"] != slot and SLEEVE_POCKET[SLEEVE_SLOTS.find(other["slot"])] == SLEEVE_POCKET[sleeve]:
				whole = Transform3D(basis, at) * box
				var them: AABB = other["box"]
				if whole.intersects(them):
					at.x += side * ((them.end.x - whole.position.x) if side > 0.0 else (whole.end.x - them.position.x)) + side * 0.001
		axis = Vector2(at.x, at.z + bow)
	visual.transform = Transform3D(basis, at)
	_contents.add_child(visual)
	_items.append({"id": item_id, "slot": slot, "node": visual, "box": Transform3D(basis, at) * box, "seat": at,
		"ellipse": ellipse, "axis": axis, "tool": head_bottom >= 0.0})
	if sleeve >= 0:
		var lowest: float = (Transform3D(basis, at) * box).position.y
		_pocket_rise[sleeve] = POCKET_RIM_Y + INSERT_START_M - lowest if insert else 0.0
		_hem_open[sleeve] = 0.0
		_hem_drag[sleeve] = 0.0
		_hem_open_speed[sleeve] = 0.0
		_hem_drag_speed[sleeve] = 0.0
		visual.position.y += _pocket_rise[sleeve]
	_refresh_proxies()
	return true


## Drops item_id loose into the main body: a random spot and pose on the floor or on what is
## already there, the same for the same items in the same order. False when it is full.
func add_loose(item_id: StringName) -> bool:
	if _items.size() >= MAX_ITEMS:
		return false
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = _local_bounds(visual)
	if box.size == Vector3.ZERO:
		SurvivalItemVisual.release(visual)
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(item_id)) + _items.size() * 7919
	## Standing, or lying on its side, at any heading.
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	if rng.randf() < 0.5:
		basis = basis * Basis(Vector3.FORWARD, PI * 0.5)
	var placed: AABB = Transform3D(basis, Vector3.ZERO) * box
	var room := Vector2(BODY.x * 0.5 - LOOSE_MARGIN_M, BODY.z - LOOSE_MARGIN_M)
	var best := Vector3.ZERO
	var best_y: float = INF
	for _try: int in range(12):
		var x: float = rng.randf_range(-room.x - placed.position.x, room.x - placed.end.x)
		var z: float = rng.randf_range(LOOSE_MARGIN_M - placed.position.z, room.y - placed.end.z)
		## It settles on the floor or on top of whatever it lands over.
		var floor_y: float = LOOSE_FLOOR_M
		var footprint := AABB(Vector3(x, 0.0, z) + placed.position * Vector3(1, 0, 1), Vector3(placed.size.x, 10.0, placed.size.z))
		for item: Dictionary in _items:
			var other: AABB = item["box"]
			if footprint.intersects(other):
				floor_y = maxf(floor_y, other.end.y)
		if floor_y < best_y:
			best_y = floor_y
			best = Vector3(x, floor_y - placed.position.y, z)
	visual.transform = Transform3D(basis, best)
	_contents.add_child(visual)
	_items.append({"id": item_id, "slot": &"", "node": visual, "box": Transform3D(basis, best) * box})
	_refresh_proxies()
	return true


## Clips item_id onto a carabiner (0 left, 1 right). It swings on the carabiner's rod, which swings
## in its loop: a double pendulum. A mug hangs by its handle (authored at +X) threaded on the rod.
## clip_on: just put back by Henry, it comes down onto the rod from above and swings off the knock (as an item
## put back in a side pocket is pushed in from above the rim).
func hang_item(item_id: StringName, carabiner_index: int, clip_on: bool = false) -> bool:
	var carabiner: Carabiner = get_carabiner(carabiner_index)
	if carabiner == null:
		return false
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = _local_bounds(visual)
	if String(item_id).contains("mug"):
		## The rod (the ring's bottom, along the carabiner body's X) runs through the handle's hole
		## (mug Z). Hung on a pin, it turns about the hole until its centre of mass is under the rod.
		var grip := Vector3(box.end.x - MUG_HANDLE_GRIP_M, box.end.y - MUG_HANDLE_TOP_M, box.get_center().z)
		var below: Vector3 = _shell_centroid(visual) - grip
		var tilt := Basis(Vector3.BACK, -PI * 0.5 - atan2(below.y, below.x))
		var out_sign: float = 1.0 if carabiner_index == 0 else -1.0
		var turn := Basis(Vector3(0.0, 0.0, -out_sign), Vector3.UP, Vector3(out_sign, 0.0, 0.0)) * tilt
		visual.transform = Transform3D(turn, -(turn * grip))
		visual.set_meta(&"grip", grip)
		visual.set_meta(&"centre_of_mass", grip + below)
	elif item_id == &"frying_pan":
		## The pan hangs by its oval eye (handle up); the rod runs through the eye along the carabiner's X.
		var eye_turn := Basis(Vector3.BACK, PI * 0.5)
		visual.transform = Transform3D(eye_turn, -(eye_turn * PAN_EYE) + Vector3.DOWN * PAN_EYE_SAG_M)
	else:
		visual.position = Vector3(-box.get_center().x, -box.end.y, -box.get_center().z)
	var swing := PendulumHang.new()
	swing.name = "Clipped"
	swing.swing_hz = CLIPPED_SWING_HZ
	swing.swing_damping = CLIPPED_SWING_DAMPING
	swing.max_swing_deg = CLIPPED_MAX_SWING_DEG
	## It rests against the pack's side instead of passing through it.
	swing.contact_points = _contact_points(visual)
	swing.contact_depth = _pack_contact
	if String(item_id).contains("mug") or item_id == &"frying_pan":
		swing.knocked.connect(_on_clipped_knock.bind(swing))
		swing.hinge_axis = Vector3.RIGHT  # the rod, along the carabiner body's X
		swing.max_swing_deg = 90.0  # on the rod it turns until it meets the pack or the tools
	carabiner.get_hang_point().add_child(swing)
	swing.add_child(visual)
	visual.set_meta(&"carabiner_index", carabiner_index)
	if clip_on:
		var seated: Vector3 = visual.position
		visual.position = seated + Vector3.UP * CLIP_ON_LIFT_M
		var tween := visual.create_tween()
		tween.tween_property(visual, ^"position", seated, CLIP_ON_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(swing.nudge.bind(Vector3(0.0, 0.0, CLIP_ON_KNOCK)))
	for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		if mesh is MeshInstance3D:
			(mesh as MeshInstance3D).layers = layers_for_contents
	_hung.append(visual)
	return true


## The item seated in a side-pocket slot (SLEEVE_SLOTS), or null.
func slot_visual(slot: StringName) -> Node3D:
	for item: Dictionary in _items:
		if item["slot"] == slot and is_instance_valid(item["node"]):
			return item["node"]
	return null


## The item clipped on carabiner `index` (0 left, 1 right), or null.
func hung_visual(index: int) -> Node3D:
	for visual: Node3D in _hung:
		if is_instance_valid(visual) and int(visual.get_meta(&"carabiner_index", -1)) == index:
			return visual
	return null


## Takes out what sits in a side-pocket slot (SLEEVE_SLOTS), leaving the others as they are.
func remove_slot_item(slot: StringName) -> void:
	for i: int in range(_items.size() - 1, -1, -1):
		if _items[i]["slot"] == slot:
			(_items[i]["node"] as Node).queue_free()
			_items.remove_at(i)
	_refresh_proxies()


## Unclips what hangs on carabiner `index` (0 left, 1 right), leaving the other as it is.
func unhang_item(index: int) -> void:
	for i: int in range(_hung.size() - 1, -1, -1):
		var visual: Node3D = _hung[i]
		if not is_instance_valid(visual):
			_hung.remove_at(i)
		elif int(visual.get_meta(&"carabiner_index", -1)) == index:
			visual.get_parent().queue_free()
			_hung.remove_at(i)


func clear_items() -> void:
	for item: Dictionary in _items:
		(item["node"] as Node).queue_free()
	_items.clear()
	for visual: Node3D in _hung:
		visual.get_parent().queue_free()
	_hung.clear()
	_refresh_proxies()


## Where the canvas moves a pack-space point p (outward normal n): bulged over the contents, slack sagging onto them.
func canvas_point(p: Vector3, n: Vector3) -> Vector3:
	return _on_canvas(p, n, 0.0)


## The canvas's fill now, 0..1 (what its empty slump is drawn from).
func get_fill() -> float:
	return _fill


## Share of the main body the contents fill, 0..1 (the target the canvas springs toward).
func get_fill_target() -> float:
	if load_fill >= 0.0:
		return clampf(load_fill, 0.0, 1.0)
	var litres: float = 0.0
	for item: Dictionary in _items:
		var size: Vector3 = (item["box"] as AABB).size
		litres += size.x * size.y * size.z * 1000.0 * 1.6  # packed items leave air round them
	for box: AABB in _interior_boxes:
		litres += box.get_volume() * 1000.0 * 1.6
	return clampf(litres / CAPACITY_L, 0.0, 1.0)


func _process(delta: float) -> void:
	## Springs are stepped explicitly: a hitch's long frame would blow them up, so cap the step.
	delta = minf(delta, MAX_SPRING_STEP_S)
	var half_w: float = BODY.x * 0.5
	var swing_target: float = deg_to_rad(_open_deg)
	if _zip_target >= _zip:
		_zip = move_toward(_zip, _zip_target, ZIP_SPEED * delta)
		## The panel folds out only as far as the sliders have freed its sides.
		var side_run: float = _zip_target - half_w
		swing_target *= clampf((_zip - half_w) / side_run, 0.0, 1.0) if side_run > 0.0 else 0.0
	elif _swing <= swing_target + deg_to_rad(4.0):
		_zip = move_toward(_zip, _zip_target, ZIP_SPEED * delta)
	var omega: float = TAU * SWING_HZ
	_swing_speed += (omega * omega * (swing_target - _swing) - 2.0 * SWING_DAMPING * omega * _swing_speed) * delta
	_swing += _swing_speed * delta
	var seam: Array = _seam_point(maxf(_zip, half_w + 0.001), 1.0)
	var bend_y: float = BODY.y + 1.0
	if _zip > half_w:
		bend_y = lerpf((seam[0] as Vector3).y, _hinge_at.y, smoothstep(ZIP_FULL_M - 0.1, ZIP_FULL_M, _zip))
	_panel_material.set_shader_parameter(&"bend_y", bend_y)
	_panel_material.set_shader_parameter(&"bend_angle", _swing)
	_panel_material.set_shader_parameter(&"mouth_m", MOUTH_M * clampf(_zip / half_w, 0.0, 1.0))
	var give: float = SIDE_GIVE_M * clampf(_swing / deg_to_rad(30.0), 0.0, 1.0)
	_shell_material.set_shader_parameter(&"side_give_m", give)
	_side_give = give
	for pocket: ShaderMaterial in _pocket_materials:
		pocket.set_shader_parameter(&"side_give_m", give)
	for material: ShaderMaterial in [_shell_material, _panel_material]:
		material.set_shader_parameter(&"zip_s", _zip)
	_place_sliders(give)
	_step_pockets(delta)
	_place_carabiners()
	_place_divider()
	## The handle sits where the canvas top is now, however far it has slumped.
	_handle.position = _on_canvas(HANDLE_AT, Vector3.UP, 0.0)
	_bedroll.position = _on_canvas(BEDROLL_AT, Vector3.UP, 0.0) - Vector3.UP * 0.008
	## The free edge sags most with the panel flat; the swing's speed flicks it the other way.
	var droop_target: float = DROOP_FLAT_M * sin(clampf(_swing, 0.0, PI))
	var droop_omega: float = TAU * DROOP_HZ
	_droop_speed += (droop_omega * droop_omega * (droop_target - _droop) - 2.0 * DROOP_DAMPING * droop_omega * _droop_speed) * delta
	_droop += _droop_speed * delta
	var fill_omega: float = TAU * FILL_HZ
	_fill_speed += (fill_omega * fill_omega * (get_fill_target() - _fill) - 2.0 * 0.8 * fill_omega * _fill_speed) * delta
	_fill += _fill_speed * delta
	var panel_xf: Transform3D = global_transform.affine_inverse() * _panel.global_transform if is_inside_tree() else _hinge.transform
	_panel_material.set_shader_parameter(&"to_pack", Projection(panel_xf))
	_panel_material.set_shader_parameter(&"droop_m", _droop)
	_panel_material.set_shader_parameter(&"droop_dir", (global_basis.inverse() * Vector3.DOWN).normalized() if is_inside_tree() else Vector3.DOWN)
	## Only the closed panel holds the contents in; an open one does not bulge.
	_panel_material.set_shader_parameter(&"item_count", _main_count if _swing < 0.2 else 0)
	for material: ShaderMaterial in [_shell_material, _panel_material, _strap_material] + _pocket_materials:
		material.set_shader_parameter(&"fill", _fill)


## Item boxes the canvas wraps: what is in the main body shapes the shell, panel and straps;
## what is in a side pocket shapes only the pockets, never the wall between them.
## The main compartment's strapped items (PackStraps), pack space: they shape the canvas like slotted ones.
func set_interior_boxes(boxes: Array[AABB]) -> void:
	_interior_boxes = boxes
	_refresh_proxies()


func _refresh_proxies() -> void:
	var main: Array[AABB] = _interior_boxes.duplicate()
	var pockets: Array = [[], []]
	for item: Dictionary in _items:
		var sleeve: int = SLEEVE_SLOTS.find(item["slot"])
		if sleeve >= 0:
			pockets[SLEEVE_POCKET[sleeve]].append(item["box"])
		else:
			main.append(item["box"])
	var groups: Array = [[[_shell_material, _panel_material, _strap_material], main]]
	if _pocket_materials.size() == 2:
		groups.append([[_pocket_materials[0]], pockets[0]])
		groups.append([[_pocket_materials[1]], pockets[1]])
	for entry: Array in groups:
		var centres: Array = []
		var halves: Array = []
		for box: AABB in entry[1]:
			if centres.size() >= MAX_ITEMS:
				break
			centres.append(Vector4(box.get_center().x, box.get_center().y, box.get_center().z, 0.0))
			halves.append(Vector4(box.size.x * 0.5, box.size.y * 0.5, box.size.z * 0.5, 0.0))
		var count: int = centres.size()
		if entry[1] == main:
			_main_count = count
			_main_proxies.assign(entry[1].slice(0, count))
		while centres.size() < MAX_ITEMS:
			centres.append(Vector4(0.0, -10.0, 0.0, 0.0))
			halves.append(Vector4.ZERO)
		for material: ShaderMaterial in entry[0]:
			if material == null:
				continue
			material.set_shader_parameter(&"item_centre", centres)
			material.set_shader_parameter(&"item_half", halves)
			material.set_shader_parameter(&"item_count", count)
		if entry[1] == main:
			## Pockets ride the side walls where the main contents bulge them.
			for pocket: ShaderMaterial in _pocket_materials:
				pocket.set_shader_parameter(&"wall_item_centre", centres)
				pocket.set_shader_parameter(&"wall_item_half", halves)
				pocket.set_shader_parameter(&"wall_item_count", count)
	_send_sleeves()


## Hands each pocket material its sleeves' items: section, axis, bottom now and seated, hem state.
func _send_sleeves() -> void:
	for pocket: int in range(_pocket_materials.size()):
		var halves := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
		var axes := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
		var bottoms := PackedFloat32Array([0.0, 0.0])
		var seats := PackedFloat32Array([0.0, 0.0])
		var opens := PackedFloat32Array([0.0, 0.0])
		var drags := PackedFloat32Array([0.0, 0.0])
		for sleeve: int in range(SLEEVE_SLOTS.size()):
			if SLEEVE_POCKET[sleeve] != pocket:
				continue
			var k: int = 0 if pocket == 0 or sleeve == 1 else 1
			var held: Dictionary = _sleeve_item(sleeve)
			if held.is_empty():
				continue
			halves[k] = held["ellipse"]
			axes[k] = held["axis"]
			seats[k] = (held["box"] as AABB).position.y
			bottoms[k] = seats[k] + _pocket_rise[sleeve]
			opens[k] = _hem_open[sleeve]
			drags[k] = _hem_drag[sleeve]
		var material: ShaderMaterial = _pocket_materials[pocket]
		material.set_shader_parameter(&"round_half", halves)
		material.set_shader_parameter(&"round_axis", axes)
		material.set_shader_parameter(&"item_bottom", bottoms)
		material.set_shader_parameter(&"seat_bottom", seats)
		material.set_shader_parameter(&"hem_open_m", opens)
		material.set_shader_parameter(&"hem_drag_m", drags)


func _canvas_material(pocket: Vector4) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CANVAS_SHADER
	material.set_shader_parameter(&"canvas_colour", CANVAS)
	material.set_shader_parameter(&"pack_height_m", BODY.y)
	material.set_shader_parameter(&"mesh_pocket", pocket)
	material.set_shader_parameter(&"lining_m", CANVAS_LINING_M)
	material.set_shader_parameter(&"max_stretch_m", CANVAS_STRETCH_M)
	return material


## A box with rounded edges as a grid on each face (faces_built picks which). Every grid
## point is pulled onto the rounded surface: clamp to the inner box, then out by the radius.
static func _rounded_box(half: Vector3, centre: Vector3, radius: float, steps: Vector3i, faces_built: int, zipped: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Vector3 = half - Vector3.ONE * radius
	## Each face: its normal axis, its sign, and the two axes it spans.
	var faces: Array = [[2, -1.0, 0, 1], [2, 1.0, 1, 0], [0, -1.0, 1, 2], [0, 1.0, 2, 1], [1, -1.0, 2, 0], [1, 1.0, 0, 2]]
	for face: Array in faces:
		var axis: int = face[0]
		var sign: float = face[1]
		var front: bool = axis == 2 and sign > 0.0
		var top: bool = axis == 1 and sign > 0.0
		if (faces_built == FACES_SHELL and front) or (faces_built == FACES_FRONT and not front) \
				or ((faces_built == FACES_OPEN_TOP or faces_built == FACES_OPEN_ENDS) and top) \
				or (faces_built == FACES_OPEN_ENDS and axis == 1 and sign < 0.0):
			continue
		var u_axis: int = face[2]
		var v_axis: int = face[3]
		var nu: int = steps[u_axis]
		var nv: int = steps[v_axis]
		var grid: Array = []
		for j: int in range(nv + 1):
			var row: Array = []
			for i: int in range(nu + 1):
				var cube := Vector3.ZERO
				cube[axis] = sign
				cube[u_axis] = lerpf(-1.0, 1.0, float(i) / nu)
				cube[v_axis] = lerpf(-1.0, 1.0, float(j) / nv)
				var raw: Vector3 = cube * half
				var core: Vector3 = raw.clamp(-inner, inner)
				var out: Vector3 = raw - core
				var normal: Vector3 = out.normalized() if out.length_squared() > 0.000001 else cube.normalized()
				var zip: Vector2 = _zip_coords(raw, half, axis, sign) if zipped else Vector2(1.0, 0.0)
				row.append([centre + core + normal * radius, normal, Vector2(float(i) / nu, float(j) / nv), zip])
			grid.append(row)
		for j: int in range(nv):
			for i: int in range(nu):
				var quad: Array = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					for k: int in _front_wound(quad[tri[0]][0], quad[tri[1]][0], quad[tri[2]][0], quad[tri[0]][1], tri):
						st.set_normal(quad[k][1])
						st.set_uv(quad[k][2])
						st.set_uv2(quad[k][3])
						st.add_vertex(quad[k][0])
	st.index()
	return st.commit()


## (distance to the zip seam, run along it from the top centre) for a point raw on the box, metres.
## The seam is the panel's top and side edges; past ZIP_FULL_M and off those faces there is none.
static func _zip_coords(raw: Vector3, half: Vector3, axis: int, sign: float) -> Vector2:
	var to_side: float = half.x - absf(raw.x)
	var to_top: float = half.y - raw.y
	var run: float = absf(raw.x) if axis == 1 or (axis == 2 and to_top < to_side) else half.x + to_top
	var distance: float = 1.0
	if axis == 2 and sign > 0.0:
		distance = minf(to_side, to_top)
	elif axis == 0 or (axis == 1 and sign > 0.0):
		distance = half.z - raw.z
	return Vector2(distance if run <= ZIP_FULL_M else 1.0, run)


## A point on the zip seam `run` metres from the top centre on one side (-1 left, +1 right):
## [position, outward normal, direction of travel], in pack space with the canvas at rest.
static func _seam_point(run: float, side: float) -> Array:
	var half: Vector3 = BODY * 0.5
	## Past the seam's end (a slider at full zip) both samples would clamp to one point.
	run = clampf(run, 0.0, half.x + BODY.y - ROUND_M)
	var at: Vector3 = _seam_surface(run, side, half)
	var ahead: Vector3 = _seam_surface(minf(run + 0.004, half.x + BODY.y - ROUND_M), side, half)
	var behind: Vector3 = _seam_surface(maxf(run - 0.004, 0.0), side, half)
	var raw := Vector3(side * minf(run, half.x), half.y - maxf(run - half.x, 0.0), half.z)
	var core: Vector3 = raw.clamp(-half + Vector3.ONE * ROUND_M, half - Vector3.ONE * ROUND_M)
	return [at, (raw - core).normalized(), (ahead - behind).normalized()]


static func _seam_surface(run: float, side: float, half: Vector3) -> Vector3:
	var raw := Vector3(side * clampf(run, 0.0, half.x), half.y - clampf(run - half.x, 0.0, BODY.y - ROUND_M), half.z)
	var core: Vector3 = raw.clamp(-half + Vector3.ONE * ROUND_M, half - Vector3.ONE * ROUND_M)
	return Vector3(0.0, half.y, half.z) + core + (raw - core).normalized() * ROUND_M


## Where the canvas moves a point at rest p (outward normal n): the empty slump plus `give` outward.
func _on_canvas(p: Vector3, n: Vector3, give: float) -> Vector3:
	## As the shader: the bulge over the main contents, and slack that sags only onto them.
	var push: float = 0.0
	var clear: float = 1.0
	for box: AABB in _main_proxies:
		var q: Vector3 = (p - box.get_center()).abs() - box.size * 0.5
		var d: float = q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - CANVAS_LINING_M
		push = maxf(push, smoothstep(CANVAS_SOFT_M, -CANVAS_SOFT_M, d) * maxf(CANVAS_SOFT_M - d, 0.0))
		clear = minf(clear, d)
	var empty: float = 1.0 - clampf(_fill, 0.0, 1.0)
	var high: float = smoothstep(BODY.y * 0.45, BODY.y, p.y)
	var slump: Vector3 = (Vector3(0.0, -SLUMP_TOP_M * high, 0.0) - n * SLUMP_WALL_M * smoothstep(0.1, 0.4, p.y / BODY.y)) * empty
	var sag: float = slump.length()
	if sag > 0.0:
		slump *= minf(sag, maxf(clear, 0.0)) / sag
	return p + slump + n * (minf(push, CANVAS_STRETCH_M) + give)


## Where the panel's bottom edge sits (its lowest vertex), in pack space: the hinge line.
static func _hinge_point(panel: ArrayMesh) -> Vector3:
	var lowest := Vector3(0.0, INF, 0.0)
	for v: Vector3 in panel.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if v.y < lowest.y:
			lowest = v
	return Vector3(0.0, lowest.y, lowest.z)


## Triangle order that faces normal (Godot's front faces wind clockwise seen from outside).
static func _front_wound(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, tri: Array) -> Array:
	return tri if (c - a).cross(b - a).dot(normal) >= 0.0 else [tri[0], tri[2], tri[1]]


## The actual packed mat and its two post-roll cinch straps, mounted across the pack top.
func _add_bedroll() -> void:
	_bedroll = Node3D.new()
	_bedroll.name = "Bedroll"
	_bedroll.visible = false
	add_child(_bedroll)
	_bedroll.position = _on_canvas(BEDROLL_AT, Vector3.UP, 0.0) - Vector3.UP * 0.008
	var roll := BEDROLL_PACKED.instantiate() as Node3D
	roll.name = "PackedMat"
	_bedroll.add_child(roll)
	StylizedEnvironmentMaterial.apply_to_tree(roll)
	## PackRig fits the canvas non-uniformly; keep the packed 39.9 cm width intact.
	roll.scale = Vector3.ONE / transform.basis.get_scale()
	## The removable loops around the roll are held by two short webbing tabs sewn
	## into the pack's top seams. No extra buckle or second roll mesh.
	var tether_material := StylizedEnvironmentMaterial.make_character(STRAP, 0.92)
	for side: float in [-1.0, 1.0]:
		var from_pack := Vector3(side * 0.11, 0.50, 0.15) - _bedroll.position
		var to_loop := Vector3(side * 0.11, 0.615, 0.12) - _bedroll.position
		var along := (to_loop - from_pack).normalized()
		var across := (Vector3.RIGHT - along * Vector3.RIGHT.dot(along)).normalized()
		var tether := MeshInstance3D.new()
		tether.name = "BedrollTetherLeft" if side < 0.0 else "BedrollTetherRight"
		var strap_mesh := BoxMesh.new()
		strap_mesh.size = Vector3(0.025, from_pack.distance_to(to_loop), 0.003)
		tether.mesh = strap_mesh
		tether.material_override = tether_material
		tether.transform = Transform3D(Basis(across, along, across.cross(along)), (from_pack + to_loop) * 0.5)
		_bedroll.add_child(tether)


func set_bedroll_visible(carried: bool) -> void:
	if _bedroll != null:
		_bedroll.visible = carried


func _add_straps() -> void:
	## Padded strips down the back where the shoulder straps are sewn, and the grab handle. The
	## strips wear the canvas shader, so they move with it.
	for x: float in [-0.11, 0.11]:
		_strap(Vector3(0.055, BODY.y * 0.78, 0.014), Vector3(x, BODY.y * 0.5, -0.009), Vector3.ZERO)
	_add_handle()


## A strap or buckle box baked into pack space, so the canvas shader shapes it with the shell.
func _strap(size: Vector3, at: Vector3, tilt: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays: Array = box.get_mesh_arrays()
	var xf := Transform3D(Basis.from_euler(tilt), at)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in range(verts.size()):
		verts[i] = xf * verts[i]
		normals[i] = xf.basis * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var strap := MeshInstance3D.new()
	strap.name = "Strap"
	strap.mesh = mesh
	strap.material_override = _strap_material
	add_child(strap)


## The grab handle: a webbing arch whose two feet stand on the top; placed on the canvas each frame.
func _add_handle() -> void:
	_handle = Node3D.new()
	_handle.name = "Handle"
	add_child(_handle)
	var webbing: StandardMaterial3D = _plain(STRAP)
	for x: float in [-0.045, 0.045]:
		var leg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.006, 0.034, 0.022)
		leg.mesh = box
		leg.material_override = webbing
		## Each foot is sewn flat to the top; the leg leans in towards the bar.
		leg.transform = Transform3D(Basis(Vector3.BACK, signf(x) * 0.5), Vector3(x, 0.015, 0.0))
		_handle.add_child(leg)
	var bar := MeshInstance3D.new()
	var grip := BoxMesh.new()
	grip.size = Vector3(0.08, 0.007, 0.022)
	bar.mesh = grip
	bar.material_override = webbing
	bar.position = Vector3(0.0, 0.031, 0.0)
	_handle.add_child(bar)
	for x: float in [-0.05, 0.05]:
		var foot := MeshInstance3D.new()
		var tab := BoxMesh.new()
		tab.size = Vector3(0.03, 0.004, 0.024)
		foot.mesh = tab
		foot.material_override = webbing
		foot.position = Vector3(x, 0.001, 0.0)
		_handle.add_child(foot)


## Two zip sliders, each with a pull tab that hangs toward the ground.
func _add_sliders() -> void:
	var metal: StandardMaterial3D = _plain(ZIP_METAL)
	metal.metallic = 0.7
	metal.roughness = 0.4
	for side: float in [-1.0, 1.0]:
		var slider := Node3D.new()
		slider.name = "SliderLeft" if side < 0.0 else "SliderRight"
		add_child(slider)
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(SLIDER_HALF_M * 2.0, 0.015, 0.009)
		body.mesh = box
		body.material_override = metal
		body.position.z = 0.003
		slider.add_child(body)
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.0, 0.008)
		slider.add_child(pivot)
		var tab := MeshInstance3D.new()
		var plate := BoxMesh.new()
		plate.size = Vector3(0.011, 0.034, 0.003)
		tab.mesh = plate
		tab.material_override = metal
		tab.position.y = -0.017
		pivot.add_child(tab)
		_sliders.append(slider)
		_tabs.append(pivot)


func _place_sliders(give: float) -> void:
	for i: int in range(_sliders.size()):
		var side: float = -1.0 if i == 0 else 1.0
		## Closed, the two sliders sit nose to nose either side of the top centre.
		var seam: Array = _seam_point(_zip + SLIDER_HALF_M, side)
		var normal: Vector3 = seam[1]
		var along: Vector3 = seam[2]
		var slider: Node3D = _sliders[i]
		slider.transform = Transform3D(Basis(along, normal.cross(along), normal).orthonormalized(), _on_canvas(seam[0], normal, give))
		if slider.is_inside_tree():
			## The tab hangs toward the ground, lying on the canvas (the slider's local XY plane). With
			## the canvas level, world down has no pull along it, and the tab keeps the slider's down.
			var down: Vector3 = slider.global_basis.orthonormalized().transposed() * Vector3.DOWN
			var hang := Vector3(down.x, down.y, 0.0)
			hang = hang.normalized() if hang.length() > 0.2 else Vector3.DOWN
			_tabs[i].basis = Basis(Vector3.BACK.cross(hang), -hang, Vector3.BACK)


## A strap loop on each side pocket with a carabiner hanging from it.
func _add_carabiners() -> void:
	var webbing: StandardMaterial3D = _plain(STRAP)
	for side: float in [-1.0, 1.0]:
		var loop := Node3D.new()
		loop.name = "PocketLoopLeft" if side < 0.0 else "PocketLoopRight"
		var tab := BoxMesh.new()
		tab.size = Vector3(0.004, LOOP_LENGTH_M, 0.02)
		var strip := MeshInstance3D.new()
		strip.mesh = tab
		strip.material_override = webbing
		## The node is the sewn point; the webbing runs down its local -Y.
		strip.position = Vector3(0.0, -LOOP_LENGTH_M * 0.5, 0.0)
		loop.add_child(strip)
		## Turned so its -Y runs out from the wall and down at LOOP_DROP_DEG.
		loop.rotation.z = side * deg_to_rad(90.0 - LOOP_DROP_DEG)
		add_child(loop)
		_loops.append(loop)
		var pivot := Node3D.new()
		pivot.name = "CarabinerLoopLeft" if side < 0.0 else "CarabinerLoopRight"
		add_child(pivot)
		var carabiner := Carabiner.new()
		carabiner.name = "Carabiner"
		## The ring lies along the wall, its gate toward the front.
		carabiner.face_yaw = -PI * 0.5
		pivot.add_child(carabiner)
		carabiner.build()
		## What hangs on it can push it out from the pack (it leans out along the side's normal).
		carabiner.contact_depth = _pack_contact
		_carabiners.append(carabiner)


func _place_carabiners() -> void:
	_to_pack = global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	_from_pack_basis = global_basis if is_inside_tree() else Basis.IDENTITY
	for i: int in range(_carabiners.size()):
		var side: float = -1.0 if i == 0 else 1.0
		var face: float = pocket_outer_x(i)
		_loops[i].position = Vector3(face, LOOP_SEW_Y, LOOP_Z)
		_side_face[i] = absf(face)
		_carabiners[i].contact_out = (global_basis * Vector3(side, 0.0, 0.0)).normalized() if is_inside_tree() else Vector3(side, 0.0, 0.0)
		_carabiners[i].get_parent_node_3d().position = loop_hold_point(i)


## Where carabiner `index` rests in its loop, pack space: LOOP_HOLD_M down the hanging webbing.
func loop_hold_point(index: int) -> Vector3:
	var loop: Node3D = _loops[index]
	return loop.transform * Vector3(0.0, -LOOP_HOLD_M, 0.0)


## Where pocket `index`'s outer cloth is now at the loop's seam, as signed x (0 left, 1 right).
func pocket_outer_x(index: int) -> float:
	var side: float = -1.0 if index == 0 else 1.0
	var seam := Vector3(side * (POCKET_X + POCKET_HALF.x), LOOP_SEW_Y, LOOP_Z)
	return pocket_cloth_point(index, seam, Vector3(side, 0.0, 0.0)).x


## Where pocket `index`'s cloth (0 left, 1 right) moves rest point p (outward normal n), pack space:
## the same rule as backpack_canvas.gdshader (kept side by side with it), for loops, contact, the
## inspector and the stand.
func pocket_cloth_point(index: int, p: Vector3, n: Vector3) -> Vector3:
	var side: float = -1.0 if index == 0 else 1.0
	return _pocket_cloth_rest(index, p, n) + Vector3(side * _pocket_shift(side, p), 0.0, 0.0)


## How far a pocket rides out from where it is sewn, as the shader: the wall's bulge over the main contents
## there, and the open front's give.
func _pocket_shift(side: float, p: Vector3) -> float:
	var wall := Vector3(side * body_side_x(p.y, p.z, false), p.y, p.z)
	var push: float = 0.0
	for box: AABB in _main_proxies:
		var q: Vector3 = (wall - box.get_center()).abs() - box.size * 0.5
		var d: float = q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - CANVAS_LINING_M
		push = maxf(push, smoothstep(CANVAS_SOFT_M, -CANVAS_SOFT_M, d) * maxf(CANVAS_SOFT_M - d, 0.0))
	return minf(push, CANVAS_STRETCH_M) + _side_give * (1.0 - smoothstep(0.0, 0.09, BODY.z - p.z))


func _pocket_cloth_rest(index: int, p: Vector3, n: Vector3) -> Vector3:
	var side: float = -1.0 if index == 0 else 1.0
	var flat: Vector3 = pocket_empty_point(index, p, n)
	var wall: float = side * body_side_x(p.y, p.z)
	var sleeve: int = sleeve_at(index, p.z)
	var held: Dictionary = _sleeve_item(sleeve)
	if held.is_empty():
		return flat
	var box: AABB = held["box"]
	var e: Vector2 = held["ellipse"]
	if e.x > 0.0:
		var axis: Vector2 = held["axis"]
		var d := Vector2(p.x, p.z) - axis
		var dl: float = d.length()
		var dir: Vector2 = d / dl if dl > 0.0001 else Vector2(side, 0.0)
		var hem: float = smoothstep(POCKET_RIM_Y - HEM_BAND_M, POCKET_RIM_Y, p.y)
		var grown: Vector2 = (e + Vector2.ONE * (POCKET_LINING_M + _hem_open[sleeve] * hem)).max(e + Vector2.ONE * 0.001)
		var r: float = 1.0 / (dir / grown).length()
		var bottom: float = box.position.y + _pocket_rise[sleeve]
		var round_xz: Vector2 = axis + dir * (minf(dl, r) if p.y < bottom - POCKET_LINING_M * 0.5 else r)
		var hug := Vector3(round_xz.x, p.y - _hem_drag[sleeve] * smoothstep(POCKET_RIM_Y - HEM_DRAG_FALL_M, POCKET_RIM_Y, p.y), round_xz.y)
		if n.x * side < -0.5:
			hug.x = wall
		var empty_w: float = smoothstep(0.0, POCKET_FUNNEL_M, bottom - p.y) * smoothstep(0.0, 0.01, _pocket_rise[sleeve])
		return hug.lerp(flat, empty_w)
	var c: Vector3 = box.get_center()
	var h: Vector3 = box.size * 0.5 + Vector3.ONE * POCKET_LINING_M
	var q: Vector3 = p.clamp(c - h, c + h)
	var inside: bool = (p - q).length() < 0.0001
	var target: Vector3
	if inside:
		var safe := Vector3(n.x if absf(n.x) > 0.001 else 0.001, n.y if absf(n.y) > 0.001 else 0.001, n.z if absf(n.z) > 0.001 else 0.001)
		var exits: Vector3 = (c + safe.sign() * h - p) / safe
		target = p + n * (minf(exits.x, minf(exits.y, exits.z)) + 0.002)
	else:
		target = q + (p - q).normalized() * 0.002
	if n.x * side < -0.5:
		target.x = wall
	return p + (target - p) * (1.0 if inside else 0.85)


## Which sleeve of pocket `index` (0 left, 1 right) cloth at depth z belongs to.
static func sleeve_at(index: int, z: float) -> int:
	if index == 0:
		return 0
	return 2 if z < SLEEVE_SPLIT_Z else 1


## Where an empty pocket `index` lays rest point p (normal n): its inner layer sewn on the body,
## the outer one a fold's thickness over it, the rim drooping (the shader's pocket_flat).
func pocket_empty_point(index: int, p: Vector3, n: Vector3) -> Vector3:
	var side: float = -1.0 if index == 0 else 1.0
	var out_x: float = (p.x - side * BODY.x * 0.5) * side
	var flat_y: float = p.y - 0.012 * smoothstep(0.1, 0.17, p.y)
	var layer: float = 0.0 if n.x * side < -0.5 else POCKET_FLAT_M + out_x * POCKET_FOLD_SPREAD
	return Vector3(side * (body_side_x(flat_y, p.z) + layer), flat_y, p.z)


## |x| of the body's side surface at (y, z), pack space: the box rounded by ROUND_M, caved in as
## the shell slumps empty (as backpack_canvas.gdshader's body_side_x); unslumped, the wall a full
## pack pushes out to.
func body_side_x(y: float, z: float, slumped: bool = true) -> float:
	var half: Vector3 = BODY * 0.5
	var dy: float = maxf(absf(y - half.y) - (half.y - ROUND_M), 0.0)
	var dz: float = maxf(absf(z - half.z) - (half.z - ROUND_M), 0.0)
	var x: float = half.x - ROUND_M + sqrt(maxf(ROUND_M * ROUND_M - dy * dy - dz * dz, 0.0))
	return x - SLUMP_WALL_M * (1.0 - clampf(_fill, 0.0, 1.0)) * smoothstep(0.1, 0.4, y / BODY.y) if slumped else x


## Live state of sleeve `index` (SLEEVE_SLOTS) for checks: rise (m above the seat), hem flare and
## drag (m), the held item's section (ellipse, radius = its larger half) and its bottom now.
func pocket_state(index: int) -> Dictionary:
	var held: Dictionary = _sleeve_item(index)
	if held.is_empty():
		return {}
	var e: Vector2 = held["ellipse"]
	return {"rise": _pocket_rise[index], "push": _pocket_push[index], "hem_open": _hem_open[index], "hem_drag": _hem_drag[index],
		"radius": maxf(e.x, e.y), "ellipse": e, "axis": held["axis"], "seat": held["seat"], "tool": held["tool"],
		"bottom": (held["box"] as AABB).position.y + _pocket_rise[index], "seat_bottom": (held["box"] as AABB).position.y,
		"height": (held["box"] as AABB).size.y, "node": held["node"]}


## Pushes what each sleeve holds down to its seat and runs the hem springs: the entering foot
## flares the hem, friction drags it down while the item moves, and both spring back once it sits.
func _step_pockets(delta: float) -> void:
	var omega: float = TAU * HEM_HZ
	for index: int in range(SLEEVE_SLOTS.size()):
		var held: Dictionary = _sleeve_item(index)
		var push: float = 0.0
		var flare: float = 0.0
		if not held.is_empty():
			var bottom: float = (held["box"] as AABB).position.y + _pocket_rise[index]
			if _pocket_rise[index] > 0.0:
				if bottom > POCKET_RIM_Y:
					push = INSERT_SPEED_FREE
				elif bottom > POCKET_RIM_Y - INSERT_HEM_ENTRY_M:
					push = INSERT_SPEED_HEM
				else:
					push = INSERT_SPEED_IN
				push *= clampf(_pocket_rise[index] / INSERT_EASE_M, 0.25, 1.0)
				_pocket_rise[index] = maxf(_pocket_rise[index] - push * delta, 0.0)
				(held["node"] as Node3D).position.y = (held["seat"] as Vector3).y + _pocket_rise[index]
			if bottom < POCKET_RIM_Y + 0.005 and bottom > POCKET_RIM_Y - INSERT_HEM_ENTRY_M and _pocket_rise[index] > 0.0:
				flare = HEM_FLARE_M
			if bottom >= POCKET_RIM_Y:
				push = 0.0  # in the air: nothing to drag the hem yet
		_pocket_push[index] = push
		_hem_open_speed[index] += (omega * omega * (flare - _hem_open[index]) - 2.0 * HEM_DAMPING * omega * _hem_open_speed[index]) * delta
		_hem_open[index] += _hem_open_speed[index] * delta
		_hem_drag_speed[index] += (omega * omega * (push * HEM_DRAG_PER_MPS - _hem_drag[index]) - 2.0 * HEM_DAMPING * omega * _hem_drag_speed[index]) * delta
		_hem_drag[index] += _hem_drag_speed[index] * delta
		if not (is_finite(_hem_open[index]) and is_finite(_hem_drag[index])):
			_hem_open[index] = 0.0
			_hem_drag[index] = 0.0
			_hem_open_speed[index] = 0.0
			_hem_drag_speed[index] = 0.0
	_handle_capsules.clear()
	for sleeve: int in range(SLEEVE_SLOTS.size()):
		var tool: Dictionary = _sleeve_item(sleeve)
		if not tool.is_empty() and tool["tool"]:
			var axis: Vector2 = tool["axis"]
			var e: Vector2 = tool["ellipse"]
			_handle_capsules.append(Vector4(axis.x, axis.y, (tool["box"] as AABB).position.y + _pocket_rise[sleeve], maxf(e.x, e.y)))
	if not _pocket_materials.is_empty():
		_send_sleeves()


func _sleeve_item(index: int) -> Dictionary:
	if index < 0 or index >= SLEEVE_SLOTS.size():
		return {}
	for item: Dictionary in _items:
		if item["slot"] == SLEEVE_SLOTS[index]:
			return item
	return {}


## The divider between the right pocket's sleeves: dark cloth from the body to the outer cloth at
## SLEEVE_SPLIT_Z, rim to bottom, rebuilt each frame on the cloth as it is.
func _place_divider() -> void:
	var mesh: ImmediateMesh = _divider.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var bottom: float = POCKET_CENTRE_Y - POCKET_HALF.y + 0.01
	for k: int in range(9):
		var y: float = lerpf(bottom, POCKET_RIM_Y - 0.004, k / 8.0)
		var inner: float = body_side_x(y, SLEEVE_SPLIT_Z)
		var outer: float = absf(pocket_cloth_point(1, Vector3(POCKET_X + POCKET_HALF.x, y, SLEEVE_SPLIT_Z), Vector3.RIGHT).x) - 0.002
		mesh.surface_set_normal(Vector3.BACK)
		mesh.surface_add_vertex(Vector3(inner, y, SLEEVE_SPLIT_Z))
		mesh.surface_set_normal(Vector3.BACK)
		mesh.surface_add_vertex(Vector3(maxf(outer, inner + 0.001), y, SLEEVE_SPLIT_Z))
	mesh.surface_end()


func _plain(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	return material


## The clipped item struck something: a dull knock where it hangs, louder for a faster strike.
func _on_clipped_knock(rate: float, swing: PendulumHang) -> void:
	knock_count += 1
	var sound := get_node_or_null(^"/root/SoundSystem") as SOUND_SYSTEM_SCRIPT
	if sound != null and is_inside_tree():
		sound.play(KNOCK_EVENT, swing.global_position, lerpf(KNOCK_QUIET_DB, 0.0, clampf(rate / KNOCK_FULL_RATE, 0.0, 1.0)))


## How deep world point `at` is inside the pack: the signed distance to its body (a box rounded
## by ROUND_M), each side pocket's cloth as placed this frame and the tool handles hanging below
## the sleeves. Vector4(outward world normal, depth).
func _pack_contact(at: Vector3) -> Vector4:
	var floor: Vector4 = Vector4(0.0, 1.0, 0.0, hang_floor_y - at.y)  # the floor, when set: a plane facing up
	var body: Vector4 = _body_contact(at)
	return floor if floor.w > body.w else body


## The pack's own body, pockets and the tools' handles (see _pack_contact).
func _body_contact(at: Vector3) -> Vector4:
	var q: Vector3 = _to_pack * at
	var best: Vector4 = _round_box(q, Vector3(0.0, BODY.y * 0.5, BODY.z * 0.5), BODY * 0.5, ROUND_M)
	## Pockets and handles only matter beside the body's sides, below the rims.
	if absf(q.x) < BODY.x * 0.5 - 0.02 or q.y > POCKET_RIM_Y + 0.02:
		var n: Vector3 = (_from_pack_basis * Vector3(best.x, best.y, best.z)).normalized()
		return Vector4(n.x, n.y, n.z, -best.w)
	for i: int in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		var inner: float = BODY.x * 0.5 - 0.01
		var half := Vector3((_side_face[i] - inner) * 0.5, POCKET_HALF.y, POCKET_HALF.z)
		var pocket: Vector4 = _round_box(q, Vector3(side * (inner + half.x), POCKET_CENTRE_Y, BODY.z * 0.5), half, 0.008)
		if pocket.w < best.w:
			best = pocket
	## Tools hanging through the sleeves: their handles, as vertical capsules down from the rim.
	for capsule: Vector4 in _handle_capsules:
		var away: Vector3 = q - Vector3(capsule.x, clampf(q.y, capsule.z, POCKET_RIM_Y), capsule.y)
		var reach: float = away.length()
		if reach - capsule.w < best.w:
			var dir: Vector3 = away / reach if reach > 0.000001 else Vector3.UP
			best = Vector4(dir.x, dir.y, dir.z, reach - capsule.w)
	var normal: Vector3 = (_from_pack_basis * Vector3(best.x, best.y, best.z)).normalized()
	return Vector4(normal.x, normal.y, normal.z, -best.w)


## Signed distance from q to a box (centre c, half size h) with edges rounded by r, and its outward
## normal: Vector4(normal, distance), negative inside (Inigo Quilez's rounded box).
static func _round_box(q: Vector3, c: Vector3, h: Vector3, r: float) -> Vector4:
	var d: Vector3 = q - c
	var k: Vector3 = d.abs() - (h - Vector3.ONE * r)
	var outside: Vector3 = k.max(Vector3.ZERO)
	var dist: float = outside.length() + minf(maxf(k.x, maxf(k.y, k.z)), 0.0) - r
	var n: Vector3
	if outside.length() > 0.0:
		n = (outside * d.sign()).normalized()
	elif k.x >= k.y and k.x >= k.z:
		n = Vector3(signf(d.x), 0.0, 0.0)
	elif k.y >= k.z:
		n = Vector3(0.0, signf(d.y), 0.0)
	else:
		n = Vector3(0.0, 0.0, signf(d.z))
	return Vector4(n.x, n.y, n.z, dist)


## A visual's surface points in its parent's space (where it hangs), one per CONTACT_CELL_M cell: the
## vertex nearest its cell's mean (vertex clustering), so no corner pick leaves a gap a tool handle slips into.
static func _contact_points(visual: Node3D) -> PackedVector3Array:
	var cells: Dictionary = {}
	var sums: Dictionary = {}
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var chain: Transform3D = Transform3D.IDENTITY
		var walk: Node = mesh_node
		while walk != visual and walk is Node3D:
			chain = (walk as Node3D).transform * chain
			walk = walk.get_parent()
		for v: Vector3 in mesh_node.mesh.get_faces():
			var p: Vector3 = visual.transform * chain * v
			var key: Vector3i = Vector3i((p / CONTACT_CELL_M).floor())
			if not cells.has(key):
				cells[key] = []  # an Array, shared by reference (a packed one would append to a copy)
				sums[key] = Vector3.ZERO
			(cells[key] as Array).append(p)
			sums[key] += p
	var points := PackedVector3Array()
	for key: Vector3i in cells:
		var members: Array = cells[key]
		var mean: Vector3 = sums[key] / float(members.size())
		var pick: Vector3 = members[0]
		for p: Vector3 in members:
			if p.distance_squared_to(mean) < pick.distance_squared_to(mean):
				pick = p
		points.append(pick)
	return points


## Centre of mass of a thin-walled visual in its own space: its surface triangles' centroids
## weighted by area (a steel mug's mass is in its walls).
static func _shell_centroid(visual: Node3D) -> Vector3:
	var sum := Vector3.ZERO
	var area: float = 0.0
	for node: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var xf: Transform3D = Transform3D.IDENTITY
		var walk: Node = mesh_node
		while walk != visual and walk is Node3D:
			xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var faces: PackedVector3Array = mesh_node.mesh.get_faces()
		for i: int in range(0, faces.size() - 2, 3):
			var a: Vector3 = xf * faces[i]
			var b: Vector3 = xf * faces[i + 1]
			var c: Vector3 = xf * faces[i + 2]
			var w: float = (b - a).cross(c - a).length() * 0.5
			sum += (a + b + c) / 3.0 * w
			area += w
	return sum / area if area > 0.0 else _local_bounds(visual).get_center()


## Bounds of a freshly built visual in its own space.
static func _local_bounds(visual: Node3D) -> AABB:
	var box := AABB()
	var first: bool = true
	for node: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var xf: Transform3D = Transform3D.IDENTITY
		var walk: Node = mesh_node
		while walk != visual and walk is Node3D:
			xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var part: AABB = xf * mesh_node.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
