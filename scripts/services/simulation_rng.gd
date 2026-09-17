class_name SimulationRng
extends RefCounted

var _rng := RandomNumberGenerator.new()
var _initial_seed := 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_initial_seed = seed_value
	_rng.seed = seed_value


func initial_seed() -> int:
	return _initial_seed


func state() -> int:
	return _rng.state


func restore(seed_value: int, state_value: int) -> void:
	_initial_seed = seed_value
	_rng.seed = seed_value
	if state_value != 0:
		_rng.state = state_value


func snapshot() -> Dictionary:
	return {
		"seed": _initial_seed,
		"state": _rng.state,
	}


func randi_range(minimum: int, maximum: int) -> int:
	assert(maximum >= minimum, "RNG range maximum must be >= minimum")
	return _rng.randi_range(minimum, maximum)


func randf_range(minimum: float, maximum: float) -> float:
	assert(maximum >= minimum, "RNG range maximum must be >= minimum")
	return _rng.randf_range(minimum, maximum)


func chance(probability: float) -> bool:
	return _rng.randf() < clampf(probability, 0.0, 1.0)