extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_entity_lifecycle_transitions()
	_test_seeded_rng_reproducibility()
	_test_attack_damage_death_and_single_rewards()
	_test_progression_threshold_and_level_change()
	_test_inventory_mutation_without_ui()
	_test_persistence_round_trip_without_disk()
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
	_expect(_event_index(first_events, GameplayEvent.Type.ATTACK_REQUESTED) < _event_index(first_events, GameplayEvent.Type.ATTACK_PERFORMED), "attack requested precedes attack performed")
	_expect(_event_index(first_events, GameplayEvent.Type.ATTACK_PERFORMED) < _event_index(first_events, GameplayEvent.Type.DAMAGE), "attack performed precedes damage")
	_expect(_event_index(first_events, GameplayEvent.Type.DAMAGE) < _event_index(first_events, GameplayEvent.Type.DEATH), "damage precedes death")
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
	_expect(progression.xp_threshold(2) == 1000, "level 2 threshold is the current classic cubic fixture threshold")
	progression.award_xp(999)
	_expect(progression.level == 1, "999 XP remains level 1")
	var result := progression.award_xp(1)
	_expect(progression.level == 2, "1000 total XP reaches level 2")
	_expect(int(result.get("previous_level", 0)) == 1 and int(result.get("level", 0)) == 2, "level-change result reports both levels")


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


func _test_persistence_round_trip_without_disk() -> void:
	var clock := SimulationClock.new()
	var persistence := PersistenceService.new("user://phase3_test_unused.json", clock)
	var envelope := {
		"schema_version": PersistenceService.SAVE_SCHEMA_VERSION,
		"zone_key": "eqm:zone:test",
		"zone_legacy_id": "test",
		"player_spawn_revision": 2,
		"simulation": {
			"clock_elapsed_seconds": 12.5,
			"inventory": [{"item_key": "fixture:item:test", "quantity": 3, "charges_remaining": null}],
			"entities": {},
		},
	}
	var serialized := persistence.serialize_envelope(envelope)
	var decoded := persistence.deserialize_envelope(serialized, "eqm:zone:test", "test")
	_expect(bool(decoded.get("ok", false)), "persistence serialize -> deserialize round trip is valid")
	var restored: Dictionary = decoded.get("state", {})
	_expect(int(restored.get("schema_version", 0)) == PersistenceService.SAVE_SCHEMA_VERSION, "round trip preserves schema version")
	_expect(str(restored.get("zone_key", "")) == "eqm:zone:test", "round trip preserves zone key")
	_expect(float(restored.get("simulation", {}).get("clock_elapsed_seconds", 0.0)) == 12.5, "round trip preserves simulation state")


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
	_expect(bool(simulation.request_attack(player.entity_id, target.entity_id, profile).get("success", false)), "first cooldown attack succeeds")
	_expect(str(simulation.request_attack(player.entity_id, target.entity_id, profile).get("reason", "")) == "cooldown", "second immediate attack is blocked by simulation cooldown")
	simulation.advance(1.9)
	_expect(simulation.cooldown_remaining(player.entity_id, "test_attack") > 0.0, "cooldown remains before simulated deadline")
	simulation.advance(0.2)
	_expect(simulation.cooldown_remaining(player.entity_id, "test_attack") == 0.0, "manual clock advancement expires cooldown")
	_expect(bool(simulation.request_attack(player.entity_id, target.entity_id, profile).get("success", false)), "attack succeeds after simulated cooldown without wall-clock waiting")


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
		"npcs": "res://data/halas_npcs.json"
	})
	_expect(content.load_all(), "content service loads the Phase 3 content set")
	if not content.last_error.is_empty():
		return
	var zone := content.zone_definition("eqm:zone:halas")
	var training_definition := _training_definition_from_zone(zone)
	var training_entity := EntityFactory.create(training_definition)
	var npc_types: Array = content.npc_dataset().get("npc_types", [])
	_expect(not npc_types.is_empty(), "real Halas NPC dataset contains NPC definitions")
	if npc_types.is_empty():
		return
	var disabled_real_npc_definition := HalasEntityAdapter.neutral_definition_from_source_npc(
		npc_types[0],
		9900001,
		Vector3(2.0, 0.0, 0.0)
	)
	_expect(not bool(disabled_real_npc_definition.get("combat_enabled", true)), "Imported NPC combat remains disabled without a reviewed or explicit architecture-test override")
	var real_npc_definition := HalasEntityAdapter.neutral_definition_from_source_npc(
		npc_types[0],
		9900001,
		Vector3(2.0, 0.0, 0.0),
		{
			"max_health": 10.0,
			"combat_enabled": true,
			"hostile": true,
			"respawn_seconds": -1.0,
			"rewards": {},
		}
	)
	var real_npc_entity := EntityFactory.create(real_npc_definition)
	_expect(training_entity is GameplayEntity and real_npc_entity is GameplayEntity, "fixture and imported NPC use the same GameplayEntity factory path")
	_expect(bool(real_npc_entity.metadata.get("architecture_test_override", false)), "real NPC combat proof uses an explicit safe test override")
	_expect(not bool(real_npc_entity.metadata.get("source_combat_enabled", true)), "unreviewed PEQ combat remains disabled as source policy")

	var simulation := Simulation.new(SimulationClock.new(), SimulationRng.new(303))
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
	_expect(bool(simulation.request_attack(player.entity_id, training_entity.entity_id, profile).get("success", false)), "Training Spark passes through generic attack machinery")
	var training_events := simulation.drain_events()
	_expect(_count_events_for_target(training_events, GameplayEvent.Type.DEATH, training_entity.entity_id) == 1, "Training Spark uses generic death event machinery")
	simulation.advance(float(zone.get("spawns", [])[0].get("respawn_seconds", 12.0)))
	var respawn_events := simulation.drain_events()
	_expect(_count_spawn_events(respawn_events, training_entity.entity_id) == 1, "Training Spark respawns through the generic lifecycle machinery")
	_expect(training_entity.is_active() and training_entity.life_number == 2, "generic respawn restores Training Spark as a new life")
	_expect(bool(simulation.request_attack(player.entity_id, real_npc_entity.entity_id, profile).get("success", false)), "real Halas NPC passes through the same generic attack machinery under safe test config")
	var real_events := simulation.drain_events()
	_expect(_count_events_for_target(real_events, GameplayEvent.Type.DEATH, real_npc_entity.entity_id) == 1, "real Halas NPC uses the same generic death event machinery")


