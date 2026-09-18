class_name EntityViewRegistry
extends RefCounted

var _views: Dictionary = {}


func bind(entity_id: String, node: Node3D) -> void:
	assert(not entity_id.is_empty(), "A view binding requires an entity ID")
	assert(node != null, "A view binding requires a Node3D")
	_views[entity_id] = node


func unbind(entity_id: String) -> void:
	_views.erase(entity_id)


func view_for(entity_id: String) -> Node3D:
	var node = _views.get(entity_id)
	if is_instance_valid(node) and node is Node3D:
		return node
	return null


func node_for(entity_id: String) -> Node3D:
	return view_for(entity_id)


func sync_to_domain(entity: GameplayEntity) -> void:
	var node := node_for(entity.entity_id)
	if node == null:
		return
	var forward := -node.global_transform.basis.z
	forward.y = 0.0
	entity.position = node.global_position
	if forward.length_squared() > 0.000001:
		entity.set_facing(forward)


func apply_from_domain(entity: GameplayEntity, apply_position: bool = true) -> void:
	var node := node_for(entity.entity_id)
	if node == null:
		return
	if apply_position:
		node.global_position = entity.position
	node.visible = entity.lifecycle in [
		GameplayEntity.Lifecycle.CREATED,
		GameplayEntity.Lifecycle.SPAWNED,
		GameplayEntity.Lifecycle.ACTIVE,
		GameplayEntity.Lifecycle.DYING,
		GameplayEntity.Lifecycle.RESPAWNING,
	]


func set_visible(entity_id: String, visible: bool) -> void:
	var node := node_for(entity_id)
	if node != null:
		node.visible = visible