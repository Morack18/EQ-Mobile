extends SceneTree

const EPSILON := 0.001
const REPORT_PATH := "/tmp/eqm-halas-npc-position-fidelity.json"

var _main: Node3D
var _population: ZoneNpcPopulation
var _zone_world_space: ZoneWorldSpace
var _zone_key := ""
var _terrain_snap_tolerance := 0.0
var _terrain_cast_height := 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		_fail("Unable to load res://scenes/Main.tscn")
		return
	_main = main_scene.instantiate() as Node3D
	if _main == null:
		_fail("Unable to instantiate Main scene")
		return
	root.add_child(_main)
	# Adding Main to the active root runs its ready chain synchronously. Do not
	# yield here: the first physics tick performs terrain validation.
	_population = _main.get("zone_npc_population") as ZoneNpcPopulation
	_zone_world_space = _main.get("zone_world_space") as ZoneWorldSpace
	_zone_key = str(_main.get("current_zone_key"))
	if _population == null or _zone_world_space == null or _zone_key.is_empty():
		_fail("Main did not expose active NPC population, world space, and zone key")
		return
	_population.set_process(false)
	if _population._terrain_validated:
		_fail("Terrain validation ran before clean source state could be reconstructed")
		return
	var zone: Dictionary = _main.get("zone") as Dictionary
	var presentation: Dictionary = zone.get("npc_presentation", {}) as Dictionary
	_terrain_snap_tolerance = float(presentation.get("terrain_snap_tolerance", 0.0))
	_terrain_cast_height = float(presentation.get("terrain_cast_height", 0.0))
	if _terrain_snap_tolerance <= 0.0 or _terrain_cast_height <= 0.0:
		_fail("Active zone NPC terrain policy is not usable")
		return
	var content: Dictionary = _population._content
	if not _restore_clean_source_state(content):
		return
	await physics_frame
	# physics_frame is emitted before node _physics_process callbacks; resume on
	# the following idle frame to inspect the completed production validation.
	await process_frame
	if not _population._terrain_validated:
		_fail("Production ZoneNpcPopulation terrain validation did not execute")
		return
	var report := _measure(content)
	if report.is_empty():
		return
	_write_report(report)
	_print_report(report)
	if not _assert_expected(report):
		return
	quit(0)


func _restore_clean_source_state(content: Dictionary) -> bool:
	var spawns_by_id := _spawns_by_id(content)
	var grids: Dictionary = content.get("grids", {}) as Dictionary
	for actor in _population._actors:
		if not is_instance_valid(actor.node) or not actor.node.visible:
			continue
		var spawn: Dictionary = spawns_by_id.get(actor.spawn2_id, {}) as Dictionary
		if spawn.is_empty():
			_fail("Visible actor has no source spawn: %d" % actor.spawn2_id)
			return false
		var position_eq: Array = spawn.get("position_eq", []) as Array
		if position_eq.size() != 3:
			_fail("Source spawn has invalid position_eq: %d" % actor.spawn2_id)
			return false
		actor.node.global_position = _zone_world_space.server_position(position_eq)
		actor.grid_id = int(spawn.get("grid_id", 0))
		actor.patrol.clear()
		actor.patrol_targets.clear()
		var grid: Array = grids.get(str(actor.grid_id), []) as Array
		for point_variant in grid:
			if not point_variant is Dictionary:
				_fail("Source grid %d has a non-dictionary patrol point" % actor.grid_id)
				return false
			var point := point_variant as Dictionary
			var point_eq: Array = point.get("position_eq", []) as Array
			if point_eq.size() != 3:
				_fail("Source patrol point has invalid position_eq for spawn2 %d" % actor.spawn2_id)
				return false
			actor.patrol.append(point)
			actor.patrol_targets.append(_zone_world_space.server_position(point_eq))
		actor.patrol_index = 0
		actor.pause_remaining = 0.0
		actor.movement_velocity = Vector3.ZERO
	return true


