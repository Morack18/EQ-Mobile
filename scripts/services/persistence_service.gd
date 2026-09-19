class_name PersistenceService
extends RefCounted

const SAVE_SCHEMA_VERSION := 5
const DEFAULT_SAVE_PATH := "user://offline_slice_save.json"
const OFFLINE_ELAPSED_POLICY := "freeze"

var _save_path := DEFAULT_SAVE_PATH
var _clock = null
var last_error := ""
var _write_failure_reported := false


func _init(
	save_path_value: String = DEFAULT_SAVE_PATH,
	clock_provider: Variant = null
) -> void:
	_save_path = save_path_value
	_clock = clock_provider


func save_simulation(
	zone_definition: Dictionary,
	simulation: Simulation,
	zone_runtime_state: ZoneRuntimeState = null,
	zone_state_store: ZoneStateStore = null
) -> Dictionary:
	# Schema 5 stores all known zone runtime snapshots while zone_key remains
	# the currently active zone. Wall-clock passage remains metadata only.
	var zone_key := str(
		zone_definition.get(
			"key",
			""
		)
	)

	if zone_key.is_empty():
		return {
			"ok": false,
			"error": "Cannot save without an active zone key",
		}

	var save_store: ZoneStateStore = (
		zone_state_store
	)

	if save_store == null:
		save_store = ZoneStateStore.new()

	if zone_runtime_state != null:
		if (
			zone_runtime_state.zone_key
			!= zone_key
		):
			return {
				"ok": false,
				"error": (
					"Active ZoneRuntimeState key does not match save zone"
				),
			}

		if not save_store.capture_zone(
			zone_runtime_state
		):
			return {
				"ok": false,
				"error": save_store.last_error,
			}
	elif not save_store.has_zone(
		zone_key
	):
		if not save_store.capture_zone(
			ZoneRuntimeState.new(
				zone_key
			)
		):
			return {
				"ok": false,
				"error": save_store.last_error,
			}

	var envelope := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"zone_key": zone_key,
		"zone_legacy_id": str(
			zone_definition.get(
				"id",
				""
			)
		),
		"player_spawn_revision": int(
			zone_definition.get(
				"player_spawn_revision",
				0
			)
		),
		"saved_unix_ms": _real_world_unix_ms(),
		"offline_elapsed_policy": OFFLINE_ELAPSED_POLICY,
		"zone_states": save_store.snapshot(),
		"simulation": simulation.snapshot(),
	}

	var file := FileAccess.open(
		_save_path,
		FileAccess.WRITE
	)

	if file == null:
		last_error = "Unable to write offline save: %s" % _save_path

		if not _write_failure_reported:
			push_warning(last_error)
			_write_failure_reported = true

		return {
			"ok": false,
			"error": last_error,
		}

	file.store_string(
		serialize_envelope(envelope)
	)
	file.close()

	_write_failure_reported = false
	last_error = ""

	return {"ok": true}


func read_save(
	zone_definition: Dictionary,
	legacy_context: Dictionary = {}
) -> Dictionary:
	if not FileAccess.file_exists(_save_path):
		return {
			"ok": true,
			"loaded": false,
			"reason": "missing",
		}

	var file := FileAccess.open(
		_save_path,
		FileAccess.READ
	)

	if file == null:
		return _load_failure(
			"Unable to open offline save for reading: %s"
			% _save_path
		)

	var text_value: String = file.get_as_text()
	file.close()

	var result := deserialize_envelope(
		text_value,
		str(
			zone_definition.get(
				"key",
				""
			)
		),
		str(
			zone_definition.get(
				"id",
				""
			)
		),
		legacy_context
	)

	if not bool(
		result.get(
			"ok",
			false
		)
	):
		return _load_failure(
			str(
				result.get(
					"error",
					"Invalid save data"
				)
			)
		)

	var envelope: Dictionary = (
		result.get(
			"state",
			{}
		)
	)

	if (
		str(
			envelope.get(
				"zone_key",
				""
			)
		)
		!= str(
			zone_definition.get(
				"key",
				""
			)
		)
	):
		return {
			"ok": true,
			"loaded": false,
			"reason": "zone_mismatch",
		}

	var restore_position := (
		int(
			envelope.get(
				"player_spawn_revision",
				-1
			)
		)
		== int(
			zone_definition.get(
				"player_spawn_revision",
				0
			)
		)
	)

	last_error = ""

	return {
		"ok": true,
		"loaded": true,
		"migrated": bool(
			result.get(
				"migrated",
				false
			)
		),
		"restore_position": restore_position,
		"offline_elapsed_policy":
			OFFLINE_ELAPSED_POLICY,
		"offline_elapsed_seconds":
			_offline_elapsed_seconds(
				envelope
			),
		"envelope":
			envelope.duplicate(true),
	}


