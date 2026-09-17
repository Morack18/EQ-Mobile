extends Node3D

const SAVE_PATH := "user://offline_slice_save.json"
const ZONE_PATH := "res://data/halas.json"
const ITEM_PATH := "res://data/items.json"
const PLAYER_CLASS_PATH := "res://data/player_classes.json"
# EQEmu's 0.7 × 40 = 28 is the client-update animation/wire value, not a
# physical world-speed authority. eqoxide's centralized controller uses 44
# u/s, but its direct manual-drive path uses 35 u/s. EQ Mobile's two-stick
# controller is the latter interaction model, and device feel confirms 44 is
# too fast for this project; use 35 u/s while retaining the discrepancy below.
const PLAYER_RUN_SPEED := 35.0
const PLAYER_WALK_SPEED := PLAYER_RUN_SPEED * (0.3 / 0.7)
const WALK_RUN_THRESHOLD := 20.0
# EQEmu's GetRaceGenderDefaultHeight defines HLM as a seven-foot actor in the
# same coordinate system as the Halas zone.  The raw Lantern GLB is only an
# authored rig; it must be normalized to this height before rendering.
const PLAYER_SERVER_SIZE := 7.0
# eqoxide's reference-client collision radius is one EQ world unit.  Keep the
# collision body's standing span equal to the HLM's native rendered height.
const PLAYER_COLLISION_RADIUS := 1.0
const PLAYER_COLLISION_HEIGHT := PLAYER_SERVER_SIZE
const COLLISION_LAYER_TERRAIN := 1
const COLLISION_LAYER_WORLD_OBJECTS := 2
const COLLISION_LAYER_TARGET_PICK := 4
const PLAYER_WORLD_COLLISION_MASK := COLLISION_LAYER_TERRAIN | COLLISION_LAYER_WORLD_OBJECTS
const PLAYER_MAX_SLOPE_ANGLE := deg_to_rad(60.0)
const PLAYER_FLOOR_SNAP_DISTANCE := 0.5
const PLAYER_SAFE_MARGIN := 0.05
# eqoxide's native-parity CharacterController uses STEP_UP = 2 EQ units for
# both free movement and navigation. It is a bounded stair/low-lip rule, not
# permission to climb arbitrary vertical walls.
const PLAYER_STEP_UP_HEIGHT := 2.0
# eqoxide's reference client uses these native EQ world-unit values.  Do not
# substitute Godot's project gravity: this zone is already normalized to EQ
# world units.
const EQ_GRAVITY := 120.0
const EQ_MAX_FALL_SPEED := 128.0
const EQ_JUMP_VELOCITY := 31.0
const EQ_SWIM_SPEED := 35.0
const EQ_SWIM_BUOYANCY_RATE := 30.0
const EQ_SWIM_FLOAT_DEPTH := 2.0
const WATER_SURFACE_MARGIN := 0.05
const PLAYER_MAX_HEALTH := 100.0
# EQEmu CombatRange's ordinary-body branch floors small actor size at 8 and
# uses range_squared = size² × 4. That produces this horizontal 16-unit reach.
const ORDINARY_MELEE_EFFECTIVE_SIZE := 8.0
const ORDINARY_MELEE_RANGE := ORDINARY_MELEE_EFFECTIVE_SIZE * 2.0
const MELEE_FACING_DOT_MIN := 0.556
const CAMERA_TURN_SPEED := 2.45
const CAMERA_PITCH_SPEED := 1.55
const CAMERA_OFFSET := Vector3(0.0, 4.7, 10.5)
const CAMERA_COLLISION_MARGIN := 0.35
const PLAYER_ATTACK_ANIMATION_SECONDS := 0.45
# eqoxide's renderer establishes that the exported glTF character meshes face
# local +X. Godot's Node3D.look_at() faces local -Z, so character visuals need
# this fixed model-space correction below their movement node.
const CHARACTER_MODEL_FACING_OFFSET := PI * 0.5

var zone: Dictionary
var player: CharacterBody3D
var player_visual: Node3D
var player_animator: AnimationPlayer
var npc: Node3D
var camera_pivot: Node3D
var camera: Camera3D
var hud: Control
var player_health := PLAYER_MAX_HEALTH
var player_xp_total := 0
var player_level := 1
var player_dead := false
var player_respawn_remaining := 0.0
var player_action_animation_remaining := 0.0
var player_class_definitions: Dictionary = {}
var player_class_id := 1
var ability_cooldowns: Dictionary = {}
var auto_attack_enabled := false
var primary_attack_remaining := 0.0
var npc_health := 0.0
var npc_alive := false
var npc_attack_timer := 0.0
var respawn_remaining := 0.0
var npc_loot_awarded := false
var joystick_vector := Vector2.ZERO
var look_stick := Vector2.ZERO
var jump_held := false
var jump_pressed := false
var status_text := "Explore classic Halas."
var autosave_elapsed := 0.0
var save_write_failed := false
var object_scenes: Dictionary[String, PackedScene] = {}
var normalized_prop_meshes: Dictionary[Mesh, ArrayMesh] = {}
var two_sided_prop_materials: Dictionary[Material, BaseMaterial3D] = {}
# Prop GLBs are immutable after the one-time reflection bake.  Many placement
# rows share those same mesh resources, so their exact trimesh shape can be
# safely reused instead of cooking duplicate physics data per placement.
var prop_collision_shapes: Dictionary[Mesh, Shape3D] = {}
var zone_prop_instance_count := 0
var zone_prop_mesh_count := 0
var zone_prop_collision_count := 0
var zone_prop_collision_shape_count := 0
var zone_prop_load_failures: Array[String] = []
var halas_population: HalasNpcPopulation
var selected_halas_target: Dictionary = {}
var item_definitions: Dictionary = {}
var inventory: Dictionary = {}
# Halas's client .wtr region file is not present in the supplied resources.
# This is therefore an authored-surface fallback, populated from the zone's
# explicit halaswater material triangles rather than a guessed rectangular pool.
var authored_water_triangles: Array[PackedVector3Array] = []

