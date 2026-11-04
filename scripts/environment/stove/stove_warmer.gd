class_name StoveWarmer
extends Node3D

## The cooking ring on the stove top. F with a warmable item carried puts one
## there; while the stove burns it warms over WARM_HOURS of game time; then F
## eats or drinks it straight off the stove. Saved with the world.

signal state_changed(state: State)

enum State { EMPTY, WARMING, READY }

const WARM_HOURS: float = 0.5
## Real presentation time for a full 30-minute cooking/melting action.
const WARM_PRESENTATION_SECONDS: float = 6.0
const WARM_STEP_HOURS: float = 1.0 / 60.0
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PROMPT_SCRIPT: String = "res://scripts/environment/stove/stove_warmer_prompt.gd"
const PUT_KEY: String = "WARM_PUT"
const WARMING_KEY: String = "WARM_WARMING"
const EAT_KEY: String = "TABLE_EAT"
const DRINK_KEY: String = "TABLE_DRINK"

@export var source: HeatSource
## The original ring keeps its save key; a second ring supplies its own key in the scene.
@export var save_key: StringName = &"stove_warmer"

var _state: State = State.EMPTY
## The raw item while warming, the warmed one when ready.
var _item_id: StringName = &""
var _progress_h: float = 0.0
var _prop: Node3D
var _prompt: InteractiveArea
var _steam: GPUParticles3D
var _action_id: StringName = &""
var _action_managed: bool = false

## One shared physical cooking plate. The old warming states and save keys stay intact.
## A pan excludes warmable vessels and carries its own persistent contents.
enum EggState { NONE, COOKING, READY }
const PAN_ID: StringName = &"frying_pan"
const RAW_EGG_ID: StringName = &"egg_raw"
const FRIED_EGG_ID: StringName = &"egg_fried"
const EGG_COOK_HOURS: float = PanCookingModel.READY_HOURS # legacy recipe threshold
const OIL_ID: StringName = &"cooking_oil_portion"
const SALT_ID: StringName = &"salt_pinch"
const PEPPER_ID: StringName = &"pepper_pinch"

var _pan_installed: bool = false
var _pan_instance_state: Dictionary = {}
var _egg_state: EggState = EggState.NONE
var _egg_progress_h: float = 0.0
var _egg_intro_seconds: float = 0.0
var _egg_visual: EggCookingVisual
var _egg_visuals: Array[EggCookingVisual] = []
var _recipe: PanCookingModel = PanCookingModel.new()


func _process(delta: float) -> void:
	if _pan_installed and _recipe.advance_intro(delta):
		_sync_legacy_egg_state()
		_sync_egg_visual()


func has_pan() -> bool:
	return _pan_installed


func get_egg_state() -> EggState:
	return _egg_state


func get_egg_progress_h() -> float:
	return _egg_progress_h


func get_egg_count() -> int:
	return _recipe.eggs.size()


func get_egg_quality(index: int) -> StringName:
	return _recipe.get_quality(index)


func get_recipe_data() -> Dictionary:
	return _recipe.to_save()


## Each action is explicit. UI cannot remove a pan or consume food through a fallback click.
func get_cooking_actions(inventory: InventoryComponent) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not _pan_installed:
		if _state == State.EMPTY:
			actions.append({"id": &"place_pan", "label": "PAN", "enabled": inventory != null and inventory.has_item(PAN_ID)})
		return actions
	var burning: bool = source != null and source.is_burning()
	if _recipe.eggs.size() < PanCookingModel.MAX_EGGS:
		actions.append({"id": &"egg", "label": "EGG %d/3" % _recipe.eggs.size(), "enabled": burning and inventory != null and inventory.has_item(RAW_EGG_ID)})
	if not _recipe.oil:
		actions.append({"id": &"oil", "label": "OIL", "enabled": inventory != null and inventory.has_item(OIL_ID)})
	if _recipe.eggs.size() > 0:
		if not _recipe.salt:
			actions.append({"id": &"salt", "label": "SALT", "enabled": inventory != null and inventory.has_item(SALT_ID)})
		if not _recipe.pepper:
			actions.append({"id": &"pepper", "label": "PEPPER", "enabled": inventory != null and inventory.has_item(PEPPER_ID)})
		if _recipe.first_ready_index() >= 0:
			actions.append({"id": &"take_egg", "label": "TAKE EGG", "enabled": true})
	else:
		actions.append({"id": &"remove_pan", "label": "REMOVE PAN", "enabled": inventory != null})
	return actions