func restore_zone_store_from_read(
	read_result: Dictionary,
	zone_state_store: ZoneStateStore
) -> Dictionary:
	if not bool(
		read_result.get(
			"ok",
			false
		)
	):
		return read_result.duplicate(true)

	if not bool(
		read_result.get(
			"loaded",
			false
		)
	):
		return {
			"ok": true,
			"loaded": false,
			"restored": false,
			"reason": str(
				read_result.get(
					"reason",
					"missing"
				)
			),
		}

	if zone_state_store == null:
		return _load_failure(
			"ZoneStateStore is required to restore zone persistence"
		)

	var envelope_variant: Variant = (
		read_result.get(
			"envelope",
			{}
		)
	)

	if not envelope_variant is Dictionary:
		return _load_failure(
			"Prepared save has no envelope"
		)

	var envelope: Dictionary = (
		envelope_variant as Dictionary
	)
	var zone_states_variant: Variant = (
		envelope.get(
			"zone_states",
			{}
		)
	)

	if not zone_states_variant is Dictionary:
		return _load_failure(
			"Save zone-state store payload is missing"
		)

	if not zone_state_store.restore(
		zone_states_variant
	):
		return _load_failure(
			"Unable to restore zone-state store: %s"
			% zone_state_store.last_error
		)

	last_error = ""

	return {
		"ok": true,
		"loaded": true,
		"restored": true,
		"zone_count":
			zone_state_store.zone_keys().size(),
	}


func restore_zone_state_from_read(
	read_result: Dictionary,
	zone_runtime_state: ZoneRuntimeState
) -> Dictionary:
	if zone_runtime_state == null:
		return _load_failure(
			"Zone runtime state is required to restore a zone save"
		)

	var store := ZoneStateStore.new()
	var store_result := (
		restore_zone_store_from_read(
			read_result,
			store
		)
	)

	if not bool(
		store_result.get(
			"ok",
			false
		)
	):
		return store_result

	if not bool(
		store_result.get(
			"loaded",
			false
		)
	):
		return store_result

	var envelope_variant: Variant = (
		read_result.get(
			"envelope",
			{}
		)
	)

	if not envelope_variant is Dictionary:
		return _load_failure(
			"Prepared save has no envelope"
		)

	var envelope: Dictionary = (
		envelope_variant as Dictionary
	)
	var zone_key := str(
		envelope.get(
			"zone_key",
			""
		)
	)

	if not store.restore_zone(
		zone_key,
		zone_runtime_state
	):
		return _load_failure(
			"Unable to restore active zone %s: %s"
			% [
				zone_key,
				store.last_error,
			]
		)

	last_error = ""

	return {
		"ok": true,
		"loaded": true,
		"restored": true,
	}


