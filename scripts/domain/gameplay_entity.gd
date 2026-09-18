class_name GameplayEntity
extends RefCounted

const ATTACHMENT_NONE := "none"
const ATTACHMENT_FACTION_IDENTITY := "faction_identity"
const ATTACHMENT_PLAYER_FACTION := "player_faction_state"
const ATTACHMENT_PLAYER_INVENTORY := "player_inventory_state"
const ATTACHMENT_PLAYER_EQUIPMENT_PENDING := "player_equipment_unimplemented"
const ATTACHMENT_MERCHANT_CATALOG := "merchant_catalog_reference"
const ATTACHMENT_SOURCE_INVENTORY_UNREVIEWED := "source_inventory_unreviewed"
const ATTACHMENT_SOURCE_EQUIPMENT_UNREVIEWED := "source_equipment_unreviewed"

enum Lifecycle {
	CREATED,
	SPAWNED,
	ACTIVE,
	DYING,
	DEAD,
	RESPAWNING,
	REMOVED,
}

const MOVEMENT_IDLE := "idle"
const MOVEMENT_MOVING := "moving"
const MOVEMENT_SWIMMING := "swimming"
const MOVEMENT_AIRBORNE := "airborne"

const COMBAT_DISABLED := "disabled"
const COMBAT_IDLE := "idle"
const COMBAT_ENGAGED := "engaged"
const COMBAT_CASTING := "casting"

var entity_id := ""
var definition_id := ""
var kind := "entity"
var display_name := "Entity"

# Shared gameplay identity. These fields describe who the actor is in gameplay
# terms. Appearance is deliberately separate.
var race_id := 0
var race_ref := ""
var gender_id := 0
var class_id := 0
var class_ref := ""
var level := 1

# Phase 5 provides stat architecture without inventing classic-EQ formulas.
var base_stats: Dictionary = {}
var derived_stats: Dictionary = {}

# Shared resource architecture.
var max_health := 1.0
var health := 1.0
var max_mana := 0.0
var mana := 0.0
var max_endurance := 0.0
var endurance := 0.0

# Shared spatial/runtime state.
var position := Vector3.ZERO
var spawn_position := Vector3.ZERO
var facing := Vector3.FORWARD
var movement_state := MOVEMENT_IDLE
var movement_velocity := Vector3.ZERO
var target_entity_id := ""

# Shared combat/lifecycle state.
var combat_size := 1.0
var combat_enabled := true
var hostile := false
var combat_state := COMBAT_IDLE
var death_delay_seconds := 0.0
var respawn_seconds := -1.0
var lifecycle := Lifecycle.CREATED
var life_number := 0
var dying_until_seconds := -1.0
var respawn_at_seconds := -1.0

# Generic actor attachments. The contents are intentionally neutral so later
# player/NPC systems can specialize without duplicating the actor foundation.
var faction_identity: Dictionary = {}
var inventory_attachment: Dictionary = {}
var equipment_attachment: Dictionary = {}
var effects: Dictionary = {}
var controller_attachment: Dictionary = {}

# Presentation identity. Race/gender/class are gameplay identity; model, skin,
# texture, face, etc. belong here.
var appearance: Dictionary = {}

var rewards: Dictionary = {}
var metadata: Dictionary = {}


func _init(definition: Dictionary = {}) -> void:
	if not definition.is_empty():
		configure(definition)


