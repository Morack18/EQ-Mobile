extends SceneTree


func _init() -> void:
	_test_clock_pause()
	_test_timer_bank_snapshot()
	_test_rng_determinism()
	_test_spawn_attack_respawn_and_pause()
	_test_ai_effect_cast_recast_and_merchant_timers()
	_test_simulation_snapshot_restores_timers_and_rng()
	_test_save_schema_migration()

	print(
		"PASS: canonical time, timers, pause, persistence, and deterministic RNG contracts hold."
	)
	quit()


func _test_clock_pause() -> void:
	var clock := SimulationClock.new()

	clock.advance(1.25)
	assert(
		is_equal_approx(
			clock.now_seconds(),
			1.25
		)
	)

	clock.set_paused(true)
	clock.advance(10.0)

	assert(
		is_equal_approx(
			clock.now_seconds(),
			1.25
		)
	)

	clock.set_paused(false)
	clock.advance(0.75)

	assert(
		is_equal_approx(
			clock.now_seconds(),
			2.0
		)
	)


func _test_timer_bank_snapshot() -> void:
	var clock := SimulationClock.new()
	var timers := SimulationTimerBank.new(clock)

	timers.start(
		"test|owner|one",
		10.0
	)
	clock.advance(3.0)

	assert(
		is_equal_approx(
			timers.remaining("test|owner|one"),
			7.0
		)
	)

	var snapshot := timers.snapshot_remaining()

	var restored_clock := SimulationClock.new()
	restored_clock.set_elapsed_seconds(100.0)

	var restored := SimulationTimerBank.new(
		restored_clock
	)
	restored.restore_remaining(snapshot)

	assert(
		is_equal_approx(
			restored.remaining("test|owner|one"),
			7.0
		)
	)


func _test_rng_determinism() -> void:
	var first := SimulationRng.new(123456)
	var second := SimulationRng.new(123456)

	for _index in 16:
		assert(
			first.randi_range(0, 1000000)
			== second.randi_range(0, 1000000)
		)

	var checkpoint_rng := SimulationRng.new(999)

	checkpoint_rng.randi_range(0, 100)
	checkpoint_rng.randi_range(0, 100)

	var checkpoint := checkpoint_rng.snapshot()
	var expected_next := checkpoint_rng.randi_range(
		-100000,
		100000
	)

	var restored_rng := SimulationRng.new(1)
	restored_rng.restore(
		int(checkpoint["seed"]),
		int(checkpoint["state"])
	)

	assert(
		restored_rng.randi_range(
			-100000,
			100000
		)
		== expected_next
	)


func _test_spawn_attack_respawn_and_pause() -> void:
	var clock := SimulationClock.new()
	var simulation := Simulation.new(
		clock,
		SimulationRng.new(42)
	)

	simulation.player_entity_id = "player"

	var player := EntityFactory.create({
		"entity_id": "player",
		"definition_id": "fixture:player:test",
		"kind": "player",
		"display_name": "Player",
		"spawn_position": Vector3.ZERO,
		"combat_size": 1.0,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": false,
	})

	var target := EntityFactory.create({
		"entity_id": "target",
		"definition_id": "fixture:npc:test",
		"kind": "npc",
		"display_name": "Target",
		"spawn_position": Vector3(
			0.0,
			0.0,
			-1.0
		),
		"combat_size": 1.0,
		"max_health": 10.0,
		"combat_enabled": true,
		"hostile": true,
		"death_delay_seconds": 0.0,
		"respawn_seconds": 2.0,
	})

	var delayed := EntityFactory.create({
		"entity_id": "delayed",
		"definition_id": "fixture:npc:delayed",
		"kind": "npc",
		"display_name": "Delayed",
		"spawn_position": Vector3(
			2.0,
			0.0,
			0.0
		),
		"combat_size": 1.0,
		"max_health": 1.0,
		"combat_enabled": false,
		"hostile": false,
	})

	simulation.add_entity(
		player,
		true,
		false
	)
	simulation.add_entity(
		target,
		true,
		false
	)
	simulation.add_entity(
		delayed,
		false,
		false
	)

	assert(
		delayed.lifecycle
		== GameplayEntity.Lifecycle.CREATED
	)

	assert(
		simulation.schedule_spawn(
			"delayed",
			1.0
		)
	)

	simulation.advance(0.5)

	assert(
		delayed.lifecycle
		== GameplayEntity.Lifecycle.CREATED
	)

	simulation.advance(0.5)
	assert(delayed.is_active())

	var attack_profile := {
		"id": "test_attack",
		"cooldown_group": "primary",
		"cooldown_seconds": 1.0,
		"damage": 10.0,
		"range": 5.0,
		"requires_facing": false,
		"hit_chance": 1.0,
	}

	var attack := simulation.request_attack(
		"player",
		"target",
		attack_profile
	)

	assert(
		bool(attack.get("success", false))
	)

	assert(
		target.lifecycle
		== GameplayEntity.Lifecycle.DEAD
	)

	assert(
		simulation.cooldown_remaining(
			"player",
			"primary"
		) > 0.99
	)

	clock.set_paused(true)
	simulation.advance(10.0)

	assert(
		target.lifecycle
		== GameplayEntity.Lifecycle.DEAD
	)

	assert(
		simulation.cooldown_remaining(
			"player",
			"primary"
		) > 0.99
	)

	clock.set_paused(false)
	simulation.advance(1.01)

	assert(
		is_equal_approx(
			simulation.cooldown_remaining(
				"player",
				"primary"
			),
			0.0
		)
	)

	assert(
		target.lifecycle
		== GameplayEntity.Lifecycle.DEAD
	)

	simulation.advance(1.0)
	assert(target.is_active())


