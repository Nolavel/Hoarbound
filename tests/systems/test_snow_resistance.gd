extends SceneTree

## SnowResistance: powder compacts, crust holds or breaks under a step, drift pockets plunge
## a leg, all deterministic by place. Run headless with --script.

const MAX_PACK: float = 0.85

var _failures: int = 0


func _process(_delta: float) -> bool:
	_test_powder_compacts_without_breaking()
	_test_crust_holds_a_walk_somewhere_and_breaks_somewhere()
	_test_running_breaks_more_crust_than_standing()
	_test_drift_pockets_plunge_deep()
	_test_same_place_same_snow()
	_test_sink_reaches_the_plunge_after_the_break()
	if _failures > 0:
		push_error("snow resistance: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("snow resistance: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow resistance: %s" % message)


func _test_powder_compacts_without_breaking() -> void:
	var p: SnowResistance.Plant = SnowResistance.plant(Vector2(3.0, 4.0), 0.2, 1.0, 0.0, 0.5, MAX_PACK)
	_check(not p.broke(), "loose powder has no crust to break")
	_check(is_equal_approx(p.support, 0.2 * MAX_PACK), "powder compacts by its whole give")


func _test_crust_holds_a_walk_somewhere_and_breaks_somewhere() -> void:
	var held: int = 0
	var broke: int = 0
	for i: int in range(400):
		var at := Vector2(float(i % 20) * 0.9, float(i / 20) * 0.9)
		var p: SnowResistance.Plant = SnowResistance.plant(at, 0.25, 0.2, 0.0, 0.4, MAX_PACK)
		if p.broke():
			broke += 1
			_check(p.plunge > p.support * 2.0, "a break plunges well below the crust")
		else:
			held += 1
			_check(p.support < 0.25 * MAX_PACK * 0.5, "held crust keeps the boot near the top")
	_check(held > 40 and broke > 40, "the same crust both holds and breaks across a street (%d held, %d broke)" % [held, broke])


func _test_running_breaks_more_crust_than_standing() -> void:
	var standing: int = 0
	var running: int = 0
	for i: int in range(400):
		var at := Vector2(float(i % 20) * 0.9 + 100.0, float(i / 20) * 0.9)
		if SnowResistance.plant(at, 0.25, 0.2, 0.0, 0.0, MAX_PACK, 0.6).broke():
			standing += 1
		if SnowResistance.plant(at, 0.25, 0.2, 0.0, 1.0, MAX_PACK).broke():
			running += 1
	_check(running > standing, "a running stride breaks more crust than standing (%d vs %d)" % [running, standing])


func _test_drift_pockets_plunge_deep() -> void:
	var deep: int = 0
	for i: int in range(400):
		var at := Vector2(float(i % 20) * 0.7, float(i / 20) * 0.7 + 50.0)
		var flat: SnowResistance.Plant = SnowResistance.plant(at, 0.6, 1.0, 0.0, 0.3, MAX_PACK)
		var drift: SnowResistance.Plant = SnowResistance.plant(at, 0.6, 1.0, 0.35, 0.3, MAX_PACK)
		_check(not flat.broke(), "no pocket under level powder")
		if drift.broke():
			deep += 1
			_check(drift.plunge > 0.6 * MAX_PACK - 0.0001 and drift.plunge <= 0.6 * 0.95 + 0.0001, "a pocket plunges almost to the ground, never through it")
	_check(deep > 10 and deep < 300, "pockets are hidden here and there in a drift (%d of 400)" % deep)


func _test_same_place_same_snow() -> void:
	var a: SnowResistance.Plant = SnowResistance.plant(Vector2(-2751.3, 1850.3), 0.3, 0.3, 0.1, 0.5, MAX_PACK)
	var b: SnowResistance.Plant = SnowResistance.plant(Vector2(-2751.3, 1850.3), 0.3, 0.3, 0.1, 0.5, MAX_PACK)
	_check(a.support == b.support and a.plunge == b.plunge and a.break_s == b.break_s, "the snowpack is a property of the place")


func _test_sink_reaches_the_plunge_after_the_break() -> void:
	var p := SnowResistance.Plant.new()
	p.support = 0.03
	p.plunge = 0.2
	p.break_s = 0.15
	var before: float = SnowResistance.sink_at(p, 0.14, 0.2, 0.0)
	var after: float = SnowResistance.sink_at(p, 0.6, 0.2, 0.0)
	_check(before <= p.support + 0.0001, "the boot rests on the crust until it breaks")
	_check(absf(after - p.plunge) < 0.01, "then it drops to the plunge (got %.3f)" % after)
