extends SceneTree

## Covers foot contact and the prints it leaves: one print per step, the right
## foot's print for the right foot, toe pointing where the foot points.
## Run: godot --headless --script tests/systems/test_footprints.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_a_step_plants_once()
	_test_blended_lift_rearms_through_probe_gap()
	_test_small_foot_jitter_does_not_rearm()
	_test_driven_contacts_plant_once_per_print()
	_test_surface_clearance_follows_the_slope_normal()
	_test_standing_still_leaves_nothing()
	_test_the_air_leaves_nothing()
	_test_the_rig_has_the_bones()
	_test_prints_point_heel_to_toe()
	_test_each_foot_leaves_its_own_print()
	_test_the_pool_reuses_the_oldest()
	_test_a_print_lies_along_a_slope()
	_test_snowfall_buries_the_trail_faster()
	if _failures > 0:
		push_error("footprints: %d check(s) failed" % _failures)
		quit(1)
		return
	print("footprints: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("footprints: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _sensor() -> FootContactSensor:
	var sensor := FootContactSensor.new()
	root.add_child(sensor)
	return sensor


## Walks one foot through a stride: up, down, and held on the ground.
func _stride(sensor: FootContactSensor, side: int, on_floor: bool, speed: float) -> int:
	var planted: int = 0
	for height: float in [0.2, 0.12, 0.05, 0.02, 0.01, 0.01, 0.02]:
		if sensor.update_foot(side, height, Vector3.ZERO, Vector3.FORWARD, on_floor, speed):
			planted += 1
	return planted


func _test_a_step_plants_once() -> void:
	var sensor := _sensor()
	_check(_stride(sensor, FootContactSensor.Side.LEFT, true, 1.5) == 1, "one stride did not plant exactly once")
	_check(_stride(sensor, FootContactSensor.Side.LEFT, true, 1.5) == 1, "the second stride did not plant again")
	_dispose(sensor)


## A blended gait can make a real step without ever reaching the old 9 cm
## absolute-clearance threshold. The animated phase must still rearm, even if
## the ground ray is absent during the lifted part of the stride.
func _test_blended_lift_rearms_through_probe_gap() -> void:
	var sensor := _sensor()
	var side: int = FootContactSensor.Side.LEFT

	sensor.observe_foot_motion(side, -1.0)
	_check(
		sensor.update_foot(side, 0.02, Vector3.ZERO, Vector3.FORWARD, true, 1.5),
		"initial blended foot plant was rejected"
	)

	## No update_foot call here: this is the frame range where a terrain seam
	## makes the ground probe miss. Animation sampling still sees a 6 cm lift.
	sensor.observe_foot_motion(side, -0.94)
	sensor.observe_foot_motion(side, -1.0)
	_check(
		sensor.update_foot(side, 0.02, Vector3(0.0, 0.0, -0.7), Vector3.FORWARD, true, 1.5),
		"animation lift during a ground-probe gap did not rearm the next step"
	)
	_dispose(sensor)


## Rearming from animation must still reject small planted-foot noise/shuffle.
func _test_small_foot_jitter_does_not_rearm() -> void:
	var sensor := _sensor()
	var side: int = FootContactSensor.Side.RIGHT

	sensor.observe_foot_motion(side, -1.0)
	_check(
		sensor.update_foot(side, 0.02, Vector3.ZERO, Vector3.FORWARD, true, 1.5),
		"initial jitter test plant was rejected"
	)
	sensor.observe_foot_motion(side, -0.97)
	sensor.observe_foot_motion(side, -1.0)
	_check(
		not sensor.update_foot(side, 0.02, Vector3.ZERO, Vector3.FORWARD, true, 1.5),
		"a 3 cm planted-foot jitter rearmed a duplicate footprint"
	)
	_dispose(sensor)


## Contacts reported by the animation (Motion Matching): one plant per print; a
## contact flickering within the print is the same step, and the print holds
## until the foot has left it.
func _test_driven_contacts_plant_once_per_print() -> void:
	var sensor := _sensor()
	var side: int = FootContactSensor.Side.LEFT
	var at := Vector3(0.0, 0.0, -1.0)
	_check(sensor.update_driven_foot(side, true, at, Vector3.FORWARD, true, 1.5), "a driven contact did not plant")
	_check(not sensor.update_driven_foot(side, true, at, Vector3.FORWARD, true, 1.5), "a held contact planted again")
	sensor.update_driven_foot(side, false, at + Vector3(0.0, 0.0, -0.03), Vector3.FORWARD, true, 1.5)
	_check(sensor.is_planted(side), "a contact gap on the print dropped the print")
	_check(not sensor.update_driven_foot(side, true, at + Vector3(0.0, 0.0, -0.04), Vector3.FORWARD, true, 1.5),
		"a contact flicker on the same print planted a second step")
	sensor.update_driven_foot(side, false, at + Vector3(0.0, 0.0, -0.3), Vector3.FORWARD, true, 1.5)
	_check(not sensor.is_planted(side), "a foot that left its print still holds it")
	_check(sensor.update_driven_foot(side, true, at + Vector3(0.0, 0.0, -0.8), Vector3.FORWARD, true, 1.5),
		"the next print did not plant")
	_check(not sensor.update_driven_foot(FootContactSensor.Side.RIGHT, true, Vector3.ZERO, Vector3.FORWARD, true, 0.1),
		"a driven contact while standing planted a step")
	_dispose(sensor)


## Contact height is measured toward the surface, not along global Y.
func _test_surface_clearance_follows_the_slope_normal() -> void:
	var sensor := _sensor()
	var normal := Vector3(0.0, 1.0, 1.0).normalized()
	var ball := Vector3(0.0, 0.08, 0.0)
	var clearance: float = sensor.surface_clearance(ball, Vector3.ZERO, normal)
	_check(
		clearance < sensor.contact_height_m,
		"slope-normal clearance %.3f did not enter the %.3f m contact band"
		% [clearance, sensor.contact_height_m]
	)
	_dispose(sensor)


func _test_standing_still_leaves_nothing() -> void:
	var sensor := _sensor()
	_check(_stride(sensor, FootContactSensor.Side.RIGHT, true, 0.1) == 0, "shuffling on the spot left a print")
	_dispose(sensor)


func _test_the_air_leaves_nothing() -> void:
	var sensor := _sensor()
	_check(_stride(sensor, FootContactSensor.Side.RIGHT, false, 4.0) == 0, "a foot in the air left a print")
	_dispose(sensor)


## The rule is worthless if the real rig names its bones differently.
func _test_the_rig_has_the_bones() -> void:
	var model := (load("res://assets/animation/ual/Unreal-Godot/UAL1_Standard.glb") as PackedScene).instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = _find_skeleton(model)
	_check(skeleton != null, "Henry's rig has no skeleton")
	if skeleton != null:
		for side: int in FootContactSensor.BONES:
			for bone: StringName in FootContactSensor.BONES[side].values():
				_check(skeleton.find_bone(bone) >= 0, "Henry's rig has no bone '%s'" % bone)
	_dispose(model)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _prints() -> FootprintSystem:
	var system := FootprintSystem.new()
	root.add_child(system)
	return system


## A decal maps the top of its image to its -Z; the image has the toe at the top.
func _test_prints_point_heel_to_toe() -> void:
	var system := _prints()
	var toe := Vector3(1.0, 0.0, 0.0)
	var decal: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3(3.0, 0.0, 4.0), Vector3.UP, toe)
	var minus_z: Vector3 = -decal.global_transform.basis.z.normalized()
	_check(minus_z.dot(toe) > 0.99, "the print's toe points %s, the foot points %s" % [str(minus_z), str(toe)])
	_check(decal.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.99, "the print does not project straight down")
	_check(decal.global_position.distance_to(Vector3(3.0, 0.05, 4.0)) < 0.01, "the print is not where the foot landed")
	_dispose(system)


