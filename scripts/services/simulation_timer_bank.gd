gdscript
class_name SimulationTimerBank
extends RefCounted

var _clock: SimulationClock
var _deadlines: Dictionary = {}


func _init(clock_provider: SimulationClock = null) -> void:
	_clock = clock_provider if clock_provider != null else SimulationClock.new()


func start(timer_key: String, duration_seconds: float) -> void:
	assert(not timer_key.is_empty(), "Simulation timer requires a stable key")
	_deadlines[timer_key] = _clock.now_seconds() + maxf(0.0, duration_seconds)


func cancel(timer_key: String) -> bool:
	if not _deadlines.has(timer_key):
		return false
	_deadlines.erase(timer_key)
	return true


func clear() -> void:
	_deadlines.clear()


func has_timer(timer_key: String) -> bool:
	return _deadlines.has(timer_key)


func remaining(timer_key: String) -> float:
	if not _deadlines.has(timer_key):
		return 0.0
	return maxf(
		0.0,
		float(_deadlines[timer_key]) - _clock.now_seconds()
	)


func is_ready(timer_key: String) -> bool:
	return _deadlines.has(timer_key) and remaining(timer_key) <= 0.0


func snapshot_remaining() -> Dictionary:
	var result: Dictionary = {}
	for timer_key in _deadlines:
		result[str(timer_key)] = remaining(str(timer_key))
	return result


func restore_remaining(snapshot_value: Variant) -> void:
	_deadlines.clear()
	if not snapshot_value is Dictionary:
		return

	var snapshot: Dictionary = snapshot_value
	for timer_key in snapshot:
		var key := str(timer_key)
		if key.is_empty():
			continue
		start(key, maxf(0.0, float(snapshot[timer_key])))