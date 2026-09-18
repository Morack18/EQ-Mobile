extends SceneTree

const TEST_SAVE_PATH := "user://phase3_persistence_round_trip_test.json"
const TEST_CORRUPT_SAVE_PATH := "user://phase3_persistence_corrupt_test.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_entity_lifecycle_transitions()
	_test_seeded_rng_reproducibility()
	_test_attack_damage_death_and_single_rewards()
	_test_progression_threshold_and_level_change()
	_test_inventory_mutation_without_ui()
	_test_persistence_actual_io_round_trip()
	_test_persistence_corrupt_save_handling()
	_test_legacy_save_migration()
	_test_simulation_clock_cooldown_without_wall_time()
	_test_fixture_and_imported_npc_share_factory_and_combat_path()
	_test_full_sequence_is_deterministic()

	if _failures.is_empty():
		print("Phase 3 simulation architecture tests: PASS")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)

	print("Phase 3 simulation architecture tests: FAIL (%d)" % _failures.size())
	quit(1)


func _test_entity_lifecycle_transitions() -> void:
	var entity := EntityFactory.create({
		"entity_id": "test:lifecycle:1",
		"definition_id": "fixture:npc:lifecycle",
		"max_health": 10.0,
		"respawn_seconds": 5.0,
		"death_delay_seconds": 1.0,
	})

	_expect(entity.lifecycle == GameplayEntity.Lifecycle.CREATED, "lifecycle starts at create")
	_expect(entity.spawn(0.0), "create -> spawn transition succeeds")
	_expect(entity.lifecycle == GameplayEntity.Lifecycle.SPAWNED, "spawn state is explicit")
	_expect(entity.activate(), "spawn -> active transition succeeds")
	_expect(entity.lifecycle == GameplayEntity.Lifecycle.ACTIVE, "entity becomes active")
	_expect(entity.begin_dying(1.0), "active -> dying transition succeeds")
	_expect(not entity.begin_dying(1.0), "death cannot begin twice in one life")
	_expect(entity.mark_dead(2.0), "dying -> dead transition succeeds")
	_expect(entity.begin_respawning(), "dead -> respawning transition succeeds")
	_expect(entity.spawn(7.0), "respawning -> spawned transition succeeds")
	_expect(entity.activate(), "respawned entity returns to active")
	_expect(entity.life_number == 2, "respawn increments the life number")
	_expect(entity.remove(), "active -> removed transition succeeds")
	_expect(entity.lifecycle == GameplayEntity.Lifecycle.REMOVED, "removed is permanent lifecycle state")


func _test_seeded_rng_reproducibility() -> void:
	var first := SimulationRng.new(8675309)
	var second := SimulationRng.new(8675309)
	var first_rolls: Array = []
	var second_rolls: Array = []

	for _index in 12:
		first_rolls.append(first.randi_range(1, 100000))
		second_rolls.append(second.randi_range(1, 100000))

	_expect(first_rolls == second_rolls, "same RNG seed produces the same sequence")
	_expect(first.initial_seed() == 8675309, "RNG records its initial seed")


