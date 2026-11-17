extends SceneTree

## Sleep and waiting burn a lit flare (owner's local test: a flare still burned after hours of sleep).
## Skipped hours burn it at its 30-minute rating; realtime steps leave it to its own frame clock.
## Run: godot --headless --script tests/systems/test_flare_sleep_burn.gd

const FLARE_SCENE: String = "res://scenes/actors/player/held/HeldFlare.tscn"
## The flare's rating in Henry's world: 75 real seconds are 30 game minutes.
const RATED_HOURS: float = 0.5

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.set_total_hours(8.0)
	var flare := (load(FLARE_SCENE) as PackedScene).instantiate() as HeldFlare
	flare.set_process(false)  # only the clock burns it here
	root.add_child(flare)
	await process_frame
	flare.set_process(false)
	_check(flare.is_burning(), "the flare did not light")
	var full: float = flare.get_remaining_seconds()
	clock.advance_hours(1.0, SimulationClock.REALTIME_REASON)
	_check(is_equal_approx(flare.get_remaining_seconds(), full), "a realtime step burned the flare twice")
	clock.advance_hours(0.1, &"wait")
	var expected: float = full - 0.1 / RATED_HOURS * flare.burn_duration_s
	_check(absf(flare.get_remaining_seconds() - expected) < 0.01,
		"six minutes of waiting left %.2f s of burn, not %.2f s" % [flare.get_remaining_seconds(), expected])
	_check(flare.is_burning(), "six minutes of waiting put out a 30-minute flare")
	clock.advance_hours(3.0, &"sleep")
	_check(not flare.is_burning() and flare.is_spent(), "the flare still burned after three hours of sleep")
	print("flare sleep burn: %.1f s left after a 6-minute wait, spent after sleep: %s" % [expected, flare.is_spent()])
	if _failures > 0:
		push_error("flare sleep burn: %d check(s) failed" % _failures)
		quit(1)
		return
	print("flare sleep burn: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("flare sleep burn: " + message)
