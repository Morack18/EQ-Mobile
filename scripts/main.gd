extends Node3D

const PLAYER_ENTITY_ID := "player:local"
const TRAINING_ENTITY_ID := "fixture:spawn:training_spark"

# These definitions are application-wide. Zone-owned content is resolved from
# the selected ZoneDefinition through ZoneDefinitionLoader.
const GLOBAL_CONTENT_PATHS := {
	"items": "res://data/items.json",
	"player_classes": "res://data/player_classes.json",
	"player_fixture": "res://data/player_fixture.json",
	"eqemu_default_heights": "res://data/eqemu_default_heights.json",
}

# Presentation/world constants. Gameplay health, damage, cooldown, progression,
# inventory, faction, death, respawn, and reward rules live in the domain layer.
const PLAYER_RUN_SPEED := EqWorldSpace.EQ_MANUAL_RUN_SPEED
const PLAYER_WALK_SPEED := PLAYER_RUN_SPEED * (0.3 / 0.7)
const WALK_RUN_THRESHOLD := 20.0
const PLAYER_COLLISION_RADIUS := EqWorldSpace.EQ_COLLISION_RADIUS
const COLLISION_LAYER_TERRAIN := EqWorldSpace.COLLISION_LAYER_TERRAIN
const COLLISION_LAYER_WORLD_OBJECTS := EqWorldSpace.COLLISION_LAYER_WORLD_OBJECTS
const COLLISION_LAYER_TARGET_PICK := EqWorldSpace.COLLISION_LAYER_TARGET_PICK
const PLAYER_WORLD_COLLISION_MASK := EqWorldSpace.WORLD_COLLISION_MASK
const PLAYER_MAX_SLOPE_ANGLE := deg_to_rad(60.0)
const PLAYER_FLOOR_SNAP_DISTANCE := 0.5
const PLAYER_SAFE_MARGIN := 0.05
const PLAYER_STEP_UP_HEIGHT := 2.0
const EQ_GRAVITY := EqWorldSpace.EQ_GRAVITY
const EQ_MAX_FALL_SPEED := EqWorldSpace.EQ_MAX_FALL_SPEED
const EQ_JUMP_VELOCITY := EqWorldSpace.EQ_JUMP_VELOCITY
const EQ_SWIM_SPEED := 35.0
const EQ_SWIM_BUOYANCY_RATE := 30.0
const EQ_SWIM_FLOAT_DEPTH := 2.0
const WATER_SURFACE_MARGIN := 0.05
const CAMERA_TURN_SPEED := 2.45
const CAMERA_PITCH_SPEED := 1.55
const CAMERA_OFFSET := Vector3(0.0, 4.7, 10.5)
const CAMERA_COLLISION_MARGIN := 0.35
const PLAYER_ATTACK_ANIMATION_SECONDS := 0.45
const NPC_LONG_PRESS_SECONDS := 0.55
const NPC_LONG_PRESS_CANCEL_DISTANCE := 28.0
const CHARACTER_MODEL_FACING_OFFSET := PI * 0.5

var zone_definition_loader: ZoneDefinitionLoader
var current_zone_key := ""
var content_service: ContentService
var persistence_service: PersistenceService
var simulation_clock: SimulationClock
var simulation_rng: SimulationRng
var simulation: Simulation
var view_registry := EntityViewRegistry.new()
var npc_behavior_system := SimpleNpcBehaviorSystem.new()
var autonomous_entity_ids: Array[String] = []

var zone: Dictionary
var zone_world_space: ZoneWorldSpace
var zone_host: ZoneHost
var zone_presentation_host: ZonePresentationHost
var active_zone_presentation: ActiveZonePresentation
var zone_runtime_state: ZoneRuntimeState
var zone_state_store: ZoneStateStore
var zone_spawn_resolver: ZoneSpawnResolver
var resolved_zone_spawns: Dictionary = {}
var player: CharacterBody3D
var player_visual: Node3D
var player_animator: AnimationPlayer
var npc: Node3D
var camera_pivot: Node3D
var camera: Camera3D
var hud: Control
var ui_layer: CanvasLayer
var merchant_panel: MerchantBrowsePanel
var merchant_interaction_popup: MerchantInteractionPopup
var zone_npc_population: ZoneNpcPopulation
var zone_spawn_entity_ids: Dictionary = {}

var selected_zone_target: Dictionary = {}
var selected_entity_id := ""
var npc_press_touch := -1
var npc_press_position := Vector2.ZERO
var npc_press_target: Dictionary = {}
var npc_press_elapsed := 0.0
var auto_attack_enabled := false
var player_action_animation_remaining := 0.0
var joystick_vector := Vector2.ZERO
var look_stick := Vector2.ZERO
var jump_held := false
var jump_pressed := false
var status_text := "Explore."
var autosave_elapsed := 0.0
var pending_save_read: Dictionary = {}

var object_scenes: Dictionary[String, PackedScene] = {}
var normalized_prop_meshes: Dictionary[Mesh, ArrayMesh] = {}
var two_sided_prop_materials: Dictionary[Material, BaseMaterial3D] = {}
var prop_collision_shapes: Dictionary[Mesh, Shape3D] = {}
var zone_prop_instance_count := 0
var zone_prop_mesh_count := 0
var zone_prop_collision_count := 0
var zone_prop_collision_shape_count := 0
var zone_prop_load_failures: Array[String] = []
var authored_water_triangles: Array[PackedVector3Array] = []


func _ready() -> void:
	EqWorldSpace.run_contract_tests()
	_configure_services()
	_configure_simulation()
	_prepare_save_read()
	_resolve_zone_spawns()
	_prepare_zone_presentation()
	_build_world()
	_build_zone_objects()
	_build_npc_population()
	_build_player()
	if simulation.entity(TRAINING_ENTITY_ID) != null:
		_build_npc()
	_build_camera()
	_build_hud()
	_restore_simulation_save()
	_apply_domain_state_to_views()
	_update_hud()


func _configure_services() -> void:
	zone_definition_loader = ZoneDefinitionLoader.new()

	assert(
		zone_definition_loader.load_catalog(),
		zone_definition_loader.last_error
	)

	current_zone_key = (
		zone_definition_loader.default_zone_key()
	)

	assert(
		not current_zone_key.is_empty(),
		"Zone catalog has no default zone key"
	)

	zone = zone_definition_loader.load_zone(
		current_zone_key
	)

	assert(
		not zone.is_empty(),
		zone_definition_loader.last_error
	)

	var zone_definition_path := (
		zone_definition_loader.zone_definition_path(
			current_zone_key
		)
	)

	assert(
		not zone_definition_path.is_empty(),
		zone_definition_loader.last_error
	)

	var content_paths: Dictionary = (
		GLOBAL_CONTENT_PATHS.duplicate(true)
	)

	content_paths["zone"] = (
		zone_definition_path
	)

	var zone_content_paths: Dictionary = (
		zone_definition_loader.runtime_content_paths(
			zone
		)
	)

	for content_key_variant in zone_content_paths:
		var content_key := str(
			content_key_variant
		)
		content_paths[content_key] = str(
			zone_content_paths[
				content_key_variant
			]
		)

	content_service = ContentService.new()
	content_service.configure(
		content_paths
	)

	assert(
		content_service.load_all(),
		content_service.last_error
	)

	# ContentService owns the runtime copy after all cross-dataset validation
	# succeeds. The loader remains responsible for catalog selection and schema
	# validation.
	zone = content_service.zone_definition(
		current_zone_key
	)

	zone_world_space = ZoneWorldSpace.new(
		zone
	)

	assert(
		zone_world_space.is_valid(),
		zone_world_space.last_error
	)

	status_text = "Explore %s." % str(
		zone.get(
			"display_name",
			zone.get(
				"id",
				"the zone"
			)
		)
	)

	simulation_clock = SimulationClock.new()
	var runtime_seed := int(
		simulation_clock.real_world_unix_ms()
		& 0x7fffffff
	)
	simulation_rng = SimulationRng.new(
		runtime_seed
	)
	persistence_service = PersistenceService.new(
		PersistenceService.DEFAULT_SAVE_PATH,
		simulation_clock
	)


func _configure_simulation() -> void:
	zone_host = ZoneHost.new()
	assert(
		zone_host.prepare_definition(
			zone,
			false
		),
		zone_host.last_error
	)
	zone_runtime_state = (
		zone_host.active_runtime_state
	)
	zone_state_store = (
		zone_host.state_store
	)
	zone_spawn_resolver = (
		zone_host.spawn_resolver
	)

	var player_fixture := content_service.player_fixture_definition()
	simulation = Simulation.new(simulation_clock, simulation_rng)
	simulation.configure_player_state(
		PLAYER_ENTITY_ID,
		content_service.item_definitions(),
		int(player_fixture.get("inventory_capacity", 8)),
		zone.get("progression", {}),
		content_service.faction_catalog(),
		player_fixture.get("identity", {}),
		player_fixture.get("inventory_item_aliases", {})
	)
	var player_identity: Dictionary = player_fixture.get(
		"identity",
		{}
	)

	var player_entity := EntityFactory.create({
		"entity_id": PLAYER_ENTITY_ID,
		"definition_id": str(player_fixture.get("key", "fixture:player:local")),
		"kind": "player",
		"display_name": "Player",
		"race_id": int(player_identity.get("race_id", 0)),
		"race_ref": str(player_identity.get("race_ref", "")),
		"gender_id": int(player_identity.get("gender_id", 0)),
		"class_id": int(player_identity.get("class_id", 0)),
		"class_ref": str(player_identity.get("class_ref", "")),
		"level": simulation.progression.level,
		"base_stats": player_fixture.get("base_stats", {}).duplicate(true),
		"derived_stats": {},
		"spawn_position": _array_to_vector3(zone.get("player_spawn", [0.0, 0.0, 0.0])),
		"combat_size": float(player_fixture.get("combat_size", 7.0)),
		"max_health": float(player_fixture.get("max_health", 100.0)),
		"max_mana": float(player_fixture.get("max_mana", 0.0)),
		"max_endurance": float(player_fixture.get("max_endurance", 0.0)),
		"combat_enabled": true,
		"hostile": false,
		"death_delay_seconds": float(zone.get("player_respawn_seconds", 2.5)),
		"respawn_seconds": 0.0,
		"faction_identity": {
			"kind": "player_standings",
		},
		"inventory_attachment": {
			"kind": "simulation_inventory",
			"owner_entity_id": PLAYER_ENTITY_ID,
		},
		"equipment_attachment": {
			"kind": "reserved",
			"owner_entity_id": PLAYER_ENTITY_ID,
		},
		"controller_attachment": {
			"kind": "local_player",
		},
		"appearance": player_fixture.get(
			"appearance",
			{}
		).duplicate(true),
		"metadata": {
			"identity": player_fixture.get("identity", {}).duplicate(true),
			"evidence": str(player_fixture.get("evidence", "temporary_fixture_default")),
		},
	})
	simulation.add_entity(player_entity, true, false)
	if bool(zone.get("enable_training_npc", false)):
		simulation.add_entity(EntityFactory.create(_training_entity_definition()), true, false)
		autonomous_entity_ids.append(TRAINING_ENTITY_ID)
	_restore_default_player_target()
	simulation.drain_events()


