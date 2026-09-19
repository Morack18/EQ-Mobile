extends SceneTree

var _failures: Array[String] = []


class PauseIntegrationGame:
	extends Node

	var simulation_clock := SimulationClock.new()
	var runtime_paused := false
	var save_count := 0
	var save_saw_frozen_state := false

	func _set_runtime_paused(
		paused: bool
	) -> void:
		runtime_paused = paused

	func _save_game() -> void:
		save_count += 1
		save_saw_frozen_state = (
			runtime_paused
			and simulation_clock.is_paused()
		)


func _init() -> void:
	_test_shared_actor_contract()
	_test_stats_and_attachment_contract()
	_test_halas_attachment_mapping()
	_test_resources_and_runtime_snapshot()
	_test_heading_movement_target_and_lifecycle()
	_test_runtime_pause_freezes_halas_bridge()
	_test_effect_container_and_simulation_timer()
	_test_controller_attachment_drives_behavior()
	_test_removed_target_cleanup()
	_test_halas_bulk_definition_mapping()
	_test_halas_source_mapping()
	if _failures.is_empty():
		print(
			"PASS: Phase 5 generic actor contract, resources, state, "
			+ "effects, and Halas appearance separation hold."
		)
		quit(0)
		return

	for failure in _failures:
		push_error(failure)

	print(
		"FAIL: Phase 5 actor model tests (%d failures)."
		% _failures.size()
	)
	quit(1)


func _test_shared_actor_contract() -> void:
	var source_stats := {
		"strength": 75,
		"stamina": 80,
	}
	var source_appearance := {
		"model_name": "hlm_s0_h0",
		"texture": 0,
	}

	var player := EntityFactory.create({
		"entity_id": "test:player",
		"definition_id": "fixture:player:test",
		"kind": "player",
		"display_name": "Test Player",
		"race_id": 2,
		"race_ref": "eqemu:race:2",
		"gender_id": 0,
		"class_id": 1,
		"class_ref": "eqemu:class:1",
		"level": 7,
		"base_stats": source_stats,
		"derived_stats": {
			"armor_class": 12,
		},
		"max_health": 90.0,
		"max_mana": 25.0,
		"max_endurance": 40.0,
		"appearance": source_appearance,
		"inventory_attachment": {
			"kind": "test_inventory",
		},
		"equipment_attachment": {
			"kind": "test_equipment",
		},
		"controller_attachment": {
			"kind": "local_player",
		},
	})

	var npc := EntityFactory.create({
		"entity_id": "test:npc",
		"definition_id": "fixture:npc:test",
		"kind": "npc",
		"display_name": "Test NPC",
		"race_id": 90,
		"race_ref": "eqemu:race:90",
		"gender_id": 1,
		"class_id": 41,
		"class_ref": "eqemu:class:41",
		"level": 45,
		"max_health": 1.0,
		"combat_enabled": false,
		"appearance": {
			"model_name": "hlf_s0_h0",
		},
		"faction_identity": {
			"npc_faction_ref": "peq:npc_faction:94",
		},
	})

	_expect(
		player.kind == "player"
		and npc.kind == "npc",
		"Player and NPC kinds do not specialize the shared actor contract."
	)
	_expect(
		player.race_id == 2
		and player.class_id == 1
		and player.gender_id == 0
		and player.level == 7,
		"Player actor identity fields were not configured."
	)
	_expect(
		npc.race_id == 90
		and npc.class_id == 41
		and npc.gender_id == 1
		and npc.level == 45,
		"NPC actor identity fields were not configured."
	)
	_expect(
		str(
			player.appearance.get(
				"model_name",
				""
			)
		) == "hlm_s0_h0",
		"Player appearance was not attached separately."
	)
	_expect(
		not player.appearance.has("race_id")
		and not player.appearance.has("class_id"),
		"Appearance data duplicated gameplay race/class identity."
	)

	source_stats["strength"] = 1
	source_appearance["model_name"] = "mutated"

	_expect(
		int(
			player.base_stats.get(
				"strength",
				0
			)
		) == 75,
		"Base stat container was not defensively copied."
	)
	_expect(
		str(
			player.appearance.get(
				"model_name",
				""
			)
		) == "hlm_s0_h0",
		"Appearance container was not defensively copied."
	)
	_expect(
		str(
			player.inventory_attachment.get(
				"kind",
				""
			)
		) == "test_inventory"
		and str(
			npc.faction_identity.get(
				"npc_faction_ref",
				""
			)
		) == "peq:npc_faction:94",
		"Actor attachment containers were not retained."
	)