func perform_cooking_action(inventory: InventoryComponent, action_id: StringName) -> bool:
	match action_id:
		&"place_pan": return put_pan(inventory)
		&"remove_pan": return take_pan(inventory)
		&"egg": return crack_egg(inventory)
		&"oil": return add_oil(inventory)
		&"salt": return add_seasoning(inventory, SALT_ID)
		&"pepper": return add_seasoning(inventory, PEPPER_ID)
		&"take_egg": return take_fried_egg(inventory)
	return false


func add_oil(inventory: InventoryComponent) -> bool:
	if inventory == null or not _pan_installed or _recipe.oil or not inventory.try_remove(OIL_ID):
		return false
	_recipe.oil = true
	_refresh()
	state_changed.emit(_state)
	return true


func add_seasoning(inventory: InventoryComponent, item_id: StringName) -> bool:
	if inventory == null or not _pan_installed or _recipe.eggs.is_empty():
		return false
	if item_id == SALT_ID and not _recipe.salt and inventory.try_remove(item_id):
		_recipe.salt = true
	elif item_id == PEPPER_ID and not _recipe.pepper and inventory.try_remove(item_id):
		_recipe.pepper = true
	else:
		return false
	_refresh()
	state_changed.emit(_state)
	return true


func _sync_legacy_egg_state() -> void:
	if _recipe.eggs.is_empty():
		_egg_state = EggState.NONE
		_egg_progress_h = 0.0
		_egg_intro_seconds = 0.0
		return
	var head: Dictionary = _recipe.eggs[0]
	_egg_progress_h = minf(EGG_COOK_HOURS, float(head.get("heat_h", 0.0)))
	_egg_intro_seconds = minf(3.0, float(head.get("intro", 3.0)))
	_egg_state = EggState.COOKING if _recipe.get_quality(0) == &"cooking" else EggState.READY


## This transfers the actual nonstackable inventory instance, not a duplicate visual.
func put_pan(inventory: InventoryComponent) -> bool:
	if inventory == null or _pan_installed or _state != State.EMPTY:
		return false
	var moved: Dictionary = inventory.take_instance(PAN_ID)
	if moved.is_empty():
		return false
	_pan_installed = true
	_pan_instance_state = (moved.get("instance_state", {}) as Dictionary).duplicate(true)
	_recipe.clear()
	_sync_legacy_egg_state()
	_refresh()
	state_changed.emit(_state)
	return true


func take_pan(inventory: InventoryComponent) -> bool:
	if inventory == null or not _pan_installed or not _recipe.eggs.is_empty():
		return false
	var item: ItemResource = ItemCatalog.get_item(PAN_ID)
	if item == null or inventory.get_add_refusal(item) != &"":
		return false
	if not inventory.try_add_instance(item, _pan_instance_state):
		return false
	_pan_installed = false
	_pan_instance_state = {}
	_recipe.clear()
	_sync_legacy_egg_state()
	_refresh()
	state_changed.emit(_state)
	return true


## Egg becomes stove-owned at commit. Its seven-second visual is not a timer.
func crack_egg(inventory: InventoryComponent) -> bool:
	if inventory == null or not _pan_installed or _recipe.eggs.size() >= PanCookingModel.MAX_EGGS or source == null or not source.is_burning():
		return false
	if not inventory.try_remove(RAW_EGG_ID):
		return false
	_recipe.add_egg()
	_sync_legacy_egg_state()
	_refresh()
	state_changed.emit(_state)
	return true


func take_fried_egg(inventory: InventoryComponent) -> bool:
	if inventory == null or not _pan_installed:
		return false
	var index: int = _recipe.first_ready_index()
	if index < 0:
		return false
	var quality: StringName = _recipe.get_quality(index)
	var output_id: StringName = &"egg_fried_burnt" if quality == &"burnt" else (&"egg_fried_well" if quality == &"well" else FRIED_EGG_ID)
	var item: ItemResource = ItemCatalog.get_item(output_id)
	if item == null or not inventory.try_add(item):
		return false
	_recipe.eggs.remove_at(index)
	_sync_legacy_egg_state()
	_refresh()
	state_changed.emit(_state)
	return true


