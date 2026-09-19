class_name ZoneNpcPopulation
extends Node3D

## Zone-owned NPC presentation. Gameplay/source content is injected through
## ContentService and resolved SpawnPoints; this class never opens gameplay
## JSON itself. Source coordinates and appearance quirks come from ZoneDefinition
## data rather than from a hardcoded first-zone transform.

const TARGET_PICK_COLLISION_LAYER := EqWorldSpace.COLLISION_LAYER_TARGET_PICK
const TARGET_TINT := Color(0.97, 0.32, 0.29, 1.0)
const NpcSizeContractScript = preload("res://scripts/domain/npc_size_contract.gd")

var _content: Dictionary = {}
var _resolved_spawns: Dictionary = {}
var _zone_runtime_state: ZoneRuntimeState
var _zone_world_space: ZoneWorldSpace
var _presentation_profile: Dictionary = {}
var _npc_default_heights: Dictionary = {}
var _models_path := ""
var _model_scenes: Dictionary[String, PackedScene] = {}
var _actors: Array[NpcActor] = []
var _actors_by_spawn2: Dictionary = {}
var _source_positions: Array = []
var _spawn_source_positions: Array = []
var _patrol_source_positions: Array = []
var _terrain_validated := false
var _terrain_aligned_count := 0
var _terrain_unmatched_count := 0
var _runtime_paused := false


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
	var movement_velocity := Vector3.ZERO
	var spawn2_id := 0
	var spawn_key := ""
	var grid_id := 0
	var npc_type_id := 0
	var display_name := ""
	var level := 1
	var class_id := 0
	var class_ref := ""
	var race_id := 0
	var race_ref := ""
	var gender_id := 0
	var texture := 0
	var face := 0
	var source_size := 0.0
	var default_size := 6.0
	var effective_size := 6.0
	var rendered_height := 6.0
	var raw_model_height := 0.0
	var presentation_scale := 1.0
	var scale_mode := "normalized_height"
	var source_mana := 0
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


func configure(
	content: Dictionary,
	models_path: String,
	resolved_spawns: Dictionary,
	zone_runtime_state: ZoneRuntimeState,
	zone_world_space: ZoneWorldSpace,
	presentation_profile: Dictionary = {},
	npc_default_heights: Dictionary = {}
) -> void:
	_content = content.duplicate(true)
	_resolved_spawns = resolved_spawns.duplicate(true)
	_zone_runtime_state = zone_runtime_state
	_zone_world_space = zone_world_space
	_presentation_profile = (
		presentation_profile.duplicate(true)
	)
	_npc_default_heights = npc_default_heights.duplicate(true)
	_models_path = models_path


func _ready() -> void:
	assert(
		not _content.is_empty(),
		"Zone NPC content is required"
	)
	assert(
		not _resolved_spawns.is_empty(),
		"Resolved zone spawn definitions are required"
	)
	assert(
		_zone_runtime_state != null,
		"ZoneRuntimeState is required by the population compatibility bridge"
	)
	assert(
		_zone_world_space != null
		and _zone_world_space.is_valid(),
		"Valid ZoneWorldSpace is required by zone NPC presentation"
	)
	assert(
		not _models_path.is_empty()
		or _missing_model_policy()
		== "placeholder",
		"Zone NPC model directory is required unless placeholder presentation is enabled"
	)
	_build_population(_content)
	_validate_static_facing()


func set_runtime_paused(
	paused: bool
) -> void:
	if _runtime_paused == paused:
		return

	_runtime_paused = paused

	if not paused:
		return

	# Patrol is currently a presentation compatibility path whose
	# pose is mirrored into GameplayEntity. Stop all reported
	# movement before the simulation is saved or suspended.
	for actor in _actors:
		actor.movement_velocity = Vector3.ZERO
		_set_animation(
			actor,
			"idle"
		)


func is_runtime_paused() -> bool:
	return _runtime_paused

func _process(delta: float) -> void:
	if _runtime_paused:
		return

	for actor in _actors:
		_update_patrol(
			actor,
			delta
		)