func configure(definition: Dictionary) -> void:
	entity_id = str(definition.get("entity_id", ""))
	definition_id = str(definition.get("definition_id", ""))
	kind = str(definition.get("kind", "entity"))
	display_name = str(
		definition.get(
			"display_name",
			definition_id if not definition_id.is_empty() else entity_id
		)
	)

	race_id = int(definition.get("race_id", 0))
	race_ref = str(definition.get("race_ref", ""))
	gender_id = int(definition.get("gender_id", 0))
	class_id = int(definition.get("class_id", 0))
	class_ref = str(definition.get("class_ref", ""))
	level = maxi(1, int(definition.get("level", 1)))

	base_stats = _dictionary_copy(definition.get("base_stats", {}))
	derived_stats = _dictionary_copy(definition.get("derived_stats", {}))

	max_health = maxf(1.0, float(definition.get("max_health", 1.0)))
	health = clampf(
		float(definition.get("health", max_health)),
		0.0,
		max_health
	)
	max_mana = maxf(0.0, float(definition.get("max_mana", 0.0)))
	mana = clampf(
		float(definition.get("mana", max_mana)),
		0.0,
		max_mana
	)
	max_endurance = maxf(
		0.0,
		float(definition.get("max_endurance", 0.0))
	)
	endurance = clampf(
		float(definition.get("endurance", max_endurance)),
		0.0,
		max_endurance
	)

	spawn_position = _as_vector3(
		definition.get("spawn_position", Vector3.ZERO)
	)
	position = spawn_position

	set_facing(
		_as_vector3(
			definition.get("facing", Vector3.FORWARD)
		)
	)

	movement_state = str(
		definition.get("movement_state", MOVEMENT_IDLE)
	)
	movement_velocity = _as_vector3(
		definition.get("movement_velocity", Vector3.ZERO)
	)
	target_entity_id = str(
		definition.get("target_entity_id", "")
	)

	combat_size = maxf(
		0.01,
		float(definition.get("combat_size", 1.0))
	)
	combat_enabled = bool(
		definition.get("combat_enabled", true)
	)
	hostile = bool(definition.get("hostile", false))
	combat_state = str(
		definition.get(
			"combat_state",
			COMBAT_IDLE if combat_enabled else COMBAT_DISABLED
		)
	)
	if not combat_enabled:
		combat_state = COMBAT_DISABLED

	death_delay_seconds = maxf(
		0.0,
		float(definition.get("death_delay_seconds", 0.0))
	)
	respawn_seconds = float(
		definition.get("respawn_seconds", -1.0)
	)

	faction_identity = _dictionary_copy(
		definition.get("faction_identity", {})
	)
	inventory_attachment = _dictionary_copy(
		definition.get("inventory_attachment", {})
	)
	equipment_attachment = _dictionary_copy(
		definition.get("equipment_attachment", {})
	)
	effects = _dictionary_copy(
		definition.get("effects", {})
	)
	controller_attachment = _dictionary_copy(
		definition.get("controller_attachment", {})
	)
	appearance = _dictionary_copy(
		definition.get("appearance", {})
	)

	rewards = _dictionary_copy(definition.get("rewards", {}))
	metadata = _dictionary_copy(definition.get("metadata", {}))
	faction_identity = _normalized_attachment(
		faction_identity,
		ATTACHMENT_FACTION_IDENTITY
	)
	inventory_attachment = _normalized_attachment(
		inventory_attachment,
		ATTACHMENT_NONE
	)
	equipment_attachment = _normalized_attachment(
		equipment_attachment,
		ATTACHMENT_NONE
	)
	controller_attachment = _normalized_attachment(
		controller_attachment,
		ATTACHMENT_NONE
	)

func spawn(now_seconds: float, override_position: Variant = null) -> bool:
	if lifecycle not in [
		Lifecycle.CREATED,
		Lifecycle.RESPAWNING,
	]:
		return false

	if override_position != null:
		spawn_position = _as_vector3(override_position)

	position = spawn_position
	health = max_health
	mana = max_mana
	endurance = max_endurance

	set_movement_state(MOVEMENT_IDLE)
	clear_target()
	set_combat_state(COMBAT_IDLE)

	life_number += 1
	dying_until_seconds = -1.0
	respawn_at_seconds = -1.0
	lifecycle = Lifecycle.SPAWNED
	return true


func activate() -> bool:
	if lifecycle != Lifecycle.SPAWNED:
		return false
	lifecycle = Lifecycle.ACTIVE
	return true


func begin_dying(now_seconds: float) -> bool:
	if lifecycle != Lifecycle.ACTIVE:
		return false

	lifecycle = Lifecycle.DYING
	health = 0.0
	set_movement_state(MOVEMENT_IDLE)
	clear_target()
	set_combat_state(COMBAT_IDLE)
	dying_until_seconds = now_seconds + death_delay_seconds
	return true


func mark_dead(now_seconds: float) -> bool:
	if lifecycle != Lifecycle.DYING:
		return false

	lifecycle = Lifecycle.DEAD
	set_movement_state(MOVEMENT_IDLE)
	clear_target()
	set_combat_state(COMBAT_IDLE)
	dying_until_seconds = -1.0
	respawn_at_seconds = (
		now_seconds + respawn_seconds
		if respawn_seconds >= 0.0
		else -1.0
	)
	return true