func _test_attack_damage_death_and_single_rewards() -> void:
	var simulation := _new_test_simulation(101)
	var player := _player_entity()
	var target := EntityFactory.create({
		"entity_id": "test:target:reward",
		"definition_id": "fixture:npc:reward_target",
		"display_name": "Reward Target",
		"spawn_position": Vector3(1.0, 0.0, 0.0),
		"max_health": 10.0,
		"combat_enabled": true,
		"hostile": true,
		"respawn_seconds": -1.0,
		"rewards": {
			"items": [{"item_key": "fixture:item:test", "quantity": 1}],
			"xp": 1000,
		},
	})

	simulation.add_entity(player)
	simulation.add_entity(target)
	simulation.drain_events()

	var profile := {
		"id": "fixture:attack:test_kill",
		"damage": 10.0,
		"range": 5.0,
		"requires_facing": true,
		"requires_los": false,
	}
	var result := simulation.request_attack(player.entity_id, target.entity_id, profile)

	_expect(bool(result.get("success", false)), "generic attack succeeds")

	var first_events := simulation.drain_events()
	_expect(
		_event_index(first_events, GameplayEvent.Type.ATTACK_REQUESTED)
			< _event_index(first_events, GameplayEvent.Type.ATTACK_PERFORMED),
		"attack requested precedes attack performed"
	)
	_expect(
		_event_index(first_events, GameplayEvent.Type.ATTACK_PERFORMED)
			< _event_index(first_events, GameplayEvent.Type.DAMAGE),
		"attack performed precedes damage"
	)
	_expect(
		_event_index(first_events, GameplayEvent.Type.DAMAGE)
			< _event_index(first_events, GameplayEvent.Type.DEATH),
		"damage precedes death"
	)
	_expect(_count_events(first_events, GameplayEvent.Type.DEATH) == 1, "death fires exactly once")
	_expect(_count_events(first_events, GameplayEvent.Type.XP_AWARDED) == 1, "XP award fires exactly once")
	_expect(_count_events(first_events, GameplayEvent.Type.LEVEL_CHANGED) == 1, "XP threshold crossing emits one level-change event")
	_expect(_count_events(first_events, GameplayEvent.Type.ITEM_GAINED) == 1, "item award fires exactly once")
	_expect(simulation.inventory.quantity("fixture:item:test") == 1, "reward item mutated inventory exactly once")
	_expect(simulation.progression.xp_total == 1000, "reward XP mutated progression exactly once")

	var duplicate := simulation.request_attack(player.entity_id, target.entity_id, profile)
	_expect(not bool(duplicate.get("success", true)), "dead target rejects a duplicate attack")

	var duplicate_events := simulation.drain_events()
	_expect(_count_events(duplicate_events, GameplayEvent.Type.DEATH) == 0, "duplicate attack cannot emit a second death")
	_expect(_count_events(duplicate_events, GameplayEvent.Type.XP_AWARDED) == 0, "duplicate attack cannot emit a second XP award")
	_expect(_count_events(duplicate_events, GameplayEvent.Type.ITEM_GAINED) == 0, "duplicate attack cannot emit a second item award")
	_expect(simulation.inventory.quantity("fixture:item:test") == 1, "duplicate death does not duplicate loot")
	_expect(simulation.progression.xp_total == 1000, "duplicate death does not duplicate XP")


func _test_progression_threshold_and_level_change() -> void:
	var progression := ProgressionState.new()
	progression.configure({"max_level": 50})

	_expect(progression.xp_threshold(2) == 1000, "current unreviewed progression threshold remains deterministic")
	progression.award_xp(999)
	_expect(progression.level == 1, "999 XP remains level 1 under the current progression rule")

	var result := progression.award_xp(1)
	_expect(progression.level == 2, "1000 total XP reaches level 2 under the current progression rule")
	_expect(
		int(result.get("previous_level", 0)) == 1
			and int(result.get("level", 0)) == 2,
		"level-change result reports both levels"
	)


func _test_inventory_mutation_without_ui() -> void:
	var inventory := InventoryState.new()
	inventory.configure({
		"fixture:item:test": {
			"key": "fixture:item:test",
			"stackable": true,
			"stack_size": 20,
			"max_charges": 0,
		},
	}, 2)

	_expect(inventory.add_item("fixture:item:test", 25), "headless inventory add succeeds")
	_expect(inventory.entries().size() == 2, "stacking uses two slots for 25 items at stack size 20")
	_expect(inventory.quantity("fixture:item:test") == 25, "inventory quantity reflects added items")
	_expect(inventory.remove_item("fixture:item:test", 5), "headless inventory remove succeeds")
	_expect(inventory.quantity("fixture:item:test") == 20, "inventory quantity reflects removed items")


