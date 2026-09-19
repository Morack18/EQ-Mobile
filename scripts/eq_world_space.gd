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
	var used_components := {}
	var mapped: Array[float] = []
	for component_variant in axis_map:
		var component := int(component_variant)
		assert(component != 0 and abs(component) <= 3, "Axis map component out of range")
		assert(not used_components.has(abs(component)), "Axis map must be a signed permutation of 1, 2, 3")
		used_components[abs(component)] = true
		var value := float(source[abs(component) - 1])
		mapped.append(-value if component < 0 else value)
	assert(used_components.size() == 3, "Axis map must contain each source component exactly once")
	return Vector3(mapped[0], mapped[1], mapped[2])

static func position_within_precision(actual: Vector3, expected: Vector3, precision: float = DEFAULT_POSITION_PRECISION) -> bool:
	return actual.distance_to(expected) <= precision

static func halas_lantern_prop_yaw(degrees_eq: float) -> float:
	return deg_to_rad(-degrees_eq)

static func server_heading_source_vector(
	heading_eq: float,
	units_per_turn: float = EQ_HEADING_UNITS_PER_TURN
) -> Vector3:
	assert(
		units_per_turn > 0.0,
		"Heading units per turn must be positive"
	)
	assert(heading_eq >= 0.0, "Server heading must be nonnegative")
	var turn := fposmod(heading_eq, units_per_turn) / units_per_turn * TAU
	return Vector3(
		sin(turn),
		cos(turn),
		0.0
	)


static func horizontal_direction_to_yaw(direction: Vector3) -> float:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	assert(
		horizontal.length_squared() > 0.000001,
		"Heading direction must have a horizontal component"
	)
	horizontal = horizontal.normalized()
	return atan2(-horizontal.x, -horizontal.z)

static func visual_scale_for_height(measured_height: float, target_height: float) -> float:
	assert(measured_height > 0.0 and target_height > 0.0, "Character heights must be positive")
	return target_height / measured_height

static func run_contract_tests() -> void:
	assert(position_within_precision(halas_server_position([0.0, 0.0, 0.0]), Vector3.ZERO))
	assert(position_within_precision(halas_server_position([10.0, 20.0, 30.0]), Vector3(-20.0, 30.0, 10.0)))
	assert(position_within_precision(map_position([10.0, 20.0, 30.0], [-1, 2, 3]), Vector3(-10.0, 20.0, 30.0)))
	assert(server_heading_source_vector(0.0).is_equal_approx(Vector3(0.0, 1.0, 0.0)))
	assert(server_heading_source_vector(128.0).is_equal_approx(Vector3(1.0, 0.0, 0.0)))
