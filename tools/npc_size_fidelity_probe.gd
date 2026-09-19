extends SceneTree

const REPORT_PATH := "/tmp/eqm-halas-npc-size-fidelity.json"
const EPSILON := 0.001


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		_fail("Unable to load Main scene")
		return
	var main := main_scene.instantiate() as Node3D
	if main == null:
		_fail("Unable to instantiate Main scene")
		return
	root.add_child(main)
	var population := main.get("zone_npc_population") as ZoneNpcPopulation
	if population == null:
		_fail("Main did not expose ZoneNpcPopulation")
		return
	var rows: Array[Dictionary] = []
	var rendered_source_sizes: Dictionary = {}
	for actor in population._actors:
		if not is_instance_valid(actor.node) or not actor.node.visible:
			continue
		var source_key := "%.3f" % actor.source_size
		rendered_source_sizes[source_key] = int(rendered_source_sizes.get(source_key, 0)) + 1
		rows.append({
			"spawn2_id": actor.spawn2_id,
			"npc_type_id": actor.npc_type_id,
			"race_id": actor.race_id,
			"gender_id": actor.gender_id,
			"model_name": actor.model_name,
			"source_size": actor.source_size,
			"default_size": actor.default_size,
			"effective_size": actor.effective_size,
			"raw_model_height": actor.raw_model_height,
			"presentation_scale": actor.presentation_scale,
			"rendered_height": actor.rendered_height,
			"scale_mode": actor.scale_mode,
		})
	var source_type_sizes := _source_type_size_distribution(population._content)
	var report := {
		"schema_id": "eqm.classic_p1999_npc_size_fidelity",
		"schema_version": 1,
		"zone_key": str(main.get("current_zone_key")),
		"visible_actor_count": rows.size(),
		"source_type_size_distribution": source_type_sizes,
		"rendered_actor_source_size_distribution": rendered_source_sizes,
		"rows": rows,
	}
	_write_report(report)
	print("NPC size fidelity summary: ", JSON.stringify({
		"zone_key": report.zone_key,
		"visible_actor_count": report.visible_actor_count,
		"source_type_size_distribution": source_type_sizes,
		"rendered_actor_source_size_distribution": rendered_source_sizes,
	}))
	for row in rows:
		print(JSON.stringify(row))
	if not _assert_halas_fixture(report):
		return
	main.free()
	quit(0)


func _assert_halas_fixture(report: Dictionary) -> bool:
	if str(report.zone_key) != "eqm:zone:halas":
		_fail("Default fixture changed; update the explicitly named validation fixture")
		return false
	var distribution: Dictionary = report.source_type_size_distribution as Dictionary
	var expected := {"3.000": 2, "6.000": 5, "7.000": 61}
	if distribution != expected:
		_fail("Unexpected Halas source-size distribution: %s" % JSON.stringify(distribution))
		return false
	var sled_dogs := 0
	for row_variant in report.rows:
		var row := row_variant as Dictionary
		if int(row.race_id) != 42 or not is_equal_approx(float(row.source_size), 3.0):
			continue
		sled_dogs += 1
		if not is_equal_approx(float(row.effective_size), 3.0):
			_fail("Sled dog effective size did not preserve explicit source size")
			return false
		if str(row.scale_mode) == "normalized_height" and absf(float(row.rendered_height) - 3.0) > EPSILON:
			_fail("Normalized sled dog did not render at effective size")
			return false
	if sled_dogs != 2:
		_fail("Expected two Halas sled dogs, got %d" % sled_dogs)
		return false
	var ferry_rows := (report.rows as Array).filter(func(row: Dictionary) -> bool: return str(row.model_name) == "hferry")
	if ferry_rows.size() != 1 or str((ferry_rows[0] as Dictionary).scale_mode) != "native_units":
		_fail("Halas ferry native-unit descriptor was not applied")
		return false
	return true


func _source_type_size_distribution(content: Dictionary) -> Dictionary:
	var distribution: Dictionary = {}
	for npc_type_variant in content.get("npc_types", []):
		if not npc_type_variant is Dictionary:
			continue
		var npc_type := npc_type_variant as Dictionary
		var key := "%.3f" % float(npc_type.get("size", 0.0))
		distribution[key] = int(distribution.get(key, 0)) + 1
	return distribution


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("Unable to write %s" % REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()


func _fail(message: String) -> void:
	push_error("NPC size fidelity probe failed: " + message)
	quit(1)
