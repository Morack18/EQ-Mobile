class_name GameplayEvent
extends RefCounted

enum Type {
	ATTACK_REQUESTED,
	ATTACK_PERFORMED,
	DAMAGE,
	HEAL,
	DEATH,
	XP_AWARDED,
	ITEM_GAINED,
	ITEM_LOST,
	LEVEL_CHANGED,
	FACTION_CHANGED,
	SPAWN,
	DESPAWN,
}

var sequence := 0
var type := Type.ATTACK_REQUESTED
var source_entity_id := ""
var target_entity_id := ""
var data: Dictionary = {}


func _init(
	sequence_value: int = 0,
	type_value: int = Type.ATTACK_REQUESTED,
	source_id: String = "",
	target_id: String = "",
	payload: Dictionary = {}
) -> void:
	sequence = sequence_value
	type = type_value
	source_entity_id = source_id
	target_entity_id = target_id
	data = payload.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"sequence": sequence,
		"type": type,
		"type_name": type_name(type),
		"source_entity_id": source_entity_id,
		"target_entity_id": target_entity_id,
		"data": data.duplicate(true),
	}


static func type_name(event_type: int) -> String:
	match event_type:
		Type.ATTACK_REQUESTED:
			return "attack_requested"
		Type.ATTACK_PERFORMED:
			return "attack_performed"
		Type.DAMAGE:
			return "damage"
		Type.HEAL:
			return "heal"
		Type.DEATH:
			return "death"
		Type.XP_AWARDED:
			return "xp_awarded"
		Type.ITEM_GAINED:
			return "item_gained"
		Type.ITEM_LOST:
			return "item_lost"
		Type.LEVEL_CHANGED:
			return "level_changed"
		Type.FACTION_CHANGED:
			return "faction_changed"
		Type.SPAWN:
			return "spawn"
		Type.DESPAWN:
			return "despawn"
	return "unknown"