func begin_respawning() -> bool:
	if (
		lifecycle != Lifecycle.DEAD
		or respawn_seconds < 0.0
	):
		return false

	lifecycle = Lifecycle.RESPAWNING
	return true


func remove() -> bool:
	if lifecycle == Lifecycle.REMOVED:
		return false

	lifecycle = Lifecycle.REMOVED
	set_movement_state(MOVEMENT_IDLE)
	clear_target()
	set_combat_state(COMBAT_IDLE)
	clear_effects()
	dying_until_seconds = -1.0
	respawn_at_seconds = -1.0
	return true


func is_active() -> bool:
	return lifecycle == Lifecycle.ACTIVE


func can_be_targeted() -> bool:
	return lifecycle == Lifecycle.ACTIVE and combat_enabled


func set_facing(direction: Vector3) -> void:
	var flat := Vector3(
		direction.x,
		0.0,
		direction.z
	)

	if flat.length_squared() <= 0.000001:
		facing = Vector3.FORWARD
	else:
		facing = flat.normalized()


func heading_radians() -> float:
	return atan2(facing.x, -facing.z)


func set_heading_radians(value: float) -> void:
	set_facing(
		Vector3(
			sin(value),
			0.0,
			-cos(value)
		)
	)


func set_movement_state(
	state: String,
	velocity: Vector3 = Vector3.ZERO
) -> void:
	movement_state = state if not state.is_empty() else MOVEMENT_IDLE
	movement_velocity = velocity


func set_target_entity(target_id: String) -> void:
	target_entity_id = target_id


func clear_target() -> void:
	target_entity_id = ""


func set_combat_state(state: String) -> void:
	if not combat_enabled:
		combat_state = COMBAT_DISABLED
		return

	combat_state = state if not state.is_empty() else COMBAT_IDLE


func attach_effect(
	effect_id: String,
	payload: Dictionary = {}
) -> bool:
	if effect_id.is_empty():
		return false

	effects[effect_id] = payload.duplicate(true)
	return true


func remove_effect(effect_id: String) -> bool:
	if not effects.has(effect_id):
		return false

	effects.erase(effect_id)
	return true


func has_effect(effect_id: String) -> bool:
	return effects.has(effect_id)


func clear_effects() -> void:
	effects.clear()


func time_until_death_completion(now_seconds: float) -> float:
	if (
		lifecycle != Lifecycle.DYING
		or dying_until_seconds < 0.0
	):
		return 0.0

	return maxf(
		0.0,
		dying_until_seconds - now_seconds
	)


func time_until_respawn(now_seconds: float) -> float:
	if (
		lifecycle != Lifecycle.DEAD
		or respawn_at_seconds < 0.0
	):
		return 0.0

	return maxf(
		0.0,
		respawn_at_seconds - now_seconds
	)


func base_stat_value(
	stat_id: String,
	default_value: float = 0.0
) -> float:
	return _numeric_stat_value(
		base_stats,
		stat_id,
		default_value
	)


func derived_stat_value(
	stat_id: String,
	default_value: float = 0.0
) -> float:
	return _numeric_stat_value(
		derived_stats,
		stat_id,
		default_value
	)


func set_base_stat_value(
	stat_id: String,
	value: float
) -> bool:
	if stat_id.is_empty():
		return false

	base_stats[stat_id] = value
	return true


func set_derived_stat_value(
	stat_id: String,
	value: float
) -> bool:
	if stat_id.is_empty():
		return false

	derived_stats[stat_id] = value
	return true


func attachment_kind(
	attachment: Dictionary
) -> String:
	return str(
		attachment.get(
			"kind",
			ATTACHMENT_NONE
		)
	)


func faction_reference() -> String:
	var npc_ref := str(
		faction_identity.get(
			"npc_faction_ref",
			""
		)
	)

	if not npc_ref.is_empty():
		return npc_ref

	return str(
		faction_identity.get(
			"faction_ref",
			""
		)
	)


