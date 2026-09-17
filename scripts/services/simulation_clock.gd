gdscript
class_name SimulationClock
extends RefCounted

var _elapsed_seconds := 0.0
var _paused := false


func now_seconds() -> float:
	return _elapsed_seconds


func advance(delta_seconds: float) -> void:
	assert(delta_seconds >= 0.0, "Simulation clock cannot move backwards")
	if _paused:
		return
	_elapsed_seconds += delta_seconds


func set_paused(value: bool) -> void:
	_paused = value


func is_paused() -> bool:
	return _paused


func set_elapsed_seconds(value: float) -> void:
	_elapsed_seconds = maxf(0.0, value)


func reset() -> void:
	_elapsed_seconds = 0.0
	_paused = false


func real_world_unix_ms() -> int:
	# Real-world time is intentionally isolated here. Gameplay timing uses
	# now_seconds(); wall-clock time is only for metadata and legacy migration.
	return int(Time.get_unix_time_from_system() * 1000.0)