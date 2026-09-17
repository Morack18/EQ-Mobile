class_name FactionSystem
extends RefCounted

var _definitions: Dictionary = {}
var _identity: Dictionary = {}
var _values: Dictionary = {}


func configure(definitions: Dictionary, identity: Dictionary) -> void:
	_definitions = definitions.duplicate(true)
	_identity = identity.duplicate(true)
	_values.clear()


func set_identity(identity: Dictionary) -> void:
	_identity = identity.duplicate(true)


func values_snapshot() -> Dictionary:
	return _values.duplicate(true)


func restore(saved_values: Variant) -> void:
	_values.clear()
	if not saved_values is Dictionary:
		return
	for raw_key in saved_values:
		var faction_ref := _normalize_faction_ref(str(raw_key))
		var definition: Dictionary = _definitions.get("factions_by_key", {}).get(faction_ref, {})
		if definition.is_empty():
			continue
		_values[faction_ref] = clampi(
			int(saved_values[raw_key]),
			int(definition.get("personal_min", -2000)),
			int(definition.get("personal_max", 2000))
		)


func change_value(faction_ref: String, delta: int) -> Dictionary:
	faction_ref = _normalize_faction_ref(faction_ref)
	var definition: Dictionary = _definitions.get("factions_by_key", {}).get(faction_ref, {})
	if definition.is_empty():
		return {"changed": false, "faction_ref": faction_ref}
	var previous := int(_values.get(faction_ref, 0))
	var current := clampi(
		previous + delta,
		int(definition.get("personal_min", -2000)),
		int(definition.get("personal_max", 2000))
	)
	_values[faction_ref] = current
	return {
		"changed": current != previous,
		"faction_ref": faction_ref,
		"previous": previous,
		"current": current,
		"delta": current - previous,
	}


func reaction_for_npc_bundle(bundle_ref: String) -> Dictionary:
	if bundle_ref.is_empty():
		return {"standing": "Indifferently", "score": 0, "primary_faction_ref": ""}
	var bundle: Dictionary = _definitions.get("npc_faction_bundles_by_key", {}).get(bundle_ref, {})
	var primary_ref := str(bundle.get("primary_faction_ref", ""))
	if primary_ref.is_empty():
		return {"standing": "Indifferently", "score": 0, "primary_faction_ref": ""}
	var faction: Dictionary = _definitions.get("factions_by_key", {}).get(primary_ref, {})
	if faction.is_empty():
		return {"standing": "Unresolved", "score": null, "primary_faction_ref": primary_ref}
	var score := int(_values.get(primary_ref, 0)) + int(faction.get("base", 0))
	for modifier in faction.get("modifiers", []):
		var kind := str(modifier.get("kind", ""))
		var identity_id := -1
		if kind == "class":
			identity_id = int(_identity.get("class_id", -1))
		elif kind == "race":
			identity_id = int(_identity.get("race_id", -1))
		elif kind == "deity":
			identity_id = int(_identity.get("deity_id", -1))
		if int(modifier.get("identity_id", -2)) == identity_id:
			score += int(modifier.get("value", 0))
	return {
		"standing": standing_for_score(score),
		"score": score,
		"primary_faction_ref": primary_ref,
	}


func standing_for_score(score: int) -> String:
	var thresholds: Dictionary = _definitions.get("thresholds", {})
	if score >= int(thresholds.get("ally", 1100)):
		return "Ally"
	if score >= int(thresholds.get("warmly", 750)):
		return "Warmly"
	if score >= int(thresholds.get("kindly", 500)):
		return "Kindly"
	if score >= int(thresholds.get("amiably", 100)):
		return "Amiably"
	if score >= int(thresholds.get("indifferently", 0)):
		return "Indifferently"
	if score >= int(thresholds.get("apprehensively", -100)):
		return "Apprehensively"
	if score >= int(thresholds.get("dubiously", -500)):
		return "Dubiously"
	if score >= int(thresholds.get("threateningly", -750)):
		return "Threateningly"
	return "Scowls"


func _normalize_faction_ref(value: String) -> String:
	if value.begins_with("peq:faction:"):
		return value
	if value.is_valid_int():
		return "peq:faction:%d" % int(value)
	return value