func _test_ai_effect_cast_recast_and_merchant_timers() -> void:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(7)
	)

	simulation.player_entity_id = "player"

	var player := EntityFactory.create({
		"entity_id": "player",
		"definition_id": "fixture:player:timers",
		"kind": "player",
		"display_name": "Player",
		"spawn_position": Vector3.ZERO,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": false,
	})

	simulation.add_entity(
		player,
		true,
		false
	)

	assert(
		simulation.claim_ai_think(
			"actor",
			0.25
		)
	)

	assert(
		not simulation.claim_ai_think(
			"actor",
			0.25
		)
	)

	simulation.advance(0.25)

	assert(
		simulation.claim_ai_think(
			"actor",
			0.25
		)
	)

	assert(
		simulation.apply_timed_effect(
			"player",
			"buff:test",
			1.0,
			{"kind": "buff"}
		)
	)

	assert(
		simulation.has_timed_effect(
			"player",
			"buff:test"
		)
	)

	simulation.advance(0.5)

	assert(
		simulation.timed_effect_remaining(
			"player",
			"buff:test"
		) > 0.49
	)

	simulation.advance(0.51)

	assert(
		not simulation.has_timed_effect(
			"player",
			"buff:test"
		)
	)

	var cast := simulation.begin_spell_cast(
		"player",
		"spell:test",
		1.0,
		"spell:test",
		2.0,
		{"target": "self"}
	)

	assert(
		bool(cast.get("success", false))
	)
	assert(
		not simulation.spell_cast_ready(
			"player"
		)
	)

	simulation.advance(1.0)

	assert(
		simulation.spell_cast_ready(
			"player"
		)
	)

	var completed := simulation.complete_spell_cast(
		"player"
	)

	assert(
		bool(completed.get("success", false))
	)

	assert(
		simulation.spell_recast_remaining(
			"player",
			"spell:test"
		) > 1.99
	)

	simulation.advance(2.01)

	assert(
		is_equal_approx(
			simulation.spell_recast_remaining(
				"player",
				"spell:test"
			),
			0.0
		)
	)

	assert(
		simulation.schedule_merchant_restock(
			"peq:merchant:test",
			0.5
		)
	)

	assert(
		not simulation.merchant_restock_due(
			"peq:merchant:test"
		)
	)

	simulation.advance(0.5)

	assert(
		simulation.merchant_restock_due(
			"peq:merchant:test"
		)
	)

	assert(
		simulation.consume_merchant_restock_due(
			"peq:merchant:test"
		)
	)

	assert(
		not simulation.merchant_restock_due(
			"peq:merchant:test"
		)
	)