func _test_persistence_actual_io_round_trip() -> void:
	var simulation := _new_test_simulation(505)
	simulation.add_entity(_player_entity())
	simulation.add_entity(_persistence_target_entity())
	simulation.drain_events()

	var player := simulation.entity("player:local")
	player.position = Vector3(4.0, 1.5, -2.0)
	player.health = 73.0

	_expect(
		simulation.grant_item(
			"fixture:test:persistence",
			"fixture:item:test",
			3
		),
		"persistence setup adds inventory state"
	)

	simulation.progression.award_xp(1234)
	simulation.credit_copper(4321)

	var faction_change := simulation.change_faction(
		"fixture:test:persistence",
		"fixture:faction:test",
		125
	)
	_expect(bool(faction_change.get("changed", false)), "persistence setup changes faction state")

	simulation.advance(3.25)

	var cooldown_profile := {
		"id": "fixture:attack:persistence",
		"damage": 1.0,
		"range": 5.0,
		"requires_facing": false,
		"requires_los": false,
		"cooldown_group": "persistence_attack",
		"cooldown_seconds": 7.0,
	}

	var attack_result := simulation.request_attack(
		"player:local",
		"test:target:persistence",
		cooldown_profile
	)
	_expect(bool(attack_result.get("success", false)), "persistence setup creates an active cooldown")
	simulation.drain_events()

	simulation.rng.randi_range(1, 100000)

	var expected_clock := simulation.clock.now_seconds()
	var expected_cooldown := simulation.cooldown_remaining(
		"player:local",
		"persistence_attack"
	)
	var expected_rng: Dictionary = simulation.rng.snapshot()
	var zone_definition := _test_zone_definition()

	var persistence := PersistenceService.new(TEST_SAVE_PATH, simulation.clock)
	persistence.clear()

	var save_result := persistence.save_simulation(zone_definition, simulation)
	_expect(bool(save_result.get("ok", false)), "persistence service writes the simulation to a temporary user save")
	if not bool(save_result.get("ok", false)):
		persistence.clear()
		return

	var restored := _new_test_simulation(999)
	restored.add_entity(_player_entity())
	restored.add_entity(_persistence_target_entity())
	restored.drain_events()

	var loader := PersistenceService.new(TEST_SAVE_PATH, restored.clock)
	var load_result := loader.load_simulation(zone_definition, restored)
	_expect(bool(load_result.get("ok", false)), "persistence service reads the temporary user save")
	_expect(bool(load_result.get("loaded", false)), "persistence service reports that state was loaded")

	if not bool(load_result.get("ok", false)) or not bool(load_result.get("loaded", false)):
		loader.clear()
		return

	var restored_player := restored.entity("player:local")
	var restored_target := restored.entity("test:target:persistence")
	var restored_faction_values := restored.faction.values_snapshot()
	var restored_rng: Dictionary = restored.rng.snapshot()

	_expect(restored_player != null, "saved player entity exists after persistence load")
	_expect(restored_target != null, "saved target entity exists after persistence load")

	if restored_player != null:
		_expect(
			restored_player.position.is_equal_approx(Vector3(4.0, 1.5, -2.0)),
			"player runtime position survives actual save/load I/O"
		)
		_expect(
			is_equal_approx(restored_player.health, 73.0),
			"player runtime health survives actual save/load I/O"
		)

	if restored_target != null:
		_expect(
			is_equal_approx(restored_target.health, 99.0),
			"non-player entity runtime state survives actual save/load I/O"
		)

	_expect(restored.inventory.quantity("fixture:item:test") == 3, "inventory survives actual save/load I/O")
	_expect(restored.progression.xp_total == 1234, "progression survives actual save/load I/O")
	_expect(restored.wallet_total_copper() == 4321, "wallet survives actual save/load I/O")
	_expect(
		int(restored_faction_values.get("fixture:faction:test", 0)) == 125,
		"faction state survives actual save/load I/O"
	)
	_expect(
		is_equal_approx(restored.clock.now_seconds(), expected_clock),
		"simulation clock survives actual save/load I/O"
	)
	_expect(
		is_equal_approx(
			restored.cooldown_remaining("player:local", "persistence_attack"),
			expected_cooldown
		),
		"remaining cooldown survives actual save/load I/O"
	)
	_expect(restored_rng == expected_rng, "exact seeded RNG seed/state survives actual JSON save/load I/O")

	loader.clear()


func _test_persistence_corrupt_save_handling() -> void:
	var simulation := _new_test_simulation(606)
	simulation.add_entity(_player_entity())
	simulation.drain_events()
	simulation.progression.award_xp(321)
	simulation.credit_copper(77)

	var before := JSON.stringify(simulation.snapshot(), "", true)
	var persistence := PersistenceService.new(
		TEST_CORRUPT_SAVE_PATH,
		simulation.clock
	)
	persistence.clear()

	var file := FileAccess.open(TEST_CORRUPT_SAVE_PATH, FileAccess.WRITE)
	_expect(file != null, "corrupt-save test can create its temporary user file")
	if file == null:
		persistence.clear()
		return

	file.store_string("{ this is intentionally invalid JSON")
	file.close()

	var result := persistence.load_simulation(
		_test_zone_definition(),
		simulation
	)

	_expect(not bool(result.get("ok", true)), "corrupt save reports failure")
	_expect(str(result.get("reason", "")) == "invalid", "corrupt save reports invalid state")
	_expect(
		JSON.stringify(simulation.snapshot(), "", true) == before,
		"corrupt save does not replace the existing simulation"
	)

	persistence.clear()


