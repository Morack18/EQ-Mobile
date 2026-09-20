extends SceneTree

const PlayerStartContractScript = preload("res://scripts/domain/player_start_contract.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	var main := scene.instantiate() as Node3D
	root.add_child(main)
	var mapper := main.get("zone_world_space") as ZoneWorldSpace
	var source := _json("res://data/player_starts_source.json")
	var overlay := _json("res://data/player_starts_overlay.json")
	var resolved := PlayerStartContractScript.resolve({"player_choice": 2, "race_id": 2, "class_id": 1, "deity_id": 396}, source, overlay)
	_expect(not resolved.is_empty(), "Exact player-start identity lookup failed.")
	_expect(PlayerStartContractScript.resolve({"player_choice": 99, "race_id": 2, "class_id": 1, "deity_id": 396}, source, overlay).is_empty(), "Missing player-start combination did not fail cleanly.")
	var baseline: Dictionary = resolved.get("baseline", {})
	_expect(float(baseline.get("x", 0.0)) == -456.0 and float(baseline.get("y", 0.0)) == 560.0 and float(baseline.get("z", 0.0)) == -26.62, "PEQ baseline row was not preserved.")
	_expect(float(resolved.get("x", 0.0)) == 54.0 and float(resolved.get("y", 0.0)) == 139.0, "Reviewed P99 horizontal correction is wrong.")
	_expect(resolved.get("initial_bind", {}) == {"zone_id": 29, "source_position_eq": resolved.get("source_position_eq"), "source_heading_eq": resolved.get("source_heading_eq")}, "Initial bind does not equal character start.")
	var horizontal := mapper.server_position([54.0, 139.0, 0.0])
	var query := PhysicsRayQueryParameters3D.create(horizontal + Vector3.UP * 200.0, horizontal + Vector3.DOWN * 200.0)
	query.collision_mask = EqWorldSpace.WORLD_COLLISION_MASK
	var hit := main.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): _expect(false, "No Halas floor at reviewed player start horizontal")
	else:
		_expect(is_equal_approx(float(resolved.get("z", 0.0)), float(hit.position.y)), "Reviewed elevation differs from imported Halas geometry.")
		_expect(mapper.server_position(resolved.get("source_position_eq", []) as Array).is_equal_approx(hit.position), "Resolved start world position does not match ZoneWorldSpace.")
	var safe: Dictionary = (main.get("zone") as Dictionary).get("safe_point", {})
	_expect(mapper.server_position(safe.get("position_eq", []) as Array).is_equal_approx(Vector3(0.0, 3.0, 0.0)), "Zone safe source did not map to Vector3(0,3,0).")
	_expect(not mapper.server_position(resolved.get("source_position_eq", []) as Array).is_equal_approx(mapper.server_position(safe.get("position_eq", []) as Array)), "Character start equals zone safe point.")
	var synthetic := ZoneWorldSpace.new({"world_space_contract": {"server_axis_map": [1, 3, 2], "server_heading_units_per_turn": 512.0}, "object_instances": "", "object_model_directory": ""})
	_expect(synthetic.is_valid() and synthetic.server_position([1.0, 2.0, 3.0]).is_equal_approx(Vector3(1, 3, 2)), "Synthetic non-Halas world-space transform failed.")
	var restored := EntityFactory.create({"entity_id": "test:player", "definition_id": "test:player", "kind": "player", "spawn_position": Vector3(1, 2, 3)})
	restored.restore_runtime({"position": [9.0, 8.0, 7.0]}, 0.0, true)
	_expect(restored.position.is_equal_approx(Vector3(9, 8, 7)), "Valid restored runtime player position was not preserved.")
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	_expect(not main_source.contains("player_entity.spawn_position = ("), "Zone transition mutates the persistent player bind.")
	if not hit.is_empty(): print("PLAYER_START_FLOOR_WORLD=", hit.position)
	if not hit.is_empty(): print("PLAYER_START_FLOOR_SOURCE_Z=", float(hit.position.y))
	main.free()
	if failures.is_empty(): print("PASS: Player start, bind, and zone-safe contracts hold.")
	else: for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