func _physics_process(_delta: float) -> void:
	if _runtime_paused:
		return

	if _terrain_validated:
		return

	_terrain_validated = true

	if (
		_terrain_snap_tolerance() <= 0.0
		or _terrain_cast_height() <= 0.0
	):
		return

	_validate_terrain_placement()

func _build_population(content: Dictionary) -> void:
	var spawns_variant: Variant = content.get(
		"spawns",
		[]
	)

	assert(
		spawns_variant is Array,
		"NPC content requires a spawn array"
	)

	for source_spawn_variant in (
		spawns_variant as Array
	):
		assert(
			source_spawn_variant is Dictionary,
			"NPC spawn must be a dictionary"
		)

		var source_spawn: Dictionary = (
			source_spawn_variant as Dictionary
		)
		var spawn2_id := int(
			source_spawn.get(
				"spawn2_id",
				0
			)
		)

		assert(
			spawn2_id > 0,
			"Presentation spawn requires spawn2 identity"
		)

		var spawn_key := str(
			source_spawn.get(
				"key",
				ZoneSpawnResolver.spawn_key_for_id(
					spawn2_id
				)
			)
		)
		var resolved_variant: Variant = (
			_resolved_spawns.get(
				spawn_key,
				null
			)
		)

		assert(
			resolved_variant is Dictionary,
			"Presentation spawn has no generic resolved definition: %s"
			% spawn_key
		)

		var spawn: Dictionary = (
			resolved_variant as Dictionary
		)

		assert(
			int(
				spawn.get(
					"spawn2_id",
					0
				)
			) == spawn2_id,
			"Resolved SpawnPoint identity mismatch: %s"
			% spawn_key
		)

		var npc_variant: Variant = (
			spawn.get(
				"npc_definition",
				null
			)
		)

		assert(
			npc_variant is Dictionary,
			"Resolved SpawnPoint has no NPC definition: %s"
			% spawn_key
		)

		var npc_type: Dictionary = (
			npc_variant as Dictionary
		)
		var selected_definition_ref := str(
			spawn.get(
				"selected_definition_ref",
				""
			)
		)
		var npc_definition_ref := str(
			npc_type.get(
				"key",
				ZoneSpawnResolver.npc_key_for_id(
					int(
						npc_type.get(
							"id",
							0
						)
					)
				)
			)
		)

		assert(
			not selected_definition_ref.is_empty()
			and selected_definition_ref
			== npc_definition_ref,
			"Resolved SpawnPoint definition mismatch: %s"
			% spawn_key
		)

		var model_descriptor := (
			_model_descriptor(
				npc_type
			)
		)
		var model_name := str(
			model_descriptor.get(
				"model_name",
				""
			)
		)

		if (
			model_name.is_empty()
			and _missing_model_policy()
			== "skip"
		):
			continue

		var heading_yaw_offset := deg_to_rad(
			float(
				model_descriptor.get(
					"heading_yaw_offset_degrees",
					0.0
				)
			)
		)

		var actor_node := Node3D.new()
		actor_node.name = (
			"%s_%d"
			% [
				str(npc_type.name),
				int(spawn.spawn2_id),
			]
		)
		actor_node.position = (
			_server_position(
				spawn.position_eq
			)
		)
		_source_positions.append(
			spawn.position_eq
		)
		_spawn_source_positions.append(
			spawn.position_eq
		)
		actor_node.rotation.y = _server_heading_to_yaw(float(spawn.heading_eq))
		add_child(actor_node)

		var source_size := float(npc_type.get("size", 0.0))
		var race_id := int(npc_type.get("race", 0))
		var gender_id := int(npc_type.get("gender", 0))
		var default_size: float = NpcSizeContractScript.default_size(
			_npc_default_heights,
			race_id,
			gender_id
		)
		var effective_size: float = NpcSizeContractScript.effective_size(
			source_size,
			_npc_default_heights,
			race_id,
			gender_id
		)
		var scale_mode := _presentation_scale_mode(model_descriptor)

		var visual: Node3D
		var animator: AnimationPlayer

		if model_name.is_empty():
			visual = (
				_placeholder_visual(
					effective_size
				)
			)
		else:
			visual = (
				_load_model(
					model_name
				).instantiate()
				as Node3D
			)
		visual.rotation.y = deg_to_rad(_visual_facing_offset_degrees()) + heading_yaw_offset

		visual.name = "Model"
		actor_node.add_child(
			visual
		)

		# Model bounds use global transforms, so the visual must belong to the
		# active scene tree before height normalization inspects child meshes.
		var rendered_height := effective_size
		var raw_model_height := effective_size
		var presentation_scale := 1.0
		if not model_name.is_empty():
			var scale_result: Dictionary = _scale_model_for_presentation(
				visual,
				effective_size,
				default_size,
				scale_mode
			)
			raw_model_height = float(scale_result["raw_height"])
			presentation_scale = float(scale_result["scale"])
			rendered_height = float(scale_result["rendered_height"])
			animator = (
				_animation_player_below(
					visual
				)
			)

		if (
			animator != null
			and animator.has_animation(
				"idle"
			)
		):
			animator.play(
				"idle"
			)
			animator.advance(
				0.0
			)

		var nameplate := (
			_add_nameplate(
				actor_node,
				str(npc_type.name),
				rendered_height
			)
		)
		_add_target_pick_area(actor_node, rendered_height, int(spawn.spawn2_id))

		var actor := NpcActor.new()
		actor.node = actor_node
		actor.visual = visual
		actor.animator = animator
		actor.model_name = model_name
		actor.spawn2_id = int(spawn.spawn2_id)
		actor.spawn_key = spawn_key
		actor.npc_type_id = int(npc_type.id)
		actor.display_name = str(npc_type.name).replace("_", " ")
		actor.level = int(npc_type.get("level", 1))
		actor.class_id = int(npc_type.get("class", 0))
		actor.class_ref = str(npc_type.get("class_ref", ""))
		actor.race_id = race_id
		actor.race_ref = str(npc_type.get("race_ref", ""))
		actor.gender_id = gender_id
		actor.texture = int(npc_type.get("texture", 0))
		actor.face = int(npc_type.get("face", 0))
		actor.source_size = source_size
		actor.default_size = default_size
		actor.effective_size = effective_size
		actor.rendered_height = rendered_height
		actor.raw_model_height = raw_model_height
		actor.presentation_scale = presentation_scale
		actor.scale_mode = scale_mode
		actor.source_mana = int(npc_type.get("mana", 0))
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
		var spawn_runtime := _spawn_runtime(
			spawn_key
		)
		actor.grid_id = int(
			spawn_runtime.get(
				"grid_id",
				spawn.get(
					"grid_id",
					0
				)
			)
		)

		var grid_key := str(
			actor.grid_id
		)

		for point in content.get(
			"grids",
			{}
		).get(
			grid_key,
			[]
		):
			actor.patrol.append(
				point
			)
			_source_positions.append(
				point.position_eq
			)
			_patrol_source_positions.append(
				point.position_eq
			)
			actor.patrol_targets.append(
				_server_position(
					point.position_eq
				)
			)

		_restore_or_seed_actor_runtime(
			actor
		)

		_actors.append(actor)
		_actors_by_spawn2[actor.spawn2_id] = actor


