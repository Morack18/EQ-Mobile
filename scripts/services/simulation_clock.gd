class_name SimulationClock
extends RefCounted

var _elapsed_seconds := 0.0


func now_seconds() -> float:
	return _elapsed_seconds


func advance(delta_seconds: float) -> void:
	assert(delta_seconds >= 0.0, "Simulation clock cannot move backwards")
	_elapsed_seconds += delta_seconds


func set_elapsed_seconds(value: float) -> void:
	_elapsed_seconds = maxf(0.0, value)


func reset() -> void:
	_elapsed_seconds = 0.0


func real_world_unix_ms() -> int:
	# Real-world time is intentionally isolated here. Core simulation cooldowns,
	# combat, lifecycle, and respawn timing use now_seconds() instead.
	return int(Time.get_unix_time_from_system() * 1000.0)