func _test_legacy_save_migration() -> void:
	var persistence := PersistenceService.new(
		"user://phase3_legacy_migration_unused.json"
	)

	var legacy := {
		"zone_id": "test",
		"player_spawn_revision": 2,
		"player_health": 88.0,
		"player_position": [1.0, 2.0, 3.0],
		"npc_alive": false,
		"npc_health": 0.0,
		"npc_position": [5.0, 0.0, 6.0],
		"respawn_remaining": 6.0,
		"npc_loot_awarded": true,
		"inventory": {
			"fixture:item:test": 2,
		},
		"wallet": {
			"platinum": 1,
			"gold": 2,
			"silver": 3,
			"copper": 4,
		},
		"player_xp_total": 1234,
		"faction_values": {
			"fixture:faction:test": 55,
		},
		"class_id": 1,
		"race_id": 2,
		"deity_id": 396,
	}

	var result := persistence.deserialize_envelope(
		JSON.stringify(legacy, "", true),
		"eqm:zone:test",
		"test",
		{
			"player_entity_id": "player:local",
			"legacy_npc_entity_id": "fixture:spawn:training_spark",
			"rng_seed": 707,
		}
	)

	_expect(bool(result.get("ok", false)), "legacy save migration produces a valid envelope")
	_expect(bool(result.get("migrated", false)), "legacy save migration reports migrated=true")

	if not bool(result.get("ok", false)):
		return

	var envelope: Dictionary = result.get("state", {})
	var migrated_simulation: Dictionary = envelope.get("simulation", {})
	var migrated_progression: Dictionary = migrated_simulation.get("progression", {})
	var migrated_inventory: Dictionary = migrated_simulation.get("inventory", {})
	var migrated_factions: Dictionary = migrated_simulation.get("faction_values", {})

	_expect(
		int(envelope.get("schema_version", 0)) == PersistenceService.SAVE_SCHEMA_VERSION,
		"legacy migration upgrades to the current save schema"
	)
	_expect(
		str(envelope.get("zone_key", "")) == "eqm:zone:test",
		"legacy migration preserves the expected zone identity"
	)
	_expect(
		int(migrated_progression.get("xp_total", 0)) == 1234,
		"legacy migration carries old XP into the simulation payload"
	)
	_expect(
		int(migrated_inventory.get("fixture:item:test", 0)) == 2,
		"legacy migration carries old inventory into the simulation payload"
	)
	_expect(
		int(migrated_factions.get("fixture:faction:test", 0)) == 55,
		"legacy migration carries old faction state into the simulation payload"
	)
	_expect(
		migrated_simulation.get("entities") is Dictionary,
		"legacy migration produces an entity-state dictionary"
	)

	var restored := _new_test_simulation(808)
	restored.add_entity(_player_entity())
	restored.add_entity(EntityFactory.create({
		"entity_id": "fixture:spawn:training_spark",
		"definition_id": "fixture:npc:training_spark",
		"kind": "npc",
		"display_name": "Legacy Training Spark",
		"spawn_position": Vector3.ZERO,
		"max_health": 35.0,
		"combat_enabled": true,
		"hostile": true,
		"respawn_seconds": 12.0,
	}))
	restored.drain_events()
	restored.restore_snapshot(migrated_simulation)

	var restored_player := restored.entity("player:local")
	var restored_npc := restored.entity("fixture:spawn:training_spark")
	var faction_values := restored.faction.values_snapshot()

	_expect(
		restored_player != null and is_equal_approx(restored_player.health, 88.0),
		"migrated player entity state is structurally restorable"
	)

	if restored_player != null:
		_expect(
			restored_player.position.is_equal_approx(Vector3(1.0, 2.0, 3.0)),
			"migrated player position is structurally restorable"
		)

	_expect(
		restored_npc != null
			and restored_npc.lifecycle == GameplayEntity.Lifecycle.DEAD,
		"migrated NPC entity state is structurally restorable"
	)
	_expect(
		restored.inventory.quantity("fixture:item:test") == 2,
		"migrated legacy inventory restores through InventoryState"
	)
	_expect(
		restored.progression.xp_total == 1234,
		"migrated legacy XP restores through ProgressionState"
	)
	_expect(
		restored.wallet_total_copper() == 1234,
		"migrated legacy wallet restores through Simulation"
	)
	_expect(
		int(faction_values.get("fixture:faction:test", 0)) == 55,
		"migrated legacy faction values restore through FactionSystem"
	)