func _test_each_foot_leaves_its_own_print() -> void:
	var system := _prints()
	var left: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	var right: Decal = system.stamp(FootContactSensor.Side.RIGHT, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	_check(left.texture_albedo == FootprintSystem.LEFT_PRINT, "the left foot left the wrong print")
	_check(right.texture_albedo == FootprintSystem.RIGHT_PRINT, "the right foot left the wrong print")
	_dispose(system)


func _test_the_pool_reuses_the_oldest() -> void:
	var system := _prints()
	system.pool_size = 8
	var first: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	for i: int in range(7):
		system.stamp(FootContactSensor.Side.RIGHT, Vector3(float(i), 0.0, 0.0), Vector3.UP, Vector3.FORWARD)
	var ninth: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3(50.0, 0.0, 0.0), Vector3.UP, Vector3.FORWARD)
	_check(ninth == first, "a full pool did not reuse its oldest print")
	_check(system.get_child_count() == 8, "the pool grew past its size: %d" % system.get_child_count())
	_dispose(system)


func _test_snowfall_buries_the_trail_faster() -> void:
	var calm := _prints()
	var storm := _prints()
	var weather := WeatherController.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	weather.starting_profile_id = &"blizzard"
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()
	storm._weather = weather

	calm.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	storm.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	for i: int in range(60):
		calm._process(1.0)
		storm._process(1.0)
	_check(calm.get_visible_count() == 1, "a calm minute already erased the print")
	_check(storm.get_visible_count() == 0, "a blizzard minute did not bury the print")
	_dispose(weather)
	_dispose(calm)
	_dispose(storm)


## On a slope the print lies on the slope: projected along the ground normal,
## toe along the ground, not hovering flat above it or cutting into it.
func _test_a_print_lies_along_a_slope() -> void:
	var sensor := _sensor()
	var slope_normal := Vector3(0.0, 1.0, 0.5).normalized()
	var got: Array = []
	sensor.foot_planted.connect(func(_s: int, _p: Vector3, n: Vector3, f: Vector3, _v: float) -> void: got.append([n, f]))
	for height: float in [0.2, 0.12, 0.02]:
		sensor.update_foot(FootContactSensor.Side.LEFT, height, Vector3.ZERO, Vector3.FORWARD, true, 1.5, slope_normal)
	_check(got.size() == 1, "a step on a slope planted %d times" % got.size())
	if got.size() == 1:
		_check(got[0][0].is_equal_approx(slope_normal), "the planted normal is not the ground's")
		_check(absf(got[0][1].dot(slope_normal)) < 0.001, "heel to toe does not lie along the slope")
	_dispose(sensor)

	var system := _prints()
	var decal: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, slope_normal, Vector3.FORWARD)
	_check(
		decal.global_transform.basis.y.normalized().dot(slope_normal) > 0.999,
		"the print projects along %s, not the slope's normal" % str(decal.global_transform.basis.y.normalized())
	)
	_dispose(system)
