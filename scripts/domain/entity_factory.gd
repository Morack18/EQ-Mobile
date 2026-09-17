class_name EntityFactory
extends RefCounted


static func create(definition: Dictionary) -> GameplayEntity:
	var entity_id := str(definition.get("entity_id", ""))
	var definition_id := str(definition.get("definition_id", ""))
	assert(not entity_id.is_empty(), "Gameplay entity requires a stable runtime entity_id")
	assert(not definition_id.is_empty(), "Gameplay entity requires a stable definition_id")
	return GameplayEntity.new(definition)