func _ready() -> void:
	zone = _load_zone()
	item_definitions = _load_item_definitions()
	player_class_definitions = _load_player_class_definitions()
	_build_world()
	_build_zone_objects()
	_build_npc_population()
	_build_player()
	if bool(zone.get("enable_training_npc", false)):
		_build_npc()
	_build_camera()
	_build_hud()
	_load_save()
	_update_hud()

func _process(delta: float) -> void:
	player_action_animation_remaining = maxf(0.0, player_action_animation_remaining - delta)
	_update_player_respawn(delta)
	_update_auto_attack(delta)
	_update_npc(delta)
	_update_camera(delta)
	_update_hud()
	autosave_elapsed += delta
	if autosave_elapsed >= 2.0:
		autosave_elapsed = 0.0
		_save_game()


func _physics_process(delta: float) -> void:
	if player_dead:
		player.velocity = Vector3.ZERO
		return
	_move_player(delta)

func _unhandled_input(event: InputEvent) -> void:
	# Space is the EQ client jump key.  It was previously part of the prototype
	# attack action, so consume it before that action is checked.
	if event is InputEventKey and event.keycode == KEY_SPACE:
		_set_jump_held(event.pressed and not event.echo)
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_target_nearest_halas_npc()
		return
	if event.is_action_pressed("attack"):
		toggle_auto_attack()
	if event is InputEventScreenTouch:
		hud.handle_touch(event.index, event.position, event.pressed)
		if event.pressed:
			_target_halas_npc_at_screen(event.position)
	if event is InputEventScreenDrag:
		hud.handle_drag(event.index, event.position, event.relative)
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		clear_save()
		get_tree().reload_current_scene()

func toggle_auto_attack() -> void:
	if player_dead:
		return
	auto_attack_enabled = not auto_attack_enabled
	if auto_attack_enabled:
		status_text = "Auto-attack enabled."
	else:
		status_text = "Auto-attack disabled."

func _update_auto_attack(delta: float) -> void:
	if player_dead or not auto_attack_enabled:
		return
	primary_attack_remaining = maxf(0.0, primary_attack_remaining - delta)
	if primary_attack_remaining > 0.0:
		return
	if _perform_primary_attack():
		primary_attack_remaining = _primary_attack_interval_seconds()

func _perform_primary_attack() -> bool:
	var validation := _validate_fixture_melee_target(_attack_profile())
	if not validation.is_empty():
		status_text = validation
		return false
	_play_player_animation("attack")
	player_action_animation_remaining = PLAYER_ATTACK_ANIMATION_SECONDS
	npc_health = maxf(0.0, npc_health - _resolve_fixture_melee_damage(str(_attack_profile().get("damage_profile", "")), 10.0))
	status_text = "You strike the Training Spark."
	_finish_training_spark_if_defeated()
	_save_game()
	return true

func try_training_strike() -> void:
	if player_dead:
		return
	var ability := _ability_definition("training_strike")
	if ability.is_empty() or not _ability_is_learned(ability):
		status_text = "Training Strike is unavailable to this class."
		return
	var group := str(ability.get("cooldown_group", ""))
	if _ability_cooldown_remaining(group) > 0.0:
		status_text = "Training Strike is recovering."
		return
	var validation := _validate_fixture_melee_target(ability)
	if not validation.is_empty():
		status_text = validation
		return
	# A valid use starts its persistent shared timer independently of normal
	# melee timing, matching the useful pTimerCombatAbility behavior.
	ability_cooldowns[group] = _unix_time_ms() + int(float(ability.get("cooldown_seconds", 0.0)) * 1000.0)
	_play_player_animation(str(ability.get("animation", "attack")))
	player_action_animation_remaining = PLAYER_ATTACK_ANIMATION_SECONDS
	npc_health = maxf(0.0, npc_health - _resolve_fixture_melee_damage(str(ability.get("damage_profile", "")), float(ability.get("damage", 0.0))))
	status_text = "You use Training Strike."
	_finish_training_spark_if_defeated()
	_save_game()

func _finish_training_spark_if_defeated() -> void:
	if npc_health > 0.0:
		return
	_award_training_loot()
	_award_training_xp()
	npc_alive = false
	respawn_remaining = float(_spawn_data().get("respawn_seconds", 12.0))
	npc.visible = false
	status_text = "Training Spark defeated — respawning soon."

func _class_definition() -> Dictionary:
	return player_class_definitions.get("classes", {}).get(str(player_class_id), {})