func _sync_egg_visual() -> void:
	for i: int in range(mini(_egg_visuals.size(), _recipe.eggs.size())):
		var visual: EggCookingVisual = _egg_visuals[i]
		if not is_instance_valid(visual):
			continue
		var entry: Dictionary = _recipe.eggs[i]
		var intro: float = float(entry.get("intro", 0.0))
		var heat: float = float(entry.get("heat_h", 0.0))
		var seconds: float = intro if intro < 3.0 else 3.0 + 4.0 * clampf(heat / EGG_COOK_HOURS, 0.0, 1.0)
		visual.seek_seconds(seconds)
		visual.set_doneness(clampf((heat - EGG_COOK_HOURS) / (PanCookingModel.BURNT_HOURS + (0.025 if _recipe.oil else 0.0) - EGG_COOK_HOURS), 0.0, 1.0))



func _ready() -> void:
	add_to_group(&"saveable")
	if source == null:
		source = get_parent() as HeatSource
	if source != null:
		source.heat_elapsed.connect(advance)
	_build_prompt()
	_refresh()


func get_state() -> State:
	return _state


func get_item_id() -> StringName:
	return _item_id


## The first carried item that warms into something, or empty.
func find_warmable(inventory: InventoryComponent) -> StringName:
	if inventory == null:
		return &""
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item != null and item.warms_into != &"":
			return item.id
	return &""


## Takes one warmable item from the pack and sets it on the ring.
func put(inventory: InventoryComponent, item_id: StringName) -> bool:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if _state != State.EMPTY or item == null or item.warms_into == &"" or not inventory.try_remove(item_id):
		return false
	_item_id = item_id
	_progress_h = 0.0
	_set_state(State.WARMING)
	return true


## Game time the stove burned through; the item warms only while it burns.
func advance(hours: float) -> void:
	if _pan_installed and not _recipe.eggs.is_empty():
		var before: Array[StringName] = []
		for i: int in range(_recipe.eggs.size()):
			before.append(_recipe.get_quality(i))
		_recipe.advance_heat(hours)
		for i: int in range(_recipe.eggs.size()):
			if before[i] != _recipe.get_quality(i):
				state_changed.emit(_state)
		_sync_legacy_egg_state()
		_sync_egg_visual()
		return
	if _state != State.WARMING:
		return
	_progress_h = minf(WARM_HOURS, _progress_h + maxf(hours, 0.0))
	if _progress_h >= WARM_HOURS - 0.000001:
		_finish_warming()


## Eats or drinks the warmed item off the ring.
func take(eater: ConsumptionController) -> bool:
	if _state != State.READY or eater == null:
		return false
	if eater.consume_from_world(_item_id) != ConsumptionController.Refusal.NONE:
		return false
	_item_id = &""
	_set_state(State.EMPTY)
	return true


## F on the ring: put, or eat, depending on state. Called by the prompt.
func interact_with(player: Node) -> void:
	if player == null:
		return
	var inventory: InventoryComponent = InventoryComponent.find_in(player)
	if _pan_installed:
		if _recipe.first_ready_index() >= 0:
			take_fried_egg(inventory)
		elif _recipe.eggs.size() < PanCookingModel.MAX_EGGS and source != null and source.is_burning() and inventory != null and inventory.has_item(RAW_EGG_ID):
			crack_egg(inventory)
		elif _recipe.eggs.is_empty():
			take_pan(inventory)
		return
	if _state == State.EMPTY and inventory != null and inventory.has_item(PAN_ID):
		put_pan(inventory)
		return
	match _state:
		State.EMPTY:
			var actions: TimeCostedActionSystem = _actions()
			if actions != null and actions.is_active():
				return
			var id: StringName = find_warmable(inventory)
			if put(inventory, id):
				_start_warm_action(player)
		State.WARMING:
			_start_warm_action(player)
		State.READY:
			take(player.get_node_or_null(^"ConsumptionController") as ConsumptionController)