func restore_simulation_from_read(
	read_result: Dictionary,
	simulation: Simulation
) -> Dictionary:
	if not bool(
		read_result.get(
			"ok",
			false
		)
	):
		return read_result.duplicate(true)

	if not bool(
		read_result.get(
			"loaded",
			false
		)
	):
		return read_result.duplicate(true)

	var envelope_variant: Variant = (
		read_result.get(
			"envelope",
			{}
		)
	)

	if not envelope_variant is Dictionary:
		return _load_failure(
			"Prepared save has no envelope"
		)

	var envelope: Dictionary = (
		envelope_variant as Dictionary
	)

	# Offline elapsed time is diagnostics only. The Phase 4 freeze policy
	# never feeds wall-clock passage into Simulation.advance().
	simulation.restore_snapshot(
		envelope.get(
			"simulation",
			{}
		),
		bool(
			read_result.get(
				"restore_position",
				true
			)
		)
	)

	last_error = ""

	var restored := (
		read_result.duplicate(true)
	)
	restored.erase(
		"envelope"
	)
	return restored


func load_simulation(
	zone_definition: Dictionary,
	simulation: Simulation,
	legacy_context: Dictionary = {},
	zone_runtime_state: ZoneRuntimeState = null
) -> Dictionary:
	var read_result := read_save(
		zone_definition,
		legacy_context
	)

	if (
		zone_runtime_state != null
		and bool(
			read_result.get(
				"ok",
				false
			)
		)
		and bool(
			read_result.get(
				"loaded",
				false
			)
		)
	):
		var zone_result := (
			restore_zone_state_from_read(
				read_result,
				zone_runtime_state
			)
		)

		if not bool(
			zone_result.get(
				"ok",
				false
			)
		):
			return zone_result

	return restore_simulation_from_read(
		read_result,
		simulation
	)


func serialize_envelope(envelope: Dictionary) -> String:
	# RandomNumberGenerator seed/state are 64-bit integers. Preserve them as
	# decimal strings at the JSON boundary to prevent precision loss.
	var serializable: Dictionary = envelope.duplicate(true)

	var simulation_variant: Variant = serializable.get(
		"simulation",
		{}
	)

	if simulation_variant is Dictionary:
		var simulation_payload: Dictionary = simulation_variant

		var rng_variant: Variant = simulation_payload.get(
			"rng",
			{}
		)

		if rng_variant is Dictionary:
			var rng_payload: Dictionary = rng_variant

			if rng_payload.has("seed"):
				rng_payload["seed"] = str(
					rng_payload.get("seed", 1)
				)

			if rng_payload.has("state"):
				rng_payload["state"] = str(
					rng_payload.get("state", 0)
				)

			simulation_payload["rng"] = rng_payload

		serializable["simulation"] = simulation_payload

	return JSON.stringify(
		serializable,
		"",
		true
	)


func deserialize_envelope(
	text: String,
	expected_zone_key: String = "",
	legacy_zone_id: String = "",
	legacy_context: Dictionary = {}
) -> Dictionary:
	var parsed_variant: Variant = JSON.parse_string(text)

	if not parsed_variant is Dictionary:
		return {
			"ok": false,
			"error": "Save is not a JSON object",
		}

	var parsed: Dictionary = parsed_variant
	var version := int(
		parsed.get("schema_version", 0)
	)
	var migrated := false
	var envelope: Dictionary

	if version <= 1:
		envelope = _migrate_legacy_save(
			parsed,
			expected_zone_key,
			legacy_zone_id,
			legacy_context
		)
		migrated = true
	elif version == 2:
		envelope = _migrate_v2_save(parsed)
		migrated = true
	elif version == 3:
		envelope = _migrate_v3_save(parsed)
		migrated = true
	elif version == 4:
		envelope = _migrate_v4_save(parsed)
		migrated = true
	elif version == SAVE_SCHEMA_VERSION:
		envelope = parsed.duplicate(true)
	else:
		return {
			"ok": false,
			"error": (
				"Unsupported save schema version: %d"
				% version
			),
		}

	_decode_exact_rng_fields(envelope)

	var validation_error := _validate_envelope(
		envelope
	)

	if not validation_error.is_empty():
		return {
			"ok": false,
			"error": validation_error,
		}

	return {
		"ok": true,
		"migrated": migrated,
		"state": envelope,
	}