func _test_stats_and_attachment_contract() -> void:
	var actor := EntityFactory.create({
		"entity_id": "test:attachments",
		"definition_id": "fixture:actor:attachments",
		"base_stats": {
			"strength": 75,
		},
		"derived_stats": {
			"armor_class": 12.5,
		},
		"faction_identity": {
			"npc_faction_ref": "peq:npc_faction:94",
		},
	})

	_expect(
		is_equal_approx(
			actor.base_stat_value(
				"strength"
			),
			75.0
		),
		"Base-stat accessor failed."
	)
	_expect(
		is_equal_approx(
			actor.derived_stat_value(
				"armor_class"
			),
			12.5
		),
		"Derived-stat accessor failed."
	)

	_expect(
		actor.set_base_stat_value(
			"stamina",
			81.0
		)
		and actor.set_derived_stat_value(
			"attack",
			22.0
		),
		"Stat mutation rejected valid IDs."
	)

	_expect(
		is_equal_approx(
			actor.base_stat_value(
				"stamina"
			),
			81.0
		)
		and is_equal_approx(
			actor.derived_stat_value(
				"attack"
			),
			22.0
		),
		"Stat mutation was not retained."
	)

	_expect(
		actor.attachment_kind(
			actor.faction_identity
		)
		== GameplayEntity.ATTACHMENT_FACTION_IDENTITY,
		"Faction attachment kind was not normalized."
	)
	_expect(
		actor.faction_reference()
		== "peq:npc_faction:94",
		"Faction reference accessor failed."
	)
	_expect(
		actor.attachment_kind(
			actor.inventory_attachment
		)
		== GameplayEntity.ATTACHMENT_NONE
		and actor.attachment_kind(
			actor.equipment_attachment
		)
		== GameplayEntity.ATTACHMENT_NONE,
		"Empty attachments were not normalized."
	)

	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(301)
	)
	simulation.player_entity_id = (
		"test:attachment_player"
	)

	var player := EntityFactory.create({
		"entity_id": "test:attachment_player",
		"definition_id": "fixture:player:attachments",
		"kind": "player",
	})

	simulation.add_entity(
		player,
		false,
		false
	)

	_expect(
		player.attachment_kind(
			player.faction_identity
		)
		== GameplayEntity.ATTACHMENT_PLAYER_FACTION,
		"Player faction service attachment was not bound."
	)
	_expect(
		player.attachment_kind(
			player.inventory_attachment
		)
		== GameplayEntity.ATTACHMENT_PLAYER_INVENTORY,
		"Player inventory service attachment was not bound."
	)
	_expect(
		player.attachment_kind(
			player.equipment_attachment
		)
		== GameplayEntity.ATTACHMENT_PLAYER_EQUIPMENT_PENDING,
		"Pending player equipment state is not explicit."
	)


