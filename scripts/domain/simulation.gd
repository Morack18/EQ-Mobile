class_name Simulation
extends RefCounted

const DEFAULT_MELEE_FACING_DOT := 0.556
const ORDINARY_MELEE_EFFECTIVE_SIZE := 8.0

const TIMER_CATEGORY_COOLDOWN := "cooldown"
const TIMER_CATEGORY_SPAWN := "spawn"
const TIMER_CATEGORY_AI := "ai"
const TIMER_CATEGORY_EFFECT := "effect"
const TIMER_CATEGORY_CAST := "cast"
const TIMER_CATEGORY_RECAST := "recast"
const TIMER_CATEGORY_MERCHANT_RESTOCK := "merchant_restock"

var clock: SimulationClock
var rng: SimulationRng
var timers: SimulationTimerBank
var entities: Dictionary = {}
var inventory := InventoryState.new()
var progression := ProgressionState.new()
var faction := FactionSystem.new()
var player_entity_id := ""
var player_identity: Dictionary = {}
var wallet := {"platinum": 0, "gold": 0, "silver": 0, "copper": 0}

var _timed_effects: Dictionary = {}
var _active_spell_casts: Dictionary = {}
var _rewarded_deaths: Dictionary = {}
var _event_queue: Array = []
var _event_sequence := 0


func _init(clock_provider: SimulationClock = null, rng_provider: SimulationRng = null) -> void:
	clock = clock_provider if clock_provider != null else SimulationClock.new()
	rng = rng_provider if rng_provider != null else SimulationRng.new(1)
	timers = SimulationTimerBank.new(clock)


func configure_player_state(
	player_id: String,
	item_definitions: Dictionary,
	inventory_capacity: int,
	progression_config: Dictionary,
	faction_definitions: Dictionary,
	identity: Dictionary,
	item_aliases: Dictionary = {}
) -> void:
	player_entity_id = player_id
	player_identity = identity.duplicate(true)
	inventory.configure(item_definitions, inventory_capacity, item_aliases)
	progression.configure(progression_config)
	faction.configure(faction_definitions, player_identity)
	wallet = {"platinum": 0, "gold": 0, "silver": 0, "copper": 0}
	timers.clear()
	_timed_effects.clear()
	_active_spell_casts.clear()
	_rewarded_deaths.clear()


func add_entity(entity_value: GameplayEntity, spawn_now: bool = true, emit_spawn_event: bool = true) -> GameplayEntity:
	assert(entity_value != null, "Cannot add a null gameplay entity")
	assert(not entity_value.entity_id.is_empty(), "Gameplay entity has no stable ID")
	assert(not entities.has(entity_value.entity_id), "Duplicate gameplay entity ID: %s" % entity_value.entity_id)
	entities[entity_value.entity_id] = entity_value
	if spawn_now:
		entity_value.spawn(clock.now_seconds())
		entity_value.activate()
		if emit_spawn_event:
			_emit(GameplayEvent.Type.SPAWN, entity_value.entity_id, "", {
				"life_number": entity_value.life_number,
			})
	return entity_value


func entity(entity_id: String) -> GameplayEntity:
	return entities.get(entity_id) as GameplayEntity


func sync_entity_pose(entity_id: String, position_value: Vector3, facing_value: Vector3) -> void:
	var target := entity(entity_id)
	if target == null or target.lifecycle == GameplayEntity.Lifecycle.REMOVED:
		return
	target.position = position_value
	var flat_facing := Vector3(facing_value.x, 0.0, facing_value.z)
	if flat_facing.length_squared() > 0.000001:
		target.facing = flat_facing.normalized()


func is_paused() -> bool:
	return clock.is_paused()


func schedule_spawn(entity_id: String, delay_seconds: float) -> bool:
	if clock.is_paused():
		return false

	var target := entity(entity_id)
	if target == null or target.lifecycle != GameplayEntity.Lifecycle.CREATED:
		return false
	timers.start(_spawn_timer_key(entity_id), maxf(0.0, delay_seconds))
	return true


func cancel_scheduled_spawn(entity_id: String) -> bool:
	if is_paused():
		return false

	return timers.cancel(_spawn_timer_key(entity_id))