func actor_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []

	for actor in _actors:
		targets.append(
			_target_dictionary(
				actor
			)
		)

	return targets


func movement_velocity_for_spawn(
	spawn2_id: int
) -> Vector3:
	var actor := (
		_actors_by_spawn2.get(
			spawn2_id
		)
		as NpcActor
	)

	if actor == null:
		return Vector3.ZERO

	return actor.movement_velocity

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
	if area == null or not area.has_meta("zone_spawn2_id"):
		return {}
	var spawn2_id := int(area.get_meta("zone_spawn2_id"))
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
		"class_id": actor.class_id,
		"class_ref": actor.class_ref,
		"race_id": actor.race_id,
		"race_ref": actor.race_ref,
		"gender_id": actor.gender_id,
		"model_name": actor.model_name,
		"texture": actor.texture,
		"face": actor.face,
		"source_size": actor.source_size,
		"default_size": actor.default_size,
		"effective_size": actor.effective_size,
		"rendered_height": actor.rendered_height,
		"raw_model_height": actor.raw_model_height,
		"presentation_scale": actor.presentation_scale,
		"scale_mode": actor.scale_mode,
		"source_mana": actor.source_mana,
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
	area.set_meta("zone_spawn2_id", spawn2_id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = clampf(target_height * 0.18, 0.45, 1.5)
	capsule.height = maxf(target_height, capsule.radius * 2.0)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	area.add_child(shape)
	actor_node.add_child(area)


func _audit_label() -> String:
	return str(
		_presentation_profile.get(
			"audit_label",
			"Zone"
		)
	)


func _missing_model_policy() -> String:
	return str(
		_presentation_profile.get(
			"missing_model_policy",
			"placeholder"
		)
	)


func _visual_facing_offset_degrees() -> float:
	return float(
		_presentation_profile.get(
			"visual_facing_offset_degrees",
			0.0
		)
	)


func _patrol_walk_speed() -> float:
	return maxf(
		0.0,
		float(
			_presentation_profile.get(
				"patrol_walk_speed",
				0.0
			)
		)
	)


func _terrain_snap_tolerance() -> float:
	return maxf(
		0.0,
		float(
			_presentation_profile.get(
				"terrain_snap_tolerance",
				0.0
			)
		)
	)


func _terrain_cast_height() -> float:
	return maxf(
		0.0,
		float(
			_presentation_profile.get(
				"terrain_cast_height",
				0.0
			)
		)
	)


func _model_descriptor(
	npc_type: Dictionary
) -> Dictionary:
	var explicit_model := str(
		npc_type.get(
			"model_name",
			""
		)
	)

	if not explicit_model.is_empty():
		return {
			"model_name":
				explicit_model,
			"default_size":
				float(
					_presentation_profile.get(
						"default_height",
						1.0
					)
				),
			"heading_yaw_offset_degrees":
				0.0,
		}

	var rules_variant: Variant = (
		_presentation_profile.get(
			"model_rules",
			[]
		)
	)

	if not rules_variant is Array:
		return {}

	var race_id := int(
		npc_type.get(
			"race",
			0
		)
	)
	var gender_id := int(
		npc_type.get(
			"gender",
			0
		)
	)
	var texture := int(
		npc_type.get(
			"texture",
			0
		)
	)
	var face := maxi(
		0,
		int(
			npc_type.get(
				"face",
				0
			)
		)
	)

	for rule_variant in (
		rules_variant as Array
	):
		if not rule_variant is Dictionary:
			continue

		var rule: Dictionary = (
			rule_variant
		)

		if int(
			rule.get(
				"race_id",
				-1
			)
		) != race_id:
			continue

		if (
			rule.has(
				"gender_id"
			)
			and int(
				rule.get(
					"gender_id",
					-1
				)
			) != gender_id
		):
			continue

		var descriptor := (
			rule.duplicate(true)
		)

		var model_name := str(
			rule.get(
				"model_name",
				""
			)
		)

		if model_name.is_empty():
			var family := str(
				rule.get(
					"family",
					""
				)
			)

			if family.is_empty():
				return {}

			model_name = (
				_appearance_model(
					family,
					texture,
					face,
					maxi(
						1,
						int(
							rule.get(
								"skin_count",
								1
							)
						)
					),
					maxi(
						1,
						int(
							rule.get(
								"head_count",
								1
							)
						)
					)
				)
			)

		descriptor[
			"model_name"
		] = model_name

		return descriptor

	return {}


func _appearance_model(
	family: String,
	texture: int,
	face: int,
	skin_count: int,
	head_count: int
) -> String:
	var skin := clampi(
		texture,
		0,
		skin_count - 1
	)
	var head := clampi(
		face,
		0,
		head_count - 1
	)

	return "%s_s%d_h%d" % [
		family,
		skin,
		head,
	]


func _presentation_scale_mode(model_descriptor: Dictionary) -> String:
	var mode := str(model_descriptor.get("scale_mode", "normalized_height"))
	assert(
		mode in ["normalized_height", "native_units"],
		"Unsupported NPC presentation scale mode: %s" % mode
	)
	return mode


func _placeholder_visual(
	target_height: float
) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()

	capsule.radius = maxf(
		0.2,
		target_height * 0.18
	)
	capsule.height = maxf(
		target_height,
		capsule.radius * 2.0
	)

	body.name = "Placeholder"
	body.mesh = capsule
	body.position.y = (
		capsule.height
		* 0.5
	)

	root.add_child(
		body
	)

	return root


func _load_model(model_name: String) -> PackedScene:
	if _model_scenes.has(model_name):
		return _model_scenes[model_name]
	var path := "%s/%s.glb" % [_models_path, model_name]
	var scene := load(path) as PackedScene
	assert(scene != null, "Missing imported zone character model: %s" % path)
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


func _scale_model_for_presentation(
	visual: Node3D,
	effective_size: float,
	default_size: float,
	scale_mode: String
) -> Dictionary:
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
	var visual_scale := NpcSizeContractScript.presentation_scale(
		raw_height,
		effective_size,
		default_size,
		scale_mode
	)
	visual.scale = Vector3.ONE * visual_scale
	visual.position.y = -lowest_point * visual_scale
	return {
		"raw_height": raw_height,
		"scale": visual_scale,
		"rendered_height": NpcSizeContractScript.rendered_height(raw_height, visual_scale),
	}


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


func _spawn_runtime(
	spawn_key: String
) -> Dictionary:
	if (
		_zone_runtime_state == null
		or spawn_key.is_empty()
	):
		return {}

	var state := (
		_zone_runtime_state.spawn_state(
			spawn_key
		)
	)

	var runtime_variant: Variant = (
		state.get(
			"runtime",
			{}
		)
	)

	if not runtime_variant is Dictionary:
		return {}

	return (
		(
			runtime_variant
			as Dictionary
		).duplicate(true)
	)


func _normalized_patrol_index(
	actor: NpcActor,
	index: int
) -> int:
	if actor.patrol.is_empty():
		return 0

	var size := actor.patrol.size()
	return (
		(index % size + size)
		% size
	)


func _runtime_position(
	value: Variant
) -> Variant:
	if not value is Array:
		return null

	var components: Array = value

	if components.size() != 3:
		return null

	return Vector3(
		float(
			components[0]
		),
		float(
			components[1]
		),
		float(
			components[2]
		)
	)


func _restore_or_seed_actor_runtime(
	actor: NpcActor
) -> void:
	var runtime := _spawn_runtime(
		actor.spawn_key
	)

	actor.grid_id = int(
		runtime.get(
			"grid_id",
			actor.grid_id
		)
	)
	actor.patrol_index = (
		_normalized_patrol_index(
			actor,
			int(
				runtime.get(
					"patrol_index",
					0
				)
			)
		)
	)
	actor.pause_remaining = maxf(
		0.0,
		float(
			runtime.get(
				"pause_remaining",
				0.0
			)
		)
	)

	var position_variant: Variant = (
		_runtime_position(
			runtime.get(
				"position",
				null
			)
		)
	)

	if position_variant is Vector3:
		actor.node.position = (
			position_variant as Vector3
		)

	if runtime.get("heading_space", "") == "canonical_world" and runtime.has("heading_radians"):
		actor.node.rotation.y = float(
			runtime[
				"heading_radians"
			]
		)

	_write_actor_runtime(
		actor,
		actor.patrol_index,
		actor.pause_remaining
	)


func _write_actor_runtime(
	actor: NpcActor,
	patrol_index: int,
	pause_remaining: float
) -> void:
	# The live zone always supplies ZoneRuntimeState. Keeping the actor fields
	# synchronized provides a temporary compatibility surface for isolated
	# presentation tests while ZoneRuntimeState remains authoritative.
	actor.patrol_index = (
		_normalized_patrol_index(
			actor,
			patrol_index
		)
	)
	actor.pause_remaining = maxf(
		0.0,
		pause_remaining
	)

	if (
		_zone_runtime_state == null
		or actor.spawn_key.is_empty()
	):
		return

	var runtime := _spawn_runtime(
		actor.spawn_key
	)

	runtime[
		"grid_id"
	] = actor.grid_id
	runtime[
		"patrol_index"
	] = actor.patrol_index
	runtime[
		"pause_remaining"
	] = actor.pause_remaining
	runtime[
		"position"
	] = [
		actor.node.position.x,
		actor.node.position.y,
		actor.node.position.z,
	]
	runtime[
		"heading_radians"
	] = actor.node.rotation.y
	runtime[
		"heading_space"
	] = "canonical_world"

	_zone_runtime_state.set_spawn_runtime(
		actor.spawn_key,
		runtime
	)


func _update_patrol(
	actor: NpcActor,
	delta: float
) -> void:
	actor.movement_velocity = Vector3.ZERO

	if actor.patrol.is_empty():
		_set_animation(
			actor,
			"idle"
		)
		return

	var runtime := _spawn_runtime(
		actor.spawn_key
	)

	var patrol_index := (
		_normalized_patrol_index(
			actor,
			int(
				runtime.get(
					"patrol_index",
					actor.patrol_index
				)
			)
		)
	)

	var pause_remaining := maxf(
		0.0,
		float(
			runtime.get(
				"pause_remaining",
				actor.pause_remaining
			)
		)
	)

	if pause_remaining > 0.0:
		pause_remaining = maxf(
			0.0,
			pause_remaining - delta
		)
		actor.visual.position.y = (
			actor.visual_ground_y
		)
		_write_actor_runtime(
			actor,
			patrol_index,
			pause_remaining
		)
		_set_animation(
			actor,
			"idle"
		)
		return

	var point: Dictionary = actor.patrol[
		patrol_index
	]
	var target := actor.patrol_targets[
		patrol_index
	]
	var offset := (
		target
		- actor.node.position
	)
	offset.y = 0.0

	var distance := offset.length()

	if distance <= 0.12:
		actor.node.position = target

		pause_remaining = float(
			point.get(
				"pause_seconds",
				0
			)
		)
		if pause_remaining > 0.0 and float(point.heading_eq) >= 0.0:
			actor.node.rotation.y = _server_heading_to_yaw(float(point.heading_eq))
		patrol_index = (
			(patrol_index + 1)
			% actor.patrol.size()
		)
		actor.visual.position.y = (
			actor.visual_ground_y
		)

		_write_actor_runtime(
			actor,
			patrol_index,
			pause_remaining
		)
		_set_animation(
			actor,
			"idle"
		)
		return

	var direction := (
		offset
		/ distance
	)
	var travel_distance := minf(
		distance,
		_patrol_walk_speed() * delta
	)

	actor.node.position += (
		direction
		* travel_distance
	)

	if delta > 0.0:
		actor.movement_velocity = (
			direction
			* (
				travel_distance
				/ delta
			)
		)

	actor.node.rotation.y = EqWorldSpace.horizontal_direction_to_yaw(direction)
	actor.visual.position.y = (
		actor.visual_ground_y
	)

	_write_actor_runtime(
		actor,
		patrol_index,
		0.0
	)
	_set_animation(
		actor,
		"walk"
	)


func _validate_static_facing() -> void:
	var static_count := 0
	var lowest_alignment := 1.0
	for actor in _actors:
		if (
			not actor.patrol.is_empty()
			or actor.model_name.is_empty()
		):
			continue
		static_count += 1
		var expected := _zone_world_space.server_heading_direction(actor.spawn_heading_eq)
		var actual := actor.visual.global_transform.basis * Vector3.RIGHT
		actual.y = 0.0
		actual = actual.normalized()
		var alignment := actual.dot(expected)
		lowest_alignment = minf(lowest_alignment, alignment)
		assert(
			alignment > 0.9999,
			"Static NPC heading mismatch: %s expected=%s actor=%s actual=%s"
			% [
				actor.node.name,
				expected,
				actor.node.global_transform.basis * Vector3.FORWARD,
				actual,
			]
		)
	print(
		"%s static facing audit: %d source-headed NPCs, worst alignment %.6f."
		% [
			_audit_label(),
			static_count,
			lowest_alignment,
		]
	)


func _validate_terrain_placement() -> void:
	var space_state := get_world_3d().direct_space_state
	_print_transform_audit(space_state)
	for actor in _actors:
		# Spawn and patrol coordinates are canonical mapped source data. Terrain
		# observations are useful for auditing transforms, but path grounding is a
		# future movement/presentation concern and must never rewrite those values.
		_record_terrain_diagnostic(
			space_state,
			actor.node.global_position
		)
		for target in actor.patrol_targets:
			_record_terrain_diagnostic(
				space_state,
				target
			)
	print(
		"%s NPC terrain diagnostic: %d terrain-aligned, %d source-elevation retained."
		% [
			_audit_label(),
			_terrain_aligned_count,
			_terrain_unmatched_count,
		]
	)


func _print_transform_audit(
	space_state: PhysicsDirectSpaceState3D
) -> void:
	var candidates_variant: Variant = (
		_presentation_profile.get(
			"coordinate_audit_axis_maps",
			[]
		)
	)

	if (
		not candidates_variant is Array
		or (
			candidates_variant as Array
		).is_empty()
	):
		return

	var results: Array[String] = []

	for candidate_variant in (
		candidates_variant as Array
	):
		if not candidate_variant is Dictionary:
			continue

		var candidate: Dictionary = (
			candidate_variant
		)
		var label := str(
			candidate.get(
				"label",
				"map"
			)
		)
		var axis_map_variant: Variant = (
			candidate.get(
				"axis_map",
				[]
			)
		)

		if not axis_map_variant is Array:
			continue

		var axis_map: Array = (
			axis_map_variant as Array
		)

		if axis_map.size() != 3:
			continue

		var spawn_aligned := (
			_count_terrain_matches(
				space_state,
				axis_map,
				_spawn_source_positions
			)
		)
		var patrol_aligned := (
			_count_terrain_matches(
				space_state,
				axis_map,
				_patrol_source_positions
			)
		)

		results.append(
			"%s=spawns %d/%d, paths %d/%d"
			% [
				label,
				spawn_aligned,
				_spawn_source_positions.size(),
				patrol_aligned,
				_patrol_source_positions.size(),
			]
		)

	if not results.is_empty():
		print(
			"%s coordinate audit: %s"
			% [
				_audit_label(),
				", ".join(
					results
				),
			]
		)


func _count_terrain_matches(
	space_state: PhysicsDirectSpaceState3D,
	axis_map: Array,
	points: Array
) -> int:
	var aligned := 0

	for source_position in points:
		if _terrain_agrees(
			space_state,
			EqWorldSpace.map_position(
				source_position,
				axis_map
			)
		):
			aligned += 1

	return aligned


func _terrain_agrees(space_state: PhysicsDirectSpaceState3D, source: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		source + Vector3.UP * _terrain_cast_height(),
		source - Vector3.UP * _terrain_cast_height()
	)
	query.collision_mask = EqWorldSpace.COLLISION_LAYER_TERRAIN
	var hit := space_state.intersect_ray(query)
	return not hit.is_empty() and absf(((hit.position as Vector3).y) - source.y) <= _terrain_snap_tolerance()


func _record_terrain_diagnostic(space_state: PhysicsDirectSpaceState3D, source: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(
		source + Vector3.UP * _terrain_cast_height(),
		source - Vector3.UP * _terrain_cast_height()
	)
	query.collision_mask = EqWorldSpace.COLLISION_LAYER_TERRAIN
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		_terrain_unmatched_count += 1
		return
	var terrain_y := (hit.position as Vector3).y
	if absf(terrain_y - source.y) > _terrain_snap_tolerance():
		_terrain_unmatched_count += 1
		return
	_terrain_aligned_count += 1


func _server_position(
	position_eq: Array
) -> Vector3:
	assert(
		_zone_world_space != null
		and _zone_world_space.is_valid(),
		"ZoneWorldSpace is required for NPC source coordinates"
	)

	return _zone_world_space.server_position(
		position_eq
	)


func _server_heading_to_yaw(heading_eq: float) -> float:
	if heading_eq < 0.0:
		return 0.0
	return _zone_world_space.server_heading_yaw(heading_eq)