func _test_halas_attachment_mapping() -> void:
	var source_npc := {
		"id": 49001,
		"key": "peq:npc:49001",
		"name": "Attachment Merchant",
		"race": 90,
		"race_ref": "eqemu:race:90",
		"gender": 0,
		"class": 41,
		"class_ref": "eqemu:class:41",
		"level": 10,
		"texture": 0,
		"face": 0,
		"size": 7.0,
		"merchant_id": 77,
		"merchant_ref": "peq:merchant:77",
		"npc_faction_id": 1337,
		"npc_faction_ref": "peq:npc_faction:1337",
	}

	var actor := EntityFactory.create(
		HalasEntityAdapter
		.neutral_definition_from_source_npc(
			source_npc,
			39001,
			Vector3.ZERO
		)
	)

	_expect(
		actor.attachment_kind(
			actor.inventory_attachment
		)
		== GameplayEntity.ATTACHMENT_MERCHANT_CATALOG,
		"Halas merchant association was not attached."
	)
	_expect(
		int(
			actor.inventory_attachment.get(
				"merchant_id",
				0
			)
		) == 77
		and str(
			actor.inventory_attachment.get(
				"merchant_ref",
				""
			)
		) == "peq:merchant:77",
		"Halas merchant identity was lost."
	)
	_expect(
		bool(
			actor.inventory_attachment.get(
				"read_only",
				false
			)
		)
		and not actor.inventory_attachment.has(
			"entries"
		),
		"Merchant catalog became actor-owned inventory."
	)
	_expect(
		actor.attachment_kind(
			actor.equipment_attachment
		)
		== GameplayEntity.ATTACHMENT_SOURCE_EQUIPMENT_UNREVIEWED,
		"Halas equipment source boundary was lost."
	)
	_expect(
		actor.attachment_kind(
			actor.faction_identity
		)
		== GameplayEntity.ATTACHMENT_FACTION_IDENTITY
		and actor.faction_reference()
		== "peq:npc_faction:1337",
		"Halas faction attachment was not normalized."
	)

func _test_resources_and_runtime_snapshot() -> void:
	var actor := EntityFactory.create({
		"entity_id": "test:resources",
		"definition_id": "fixture:actor:resources",
		"max_health": 80.0,
		"max_mana": 30.0,
		"max_endurance": 55.0,
	})

	_expect(
		actor.spawn(10.0)
		and actor.activate(),
		"Resource test actor did not spawn."
	)

	_expect(
		is_equal_approx(actor.health, 80.0)
		and is_equal_approx(actor.mana, 30.0)
		and is_equal_approx(actor.endurance, 55.0),
		"Spawn did not initialize all shared resources to maximum."
	)

	actor.health = 23.0
	actor.mana = 11.0
	actor.endurance = 17.0

	var snapshot := actor.runtime_snapshot(10.0)

	actor.health = 1.0
	actor.mana = 1.0
	actor.endurance = 1.0

	actor.restore_runtime(
		snapshot,
		25.0
	)

	_expect(
		is_equal_approx(actor.health, 23.0)
		and is_equal_approx(actor.mana, 11.0)
		and is_equal_approx(actor.endurance, 17.0),
		"HP/mana/endurance did not survive actor runtime restore."
	)


func _test_heading_movement_target_and_lifecycle() -> void:
	var actor := EntityFactory.create({
		"entity_id": "test:state",
		"definition_id": "fixture:actor:state",
		"max_health": 20.0,
		"combat_enabled": true,
		"death_delay_seconds": 1.0,
	})

	actor.spawn(0.0)
	actor.activate()

	actor.set_heading_radians(PI * 0.5)

	_expect(
		actor.facing.distance_to(
			Vector3.RIGHT
		) < 0.0001,
		"Heading-to-facing conversion failed."
	)
	_expect(
		absf(
			actor.heading_radians()
			- PI * 0.5
		) < 0.0001,
		"Facing-to-heading conversion failed."
	)

	actor.set_movement_state(
		GameplayEntity.MOVEMENT_MOVING,
		Vector3(2.0, 0.0, 0.0)
	)
	actor.set_target_entity("test:target")
	actor.set_combat_state(
		GameplayEntity.COMBAT_ENGAGED
	)

	_expect(
		actor.movement_state
		== GameplayEntity.MOVEMENT_MOVING
		and actor.target_entity_id == "test:target"
		and actor.combat_state
		== GameplayEntity.COMBAT_ENGAGED,
		"Movement, target, or combat state was not represented."
	)

	_expect(
		actor.begin_dying(3.0),
		"Actor could not enter the dying state."
	)
	_expect(
		actor.target_entity_id.is_empty()
		and actor.movement_state
		== GameplayEntity.MOVEMENT_IDLE
		and actor.health == 0.0,
		"Dying transition did not clear transient actor state."
	)


