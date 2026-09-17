class_name HalasNpcPopulation
extends Node3D

## Visual classic-era Halas population. Gameplay/source content is injected by
## ContentService; this presentation adapter never opens gameplay JSON itself.
## EQ server coordinates are [x, y, elevation]. Terrain calibration against
## every static Halas source spawn gives (-y, elevation, x).

const WALK_SPEED := 2.35
const TERRAIN_SNAP_TOLERANCE := 6.0
const TERRAIN_CAST_HEIGHT := 12.0
const TARGET_PICK_COLLISION_LAYER := EqWorldSpace.COLLISION_LAYER_TARGET_PICK
const TARGET_TINT := Color(0.97, 0.32, 0.29, 1.0)
const CHARACTER_MODEL_FACING_OFFSET := PI * 0.5

var _content: Dictionary = {}
var _models_path := ""
var _model_scenes: Dictionary[String, PackedScene] = {}
var _actors: Array[NpcActor] = []
var _source_positions: Array = []
var _spawn_source_positions: Array = []
var _patrol_source_positions: Array = []
var _terrain_validated := false
var _terrain_snapped_count := 0
var _terrain_unmatched_count := 0


class NpcActor:
	var node: Node3D
	var visual: Node3D
	var animator: AnimationPlayer
	var model_name := ""
	var spawn_heading_eq := 0.0
	var visual_ground_y := 0.0
	var patrol: Array = []
	var patrol_targets: Array[Vector3] = []
	var patrol_index := 0
	var pause_remaining := 0.0
	var spawn2_id := 0
	var npc_type_id := 0
	var display_name := ""
	var level := 1
	var class_id := 0
	var merchant_id := 0
	var npc_faction_id := 0
	var loottable_id := 0
	var merchant_ref := ""
	var npc_faction_ref := ""
	var loot_table_ref := ""
	var hp := 1
	var armor_class := 0
	var min_damage := 0
	var max_damage := 0
	var attack_delay_raw := 0
	var nameplate: Label3D


func configure(content: Dictionary, models_path: String) -> void:
	_content = content.duplicate(true)
	_models_path = models_path


func _ready() -> void:
	assert(not _content.is_empty(), "Halas NPC content is required")
	assert(not _models_path.is_empty(), "Halas NPC model directory is required")
	_build_population(_content)
	_validate_static_facing()


func _process(delta: float) -> void:
	for actor in _actors:
		_update_patrol(actor, delta)


func _physics_process(_delta: float) -> void:
	if _terrain_validated:
		return
	_terrain_validated = true
	_validate_terrain_placement()