func clear() -> void:
	if FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(
				_save_path
			)
		)


func _validate_envelope(envelope: Dictionary) -> String:
	if (
		int(envelope.get("schema_version", 0))
		!= SAVE_SCHEMA_VERSION
	):
		return "Save schema version is missing or invalid"

	if str(envelope.get("zone_key", "")).is_empty():
		return "Save zone key is missing"

	if not envelope.get("simulation") is Dictionary:
		return "Save simulation payload is missing"

	var zone_states_variant: Variant = (
		envelope.get(
			"zone_states",
			null
		)
	)

	if not zone_states_variant is Dictionary:
		return "Save zone-state store payload is missing"

	var zone_store_probe := ZoneStateStore.new()

	if not zone_store_probe.restore(
		zone_states_variant
	):
		return (
			"Save zone-state store is invalid: %s"
			% zone_store_probe.last_error
		)

	var active_zone_key := str(
		envelope.get(
			"zone_key",
			""
		)
	)

	if not zone_store_probe.has_zone(
		active_zone_key
	):
		return (
			"Save zone-state store does not contain active zone %s"
			% active_zone_key
		)

	if (
		str(
			envelope.get(
				"offline_elapsed_policy",
				OFFLINE_ELAPSED_POLICY
			)
		)
		!= OFFLINE_ELAPSED_POLICY
	):
		return "Unsupported offline elapsed-time policy"

	return ""


func _decode_exact_rng_fields(
	envelope: Dictionary
) -> void:
	var simulation_variant: Variant = envelope.get(
		"simulation",
		{}
	)

	if not simulation_variant is Dictionary:
		return

	var simulation_payload: Dictionary = simulation_variant
	var rng_variant: Variant = simulation_payload.get(
		"rng",
		{}
	)

	if not rng_variant is Dictionary:
		return

	var rng_payload: Dictionary = rng_variant

	if rng_payload.has("seed"):
		rng_payload["seed"] = int(
			rng_payload.get("seed", 1)
		)

	if rng_payload.has("state"):
		rng_payload["state"] = int(
			rng_payload.get("state", 0)
		)

	simulation_payload["rng"] = rng_payload
	envelope["simulation"] = simulation_payload


func _empty_zone_state(
	zone_key: String
) -> Dictionary:
	return ZoneRuntimeState.new(
		zone_key
	).snapshot()


func _single_zone_store_snapshot(
	zone_key: String,
	zone_state: Dictionary
) -> Dictionary:
	var zones: Dictionary = {}

	zones[
		zone_key
	] = zone_state.duplicate(true)

	return {
		"schema_version":
			ZoneStateStore.SCHEMA_VERSION,
		"zones":
			zones,
	}


func _empty_zone_store(
	zone_key: String
) -> Dictionary:
	return _single_zone_store_snapshot(
		zone_key,
		_empty_zone_state(
			zone_key
		)
	)


func _migrate_v4_save(
	version_four: Dictionary
) -> Dictionary:
	var envelope := (
		version_four.duplicate(true)
	)
	var zone_key := str(
		envelope.get(
			"zone_key",
			""
		)
	)
	var zone_state_variant: Variant = (
		envelope.get(
			"zone_state",
			null
		)
	)

	envelope[
		"schema_version"
	] = SAVE_SCHEMA_VERSION

	if zone_state_variant is Dictionary:
		envelope[
			"zone_states"
		] = _single_zone_store_snapshot(
			zone_key,
			zone_state_variant as Dictionary
		)
	else:
		# Schema 4 required zone_state. Preserve invalidity rather than
		# manufacturing state for a malformed schema-4 save.
		envelope[
			"zone_states"
		] = {}

	envelope.erase(
		"zone_state"
	)

	return envelope