func _test_simulation_clock_cooldown_without_wall_time() -> void:
	var simulation := _new_test_simulation(202)
	var player := _player_entity()
	var target := EntityFactory.create({
		"entity_id": "test:target:cooldown",
		"definition_id": "fixture:npc:cooldown_target",
		"spawn_position": Vector3(1.0, 0.0, 0.0),
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": true,
	})

	simulation.add_entity(player)
	simulation.add_entity(target)
	simulation.drain_events()

	var profile := {
		"id": "fixture:attack:cooldown",
		"damage": 1.0,
		"range": 5.0,
		"requires_facing": false,
		"requires_los": false,
		"cooldown_group": "test_attack",
		"cooldown_seconds": 2.0,
	}

	_expect(
		bool(
			simulation.request_attack(
				player.entity_id,
				target.entity_id,
				profile
			).get("success", false)
		),
		"first cooldown attack succeeds"
	)

	_expect(
		str(
			simulation.request_attack(
				player.entity_id,
				target.entity_id,
				profile
			).get("reason", "")
		) == "cooldown",
		"second immediate attack is blocked by simulation cooldown"
	)

	simulation.advance(1.9)
	_expect(
		simulation.cooldown_remaining(player.entity_id, "test_attack") > 0.0,
		"cooldown remains before simulated deadline"
	)

	simulation.advance(0.2)
	_expect(
		simulation.cooldown_remaining(player.entity_id, "test_attack") == 0.0,
		"manual clock advancement expires cooldown"
	)
	_expect(
		bool(
			simulation.request_attack(
				player.entity_id,
				target.entity_id,
				profile
			).get("success", false)
		),
		"attack succeeds after simulated cooldown without wall-clock waiting"
	)


