extends SceneTree

## The vital HUD reacts to movement and changes colour/morph only at thresholds.
## Run: godot --headless --script tests/systems/test_vital_cluster.gd

var _failures: int = 0
var _frame: int = 0
var _elapsed: float = 0.0
var _settled: bool = false
var _max_push: float = 0.0
var _max_grow: float = 0.0
var _cluster: VitalCluster
var _strip: HealthStrip


## Tweens run on real time, so the settle check waits on seconds, not frames.
func _process(delta: float) -> bool:
	_frame += 1
	if _frame > 1:
		_max_push = maxf(_max_push, _cluster.get_cell(&"hunger").push)
		_max_grow = maxf(_max_grow, _cluster.get_cell(&"thirst").grow)
	if _frame > 8:
		_elapsed += delta
	if _elapsed > 1.5 and not _settled:
		_settled = true
		_check(_max_push > 3.0, "a drain did not push the food cell out (peak %.2f)" % _max_push)
		_check(_max_grow > 0.1, "a refill did not grow the water cell (peak %.3f)" % _max_grow)
		_check(_cluster.get_cell(&"hunger").push < 0.05, "the food cell did not settle back")
		_check(absf(_strip.trail - 0.6) < 0.02, "the trail did not catch up (%.2f)" % _strip.trail)
		_finish()
	match _frame:
		1:
			_cluster = VitalCluster.new()
			_cluster.size = Vector2(180.0, 180.0)
			root.add_child(_cluster)
			_strip = HealthStrip.new()
			_strip.size = Vector2(540.0, 12.0)
			root.add_child(_strip)
			_cluster.set_vital(&"hunger", 0.8)
			_cluster.set_vital(&"hunger", 0.6)
			_cluster.set_vital(&"thirst", 0.4)
			_cluster.set_vital(&"thirst", 0.9)
			_cluster.set_vital(&"sleep", 0.09)
			_strip.set_health(100.0, 100.0, false)
			_strip.set_health(60.0, 100.0)
		8:
			var hunger: VitalCell = _cluster.get_cell(&"hunger")
			var thirst: VitalCell = _cluster.get_cell(&"thirst")
			var sleep: VitalCell = _cluster.get_cell(&"sleep")
			_check(hunger.pulse == VitalCell.Pulse.DRAIN, "a drain was not recognised")
			_check(thirst.pulse == VitalCell.Pulse.REFILL, "a refill was not recognised")
			_check(sleep.critical, "below 10% sleep is not critical")
			_check(sleep.target_morph_frame() == VitalCell.MORPH_CRITICAL_FRAME, "critical morph does not target its final frame")
			_check(not thirst.critical, "90% water reads as critical")
			_check(VitalCell.severity_for_level(0.50) == VitalCell.Severity.NORMAL, "50% must remain neutral")
			_check(VitalCell.severity_for_level(0.499) == VitalCell.Severity.WARNING, "below 50% must be warning")
			_check(VitalCell.severity_for_level(0.10) == VitalCell.Severity.WARNING, "10% must remain warning")
			_check(VitalCell.severity_for_level(0.099) == VitalCell.Severity.CRITICAL, "below 10% must be critical")
			_check(VitalCluster.TREND_IDS.size() == 4, "all four vitals must expose trend markers")
			_check(VitalCluster.TREND_IDS.has(&"thirst") and VitalCluster.TREND_IDS.has(&"hunger") and VitalCluster.TREND_IDS.has(&"sleep") and VitalCluster.TREND_IDS.has(&"warmth"), "trend markers are not wired to every vital")
			_check(_cluster.state_color_for(&"hunger", 1.0).is_equal_approx(_cluster.normal_color), "a full column must be green")
			_check(_cluster.state_color_for(&"hunger", 0.5).is_equal_approx(_cluster.warning_color), "a half column must be yellow")
			_check(_cluster.state_color_for(&"hunger", 0.2).is_equal_approx(_cluster.critical_color), "below 33% must be red")
			var mid: Color = _cluster.state_color_for(&"hunger", 0.66)
			_check(not mid.is_equal_approx(_cluster.normal_color) and not mid.is_equal_approx(_cluster.warning_color), "colours must blend at a threshold, not switch")
			_check(_cluster.vividness_for(&"thirst", 0.95) < 0.05 and _cluster.vividness_for(&"thirst", 0.2) > 0.95, "symbols must be half-tone when safe and vivid when critical")
			## Without a ThermalManager warmth falls back to the stage thresholds (36 °C and 33 °C on 28..36.6).
			var warm: Vector2 = _cluster.thresholds_for(&"warmth")
			_check(absf(warm.x - 0.93) < 0.01 and absf(warm.y - 0.58) < 0.01, "warmth thresholds are not the hypothermia stages: %s" % warm)
			_check(_cluster.state_color_for(&"warmth", 0.35).is_equal_approx(_cluster.critical_color), "31 °C (critical stage) still reads yellow")
			_check(_cluster.get_trend_strength(&"hunger") == 0 or _cluster.get_trend(&"hunger") != 0, "a trend strength without a trend")
			_check(is_equal_approx(_strip.ratio, 0.6) and _strip.trail > 0.61, "damage left no trail (ratio %.2f trail %.2f)" % [_strip.ratio, _strip.trail])
	return false


func _finish() -> void:
	if _failures > 0:
		push_error("vital cluster: %d check(s) failed" % _failures)
		quit(1)
		return
	print("vital cluster: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("vital cluster: %s" % message)