func _class_display_name() -> String:
	return str(_class_definition().get("display_name", "Unknown"))

func _attack_profile() -> Dictionary:
	return _class_definition().get("attack_profile", {})

func _ability_definition(ability_id: String) -> Dictionary:
	return player_class_definitions.get("abilities", {}).get(ability_id, {})

func _ability_is_learned(ability: Dictionary) -> bool:
	if player_level < int(ability.get("required_level", 1)):
		return false
	var allowed_classes: Array = ability.get("allowed_class_ids", [])
	return player_class_id in allowed_classes

func _primary_attack_interval_seconds() -> float:
	# Item delay is expressed in EQ tenths; no haste exists in this vertical
	# slice, while EQEmu's default minimum-hasted delay remains 400 ms.
	var delay_tenths := maxi(1, int(_attack_profile().get("delay_tenths", 35)))
	return maxf(0.4, delay_tenths * 0.1)

func _ordinary_melee_range_squared(attacker_size: float, defender_size: float) -> float:
	# Bounded ordinary-actor adaptation of EQEmu Mob::CombatRange: effective
	# size is floored at 8 and range² is largest_size² × 4 for sizes <= 19.
	var effective_size := maxf(ORDINARY_MELEE_EFFECTIVE_SIZE, maxf(attacker_size, defender_size))
	return effective_size * effective_size * 4.0

func _validate_fixture_melee_target(profile: Dictionary) -> String:
	if npc == null and not selected_halas_target.is_empty():
		return "%s is targeted. Source combat data has not been imported yet." % str(selected_halas_target.name)
	if npc == null or not npc_alive:
		return "No hostile target."
	var horizontal_offset := npc.global_position - player.global_position
	horizontal_offset.y = 0.0
	if horizontal_offset.length_squared() > _ordinary_melee_range_squared(ORDINARY_MELEE_EFFECTIVE_SIZE, ORDINARY_MELEE_EFFECTIVE_SIZE):
		return "Move closer to attack."
	if bool(profile.get("requires_facing", true)) and not _player_is_facing(npc.global_position):
		return "Face the Training Spark to attack."
	if bool(profile.get("requires_los", true)) and not _has_melee_line_of_sight(npc.global_position):
		return "Your line of sight is blocked."
	return ""

func _player_is_facing(target_position: Vector3) -> bool:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	var toward_target := target_position - player.global_position
	toward_target.y = 0.0
	if toward_target.length_squared() <= 0.000001:
		return true
	return forward.normalized().dot(toward_target.normalized()) >= MELEE_FACING_DOT_MIN

