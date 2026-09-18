extends Node3D

const ZONE_KEY := "eqm:zone:halas"
const PLAYER_ENTITY_ID := "player:local"
const TRAINING_ENTITY_ID := "fixture:spawn:training_spark"
const CONTENT_PATHS := {
	"zone": "res://data/halas.json",
	"items": "res://data/items.json",
	"peq_items": "res://data/halas_items_source.json",
	"player_classes": "res://data/player_classes.json",
	"player_fixture": "res://data/player_fixture.json",
	"merchants": "res://data/halas_merchants_source.json",
	"factions": "res://data/halas_factions_source.json",
	"npcs": "res://data/halas_npcs.json",
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

var content_service: ContentService
var persistence_service: PersistenceService
var simulation_clock: SimulationClock
var simulation_rng: SimulationRng
var simulation: Simulation
var view_registry := EntityViewRegistry.new()
var npc_behavior_system := SimpleNpcBehaviorSystem.new()
var autonomous_entity_ids: Array[String] = []

var zone: Dictionary
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
var halas_population: HalasNpcPopulation
var halas_spawn_entity_ids: Dictionary = {}

var selected_halas_target: Dictionary = {}
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
var status_text := "Explore classic Halas."
var autosave_elapsed := 0.0

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
	_build_world()
	_build_zone_objects()
	_build_npc_population()
	_build_player()
	if simulation.entity(TRAINING_ENTITY_ID) != null:
		_build_npc()
	_build_camera()
	_build_hud()
	_load_save()
	_apply_domain_state_to_views()
	_update_hud()


func _configure_services() -> void:
	content_service = ContentService.new()
	content_service.configure(CONTENT_PATHS)
	assert(content_service.load_all(), content_service.last_error)
	zone = content_service.zone_definition(ZONE_KEY)
	simulation_clock = SimulationClock.new()
	var runtime_seed := int(simulation_clock.real_world_unix_ms() & 0x7fffffff)
	simulation_rng = SimulationRng.new(runtime_seed)
	persistence_service = PersistenceService.new(PersistenceService.DEFAULT_SAVE_PATH, simulation_clock)


func _configure_simulation() -> void:
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
		_target_nearest_halas_npc()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		open_selected_merchant()
		return
	if event.is_action_pressed("attack"):
		toggle_auto_attack()
	if event is InputEventScreenTouch:
		hud.handle_touch(event.index, event.position, event.pressed)
		if event.pressed:
			var touch_target := _target_halas_npc_at_screen(event.position)
			var touch_actor := _halas_entity_for_target(
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

	if halas_population == null:
		return

	for spawn2_variant in (
		halas_spawn_entity_ids
	):
		var spawn2_id := int(
			spawn2_variant
		)
		var entity_id := str(
			halas_spawn_entity_ids[
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

		# Halas patrol remains a presentation
		# compatibility path. Mirror its pose
		# into the generic actor contract.
		view_registry.sync_to_domain(
			actor
		)

		var velocity := (
			halas_population
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


func _build_world() -> void:
	var geometry_path := str(zone.get("geometry_scene", ""))
	if not geometry_path.is_empty():
		var geometry_scene := load(geometry_path) as PackedScene
		assert(geometry_scene != null, "Unable to import zone geometry: %s" % geometry_path)
		var geometry := geometry_scene.instantiate()
		geometry.name = "ZoneGeometry"
		geometry.scale = Vector3.ONE * float(zone.get("geometry_scale", 1.0))
		add_child(geometry)
		_build_zone_collision(geometry)
		assert(not authored_water_triangles.is_empty(), "Halas water surface was not found in the imported zone mesh")
	else:
		_build_placeholder_ground()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_energy = 1.2
	add_child(light)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fb9c5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("bfd7c8")
	env.ambient_light_energy = 0.65
	environment.environment = env
	add_child(environment)


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
		if _surface_is_halas_water(mesh_instance, surface_index):
			if _surface_defines_halas_water_surface(mesh_instance, surface_index):
				_register_water_surface(vertices, indices, mesh_instance.global_transform)
		else:
			_append_triangle_faces(terrain_faces, vertices, indices)
	if terrain_faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(terrain_faces)
	_add_collision_shape(mesh_instance, shape, COLLISION_LAYER_TERRAIN, "TerrainCollision")


func _surface_is_halas_water(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	var material := mesh_instance.get_active_material(surface_index)
	if material != null:
		var identifier := (material.resource_name + " " + material.resource_path).to_lower()
		if identifier.contains("halaswater"):
			return true
	return mesh_instance.mesh.get_surface_count() == 62 and surface_index in [58, 61]


func _surface_defines_halas_water_surface(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	return mesh_instance.mesh.get_surface_count() == 62 and surface_index == 58


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
	add_child(ground)
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
	add_child(container)
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
		placement.position = EqWorldSpace.halas_lantern_prop_position(float(values[1]), float(values[2]), float(values[3]))
		placement.rotation.y = EqWorldSpace.halas_lantern_prop_yaw(float(values[5]))
		placement.scale = Vector3(float(values[7]), float(values[8]), float(values[9]))
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
	npc = Node3D.new()
	npc.name = "TrainingSpark"
	npc.position = entity.position
	add_child(npc)
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

	if (
		npc_content.is_empty()
		or models_path.is_empty()
	):
		return

	halas_population = (
		HalasNpcPopulation.new()
	)
	halas_population.name = (
		"ClassicHalasPopulation"
	)
	halas_population.configure(
		npc_content,
		models_path
	)
	add_child(
		halas_population
	)

	_register_halas_domain_actors()


func _register_halas_domain_actors() -> void:
	assert(
		halas_population != null,
		"Halas population must exist "
		+ "before actor registration"
	)

	halas_spawn_entity_ids.clear()

	var targets: Array[Dictionary] = (
		halas_population.actor_targets()
	)
	var definitions: Array[Dictionary] = (
		HalasEntityAdapter
		.neutral_definitions_from_targets(
			targets
		)
	)

	assert(
		definitions.size()
		== targets.size(),
		"Halas actor definition count "
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
			"Halas runtime actor "
			+ "requires a spawn2 ID"
		)

		var entity_id := str(
			definition.get(
				"entity_id",
				""
			)
		)

		assert(
			not entity_id.is_empty(),
			"Halas runtime actor "
			+ "requires an entity ID"
		)
		assert(
			simulation.entity(
				entity_id
			) == null,
			"Duplicate Halas runtime "
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
			"Halas runtime actor "
			+ "requires a view node"
		)

		view_registry.bind(
			entity_id,
			node_variant as Node3D
		)
		view_registry.sync_to_domain(
			entity
		)

		halas_spawn_entity_ids[
			spawn2_id
		] = entity_id

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


func _target_nearest_halas_npc() -> void:
	if halas_population == null:
		return
	var forward := -camera_pivot.global_transform.basis.z
	var target := halas_population.nearest_target(player.global_position, forward)
	if target.is_empty():
		_clear_halas_selection()
		status_text = "No Halas NPC is in target range."
		return
	_select_halas_target(target)


func _target_halas_npc_at_screen(screen_position: Vector2) -> Dictionary:
	if halas_population == null or camera == null:
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
	var target := halas_population.target_for_pick_area(collider)
	if target.is_empty():
		return {}
	_select_halas_target(target)
	return target


func _select_halas_target(
	target: Dictionary
) -> void:
	var entity_id := (
		HalasEntityAdapter.runtime_entity_id(
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
			"Halas presentation target "
			+ "has no registered domain "
			+ "actor: "
			+ entity_id
		)
		_clear_halas_selection()
		return

	selected_halas_target = target
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
		_clear_halas_selection()
		return

	halas_population.set_selected_spawn(
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

func _clear_halas_selection() -> void:
	selected_halas_target = {}
	selected_entity_id = ""

	_restore_default_player_target()

	if halas_population != null:
		halas_population.set_selected_spawn(
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


func _halas_entity_for_target(
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
		HalasEntityAdapter.runtime_entity_id(
			spawn2_id
		)
	)


func _selected_halas_entity() -> GameplayEntity:
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
	var actor := _halas_entity_for_target(
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
	var actor := _halas_entity_for_target(
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
	var actor := _selected_halas_entity()

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

	var actor := _selected_halas_entity()

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

func _load_save() -> void:
	var player_fixture := content_service.player_fixture_definition()
	var result := persistence_service.load_simulation(zone, simulation, {
		"player_entity_id": PLAYER_ENTITY_ID,
		"legacy_npc_entity_id": TRAINING_ENTITY_ID,
		"rng_seed": simulation_rng.initial_seed(),
		"class_id": int(player_fixture.get("identity", {}).get("class_id", 1)),
		"race_id": int(player_fixture.get("identity", {}).get("race_id", 2)),
		"deity_id": int(player_fixture.get("identity", {}).get("deity_id", 396)),
	})
	if not bool(result.get("ok", true)):
		status_text = "Save data was ignored: %s" % str(result.get("error", "invalid save"))

	_restore_default_player_target()

func _save_game() -> void:
	if simulation == null or player == null:
		return
	_sync_domain_from_views()
	var result := persistence_service.save_simulation(zone, simulation)
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