func _build_population(content: Dictionary) -> void:
	var npc_types: Dictionary = {}
	var spawn_groups: Dictionary = {}
	for npc_type in content.get("npc_types", []):
		npc_types[str(npc_type.get("key", "peq:npc:%d" % int(npc_type.id)))] = npc_type
	for group_id in content.get("spawn_groups", {}):
		var group: Dictionary = content.spawn_groups[group_id]
		spawn_groups[str(group.get("key", "peq:spawn_group:%s" % group_id))] = group
	for spawn in content.get("spawns", []):
		var spawn_group_ref := str(spawn.get("spawn_group_ref", "peq:spawn_group:%d" % int(spawn.get("spawn_group_id", 0))))
		var spawn_group: Dictionary = spawn_groups.get(spawn_group_ref, {})
		if spawn_group.is_empty():
			push_error("Spawn %s has no resolved SpawnGroup %s" % [str(spawn.get("key", spawn.get("spawn2_id", "?"))), spawn_group_ref])
			continue
		var selection_spawn: Dictionary = spawn.duplicate()
		selection_spawn["candidates"] = spawn_group.get("candidates", [])
		var npc_type: Dictionary = _choose_npc_type(selection_spawn, npc_types)
		if npc_type.is_empty():
			continue
		var model_name := _model_for(npc_type)
		if model_name.is_empty():
			continue
		var actor_node := Node3D.new()
		actor_node.name = "%s_%d" % [str(npc_type.name), int(spawn.spawn2_id)]
		actor_node.position = eq_to_world(spawn.position_eq)
		_source_positions.append(spawn.position_eq)
		_spawn_source_positions.append(spawn.position_eq)
		actor_node.rotation.y = static_heading_to_yaw(float(spawn.heading_eq), model_name)
		add_child(actor_node)
		var visual := _load_model(model_name).instantiate() as Node3D
		visual.name = "Model"
		visual.rotation.y = CHARACTER_MODEL_FACING_OFFSET
		actor_node.add_child(visual)
		var animator := _animation_player_below(visual)
		if animator != null and animator.has_animation("idle"):
			animator.play("idle")
			animator.advance(0.0)
		var target_height := _npc_target_height(npc_type)
		_normalize_model_to_height(visual, target_height)
		var nameplate := _add_nameplate(actor_node, str(npc_type.name), target_height)
		_add_target_pick_area(actor_node, target_height, int(spawn.spawn2_id))

		var actor := NpcActor.new()
		actor.node = actor_node
		actor.visual = visual
		actor.animator = animator
		actor.model_name = model_name
		actor.spawn2_id = int(spawn.spawn2_id)
		actor.npc_type_id = int(npc_type.id)
		actor.display_name = str(npc_type.name).replace("_", " ")
		actor.level = int(npc_type.get("level", 1))
		actor.class_id = int(npc_type.get("class", 0))
		# Source combat/loot values are retained for provenance and inspection only.
		# They do not authorize the generic simulation to enable imported combat.
		actor.merchant_id = int(npc_type.get("merchant_id", 0))
		actor.npc_faction_id = int(npc_type.get("npc_faction_id", 0))
		actor.loottable_id = int(npc_type.get("loottable_id", 0))
		actor.merchant_ref = str(npc_type.get("merchant_ref", ""))
		actor.npc_faction_ref = str(npc_type.get("npc_faction_ref", ""))
		actor.loot_table_ref = str(npc_type.get("loot_table_ref", ""))
		actor.hp = int(npc_type.get("hp", 1))
		actor.armor_class = int(npc_type.get("armor_class", 0))
		actor.min_damage = int(npc_type.get("mindmg", 0))
		actor.max_damage = int(npc_type.get("maxdmg", 0))
		actor.attack_delay_raw = int(npc_type.get("attack_delay", 0))
		actor.nameplate = nameplate
		actor.spawn_heading_eq = float(spawn.heading_eq)
		actor.visual_ground_y = visual.position.y
		_set_animation(actor, "idle")
		var grid_id := str(int(spawn.get("grid_id", 0)))
		for point in content.get("grids", {}).get(grid_id, []):
			actor.patrol.append(point)
			_source_positions.append(point.position_eq)
			_patrol_source_positions.append(point.position_eq)
			actor.patrol_targets.append(eq_to_world(point.position_eq))
		_actors.append(actor)


func nearest_target(origin: Vector3, view_forward: Vector3, max_distance: float = 200.0) -> Dictionary:
	var forward := view_forward
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var best: NpcActor = null
	var best_score := INF
	for actor in _actors:
		if not is_instance_valid(actor.node) or not actor.node.visible:
			continue
		var offset := actor.node.global_position - origin
		var distance := offset.length()
		if distance > max_distance:
			continue
		var flat_offset := Vector3(offset.x, 0.0, offset.z)
		var facing := forward.dot(flat_offset.normalized()) if flat_offset.length_squared() > 0.0001 else 1.0
		var score := distance + (1.0 - facing) * 20.0
		if score < best_score:
			best_score = score
			best = actor
	if best == null:
		return {}
	return _target_dictionary(best)


func target_for_pick_area(area: Area3D) -> Dictionary:
	if area == null or not area.has_meta("halas_spawn2_id"):
		return {}
	var spawn2_id := int(area.get_meta("halas_spawn2_id"))
	for actor in _actors:
		if actor.spawn2_id == spawn2_id:
			return _target_dictionary(actor)
	return {}