func _test_full_sequence_is_deterministic() -> void:
	var first := _run_seeded_sequence(404)
	var second := _run_seeded_sequence(404)
	_expect(JSON.stringify(first, "", true) == JSON.stringify(second, "", true), "same initial state, time advances, and RNG seed reproduce the same combat result")


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
		"rewards": {"xp": 25, "items": []},
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
		simulation.request_attack(player.entity_id, target.entity_id, profile)
		for event in simulation.drain_events():
			event_trace.append(event.to_dict())
		simulation.advance(0.5)
	return {
		"events": event_trace,
		"snapshot": simulation.snapshot(),
	}


func _new_test_simulation(seed_value: int) -> Simulation:
	var simulation := Simulation.new(SimulationClock.new(), SimulationRng.new(seed_value))
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
		{"thresholds": {}, "factions_by_key": {}, "npc_faction_bundles_by_key": {}},
		{"class_id": 1, "race_id": 2, "deity_id": 396}
	)
	return simulation


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
	var archetype: Dictionary = zone.get("npc_archetypes", {}).get(str(spawn.get("archetype", "")), {})
	return {
		"entity_id": "fixture:spawn:training_spark",
		"definition_id": str(archetype.get("key", "fixture:npc:training_spark")),
		"kind": "npc",
		"display_name": str(archetype.get("name", "Training Spark")),
		"spawn_position": _vector3(spawn.get("position", [0.0, 0.0, 0.0])),
		"combat_size": float(archetype.get("combat_size", 1.0)),
		"max_health": float(archetype.get("max_health", 1.0)),
		"combat_enabled": true,
		"hostile": true,
		"death_delay_seconds": float(archetype.get("death_delay_seconds", 0.0)),
		"respawn_seconds": float(spawn.get("respawn_seconds", -1.0)),
		"rewards": archetype.get("rewards", {}).duplicate(true),
		"metadata": {
			"behavior": archetype.get("behavior", {}).duplicate(true),
			"combat_profile": archetype.get("combat", {}).duplicate(true),
			"evidence": str(archetype.get("evidence", "temporary_fixture_default")),
		},
	}


func _event_index(events: Array, event_type: int) -> int:
	for index in events.size():
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


func _count_events_for_target(events: Array, event_type: int, target_id: String) -> int:
	var count := 0
	for event_variant in events:
		var event := event_variant as GameplayEvent
		if event != null and event.type == event_type and event.target_entity_id == target_id:
			count += 1
	return count


func _count_spawn_events(events: Array, entity_id: String) -> int:
	var count := 0
	for event_variant in events:
		var event := event_variant as GameplayEvent
		if event != null and event.type == GameplayEvent.Type.SPAWN and event.source_entity_id == entity_id:
			count += 1
	return count


func _vector3(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)