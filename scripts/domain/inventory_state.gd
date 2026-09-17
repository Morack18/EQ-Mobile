class_name InventoryState
extends RefCounted

var capacity := 8
var _item_definitions: Dictionary = {}
var _aliases: Dictionary = {}
var _entries: Array = []


func configure(item_definitions: Dictionary, capacity_value: int, aliases: Dictionary = {}) -> void:
	_item_definitions = item_definitions.duplicate(true)
	capacity = maxi(1, capacity_value)
	_aliases = aliases.duplicate(true)
	_entries.clear()


func entries() -> Array:
	var result: Array = []
	for entry in _entries:
		result.append(entry.duplicate(true))
	return result


func snapshot() -> Array:
	return entries()


func restore(saved_inventory: Variant) -> void:
	_entries.clear()
	if saved_inventory is Dictionary:
		for legacy_key in saved_inventory:
			_append_loaded_item(_normalize_key(str(legacy_key)), int(saved_inventory[legacy_key]), null)
		return
	if not saved_inventory is Array:
		return
	for instance in saved_inventory:
		if instance is Dictionary:
			_append_loaded_item(
				_normalize_key(str(instance.get("item_key", ""))),
				int(instance.get("quantity", 0)),
				instance.get("charges_remaining")
			)


func add_item(item_key: String, amount: int) -> bool:
	item_key = _normalize_key(item_key)
	if not _item_definitions.has(item_key) or amount <= 0:
		return false
	var candidate := entries()
	var definition: Dictionary = _item_definitions[item_key]
	var remaining := amount
	var stackable := bool(definition.get("stackable", false))
	var stack_size := maxi(1, int(definition.get("stack_size", 1))) if stackable else 1
	if stackable:
		for instance in candidate:
			if str(instance.get("item_key", "")) != item_key or int(instance.get("quantity", 0)) >= stack_size:
				continue
			var moved := mini(remaining, stack_size - int(instance.get("quantity", 0)))
			instance["quantity"] = int(instance.get("quantity", 0)) + moved
			remaining -= moved
			if remaining <= 0:
				break
	while remaining > 0:
		if candidate.size() >= capacity:
			return false
		var quantity := mini(remaining, stack_size)
		var charges: Variant = null
		if not stackable and int(definition.get("max_charges", 0)) > 0:
			charges = int(definition.get("max_charges", 0))
		candidate.append({
			"item_key": item_key,
			"quantity": quantity,
			"charges_remaining": charges,
		})
		remaining -= quantity
	_entries = candidate
	return true


func remove_item(item_key: String, amount: int) -> bool:
	item_key = _normalize_key(item_key)
	if amount <= 0 or quantity(item_key) < amount:
		return false
	var remaining := amount
	for index in range(_entries.size() - 1, -1, -1):
		var instance: Dictionary = _entries[index]
		if str(instance.get("item_key", "")) != item_key:
			continue
		var available := int(instance.get("quantity", 0))
		var removed := mini(remaining, available)
		available -= removed
		remaining -= removed
		if available <= 0:
			_entries.remove_at(index)
		else:
			instance["quantity"] = available
		if remaining <= 0:
			break
	return remaining == 0


func quantity(item_key: String) -> int:
	item_key = _normalize_key(item_key)
	var total := 0
	for instance in _entries:
		if str(instance.get("item_key", "")) == item_key:
			total += int(instance.get("quantity", 0))
	return total


func definition(item_key: String) -> Dictionary:
	item_key = _normalize_key(item_key)
	return _item_definitions.get(item_key, {}).duplicate(true)


func _append_loaded_item(item_key: String, amount: int, charges: Variant) -> void:
	if not _item_definitions.has(item_key) or amount <= 0:
		return
	var definition: Dictionary = _item_definitions[item_key]
	var stackable := bool(definition.get("stackable", false))
	var stack_size := maxi(1, int(definition.get("stack_size", 1))) if stackable else 1
	var remaining := amount
	while remaining > 0 and _entries.size() < capacity:
		var quantity_value := mini(remaining, stack_size)
		_entries.append({
			"item_key": item_key,
			"quantity": quantity_value,
			"charges_remaining": charges,
		})
		remaining -= quantity_value


func _normalize_key(item_key: String) -> String:
	return str(_aliases.get(item_key, item_key))