func _numeric_stat_value(
	container: Dictionary,
	stat_id: String,
	default_value: float
) -> float:
	var value: Variant = container.get(
		stat_id,
		default_value
	)
	var value_type := typeof(value)

	if (
		value_type != TYPE_INT
		and value_type != TYPE_FLOAT
	):
		return default_value

	return float(value)


func _normalized_attachment(
	attachment: Dictionary,
	nonempty_default_kind: String
) -> Dictionary:
	var result := attachment.duplicate(
		true
	)

	if result.has("kind"):
		return result

	result["kind"] = (
		ATTACHMENT_NONE
		if result.is_empty()
		else nonempty_default_kind
	)

	return result

func runtime_snapshot(now_seconds: float) -> Dictionary:
	return {
		"entity_id": entity_id,
		"position": [
			position.x,
			position.y,
			position.z,
		],
		"facing": [
			facing.x,
			facing.y,
			facing.z,
		],
		"health": health,
		"mana": mana,
		"endurance": endurance,
		"lifecycle": lifecycle_name(lifecycle),
		"life_number": life_number,
		"dying_remaining": time_until_death_completion(
			now_seconds
		),
		"respawn_remaining": time_until_respawn(
			now_seconds
		),
	}


func restore_runtime(
	snapshot: Dictionary,
	now_seconds: float,
	restore_position: bool = true
) -> void:
	if restore_position and snapshot.has("position"):
		position = _as_vector3(
			snapshot.get(
				"position",
				spawn_position
			)
		)

	if snapshot.has("facing"):
		set_facing(
			_as_vector3(
				snapshot.get(
					"facing",
					facing
				)
			)
		)

	health = clampf(
		float(snapshot.get("health", max_health)),
		0.0,
		max_health
	)
	mana = clampf(
		float(snapshot.get("mana", max_mana)),
		0.0,
		max_mana
	)
	endurance = clampf(
		float(
			snapshot.get(
				"endurance",
				max_endurance
			)
		),
		0.0,
		max_endurance
	)

	life_number = maxi(
		0,
		int(
			snapshot.get(
				"life_number",
				life_number
			)
		)
	)

	lifecycle = lifecycle_from_name(
		str(
			snapshot.get(
				"lifecycle",
				"active"
			)
		)
	)

	dying_until_seconds = -1.0
	respawn_at_seconds = -1.0

	set_movement_state(MOVEMENT_IDLE)
	clear_target()
	set_combat_state(COMBAT_IDLE)

	if lifecycle == Lifecycle.DYING:
		health = 0.0
		dying_until_seconds = (
			now_seconds
			+ maxf(
				0.0,
				float(
					snapshot.get(
						"dying_remaining",
						0.0
					)
				)
			)
		)
	elif lifecycle == Lifecycle.DEAD:
		health = 0.0
		if respawn_seconds >= 0.0:
			respawn_at_seconds = (
				now_seconds
				+ maxf(
					0.0,
					float(
						snapshot.get(
							"respawn_remaining",
							0.0
						)
					)
				)
			)
	elif lifecycle == Lifecycle.RESPAWNING:
		health = 0.0
	elif lifecycle == Lifecycle.REMOVED:
		health = 0.0
	elif health <= 0.0:
		health = max_health


static func lifecycle_name(value: int) -> String:
	match value:
		Lifecycle.CREATED:
			return "created"
		Lifecycle.SPAWNED:
			return "spawned"
		Lifecycle.ACTIVE:
			return "active"
		Lifecycle.DYING:
			return "dying"
		Lifecycle.DEAD:
			return "dead"
		Lifecycle.RESPAWNING:
			return "respawning"
		Lifecycle.REMOVED:
			return "removed"

	return "created"


static func lifecycle_from_name(value: String) -> int:
	match value:
		"spawned":
			return Lifecycle.SPAWNED
		"active":
			return Lifecycle.ACTIVE
		"dying":
			return Lifecycle.DYING
		"dead":
			return Lifecycle.DEAD
		"respawning":
			return Lifecycle.RESPAWNING
		"removed":
			return Lifecycle.REMOVED

	return Lifecycle.CREATED


static func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value

	if value is Array and value.size() == 3:
		return Vector3(
			float(value[0]),
			float(value[1]),
			float(value[2])
		)

	return Vector3.ZERO


static func _dictionary_copy(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}
