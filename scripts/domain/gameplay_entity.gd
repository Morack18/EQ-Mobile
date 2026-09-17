class_name GameplayEntity
extends RefCounted

enum Lifecycle {
	CREATED,
	SPAWNED,
	ACTIVE,
	DYING,
	DEAD,
	RESPAWNING,
	REMOVED,
}

var entity_id := ""
var definition_id := ""
var kind := "entity"
var display_name := "Entity"
var position := Vector3.ZERO
var spawn_position := Vector3.ZERO
var facing := Vector3.FORWARD
var combat_size := 1.0
var max_health := 1.0
var health := 1.0
var combat_enabled := true
var hostile := false
var death_delay_seconds := 0.0
var respawn_seconds := -1.0
var lifecycle := Lifecycle.CREATED
var life_number := 0
var dying_until_seconds := -1.0
var respawn_at_seconds := -1.0
var rewards: Dictionary = {}
var metadata: Dictionary = {}


func _init(definition: Dictionary = {}) -> void:
	if not definition.is_empty():
		configure(definition)


func configure(definition: Dictionary) -> void:
	entity_id = str(definition.get("entity_id", ""))
	definition_id = str(definition.get("definition_id", ""))
	kind = str(definition.get("kind", "entity"))
	display_name = str(definition.get("display_name", definition_id if not definition_id.is_empty() else entity_id))
	spawn_position = _as_vector3(definition.get("spawn_position", Vector3.ZERO))
	position = spawn_position
	facing = _as_vector3(definition.get("facing", Vector3.FORWARD))
	if facing.length_squared() <= 0.000001:
		facing = Vector3.FORWARD
	else:
		facing = facing.normalized()
	combat_size = maxf(0.01, float(definition.get("combat_size", 1.0)))
	max_health = maxf(1.0, float(definition.get("max_health", 1.0)))
	health = max_health
	combat_enabled = bool(definition.get("combat_enabled", true))
	hostile = bool(definition.get("hostile", false))
	death_delay_seconds = maxf(0.0, float(definition.get("death_delay_seconds", 0.0)))
	respawn_seconds = float(definition.get("respawn_seconds", -1.0))
	rewards = _dictionary_copy(definition.get("rewards", {}))
	metadata = _dictionary_copy(definition.get("metadata", {}))


func spawn(now_seconds: float, override_position: Variant = null) -> bool:
	if lifecycle not in [Lifecycle.CREATED, Lifecycle.RESPAWNING]:
		return false
	if override_position != null:
		spawn_position = _as_vector3(override_position)
	position = spawn_position
	health = max_health
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
	dying_until_seconds = now_seconds + death_delay_seconds
	return true


func mark_dead(now_seconds: float) -> bool:
	if lifecycle != Lifecycle.DYING:
		return false
	lifecycle = Lifecycle.DEAD
	dying_until_seconds = -1.0
	respawn_at_seconds = now_seconds + respawn_seconds if respawn_seconds >= 0.0 else -1.0
	return true


func begin_respawning() -> bool:
	if lifecycle != Lifecycle.DEAD or respawn_seconds < 0.0:
		return false
	lifecycle = Lifecycle.RESPAWNING
	return true


func remove() -> bool:
	if lifecycle == Lifecycle.REMOVED:
		return false
	lifecycle = Lifecycle.REMOVED
	dying_until_seconds = -1.0
	respawn_at_seconds = -1.0
	return true


func is_active() -> bool:
	return lifecycle == Lifecycle.ACTIVE


func can_be_targeted() -> bool:
	return lifecycle == Lifecycle.ACTIVE and combat_enabled


func time_until_death_completion(now_seconds: float) -> float:
	if lifecycle != Lifecycle.DYING or dying_until_seconds < 0.0:
		return 0.0
	return maxf(0.0, dying_until_seconds - now_seconds)


func time_until_respawn(now_seconds: float) -> float:
	if lifecycle != Lifecycle.DEAD or respawn_at_seconds < 0.0:
		return 0.0
	return maxf(0.0, respawn_at_seconds - now_seconds)


func runtime_snapshot(now_seconds: float) -> Dictionary:
	return {
		"entity_id": entity_id,
		"position": [position.x, position.y, position.z],
		"facing": [facing.x, facing.y, facing.z],
		"health": health,
		"lifecycle": lifecycle_name(lifecycle),
		"life_number": life_number,
		"dying_remaining": time_until_death_completion(now_seconds),
		"respawn_remaining": time_until_respawn(now_seconds),
	}


func restore_runtime(snapshot: Dictionary, now_seconds: float, restore_position: bool = true) -> void:
	if restore_position and snapshot.has("position"):
		position = _as_vector3(snapshot.get("position", spawn_position))
	if snapshot.has("facing"):
		facing = _as_vector3(snapshot.get("facing", facing))
		if facing.length_squared() > 0.000001:
			facing = facing.normalized()
	health = clampf(float(snapshot.get("health", max_health)), 0.0, max_health)
	life_number = maxi(0, int(snapshot.get("life_number", life_number)))
	lifecycle = lifecycle_from_name(str(snapshot.get("lifecycle", "active")))
	dying_until_seconds = -1.0
	respawn_at_seconds = -1.0
	if lifecycle == Lifecycle.DYING:
		health = 0.0
		dying_until_seconds = now_seconds + maxf(0.0, float(snapshot.get("dying_remaining", 0.0)))
	elif lifecycle == Lifecycle.DEAD:
		health = 0.0
		if respawn_seconds >= 0.0:
			respawn_at_seconds = now_seconds + maxf(0.0, float(snapshot.get("respawn_remaining", 0.0)))
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
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _dictionary_copy(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}