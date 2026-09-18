extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_clock_pause()
	_test_timer_bank_snapshot()
	_test_rng_determinism()
	_test_spawn_attack_respawn_and_pause()
	_test_ai_effect_cast_recast_and_merchant_timers()
	_test_simulation_snapshot_restores_timers_and_rng()
	_test_save_schema_migration()
	_test_death_delay_and_respawn()
	_test_paused_gameplay_mutation()
	_test_removed_entity_cleanup()
	_test_offline_freeze()
	_test_explicit_zero_rng_restore()

	if _failures.is_empty():
		print(
			"PASS: canonical time, timers, pause, persistence, and deterministic RNG contracts hold."
		)
		quit(0)
		return

	for failure in _failures:
		push_error(failure)

	print(
		"FAIL: Phase 4 time/RNG tests (%d failures)."
		% _failures.size()
	)
	quit(1)


func _test_clock_pause() -> void:
	var clock := SimulationClock.new()

	clock.advance(1.25)
	_expect(
		is_equal_approx(
			clock.now_seconds(),
			1.25
		)
	)

	clock.set_paused(true)
	clock.advance(10.0)

	_expect(
		is_equal_approx(
			clock.now_seconds(),
			1.25
		)
	)

	clock.set_paused(false)
	clock.advance(0.75)

	_expect(
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

	_expect(
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

	_expect(
		is_equal_approx(
			restored.remaining("test|owner|one"),
			7.0
		)
	)


func _test_rng_determinism() -> void:
	var first := SimulationRng.new(123456)
	var second := SimulationRng.new(123456)

	for _index in 16:
		_expect(
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

	_expect(
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

	_expect(
		delayed.lifecycle
		== GameplayEntity.Lifecycle.CREATED
	)

	_expect(
		simulation.schedule_spawn(
			"delayed",
			1.0
		)
	)

	simulation.advance(0.5)

	_expect(
		delayed.lifecycle
		== GameplayEntity.Lifecycle.CREATED
	)

	simulation.advance(0.5)
	_expect(delayed.is_active())

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

	_expect(
		bool(attack.get("success", false))
	)

	_expect(
		target.lifecycle
		== GameplayEntity.Lifecycle.DEAD
	)

	_expect(
		simulation.cooldown_remaining(
			"player",
			"primary"
		) > 0.99
	)

	clock.set_paused(true)
	simulation.advance(10.0)

	_expect(
		target.lifecycle
		== GameplayEntity.Lifecycle.DEAD
	)

	_expect(
		simulation.cooldown_remaining(
			"player",
			"primary"
		) > 0.99
	)

	clock.set_paused(false)
	simulation.advance(1.01)

	_expect(
		is_equal_approx(
			simulation.cooldown_remaining(
				"player",
				"primary"
			),
			0.0
		)
	)

	_expect(
		target.lifecycle
		== GameplayEntity.Lifecycle.DEAD
	)

	simulation.advance(1.0)
	_expect(target.is_active())


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

	_expect(
		simulation.claim_ai_think(
			"actor",
			0.25
		)
	)

	_expect(
		not simulation.claim_ai_think(
			"actor",
			0.25
		)
	)

	simulation.advance(0.25)

	_expect(
		simulation.claim_ai_think(
			"actor",
			0.25
		)
	)

	_expect(
		simulation.apply_timed_effect(
			"player",
			"buff:test",
			1.0,
			{"kind": "buff"}
		)
	)

	_expect(
		simulation.has_timed_effect(
			"player",
			"buff:test"
		)
	)

	simulation.advance(0.5)

	_expect(
		simulation.timed_effect_remaining(
			"player",
			"buff:test"
		) > 0.49
	)

	simulation.advance(0.51)

	_expect(
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

	_expect(
		bool(cast.get("success", false))
	)
	_expect(
		not simulation.spell_cast_ready(
			"player"
		)
	)

	simulation.advance(1.0)

	_expect(
		simulation.spell_cast_ready(
			"player"
		)
	)

	var completed := simulation.complete_spell_cast(
		"player"
	)

	_expect(
		bool(completed.get("success", false))
	)

	_expect(
		simulation.spell_recast_remaining(
			"player",
			"spell:test"
		) > 1.99
	)

	simulation.advance(2.01)

	_expect(
		is_equal_approx(
			simulation.spell_recast_remaining(
				"player",
				"spell:test"
			),
			0.0
		)
	)

	_expect(
		simulation.schedule_merchant_restock(
			"peq:merchant:test",
			0.5
		)
	)

	_expect(
		not simulation.merchant_restock_due(
			"peq:merchant:test"
		)
	)

	simulation.advance(0.5)

	_expect(
		simulation.merchant_restock_due(
			"peq:merchant:test"
		)
	)

	_expect(
		simulation.consume_merchant_restock_due(
			"peq:merchant:test"
		)
	)

	_expect(
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

	_expect(
		is_equal_approx(
			restored.merchant_restock_remaining(
				"peq:merchant:snapshot"
			),
			13.0
		)
	)

	_expect(
		is_equal_approx(
			restored.timed_effect_remaining(
				"player",
				"buff:snapshot"
			),
			8.0
		)
	)

	_expect(
		is_equal_approx(
			restored.spell_cast_remaining(
				"player"
			),
			3.0
		)
	)

	_expect(
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

	_expect(
		bool(migrated.get("ok", false))
	)

	_expect(
		bool(migrated.get("migrated", false))
	)

	var migrated_state: Dictionary = migrated["state"]

	_expect(
		int(migrated_state["schema_version"])
		== PersistenceService.SAVE_SCHEMA_VERSION
	)

	_expect(
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

	_expect(
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

	_expect(
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

	_expect(
		int(round_trip_rng["seed"])
		== exact_seed
	)

	_expect(
		int(round_trip_rng["state"])
		== exact_state
	)


func _expect(
	condition: bool,
	message: String = "Phase 4 expectation failed"
) -> void:
	if not condition:
		_failures.append(message)


func _test_death_delay_and_respawn() -> void:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(21)
	)

	simulation.player_entity_id = "player"

	var player := EntityFactory.create({
		"entity_id": "player",
		"definition_id": "fixture:player:death",
		"spawn_position": Vector3.ZERO,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": false,
	})

	var target := EntityFactory.create({
		"entity_id": "death_target",
		"definition_id": "fixture:npc:death",
		"spawn_position": Vector3(0.0, 0.0, -1.0),
		"max_health": 10.0,
		"combat_enabled": true,
		"hostile": true,
		"death_delay_seconds": 0.5,
		"respawn_seconds": 1.0,
	})

	simulation.add_entity(player, true, false)
	simulation.add_entity(target, true, false)

	var attack := simulation.request_attack(
		"player",
		"death_target",
		{
			"id": "death_test",
			"damage": 10.0,
			"range": 5.0,
			"requires_facing": false,
		}
	)

	_expect(
		bool(attack.get("success", false)),
		"death-delay test attack succeeds"
	)

	_expect(
		target.lifecycle
			== GameplayEntity.Lifecycle.DYING,
		"lethal hit enters DYING during nonzero death delay"
	)

	simulation.advance(0.49)

	_expect(
		target.lifecycle
			== GameplayEntity.Lifecycle.DYING,
		"entity remains DYING before death deadline"
	)

	simulation.advance(0.02)

	_expect(
		target.lifecycle
			== GameplayEntity.Lifecycle.DEAD,
		"entity becomes DEAD after death deadline"
	)

	simulation.advance(0.98)

	_expect(
		target.lifecycle
			== GameplayEntity.Lifecycle.DEAD,
		"entity remains DEAD before respawn deadline"
	)

	simulation.advance(0.03)

	_expect(
		target.is_active(),
		"entity respawns after canonical respawn deadline"
	)


func _test_paused_gameplay_mutation() -> void:
	var clock := SimulationClock.new()
	var simulation := Simulation.new(
		clock,
		SimulationRng.new(22)
	)

	simulation.player_entity_id = "player"

	var player := EntityFactory.create({
		"entity_id": "player",
		"definition_id": "fixture:player:paused",
		"spawn_position": Vector3.ZERO,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": false,
	})

	var target := EntityFactory.create({
		"entity_id": "paused_target",
		"definition_id": "fixture:npc:paused",
		"spawn_position": Vector3(0.0, 0.0, -1.0),
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": true,
	})

	var delayed := EntityFactory.create({
		"entity_id": "paused_delayed",
		"definition_id": "fixture:npc:paused_delayed",
		"spawn_position": Vector3.ZERO,
		"max_health": 1.0,
		"combat_enabled": false,
		"hostile": false,
	})

	simulation.add_entity(player, true, false)
	simulation.add_entity(target, true, false)
	simulation.add_entity(delayed, false, false)

	var health_before := target.health
	var wallet_before := simulation.wallet_total_copper()

	clock.set_paused(true)

	var attack := simulation.request_attack(
		"player",
		"paused_target",
		{
			"id": "paused_attack",
			"damage": 25.0,
			"range": 5.0,
			"requires_facing": false,
			"cooldown_group": "paused",
			"cooldown_seconds": 10.0,
		}
	)

	_expect(
		not bool(attack.get("success", true)),
		"paused attack is rejected"
	)

	_expect(
		str(attack.get("reason", ""))
			== "simulation_paused",
		"paused attack reports simulation_paused"
	)

	_expect(
		is_equal_approx(target.health, health_before),
		"paused attack does not damage target"
	)

	_expect(
		is_equal_approx(
			simulation.cooldown_remaining(
				"player",
				"paused"
			),
			0.0
		),
		"paused attack does not start cooldown"
	)

	_expect(
		not simulation.schedule_spawn(
			"paused_delayed",
			1.0
		),
		"paused simulation cannot schedule spawn"
	)

	_expect(
		not simulation.claim_ai_think(
			"player",
			1.0
		),
		"paused simulation cannot claim AI think timer"
	)

	_expect(
		not simulation.apply_timed_effect(
			"player",
			"paused_effect",
			10.0
		),
		"paused simulation cannot apply timed effect"
	)

	var cast := simulation.begin_spell_cast(
		"player",
		"paused_spell",
		1.0
	)

	_expect(
		not bool(cast.get("success", true)),
		"paused simulation cannot begin spell cast"
	)

	_expect(
		str(cast.get("reason", ""))
			== "simulation_paused",
		"paused cast reports simulation_paused"
	)

	_expect(
		not simulation.schedule_merchant_restock(
			"peq:merchant:paused",
			10.0
		),
		"paused simulation cannot schedule merchant restock"
	)

	simulation.credit_copper(100)

	_expect(
		simulation.wallet_total_copper() == wallet_before,
		"paused simulation cannot mutate wallet"
	)

	clock.set_paused(false)


func _test_removed_entity_cleanup() -> void:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(23)
	)

	var actor := EntityFactory.create({
		"entity_id": "cleanup_actor",
		"definition_id": "fixture:npc:cleanup_actor",
		"spawn_position": Vector3.ZERO,
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": true,
	})

	var target := EntityFactory.create({
		"entity_id": "cleanup_target",
		"definition_id": "fixture:npc:cleanup_target",
		"spawn_position": Vector3(0.0, 0.0, -1.0),
		"max_health": 100.0,
		"combat_enabled": true,
		"hostile": true,
	})

	var delayed := EntityFactory.create({
		"entity_id": "cleanup_delayed",
		"definition_id": "fixture:npc:cleanup_delayed",
		"spawn_position": Vector3.ZERO,
		"max_health": 1.0,
		"combat_enabled": false,
		"hostile": false,
	})

	simulation.add_entity(actor, true, false)
	simulation.add_entity(target, true, false)
	simulation.add_entity(delayed, false, false)

	_expect(
		simulation.claim_ai_think(
			"cleanup_actor",
			30.0
		),
		"cleanup setup creates AI timer"
	)

	_expect(
		simulation.apply_timed_effect(
			"cleanup_actor",
			"cleanup_effect",
			30.0
		),
		"cleanup setup creates timed effect"
	)

	var recast_cast := simulation.begin_spell_cast(
		"cleanup_actor",
		"cleanup_recast_spell",
		0.0,
		"cleanup_recast",
		30.0
	)

	_expect(
		bool(recast_cast.get("success", false)),
		"cleanup setup creates zero-duration cast"
	)

	var completed := simulation.complete_spell_cast(
		"cleanup_actor"
	)

	_expect(
		bool(completed.get("success", false)),
		"cleanup setup creates recast timer"
	)

	var active_cast := simulation.begin_spell_cast(
		"cleanup_actor",
		"cleanup_active_spell",
		30.0
	)

	_expect(
		bool(active_cast.get("success", false)),
		"cleanup setup creates active cast"
	)

	var attack := simulation.request_attack(
		"cleanup_actor",
		"cleanup_target",
		{
			"id": "cleanup_attack",
			"damage": 1.0,
			"range": 5.0,
			"requires_facing": false,
			"cooldown_group": "cleanup_attack",
			"cooldown_seconds": 30.0,
		}
	)

	_expect(
		bool(attack.get("success", false)),
		"cleanup setup creates cooldown timer"
	)

	_expect(
		simulation.schedule_spawn(
			"cleanup_delayed",
			30.0
		),
		"cleanup setup creates delayed spawn timer"
	)

	_expect(
		simulation.schedule_merchant_restock(
			"peq:merchant:keep",
			30.0
		),
		"cleanup setup creates unrelated merchant timer"
	)

	_expect(
		simulation.remove_entity("cleanup_actor"),
		"active cleanup actor is removed"
	)

	_expect(
		simulation.remove_entity("cleanup_delayed"),
		"created delayed entity is removed"
	)

	var snapshot := simulation.snapshot()

	var timer_snapshot: Dictionary = snapshot.get(
		"timers_remaining",
		{}
	)

	for timer_key_variant in timer_snapshot:
		var timer_key := str(timer_key_variant)

		_expect(
			not timer_key.contains("|cleanup_actor|"),
			"removed actor leaves no owned timer: %s"
			% timer_key
		)

		_expect(
			not timer_key.contains("|cleanup_delayed|"),
			"removed delayed entity leaves no spawn timer: %s"
			% timer_key
		)

	_expect(
		timer_snapshot.has(
			"merchant_restock|peq:merchant:keep|stock"
		),
		"unrelated merchant restock timer survives entity removal"
	)

	var effects: Dictionary = snapshot.get(
		"timed_effects",
		{}
	)

	for record_variant in effects.values():
		if not record_variant is Dictionary:
			continue

		var record: Dictionary = record_variant

		_expect(
			str(
				record.get(
					"target_entity_id",
					""
				)
			)
			!= "cleanup_actor",
			"removed actor leaves no timed-effect metadata"
		)

	var casts: Dictionary = snapshot.get(
		"active_spell_casts",
		{}
	)

	_expect(
		not casts.has("cleanup_actor"),
		"removed actor leaves no active-cast metadata"
	)


func _test_offline_freeze() -> void:
	var save_path := (
		"user://phase4_offline_freeze_test.json"
	)

	var source := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(24)
	)

	_expect(
		source.schedule_merchant_restock(
			"peq:merchant:offline",
			30.0
		),
		"offline-freeze setup creates timer"
	)

	var envelope := {
		"schema_version":
			PersistenceService.SAVE_SCHEMA_VERSION,
		"zone_key": "eqm:zone:test",
		"zone_legacy_id": "test",
		"player_spawn_revision": 0,
		"saved_unix_ms":
			source.clock.real_world_unix_ms()
			- 120000,
		"offline_elapsed_policy":
			PersistenceService.OFFLINE_ELAPSED_POLICY,
		"simulation": source.snapshot(),
	}

	var persistence := PersistenceService.new(
		save_path,
		source.clock
	)

	persistence.clear()

	var file := FileAccess.open(
		save_path,
		FileAccess.WRITE
	)

	_expect(
		file != null,
		"offline-freeze test can create save file"
	)

	if file == null:
		return

	file.store_string(
		persistence.serialize_envelope(envelope)
	)
	file.close()

	var restored := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(1)
	)

	var loader := PersistenceService.new(
		save_path,
		restored.clock
	)

	var result := loader.load_simulation(
		{
			"key": "eqm:zone:test",
			"id": "test",
			"player_spawn_revision": 0,
		},
		restored
	)

	_expect(
		bool(result.get("ok", false))
			and bool(result.get("loaded", false)),
		"offline-freeze save loads"
	)

	_expect(
		float(
			result.get(
				"offline_elapsed_seconds",
				0.0
			)
		) >= 100.0,
		"offline elapsed wall time is observed"
	)

	_expect(
		is_equal_approx(
			restored.merchant_restock_remaining(
				"peq:merchant:offline"
			),
			30.0
		),
		"offline wall time does not advance gameplay timer"
	)

	loader.clear()


func _test_explicit_zero_rng_restore() -> void:
	var simulation := Simulation.new(
		SimulationClock.new(),
		SimulationRng.new(99)
	)

	simulation.restore_snapshot({
		"clock_elapsed_seconds": 0.0,
		"rng": {
			"seed": 12345,
			"state": 0,
		},
	})

	_expect(
		simulation.rng.initial_seed() == 12345,
		"explicit zero-state restore preserves RNG seed"
	)

	_expect(
		simulation.rng.state() == 0,
		"explicit RNG state zero restores exactly"
	)