func can_interact_with(player: Node) -> bool:
	var inventory: InventoryComponent = InventoryComponent.find_in(player)
	if _pan_installed:
		if _recipe.first_ready_index() >= 0:
			return inventory != null
		if _recipe.eggs.size() < PanCookingModel.MAX_EGGS and source != null and source.is_burning() and inventory != null and inventory.has_item(RAW_EGG_ID):
			return true
		return _recipe.eggs.is_empty() and inventory != null and inventory.get_add_refusal(ItemCatalog.get_item(PAN_ID)) == &""
	if _state == State.EMPTY and inventory != null and inventory.has_item(PAN_ID):
		return true
	match _state:
		State.EMPTY:
			var actions: TimeCostedActionSystem = _actions()
			return (
				source != null
				and source.is_burning()
				and (actions == null or not actions.is_active())
				and find_warmable(InventoryComponent.find_in(player)) != &""
			)
		State.WARMING:
			var actions: TimeCostedActionSystem = _actions()
			return source != null and source.is_burning() and (actions == null or not actions.is_active())
		State.READY:
			return true
	return false


func get_prompt_text(player: Node) -> String:
	if _pan_installed:
		return "Cooktop: %d/3 eggs; open cooking ring" % _recipe.eggs.size()
	if _state == State.EMPTY:
		var pack_inventory: InventoryComponent = InventoryComponent.find_in(player)
		if pack_inventory != null and pack_inventory.has_item(PAN_ID):
			return "Place frying pan"
	match _state:
		State.EMPTY:
			var id: StringName = find_warmable(InventoryComponent.find_in(player))
			var raw: ItemResource = ItemCatalog.get_item(id) if id != &"" else null
			return "%s: %s" % [tr(PUT_KEY), tr(raw.display_name) if raw != null else ""]
		State.WARMING:
			return tr(WARMING_KEY)
	var hot: ItemResource = ItemCatalog.get_item(_item_id)
	var drink: bool = hot != null and hot.consumable != null and hot.consumable.calories <= 0.0
	return "%s: %s" % [tr(DRINK_KEY if drink else EAT_KEY), tr(hot.display_name) if hot != null else ""]


func _start_warm_action(player: Node) -> bool:
	if _state != State.WARMING or source == null or not source.is_burning():
		return false
	var actions: TimeCostedActionSystem = _actions()
	if actions == null:
		## Isolated tools may still advance the HeatSource explicitly.
		return false
	if actions.is_active():
		return false

	var remaining_h: float = maxf(WARM_HOURS - _progress_h, 0.0)
	if remaining_h <= 0.000001:
		return true

	var request := TimeActionRequest.new()
	var reason: StringName = _warm_reason()
	_action_id = StringName("%s:%d" % [String(reason), get_instance_id()])
	request.action_id = _action_id
	request.duration_hours = remaining_h
	request.presentation_seconds = WARM_PRESENTATION_SECONDS * (remaining_h / WARM_HOURS)
	request.reason = reason
	request.actor = player
	request.target = self
	request.interruptible = true
	request.simulation_step_hours = WARM_STEP_HOURS
	request.player_mode = _resolve_player_mode(&"WORKING")
	request.stop_check = _warm_stop_reason
	request.on_complete = _warm_action_completed
	request.on_cancel = _warm_action_cancelled
	_action_managed = actions.start_action(request)
	return _action_managed


func _warm_reason() -> StringName:
	if _item_id in [&"mug_snow", &"snow_handful"]:
		return &"melt_snow"
	return &"cook_food"


func _warm_stop_reason() -> StringName:
	if _state != State.WARMING:
		return &""
	if source == null:
		return &"target_lost"
	if not source.is_burning():
		return &"fire_out"
	return &""


func _warm_action_completed(_elapsed_h: float) -> void:
	_action_managed = false
	_action_id = &""
	## The HeatSource heat_elapsed signal is the recipe truth. If a custom
	## source failed to provide enough actual heat, leave the item warming.
	if _state == State.WARMING and _progress_h >= WARM_HOURS - 0.000001:
		_finish_warming()