func _test_fixture_and_imported_npc_share_factory_and_combat_path() -> void:
	var content := ContentService.new()
	content.configure({
		"zone": "res://data/halas.json",
		"items": "res://data/items.json",
		"peq_items": "res://data/halas_items_source.json",
		"player_classes": "res://data/player_classes.json",
		"player_fixture": "res://data/player_fixture.json",
		"merchants": "res://data/halas_merchants_source.json",
		"factions": "res://data/halas_factions_source.json",
		"npcs": "res://data/halas_npcs.json",
	})

	_expect(content.load_all(), "content service loads the Phase 3 content set")
	if not content.last_error.is_empty():
		return

	var zone := content.zone_definition("eqm:zone:halas")
	var training_definition := _training_definition_from_zone(zone)
	var training_entity := EntityFactory.create(training_definition)

	var npc_dataset := content.npc_dataset()
	var dataset_meta: Dictionary = npc_dataset.get("meta", {})
	var dataset_source: Dictionary = npc_dataset.get("source", {})

	_expect(
		str(dataset_meta.get("review_state", "")) == "current_unreviewed_peq",
		"Halas NPC dataset remains explicitly current_unreviewed_peq"
	)
	_expect(
		str(dataset_source.get("zone", "")) == "halas",
		"foundation proof uses the imported Halas NPC dataset"
	)

	var resolved := _resolve_spawn_referenced_halas_npc(npc_dataset)
	_expect(
		not resolved.is_empty(),
		"foundation gate resolves a real NPC through SpawnPoint -> SpawnGroup -> candidate npc_ref -> NpcArchetype"
	)
	if resolved.is_empty():
		return

	var source_spawn: Dictionary = resolved.get("spawn", {})
	var source_group: Dictionary = resolved.get("group", {})
	var source_candidate: Dictionary = resolved.get("candidate", {})
	var source_npc: Dictionary = resolved.get("npc", {})

	var spawn2_id := int(source_spawn.get("spawn2_id", 0))
	var npc_ref := str(source_npc.get("key", ""))

	_expect(spawn2_id > 0, "resolved Halas spawn has a real spawn2 identity")
	_expect(
		str(source_spawn.get("key", "")).begins_with("peq:spawn:"),
		"resolved Halas spawn uses the typed PEQ spawn identity"
	)
	_expect(
		str(source_group.get("key", "")).begins_with("peq:spawn_group:"),
		"resolved Halas spawn group uses the typed PEQ spawn-group identity"
	)
	_expect(
		str(source_spawn.get("spawn_group_ref", ""))
			== str(source_group.get("key", "")),
		"resolved Halas spawn points to the resolved spawn group"
	)
	_expect(
		str(source_candidate.get("npc_ref", "")) == npc_ref,
		"resolved spawn-group candidate points to the resolved NPC archetype"
	)
	_expect(
		npc_ref.begins_with("peq:npc:"),
		"resolved Halas NPC is an imported PEQ NPC definition"
	)

	# Select a source-backed record that actually contains HP, damage, and loot
	# references so the test proves those fields are not promoted.
	_expect(
		int(source_npc.get("hp", 0)) > 0,
		"resolved imported NPC carries source HP provenance"
	)
	_expect(
		int(source_npc.get("maxdmg", 0)) > 0,
		"resolved imported NPC carries source damage provenance"
	)
	_expect(
		source_npc.get("loot_table_ref", null) != null,
		"resolved imported NPC carries source loot-table provenance"
	)

	var disabled_real_npc_definition := HalasEntityAdapter.neutral_definition_from_source_npc(
		source_npc,
		spawn2_id,
		Vector3(2.0, 0.0, 0.0)
	)
	var disabled_rewards: Dictionary = disabled_real_npc_definition.get("rewards", {})

	_expect(
		str(disabled_real_npc_definition.get("definition_id", "")) == npc_ref,
		"normal runtime definition preserves the imported NPC definition identity"
	)
	_expect(
		not bool(disabled_real_npc_definition.get("combat_enabled", true)),
		"imported NPC combat remains disabled without an explicit architecture-test override"
	)
	_expect(
		is_equal_approx(
			float(disabled_real_npc_definition.get("max_health", 0.0)),
			1.0
		),
		"source PEQ HP is not promoted into normal runtime health"
	)
	_expect(
		not disabled_real_npc_definition.has("damage")
			and not disabled_real_npc_definition.has("damage_min")
			and not disabled_real_npc_definition.has("damage_max"),
		"source PEQ damage is not promoted into the normal runtime definition"
	)
	_expect(
		disabled_rewards.is_empty(),
		"source PEQ loot is not promoted into the normal runtime definition"
	)

	var real_npc_definition := HalasEntityAdapter.neutral_definition_from_source_npc(
		source_npc,
		spawn2_id,
		Vector3(2.0, 0.0, 0.0),
		{
			"max_health": 10.0,
			"combat_enabled": true,
			"hostile": true,
			"respawn_seconds": -1.0,
			"rewards": {},
		}
	)
	var safe_rewards: Dictionary = real_npc_definition.get("rewards", {})
	var real_npc_entity := EntityFactory.create(real_npc_definition)

	_expect(
		training_entity is GameplayEntity and real_npc_entity is GameplayEntity,
		"fixture and imported NPC use the same GameplayEntity factory path"
	)
	_expect(
		real_npc_entity.definition_id == npc_ref,
		"safe test entity still references the genuine imported NPC definition"
	)
	_expect(
		bool(real_npc_entity.metadata.get("architecture_test_override", false)),
		"real NPC combat proof uses an explicit project-owned safe test override"
	)
	_expect(
		not bool(real_npc_entity.metadata.get("source_combat_enabled", true)),
		"unreviewed PEQ combat remains disabled as source policy"
	)
	_expect(
		is_equal_approx(
			float(real_npc_definition.get("max_health", 0.0)),
			10.0
		),
		"safe test health is the project-owned override"
	)
	_expect(
		not is_equal_approx(
			float(real_npc_definition.get("max_health", 0.0)),
			float(source_npc.get("hp", 0))
		),
		"safe test health does not copy source PEQ HP"
	)
	_expect(
		not real_npc_definition.has("damage")
			and not real_npc_definition.has("damage_min")
			and not real_npc_definition.has("damage_max"),
		"safe test definition does not promote source PEQ damage"
	)
	_expect(
		safe_rewards.is_empty(),
		"safe test definition does not promote source PEQ loot"
	)

	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(303)
	)
	var fixture := content.player_fixture_definition()

	simulation.configure_player_state(
		"player:local",
		content.item_definitions(),
		int(fixture.get("inventory_capacity", 8)),
		zone.get("progression", {}),
		content.faction_catalog(),
		fixture.get("identity", {}),
		fixture.get("inventory_item_aliases", {})
	)

	var player := _player_entity()
	simulation.add_entity(player)
	simulation.add_entity(training_entity)
	simulation.add_entity(real_npc_entity)
	simulation.drain_events()

	var profile := {
		"id": "fixture:attack:foundation_gate",
		"damage": 100.0,
		"range": 20.0,
		"requires_facing": false,
		"requires_los": false,
	}

	player.position = Vector3.ZERO
	training_entity.position = Vector3(1.0, 0.0, 0.0)
	real_npc_entity.position = Vector3(2.0, 0.0, 0.0)

	_expect(
		bool(
			simulation.request_attack(
				player.entity_id,
				training_entity.entity_id,
				profile
			).get("success", false)
		),
		"Training Spark passes through generic attack machinery"
	)

	var training_events := simulation.drain_events()
	_expect(
		_count_events_for_target(
			training_events,
			GameplayEvent.Type.DAMAGE,
			training_entity.entity_id
		) == 1,
		"Training Spark uses generic damage event machinery"
	)
	_expect(
		_count_events_for_target(
			training_events,
			GameplayEvent.Type.DEATH,
			training_entity.entity_id
		) == 1,
		"Training Spark uses generic death event machinery"
	)

	simulation.advance(
		float(zone.get("spawns", [])[0].get("respawn_seconds", 12.0))
	)

	var respawn_events := simulation.drain_events()
	_expect(
		_count_spawn_events(respawn_events, training_entity.entity_id) == 1,
		"Training Spark respawns through the generic lifecycle machinery"
	)
	_expect(
		training_entity.is_active() and training_entity.life_number == 2,
		"generic respawn restores Training Spark as a new life"
	)

	_expect(
		bool(
			simulation.request_attack(
				player.entity_id,
				real_npc_entity.entity_id,
				profile
			).get("success", false)
		),
		"spawn-referenced real Halas NPC passes through the same generic attack machinery under safe test configuration"
	)

	var real_events := simulation.drain_events()
	_expect(
		_count_events_for_target(
			real_events,
			GameplayEvent.Type.DAMAGE,
			real_npc_entity.entity_id
		) == 1,
		"real Halas NPC uses the same generic damage event machinery"
	)
	_expect(
		_count_events_for_target(
			real_events,
			GameplayEvent.Type.DEATH,
			real_npc_entity.entity_id
		) == 1,
		"real Halas NPC uses the same generic death event machinery"
	)


