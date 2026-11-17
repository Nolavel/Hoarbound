extends SceneTree

## Breath vapor: none in warm air, a puff on every exhale in the cold, quicker and faster
## puffs while panting, and a panting rhythm that settles slowly instead of snapping.
## Run: godot --headless --script tests/systems/test_breath_vapor.gd

const SCENE: String = "res://scenes/actors/player/breath_vapor.tscn"
const DT: float = 1.0 / 60.0

var _failures: int = 0


func _process(_delta: float) -> bool:
	_test_scene_is_authored()
	_test_warm_air_shows_nothing()
	_test_density_follows_air()
	_test_panting_breathes_faster_and_harder()
	_test_panting_settles_slowly()
	if _failures > 0:
		push_error("breath vapor: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("breath vapor: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("breath vapor: " + message)


func _breath() -> BreathVapor:
	var breath := (load(SCENE) as PackedScene).instantiate() as BreathVapor
	root.add_child(breath)
	breath.set_process(false)
	return breath


## Runs the breath and returns [puffs started, mean exhale speed].
func _run(breath: BreathVapor, seconds: float, air_c: float, effort: float) -> Array:
	var puffs: int = 0
	var speed: float = 0.0
	var was: bool = breath.is_puffing()
	var material := (breath.get_node(^"Puff") as GPUParticles3D).process_material as ParticleProcessMaterial
	for _i: int in range(int(round(seconds / DT))):
		breath.step(DT, air_c, effort)
		var now: bool = breath.is_puffing()
		if now and not was:
			puffs += 1
			speed += material.initial_velocity_max
		was = now
	return [puffs, speed / maxf(puffs, 1)]


func _test_scene_is_authored() -> void:
	var breath := _breath()
	var puff := breath.get_node_or_null(^"Puff") as GPUParticles3D
	_check(puff != null and puff.process_material != null and puff.draw_pass_1 != null, "the puff is not authored in the scene")
	_check(puff != null and not puff.local_coords, "puffs must stay where they were breathed, not follow the head")
	breath.queue_free()


func _test_warm_air_shows_nothing() -> void:
	var breath := _breath()
	var result: Array = _run(breath, 12.0, 12.0, 1.0)
	_check(result[0] == 0, "breath showed in +12 °C air (%d puffs)" % result[0])
	breath.queue_free()


func _test_density_follows_air() -> void:
	var breath := _breath()
	breath.step(DT, 5.0, 0.0)
	var mild: float = breath.get_density()
	breath.step(DT, -25.0, 0.0)
	var deep: float = breath.get_density()
	_check(mild > 0.0 and mild < 0.3, "+5 °C should show a faint breath, density %.2f" % mild)
	_check(is_equal_approx(deep, 1.0), "-25 °C should show the full breath, density %.2f" % deep)
	breath.queue_free()


func _test_panting_breathes_faster_and_harder() -> void:
	var rest := _breath()
	var calm: Array = _run(rest, 30.0, -20.0, 0.0)
	var run := _breath()
	_run(run, 3.0, -20.0, 1.0)
	var hard: Array = _run(run, 30.0, -20.0, 1.0)
	_check(calm[0] >= 6 and calm[0] <= 8, "resting breath should be about 14 a minute, got %d in 30 s" % calm[0])
	_check(hard[0] >= 20, "panting should be over 40 a minute, got %d in 30 s" % hard[0])
	_check(hard[1] > calm[1] * 2.0, "panting puffs should leave the mouth faster (%.2f vs %.2f m/s)" % [hard[1], calm[1]])
	rest.queue_free()
	run.queue_free()


func _test_panting_settles_slowly() -> void:
	var breath := _breath()
	_run(breath, 10.0, -20.0, 1.0)
	_run(breath, 2.0, -20.0, 0.0)
	var after_two: float = breath.get_exertion()
	_run(breath, 20.0, -20.0, 0.0)
	_check(after_two > 0.55, "panting stopped at once after the run (exertion %.2f after 2 s)" % after_two)
	_check(breath.get_exertion() < 0.05, "breath never settled after 22 s (exertion %.2f)" % breath.get_exertion())
	breath.queue_free()