func _migrate_v3_save(
	version_three: Dictionary
) -> Dictionary:
	var envelope := (
		version_three.duplicate(true)
	)
	var zone_key := str(
		envelope.get(
			"zone_key",
			""
		)
	)

	envelope[
		"schema_version"
	] = SAVE_SCHEMA_VERSION
	envelope[
		"zone_states"
	] = _empty_zone_store(
		zone_key
	)
	envelope.erase(
		"zone_state"
	)

	return envelope


func _migrate_v2_save(version_two: Dictionary) -> Dictionary:
	var envelope := version_two.duplicate(true)

	envelope["schema_version"] = SAVE_SCHEMA_VERSION
	envelope["saved_unix_ms"] = 0
	envelope["offline_elapsed_policy"] = OFFLINE_ELAPSED_POLICY

	var simulation_variant: Variant = envelope.get(
		"simulation",
		{}
	)
	var simulation_payload: Dictionary = {}

	if simulation_variant is Dictionary:
		simulation_payload = simulation_variant.duplicate(true)

	if not simulation_payload.get("timers_remaining") is Dictionary:
		var timers_remaining: Dictionary = {}
		var cooldowns_variant: Variant = simulation_payload.get(
			"cooldowns_remaining",
			{}
		)

		if cooldowns_variant is Dictionary:
			for legacy_key in cooldowns_variant:
				var remaining_seconds := maxf(
					0.0,
					float(
						cooldowns_variant[legacy_key]
					)
				)

				if remaining_seconds <= 0.0:
					continue

				timers_remaining[
					"%s|%s" % [
						Simulation.TIMER_CATEGORY_COOLDOWN,
						str(legacy_key),
					]
				] = remaining_seconds

		simulation_payload[
			"timers_remaining"
		] = timers_remaining

	if not simulation_payload.get("timed_effects") is Dictionary:
		simulation_payload["timed_effects"] = {}

	if not simulation_payload.get("active_spell_casts") is Dictionary:
		simulation_payload["active_spell_casts"] = {}

	envelope["simulation"] = simulation_payload
	envelope["zone_states"] = _empty_zone_store(
		str(
			envelope.get(
				"zone_key",
				""
			)
		)
	)
	envelope.erase(
		"zone_state"
	)
	return envelope