func _target_dictionary(actor: NpcActor) -> Dictionary:
	return {
		"spawn2_id": actor.spawn2_id,
		"npc_type_id": actor.npc_type_id,
		"name": actor.display_name,
		"level": actor.level,
		"class": actor.class_id,
		"merchant_id": actor.merchant_id,
		"npc_faction_id": actor.npc_faction_id,
		"loottable_id": actor.loottable_id,
		"merchant_ref": actor.merchant_ref,
		"npc_faction_ref": actor.npc_faction_ref,
		"loot_table_ref": actor.loot_table_ref,
		"source_hp": actor.hp,
		"source_armor_class": actor.armor_class,
		"source_min_damage": actor.min_damage,
		"source_max_damage": actor.max_damage,
		"attack_delay_raw": actor.attack_delay_raw,
		"combat_state": "disabled_unreviewed",
		"faction_reaction": "indifferent" if actor.npc_faction_id == 0 else "unresolved",
		"merchant_state": "candidate" if actor.merchant_id > 0 else "none",
		"loot_state": "reference_only" if actor.loottable_id > 0 else "none",
		"node": actor.node,
	}


func set_selected_spawn(spawn2_id: int) -> void:
	for actor in _actors:
		_set_target_highlight(actor, actor.spawn2_id == spawn2_id)


func _set_target_highlight(actor: NpcActor, selected: bool) -> void:
	if actor.nameplate != null:
		actor.nameplate.modulate = TARGET_TINT if selected else Color("f4edcf")
	for mesh_instance in _mesh_instances_below(actor.visual):
		for surface_index in mesh_instance.mesh.get_surface_count():
			if not selected:
				mesh_instance.set_surface_override_material(surface_index, null)
				continue
			var source_material := mesh_instance.get_active_material(surface_index)
			if source_material is BaseMaterial3D:
				var highlight := source_material.duplicate() as BaseMaterial3D
				highlight.albedo_color = TARGET_TINT
				mesh_instance.set_surface_override_material(surface_index, highlight)