func _measure(content: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	var spawns_by_id := _spawns_by_id(content)
	var space_state := _main.get_world_3d().direct_space_state
	for actor in _population._actors:
		if not is_instance_valid(actor.node) or not actor.node.visible:
			continue
		var spawn: Dictionary = spawns_by_id.get(actor.spawn2_id, {}) as Dictionary
		if spawn.is_empty():
			_fail("Visible actor lost its source spawn: %d" % actor.spawn2_id)
			return {}
		var spawn_eq: Array = spawn.get("position_eq", []) as Array
		var spawn_world := _zone_world_space.server_position(spawn_eq)
		rows.append(_measure_point(space_state, "spawn", actor.spawn2_id, int(spawn.get("grid_id", 0)), 0, spawn_eq, spawn_world, actor.node.global_position))
		for index in actor.patrol.size():
			var point: Dictionary = actor.patrol[index] as Dictionary
			var point_eq: Array = point.get("position_eq", []) as Array
			rows.append(_measure_point(space_state, "patrol", actor.spawn2_id, actor.grid_id, int(point.get("number", index + 1)), point_eq, _zone_world_space.server_position(point_eq), actor.patrol_targets[index]))
	return {
		"schema_id": "eqm.classic_p1999_npc_position_fidelity", "schema_version": 2,
		"zone_key": _zone_key, "terrain_snap_tolerance": _terrain_snap_tolerance,
		"terrain_cast_height": _terrain_cast_height, "summary": _summarize(rows), "rows": rows,
	}


func _measure_point(space_state: PhysicsDirectSpaceState3D, kind: String, spawn2_id: int, grid_id: int, point_number: int, source_eq: Array, source_world: Vector3, runtime_world: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(source_world + Vector3.UP * _terrain_cast_height, source_world - Vector3.UP * _terrain_cast_height, EqWorldSpace.COLLISION_LAYER_TERRAIN)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space_state.intersect_ray(query)
	var terrain_hit := not hit.is_empty()
	var terrain_y: Variant = null
	var terrain_delta_y: Variant = null
	var within_current_tolerance := false
	if terrain_hit:
		terrain_y = (hit.position as Vector3).y
		terrain_delta_y = float(terrain_y) - source_world.y
		within_current_tolerance = absf(float(terrain_delta_y)) <= _terrain_snap_tolerance
	var runtime_delta_y := runtime_world.y - source_world.y
	return {
		"kind": kind, "spawn2_id": spawn2_id, "grid_id": grid_id, "point_number": point_number,
		"source_eq": source_eq.duplicate(), "source_world": _vector_array(source_world), "runtime_world": _vector_array(runtime_world),
		"terrain_hit": terrain_hit, "terrain_y": terrain_y, "terrain_delta_y": terrain_delta_y,
		"within_current_tolerance": within_current_tolerance, "runtime_delta_y": runtime_delta_y,
		"runtime_changed_source_y": absf(runtime_delta_y) > EPSILON,
		"runtime_matches_source": absf(runtime_world.y - source_world.y) <= EPSILON,
	}


func _summarize(rows: Array[Dictionary]) -> Dictionary:
	var summary := {"total": rows.size(), "spawns": 0, "patrol": 0, "terrain_hits": 0, "within_tolerance": 0, "retained": 0, "runtime_changed": 0, "runtime_exact_source": 0, "source_mismatches": 0, "max_abs_terrain_delta": 0.0}
	for row in rows:
		var count_key := "spawns" if row.kind == "spawn" else "patrol"
		summary[count_key] = int(summary[count_key]) + 1
		if bool(row.terrain_hit):
			summary.terrain_hits = int(summary.terrain_hits) + 1
			summary.max_abs_terrain_delta = maxf(float(summary.max_abs_terrain_delta), absf(float(row.terrain_delta_y)))
		if bool(row.within_current_tolerance):
			summary.within_tolerance = int(summary.within_tolerance) + 1
		else:
			summary.retained = int(summary.retained) + 1
		if bool(row.runtime_changed_source_y):
			summary.runtime_changed = int(summary.runtime_changed) + 1
		else:
			summary.runtime_exact_source = int(summary.runtime_exact_source) + 1
		if not bool(row.runtime_matches_source):
			summary.source_mismatches = int(summary.source_mismatches) + 1
	return summary


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("Unable to write %s" % REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()


func _print_report(report: Dictionary) -> void:
	var summary: Dictionary = report.summary as Dictionary
	print("NPC position fidelity summary: ", JSON.stringify(summary))
	print("terrain_snap_tolerance=%.6f terrain_cast_height=%.6f" % [_terrain_snap_tolerance, _terrain_cast_height])
	var ranked: Array = (report.rows as Array).duplicate()
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return _absolute_terrain_delta(left) > _absolute_terrain_delta(right))
	print("Top 30 absolute terrain/source Y deltas:")
	for row in ranked.slice(0, mini(30, ranked.size())):
		_print_row(row as Dictionary)
	print("Retained source-elevation rows:")
	for row in report.rows:
		if not bool(row.within_current_tolerance):
			_print_row(row as Dictionary)


func _print_row(row: Dictionary) -> void:
	print("kind=%s spawn2_id=%d grid_id=%d point_number=%d source_y=%.6f terrain_y=%s terrain_delta_y=%s runtime_y=%.6f runtime_changed_source_y=%s source_eq=%s source_world=%s runtime_world=%s" % [str(row.kind), int(row.spawn2_id), int(row.grid_id), int(row.point_number), float((row.source_world as Array)[1]), str(row.terrain_y), str(row.terrain_delta_y), float((row.runtime_world as Array)[1]), str(row.runtime_changed_source_y), JSON.stringify(row.source_eq), JSON.stringify(row.source_world), JSON.stringify(row.runtime_world)])


func _absolute_terrain_delta(row: Dictionary) -> float:
	if not bool(row.terrain_hit):
		return -1.0
	return absf(float(row.terrain_delta_y))


func _assert_expected(report: Dictionary) -> bool:
	var summary: Dictionary = report.summary as Dictionary
	var expected := {"total": 245, "spawns": 67, "patrol": 178, "terrain_hits": 242, "runtime_changed": 0, "runtime_exact_source": 245, "source_mismatches": 0}
	for key in expected:
		if int(summary.get(key, -1)) != int(expected[key]):
			_fail("Expected %s=%d, got %d" % [key, int(expected[key]), int(summary.get(key, -1))])
			return false
	var boat_points := 0
	for row_variant in report.rows:
		var row := row_variant as Dictionary
		if int(row.spawn2_id) != 10047 or int(row.grid_id) != 17:
			continue
		boat_points += 1
		if bool(row.terrain_hit) or not bool(row.runtime_matches_source):
			_fail("Spawn2 10047/grid 17 source-coordinate regression failed")
			return false
	if boat_points != 3:
		_fail("Expected 3 Spawn2 10047/grid 17 source-coordinate rows, got %d" % boat_points)
		return false
	return true


func _spawns_by_id(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for spawn_variant in content.get("spawns", []):
		if spawn_variant is Dictionary:
			var spawn := spawn_variant as Dictionary
			result[int(spawn.get("spawn2_id", 0))] = spawn
	return result


func _vector_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _fail(message: String) -> void:
	push_error("NPC position fidelity probe failed: " + message)
	quit(1)