func _migrate_legacy_save(
	legacy: Dictionary,
	expected_zone_key: String,
	legacy_zone_id: String,
	context: Dictionary
) -> Dictionary:
	var player_entity_id := str(
		context.get(
			"player_entity_id",
			"player:local"
		)
	)
	var npc_entity_id := str(
		context.get(
			"legacy_npc_entity_id",
			""
		)
	)
	var entities: Dictionary = {}

	var player_state := {
		"entity_id": player_entity_id,
		"health": float(
			legacy.get(
				"player_health",
				100.0
			)
		),
		"lifecycle": "active",
		"life_number": 1,
		"dying_remaining": 0.0,
		"respawn_remaining": 0.0,
	}

	if legacy.get("player_position") is Array:
		player_state["position"] = legacy.get(
			"player_position"
		)

	entities[player_entity_id] = player_state

	var rewarded_deaths: Dictionary = {}

	if (
		not npc_entity_id.is_empty()
		and (
			legacy.has("npc_alive")
			or legacy.has("npc_health")
		)
	):
		var npc_alive := bool(
			legacy.get("npc_alive", true)
		)

		var npc_state := {
			"entity_id": npc_entity_id,
			"health": float(
				legacy.get(
					"npc_health",
					1.0
				)
			),
			"lifecycle": (
				"active"
				if npc_alive
				else "dead"
			),
			"life_number": 1,
			"dying_remaining": 0.0,
			"respawn_remaining": maxf(
				0.0,
				float(
					legacy.get(
						"respawn_remaining",
						0.0
					)
				)
			),
		}

		if legacy.get("npc_position") is Array:
			npc_state["position"] = legacy.get(
				"npc_position"
			)

		entities[npc_entity_id] = npc_state

		if bool(
			legacy.get(
				"npc_loot_awarded",
				not npc_alive
			)
		):
			rewarded_deaths[
				"%s:%d" % [
					npc_entity_id,
					1,
				]
			] = true

	var timers_remaining: Dictionary = {}
	var legacy_cooldowns: Variant = legacy.get(
		"ability_cooldowns",
		{}
	)

	if legacy_cooldowns is Dictionary:
		var now_unix_ms := _real_world_unix_ms()

		for group_variant in legacy_cooldowns:
			var group := str(group_variant)
			var ready_at_unix_ms := int(
				legacy_cooldowns[group_variant]
			)
			var remaining_seconds := 0.0

			if now_unix_ms > 0:
				remaining_seconds = maxf(
					0.0,
					(
						ready_at_unix_ms
						- now_unix_ms
					) / 1000.0
				)

			if (
				not group.is_empty()
				and remaining_seconds > 0.0
			):
				var legacy_key := Simulation.make_cooldown_key(
					player_entity_id,
					group
				)

				timers_remaining[
					"%s|%s" % [
						Simulation.TIMER_CATEGORY_COOLDOWN,
						legacy_key,
					]
				] = remaining_seconds

	var saved_legacy_zone := str(
		legacy.get(
			"zone_id",
			legacy_zone_id
		)
	)
	var zone_key := expected_zone_key

	if (
		not legacy_zone_id.is_empty()
		and not saved_legacy_zone.is_empty()
		and saved_legacy_zone != legacy_zone_id
	):
		zone_key = "eqm:zone:%s" % saved_legacy_zone
	elif zone_key.is_empty():
		zone_key = (
			"eqm:zone:%s" % saved_legacy_zone
			if not saved_legacy_zone.is_empty()
			else "eqm:zone:unknown"
		)

	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"zone_key": zone_key,
		"zone_legacy_id": str(
			legacy.get(
				"zone_id",
				legacy_zone_id
			)
		),
		"player_spawn_revision": int(
			legacy.get(
				"player_spawn_revision",
				-1
			)
		),
		"saved_unix_ms": 0,
		"offline_elapsed_policy": OFFLINE_ELAPSED_POLICY,
		"zone_states": _empty_zone_store(
			zone_key
		),
		"simulation": {
			"clock_elapsed_seconds": 0.0,
			"rng": {
				"seed": int(
					context.get("rng_seed", 1)
				)
			},
			"player_entity_id": player_entity_id,
			"player_identity": {
				"class_id": int(
					legacy.get(
						"class_id",
						context.get("class_id", 1)
					)
				),
				"race_id": int(
					legacy.get(
						"race_id",
						context.get("race_id", 2)
					)
				),
				"deity_id": int(
					legacy.get(
						"deity_id",
						context.get("deity_id", 396)
					)
				),
			},
			"entities": entities,
			"inventory": legacy.get(
				"inventory",
				{}
			),
			"wallet": legacy.get(
				"wallet",
				{}
			),
			"progression": {
				"xp_total": int(
					legacy.get(
						"player_xp_total",
						0
					)
				),
			},
			"faction_values": legacy.get(
				"faction_values",
				{}
			),
			"timers_remaining": timers_remaining,
			"timed_effects": {},
			"active_spell_casts": {},
			"rewarded_deaths": rewarded_deaths,
		},
	}


func _offline_elapsed_seconds(
	envelope: Dictionary
) -> float:
	var saved_unix_ms := int(
		envelope.get("saved_unix_ms", 0)
	)
	var current_unix_ms := _real_world_unix_ms()

	if (
		saved_unix_ms <= 0
		or current_unix_ms <= saved_unix_ms
	):
		return 0.0

	return maxf(
		0.0,
		(
			current_unix_ms
			- saved_unix_ms
		) / 1000.0
	)


func _real_world_unix_ms() -> int:
	if _clock == null:
		return 0
	return int(
		_clock.real_world_unix_ms()
	)


func _load_failure(message: String) -> Dictionary:
	last_error = message
	push_warning(message)

	return {
		"ok": false,
		"loaded": false,
		"reason": "invalid",
		"error": message,
	}