func _warm_action_cancelled(_elapsed_h: float, _reason: StringName) -> void:
	_action_managed = false
	_action_id = &""


func _is_action_active() -> bool:
	if not _action_managed:
		return false
	var actions: TimeCostedActionSystem = _actions()
	return actions != null and actions.get_active_action_id() == _action_id


func _actions() -> TimeCostedActionSystem:
	return TimeCostedActionSystem.find(get_tree()) if is_inside_tree() else null


func _resolve_player_mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state == null:
		return -1
	var script: Script = state.get_script() as Script
	if script == null:
		return -1
	var constants: Dictionary = script.get_script_constant_map()
	var modes: Dictionary = constants.get("Mode", {})
	return int(modes.get(String(mode_name), -1))


func _finish_warming() -> void:
	if _state != State.WARMING:
		return
	var raw: ItemResource = ItemCatalog.get_item(_item_id)
	_item_id = raw.warms_into if raw != null else &""
	_progress_h = WARM_HOURS
	_set_state(State.READY if _item_id != &"" else State.EMPTY)


func _set_state(state: State) -> void:
	_state = state
	_refresh()
	state_changed.emit(state)


func _refresh() -> void:
	if is_instance_valid(_prop):
		_prop.queue_free()
	_prop = null
	_egg_visual = null
	_egg_visuals.clear()
	if _pan_installed:
		_prop = SurvivalItemVisual.make(PAN_ID)
		_prop.name = "CookwareFryingPan"
		_prop.position.y = 0.012 # Warmer anchor at 0.69 m; ring top at ~0.702 m.
		add_child(_prop)
		if _recipe.oil:
			var oil_mesh := MeshInstance3D.new()
			oil_mesh.name = "OilFilm"
			var disc := CylinderMesh.new()
			disc.top_radius = 0.093
			disc.bottom_radius = 0.093
			disc.height = 0.001
			oil_mesh.mesh = disc
			oil_mesh.position.y = 0.009
			var grease := StandardMaterial3D.new()
			grease.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			grease.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			grease.albedo_color = Color(0.96, 0.78, 0.34, 0.22)
			oil_mesh.material_override = grease
			_prop.add_child(oil_mesh)
		for i: int in range(_recipe.eggs.size()):
			var entry: Dictionary = _recipe.eggs[i]
			var visual := EggCookingVisual.new()
			visual.name = "EggCookingVisual%02d" % i
			visual.rotation.y = PI * 0.5
			visual.scale = Vector3.ONE * 0.56
			visual.position = Vector3(float(entry.get("x", 0.0)), 0.010, float(entry.get("z", 0.0)))
			_prop.add_child(visual)
			_egg_visuals.append(visual)
			if i == 0:
				_egg_visual = visual
		if _recipe.salt or _recipe.pepper:
			_add_seasoning_visual()
		_sync_egg_visual()
	elif _item_id != &"":
		_prop = _make_prop(_item_id)
		add_child(_prop)
	if _steam != null:
		_steam.emitting = _state == State.READY
	if _prompt != null:
		_prompt.call(&"refresh_label")


## Restrained NPR specks for seasoning; no particle simulation or UI-only state.
func _add_seasoning_visual() -> void:
	for i: int in range(19):
		var angle: float = TAU * float(i) / 19.0
		var r: float = 0.024 + 0.055 * float((i * 7) % 19) / 19.0
		var speck := MeshInstance3D.new()
		speck.name = "SaltOrPepper%02d" % i
		var mesh := SphereMesh.new()
		mesh.radius = 0.0007 if (_recipe.salt and i % 2 == 0) else 0.0012
		mesh.height = mesh.radius * 1.7
		mesh.radial_segments = 6
		mesh.rings = 3
		speck.mesh = mesh
		speck.position = Vector3(cos(angle) * r, 0.016, sin(angle) * r)
		var color: Color = Color(0.92, 0.90, 0.79) if (_recipe.salt and i % 2 == 0) else Color(0.14, 0.11, 0.09)
		speck.material_override = StylizedEnvironmentMaterial.make_unshaded(color)
		_prop.add_child(speck)