func _test_full_sequence_is_deterministic() -> void:
	var first := _run_seeded_sequence(404)
	var second := _run_seeded_sequence(404)
	_expect(
		JSON.stringify(first, "", true) == JSON.stringify(second, "", true),
		"same initial state, time advances, and RNG seed reproduce the same combat result"
	)


func _run_seeded_sequence(seed_value: int) -> Dictionary:
	var simulation := _new_test_simulation(seed_value)
	var player := _player_entity()
	var target := EntityFactory.create({
		"entity_id": "test:target:determinism",
		"definition_id": "fixture:npc:determinism",
		"spawn_position": Vector3(1.0, 0.0, 0.0),
		"max_health": 13.0,
		"combat_enabled": true,
		"hostile": true,
		"respawn_seconds": -1.0,
		"rewards": {
			"xp": 25,
			"items": [],
		},
	})

	simulation.add_entity(player)
	simulation.add_entity(target)
	simulation.drain_events()

	var profile := {
		"id": "fixture:attack:determinism",
		"damage_min": 4.0,
		"damage_max": 6.0,
		"range": 5.0,
		"requires_facing": false,
		"requires_los": false,
	}

	var event_trace: Array = []

	for _index in 4:
		simulation.request_attack(
			player.entity_id,
			target.entity_id,
			profile
		)

		for event in simulation.drain_events():
			event_trace.append(event.to_dict())

		simulation.advance(0.5)

	return {
		"events": event_trace,
		"snapshot": simulation.snapshot(),
	}


func _new_test_simulation(seed_value: int) -> Simulation:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(seed_value)
	)

	simulation.configure_player_state(
		"player:local",
		{
			"fixture:item:test": {
				"key": "fixture:item:test",
				"name": "Test Item",
				"stackable": true,
				"stack_size": 20,
				"max_charges": 0,
			},
		},
		8,
		{"max_level": 50},
		_fixture_faction_catalog(),
		{
			"class_id": 1,
			"race_id": 2,
			"deity_id": 396,
		}
	)

	return simulation


func _fixture_faction_catalog() -> Dictionary:
	return {
		"thresholds": {},
		"factions_by_key": {
			"fixture:faction:test": {
				"key": "fixture:faction:test",
				"base": 0,
				"personal_min": -2000,
				"personal_max": 2000,
				"modifiers": [],
			},
		},
		"npc_faction_bundles_by_key": {},
	}


func _test_zone_definition() -> Dictionary:
	return {
		"key": "eqm:zone:test",
		"id": "test",
		"player_spawn_revision": 2,
	}


func _persistence_target_entity() -> GameplayEntity:
	return EntityFactory.create({
		"entity_id": "test:target:persistence",
		"definition_id": "fixture:npc:persistence_target",
		"display_name": "Persistence Target",
		"spawn_position": Vector3(1.0, 0.0, 0.0),
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": true,
		"respawn_seconds": -1.0,
	})


func _player_entity() -> GameplayEntity:
	return EntityFactory.create({
		"entity_id": "player:local",
		"definition_id": "fixture:player:local",
		"kind": "player",
		"display_name": "Player",
		"spawn_position": Vector3.ZERO,
		"facing": Vector3.RIGHT,
		"combat_size": 7.0,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": false,
		"respawn_seconds": 0.0,
		"death_delay_seconds": 2.5,
	})


