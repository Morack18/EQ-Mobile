extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_invalid_data()
	_test_legacy_migration()
	_test_v2_migration()
	_test_exact_rng_json()
	_test_explicit_zero_rng_state()
	_test_seed_only_rng_restore()

	if _failures.is_empty():
		print(
			"PASS: Phase 4 save migration and deterministic persistence contract."
		)
		quit(0)
		return

	for failure in _failures:
		push_error(failure)

	print(
		"FAIL: Phase 4 save migration tests (%d failures)."
		% _failures.size()
	)
	quit(1)


func _test_invalid_data() -> void:
	var service := PersistenceService.new(
		"user://phase4_invalid_unused.json",
		SimulationClock.new()
	)

	var malformed := service.deserialize_envelope(
		"{ invalid json",
		"eqm:zone:test",
		"test"
	)

	_expect(
		not bool(malformed.get("ok", true)),
		"malformed JSON is rejected"
	)

	var unsupported := service.deserialize_envelope(
		JSON.stringify({
			"schema_version": 999,
			"zone_key": "eqm:zone:test",
			"simulation": {},
		}),
		"eqm:zone:test",
		"test"
	)

	_expect(
		not bool(unsupported.get("ok", true)),
		"unsupported schema version is rejected"
	)


func _test_legacy_migration() -> void:
	var service := PersistenceService.new(
		"user://phase4_legacy_unused.json",
		SimulationClock.new()
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
			"fixture:training_spark_fragment": 2,
		},
		"wallet": {
			"platinum": 1,
			"gold": 2,
			"silver": 3,
			"copper": 4,
		},
		"player_xp_total": 1234,
		"faction_values": {
			"223": 125,
			"peq:faction:1159": -25,
		},
		"class_id": 1,
		"race_id": 2,
		"deity_id": 396,
	}

	var result := service.deserialize_envelope(
		JSON.stringify(legacy),
		"eqm:zone:test",
		"test",
		{
			"player_entity_id": "player:local",
			"legacy_npc_entity_id":
				"fixture:spawn:training_spark",
			"rng_seed": 707,
		}
	)

	_expect(
		bool(result.get("ok", false)),
		"legacy save migrates"
	)

	_expect(
		bool(result.get("migrated", false)),
		"legacy save reports migrated=true"
	)

	if not bool(result.get("ok", false)):
		return

	var envelope: Dictionary = result.get("state", {})
	var payload: Dictionary = envelope.get("simulation", {})
	var rng_payload: Dictionary = payload.get("rng", {})

	_expect(
		int(envelope.get("schema_version", 0))
			== PersistenceService.SAVE_SCHEMA_VERSION,
		"legacy save upgrades to current schema"
	)

	_expect(
		str(envelope.get("offline_elapsed_policy", ""))
			== PersistenceService.OFFLINE_ELAPSED_POLICY,
		"legacy save adopts frozen offline policy"
	)

	_expect(
		int(rng_payload.get("seed", 0)) == 707,
		"legacy RNG seed is retained"
	)

	_expect(
		not rng_payload.has("state"),
		"legacy migration does not invent RNG state"
	)

	var simulation := _new_test_simulation(1)
	simulation.restore_snapshot(payload)

	var player := simulation.entity("player:local")
	var npc := simulation.entity(
		"fixture:spawn:training_spark"
	)

	_expect(
		player != null
			and is_equal_approx(player.health, 88.0),
		"legacy player health restores"
	)

	if player != null:
		_expect(
			player.position.is_equal_approx(
				Vector3(1.0, 2.0, 3.0)
			),
			"legacy player position restores"
		)

	_expect(
		npc != null
			and npc.lifecycle
				== GameplayEntity.Lifecycle.DEAD,
		"legacy NPC lifecycle restores"
	)

	_expect(
		simulation.inventory.quantity(
			"fixture:item:training_spark_fragment"
		) == 2,
		"legacy inventory alias restores"
	)

	var factions := simulation.faction.values_snapshot()

	_expect(
		int(factions.get("peq:faction:223", 0))
			== 125,
		"numeric legacy faction ID normalizes"
	)

	_expect(
		int(factions.get("peq:faction:1159", 0))
			== -25,
		"typed faction reference restores"
	)

	_expect(
		simulation.wallet_total_copper() == 1234,
		"legacy wallet restores"
	)

	_expect(
		simulation.progression.xp_total == 1234,
		"legacy XP restores"
	)

	var expected_rng := SimulationRng.new(707)

	_expect(
		simulation.rng.randi_range(1, 1000000)
			== expected_rng.randi_range(1, 1000000),
		"seed-only legacy RNG starts deterministically from seed"
	)


func _test_v2_migration() -> void:
	var service := PersistenceService.new(
		"user://phase4_v2_unused.json",
		SimulationClock.new()
	)

	var result := service.deserialize_envelope(
		JSON.stringify({
			"schema_version": 2,
			"zone_key": "eqm:zone:test",
			"zone_legacy_id": "test",
			"player_spawn_revision": 1,
			"simulation": {
				"clock_elapsed_seconds": 12.0,
				"rng": {
					"seed": 17,
					"state": 123,
				},
				"entities": {},
				"cooldowns_remaining": {
					"player:local|primary": 4.5,
				},
			},
		}),
		"eqm:zone:test",
		"test"
	)

	_expect(
		bool(result.get("ok", false)),
		"v2 save migrates"
	)

	if not bool(result.get("ok", false)):
		return

	var state: Dictionary = result.get("state", {})
	var payload: Dictionary = state.get("simulation", {})
	var timers: Dictionary = payload.get(
		"timers_remaining",
		{}
	)

	_expect(
		is_equal_approx(
			float(
				timers.get(
					"cooldown|player:local|primary",
					0.0
				)
			),
			4.5
		),
		"v2 cooldown becomes a generic cooldown timer"
	)

	var rng_payload: Dictionary = payload.get("rng", {})

	_expect(
		int(rng_payload.get("state", 0)) == 123,
		"v2 exact RNG state is preserved"
	)