func _has_melee_line_of_sight(target_position: Vector3) -> bool:
	var origin := player.global_position + Vector3.UP * (PLAYER_SERVER_SIZE * 0.5)
	var destination := target_position + Vector3.UP * 0.7
	var query := PhysicsRayQueryParameters3D.create(origin, destination, PLAYER_WORLD_COLLISION_MASK, [player.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _resolve_fixture_melee_damage(damage_profile: String, fallback_damage: float) -> float:
	# The fixture has no sourced STR/skills/AC/hit data. Keep current deterministic
	# tuning behind this explicit seam so source-appropriate resolution can replace
	# it without changing attack cadence or ability scheduling.
	if damage_profile == "training_fixture":
		return fallback_damage
	push_warning("Unknown fixture damage profile: %s" % damage_profile)
	return 0.0

func _unix_time_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _ability_cooldown_remaining(group: String) -> float:
	if group.is_empty():
		return 0.0
	return maxf(0.0, (int(ability_cooldowns.get(group, 0)) - _unix_time_ms()) / 1000.0)

func _sanitized_ability_cooldowns(saved_cooldowns: Variant) -> Dictionary:
	var restored: Dictionary = {}
	if not saved_cooldowns is Dictionary:
		return restored
	var now := _unix_time_ms()
	for group_variant in saved_cooldowns:
		var group := str(group_variant)
		var ready_at := int(saved_cooldowns[group_variant])
		if not group.is_empty() and ready_at > now:
			restored[group] = ready_at
	return restored

func _move_player(delta: float) -> void:
	var keyboard := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input := joystick_vector if joystick_vector.length() > 0.05 else keyboard
	var water_surface: Variant = _water_surface_at(player.global_position)
	var swimming := water_surface != null and player.global_position.y < float(water_surface) - WATER_SURFACE_MARGIN
	var direction := Vector3.ZERO
	if input.length() > 0.05:
		var forward := -camera_pivot.global_transform.basis.z
		# The EQ client's camera-drive keeps horizontal steering normalized but
		# derives a separate vertical swim wish from camera pitch. Mobile's left
		# stick is that forward/back drive; the right stick remains camera orbit.
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera_pivot.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		direction = (right * input.x + forward * input.y).normalized()
	# Heading is camera-driven state, separate from horizontal displacement: left
	# stick lateral input strafes and must not rotate the body toward its wish.
	player.rotation.y = camera_pivot.rotation.y

	var movement_speed := EQ_SWIM_SPEED if swimming else PLAYER_RUN_SPEED
	player.velocity.x = direction.x * movement_speed
	player.velocity.z = direction.z * movement_speed
	if swimming:
		_apply_swim_vertical_motion(delta, float(water_surface), input)
	elif jump_pressed and player.is_on_floor():
		# eqoxide applies a 31 u/s upward impulse only from a grounded state.
		player.velocity.y = EQ_JUMP_VELOCITY
	elif player.is_on_floor():
		# A small downward velocity keeps floor contact stable over triangle seams.
		player.velocity.y = -1.0
	else:
		player.velocity.y = maxf(player.velocity.y - EQ_GRAVITY * delta, -EQ_MAX_FALL_SPEED)
	var horizontal_motion := Vector3(direction.x, 0.0, direction.z) * movement_speed * delta
	# The reference controller grants a swimmer the same bounded step-up as a
	# grounded walker, allowing a player to haul out over a legitimate shore lip.
	# An explicit upward swim wish stays in the water column instead.
	var may_swim_step := swimming and player.velocity.y <= 0.0
	var stepped_up := direction != Vector3.ZERO and (player.is_on_floor() or may_swim_step) and _try_step_up(horizontal_motion)
	if not stepped_up:
		player.move_and_slide()
	_update_locomotion_animation(swimming)

	_clamp_player_to_zone_bounds()
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
		# The HLM export currently contains no run clip. Do not fake it by speeding
		# up walk; this is a visible asset dependency, not source-faithful running.
		_play_player_animation("walk")


func _set_jump_held(pressed: bool) -> void:
	if pressed and not jump_held:
		jump_pressed = true
	jump_held = pressed


func _apply_swim_vertical_motion(delta: float, surface: float, input: Vector2) -> void:
	# eqoxide suspends gravity underwater. Forward/back follows camera pitch,
	# while the jump key is an explicit swim-up control and idle actors rise at
	# the native 30 u/s buoyancy rate toward two units below the surface.
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
	# Equivalent in intent to eqoxide's try_step_up: only attempt a step after
	# low movement is obstructed, require room above the character, clear travel
	# over the lip, then require a walkable landing within the bounded step band.
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
	var landing := player.move_and_collide(
		Vector3.DOWN * (PLAYER_STEP_UP_HEIGHT + PLAYER_FLOOR_SNAP_DISTANCE)
	)
	if landing == null or landing.get_normal().dot(Vector3.UP) < cos(PLAYER_MAX_SLOPE_ANGLE):
		player.global_transform = start
		return false
	player.velocity.y = -1.0
	return true


func _clamp_player_to_zone_bounds() -> void:
	var limit := float(zone.get("bounds", {}).get("half_extent", 18.0)) - 0.8
	player.global_position.x = clampf(player.global_position.x, -limit, limit)
	player.global_position.z = clampf(player.global_position.z, -limit, limit)

func _update_npc(delta: float) -> void:
	if npc == null or player_dead:
		return
	if not npc_alive:
		respawn_remaining -= delta
		if respawn_remaining <= 0.0:
			_respawn_npc()
		return
	var archetype: Dictionary = zone.npc_archetypes[_spawn_data().archetype]
	var distance := npc.global_position.distance_to(player.global_position)
	var aggro_range := float(archetype.aggro_range)
	if distance > aggro_range:
		return
	var attack_range := float(archetype.attack_range)
	if distance > attack_range:
		var direction := (player.global_position - npc.global_position).normalized()
		npc.global_position += direction * float(archetype.move_speed) * delta
		npc.look_at(player.global_position, Vector3.UP)
		return
	npc_attack_timer = maxf(0.0, npc_attack_timer - delta)
	if npc_attack_timer <= 0.0:
		npc_attack_timer = float(archetype.attack_cooldown)
		player_health = maxf(0.0, player_health - float(archetype.damage))
		status_text = "The Training Spark hits you."
		if player_health <= 0.0:
			player_dead = true
			auto_attack_enabled = false
			primary_attack_remaining = 0.0
			player_respawn_remaining = float(zone.get("player_respawn_seconds", 2.5))
			player.velocity = Vector3.ZERO
			_play_player_animation("death")
			status_text = "You were defeated — respawning in %.0f." % ceil(player_respawn_remaining)
			return
		_save_game()

func _update_player_respawn(delta: float) -> void:
	if not player_dead:
		return
	player_respawn_remaining = maxf(0.0, player_respawn_remaining - delta)
	status_text = "You were defeated — respawning in %.0f." % ceil(player_respawn_remaining)
	if player_respawn_remaining > 0.0:
		return
	player_dead = false
	auto_attack_enabled = false
	primary_attack_remaining = 0.0
	player_health = PLAYER_MAX_HEALTH
	player.global_position = _array_to_vector3(zone.player_spawn)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	_play_player_animation("idle")
	status_text = "You recover at the clearing entrance."
	_save_game()

func _update_camera(delta: float) -> void:
	# Camera follow has no positional lag: the orbit pivot is always the player,
	# keeping the character centered while physics interpolation smooths rendered
	# movement between fixed ticks.
	camera_pivot.global_position = player.global_position
	# The right mobile stick continuously controls yaw and pitch. Movement stays
	# camera-relative, so the left stick naturally follows the new heading.
	camera_pivot.rotation.y -= look_stick.x * CAMERA_TURN_SPEED * delta
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x + look_stick.y * CAMERA_PITCH_SPEED * delta,
		-0.75,
		-0.2
	)
	_update_camera_collision()


func _update_camera_collision() -> void:
	# Match the useful classic-client behavior documented by eqoxide: the camera
	# line is tested against the same authored zone collision used by the player,
	# then pulled forward before a wall instead of looking through it.
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
	# Aim at the visual center rather than the CharacterBody's ground origin so
	# the whole player, not its feet, remains centered on screen.
	return player.global_position + Vector3.UP * (PLAYER_SERVER_SIZE * 0.5)

func _respawn_npc() -> void:
	if npc == null:
		return
	npc_alive = true
	npc.visible = true
	npc.global_position = _array_to_vector3(_spawn_data().position)
	npc_health = float(zone.npc_archetypes[_spawn_data().archetype].max_health)
	npc_attack_timer = 0.0
	npc_loot_awarded = false
	status_text = "The Training Spark has returned."
	_save_game()

func _build_world() -> void:
	var geometry_path := str(zone.get("geometry_scene", ""))
	if not geometry_path.is_empty():
		var geometry_scene := load(geometry_path) as PackedScene
		assert(geometry_scene != null, "Unable to import zone geometry: %s" % geometry_path)
		var geometry := geometry_scene.instantiate()
		geometry.name = "ZoneGeometry"
		# Lantern's zone GLBs apply a 0.1 root transform, while its character
		# GLBs retain native game-scale units. geometry_scale normalizes the
		# two asset classes without modifying either extracted source file.
		geometry.scale = Vector3.ONE * float(zone.get("geometry_scale", 1.0))
		add_child(geometry)
		_build_zone_collision(geometry)
		# Lantern's source Halas GLB has a visible t75_agua1 water primitive.
		# Failing to find it would turn that surface back into a solid floor, so
		# fail visibly instead of silently shipping broken swim.
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
	# The authored zone shell is the terrain authority used for NPC elevation
	# validation. Props use a separate layer below: they block movement/cameras
	# but must not turn a table or crate into a terrain spawn surface.
	if node is MeshInstance3D and node.mesh != null:
		_add_zone_terrain_collision(node)
	for child in node.get_children():
		_build_zone_collision(child)


func _add_zone_terrain_collision(mesh_instance: MeshInstance3D) -> void:
	# Client water has its own region/surface logic; including the visible water
	# triangles in terrain collision would make a character stand on the water.
	# Keep all non-water triangle surfaces exactly as authored for land collision.
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
	# The supplied Lantern source GLB has two water-textured primitives:
	# t75_agua1 (58), its visible surface, and d_halaswater1 (61), the deeper
	# water geometry. Godot can clear embedded material resource names, so retain
	# these precise source-export fallbacks instead of treating water as land.
	return mesh_instance.mesh.get_surface_count() == 62 and surface_index in [58, 61]


func _surface_defines_halas_water_surface(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	# Source GLB inspection: primitive 58 / t75_agua1 occupies Y -3 through -1;
	# primitive 61 / d_halaswater1 extends down to Y -131.9375 and is not a
	# surface for buoyancy. Both must be non-solid; only 58 defines the surface.
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
	# Resolve the Y coordinate by barycentric interpolation of the authored
	# horizontal projection. The highest overlapping water triangle wins.
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
		# Keep an imported prop's transform separate from its placement transform.
		# Every Lantern prop root has a -X reflection. Assigning placement scale to
		# that root overwrites the reflection before it can be baked into the mesh,
		# leaving the source faces backwards on Android.
		var placement := Node3D.new()
		placement.name = "%s_%d" % [model_name, line_number]
		# Lantern writes raw EQ placement data. The Halas zone's root transform
		# mirrors X, so instance positions and headings must be mirrored too.
		placement.position = Vector3(-float(values[1]), float(values[2]), float(values[3]))
		placement.rotation.y = deg_to_rad(-float(values[5]))
		placement.scale = Vector3(float(values[7]), float(values[8]), float(values[9]))
		var object := scene.instantiate() as Node3D
		object.name = "Visual"
		placement.add_child(object)
		# Lantern's static-prop exporter mirrors each model root on X. Keeping that
		# negative transform works incidentally in the desktop renderer, but Android
		# drivers can cull it and physics receives a reflected trimesh hierarchy.
		# Bake the mirror into a private runtime mesh instead. This preserves the
		# visible model and its winding while leaving a normal transform for both
		# rendering and the collision body. NPC exports do not use this transform.
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
	# eqoxide's Collision::build expands every placed object into world-space
	# triangles alongside zone terrain. Use the imported prop triangles directly
	# here; manifest position/rotation/scale already live on their ancestor.
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
	# This is intentionally applied after baking. The source assets originate in
	# a different handedness and Android Vulkan/OpenGL drivers have disagreed on
	# front-face state for those imported materials. Culling must never make a
	# solid world prop disappear; triangle collision remains the authority.
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
	# GLB props are static triangle meshes. Applying the reflected local
	# transform to their vertices and reversing each face restores normal winding
	# without asking a renderer or physics backend to support negative scale.
	var baked_mesh := ArrayMesh.new()
	var normal_transform := mesh_transform.basis.inverse().transposed()
	var reverses_winding := mesh_transform.basis.determinant() < 0.0
	for surface_index in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for vertex_index in vertices.size():
			vertices[vertex_index] = mesh_transform * vertices[vertex_index]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		for normal_index in normals.size():
			normals[normal_index] = (normal_transform * normals[normal_index]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
		if source_mesh.surface_get_primitive_type(surface_index) == Mesh.PRIMITIVE_TRIANGLES and reverses_winding:
			var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
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
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = _array_to_vector3(zone.player_spawn)
	# Keep walkable terrain as floor instead of interpreting an incline's next
	# triangle as a wall. Very steep faces still remain collision walls.
	player.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	player.floor_max_angle = PLAYER_MAX_SLOPE_ANGLE
	player.floor_snap_length = PLAYER_FLOOR_SNAP_DISTANCE
	player.floor_constant_speed = true
	# A stationary grounded player must not creep downhill on walkable terrain.
	# This is a Godot/Jolt stability adaptation; the project has no sourced
	# classic-client slope-angle/slide rule to claim here.
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
	capsule.height = PLAYER_COLLISION_HEIGHT
	collision_shape.shape = capsule
	# The CharacterBody origin is the server's ground elevation. Put the capsule
	# bottom at that origin to match the grounded HLM visual.
	collision_shape.position.y = PLAYER_COLLISION_HEIGHT * 0.5
	player.add_child(collision_shape)
	var player_scene := load("res://assets/imported/halas/characters/hlm_s0_h0.glb") as PackedScene
	assert(player_scene != null, "Missing animated HLM placeholder player model")
	player_visual = player_scene.instantiate() as Node3D
	player_visual.name = "HLMPlaceholder"
	# Keep the CharacterBody's conventional -Z forward axis aligned to movement,
	# while the extracted EQ model's local +X face points along it.
	player_visual.rotation.y = CHARACTER_MODEL_FACING_OFFSET
	player.add_child(player_visual)
	player_animator = _animation_player_below(player_visual)
	assert(player_animator != null, "HLM placeholder model has no AnimationPlayer")
	for clip in ["idle", "walk", "attack", "death", "swimming", "treading"]:
		assert(player_animator.has_animation(clip), "HLM placeholder is missing %s animation" % clip)
	player_animator.play("idle")
	player_animator.advance(0.0)
	_normalize_player_model_to_height(player_visual, PLAYER_SERVER_SIZE)
	_play_player_animation("idle")


func _play_player_animation(clip: String) -> void:
	if player_animator == null or not player_animator.has_animation(clip):
		return
	if player_animator.current_animation != clip:
		player_animator.play(clip)


func _play_water_animation(moving: bool) -> void:
	# eqoxide selects L06/P06-family swim while moving and L08/P07-family tread
	# while still. These clips are required on the player export; the fallback
	# keeps custom/replacement player art usable during development.
	var clip := "swimming" if moving else "treading"
	if player_animator != null and player_animator.has_animation(clip):
		_play_player_animation(clip)
	else:
		_play_player_animation("walk" if moving else "idle")


func _normalize_player_model_to_height(visual: Node3D, target_height: float) -> void:
	# Match the NPC normalization exactly: a player HLM must render as a 7-foot
	# Halas citizen even when the imported rig's raw bounding box differs.
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
	var visual_scale := target_height / raw_height
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
	npc = Node3D.new()
	npc.name = "TrainingSpark"
	npc.position = _array_to_vector3(_spawn_data().position)
	add_child(npc)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.65
	sphere.height = 1.3
	body.mesh = sphere
	body.material_override = _material(Color("ff9f43"), true)
	body.position.y = 0.7
	npc.add_child(body)
	npc_health = float(zone.npc_archetypes[_spawn_data().archetype].max_health)
	npc_alive = true

func _build_npc_population() -> void:
	var source_path := str(zone.get("npc_source", ""))
	var models_path := str(zone.get("npc_model_directory", ""))
	if source_path.is_empty() or models_path.is_empty():
		return
	halas_population = HalasNpcPopulation.new()
	halas_population.name = "ClassicHalasPopulation"
	halas_population.configure(source_path, models_path)
	add_child(halas_population)

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
	hud.jump_changed.connect(_set_jump_held)
	hud.joystick_changed.connect(func(value: Vector2): joystick_vector = value)
	hud.look_changed.connect(func(value: Vector2): look_stick = value)
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "MobileHUD"
	add_child(canvas_layer)
	canvas_layer.add_child(hud)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()

func _update_hud() -> void:
	if hud == null:
		return
	var inventory_line := _inventory_summary()
	var progression_line := _progression_summary()
	hud.set_auto_attack(auto_attack_enabled)
	var training_strike := _ability_definition("training_strike")
	var ability_available := not training_strike.is_empty() and _ability_is_learned(training_strike)
	hud.set_ability(str(training_strike.get("display_name", "TRAINING\nSTRIKE")), ability_available, _ability_cooldown_remaining(str(training_strike.get("cooldown_group", ""))))
	var class_line := "Class: %s    Auto: %s" % [_class_display_name(), "ON" if auto_attack_enabled else "OFF"]
	if npc == null:
		var target_line := "No target"
		if not selected_halas_target.is_empty():
			target_line = "Target: %s (Lv %d)" % [str(selected_halas_target.name), int(selected_halas_target.level)]
		hud.set_status("%s\nLevel %d    HP %.0f / %.0f    %s\n%s\n%s\n%s" % [status_text, player_level, player_health, PLAYER_MAX_HEALTH, target_line, class_line, progression_line, inventory_line])
		return
	var npc_name := str(zone.npc_archetypes[_spawn_data().archetype].name)
	var npc_line := "%s: %.0f / %.0f" % [npc_name, npc_health, float(zone.npc_archetypes[_spawn_data().archetype].max_health)] if npc_alive else "%s: respawns in %.0fs" % [npc_name, maxf(0.0, respawn_remaining)]
	hud.set_status("%s\nLevel %d    HP %.0f / %.0f    %s\n%s\n%s\n%s" % [status_text, player_level, player_health, PLAYER_MAX_HEALTH, npc_line, class_line, progression_line, inventory_line])


func _target_nearest_halas_npc() -> void:
	if halas_population == null:
		return
	var forward := -camera_pivot.global_transform.basis.z
	selected_halas_target = halas_population.nearest_target(player.global_position, forward)
	if selected_halas_target.is_empty():
		status_text = "No Halas NPC is in target range."
		return
	halas_population.set_selected_spawn(int(selected_halas_target.spawn2_id))
	status_text = _selected_npc_interaction_summary(selected_halas_target)


func _target_halas_npc_at_screen(screen_position: Vector2) -> void:
	if halas_population == null or camera == null:
		return
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
		return
	var collider: Variant = hit.get("collider")
	if not collider is Area3D:
		return
	var target := halas_population.target_for_pick_area(collider)
	if target.is_empty():
		return
	selected_halas_target = target
	halas_population.set_selected_spawn(int(selected_halas_target.spawn2_id))
	status_text = _selected_npc_interaction_summary(selected_halas_target)

func _selected_npc_interaction_summary(target: Dictionary) -> String:
	# Imported PEQ data is useful for inspection, but the current overlay has no
	# reviewed classic stat/faction corrections. Keep that provenance visible and
	# prevent a selected actor from looking silently combat-ready.
	var details: Array[String] = []
	if str(target.get("merchant_state", "none")) == "candidate":
		details.append("merchant candidate")
	if str(target.get("loot_state", "none")) == "reference_only":
		details.append("loot reference")
	if str(target.get("faction_reaction", "unresolved")) == "unresolved":
		details.append("faction unresolved")
	if details.is_empty():
		details.append("faction indifferent")
	return "You target %s (Lv %d) — %s; combat disabled pending review." % [
		str(target.name), int(target.level), ", ".join(details)
	]

func _load_zone() -> Dictionary:
	var file := FileAccess.open(ZONE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "Invalid test-zone data")
	return parsed

func _load_item_definitions() -> Dictionary:
	var file := FileAccess.open(ITEM_PATH, FileAccess.READ)
	assert(file != null, "Unable to read item definitions: %s" % ITEM_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and parsed.get("items") is Dictionary, "Invalid item definitions")
	return parsed.items

func _load_player_class_definitions() -> Dictionary:
	var file := FileAccess.open(PLAYER_CLASS_PATH, FileAccess.READ)
	assert(file != null, "Unable to read player class definitions: %s" % PLAYER_CLASS_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and parsed.get("classes") is Dictionary and parsed.get("abilities") is Dictionary, "Invalid player class definitions")
	return parsed

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Unable to open offline save for reading: %s" % SAVE_PATH)
		return
	var saved = JSON.parse_string(file.get_as_text())
	if not saved is Dictionary or saved.get("zone_id") != zone.id:
		return
	if int(saved.get("player_spawn_revision", -1)) == int(zone.get("player_spawn_revision", 0)):
		player.global_position = _array_to_vector3(saved.get("player_position", zone.player_spawn))
	player_health = clampf(float(saved.get("player_health", PLAYER_MAX_HEALTH)), 1.0, PLAYER_MAX_HEALTH)
	player_xp_total = clampi(int(saved.get("player_xp_total", 0)), 0, _xp_cap_total())
	player_level = _level_for_xp(player_xp_total)
	player_class_id = int(saved.get("class_id", 1))
	if _class_definition().is_empty():
		push_warning("Saved player class is unavailable; using Warrior fixture class.")
		player_class_id = 1
	ability_cooldowns = _sanitized_ability_cooldowns(saved.get("ability_cooldowns", {}))
	# Toggle/target state is intentionally transient, so a reload never resumes
	# unattended combat.
	auto_attack_enabled = false
	primary_attack_remaining = 0.0
	inventory = _sanitized_inventory(saved.get("inventory", {}))
	if npc == null:
		return
	npc_alive = bool(saved.get("npc_alive", true))
	npc_health = float(saved.get("npc_health", npc_health))
	respawn_remaining = maxf(0.0, float(saved.get("respawn_remaining", 0.0)))
	npc_loot_awarded = bool(saved.get("npc_loot_awarded", not npc_alive))
	npc.visible = npc_alive
	if npc_alive:
		npc.global_position = _array_to_vector3(saved.get("npc_position", _spawn_data().position))

func _save_game() -> void:
	if player_dead:
		return
	var saved := {"zone_id": zone.id, "player_spawn_revision": int(zone.get("player_spawn_revision", 0)), "player_position": [player.global_position.x, player.global_position.y, player.global_position.z], "player_health": player_health, "inventory": inventory, "progression_version": int(_progression().get("formula_version", 1)), "player_xp_total": player_xp_total, "player_level": player_level, "class_id": player_class_id, "ability_cooldowns": _sanitized_ability_cooldowns(ability_cooldowns)}
	if npc != null:
		saved.merge({"npc_alive": npc_alive, "npc_health": npc_health, "npc_position": [npc.global_position.x, npc.global_position.y, npc.global_position.z], "respawn_remaining": respawn_remaining, "npc_loot_awarded": npc_loot_awarded})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		# Storage can be unavailable (full, revoked, or temporarily unmounted).
		# Keep the offline loop playable and avoid emitting the same error every
		# autosave interval; a later successful write clears this state.
		if not save_write_failed:
			push_warning("Unable to write offline save: %s" % SAVE_PATH)
			save_write_failed = true
		return
	file.store_string(JSON.stringify(saved))
	save_write_failed = false

func _award_training_loot() -> void:
	if npc_loot_awarded:
		return
	npc_loot_awarded = true
	var rewards: Array = zone.npc_archetypes[_spawn_data().archetype].get("loot", [])
	var awarded: Array[String] = []
	for reward in rewards:
		if not reward is Dictionary:
			continue
		var item_id := str(reward.get("item_id", ""))
		var quantity := int(reward.get("quantity", 0))
		if item_id.is_empty() or quantity <= 0 or not item_definitions.has(item_id):
			push_warning("Ignoring invalid Training Spark loot entry: %s" % reward)
			continue
		inventory[item_id] = int(inventory.get(item_id, 0)) + quantity
		awarded.append("%s ×%d" % [str(item_definitions[item_id].get("display_name", item_id)), quantity])
	if not awarded.is_empty():
		status_text = "Training Spark defeated — looted %s." % ", ".join(awarded)

func _award_training_xp() -> void:
	var reward := int(zone.npc_archetypes[_spawn_data().archetype].get("xp_reward", 0))
	if reward <= 0:
		return
	var previous_level := player_level
	player_xp_total = mini(_xp_cap_total(), player_xp_total + reward)
	player_level = _level_for_xp(player_xp_total)
	if player_level > previous_level:
		status_text = "Training Spark defeated — level %d reached!" % player_level
	else:
		status_text = "Training Spark defeated — gained %d XP." % reward

func _progression() -> Dictionary:
	return zone.get("progression", {})

func _xp_threshold(level: int) -> int:
	# EQEmu GetEXPForLevel's classic cubic threshold shape, without the
	# timeline-sensitive race/class modifiers. Thresholds are cumulative.
	var hell_modifier := 1.0
	if level >= 31 and level <= 35:
		hell_modifier = 1.1
	elif level >= 36 and level <= 40:
		hell_modifier = 1.2
	elif level >= 41 and level <= 45:
		hell_modifier = 1.3
	elif level >= 46 and level <= 51:
		hell_modifier = 1.4
	elif level == 52:
		hell_modifier = 1.5
	elif level == 53:
		hell_modifier = 1.6
	elif level == 54:
		hell_modifier = 1.7
	elif level == 55:
		hell_modifier = 1.9
	elif level == 56:
		hell_modifier = 2.1
	elif level == 57:
		hell_modifier = 2.3
	elif level == 58:
		hell_modifier = 2.5
	elif level == 59:
		hell_modifier = 2.7
	elif level == 60:
		hell_modifier = 3.0
	elif level >= 61:
		hell_modifier = 3.1
	return int(pow(maxi(0, level - 1), 3) * 1000.0 * hell_modifier)

func _max_level() -> int:
	return maxi(1, int(_progression().get("max_level", 50)))

func _xp_cap_total() -> int:
	return _xp_threshold(_max_level() + 1)

func _level_for_xp(total_xp: int) -> int:
	var level := 1
	while level < _max_level() and total_xp >= _xp_threshold(level + 1):
		level += 1
	return level

func _progression_summary() -> String:
	if player_level >= _max_level():
		return "XP: %d (level cap)" % player_xp_total
	var threshold := _xp_threshold(player_level)
	var next_threshold := _xp_threshold(player_level + 1)
	return "XP: %d / %d" % [player_xp_total - threshold, next_threshold - threshold]

func _sanitized_inventory(saved_inventory: Variant) -> Dictionary:
	var restored: Dictionary = {}
	if not saved_inventory is Dictionary:
		return restored
	for item_id_variant in saved_inventory:
		var item_id := str(item_id_variant)
		var quantity := int(saved_inventory[item_id_variant])
		if item_definitions.has(item_id) and quantity > 0:
			restored[item_id] = quantity
	return restored

func _inventory_summary() -> String:
	if inventory.is_empty():
		return "Inventory: empty"
	var item_ids: Array = inventory.keys()
	item_ids.sort()
	var entries: Array[String] = []
	for item_id_variant in item_ids:
		var item_id := str(item_id_variant)
		entries.append("%s ×%d" % [str(item_definitions[item_id].get("display_name", item_id)), int(inventory[item_id])])
	return "Inventory: %s" % ", ".join(entries)

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _spawn_data() -> Dictionary:
	return zone.spawns[0]

func _array_to_vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

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