func _restore_default_player_target() -> void:
	if simulation == null:
		return

	var training := simulation.entity(
		TRAINING_ENTITY_ID
	)

	if (
		training != null
		and training.lifecycle
		!= GameplayEntity.Lifecycle.REMOVED
	):
		simulation.set_target(
			PLAYER_ENTITY_ID,
			TRAINING_ENTITY_ID
		)
		return

	simulation.clear_target(
		PLAYER_ENTITY_ID
	)

func _training_entity_definition() -> Dictionary:
	var spawn := _spawn_data()
	var archetype: Dictionary = zone.get("npc_archetypes", {}).get(str(spawn.get("archetype", "")), {})
	return {
		"entity_id": TRAINING_ENTITY_ID,
		"definition_id": str(archetype.get("key", "fixture:npc:training_spark")),
		"kind": "npc",
		"display_name": str(archetype.get("name", "Training Spark")),
		"level": maxi(1, int(archetype.get("level", 1))),
		"base_stats": {},
		"derived_stats": {},
		"spawn_position": _array_to_vector3(spawn.get("position", [0.0, 0.0, 0.0])),
		"combat_size": float(archetype.get("combat_size", 1.0)),
		"max_health": float(archetype.get("max_health", 1.0)),
		"max_mana": 0.0,
		"max_endurance": 0.0,
		"combat_enabled": true,
		"hostile": true,
		"death_delay_seconds": float(archetype.get("death_delay_seconds", 0.0)),
		"respawn_seconds": float(spawn.get("respawn_seconds", -1.0)),
		"rewards": archetype.get("rewards", {}).duplicate(true),
		"controller_attachment": {
			"kind": "simple_npc_behavior",
			"behavior": archetype.get("behavior", {}).duplicate(true),
			"combat_profile": archetype.get("combat", {}).duplicate(true),
		},
		"appearance": {
			"kind": "procedural_training_fixture",
		},
		"metadata": {
			"evidence": str(archetype.get("evidence", "temporary_fixture_default")),
		},
	}


func _process(delta: float) -> void:
	player_action_animation_remaining = maxf(0.0, player_action_animation_remaining - delta)
	_sync_domain_from_views()
	simulation.advance(delta)
	_consume_simulation_events()
	_update_auto_attack()
	_update_simulation_npcs(delta)
	_consume_simulation_events()
	_update_lifecycle_status()
	_update_camera(delta)
	_update_npc_long_press(delta)
	_update_hud()
	autosave_elapsed += delta
	if autosave_elapsed >= 2.0:
		autosave_elapsed = 0.0
		_save_game()


func _physics_process(delta: float) -> void:
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity == null or not player_entity.is_active():
		player.velocity = Vector3.ZERO
		if player_entity != null:
			player_entity.set_movement_state(
				GameplayEntity.MOVEMENT_IDLE
			)
		return
	_move_player(delta)


func _unhandled_input(event: InputEvent) -> void:
	if simulation != null and simulation.is_paused():
		return

	if event is InputEventKey and event.keycode == KEY_SPACE:
		_set_jump_held(event.pressed and not event.echo)
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_target_nearest_zone_npc()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		open_selected_merchant()
		return
	if event.is_action_pressed("attack"):
		toggle_auto_attack()
	if event is InputEventScreenTouch:
		hud.handle_touch(event.index, event.position, event.pressed)
		if event.pressed:
			var touch_target := _target_zone_npc_at_screen(event.position)
			var touch_actor := _zone_entity_for_target(
				touch_target
			)
			if (
				not touch_target.is_empty()
				and _actor_has_merchant_catalog(
					touch_actor
				)
			):
				npc_press_touch = event.index
				npc_press_position = event.position
				npc_press_target = touch_target
				npc_press_elapsed = 0.0
		else:
			_cancel_npc_long_press(event.index)
	if event is InputEventScreenDrag:
		hud.handle_drag(event.index, event.position, event.relative)
		if event.index == npc_press_touch and event.position.distance_to(npc_press_position) > NPC_LONG_PRESS_CANCEL_DISTANCE:
			_cancel_npc_long_press(event.index)
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		clear_save()
		get_tree().reload_current_scene()


func toggle_auto_attack() -> void:
	if simulation != null and simulation.is_paused():
		return
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity == null or not player_entity.is_active():
		return
	auto_attack_enabled = not auto_attack_enabled
	status_text = "Auto-attack enabled." if auto_attack_enabled else "Auto-attack disabled."


func _update_auto_attack() -> void:
	if not auto_attack_enabled:
		return
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity == null or not player_entity.is_active():
		return
	var profile := _attack_profile()
	if simulation.cooldown_remaining(PLAYER_ENTITY_ID, str(profile.get("cooldown_group", ""))) > 0.0:
		return
	var result := _request_player_attack(profile)
	if not bool(result.get("success", false)) and str(result.get("reason", "")) != "cooldown":
		status_text = _attack_failure_text(str(result.get("reason", "")), _current_target_entity_id())


func _request_player_attack(profile: Dictionary) -> Dictionary:
	var target_id := _current_target_entity_id()
	if target_id.is_empty():
		return {"success": false, "reason": "target_missing"}
	var target := simulation.entity(target_id)
	if target == null:
		return {"success": false, "reason": "target_missing"}
	var context := {
		"line_of_sight": _has_melee_line_of_sight(target.position) if bool(profile.get("requires_los", false)) else true,
	}
	return simulation.request_attack(PLAYER_ENTITY_ID, target_id, profile, context)


func try_training_strike() -> void:
	if simulation != null and simulation.is_paused():
		return
	var ability := _ability_definition("training_strike")
	if ability.is_empty():
		status_text = "Training Strike is unavailable."
		return
	var result := _request_player_attack(ability)
	if not bool(result.get("success", false)):
		status_text = _attack_failure_text(str(result.get("reason", "")), _current_target_entity_id())


func _attack_failure_text(reason: String, target_id: String) -> String:
	var target := simulation.entity(target_id)
	var target_name := target.display_name if target != null else "target"
	match reason:
		"target_missing", "target_inactive":
			return "No hostile target."
		"attacker_inactive":
			return "You cannot attack right now."
		"target_combat_disabled":
			return "%s is targeted. Source combat data is disabled pending review." % target_name
		"target_not_hostile":
			return "%s is not a hostile target." % target_name
		"ability_unavailable":
			return "That ability is unavailable to your class or level."
		"cooldown":
			return "That attack is recovering."
		"out_of_range":
			return "Move closer to attack."
		"not_facing":
			return "Face %s to attack." % target_name
		"line_of_sight":
			return "Your line of sight is blocked."
	return "The attack cannot be performed."


func _class_definition() -> Dictionary:
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	var class_id := (
		player_entity.class_id
		if player_entity != null
		else int(simulation.player_identity.get("class_id", 1))
	)
	return content_service.player_class_catalog().get("classes", {}).get(str(class_id), {})


func _class_display_name() -> String:
	return str(_class_definition().get("display_name", "Unknown"))


func _attack_profile() -> Dictionary:
	return _class_definition().get("attack_profile", {}).duplicate(true)


func _ability_definition(ability_id: String) -> Dictionary:
	return content_service.player_class_catalog().get("abilities", {}).get(ability_id, {}).duplicate(true)


func _has_melee_line_of_sight(target_position: Vector3) -> bool:
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity == null:
		return false
	return _has_world_line_of_sight(
		player_entity.position + Vector3.UP * (player_entity.combat_size * 0.5),
		target_position + Vector3.UP * 0.7
	)