## A tin on the ring for stew; a small pot for snow and water.
func _make_prop(item_id: StringName) -> Node3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var metal := StandardMaterial3D.new()
	metal.metallic = 0.8
	metal.roughness = 0.4
	if item_id == &"tinned_stew" or item_id == &"tinned_stew_hot":
		mesh.top_radius = 0.037
		mesh.bottom_radius = 0.037
		mesh.height = 0.075
		metal.albedo_color = Color(0.62, 0.6, 0.55)
	else:
		mesh.top_radius = 0.07
		mesh.bottom_radius = 0.06
		mesh.height = 0.08
		metal.albedo_color = Color(0.35, 0.36, 0.38)
		var fill := MeshInstance3D.new()
		var surface := CylinderMesh.new()
		surface.top_radius = 0.064
		surface.bottom_radius = 0.064
		surface.height = 0.01
		var look := StandardMaterial3D.new()
		look.albedo_color = Color(0.93, 0.95, 0.98) if item_id == &"snow_handful" else Color(0.55, 0.62, 0.66)
		surface.material = look
		fill.mesh = surface
		fill.position.y = 0.03
		node.add_child(fill)
	mesh.material = metal
	node.mesh = mesh
	node.position.y = mesh.height * 0.5
	var holder := Node3D.new()
	holder.add_child(node)
	return holder


func _build_prompt() -> void:
	var area: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	area.name = "Warm"
	area.set_script(load(PROMPT_SCRIPT))
	area.set(&"warmer", self)
	area.set(&"interactable_scene", null)
	area.set(&"object_on_ground", false)
	area.set(&"info_height_offset", 0.4)
	var col := area.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.28, 0.3, 0.24)
		col.shape = shape
	add_child(area)
	_prompt = area as InteractiveArea
	_steam = GPUParticles3D.new()
	_steam.amount = 16
	_steam.lifetime = 1.4
	_steam.emitting = false
	_steam.position.y = 0.1
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 6.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.3
	process.gravity = Vector3(0.0, 0.05, 0.0)
	_steam.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(0.06, 0.06)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	look.disable_fog = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	soft.gradient = falloff
	look.albedo_texture = soft
	puff.material = look
	_steam.draw_pass_1 = puff
	add_child(_steam)


func get_save_key() -> StringName:
	return save_key


func get_save_data() -> Dictionary:
	return {"state": int(_state), "item": String(_item_id), "progress": _progress_h,
		"pan_installed": _pan_installed, "pan_instance_state": _pan_instance_state.duplicate(true),
		"egg_state": int(_egg_state), "egg_progress_h": _egg_progress_h,
		"egg_intro_seconds": _egg_intro_seconds, "pan_recipe": _recipe.to_save()}


func load_save_data(data: Dictionary) -> void:
	_action_managed = false
	_action_id = &""
	_state = int(data.get("state", 0)) as State
	_item_id = StringName(data.get("item", ""))
	_progress_h = clampf(float(data.get("progress", 0.0)), 0.0, WARM_HOURS)
	if _item_id == &"" or ItemCatalog.get_item(_item_id) == null:
		_state = State.EMPTY
		_item_id = &""
	_pan_installed = bool(data.get("pan_installed", false))
	_pan_instance_state = (data.get("pan_instance_state", {}) as Dictionary).duplicate(true)
	_recipe.from_save(data.get("pan_recipe", {}) as Dictionary)
	## Migrate saves written by the old one-egg implementation.
	if _pan_installed and not data.has("pan_recipe") and int(data.get("egg_state", 0)) != EggState.NONE:
		_recipe.add_egg()
		var old: Dictionary = _recipe.eggs[0]
		old["heat_h"] = maxf(float(data.get("egg_progress_h", 0.0)), EGG_COOK_HOURS if int(data.get("egg_state", 0)) == EggState.READY else 0.0)
		old["intro"] = float(data.get("egg_intro_seconds", 3.0))
		_recipe.eggs[0] = old
	if not _pan_installed:
		_pan_instance_state = {}
		_recipe.clear()
	if _pan_installed:
		_state = State.EMPTY
		_item_id = &""
		_progress_h = 0.0
	_sync_legacy_egg_state()
	_refresh()