func _test_exact_rng_json() -> void:
	var service := PersistenceService.new(
		"user://phase4_rng_unused.json",
		SimulationClock.new()
	)

	var exact_seed: int = 9007199254740997
	var exact_state: int = 9007199254741999

	var result := service.deserialize_envelope(
		service.serialize_envelope(
			_schema_three(
				exact_seed,
				exact_state
			)
		),
		"eqm:zone:test",
		"test"
	)

	_expect(
		bool(result.get("ok", false)),
		"schema-v3 exact RNG round trip succeeds"
	)

	if not bool(result.get("ok", false)):
		return

	var state: Dictionary = result.get("state", {})
	var payload: Dictionary = state.get("simulation", {})
	var rng_payload: Dictionary = payload.get("rng", {})

	_expect(
		int(rng_payload.get("seed", 0))
			== exact_seed,
		"64-bit RNG seed survives JSON"
	)

	_expect(
		int(rng_payload.get("state", 0))
			== exact_state,
		"64-bit RNG state survives JSON"
	)


func _test_explicit_zero_rng_state() -> void:
	var service := PersistenceService.new(
		"user://phase4_zero_rng_unused.json",
		SimulationClock.new()
	)

	var result := service.deserialize_envelope(
		service.serialize_envelope(
			_schema_three(12345, 0)
		),
		"eqm:zone:test",
		"test"
	)

	_expect(
		bool(result.get("ok", false)),
		"explicit RNG state zero round trips"
	)

	if not bool(result.get("ok", false)):
		return

	var state: Dictionary = result.get("state", {})
	var payload: Dictionary = state.get("simulation", {})
	var rng_payload: Dictionary = payload.get("rng", {})

	_expect(
		rng_payload.has("state"),
		"explicit zero RNG state remains present"
	)

	_expect(
		int(rng_payload.get("state", -1)) == 0,
		"explicit zero RNG state remains exactly zero"
	)


func _test_seed_only_rng_restore() -> void:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(1)
	)

	simulation.restore_snapshot({
		"clock_elapsed_seconds": 0.0,
		"rng": {
			"seed": 8080,
		},
	})

	var expected := SimulationRng.new(8080)

	_expect(
		simulation.rng.randi_range(1, 1000000)
			== expected.randi_range(1, 1000000),
		"seed-only RNG snapshot initializes from the supplied seed"
	)


func _new_test_simulation(seed_value: int) -> Simulation:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(seed_value)
	)

	simulation.configure_player_state(
		"player:local",
		{
			"fixture:item:training_spark_fragment": {
				"key":
					"fixture:item:training_spark_fragment",
				"name": "Training Spark Fragment",
				"stackable": true,
				"stack_size": 20,
				"max_charges": 0,
			},
		},
		8,
		{"max_level": 50},
		{
			"thresholds": {},
			"factions_by_key": {
				"peq:faction:223": {
					"key": "peq:faction:223",
					"base": 0,
					"personal_min": -2000,
					"personal_max": 2000,
					"modifiers": [],
				},
				"peq:faction:1159": {
					"key": "peq:faction:1159",
					"base": 0,
					"personal_min": -2000,
					"personal_max": 2000,
					"modifiers": [],
				},
			},
			"npc_faction_bundles_by_key": {},
		},
		{
			"class_id": 1,
			"race_id": 2,
			"deity_id": 396,
		},
		{
			"fixture:training_spark_fragment":
				"fixture:item:training_spark_fragment",
		}
	)

	simulation.add_entity(
		EntityFactory.create({
			"entity_id": "player:local",
			"definition_id": "fixture:player:test",
			"kind": "player",
			"display_name": "Player",
			"spawn_position": Vector3.ZERO,
			"max_health": 100.0,
			"combat_enabled": true,
			"hostile": false,
		}),
		true,
		false
	)

	simulation.add_entity(
		EntityFactory.create({
			"entity_id":
				"fixture:spawn:training_spark",
			"definition_id":
				"fixture:npc:training_spark",
			"kind": "npc",
			"display_name": "Training Spark",
			"spawn_position": Vector3.ZERO,
			"max_health": 35.0,
			"combat_enabled": true,
			"hostile": true,
			"respawn_seconds": 12.0,
		}),
		true,
		false
	)

	simulation.drain_events()
	return simulation


func _schema_three(
	seed_value: int,
	state_value: int
) -> Dictionary:
	return {
		"schema_version":
			PersistenceService.SAVE_SCHEMA_VERSION,
		"zone_key": "eqm:zone:test",
		"zone_legacy_id": "test",
		"player_spawn_revision": 1,
		"saved_unix_ms": 0,
		"offline_elapsed_policy":
			PersistenceService.OFFLINE_ELAPSED_POLICY,
		"simulation": {
			"clock_elapsed_seconds": 0.0,
			"rng": {
				"seed": seed_value,
				"state": state_value,
			},
			"entities": {},
			"timers_remaining": {},
			"timed_effects": {},
			"active_spell_casts": {},
		},
	}


func _expect(
	condition: bool,
	message: String
) -> void:
	if not condition:
		_failures.append(message)