func _test_runtime_pause_freezes_halas_bridge() -> void:
	var population := HalasNpcPopulation.new()
	var actor := (
		HalasNpcPopulation.NpcActor.new()
	)

	actor.node = Node3D.new()
	actor.visual = Node3D.new()
	actor.spawn2_id = 99001
	actor.pause_remaining = 5.0
	actor.patrol.append({
		"heading_eq": -1.0,
		"pause_seconds": 0.0,
	})
	actor.patrol_targets.append(
		Vector3.ZERO
	)
	actor.movement_velocity = Vector3(
		2.0,
		0.0,
		0.0
	)

	population._actors.append(
		actor
	)
	population._actors_by_spawn2[
		actor.spawn2_id
	] = actor

	population.set_runtime_paused(
		true
	)
	population._process(
		2.0
	)

	_expect(
		population.is_runtime_paused(),
		"Halas population did not enter runtime pause."
	)
	_expect(
		is_equal_approx(
			actor.pause_remaining,
			5.0
		),
		"Paused Halas patrol timer advanced."
	)
	_expect(
		population.movement_velocity_for_spawn(
			actor.spawn2_id
		) == Vector3.ZERO,
		"Paused Halas actor retained mirrored movement velocity."
	)

	population.set_runtime_paused(
		false
	)
	population._process(
		2.0
	)

	_expect(
		not population.is_runtime_paused()
		and is_equal_approx(
			actor.pause_remaining,
			3.0
		),
		"Halas patrol did not resume from frozen state."
	)

	actor.node.free()
	actor.visual.free()
	population.free()

	var game := PauseIntegrationGame.new()
	var bridge := RuntimeLifecycleBridge.new()

	get_root().add_child(
		game
	)
	game.add_child(
		bridge
	)

	bridge.set_simulation_paused(
		true
	)

	_expect(
		game.simulation_clock.is_paused()
		and game.runtime_paused,
		"Lifecycle bridge did not freeze domain and presentation together."
	)
	_expect(
		game.save_count == 1
		and game.save_saw_frozen_state,
		"Lifecycle bridge saved before runtime state was fully frozen."
	)

	bridge.set_simulation_paused(
		false
	)

	_expect(
		not game.simulation_clock.is_paused()
		and not game.runtime_paused,
		"Lifecycle bridge did not resume domain and presentation together."
	)

	game.queue_free()

func _test_effect_container_and_simulation_timer() -> void:
	var clock := SimulationClock.new()
	var simulation := Simulation.new(
		clock,
		SimulationRng.new(123)
	)

	var actor := EntityFactory.create({
		"entity_id": "test:effect_target",
		"definition_id": "fixture:actor:effect_target",
		"max_health": 10.0,
	})

	simulation.add_entity(
		actor,
		true,
		false
	)

	_expect(
		simulation.apply_timed_effect(
			actor.entity_id,
			"fixture:effect:test",
			2.0,
			{
				"magnitude": 3,
			}
		),
		"Simulation rejected valid timed effect."
	)
	_expect(
		actor.has_effect(
			"fixture:effect:test"
		),
		"Actor effect container did not mirror canonical timed effect."
	)

	var saved := simulation.snapshot()

	actor.clear_effects()
	simulation.restore_snapshot(saved)

	_expect(
		actor.has_effect(
			"fixture:effect:test"
		),
		"Actor effect container was not rebuilt during restore."
	)

	simulation.advance(2.1)

	_expect(
		not actor.has_effect(
			"fixture:effect:test"
		)
		and not simulation.has_timed_effect(
			actor.entity_id,
			"fixture:effect:test"
		),
		"Expired timed effect remained attached to the actor."
	)


