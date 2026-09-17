class_name EqWorldSpace
extends RefCounted

## Phase 1 spatial contract. One Godot world unit equals one native EQ world
## unit after an asset's declared import compensation has been applied.

const EQ_HEADING_UNITS_PER_TURN := 512.0
const EQ_GRAVITY := 120.0
const EQ_MAX_FALL_SPEED := 128.0
const EQ_JUMP_VELOCITY := 31.0
const EQ_MANUAL_RUN_SPEED := 35.0
const EQ_COLLISION_RADIUS := 1.0
const DEFAULT_POSITION_PRECISION := 0.001
const COLLISION_LAYER_TERRAIN := 1
const COLLISION_LAYER_WORLD_OBJECTS := 2
const COLLISION_LAYER_TARGET_PICK := 4
const WORLD_COLLISION_MASK := COLLISION_LAYER_TERRAIN | COLLISION_LAYER_WORLD_OBJECTS

static func halas_server_position(position_eq: Array) -> Vector3:
	# PEQ/EQEmu server coordinates are [x, y, elevation]. Halas calibration
	# against authored terrain selected (-y, elevation, x).
	assert(position_eq.size() == 3, "Server position must be [x, y, elevation]")
	return map_position(position_eq, [-2, 3, 1])

static func halas_lantern_prop_position(x: float, y: float, z: float) -> Vector3:
	# Lantern's Halas object manifest is a separate coordinate source from PEQ
	# server positions; its exported zone root mirrors X.
	return map_position([x, y, z], [-1, 2, 3])

static func map_position(source: Array, axis_map: Array) -> Vector3:
	# axis_map is signed one-based source components, e.g. [-2, 3, 1] means
	# world X=-source[1], Y=source[2], Z=source[0]. Zone calibration supplies
	# data; it never needs to reimplement coordinate arithmetic.
	assert(source.size() == 3 and axis_map.size() == 3, "Position maps require three components")
	var mapped: Array[float] = []
	for component_variant in axis_map:
		var component := int(component_variant)
		assert(component != 0 and abs(component) <= 3, "Axis map component out of range")
		var value := float(source[abs(component) - 1])
		mapped.append(-value if component < 0 else value)
	return Vector3(mapped[0], mapped[1], mapped[2])

static func halas_lantern_prop_yaw(degrees_eq: float) -> float:
	return deg_to_rad(-degrees_eq)

static func heading_to_godot_yaw(heading_eq: float) -> float:
	assert(heading_eq >= 0.0 and heading_eq <= EQ_HEADING_UNITS_PER_TURN, "EQ heading out of range")
	return PI * 0.5 - (heading_eq / EQ_HEADING_UNITS_PER_TURN) * TAU

static func heading_forward(heading_eq: float) -> Vector3:
	var turn := (heading_eq / EQ_HEADING_UNITS_PER_TURN) * TAU
	return Vector3(-cos(turn), 0.0, -sin(turn))

static func visual_scale_for_height(measured_height: float, target_height: float) -> float:
	assert(measured_height > 0.0 and target_height > 0.0, "Character heights must be positive")
	return target_height / measured_height

static func run_contract_tests() -> void:
	assert(halas_server_position([0.0, 0.0, 0.0]).is_equal_approx(Vector3.ZERO))
	assert(halas_server_position([10.0, 20.0, 30.0]).is_equal_approx(Vector3(-20.0, 30.0, 10.0)))
	assert(map_position([10.0, 20.0, 30.0], [-1, 2, 3]).is_equal_approx(Vector3(-10.0, 20.0, 30.0)))
	assert(is_equal_approx(heading_to_godot_yaw(0.0), PI * 0.5))
	assert(is_equal_approx(heading_to_godot_yaw(256.0), -PI * 0.5))
	assert(heading_forward(0.0).is_equal_approx(Vector3(-1.0, 0.0, 0.0)))
	assert(heading_forward(128.0).is_equal_approx(Vector3(0.0, 0.0, -1.0)))