func spawn_remaining(entity_id: String) -> float:
	return timers.remaining(_spawn_timer_key(entity_id))


func request_attack(
	attacker_id: String,
	target_id: String,
	profile: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	if is_paused():
		return {
			"success": false,
			"reason": "simulation_paused",
		}

	_emit(GameplayEvent.Type.ATTACK_REQUESTED, attacker_id, target_id, {
		"profile_id": str(profile.get("id", profile.get("display_name", "primary"))),
	})

	var reason := _validate_attack(attacker_id, target_id, profile, context)
	if not reason.is_empty():
		return {"success": false, "reason": reason}

	var attacker := entity(attacker_id)
	var target := entity(target_id)
	var cooldown_group := str(profile.get("cooldown_group", ""))
	var cooldown_seconds := _profile_cooldown_seconds(profile)

	if not cooldown_group.is_empty() and cooldown_seconds > 0.0:
		timers.start(
			_cooldown_timer_key(attacker_id, cooldown_group),
			cooldown_seconds
		)

	var hit := _resolve_hit(profile)
	var damage := _resolve_damage(profile) if hit else 0.0

	_emit(GameplayEvent.Type.ATTACK_PERFORMED, attacker_id, target_id, {
		"hit": hit,
		"damage": damage,
		"profile_id": str(profile.get("id", profile.get("display_name", "primary"))),
	})

	if hit:
		_apply_damage(attacker, target, damage)

	return {
		"success": true,
		"reason": "",
		"hit": hit,
		"damage": damage,
	}


func profile_is_learned(attacker_id: String, profile: Dictionary) -> bool:
	if attacker_id != player_entity_id:
		return true
	if progression.level < int(profile.get("required_level", 1)):
		return false

	var allowed_classes = profile.get("allowed_class_ids", [])
	if allowed_classes is Array and not allowed_classes.is_empty():
		return int(player_identity.get("class_id", -1)) in allowed_classes

	return true


func cooldown_remaining(entity_id: String, cooldown_group: String) -> float:
	if cooldown_group.is_empty():
		return 0.0

	var timer_key := _cooldown_timer_key(entity_id, cooldown_group)
	var remaining_seconds := timers.remaining(timer_key)

	if remaining_seconds <= 0.0 and timers.has_timer(timer_key):
		timers.cancel(timer_key)

	return remaining_seconds


func claim_ai_think(entity_id: String, interval_seconds: float) -> bool:
	if is_paused():
		return false

	if interval_seconds <= 0.0:
		return true

	var timer_key := _ai_timer_key(entity_id)
	if not timers.has_timer(timer_key) or timers.is_ready(timer_key):
		timers.start(timer_key, interval_seconds)
		return true

	return false


func ai_think_remaining(entity_id: String) -> float:
	return timers.remaining(_ai_timer_key(entity_id))


func apply_timed_effect(
	target_id: String,
	effect_id: String,
	duration_seconds: float,
	payload: Dictionary = {}
) -> bool:
	if is_paused():
		return false

	var target := entity(target_id)
	if target == null or not target.is_active():
		return false
	if effect_id.is_empty() or duration_seconds <= 0.0:
		return false

	var record_key := _effect_record_key(target_id, effect_id)

	var record := payload.duplicate(true)
	record["target_entity_id"] = target_id
	record["effect_id"] = effect_id
	_timed_effects[record_key] = record

	timers.start(
		_effect_timer_key(target_id, effect_id),
		duration_seconds
	)

	return true


func remove_timed_effect(target_id: String, effect_id: String) -> bool:
	if is_paused():
		return false

	var record_key := _effect_record_key(target_id, effect_id)
	var existed := _timed_effects.has(record_key)

	_timed_effects.erase(record_key)
	timers.cancel(_effect_timer_key(target_id, effect_id))

	return existed


func has_timed_effect(target_id: String, effect_id: String) -> bool:
	return _timed_effects.has(
		_effect_record_key(target_id, effect_id)
	)


func timed_effect_remaining(target_id: String, effect_id: String) -> float:
	return timers.remaining(
		_effect_timer_key(target_id, effect_id)
	)


func timed_effects_for(target_id: String) -> Array:
	var result: Array = []

	for record_key in _timed_effects:
		var record_variant: Variant = _timed_effects[record_key]
		if not record_variant is Dictionary:
			continue

		var record: Dictionary = record_variant
		if str(record.get("target_entity_id", "")) != target_id:
			continue

		var copy := record.duplicate(true)
		copy["remaining_seconds"] = timed_effect_remaining(
			target_id,
			str(record.get("effect_id", ""))
		)
		result.append(copy)

	return result


func begin_spell_cast(
	entity_id: String,
	spell_id: String,
	cast_seconds: float,
	recast_group: String = "",
	recast_seconds: float = 0.0,
	payload: Dictionary = {}
) -> Dictionary:
	if is_paused():
		return {
			"success": false,
			"reason": "simulation_paused",
		}

	var caster := entity(entity_id)
	if caster == null or not caster.is_active():
		return {"success": false, "reason": "caster_inactive"}
	if spell_id.is_empty():
		return {"success": false, "reason": "spell_missing"}
	if _active_spell_casts.has(entity_id):
		return {"success": false, "reason": "already_casting"}
	if not recast_group.is_empty() and spell_recast_remaining(entity_id, recast_group) > 0.0:
		return {"success": false, "reason": "recast"}

	_active_spell_casts[entity_id] = {
		"spell_id": spell_id,
		"recast_group": recast_group,
		"recast_seconds": maxf(0.0, recast_seconds),
		"payload": payload.duplicate(true),
	}

	timers.start(
		_cast_timer_key(entity_id),
		maxf(0.0, cast_seconds)
	)

	return {
		"success": true,
		"reason": "",
		"spell_id": spell_id,
		"cast_seconds": maxf(0.0, cast_seconds),
	}


func spell_cast_remaining(entity_id: String) -> float:
	if not _active_spell_casts.has(entity_id):
		return 0.0
	return timers.remaining(_cast_timer_key(entity_id))


func spell_cast_ready(entity_id: String) -> bool:
	if not _active_spell_casts.has(entity_id):
		return false

	var timer_key := _cast_timer_key(entity_id)
	return not timers.has_timer(timer_key) or timers.is_ready(timer_key)


func complete_spell_cast(entity_id: String) -> Dictionary:
	if is_paused():
		return {
			"success": false,
			"reason": "simulation_paused",
		}

	if not _active_spell_casts.has(entity_id):
		return {"success": false, "reason": "not_casting"}
	if not spell_cast_ready(entity_id):
		return {"success": false, "reason": "casting"}

	var cast_variant: Variant = _active_spell_casts[entity_id]
	if not cast_variant is Dictionary:
		_active_spell_casts.erase(entity_id)
		timers.cancel(_cast_timer_key(entity_id))
		return {"success": false, "reason": "invalid_cast"}

	var cast: Dictionary = cast_variant

	_active_spell_casts.erase(entity_id)
	timers.cancel(_cast_timer_key(entity_id))

	var recast_group := str(cast.get("recast_group", ""))
	var recast_seconds := maxf(
		0.0,
		float(cast.get("recast_seconds", 0.0))
	)

	if not recast_group.is_empty() and recast_seconds > 0.0:
		timers.start(
			_recast_timer_key(entity_id, recast_group),
			recast_seconds
		)

	var payload: Dictionary = {}
	if cast.get("payload", {}) is Dictionary:
		payload = cast.get("payload", {}).duplicate(true)

	return {
		"success": true,
		"reason": "",
		"spell_id": str(cast.get("spell_id", "")),
		"payload": payload,
	}


func interrupt_spell_cast(entity_id: String) -> bool:
	if is_paused():
		return false

	if not _active_spell_casts.has(entity_id):
		return false

	_active_spell_casts.erase(entity_id)
	timers.cancel(_cast_timer_key(entity_id))
	return true


func spell_recast_remaining(entity_id: String, recast_group: String) -> float:
	if recast_group.is_empty():
		return 0.0

	var timer_key := _recast_timer_key(entity_id, recast_group)
	var remaining_seconds := timers.remaining(timer_key)

	if remaining_seconds <= 0.0 and timers.has_timer(timer_key):
		timers.cancel(timer_key)

	return remaining_seconds


func schedule_merchant_restock(
	merchant_ref: String,
	delay_seconds: float
) -> bool:
	if is_paused() or merchant_ref.is_empty():
		return false

	timers.start(
		_merchant_restock_timer_key(merchant_ref),
		maxf(0.0, delay_seconds)
	)
	return true


func merchant_restock_remaining(merchant_ref: String) -> float:
	if merchant_ref.is_empty():
		return 0.0
	return timers.remaining(
		_merchant_restock_timer_key(merchant_ref)
	)


func merchant_restock_due(merchant_ref: String) -> bool:
	if merchant_ref.is_empty():
		return false

	var timer_key := _merchant_restock_timer_key(merchant_ref)
	return timers.has_timer(timer_key) and timers.is_ready(timer_key)


func consume_merchant_restock_due(merchant_ref: String) -> bool:
	if is_paused():
		return false

	if not merchant_restock_due(merchant_ref):
		return false

	timers.cancel(_merchant_restock_timer_key(merchant_ref))
	return true


func heal(source_id: String, target_id: String, amount: float) -> float:
	if is_paused():
		return 0.0

	var target := entity(target_id)
	if target == null or not target.is_active() or amount <= 0.0:
		return 0.0

	var previous := target.health
	target.health = minf(target.max_health, target.health + amount)

	var restored := target.health - previous
	if restored > 0.0:
		_emit(
			GameplayEvent.Type.HEAL,
			source_id,
			target_id,
			{"amount": restored}
		)

	return restored


func grant_item(source_id: String, item_key: String, amount: int) -> bool:
	if is_paused():
		return false

	if not inventory.add_item(item_key, amount):
		return false

	_emit(GameplayEvent.Type.ITEM_GAINED, source_id, player_entity_id, {
		"item_key": item_key,
		"quantity": amount,
	})
	return true


func remove_item(source_id: String, item_key: String, amount: int) -> bool:
	if is_paused():
		return false

	if not inventory.remove_item(item_key, amount):
		return false

	_emit(GameplayEvent.Type.ITEM_LOST, source_id, player_entity_id, {
		"item_key": item_key,
		"quantity": amount,
	})
	return true


func change_faction(
	source_id: String,
	faction_ref: String,
	delta: int
) -> Dictionary:
	if is_paused():
		return {
			"changed": false,
			"reason": "simulation_paused",
			"faction_ref": faction_ref,
		}

	var change := faction.change_value(faction_ref, delta)
	if bool(change.get("changed", false)):
		_emit(
			GameplayEvent.Type.FACTION_CHANGED,
			source_id,
			player_entity_id,
			change
		)
	return change


func faction_reaction(bundle_ref: String) -> Dictionary:
	return faction.reaction_for_npc_bundle(bundle_ref)


func advance(delta_seconds: float) -> void:
	if clock.is_paused():
		return

	clock.advance(delta_seconds)
	var now := clock.now_seconds()

	for entity_id in entities:
		var current := entities[entity_id] as GameplayEntity
		if current == null:
			continue

		if current.lifecycle == GameplayEntity.Lifecycle.CREATED:
			var spawn_timer_key := _spawn_timer_key(current.entity_id)
			if timers.has_timer(spawn_timer_key) and timers.is_ready(spawn_timer_key):
				timers.cancel(spawn_timer_key)
				if current.spawn(now) and current.activate():
					_emit(GameplayEvent.Type.SPAWN, current.entity_id, "", {
						"life_number": current.life_number,
					})

		if (
			current.lifecycle == GameplayEntity.Lifecycle.DYING
			and current.dying_until_seconds <= now
		):
			_complete_death(current)

		if (
			current.lifecycle == GameplayEntity.Lifecycle.DEAD
			and current.respawn_at_seconds >= 0.0
			and current.respawn_at_seconds <= now
		):
			if current.begin_respawning() and current.spawn(now) and current.activate():
				_emit(GameplayEvent.Type.SPAWN, current.entity_id, "", {
					"life_number": current.life_number,
				})

	_expire_timed_effects()


func remove_entity(entity_id: String) -> bool:
	if is_paused():
		return false

	var current := entity(entity_id)

	if current == null or not current.remove():
		return false

	# All entity-owned generic timers use category|owner|timer.
	# Clearing by stable runtime entity ID removes cooldown, initial spawn,
	# AI, timed-effect, cast, and recast deadlines without teaching entity
	# lifecycle code about every timer category individually.
	timers.cancel_owner(entity_id)

	_active_spell_casts.erase(entity_id)

	for record_key in _timed_effects.keys():
		var record_variant: Variant = _timed_effects[record_key]

		if not record_variant is Dictionary:
			_timed_effects.erase(record_key)
			continue

		var record: Dictionary = record_variant

		if str(record.get("target_entity_id", "")) == entity_id:
			_timed_effects.erase(record_key)

	_emit(
		GameplayEvent.Type.DESPAWN,
		current.entity_id,
		"",
		{"reason": "removed"}
	)

	return true


func drain_events() -> Array:
	var result := _event_queue.duplicate()
	_event_queue.clear()
	return result


func snapshot() -> Dictionary:
	var entity_states: Dictionary = {}

	for entity_id in entities:
		var current := entities[entity_id] as GameplayEntity
		entity_states[entity_id] = current.runtime_snapshot(
			clock.now_seconds()
		)

	return {
		"clock_elapsed_seconds": clock.now_seconds(),
		"rng": rng.snapshot(),
		"player_entity_id": player_entity_id,
		"player_identity": player_identity.duplicate(true),
		"entities": entity_states,
		"inventory": inventory.snapshot(),
		"wallet": wallet.duplicate(true),
		"progression": progression.snapshot(),
		"faction_values": faction.values_snapshot(),
		"timers_remaining": timers.snapshot_remaining(),
		"timed_effects": _timed_effects.duplicate(true),
		"active_spell_casts": _active_spell_casts.duplicate(true),
		"rewarded_deaths": _rewarded_deaths.duplicate(true),
		"event_sequence": _event_sequence,
	}


func restore_snapshot(
	snapshot_value: Variant,
	restore_player_position: bool = true
) -> void:
	if not snapshot_value is Dictionary:
		return

	var snapshot: Dictionary = snapshot_value

	var was_paused := clock.is_paused()

	clock.set_elapsed_seconds(
		float(snapshot.get("clock_elapsed_seconds", 0.0))
	)
	clock.set_paused(was_paused)

	var rng_state_variant: Variant = snapshot.get("rng", {})

	if rng_state_variant is Dictionary:
		var rng_state: Dictionary = rng_state_variant
		var seed_value := int(
			rng_state.get(
				"seed",
				rng.initial_seed()
			)
		)

		if rng_state.has("state"):
			rng.restore(
				seed_value,
				int(rng_state.get("state", 0))
			)
		else:
			# Legacy data may provide a seed but no captured generator state.
			# Restart deterministically from that seed rather than inventing
			# state zero.
			rng.set_seed(seed_value)

	var saved_identity = snapshot.get("player_identity", {})
	if saved_identity is Dictionary and not saved_identity.is_empty():
		player_identity = saved_identity.duplicate(true)
		faction.set_identity(player_identity)

	inventory.restore(snapshot.get("inventory", []))
	progression.restore(snapshot.get("progression", {}))
	faction.restore(snapshot.get("faction_values", {}))
	wallet = _sanitized_wallet(snapshot.get("wallet", {}))

	var saved_timers: Variant = snapshot.get("timers_remaining", null)
	if saved_timers is Dictionary:
		timers.restore_remaining(saved_timers)
	else:
		timers.clear()
		_restore_legacy_cooldowns(
			snapshot.get("cooldowns_remaining", {})
		)

	_timed_effects = (
		snapshot.get("timed_effects", {}).duplicate(true)
		if snapshot.get("timed_effects", {}) is Dictionary
		else {}
	)

	_active_spell_casts = (
		snapshot.get("active_spell_casts", {}).duplicate(true)
		if snapshot.get("active_spell_casts", {}) is Dictionary
		else {}
	)

	_rewarded_deaths = (
		snapshot.get("rewarded_deaths", {}).duplicate(true)
		if snapshot.get("rewarded_deaths", {}) is Dictionary
		else {}
	)

	_event_sequence = maxi(
		_event_sequence,
		int(snapshot.get("event_sequence", _event_sequence))
	)

	var saved_entities = snapshot.get("entities", {})
	if saved_entities is Dictionary:
		for entity_id in saved_entities:
			var current := entity(str(entity_id))
			if current == null or not saved_entities[entity_id] is Dictionary:
				continue

			var restore_position := (
				restore_player_position
				if str(entity_id) == player_entity_id
				else true
			)

			current.restore_runtime(
				saved_entities[entity_id],
				clock.now_seconds(),
				restore_position
			)

	_event_queue.clear()


func wallet_total_copper() -> int:
	return (
		int(wallet.get("copper", 0))
		+ int(wallet.get("silver", 0)) * 10
		+ int(wallet.get("gold", 0)) * 100
		+ int(wallet.get("platinum", 0)) * 1000
	)


func credit_copper(amount: int) -> void:
	if is_paused():
		return

	_set_wallet_total_copper(
		wallet_total_copper() + maxi(0, amount)
	)


func debit_copper(amount: int) -> bool:
	if is_paused():
		return false

	if amount < 0 or wallet_total_copper() < amount:
		return false

	_set_wallet_total_copper(
		wallet_total_copper() - amount
	)
	return true


func _validate_attack(
	attacker_id: String,
	target_id: String,
	profile: Dictionary,
	context: Dictionary
) -> String:
	var attacker := entity(attacker_id)
	var target := entity(target_id)

	if attacker == null:
		return "attacker_missing"
	if target == null:
		return "target_missing"
	if not attacker.is_active():
		return "attacker_inactive"
	if not target.is_active():
		return "target_inactive"
	if not attacker.combat_enabled:
		return "attacker_combat_disabled"
	if not target.combat_enabled:
		return "target_combat_disabled"
	if (
		attacker_id == player_entity_id
		and not target.hostile
		and not bool(profile.get("allow_non_hostile", false))
	):
		return "target_not_hostile"
	if not profile_is_learned(attacker_id, profile):
		return "ability_unavailable"

	var cooldown_group := str(
		profile.get("cooldown_group", "")
	)
	if cooldown_remaining(attacker_id, cooldown_group) > 0.0:
		return "cooldown"

	var offset := target.position - attacker.position
	offset.y = 0.0

	var range_squared := _attack_range_squared(
		attacker,
		target,
		profile
	)
	if offset.length_squared() > range_squared:
		return "out_of_range"

	if (
		bool(profile.get("requires_facing", true))
		and offset.length_squared() > 0.000001
	):
		var facing := Vector3(
			attacker.facing.x,
			0.0,
			attacker.facing.z
		)

		if facing.length_squared() <= 0.000001:
			return "not_facing"

		if (
			facing.normalized().dot(offset.normalized())
			< float(
				profile.get(
					"facing_dot_min",
					DEFAULT_MELEE_FACING_DOT
				)
			)
		):
			return "not_facing"

	if (
		bool(profile.get("requires_los", false))
		and not bool(context.get("line_of_sight", false))
	):
		return "line_of_sight"

	return ""


func _attack_range_squared(
	attacker: GameplayEntity,
	target: GameplayEntity,
	profile: Dictionary
) -> float:
	var explicit_range := float(profile.get("range", 0.0))
	if explicit_range > 0.0:
		return explicit_range * explicit_range

	var effective_size := maxf(
		ORDINARY_MELEE_EFFECTIVE_SIZE,
		maxf(attacker.combat_size, target.combat_size)
	)
	return effective_size * effective_size * 4.0


func _profile_cooldown_seconds(profile: Dictionary) -> float:
	if profile.has("cooldown_seconds"):
		return maxf(
			0.0,
			float(profile.get("cooldown_seconds", 0.0))
		)

	if profile.has("delay_tenths"):
		return maxf(
			0.4,
			maxi(1, int(profile.get("delay_tenths", 1))) * 0.1
		)

	return 0.0


func _resolve_hit(profile: Dictionary) -> bool:
	if not profile.has("hit_chance"):
		return true

	return rng.chance(
		float(profile.get("hit_chance", 1.0))
	)


func _resolve_damage(profile: Dictionary) -> float:
	if profile.has("damage"):
		return maxf(
			0.0,
			float(profile.get("damage", 0.0))
		)

	var minimum := float(profile.get("damage_min", 0.0))
	var maximum := float(
		profile.get("damage_max", minimum)
	)

	if maximum < minimum:
		var swap := minimum
		minimum = maximum
		maximum = swap

	if is_equal_approx(minimum, maximum):
		return maxf(0.0, minimum)

	return maxf(
		0.0,
		rng.randf_range(minimum, maximum)
	)


func _apply_damage(
	attacker: GameplayEntity,
	target: GameplayEntity,
	amount: float
) -> void:
	var applied := minf(
		target.health,
		maxf(0.0, amount)
	)

	target.health = maxf(
		0.0,
		target.health - applied
	)

	_emit(GameplayEvent.Type.DAMAGE, attacker.entity_id, target.entity_id, {
		"amount": applied,
		"remaining_health": target.health,
	})

	if target.health > 0.0:
		return
	if not target.begin_dying(clock.now_seconds()):
		return

	_emit(GameplayEvent.Type.DEATH, attacker.entity_id, target.entity_id, {
		"life_number": target.life_number,
	})

	_grant_death_rewards_once(attacker, target)

	if target.death_delay_seconds <= 0.0:
		_complete_death(target)


func _grant_death_rewards_once(
	attacker: GameplayEntity,
	target: GameplayEntity
) -> void:
	var death_key := "%s:%d" % [
		target.entity_id,
		target.life_number,
	]

	if _rewarded_deaths.has(death_key):
		return

	_rewarded_deaths[death_key] = true

	if attacker.entity_id != player_entity_id:
		return

	for reward_variant in target.rewards.get("items", []):
		if not reward_variant is Dictionary:
			continue

		var reward: Dictionary = reward_variant
		var item_key := str(
			reward.get(
				"item_key",
				reward.get("item_id", "")
			)
		)
		var quantity := int(reward.get("quantity", 0))

		if item_key.is_empty() or quantity <= 0:
			continue

		if inventory.add_item(item_key, quantity):
			_emit(
				GameplayEvent.Type.ITEM_GAINED,
				target.entity_id,
				player_entity_id,
				{
					"item_key": item_key,
					"quantity": quantity,
					"death_key": death_key,
				}
			)

	var xp_reward := int(
		target.rewards.get(
			"xp",
			target.rewards.get("xp_reward", 0)
		)
	)

	if xp_reward <= 0:
		return

	var result := progression.award_xp(xp_reward)
	var awarded := int(result.get("awarded", 0))

	if awarded > 0:
		_emit(
			GameplayEvent.Type.XP_AWARDED,
			target.entity_id,
			player_entity_id,
			{
				"amount": awarded,
				"xp_total": progression.xp_total,
				"death_key": death_key,
			}
		)

	if (
		int(result.get("level", progression.level))
		> int(
			result.get(
				"previous_level",
				progression.level
			)
		)
	):
		_emit(
			GameplayEvent.Type.LEVEL_CHANGED,
			player_entity_id,
			player_entity_id,
			{
				"previous_level": int(
					result.get(
						"previous_level",
						progression.level
					)
				),
				"level": progression.level,
			}
		)


func _complete_death(target: GameplayEntity) -> void:
	if not target.mark_dead(clock.now_seconds()):
		return

	_emit(GameplayEvent.Type.DESPAWN, target.entity_id, "", {
		"reason": "death",
		"life_number": target.life_number,
		"respawn_seconds": target.respawn_seconds,
	})


func _expire_timed_effects() -> void:
	for record_key in _timed_effects.keys():
		var record_variant: Variant = _timed_effects[record_key]

		if not record_variant is Dictionary:
			_timed_effects.erase(record_key)
			continue

		var record: Dictionary = record_variant
		var target_id := str(
			record.get("target_entity_id", "")
		)
		var effect_id := str(
			record.get("effect_id", "")
		)
		var timer_key := _effect_timer_key(
			target_id,
			effect_id
		)

		if (
			not timers.has_timer(timer_key)
			or timers.is_ready(timer_key)
		):
			_timed_effects.erase(record_key)
			timers.cancel(timer_key)


func _restore_legacy_cooldowns(saved_cooldowns: Variant) -> void:
	if not saved_cooldowns is Dictionary:
		return

	for legacy_key in saved_cooldowns:
		var remaining_seconds := maxf(
			0.0,
			float(saved_cooldowns[legacy_key])
		)

		if remaining_seconds <= 0.0:
			continue

		timers.start(
			"%s|%s" % [
				TIMER_CATEGORY_COOLDOWN,
				str(legacy_key),
			],
			remaining_seconds
		)


func _emit(
	event_type: int,
	source_id: String,
	target_id: String,
	data: Dictionary = {}
) -> GameplayEvent:
	_event_sequence += 1

	var event := GameplayEvent.new(
		_event_sequence,
		event_type,
		source_id,
		target_id,
		data
	)

	_event_queue.append(event)
	return event


func _sanitized_wallet(saved_wallet: Variant) -> Dictionary:
	var restored := {
		"platinum": 0,
		"gold": 0,
		"silver": 0,
		"copper": 0,
	}

	if saved_wallet is Dictionary:
		for denomination in restored:
			restored[denomination] = maxi(
				0,
				int(saved_wallet.get(denomination, 0))
			)

	return restored


func _set_wallet_total_copper(total: int) -> void:
	var remaining := maxi(0, total)

	wallet["platinum"] = remaining / 1000
	remaining %= 1000

	wallet["gold"] = remaining / 100
	remaining %= 100

	wallet["silver"] = remaining / 10
	wallet["copper"] = remaining % 10


func _cooldown_timer_key(
	entity_id: String,
	cooldown_group: String
) -> String:
	return make_timer_key(
		TIMER_CATEGORY_COOLDOWN,
		entity_id,
		cooldown_group
	)


func _spawn_timer_key(entity_id: String) -> String:
	return make_timer_key(
		TIMER_CATEGORY_SPAWN,
		entity_id,
		"initial"
	)


func _ai_timer_key(entity_id: String) -> String:
	return make_timer_key(
		TIMER_CATEGORY_AI,
		entity_id,
		"think"
	)


func _effect_timer_key(
	target_id: String,
	effect_id: String
) -> String:
	return make_timer_key(
		TIMER_CATEGORY_EFFECT,
		target_id,
		effect_id
	)


func _effect_record_key(
	target_id: String,
	effect_id: String
) -> String:
	return "%s|%s" % [
		target_id,
		effect_id,
	]


func _cast_timer_key(entity_id: String) -> String:
	return make_timer_key(
		TIMER_CATEGORY_CAST,
		entity_id,
		"active"
	)


func _recast_timer_key(
	entity_id: String,
	recast_group: String
) -> String:
	return make_timer_key(
		TIMER_CATEGORY_RECAST,
		entity_id,
		recast_group
	)


func _merchant_restock_timer_key(
	merchant_ref: String
) -> String:
	return make_timer_key(
		TIMER_CATEGORY_MERCHANT_RESTOCK,
		merchant_ref,
		"stock"
	)


static func make_cooldown_key(
	entity_id: String,
	cooldown_group: String
) -> String:
	# Retained for migration of saves that predate the generic timer bank.
	return "%s|%s" % [
		entity_id,
		cooldown_group,
	]


static func make_timer_key(
	category: String,
	owner_id: String,
	timer_id: String
) -> String:
	assert(
		not category.is_empty(),
		"Simulation timer category cannot be empty"
	)
	assert(
		not owner_id.is_empty(),
		"Simulation timer owner cannot be empty"
	)
	assert(
		not timer_id.is_empty(),
		"Simulation timer ID cannot be empty"
	)

	return "%s|%s|%s" % [
		category,
		owner_id,
		timer_id,
	]