func _test_controller_attachment_drives_behavior() -> void:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(77)
	)

	var actor := EntityFactory.create({
		"entity_id": "test:controller_actor",
		"definition_id": "fixture:actor:controller",
		"kind": "npc",
		"spawn_position": Vector3.ZERO,
		"combat_enabled": true,
		"controller_attachment": {
			"kind": "simple_npc_behavior",
			"behavior": {
				"move_speed": 1.0,
				"aggro_range": 10.0,
			},
			"combat_profile": {
				"id": "fixture:attack:controller",
				"damage": 3.0,
				"range": 2.0,
				"requires_facing": false,
				"requires_los": false,
			},
		},
	})

	var target := EntityFactory.create({
		"entity_id": "test:controller_target",
		"definition_id": "fixture:actor:controller_target",
		"kind": "npc",
		"spawn_position": Vector3(1.0, 0.0, 0.0),
		"max_health": 20.0,
		"combat_enabled": true,
	})

	simulation.add_entity(actor, true, false)
	simulation.add_entity(target, true, false)

	var system := SimpleNpcBehaviorSystem.new()
	var result := system.update_entity(
		simulation,
		actor.entity_id,
		target.entity_id,
		0.1
	)

	_expect(
		str(result.get("state", "")) == "attacking",
		"Controller attachment did not drive simple NPC behavior."
	)
	_expect(
		is_equal_approx(target.health, 17.0),
		"Controller combat profile did not drive the attack."
	)
	_expect(
		actor.target_entity_id == target.entity_id
		and actor.combat_state
		== GameplayEntity.COMBAT_ENGAGED,
		"Controller-driven actor did not record target/combat state."
	)
	_expect(
		not actor.metadata.has("behavior")
		and not actor.metadata.has("combat_profile"),
		"Controller test accidentally depended on legacy metadata."
	)


func _test_removed_target_cleanup() -> void:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(91)
	)

	var observer := EntityFactory.create({
		"entity_id": "test:observer",
		"definition_id": "fixture:actor:observer",
	})

	var target := EntityFactory.create({
		"entity_id": "test:removed_target",
		"definition_id": "fixture:actor:removed_target",
	})

	simulation.add_entity(observer, true, false)
	simulation.add_entity(target, true, false)

	_expect(
		simulation.set_target(
			observer.entity_id,
			target.entity_id
		),
		"Simulation rejected a valid actor target."
	)

	_expect(
		observer.target_entity_id == target.entity_id,
		"Simulation did not attach the selected target."
	)

	_expect(
		simulation.remove_entity(target.entity_id),
		"Target entity could not be permanently removed."
	)

	_expect(
		observer.target_entity_id.is_empty(),
		"Removed entity remained referenced as another actor's target."
	)

	_expect(
		simulation.release_entity(
			target.entity_id
		),
		"Removed transient entity could not be released from simulation."
	)

	_expect(
		simulation.entity(
			target.entity_id
		) == null,
		"Released transient entity remained registered in simulation."
	)

	_expect(
		simulation.drain_events().is_empty(),
		"Released transient entity left stale queued events."
	)

	var replacement := EntityFactory.create({
		"entity_id":
			target.entity_id,
		"definition_id":
			"fixture:actor:replacement",
	})

	simulation.add_entity(
		replacement,
		true,
		false
	)

	_expect(
		simulation.entity(
			target.entity_id
		) == replacement,
		"Released transient entity ID could not be registered again."
	)