func _add_target_pick_area(actor_node: Node3D, target_height: float, spawn2_id: int) -> void:
	var area := Area3D.new()
	area.name = "TargetPick"
	area.collision_layer = TARGET_PICK_COLLISION_LAYER
	area.collision_mask = 0
	area.input_ray_pickable = true
	area.set_meta("halas_spawn2_id", spawn2_id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = clampf(target_height * 0.18, 0.45, 1.5)
	capsule.height = maxf(target_height, capsule.radius * 2.0)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	area.add_child(shape)
	actor_node.add_child(area)


func _choose_npc_type(spawn: Dictionary, npc_types: Dictionary) -> Dictionary:
	var candidates: Array = spawn.get("candidates", [])
	if candidates.is_empty():
		return {}
	# This roster choice is intentionally deterministic content selection, not a
	# simulation random roll. Runtime stochastic systems use SimulationRng.
	var total_weight := 0
	for candidate in candidates:
		total_weight += int(candidate.chance)
	if total_weight <= 0:
		return {}
	var roll := int(spawn.spawn2_id) % total_weight
	for candidate in candidates:
		roll -= int(candidate.chance)
		if roll < 0:
			return npc_types.get(str(candidate.get("npc_ref", "peq:npc:%d" % int(candidate.npc_type_id))), {})
	return npc_types.get(str(candidates[0].get("npc_ref", "peq:npc:%d" % int(candidates[0].npc_type_id))), {})


func _model_for(npc_type: Dictionary) -> String:
	var race := int(npc_type.race)
	var gender := int(npc_type.gender)
	var texture := int(npc_type.get("texture", 0))
	var face := maxi(0, int(npc_type.get("face", 0)))
	if race == 90:
		return _appearance_model("hlf" if gender == 1 else "hlm", texture, face, 1 if gender == 1 else 2, 1 if gender == 1 else 2)
	if race == 2:
		return _appearance_model("baf" if gender == 1 else "bam", texture, face, 4, 4)
	if race == 1:
		return _appearance_model("huf" if gender == 1 else "hum", texture, face, 5, 4)
	if race == 42:
		return _appearance_model("wol", texture, face, 4, 2)
	if race == 73:
		return "hferry"
	return ""


func _appearance_model(family: String, texture: int, face: int, skin_count: int, head_count: int) -> String:
	var skin := clampi(texture, 0, skin_count - 1)
	var head := clampi(face, 0, head_count - 1)
	return "%s_s%d_h%d" % [family, skin, head]


func _npc_target_height(npc_type: Dictionary) -> float:
	var source_size := float(npc_type.get("size", 0.0))
	var default_size := _race_gender_default_size(int(npc_type.race), int(npc_type.gender))
	return source_size if source_size > 0.0 else default_size


func _race_gender_default_size(race: int, _gender: int) -> float:
	match race:
		1:
			return 6.0
		2:
			return 7.0
		42:
			return 4.0
		73:
			return 6.0
		90:
			return 7.0
	return 6.0


func _load_model(model_name: String) -> PackedScene:
	if _model_scenes.has(model_name):
		return _model_scenes[model_name]
	var path := "%s/%s.glb" % [_models_path, model_name]
	var scene := load(path) as PackedScene
	assert(scene != null, "Missing imported Halas character model: %s" % path)
	_model_scenes[model_name] = scene
	return scene


func _add_nameplate(actor_node: Node3D, npc_name: String, target_height: float) -> Label3D:
	var nameplate := Label3D.new()
	nameplate.name = "Nameplate"
	nameplate.text = npc_name.replace("_", " ")
	nameplate.position = Vector3(0.0, target_height + 0.35, 0.0)
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.modulate = Color("f4edcf")
	nameplate.font_size = 32
	nameplate.outline_size = 4
	actor_node.add_child(nameplate)
	return nameplate


func _normalize_model_to_height(visual: Node3D, target_height: float) -> void:
	var lowest_point := INF
	var highest_point := -INF
	for mesh_instance in _mesh_instances_below(visual):
		if mesh_instance.mesh == null:
			continue
		var relative_transform := visual.global_transform.affine_inverse() * mesh_instance.global_transform
		var bounds := mesh_instance.get_aabb()
		for corner in 8:
			var point := relative_transform * bounds.get_endpoint(corner)
			lowest_point = minf(lowest_point, point.y)
			highest_point = maxf(highest_point, point.y)
	var raw_height := highest_point - lowest_point
	assert(raw_height > 0.001, "Unable to measure character model height")
	var visual_scale := EqWorldSpace.visual_scale_for_height(raw_height, target_height)
	visual.scale = Vector3.ONE * visual_scale
	visual.position.y = -lowest_point * visual_scale


func _mesh_instances_below(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_mesh_instances_below(child))
	return result


func _animation_player_below(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found := _animation_player_below(child)
		if found != null:
			return found
	return null


func _set_animation(actor: NpcActor, clip: String) -> void:
	if actor.animator == null or not actor.animator.has_animation(clip):
		return
	if actor.animator.current_animation != clip:
		actor.animator.play(clip)


func _update_patrol(actor: NpcActor, delta: float) -> void:
	if actor.patrol.is_empty():
		_set_animation(actor, "idle")
		return
	if actor.pause_remaining > 0.0:
		actor.pause_remaining = maxf(0.0, actor.pause_remaining - delta)
		actor.visual.position.y = actor.visual_ground_y
		_set_animation(actor, "idle")
		return
	var point: Dictionary = actor.patrol[actor.patrol_index]
	var target := actor.patrol_targets[actor.patrol_index]
	var offset := target - actor.node.position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= 0.12:
		actor.node.position = target
		actor.node.rotation.y = static_heading_to_yaw(float(point.heading_eq), actor.model_name) if float(point.heading_eq) >= 0.0 else actor.node.rotation.y
		actor.pause_remaining = float(point.get("pause_seconds", 0))
		actor.patrol_index = (actor.patrol_index + 1) % actor.patrol.size()
		actor.visual.position.y = actor.visual_ground_y
		_set_animation(actor, "idle")
		return
	var direction := offset / distance
	actor.node.position += direction * minf(distance, WALK_SPEED * delta)
	actor.node.look_at(actor.node.global_position + direction, Vector3.UP)
	actor.visual.position.y = actor.visual_ground_y
	_set_animation(actor, "walk")


func _validate_static_facing() -> void:
	var static_count := 0
	var lowest_alignment := 1.0
	for actor in _actors:
		if not actor.patrol.is_empty():
			continue
		static_count += 1
		var expected := static_heading_expected_forward(actor.spawn_heading_eq, actor.model_name)
		var actual := actor.visual.global_transform.basis * Vector3.RIGHT
		actual.y = 0.0
		actual = actual.normalized()
		var alignment := actual.dot(expected)
		lowest_alignment = minf(lowest_alignment, alignment)
		assert(alignment > 0.9999, "Static NPC heading mismatch: %s" % actor.node.name)
	print(
		"Halas static facing audit: %d source-headed NPCs, worst alignment %.6f."
		% [static_count, lowest_alignment]
	)


func _validate_terrain_placement() -> void:
	var space_state := get_world_3d().direct_space_state
	_print_transform_audit(space_state)
	for actor in _actors:
		actor.node.global_position = _snap_to_agreeing_terrain(space_state, actor.node.global_position)
		for index in actor.patrol_targets.size():
			actor.patrol_targets[index] = _snap_to_agreeing_terrain(space_state, actor.patrol_targets[index])
	print(
		"Halas NPC placement validation: %d terrain-aligned, %d source-elevation retained."
		% [_terrain_snapped_count, _terrain_unmatched_count]
	)


func _print_transform_audit(space_state: PhysicsDirectSpaceState3D) -> void:
	var candidates := {
		"-x,z,y": func(p: Array) -> Vector3: return Vector3(-float(p[0]), float(p[2]), float(p[1])),
		"x,z,-y": func(p: Array) -> Vector3: return Vector3(float(p[0]), float(p[2]), -float(p[1])),
		"-y,z,x": func(p: Array) -> Vector3: return Vector3(-float(p[1]), float(p[2]), float(p[0])),
		"y,z,-x": func(p: Array) -> Vector3: return Vector3(float(p[1]), float(p[2]), -float(p[0])),
	}
	var results: Array[String] = []
	for label in candidates:
		var transform: Callable = candidates[label]
		var spawn_aligned := _count_terrain_matches(space_state, transform, _spawn_source_positions)
		var patrol_aligned := _count_terrain_matches(space_state, transform, _patrol_source_positions)
		results.append(
			"%s=spawns %d/%d, paths %d/%d" % [
				label,
				spawn_aligned,
				_spawn_source_positions.size(),
				patrol_aligned,
				_patrol_source_positions.size(),
			]
		)
	print("Halas coordinate audit: " + ", ".join(results))


func _count_terrain_matches(space_state: PhysicsDirectSpaceState3D, transform: Callable, points: Array) -> int:
	var aligned := 0
	for source_position in points:
		if _terrain_agrees(space_state, transform.call(source_position)):
			aligned += 1
	return aligned


func _terrain_agrees(space_state: PhysicsDirectSpaceState3D, source: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		source + Vector3.UP * TERRAIN_CAST_HEIGHT,
		source - Vector3.UP * TERRAIN_CAST_HEIGHT
	)
	query.collision_mask = EqWorldSpace.COLLISION_LAYER_TERRAIN
	var hit := space_state.intersect_ray(query)
	return not hit.is_empty() and absf(((hit.position as Vector3).y) - source.y) <= TERRAIN_SNAP_TOLERANCE


func _snap_to_agreeing_terrain(space_state: PhysicsDirectSpaceState3D, source: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		source + Vector3.UP * TERRAIN_CAST_HEIGHT,
		source - Vector3.UP * TERRAIN_CAST_HEIGHT
	)
	query.collision_mask = EqWorldSpace.COLLISION_LAYER_TERRAIN
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		_terrain_unmatched_count += 1
		return source
	var terrain_y := (hit.position as Vector3).y
	if absf(terrain_y - source.y) > TERRAIN_SNAP_TOLERANCE:
		_terrain_unmatched_count += 1
		return source
	_terrain_snapped_count += 1
	return Vector3(source.x, terrain_y, source.z)


static func eq_to_world(position_eq: Array) -> Vector3:
	return EqWorldSpace.halas_server_position(position_eq)


static func static_heading_to_yaw(heading_eq: float, model_name: String) -> float:
	if heading_eq < 0.0:
		return 0.0
	var yaw := EqWorldSpace.heading_to_godot_yaw(heading_eq)
	if model_name.begins_with("hlf_"):
		yaw += PI
	return yaw


static func static_heading_expected_forward(heading_eq: float, model_name: String) -> Vector3:
	var forward := EqWorldSpace.heading_forward(heading_eq)
	if model_name.begins_with("hlf_"):
		forward = -forward
	return forward