func _training_definition_from_zone(zone: Dictionary) -> Dictionary:
	var spawn: Dictionary = zone.get("spawns", [])[0]
	var archetype: Dictionary = zone.get(
		"npc_archetypes",
		{}
	).get(
		str(spawn.get("archetype", "")),
		{}
	)

	return {
		"entity_id": "fixture:spawn:training_spark",
		"definition_id": str(
			archetype.get(
				"key",
				"fixture:npc:training_spark"
			)
		),
		"kind": "npc",
		"display_name": str(
			archetype.get(
				"name",
				"Training Spark"
			)
		),
		"spawn_position": _vector3(
			spawn.get(
				"position",
				[0.0, 0.0, 0.0]
			)
		),
		"combat_size": float(archetype.get("combat_size", 1.0)),
		"max_health": float(archetype.get("max_health", 1.0)),
		"combat_enabled": true,
		"hostile": true,
		"death_delay_seconds": float(
			archetype.get(
				"death_delay_seconds",
				0.0
			)
		),
		"respawn_seconds": float(
			spawn.get(
				"respawn_seconds",
				-1.0
			)
		),
		"rewards": archetype.get(
			"rewards",
			{}
		).duplicate(true),
		"metadata": {
			"behavior": archetype.get(
				"behavior",
				{}
			).duplicate(true),
			"combat_profile": archetype.get(
				"combat",
				{}
			).duplicate(true),
			"evidence": str(
				archetype.get(
					"evidence",
					"temporary_fixture_default"
				)
			),
		},
	}


func _resolve_spawn_referenced_halas_npc(dataset: Dictionary) -> Dictionary:
	var spawn_groups: Dictionary = dataset.get("spawn_groups", {})
	var npc_types: Array = dataset.get("npc_types", [])
	var npc_by_key: Dictionary = {}

	for npc_variant in npc_types:
		if not npc_variant is Dictionary:
			continue

		var npc: Dictionary = npc_variant
		var npc_key := str(npc.get("key", ""))
		if not npc_key.is_empty():
			npc_by_key[npc_key] = npc

	for spawn_variant in dataset.get("spawns", []):
		if not spawn_variant is Dictionary:
			continue

		var spawn: Dictionary = spawn_variant
		var group_ref := str(spawn.get("spawn_group_ref", ""))
		if group_ref.is_empty():
			continue

		var group := _spawn_group_by_ref(spawn_groups, group_ref)
		if group.is_empty():
			continue

		var candidates: Variant = group.get("candidates", [])
		if not candidates is Array:
			continue

		for candidate_variant in candidates:
			if not candidate_variant is Dictionary:
				continue

			var candidate: Dictionary = candidate_variant
			var npc_ref := str(candidate.get("npc_ref", ""))
			if npc_ref.is_empty() or not npc_by_key.has(npc_ref):
				continue

			var npc: Dictionary = npc_by_key[npc_ref]
			var loot_ref_variant: Variant = npc.get(
				"loot_table_ref",
				null
			)

			if int(npc.get("hp", 0)) <= 0:
				continue
			if int(npc.get("maxdmg", 0)) <= 0:
				continue
			if loot_ref_variant == null:
				continue
			if str(loot_ref_variant).is_empty():
				continue

			return {
				"spawn": spawn,
				"group": group,
				"candidate": candidate,
				"npc": npc,
			}

	return {}


func _spawn_group_by_ref(
	spawn_groups: Dictionary,
	group_ref: String
) -> Dictionary:
	for group_id in spawn_groups:
		var group_variant: Variant = spawn_groups[group_id]
		if not group_variant is Dictionary:
			continue

		var group: Dictionary = group_variant
		if str(group.get("key", "")) == group_ref:
			return group

	return {}


func _event_index(events: Array, event_type: int) -> int:
	for index in range(events.size()):
		var event := events[index] as GameplayEvent
		if event != null and event.type == event_type:
			return index

	return 999999


func _count_events(events: Array, event_type: int) -> int:
	var count := 0

	for event_variant in events:
		var event := event_variant as GameplayEvent
		if event != null and event.type == event_type:
			count += 1

	return count


func _count_events_for_target(
	events: Array,
	event_type: int,
	target_id: String
) -> int:
	var count := 0

	for event_variant in events:
		var event := event_variant as GameplayEvent
		if (
			event != null
			and event.type == event_type
			and event.target_entity_id == target_id
		):
			count += 1

	return count


func _count_spawn_events(
	events: Array,
	entity_id: String
) -> int:
	var count := 0

	for event_variant in events:
		var event := event_variant as GameplayEvent
		if (
			event != null
			and event.type == GameplayEvent.Type.SPAWN
			and event.source_entity_id == entity_id
		):
			count += 1

	return count


func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(
			float(value[0]),
			float(value[1]),
			float(value[2])
		)

	return Vector3.ZERO


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)