func _test_halas_bulk_definition_mapping() -> void:
	var targets: Array = [
		{
			"spawn2_id": 31001,
			"npc_type_id": 41001,
			"name": "First Halas NPC",
			"race_id": 90,
			"race_ref": "eqemu:race:90",
			"gender_id": 0,
			"class": 1,
			"class_ref": "eqemu:class:1",
			"level": 3,
			"model_name": "hlm_s0_h0",
			"texture": 0,
			"face": 0,
			"source_size": 7.0,
			"source_hp": 25,
			"source_mana": 0,
		},
		{
			"spawn2_id": 31002,
			"npc_type_id": 41002,
			"name": "Second Halas NPC",
			"race_id": 90,
			"race_ref": "eqemu:race:90",
			"gender_id": 1,
			"class": 9,
			"class_ref": "eqemu:class:9",
			"level": 4,
			"model_name": "hlf_s0_h0",
			"texture": 0,
			"face": 0,
			"source_size": 7.0,
			"source_hp": 30,
			"source_mana": 10,
		},
	]

	var definitions := (
		HalasEntityAdapter
		.neutral_definitions_from_targets(
			targets
		)
	)

	_expect(
		definitions.size() == 2,
		"Bulk Halas mapping did not preserve the roster."
	)

	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(201)
	)

	for definition in definitions:
		simulation.add_entity(
			EntityFactory.create(
				definition
			),
			true,
			false
		)

	var first := simulation.entity(
		"halas:spawn:31001"
	)
	var second := simulation.entity(
		"halas:spawn:31002"
	)

	_expect(
		first != null
		and second != null,
		"Bulk Halas mapping did not create distinct actors."
	)

	if first == null or second == null:
		return

	_expect(
		first.definition_id
		== "peq:npc:41001"
		and second.definition_id
		== "peq:npc:41002",
		"Bulk Halas actors lost definition identity."
	)

	_expect(
		first.level == 3
		and second.level == 4
		and first.class_id == 1
		and second.class_id == 9,
		"Bulk Halas actors lost structural identity."
	)

	_expect(
		not first.combat_enabled
		and not second.combat_enabled,
		"Bulk Halas mapping activated unreviewed combat."
	)

	_expect(
		is_equal_approx(
			first.max_health,
			1.0
		)
		and is_equal_approx(
			second.max_health,
			1.0
		),
		"Bulk Halas mapping promoted source HP into gameplay."
	)
func _test_halas_source_mapping() -> void:
	var source_npc := {
		"id": 29000,
		"key": "peq:npc:29000",
		"name": "Dargon",
		"race": 90,
		"race_ref": "eqemu:race:90",
		"gender": 1,
		"class": 41,
		"class_ref": "eqemu:class:41",
		"level": 45,
		"texture": 2,
		"face": 3,
		"size": 7.0,
		"hp": 5875,
		"mana": 900,
		"npc_faction_id": 1337,
		"npc_faction_ref": "peq:npc_faction:1337",
	}

	var definition := (
		HalasEntityAdapter
		.neutral_definition_from_source_npc(
			source_npc,
			10001,
			Vector3(4.0, 5.0, 6.0)
		)
	)

	var actor := EntityFactory.create(definition)

	_expect(
		actor.race_id == 90
		and actor.race_ref == "eqemu:race:90"
		and actor.gender_id == 1
		and actor.class_id == 41
		and actor.class_ref == "eqemu:class:41"
		and actor.level == 45,
		"Halas adapter did not promote structural actor identity."
	)

	_expect(
		int(
			actor.appearance.get(
				"texture",
				-1
			)
		) == 2
		and int(
			actor.appearance.get(
				"face",
				-1
			)
		) == 3
		and is_equal_approx(
			float(
				actor.appearance.get(
					"source_size",
					0.0
				)
			),
			7.0
		),
		"Halas appearance fields were not separated into appearance data."
	)

	_expect(
		not actor.appearance.has("race_id")
		and not actor.appearance.has("class_id"),
		"Halas appearance container duplicated gameplay identity."
	)

	_expect(
		not actor.combat_enabled
		and is_equal_approx(
			actor.max_health,
			1.0
		)
		and is_equal_approx(
			actor.max_mana,
			0.0
		)
		and is_equal_approx(
			actor.combat_size,
			8.0
		),
		"Unreviewed PEQ HP/mana/visual size leaked into gameplay state."
	)

	_expect(
		int(
			actor.metadata.get(
				"source_hp",
				0
			)
		) == 5875
		and int(
			actor.metadata.get(
				"source_mana",
				0
			)
		) == 900,
		"Source HP/mana provenance was lost."
	)

	_expect(
		str(
			actor.faction_identity.get(
				"npc_faction_ref",
				""
			)
		) == "peq:npc_faction:1337",
		"Halas faction identity was not attached to the actor."
	)


func _expect(
	condition: bool,
	message: String
) -> void:
	if not condition:
		_failures.append(message)