func _test_simulation_snapshot_restores_timers_and_rng() -> void:
	var source := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(314159)
	)

	source.player_entity_id = "player"

	var player := EntityFactory.create({
		"entity_id": "player",
		"definition_id": "fixture:player:snapshot",
		"kind": "player",
		"display_name": "Player",
		"spawn_position": Vector3.ZERO,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": false,
	})

	source.add_entity(
		player,
		true,
		false
	)

	source.schedule_merchant_restock(
		"peq:merchant:snapshot",
		15.0
	)

	source.apply_timed_effect(
		"player",
		"buff:snapshot",
		10.0
	)

	source.begin_spell_cast(
		"player",
		"spell:snapshot",
		5.0,
		"spell:snapshot",
		3.0
	)

	source.advance(2.0)
	source.rng.randi_range(0, 100000)

	var snapshot := source.snapshot()

	var expected_rng_value := source.rng.randi_range(
		0,
		1000000
	)

	var restored := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(1)
	)

	restored.player_entity_id = "player"

	var restored_player := EntityFactory.create({
		"entity_id": "player",
		"definition_id": "fixture:player:snapshot",
		"kind": "player",
		"display_name": "Player",
		"spawn_position": Vector3.ZERO,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": false,
	})

	restored.add_entity(
		restored_player,
		true,
		false
	)

	restored.restore_snapshot(snapshot)

	assert(
		is_equal_approx(
			restored.merchant_restock_remaining(
				"peq:merchant:snapshot"
			),
			13.0
		)
	)

	assert(
		is_equal_approx(
			restored.timed_effect_remaining(
				"player",
				"buff:snapshot"
			),
			8.0
		)
	)

	assert(
		is_equal_approx(
			restored.spell_cast_remaining(
				"player"
			),
			3.0
		)
	)

	assert(
		restored.rng.randi_range(
			0,
			1000000
		)
		== expected_rng_value
	)


func _test_save_schema_migration() -> void:
	var service := PersistenceService.new(
		"user://phase4_unused_test_save.json",
		SimulationClock.new()
	)

	var version_two := {
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
	}

	var migrated := service.deserialize_envelope(
		JSON.stringify(version_two),
		"eqm:zone:test",
		"test"
	)

	assert(
		bool(migrated.get("ok", false))
	)

	assert(
		bool(migrated.get("migrated", false))
	)

	var migrated_state: Dictionary = migrated["state"]

	assert(
		int(migrated_state["schema_version"])
		== PersistenceService.SAVE_SCHEMA_VERSION
	)

	assert(
		str(
			migrated_state[
				"offline_elapsed_policy"
			]
		)
		== PersistenceService.OFFLINE_ELAPSED_POLICY
	)

	var migrated_simulation: Dictionary = migrated_state[
		"simulation"
	]

	var migrated_timers: Dictionary = migrated_simulation[
		"timers_remaining"
	]

	assert(
		is_equal_approx(
			float(
				migrated_timers[
					"cooldown|player:local|primary"
				]
			),
			4.5
		)
	)

	var exact_seed: int = 9007199254740997
	var exact_state: int = 9007199254741999

	var version_three := {
		"schema_version": PersistenceService.SAVE_SCHEMA_VERSION,
		"zone_key": "eqm:zone:test",
		"zone_legacy_id": "test",
		"player_spawn_revision": 1,
		"saved_unix_ms": 0,
		"offline_elapsed_policy": PersistenceService.OFFLINE_ELAPSED_POLICY,
		"simulation": {
			"clock_elapsed_seconds": 0.0,
			"rng": {
				"seed": exact_seed,
				"state": exact_state,
			},
			"entities": {},
			"timers_remaining": {},
			"timed_effects": {},
			"active_spell_casts": {},
		},
	}

	var round_trip := service.deserialize_envelope(
		service.serialize_envelope(
			version_three
		),
		"eqm:zone:test",
		"test"
	)

	assert(
		bool(round_trip.get("ok", false))
	)

	var round_trip_state: Dictionary = round_trip[
		"state"
	]
	var round_trip_simulation: Dictionary = round_trip_state[
		"simulation"
	]
	var round_trip_rng: Dictionary = round_trip_simulation[
		"rng"
	]

	assert(
		int(round_trip_rng["seed"])
		== exact_seed
	)

	assert(
		int(round_trip_rng["state"])
		== exact_state
	)