func _has_world_line_of_sight(origin: Vector3, destination: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, destination, PLAYER_WORLD_COLLISION_MASK, [player.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _sync_domain_from_views() -> void:
	var player_entity := simulation.entity(
		PLAYER_ENTITY_ID
	)

	if (
		player_entity != null
		and player_entity.lifecycle in [
			GameplayEntity.Lifecycle.ACTIVE,
			GameplayEntity.Lifecycle.DYING,
		]
	):
		view_registry.sync_to_domain(
			player_entity
		)

	var training_entity := simulation.entity(
		TRAINING_ENTITY_ID
	)

	if (
		training_entity != null
		and training_entity.is_active()
	):
		view_registry.sync_to_domain(
			training_entity
		)

	if zone_npc_population == null:
		return

	for spawn2_variant in (
		zone_spawn_entity_ids
	):
		var spawn2_id := int(
			spawn2_variant
		)
		var entity_id := str(
			zone_spawn_entity_ids[
				spawn2_variant
			]
		)
		var actor := simulation.entity(
			entity_id
		)

		if (
			actor == null
			or not actor.is_active()
		):
			continue

		# Zone NPC patrol remains a presentation
		# compatibility path. Mirror its pose
		# into the generic actor contract.
		view_registry.sync_to_domain(
			actor
		)

		var velocity := (
			zone_npc_population
			.movement_velocity_for_spawn(
				spawn2_id
			)
		)
		var planar_speed_squared := (
			Vector2(
				velocity.x,
				velocity.z
			)
			.length_squared()
		)

		actor.set_movement_state(
			GameplayEntity.MOVEMENT_MOVING
			if planar_speed_squared > 0.0001
			else GameplayEntity.MOVEMENT_IDLE,
			velocity
		)

func _consume_simulation_events() -> void:
	for event_variant in simulation.drain_events():
		var event := event_variant as GameplayEvent
		if event == null:
			continue
		match event.type:
			GameplayEvent.Type.ATTACK_PERFORMED:
				if event.source_entity_id == PLAYER_ENTITY_ID:
					_play_player_animation("attack")
					player_action_animation_remaining = PLAYER_ATTACK_ANIMATION_SECONDS
					status_text = "You attack %s." % _entity_display_name(event.target_entity_id)
				else:
					status_text = "%s hits you." % _entity_display_name(event.source_entity_id)
			GameplayEvent.Type.DEATH:
				if event.target_entity_id == PLAYER_ENTITY_ID:
					auto_attack_enabled = false
					player.velocity = Vector3.ZERO
					_play_player_animation("death")
					status_text = "You were defeated."
				else:
					status_text = "%s defeated." % _entity_display_name(event.target_entity_id)
			GameplayEvent.Type.ITEM_GAINED:
				var item_key := str(event.data.get("item_key", ""))
				var item := content_service.item_definition(item_key)
				status_text = "Looted %s ×%d." % [str(item.get("name", item_key)), int(event.data.get("quantity", 0))]
			GameplayEvent.Type.XP_AWARDED:
				status_text = "Gained %d XP." % int(event.data.get("amount", 0))
			GameplayEvent.Type.LEVEL_CHANGED:
				status_text = "Level %d reached!" % int(event.data.get("level", simulation.progression.level))
			GameplayEvent.Type.SPAWN:
				var spawned := simulation.entity(event.source_entity_id)
				if spawned != null:
					view_registry.apply_from_domain(spawned)
				if event.source_entity_id == PLAYER_ENTITY_ID:
					player.velocity = Vector3.ZERO
					player.reset_physics_interpolation()
					_play_player_animation("idle")
					status_text = "You recover at the clearing entrance."
				elif event.source_entity_id == TRAINING_ENTITY_ID:
					status_text = "The Training Spark has returned."
			GameplayEvent.Type.DESPAWN:
				view_registry.set_visible(event.source_entity_id, false)


func _update_lifecycle_status() -> void:
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity != null and player_entity.lifecycle == GameplayEntity.Lifecycle.DYING:
		status_text = "You were defeated — respawning in %.0f." % ceil(player_entity.time_until_death_completion(simulation_clock.now_seconds()))


func _entity_display_name(entity_id: String) -> String:
	var target := simulation.entity(entity_id)
	return target.display_name if target != null else "Unknown"


func _current_target_entity_id() -> String:
	if simulation == null:
		return ""

	var player_entity := simulation.entity(
		PLAYER_ENTITY_ID
	)

	if player_entity == null:
		return ""

	return player_entity.target_entity_id

func _move_player(delta: float) -> void:
	var keyboard := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input := joystick_vector if joystick_vector.length() > 0.05 else keyboard
	var water_surface: Variant = _water_surface_at(player.global_position)
	var swimming := water_surface != null and player.global_position.y < float(water_surface) - WATER_SURFACE_MARGIN
	var direction := Vector3.ZERO
	if input.length() > 0.05:
		var forward := -camera_pivot.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera_pivot.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		direction = (right * input.x + forward * input.y).normalized()
	player.rotation.y = camera_pivot.rotation.y

	var movement_speed := EQ_SWIM_SPEED if swimming else PLAYER_RUN_SPEED
	player.velocity.x = direction.x * movement_speed
	player.velocity.z = direction.z * movement_speed
	if swimming:
		_apply_swim_vertical_motion(delta, float(water_surface), input)
	elif jump_pressed and player.is_on_floor():
		player.velocity.y = EQ_JUMP_VELOCITY
	elif player.is_on_floor():
		player.velocity.y = -1.0
	else:
		player.velocity.y = maxf(player.velocity.y - EQ_GRAVITY * delta, -EQ_MAX_FALL_SPEED)
	var horizontal_motion := Vector3(direction.x, 0.0, direction.z) * movement_speed * delta
	var may_swim_step := swimming and player.velocity.y <= 0.0
	var stepped_up := direction != Vector3.ZERO and (player.is_on_floor() or may_swim_step) and _try_step_up(horizontal_motion)
	if not stepped_up:
		player.move_and_slide()
	_update_locomotion_animation(swimming)
	_clamp_player_to_zone_bounds()

	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity != null:
		var actual_velocity := player.get_real_velocity()

		if swimming:
			player_entity.set_movement_state(
				GameplayEntity.MOVEMENT_SWIMMING,
				actual_velocity
			)
		elif not player.is_on_floor():
			player_entity.set_movement_state(
				GameplayEntity.MOVEMENT_AIRBORNE,
				actual_velocity
			)
		elif Vector2(
			actual_velocity.x,
			actual_velocity.z
		).length() > 0.01:
			player_entity.set_movement_state(
				GameplayEntity.MOVEMENT_MOVING,
				actual_velocity
			)
		else:
			player_entity.set_movement_state(
				GameplayEntity.MOVEMENT_IDLE
			)

	jump_pressed = false


func _update_locomotion_animation(swimming: bool) -> void:
	if player_action_animation_remaining > 0.0:
		return
	var actual_velocity := player.get_real_velocity()
	var horizontal_speed := Vector2(actual_velocity.x, actual_velocity.z).length()
	if swimming:
		_play_water_animation(horizontal_speed > 0.01 or absf(actual_velocity.y) > 0.01)
		return
	if horizontal_speed <= 0.01:
		_play_player_animation("idle")
	elif horizontal_speed <= WALK_RUN_THRESHOLD:
		_play_player_animation("walk")
	elif player_animator != null and player_animator.has_animation("run"):
		_play_player_animation("run")
	else:
		_play_player_animation("walk")


func _set_jump_held(pressed: bool) -> void:
	if simulation != null and simulation.is_paused():
		return
	if pressed and not jump_held:
		jump_pressed = true
	jump_held = pressed


func _apply_swim_vertical_motion(delta: float, surface: float, input: Vector2) -> void:
	var requested_vertical := 0.0
	if jump_held:
		requested_vertical = EQ_SWIM_SPEED
	elif absf(input.y) > 0.05:
		requested_vertical = -camera_pivot.global_transform.basis.z.y * input.y * EQ_SWIM_SPEED
	if requested_vertical > 0.0:
		requested_vertical = minf(requested_vertical, (surface - WATER_SURFACE_MARGIN - player.global_position.y) / delta)
	if absf(requested_vertical) > 0.001:
		player.velocity.y = requested_vertical
		return
	var float_target := surface - EQ_SWIM_FLOAT_DEPTH
	if player.global_position.y < float_target:
		player.velocity.y = minf(EQ_SWIM_BUOYANCY_RATE, (float_target - player.global_position.y) / delta)
	else:
		player.velocity.y = 0.0


func _try_step_up(horizontal_motion: Vector3) -> bool:
	if horizontal_motion.length_squared() <= 0.000001:
		return false
	var start := player.global_transform
	if not player.test_move(start, horizontal_motion):
		return false
	if player.test_move(start, Vector3.UP * PLAYER_STEP_UP_HEIGHT):
		return false
	var raised := start
	raised.origin += Vector3.UP * PLAYER_STEP_UP_HEIGHT
	if player.test_move(raised, horizontal_motion):
		return false
	player.global_transform = raised
	player.move_and_collide(horizontal_motion)
	var landing := player.move_and_collide(Vector3.DOWN * (PLAYER_STEP_UP_HEIGHT + PLAYER_FLOOR_SNAP_DISTANCE))
	if landing == null or landing.get_normal().dot(Vector3.UP) < cos(PLAYER_MAX_SLOPE_ANGLE):
		player.global_transform = start
		return false
	player.velocity.y = -1.0
	return true


func _clamp_player_to_zone_bounds() -> void:
	var limit := float(zone.get("bounds", {}).get("half_extent", 18.0)) - 0.8
	player.global_position.x = clampf(player.global_position.x, -limit, limit)
	player.global_position.z = clampf(player.global_position.z, -limit, limit)


func _update_simulation_npcs(delta: float) -> void:
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity == null:
		return
	for entity_id in autonomous_entity_ids:
		var actor := simulation.entity(entity_id)
		if actor == null:
			continue
		var profile: Dictionary = actor.controller_attachment.get(
			"combat_profile",
			actor.metadata.get("combat_profile", {})
		)
		var context := {"line_of_sight": true}
		if actor.is_active() and player_entity.is_active() and bool(profile.get("requires_los", false)):
			context["line_of_sight"] = _has_world_line_of_sight(
				actor.position + Vector3.UP * (actor.combat_size * 0.5),
				player_entity.position + Vector3.UP * (player_entity.combat_size * 0.5)
			)
		npc_behavior_system.update_entity(simulation, entity_id, PLAYER_ENTITY_ID, delta, context)
		view_registry.apply_from_domain(actor)
		var actor_view := view_registry.view_for(entity_id)
		if actor_view != null and actor.facing.length_squared() > 0.000001:
			actor_view.look_at(actor_view.global_position + actor.facing, Vector3.UP)


func _update_camera(delta: float) -> void:
	camera_pivot.global_position = player.global_position
	camera_pivot.rotation.y -= look_stick.x * CAMERA_TURN_SPEED * delta
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x + look_stick.y * CAMERA_PITCH_SPEED * delta,
		-0.75,
		-0.2
	)
	_update_camera_collision()


func _update_camera_collision() -> void:
	var origin := camera_pivot.global_position + Vector3.UP * 1.35
	var desired := camera_pivot.to_global(CAMERA_OFFSET)
	var query := PhysicsRayQueryParameters3D.create(origin, desired, PLAYER_WORLD_COLLISION_MASK, [player.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		camera.position = CAMERA_OFFSET
		camera.look_at(_camera_focus_position(), Vector3.UP)
		return
	var total_distance := origin.distance_to(desired)
	var clear_distance := maxf(0.5, origin.distance_to(hit.position) - CAMERA_COLLISION_MARGIN)
	camera.global_position = origin.lerp(desired, clear_distance / total_distance)
	camera.look_at(_camera_focus_position(), Vector3.UP)


func _camera_focus_position() -> Vector3:
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	var height := player_entity.combat_size if player_entity != null else 7.0
	return player.global_position + Vector3.UP * (height * 0.5)


func _resolve_zone_spawns() -> void:
	assert(
		zone_host != null,
		"ZoneHost must exist before spawn resolution"
	)
	assert(
		zone_host.resolve_spawns(
			content_service.npc_dataset()
		),
		zone_host.last_error
	)

	# Compatibility aliases remain temporarily while presentation/world
	# construction is migrated out of main.gd in later slices.
	zone_runtime_state = (
		zone_host.active_runtime_state
	)
	zone_state_store = (
		zone_host.state_store
	)
	zone_spawn_resolver = (
		zone_host.spawn_resolver
	)
	resolved_zone_spawns = (
		zone_host.resolved_spawns
	)



func _prepare_zone_presentation() -> void:
	assert(
		zone_host != null,
		"ZoneHost must exist before presentation is prepared"
	)
	assert(
		zone_host.is_prepared(),
		"ZoneHost must have an active runtime before presentation is prepared"
	)

	if zone_presentation_host == null:
		zone_presentation_host = (
			ZonePresentationHost.new()
		)
		zone_presentation_host.name = (
			"ZonePresentationHost"
		)
		add_child(
			zone_presentation_host
		)

	active_zone_presentation = (
		zone_presentation_host.begin_zone(
			current_zone_key
		)
	)

	assert(
		active_zone_presentation != null,
		"Unable to create active-zone presentation root"
	)
	assert(
		active_zone_presentation.zone_key
		== current_zone_key,
		"Active-zone presentation key does not match current zone"
	)

	# These are presentation-build caches, not durable zone state. Reset them
	# whenever a fresh active-zone root is created so no future zone can inherit
	# geometry/water/prop artifacts from the previously active zone.
	object_scenes.clear()
	normalized_prop_meshes.clear()
	two_sided_prop_materials.clear()
	prop_collision_shapes.clear()

	zone_prop_instance_count = 0
	zone_prop_mesh_count = 0
	zone_prop_collision_count = 0
	zone_prop_collision_shape_count = 0
	zone_prop_load_failures.clear()
	authored_water_triangles.clear()


func _build_world() -> void:
	var geometry_path := str(
		zone.get(
			"geometry_scene",
			""
		)
	)

	if not geometry_path.is_empty():
		var geometry_scene := (
			load(
				geometry_path
			) as PackedScene
		)

		assert(
			geometry_scene != null,
			"Unable to import zone geometry: %s"
			% geometry_path
		)

		var geometry := (
			geometry_scene.instantiate()
		)
		geometry.name = "ZoneGeometry"
		geometry.scale = (
			Vector3.ONE
			* float(
				zone.get(
					"geometry_scale",
					1.0
				)
			)
		)

		active_zone_presentation.add_child(
			geometry
		)
		_build_zone_collision(
			geometry
		)

		if _zone_water_enabled():
			assert(
				not authored_water_triangles.is_empty(),
				"Zone %s declares authored water, but no water surface was found"
				% current_zone_key
			)
	else:
		_build_placeholder_ground()

	_build_zone_environment()


func _build_zone_environment() -> void:
	var definition := (
		_zone_environment_definition()
	)

	var light_variant: Variant = (
		definition.get(
			"directional_light",
			{}
		)
	)

	if (
		light_variant is Dictionary
		and not (
			light_variant as Dictionary
		).is_empty()
	):
		var light_definition: Dictionary = (
			light_variant as Dictionary
		)

		var light := DirectionalLight3D.new()
		light.rotation_degrees = (
			_vector3_from_zone_value(
				light_definition.get(
					"rotation_degrees",
					[]
				),
				"environment.directional_light.rotation_degrees"
			)
		)
		light.light_energy = float(
			light_definition.get(
				"energy",
				1.0
			)
		)
		active_zone_presentation.add_child(
			light
		)

	var background_color := str(
		definition.get(
			"background_color",
			""
		)
	)
	var ambient_color := str(
		definition.get(
			"ambient_light_color",
			""
		)
	)

	assert(
		not background_color.is_empty(),
		"Zone environment requires background_color"
	)
	assert(
		not ambient_color.is_empty(),
		"Zone environment requires ambient_light_color"
	)

	var environment := WorldEnvironment.new()
	var env := Environment.new()

	env.background_mode = (
		Environment.BG_COLOR
	)
	env.background_color = Color(
		background_color
	)
	env.ambient_light_source = (
		Environment.AMBIENT_SOURCE_COLOR
	)
	env.ambient_light_color = Color(
		ambient_color
	)
	env.ambient_light_energy = float(
		definition.get(
			"ambient_light_energy",
			0.0
		)
	)

	environment.environment = env
	active_zone_presentation.add_child(
		environment
	)


func _zone_environment_definition() -> Dictionary:
	var environment_variant: Variant = (
		zone.get(
			"environment",
			{}
		)
	)

	assert(
		environment_variant is Dictionary,
		"Zone environment must be a dictionary"
	)

	return (
		environment_variant as Dictionary
	)


func _zone_water_definition() -> Dictionary:
	var water_variant: Variant = (
		_zone_environment_definition().get(
			"water",
			{}
		)
	)

	if not water_variant is Dictionary:
		return {}

	return (
		water_variant as Dictionary
	)


func _zone_water_enabled() -> bool:
	return bool(
		_zone_water_definition().get(
			"enabled",
			false
		)
	)


func _vector3_from_zone_value(
	value: Variant,
	field_name: String
) -> Vector3:
	assert(
		value is Array,
		"%s must be a three-component array"
		% field_name
	)

	var components: Array = value

	assert(
		components.size() == 3,
		"%s must contain exactly three components"
		% field_name
	)

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


func _build_zone_collision(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_add_zone_terrain_collision(node)
	for child in node.get_children():
		_build_zone_collision(child)


func _add_zone_terrain_collision(mesh_instance: MeshInstance3D) -> void:
	var terrain_faces := PackedVector3Array()
	for surface_index in mesh_instance.mesh.get_surface_count():
		if mesh_instance.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if _surface_is_zone_water(
			mesh_instance,
			surface_index
		):
			if _surface_defines_zone_water_surface(
				mesh_instance,
				surface_index
			):
				_register_water_surface(
					vertices,
					indices,
					mesh_instance.global_transform
				)
		else:
			_append_triangle_faces(
				terrain_faces,
				vertices,
				indices
			)
	if terrain_faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(terrain_faces)
	_add_collision_shape(mesh_instance, shape, COLLISION_LAYER_TERRAIN, "TerrainCollision")


func _surface_is_zone_water(
	mesh_instance: MeshInstance3D,
	surface_index: int
) -> bool:
	if _surface_material_matches_zone_water(
		mesh_instance,
		surface_index
	):
		return true

	var fallback := (
		_matching_zone_water_fallback(
			mesh_instance
		)
	)

	if fallback.is_empty():
		return false

	return _zone_surface_index_list_contains(
		fallback.get(
			"water_surface_indices",
			[]
		),
		surface_index
	)


func _surface_defines_zone_water_surface(
	mesh_instance: MeshInstance3D,
	surface_index: int
) -> bool:
	var fallback := (
		_matching_zone_water_fallback(
			mesh_instance
		)
	)

	if not fallback.is_empty():
		return _zone_surface_index_list_contains(
			fallback.get(
				"surface_height_indices",
				[]
			),
			surface_index
		)

	# A zone without an index fallback may define ordinary water purely by
	# material identity. In that case the authored water surface itself
	# supplies swimming height.
	return _surface_material_matches_zone_water(
		mesh_instance,
		surface_index
	)


func _zone_surface_index_list_contains(
	indices_variant: Variant,
	surface_index: int
) -> bool:
	if not indices_variant is Array:
		return false

	for configured_index_variant in (
		indices_variant as Array
	):
		if int(
			configured_index_variant
		) == surface_index:
			return true

	return false


func _surface_material_matches_zone_water(
	mesh_instance: MeshInstance3D,
	surface_index: int
) -> bool:
	var water := _zone_water_definition()

	if not bool(
		water.get(
			"enabled",
			false
		)
	):
		return false

	var patterns_variant: Variant = (
		water.get(
			"material_name_contains",
			[]
		)
	)

	if not patterns_variant is Array:
		return false

	var material := (
		mesh_instance.get_active_material(
			surface_index
		)
	)

	if material == null:
		return false

	var identifier := (
		material.resource_name
		+ " "
		+ material.resource_path
	).to_lower()

	for pattern_variant in (
		patterns_variant as Array
	):
		var pattern := str(
			pattern_variant
		).strip_edges().to_lower()

		if (
			not pattern.is_empty()
			and identifier.contains(
				pattern
			)
		):
			return true

	return false


func _matching_zone_water_fallback(
	mesh_instance: MeshInstance3D
) -> Dictionary:
	var fallbacks_variant: Variant = (
		_zone_water_definition().get(
			"surface_fallbacks",
			[]
		)
	)

	if not fallbacks_variant is Array:
		return {}

	var surface_count := (
		mesh_instance.mesh.get_surface_count()
	)

	for fallback_variant in (
		fallbacks_variant as Array
	):
		if not fallback_variant is Dictionary:
			continue

		var fallback: Dictionary = (
			fallback_variant as Dictionary
		)

		if int(
			fallback.get(
				"mesh_surface_count",
				-1
			)
		) == surface_count:
			return fallback

	return {}


func _register_water_surface(vertices: PackedVector3Array, indices: PackedInt32Array, transform: Transform3D) -> void:
	var faces := PackedVector3Array()
	_append_triangle_faces(faces, vertices, indices)
	for face_index in range(0, faces.size(), 3):
		var triangle := PackedVector3Array([
			transform * faces[face_index],
			transform * faces[face_index + 1],
			transform * faces[face_index + 2],
		])
		authored_water_triangles.append(triangle)


func _append_triangle_faces(destination: PackedVector3Array, vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	if indices.is_empty():
		for vertex_index in range(0, vertices.size() - 2, 3):
			destination.append(vertices[vertex_index])
			destination.append(vertices[vertex_index + 1])
			destination.append(vertices[vertex_index + 2])
		return
	for index_position in range(0, indices.size() - 2, 3):
		destination.append(vertices[indices[index_position]])
		destination.append(vertices[indices[index_position + 1]])
		destination.append(vertices[indices[index_position + 2]])


func _water_surface_at(world_position: Vector3) -> Variant:
	var highest_surface: Variant = null
	for triangle in authored_water_triangles:
		var a := triangle[0]
		var b := triangle[1]
		var c := triangle[2]
		var denominator := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(denominator) < 0.000001:
			continue
		var u := ((b.z - c.z) * (world_position.x - c.x) + (c.x - b.x) * (world_position.z - c.z)) / denominator
		var v := ((c.z - a.z) * (world_position.x - c.x) + (a.x - c.x) * (world_position.z - c.z)) / denominator
		var w := 1.0 - u - v
		if u < -0.0001 or v < -0.0001 or w < -0.0001:
			continue
		var surface := u * a.y + v * b.y + w * c.y
		if highest_surface == null or surface > float(highest_surface):
			highest_surface = surface
	return highest_surface


func _add_static_mesh_collision(mesh_instance: MeshInstance3D, layer: int, body_name: String) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	var shape := prop_collision_shapes.get(mesh) as Shape3D
	if shape == null:
		shape = mesh.create_trimesh_shape()
		if shape != null:
			prop_collision_shapes[mesh] = shape
			zone_prop_collision_shape_count += 1
	if shape == null:
		return
	_add_collision_shape(mesh_instance, shape, layer, body_name)
	zone_prop_collision_count += 1


func _add_collision_shape(mesh_instance: MeshInstance3D, shape: Shape3D, layer: int, body_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	body.add_child(collision_shape)
	mesh_instance.add_child(body)


func _build_placeholder_ground() -> void:
	var extent := float(zone.get("bounds", {}).get("half_extent", 18.0))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 2.0, extent * 2.0)
	ground.mesh = plane
	ground.material_override = _material(Color("355842"))
	active_zone_presentation.add_child(ground)
	for coordinate in [Vector3(-extent, 0.1, -extent), Vector3(extent, 0.1, -extent), Vector3(-extent, 0.1, extent), Vector3(extent, 0.1, extent)]:
		_add_marker(coordinate)


func _build_zone_objects() -> void:
	var instances_path := str(zone.get("object_instances", ""))
	var models_path := str(zone.get("object_model_directory", ""))
	if instances_path.is_empty() or models_path.is_empty():
		return
	# This file is a presentation-space placement manifest rather than gameplay
	# content. Gameplay JSON is loaded exclusively through ContentService.
	var file := FileAccess.open(instances_path, FileAccess.READ)
	if file == null:
		push_error("Unable to read zone object instances: %s" % instances_path)
		return
	var container := Node3D.new()
	container.name = "ZoneObjects"
	active_zone_presentation.add_child(container)
	var line_number := 0
	while not file.eof_reached():
		line_number += 1
		var values := file.get_csv_line()
		if values.is_empty() or values[0].is_empty() or values[0].begins_with("#"):
			continue
		assert(values.size() == 11, "Invalid zone object entry at line %d" % line_number)
		var model_name := values[0]
		var scene := _load_object_scene(models_path, model_name)
		if scene == null:
			zone_prop_load_failures.append(model_name)
			continue
		var placement := Node3D.new()
		placement.name = "%s_%d" % [model_name, line_number]
		placement.transform = Transform3D(
			zone_world_space.object_rotation_basis([
				float(values[4]),
				float(values[5]),
				float(values[6]),
			]),
			zone_world_space.object_position([
				float(values[1]),
				float(values[2]),
				float(values[3]),
			])
		)
		placement.scale = Vector3(
			float(values[7]),
			float(values[8]),
			float(values[9])
		)
		var object := scene.instantiate() as Node3D
		object.name = "Visual"
		placement.add_child(object)
		_bake_reflected_prop_meshes(object)
		_force_prop_materials_two_sided(object)
		container.add_child(placement)
		_build_object_collision(placement)
		zone_prop_instance_count += 1
	status_text = "Props: %d instances, %d mesh nodes, %d colliders (%d shared shapes), %d load failures." % [
		zone_prop_instance_count,
		zone_prop_mesh_count,
		zone_prop_collision_count,
		zone_prop_collision_shape_count,
		zone_prop_load_failures.size(),
	]
	print(status_text)


func _build_object_collision(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		zone_prop_mesh_count += 1
		_add_static_mesh_collision(node, COLLISION_LAYER_WORLD_OBJECTS, "ObjectCollision")
	for child in node.get_children():
		_build_object_collision(child)


func _load_object_scene(models_path: String, model_name: String) -> PackedScene:
	if object_scenes.has(model_name):
		return object_scenes[model_name]
	var path := "%s/%s.glb" % [models_path, model_name]
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Missing imported zone object model: %s" % path)
		return null
	object_scenes[model_name] = scene
	return scene


func _bake_reflected_prop_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null and node.transform.basis.determinant() < 0.0:
		var source_mesh: Mesh = node.mesh
		if not normalized_prop_meshes.has(source_mesh):
			normalized_prop_meshes[source_mesh] = _bake_mesh_transform(source_mesh, node.transform)
		node.mesh = normalized_prop_meshes[source_mesh]
		node.transform = Transform3D.IDENTITY
	for child in node.get_children():
		_bake_reflected_prop_meshes(child)


func _force_prop_materials_two_sided(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface_index in node.mesh.get_surface_count():
			var source_material: Material = node.get_active_material(surface_index)
			if source_material is BaseMaterial3D:
				if not two_sided_prop_materials.has(source_material):
					var prop_material := source_material.duplicate() as BaseMaterial3D
					prop_material.cull_mode = BaseMaterial3D.CULL_DISABLED
					two_sided_prop_materials[source_material] = prop_material
				node.set_surface_override_material(surface_index, two_sided_prop_materials[source_material])
	for child in node.get_children():
		_force_prop_materials_two_sided(child)


func _bake_mesh_transform(source_mesh: Mesh, mesh_transform: Transform3D) -> ArrayMesh:
	var baked_mesh := ArrayMesh.new()
	var normal_transform := mesh_transform.basis.inverse().transposed()
	var reverses_winding := mesh_transform.basis.determinant() < 0.0
	for surface_index in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in vertices.size():
			vertices[vertex_index] = mesh_transform * vertices[vertex_index]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for normal_index in normals.size():
			normals[normal_index] = (normal_transform * normals[normal_index]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
		if source_mesh.surface_get_primitive_type(surface_index) == Mesh.PRIMITIVE_TRIANGLES and reverses_winding:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for vertex_index in vertices.size():
					indices.append(vertex_index)
			for index_offset in range(0, indices.size() - 2, 3):
				var first_index := indices[index_offset]
				indices[index_offset] = indices[index_offset + 2]
				indices[index_offset + 2] = first_index
			arrays[Mesh.ARRAY_INDEX] = indices
		baked_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
		baked_mesh.surface_set_material(surface_index, source_mesh.surface_get_material(surface_index))
	return baked_mesh


func _build_player() -> void:
	var entity := simulation.entity(PLAYER_ENTITY_ID)
	assert(entity != null, "Player domain entity is required before presentation is built")
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = entity.position
	player.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	player.floor_max_angle = PLAYER_MAX_SLOPE_ANGLE
	player.floor_snap_length = PLAYER_FLOOR_SNAP_DISTANCE
	player.floor_constant_speed = true
	player.floor_stop_on_slope = true
	player.max_slides = 6
	player.safe_margin = PLAYER_SAFE_MARGIN
	player.collision_layer = 0
	player.collision_mask = PLAYER_WORLD_COLLISION_MASK
	add_child(player)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "PlayerCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_COLLISION_RADIUS
	capsule.height = entity.combat_size
	collision_shape.shape = capsule
	collision_shape.position.y = entity.combat_size * 0.5
	player.add_child(collision_shape)
	var player_model_path := str(
		entity.appearance.get(
			"model_path",
			"res://assets/imported/halas/characters/hlm_s0_h0.glb"
		)
	)
	var player_scene := load(player_model_path) as PackedScene
	assert(
		player_scene != null,
		"Missing player appearance model: %s" % player_model_path
	)
	player_visual = player_scene.instantiate() as Node3D
	player_visual.name = str(
		entity.appearance.get(
			"model_name",
			"HLMPlaceholder"
		)
	)
	player_visual.rotation.y = CHARACTER_MODEL_FACING_OFFSET
	player.add_child(player_visual)
	player_animator = _animation_player_below(player_visual)
	assert(player_animator != null, "HLM placeholder model has no AnimationPlayer")
	for clip in ["idle", "walk", "attack", "death", "swimming", "treading"]:
		assert(player_animator.has_animation(clip), "HLM placeholder is missing %s animation" % clip)
	player_animator.play("idle")
	player_animator.advance(0.0)
	_normalize_player_model_to_height(player_visual, entity.combat_size)
	_play_player_animation("idle")
	view_registry.bind(PLAYER_ENTITY_ID, player)


func _play_player_animation(clip: String) -> void:
	if player_animator == null or not player_animator.has_animation(clip):
		return
	if player_animator.current_animation != clip:
		player_animator.play(clip)


func _play_water_animation(moving: bool) -> void:
	var clip := "swimming" if moving else "treading"
	if player_animator != null and player_animator.has_animation(clip):
		_play_player_animation(clip)
	else:
		_play_player_animation("walk" if moving else "idle")


func _normalize_player_model_to_height(visual: Node3D, target_height: float) -> void:
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
	assert(raw_height > 0.001, "Unable to measure HLM placeholder height")
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


func _build_npc() -> void:
	var entity := simulation.entity(TRAINING_ENTITY_ID)
	if entity == null:
		return
	assert(
		active_zone_presentation != null,
		"Active-zone presentation is required before training NPC"
	)
	npc = Node3D.new()
	npc.name = "TrainingSpark"
	npc.position = entity.position
	active_zone_presentation.add_child(npc)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.65
	sphere.height = 1.3
	body.mesh = sphere
	body.material_override = _material(Color("ff9f43"), true)
	body.position.y = 0.7
	npc.add_child(body)
	view_registry.bind(TRAINING_ENTITY_ID, npc)
	view_registry.apply_from_domain(entity)


func _npc_presentation_profile() -> Dictionary:
	var profile_variant: Variant = (
		zone.get(
			"npc_presentation",
			{}
		)
	)

	if not profile_variant is Dictionary:
		return {}

	return (
		(
			profile_variant as Dictionary
		).duplicate(true)
	)


func _npc_presentation_context() -> Dictionary:
	var context := (
		_npc_presentation_profile()
	)

	context[
		"zone_key"
	] = current_zone_key

	if str(
		context.get(
			"runtime_id_namespace",
			""
		)
	).is_empty():
		context[
			"runtime_id_namespace"
		] = current_zone_key

	return context


func _zone_runtime_entity_id(
	spawn2_id: int
) -> String:
	return (
		ZoneEntityAdapter.runtime_entity_id(
			spawn2_id,
			_npc_presentation_context()
		)
	)


func _build_npc_population() -> void:
	var models_path := str(
		zone.get(
			"npc_model_directory",
			""
		)
	)
	var npc_content := (
		content_service.npc_dataset()
	)

	if npc_content.is_empty():
		return

	assert(
		active_zone_presentation != null,
		"Active-zone presentation is required before NPC population"
	)

	zone_npc_population = (
		ZoneNpcPopulation.new()
	)
	zone_npc_population.name = (
		"ZoneNpcPopulation"
	)
	zone_npc_population.configure(
		npc_content,
		models_path,
		resolved_zone_spawns,
		zone_runtime_state,
		zone_world_space,
		_npc_presentation_profile(),
		content_service.npc_default_heights()
	)
	active_zone_presentation.add_child(
		zone_npc_population
	)

	_register_zone_domain_actors()


func _register_zone_domain_actors() -> void:
	assert(
		zone_npc_population != null,
		"Zone NPC population must exist "
		+ "before actor registration"
	)

	zone_spawn_entity_ids.clear()

	var targets: Array[Dictionary] = (
		zone_npc_population.actor_targets()
	)
	var definitions: Array[Dictionary] = (
		ZoneEntityAdapter
		.neutral_definitions_from_targets(
			targets,
			_npc_presentation_context()
		)
	)

	assert(
		definitions.size()
		== targets.size(),
		"Zone actor definition count "
		+ "must match presentation roster"
	)

	for index in range(
		targets.size()
	):
		var target: Dictionary = (
			targets[index]
		)
		var definition: Dictionary = (
			definitions[index]
		)
		var spawn2_id := int(
			target.get(
				"spawn2_id",
				0
			)
		)

		assert(
			spawn2_id > 0,
			"Zone runtime actor "
			+ "requires a spawn2 ID"
		)

		var spawn_key := (
			ZoneSpawnResolver.spawn_key_for_id(
				spawn2_id
			)
		)
		var runtime_spawn_state := (
			zone_runtime_state.spawn_state(
				spawn_key
			)
		)

		assert(
			not runtime_spawn_state.is_empty(),
			"Presentation actor has no generic SpawnPoint state: %s"
			% spawn_key
		)

		var selected_definition_ref := str(
			runtime_spawn_state.get(
				"selected_definition_ref",
				""
			)
		)
		var actor_definition_ref := str(
			definition.get(
				"definition_id",
				""
			)
		)

		assert(
			not selected_definition_ref.is_empty()
			and actor_definition_ref
			== selected_definition_ref,
			"Presentation roster diverged from generic SpawnPoint selection "
			+ "%s: expected %s, got %s"
			% [
				spawn_key,
				selected_definition_ref,
				actor_definition_ref,
			]
		)

		var actor_metadata_variant: Variant = (
			definition.get(
				"metadata",
				{}
			)
		)
		var actor_metadata: Dictionary = (
			(
				actor_metadata_variant
				as Dictionary
			).duplicate(true)
			if actor_metadata_variant
			is Dictionary
			else {}
		)

		actor_metadata[
			"zone_ref"
		] = current_zone_key
		actor_metadata[
			"spawn_point_ref"
		] = spawn_key
		actor_metadata[
			"spawn_group_ref"
		] = str(
			runtime_spawn_state.get(
				"spawn_group_ref",
				""
			)
		)

		definition[
			"metadata"
		] = actor_metadata

		var entity_id := str(
			definition.get(
				"entity_id",
				""
			)
		)

		assert(
			not entity_id.is_empty(),
			"Zone runtime actor "
			+ "requires an entity ID"
		)
		assert(
			simulation.entity(
				entity_id
			) == null,
			"Duplicate zone runtime "
			+ "actor: %s"
			% entity_id
		)

		var entity := (
			EntityFactory.create(
				definition
			)
		)

		simulation.add_entity(
			entity,
			true,
			false
		)

		var node_variant: Variant = (
			target.get(
				"node"
			)
		)

		assert(
			node_variant is Node3D,
			"Zone runtime actor "
			+ "requires a view node"
		)

		view_registry.bind(
			entity_id,
			node_variant as Node3D
		)
		view_registry.sync_to_domain(
			entity
		)

		zone_runtime_state.occupy_spawn(
			spawn_key,
			entity_id,
			selected_definition_ref
		)

		var occupied_spawn_state := (
			zone_runtime_state.spawn_state(
				spawn_key
			)
		)

		assert(
			str(
				occupied_spawn_state.get(
					"state",
					""
				)
			) == ZoneRuntimeState.SPAWN_OCCUPIED
			and str(
				occupied_spawn_state.get(
					"occupant_entity_id",
					""
				)
			) == entity_id
			and str(
				occupied_spawn_state.get(
					"selected_definition_ref",
					""
				)
			) == selected_definition_ref,
			"Generic SpawnPoint occupancy was not recorded for %s"
			% spawn_key
		)

		zone_spawn_entity_ids[
			spawn2_id
		] = entity_id

func _release_active_zone_population() -> bool:
	if simulation == null:
		return false

	# Clear interaction state while presentation objects are still valid.
	# This also restores the persistent player's default target.
	_clear_zone_selection()

	npc_press_touch = -1
	npc_press_target = {}
	npc_press_elapsed = 0.0

	if merchant_interaction_popup != null:
		merchant_interaction_popup.queue_free()
		merchant_interaction_popup = null

	# Release the zone-local Training Spark before its presentation root dies.
	view_registry.unbind(
		TRAINING_ENTITY_ID
	)

	if simulation.entity(
		TRAINING_ENTITY_ID
	) != null:
		if not simulation.release_entity(
			TRAINING_ENTITY_ID
		):
			push_error(
				"Unable to release zone-local Training Spark"
			)
			return false

	autonomous_entity_ids.erase(
		TRAINING_ENTITY_ID
	)
	npc = null

	var unique_entity_ids: Dictionary = {}

	for entity_id_variant in (
		zone_spawn_entity_ids.values()
	):
		var entity_id := str(
			entity_id_variant
		)

		if not entity_id.is_empty():
			unique_entity_ids[
				entity_id
			] = true

	var entity_ids: Array[String] = []

	for entity_id_variant in (
		unique_entity_ids.keys()
	):
		entity_ids.append(
			str(
				entity_id_variant
			)
		)

	entity_ids.sort()

	for entity_id in entity_ids:
		# Binding removal happens before domain release while both identities
		# are still known to the unload coordinator.
		view_registry.unbind(
			entity_id
		)

		if simulation.entity(
			entity_id
		) == null:
			continue

		if not simulation.release_entity(
			entity_id
		):
			push_error(
				"Unable to release zone-owned runtime actor: %s"
				% entity_id
			)
			return false

	zone_spawn_entity_ids.clear()
	zone_npc_population = null

	return true


func _ensure_active_zone_fixture_entities() -> void:
	if not bool(
		zone.get(
			"enable_training_npc",
			false
		)
	):
		return

	if simulation.entity(
		TRAINING_ENTITY_ID
	) == null:
		simulation.add_entity(
			EntityFactory.create(
				_training_entity_definition()
			),
			true,
			false
		)

	if not autonomous_entity_ids.has(
		TRAINING_ENTITY_ID
	):
		autonomous_entity_ids.append(
			TRAINING_ENTITY_ID
		)


func _staged_content_service_for_zone(
	target_definition: Dictionary
) -> ContentService:
	var target_key := str(
		target_definition.get(
			"key",
			""
		)
	)

	var definition_path := (
		zone_definition_loader
		.zone_definition_path(
			target_key
		)
	)

	if definition_path.is_empty():
		push_error(
			zone_definition_loader.last_error
		)
		return null

	var paths := (
		content_service
		.configured_paths()
	)

	# These are the zone-owned document slots emitted by
	# ZoneDefinitionLoader.runtime_content_paths().
	for key in [
		"zone",
		"npcs",
		"merchants",
		"factions",
		"peq_items",
		"world_objects",
		"transitions",
	]:
		paths.erase(
			key
		)

	paths[
		"zone"
	] = definition_path

	var runtime_paths := (
		zone_definition_loader
		.runtime_content_paths(
			target_definition
		)
	)

	for key_variant in runtime_paths:
		paths[
			str(
				key_variant
			)
		] = runtime_paths[
			key_variant
		]

	var staged := ContentService.new()
	staged.configure(
		paths
	)

	if not staged.load_all():
		push_error(
			"Unable to stage target-zone content: %s"
			% staged.last_error
		)
		return null

	return staged


func _transition_placement(
	request: ZoneTransitionRequest,
	target_definition: Dictionary
) -> Dictionary:
	var payload := request.to_dict()
	var position_variant: Variant = (
		payload.get(
			"target_position",
			null
		)
	)

	var heading_eq := float(
		payload.get(
			"target_heading_eq",
			-1.0
		)
	)

	# Heading application is intentionally not silently approximated. The first
	# executable transition slice proves coordinate placement only.
	if heading_eq >= 0.0:
		return {
			"ok": false,
			"error":
				"Executable target_heading_eq support is not wired yet",
		}

	if position_variant is Vector3:
		return {
			"ok": true,
			"position":
				position_variant,
		}

	if (
		position_variant is Array
		and (
			position_variant
			as Array
		).size() >= 3
	):
		return {
			"ok": true,
			"position":
				_array_to_vector3(
					position_variant
				),
		}

	if not request.target_entry_ref.is_empty():
		return {
			"ok": false,
			"error":
				"Entry-reference transition execution requires a resolved entry dataset",
		}

	# A valid request normally supplies coordinates or an entry reference.
	# Retain the target spawn only as a defensive fixture fallback.
	return {
		"ok": true,
		"position":
			_array_to_vector3(
				target_definition.get(
					"player_spawn",
					[
						0.0,
						0.0,
						0.0,
					]
				)
			),
	}


func _place_persistent_player_after_transition(
	target_position: Vector3
) -> bool:
	var player_entity := simulation.entity(
		PLAYER_ENTITY_ID
	)

	if (
		player_entity == null
		or player == null
	):
		push_error(
			"Zone transition requires the persistent player actor and view"
		)
		return false

	# Death/respawn belongs to the newly active zone's configured player spawn;
	# the transition coordinate is only the immediate entry position.
	player_entity.spawn_position = (
		_array_to_vector3(
			zone.get(
				"player_spawn",
				[
					0.0,
					0.0,
					0.0,
				]
			)
		)
	)
	player_entity.position = (
		target_position
	)
	player_entity.clear_target()
	player_entity.set_movement_state(
		GameplayEntity.MOVEMENT_IDLE,
		Vector3.ZERO
	)

	player.global_position = (
		target_position
	)
	player.velocity = (
		Vector3.ZERO
	)
	player.reset_physics_interpolation()

	if camera_pivot != null:
		camera_pivot.global_position = (
			target_position
		)

	return true


func execute_zone_transition(
	request: ZoneTransitionRequest
) -> bool:
	if (
		request == null
		or not request.is_valid()
	):
		push_error(
			"Rejected invalid zone transition request"
		)
		return false

	if (
		not request.source_zone_key.is_empty()
		and request.source_zone_key
		!= current_zone_key
	):
		push_error(
			"Zone transition source mismatch: expected %s, got %s"
			% [
				current_zone_key,
				request.source_zone_key,
			]
		)
		return false

	var target_definition := (
		zone_definition_loader
		.load_zone(
			request.target_zone_key
		)
	)

	if target_definition.is_empty():
		push_error(
			zone_definition_loader.last_error
		)
		return false

	if str(
		target_definition.get(
			"key",
			""
		)
	) != request.target_zone_key:
		push_error(
			"Loaded transition target does not match request target"
		)
		return false

	var placement := (
		_transition_placement(
			request,
			target_definition
		)
	)

	if not bool(
		placement.get(
			"ok",
			false
		)
	):
		push_error(
			str(
				placement.get(
					"error",
					"Unable to resolve target placement"
				)
			)
		)
		return false

	# Stage and validate all target content and world-space configuration before
	# destroying the current active zone. A bad target therefore leaves the current zone
	# fully intact.
	var staged_content := (
		_staged_content_service_for_zone(
			target_definition
		)
	)

	if staged_content == null:
		return false

	var staged_zone := (
		staged_content.zone_definition(
			request.target_zone_key
		)
	)
	var staged_world_space := (
		ZoneWorldSpace.new(
			staged_zone
		)
	)

	if not staged_world_space.is_valid():
		push_error(
			staged_world_space.last_error
		)
		return false

	_sync_domain_from_views()

	if not _unload_active_zone():
		return false

	current_zone_key = (
		request.target_zone_key
	)
	content_service = (
		staged_content
	)
	zone = (
		staged_zone
	)
	zone_world_space = (
		staged_world_space
	)

	if not zone_host.prepare_definition(
		zone,
		false
	):
		push_error(
			zone_host.last_error
		)
		return false

	_resolve_zone_spawns()
	_prepare_zone_presentation()
	_build_world()
	_build_zone_objects()

	_ensure_active_zone_fixture_entities()
	_build_npc()
	_build_npc_population()

	if not _place_persistent_player_after_transition(
		placement.get(
			"position",
			Vector3.ZERO
		) as Vector3
	):
		return false

	_restore_default_player_target()

	auto_attack_enabled = false
	joystick_vector = Vector2.ZERO
	jump_held = false
	jump_pressed = false
	autosave_elapsed = 0.0

	status_text = (
		"Entered %s."
		% str(
			zone.get(
				"name",
				current_zone_key
			)
		)
	)

	return true


func _unload_active_zone() -> bool:
	if zone_host == null:
		return true

	# Runtime state must be captured while the transient actors still exist.
	# Patrol position, respawn state, spawn selection, and world-object state
	# therefore survive presentation teardown.
	if not zone_host.capture_active_zone():
		push_error(
			zone_host.last_error
		)
		return false

	if not _release_active_zone_population():
		return false

	# Presentation lifetime belongs to the presentation layer. Domain/view
	# bindings have already been released, so the complete zone scene can now
	# disappear before ZoneHost clears the active runtime references.
	if zone_presentation_host != null:
		zone_presentation_host.clear_zone()

	active_zone_presentation = null

	if not zone_host.unload_active_zone(
		false
	):
		push_error(
			zone_host.last_error
		)
		return false

	zone_runtime_state = null
	zone_spawn_resolver = null
	resolved_zone_spawns = {}

	return true


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = player.global_position
	camera_pivot.rotation.x = -0.42
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.position = CAMERA_OFFSET
	camera.current = true
	camera_pivot.add_child(camera)


func _build_hud() -> void:
	hud = preload("res://scripts/mobile_hud.gd").new()
	hud.attack_requested.connect(toggle_auto_attack)
	hud.ability_requested.connect(try_training_strike)
	hud.interact_requested.connect(open_selected_merchant)
	hud.jump_changed.connect(_set_jump_held)
	hud.joystick_changed.connect(func(value: Vector2): joystick_vector = value)
	hud.look_changed.connect(func(value: Vector2): look_stick = value)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "MobileHUD"
	add_child(ui_layer)
	ui_layer.add_child(hud)


func _set_runtime_paused(
	paused: bool
) -> void:
	if zone_npc_population != null:
		zone_npc_population.set_runtime_paused(
			paused
		)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and simulation != null:
		_save_game()


func _update_hud() -> void:
	if hud == null or simulation == null:
		return
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity == null:
		return
	var inventory_line := _inventory_summary()
	var progression_line := _progression_summary()
	hud.set_auto_attack(auto_attack_enabled)
	var training_strike := _ability_definition("training_strike")
	var ability_available := not training_strike.is_empty() and simulation.profile_is_learned(PLAYER_ENTITY_ID, training_strike)
	hud.set_ability(
		str(training_strike.get("display_name", "TRAINING\nSTRIKE")),
		ability_available,
		simulation.cooldown_remaining(PLAYER_ENTITY_ID, str(training_strike.get("cooldown_group", "")))
	)
	var class_line := "Class: %s    Auto: %s" % [_class_display_name(), "ON" if auto_attack_enabled else "OFF"]
	hud.set_interaction_available(_selected_merchant_is_browseable())
	var target_line := _target_status_line()
	hud.set_status("%s\nLevel %d    HP %.0f / %.0f    %s\n%s\n%s\n%s" % [
		status_text,
		player_entity.level,
		player_entity.health,
		player_entity.max_health,
		target_line,
		class_line,
		progression_line,
		inventory_line,
	])


func _target_status_line() -> String:
	var target_id := _current_target_entity_id()
	if target_id.is_empty():
		return "No target"
	var entity := simulation.entity(target_id)
	if entity == null:
		return "No target"
	if target_id == TRAINING_ENTITY_ID:
		if entity.is_active():
			return "%s: %.0f / %.0f" % [entity.display_name, entity.health, entity.max_health]
		if entity.lifecycle == GameplayEntity.Lifecycle.DEAD:
			return "%s: respawns in %.0fs" % [entity.display_name, entity.time_until_respawn(simulation_clock.now_seconds())]
		return "%s: %s" % [entity.display_name, GameplayEntity.lifecycle_name(entity.lifecycle)]
	return "Target: %s (Lv %d)" % [
		entity.display_name,
		entity.level,
	]


func _target_nearest_zone_npc() -> void:
	if zone_npc_population == null:
		return
	var forward := -camera_pivot.global_transform.basis.z
	var target := zone_npc_population.nearest_target(player.global_position, forward)
	if target.is_empty():
		_clear_zone_selection()
		status_text = "No zone NPC is in target range."
		return
	_select_zone_target(target)


func _target_zone_npc_at_screen(screen_position: Vector2) -> Dictionary:
	if zone_npc_population == null or camera == null:
		return {}
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * camera.far,
		COLLISION_LAYER_TARGET_PICK
	)
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Variant = hit.get("collider")
	if not collider is Area3D:
		return {}
	var target := zone_npc_population.target_for_pick_area(collider)
	if target.is_empty():
		return {}
	_select_zone_target(target)
	return target


func _select_zone_target(
	target: Dictionary
) -> void:
	var entity_id := (
		_zone_runtime_entity_id(
			int(
				target.get(
					"spawn2_id",
					0
				)
			)
		)
	)
	var entity := simulation.entity(
		entity_id
	)

	if entity == null:
		push_error(
			"Zone presentation target "
			+ "has no registered domain "
			+ "actor: "
			+ entity_id
		)
		_clear_zone_selection()
		return

	selected_zone_target = target
	selected_entity_id = entity_id

	view_registry.sync_to_domain(
		entity
	)

	if not simulation.set_target(
		PLAYER_ENTITY_ID,
		entity_id
	):
		push_error(
			"Unable to assign player "
			+ "target: "
			+ entity_id
		)
		_clear_zone_selection()
		return

	zone_npc_population.set_selected_spawn(
		int(
			target.get(
				"spawn2_id",
				0
			)
		)
	)
	status_text = (
		_selected_npc_interaction_summary(
			target
		)
	)

func _clear_zone_selection() -> void:
	selected_zone_target = {}
	selected_entity_id = ""

	_restore_default_player_target()

	if zone_npc_population != null:
		zone_npc_population.set_selected_spawn(
			-1
		)

func _update_npc_long_press(delta: float) -> void:
	if npc_press_touch < 0 or npc_press_target.is_empty():
		return
	npc_press_elapsed += delta
	if npc_press_elapsed < NPC_LONG_PRESS_SECONDS:
		return
	var target := npc_press_target
	_cancel_npc_long_press(npc_press_touch)
	_open_merchant_interaction(target)


func _cancel_npc_long_press(touch_index: int) -> void:
	if touch_index != npc_press_touch:
		return
	npc_press_touch = -1
	npc_press_target = {}
	npc_press_elapsed = 0.0


func _zone_entity_for_target(
	target: Dictionary
) -> GameplayEntity:
	if (
		simulation == null
		or target.is_empty()
	):
		return null

	var spawn2_id := int(
		target.get(
			"spawn2_id",
			0
		)
	)

	if spawn2_id <= 0:
		return null

	return simulation.entity(
		_zone_runtime_entity_id(
			spawn2_id
		)
	)


func _selected_zone_entity() -> GameplayEntity:
	if (
		simulation == null
		or selected_entity_id.is_empty()
	):
		return null

	var actor := simulation.entity(
		selected_entity_id
	)

	if (
		actor == null
		or actor.kind != "npc"
	):
		return null

	return actor


func _actor_has_merchant_catalog(
	actor: GameplayEntity
) -> bool:
	if actor == null:
		return false

	if (
		actor.attachment_kind(
			actor.inventory_attachment
		)
		!= GameplayEntity.ATTACHMENT_MERCHANT_CATALOG
	):
		return false

	return (
		int(
			actor.inventory_attachment.get(
				"merchant_id",
				0
			)
		) > 0
		or not str(
			actor.inventory_attachment.get(
				"merchant_ref",
				""
			)
		).is_empty()
	)

func _open_merchant_interaction(
	target: Dictionary
) -> void:
	var actor := _zone_entity_for_target(
		target
	)

	if not _actor_has_merchant_catalog(
		actor
	):
		return

	var standing := str(
		_actor_faction_reaction(
			actor
		).get(
			"standing",
			"Unresolved"
		)
	)

	if not MerchantPolicy.can_browse(
		standing
	):
		status_text = (
			"%s will not trade with you."
			% actor.display_name
		)
		return

	if merchant_interaction_popup != null:
		merchant_interaction_popup.queue_free()

	merchant_interaction_popup = preload(
		"res://scripts/merchant_interaction_popup.gd"
	).new()

	merchant_interaction_popup.trade_requested.connect(
		func():
			merchant_interaction_popup.queue_free()
			merchant_interaction_popup = null
			open_selected_merchant()
	)
	merchant_interaction_popup.closed.connect(
		func():
			merchant_interaction_popup = null
	)

	ui_layer.add_child(
		merchant_interaction_popup
	)
	merchant_interaction_popup.show_for_merchant(
		actor.display_name
	)

func _selected_npc_interaction_summary(
	target: Dictionary
) -> String:
	var actor := _zone_entity_for_target(
		target
	)

	if actor == null:
		return "Selected NPC has no runtime actor."

	var details: Array[String] = []

	if _actor_has_merchant_catalog(
		actor
	):
		details.append(
			"merchant candidate"
		)

	if str(
		target.get(
			"loot_state",
			"none"
		)
	) == "reference_only":
		details.append(
			"loot reference"
		)

	var reaction := _actor_faction_reaction(
		actor
	)
	var standing := str(
		reaction.get(
			"standing",
			"Unresolved"
		)
	)

	if standing == "Unresolved":
		details.append(
			"faction unresolved"
		)
	else:
		details.append(
			standing
		)

	if details.is_empty():
		details.append(
			"faction indifferent"
		)

	var summary := (
		"You target %s (Lv %d) — %s; "
		+ "combat disabled pending review."
	) % [
		actor.display_name,
		actor.level,
		", ".join(details),
	]

	if _actor_has_merchant_catalog(
		actor
	):
		var preview := (
			_merchant_preview_for_actor(
				actor
			)
		)

		if not preview.is_empty():
			summary += (
				"
%s"
				% preview
			)

	return summary

func _actor_faction_reaction(
	actor: GameplayEntity
) -> Dictionary:
	if actor == null:
		return simulation.faction_reaction(
			""
		)

	return simulation.faction_reaction(
		actor.faction_reference()
	)

func _merchant_listings_for_actor(
	actor: GameplayEntity
) -> Array:
	if not _actor_has_merchant_catalog(
		actor
	):
		return []

	return content_service.merchant_listings(
		str(
			actor.inventory_attachment.get(
				"merchant_ref",
				""
			)
		),
		int(
			actor.inventory_attachment.get(
				"merchant_id",
				0
			)
		)
	)

func _merchant_preview_for_actor(
	actor: GameplayEntity
) -> String:
	var listings := (
		_merchant_listings_for_actor(
			actor
		)
	)

	if listings.is_empty():
		return "Shop inventory is unavailable."

	var names: Array[String] = []

	for listing in listings.slice(
		0,
		3
	):
		names.append(
			str(
				listing.get(
					"item_name",
					"Unknown item"
				)
			)
		)

	return "Shop stock (%d): %s%s — browsing only." % [
		listings.size(),
		", ".join(names),
		"…"
		if listings.size() > names.size()
		else "",
	]

func _selected_merchant_is_browseable() -> bool:
	var actor := _selected_zone_entity()

	if not _actor_has_merchant_catalog(
		actor
	):
		return false

	var reaction := _actor_faction_reaction(
		actor
	)

	return MerchantPolicy.can_browse(
		str(
			reaction.get(
				"standing",
				"Unresolved"
			)
		)
	)

func open_selected_merchant() -> void:
	if (
		simulation != null
		and simulation.is_paused()
	):
		return

	var actor := _selected_zone_entity()

	if not _actor_has_merchant_catalog(
		actor
	):
		status_text = (
			"Select a merchant to browse their stock."
		)
		return

	var reaction := _actor_faction_reaction(
		actor
	)
	var standing := str(
		reaction.get(
			"standing",
			"Unresolved"
		)
	)

	if not MerchantPolicy.can_browse(
		standing
	):
		status_text = (
			"%s will not trade with you (%s)."
			% [
				actor.display_name,
				standing,
			]
		)
		return

	var listings := (
		_merchant_listings_for_actor(
			actor
		)
	)

	if listings.is_empty():
		status_text = (
			"This merchant has no available stock."
		)
		return

	if merchant_panel != null:
		merchant_panel.queue_free()

	merchant_panel = preload(
		"res://scripts/merchant_browse_panel.gd"
	).new()
	merchant_panel.closed.connect(
		func():
			merchant_panel = null
	)

	ui_layer.add_child(
		merchant_panel
	)
	merchant_panel.show_merchant(
		actor.display_name,
		listings
	)

func _legacy_save_context() -> Dictionary:
	var player_fixture := (
		content_service.player_fixture_definition()
	)

	return {
		"player_entity_id":
			PLAYER_ENTITY_ID,
		"legacy_npc_entity_id":
			TRAINING_ENTITY_ID,
		"rng_seed":
			simulation_rng.initial_seed(),
		"class_id": int(
			player_fixture.get(
				"identity",
				{}
			).get(
				"class_id",
				1
			)
		),
		"race_id": int(
			player_fixture.get(
				"identity",
				{}
			).get(
				"race_id",
				2
			)
		),
		"deity_id": int(
			player_fixture.get(
				"identity",
				{}
			).get(
				"deity_id",
				396
			)
		),
	}


func _prepare_save_read() -> void:
	pending_save_read = (
		persistence_service.read_save(
			zone,
			_legacy_save_context()
		)
	)

	if not bool(
		pending_save_read.get(
			"ok",
			true
		)
	):
		status_text = (
			"Save data was ignored: %s"
			% str(
				pending_save_read.get(
					"error",
					"invalid save"
				)
			)
		)
		return

	if not bool(
		pending_save_read.get(
			"loaded",
			false
		)
	):
		return

	var store_result := (
		persistence_service
		.restore_zone_store_from_read(
			pending_save_read,
			zone_state_store
		)
	)

	if not bool(
		store_result.get(
			"ok",
			false
		)
	):
		status_text = (
			"Save data was ignored: %s"
			% str(
				store_result.get(
					"error",
					"invalid zone-state store"
				)
			)
		)
		pending_save_read = store_result
		return

	if zone_state_store.has_zone(
		current_zone_key
	):
		if not zone_host.restore_active_from_store():
			status_text = (
				"Save data was ignored: %s"
				% zone_host.last_error
			)
			pending_save_read = {
				"ok": false,
				"loaded": false,
				"reason": "invalid",
				"error": zone_host.last_error,
			}
		else:
			zone_runtime_state = (
				zone_host.active_runtime_state
			)


func _restore_simulation_save() -> void:
	if pending_save_read.is_empty():
		_restore_default_player_target()
		return

	if not bool(
		pending_save_read.get(
			"ok",
			true
		)
	):
		_restore_default_player_target()
		return

	var result := (
		persistence_service
		.restore_simulation_from_read(
			pending_save_read,
			simulation
		)
	)

	if not bool(
		result.get(
			"ok",
			true
		)
	):
		status_text = (
			"Save data was ignored: %s"
			% str(
				result.get(
					"error",
					"invalid save"
				)
			)
		)

	_restore_default_player_target()


func _save_game() -> void:
	if simulation == null or player == null:
		return
	_sync_domain_from_views()
	var result := persistence_service.save_simulation(
		zone,
		simulation,
		zone_runtime_state,
		zone_state_store
	)
	if not bool(result.get("ok", false)):
		status_text = "Unable to save local progress."


func _apply_domain_state_to_views() -> void:
	for entity_id in [PLAYER_ENTITY_ID, TRAINING_ENTITY_ID]:
		var entity := simulation.entity(entity_id)
		if entity != null:
			view_registry.apply_from_domain(entity)
	var player_entity := simulation.entity(PLAYER_ENTITY_ID)
	if player_entity != null:
		player.reset_physics_interpolation()
		if player_entity.lifecycle == GameplayEntity.Lifecycle.DYING:
			_play_player_animation("death")
		elif player_entity.is_active():
			_play_player_animation("idle")


func _progression_summary() -> String:
	if simulation.progression.level >= simulation.progression.max_level:
		return "XP: %d (level cap)" % simulation.progression.xp_total
	return "XP: %d / %d" % [
		simulation.progression.xp_into_level(),
		simulation.progression.xp_needed_for_next_level(),
	]


func _inventory_summary() -> String:
	var entries := simulation.inventory.entries()
	if entries.is_empty():
		return "Inventory: empty    Wallet: %s" % _format_wallet()
	var labels: Array[String] = []
	for instance in entries:
		var item_key := str(instance.get("item_key", ""))
		var definition := content_service.item_definition(item_key)
		labels.append("%s ×%d" % [
			str(definition.get("name", item_key)),
			int(instance.get("quantity", 0)),
		])
	return "Inventory (%d/%d): %s    Wallet: %s" % [
		entries.size(),
		simulation.inventory.capacity,
		", ".join(labels),
		_format_wallet(),
	]


func wallet_total_copper() -> int:
	return simulation.wallet_total_copper()


func credit_copper(amount: int) -> void:
	simulation.credit_copper(amount)


func debit_copper(amount: int) -> bool:
	return simulation.debit_copper(amount)


func _format_wallet() -> String:
	var wallet := simulation.wallet
	return "%dpp %dgp %dsp %dcp" % [
		int(wallet.get("platinum", 0)),
		int(wallet.get("gold", 0)),
		int(wallet.get("silver", 0)),
		int(wallet.get("copper", 0)),
	]


func clear_save() -> void:
	persistence_service.clear()


func _spawn_data() -> Dictionary:
	var spawns: Array = zone.get("spawns", [])
	return spawns[0] if not spawns.is_empty() else {}


func _array_to_vector3(values: Variant) -> Vector3:
	if values is Vector3:
		return values
	if values is Array and values.size() >= 3:
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO


func _material(color: Color, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.3
	return material


func _add_marker(location: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.3
	cylinder.bottom_radius = 0.55
	cylinder.height = 2.0
	marker.mesh = cylinder
	marker.material_override = _material(Color("27503d"))
	marker.position = location + Vector3.UP
	add_child(marker)
