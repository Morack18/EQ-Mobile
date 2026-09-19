class_name ContentService
extends RefCounted

var _paths: Dictionary = {}
var _documents: Dictionary = {}
var _item_definitions: Dictionary = {}
var _merchant_catalog: Dictionary = {}
var _faction_catalog: Dictionary = {}
var last_error := ""


func configure(paths: Dictionary) -> void:
	_paths = paths.duplicate(true)
	_documents.clear()
	_item_definitions.clear()
	_merchant_catalog.clear()
	_faction_catalog.clear()
	last_error = ""


func configured_paths() -> Dictionary:
	return _paths.duplicate(
		true
	)


func load_all() -> bool:
	for key in _paths:
		var path := str(_paths[key])
		var document: Variant = _read_json(path)
		if document == null:
			return false
		_documents[str(key)] = document
	if not _build_item_catalog():
		return false
	if not _build_merchant_catalog():
		return false
	if not _build_faction_catalog():
		return false
	if not _validate_references():
		return false
	return true


func zone_definition(expected_key: String = "") -> Dictionary:
	var zone: Dictionary = _documents.get("zone", {})
	assert(not zone.is_empty(), "Zone content has not been loaded")
	if not expected_key.is_empty():
		assert(str(zone.get("key", "")) == expected_key, "Loaded zone key does not match %s" % expected_key)
	return zone.duplicate(true)


func player_fixture_definition() -> Dictionary:
	var definition: Dictionary = _documents.get("player_fixture", {})
	assert(not definition.is_empty(), "Player fixture content has not been loaded")
	return definition.duplicate(true)


func player_class_catalog() -> Dictionary:
	var catalog: Dictionary = _documents.get("player_classes", {})
	assert(catalog.get("classes") is Dictionary and catalog.get("abilities") is Dictionary, "Invalid player class catalog")
	return catalog.duplicate(true)


func npc_dataset() -> Dictionary:
	var dataset: Dictionary = _documents.get("npcs", {})
	return dataset.duplicate(true)


func world_object_dataset() -> Dictionary:
	var document: Dictionary = _documents.get(
		"world_objects",
		{}
	)
	return document.duplicate(true)


func transition_dataset() -> Dictionary:
	var document: Dictionary = _documents.get(
		"transitions",
		{}
	)
	return document.duplicate(true)


func item_definitions() -> Dictionary:
	return _item_definitions.duplicate(true)


func item_definition(item_key: String) -> Dictionary:
	var definition: Dictionary = _item_definitions.get(item_key, {})
	assert(not definition.is_empty(), "Missing item definition: %s" % item_key)
	return definition.duplicate(true)


func faction_catalog() -> Dictionary:
	return _faction_catalog.duplicate(true)


func merchant_listings(merchant_ref: String, merchant_id: int = 0) -> Array:
	var listings: Array = []
	if not merchant_ref.is_empty():
		listings = _merchant_catalog.get("by_key", {}).get(merchant_ref, [])
	elif merchant_id > 0:
		listings = _merchant_catalog.get("by_id", {}).get(str(merchant_id), [])
	var resolved: Array = []
	for listing_variant in listings:
		assert(listing_variant is Dictionary, "Merchant listing must be a Dictionary")
		var listing: Dictionary = listing_variant
		var item_ref := str(listing.get("item_ref", ""))
		assert(_item_definitions.has(item_ref), "Merchant listing has unresolved item ref: %s" % item_ref)
		var item_definition: Dictionary = _item_definitions[item_ref]
		var entry: Dictionary = listing.duplicate(true)
		entry["item_name"] = item_definition.get("name", entry.get("item_name", "Unknown item"))
		entry["base_price"] = int(item_definition.get("price_copper", entry.get("base_price", 0)))
		resolved.append(entry)
	return resolved


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Unable to read required content: %s" % path)
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _fail("Invalid JSON content document: %s" % path)
	return parsed


func _build_item_catalog() -> bool:
	_item_definitions.clear()
	for document_key in ["items", "peq_items"]:
		if not _documents.has(document_key):
			continue
		var document: Dictionary = _documents.get(document_key, {})
		var items = document.get("items")
		if not items is Dictionary:
			_fail("Content document %s has no item dictionary" % document_key)
			return false
		for source_id in items:
			var definition: Dictionary = items[source_id]
			var item_key := str(definition.get("key", source_id))
			if item_key.is_empty() or _item_definitions.has(item_key):
				_fail("Duplicate or empty item definition key: %s" % item_key)
				return false
			_item_definitions[item_key] = definition.duplicate(true)
	return true


func _build_merchant_catalog() -> bool:
	if not _documents.has("merchants"):
		_merchant_catalog = {
			"by_id": {},
			"by_key": {},
		}
		return true

	var document: Dictionary = _documents.get("merchants", {})
	var merchants = document.get("merchants")
	if not merchants is Dictionary:
		_fail("Merchant content has no merchants dictionary")
		return false
	var by_key: Dictionary = {}
	for merchant_id in merchants:
		var listings: Array = merchants[merchant_id]
		if listings.is_empty():
			continue
		var merchant_ref := str(listings[0].get("merchant_ref", "peq:merchant:%s" % merchant_id))
		if by_key.has(merchant_ref):
			_fail("Duplicate merchant definition key: %s" % merchant_ref)
			return false
		by_key[merchant_ref] = listings
	_merchant_catalog = {
		"by_id": merchants.duplicate(true),
		"by_key": by_key,
	}
	return true


func _build_faction_catalog() -> bool:
	if not _documents.has("factions"):
		_faction_catalog = {
			"factions": {},
			"npc_faction_bundles": {},
			"factions_by_key": {},
			"npc_faction_bundles_by_key": {},
		}
		return true

	var document: Dictionary = _documents.get("factions", {})
	var factions = document.get("factions")
	var bundles = document.get("npc_faction_bundles")
	if not factions is Dictionary or not bundles is Dictionary:
		_fail("Faction content is missing faction definitions or NPC faction bundles")
		return false
	var factions_by_key: Dictionary = {}
	for faction_id in factions:
		var definition: Dictionary = factions[faction_id]
		var faction_key := str(definition.get("key", "peq:faction:%s" % faction_id))
		if factions_by_key.has(faction_key):
			_fail("Duplicate faction definition key: %s" % faction_key)
			return false
		factions_by_key[faction_key] = definition.duplicate(true)
	var bundles_by_key: Dictionary = {}
	for bundle_id in bundles:
		var bundle: Dictionary = bundles[bundle_id]
		var bundle_key := str(bundle.get("key", "peq:npc_faction:%s" % bundle_id))
		if bundles_by_key.has(bundle_key):
			_fail("Duplicate NPC faction bundle key: %s" % bundle_key)
			return false
		bundles_by_key[bundle_key] = bundle.duplicate(true)
	_faction_catalog = document.duplicate(true)
	_faction_catalog["factions_by_key"] = factions_by_key
	_faction_catalog["npc_faction_bundles_by_key"] = bundles_by_key
	return true


func _validate_references() -> bool:
	for merchant_id in _merchant_catalog.get("by_id", {}):
		for listing_variant in _merchant_catalog.get("by_id", {})[merchant_id]:
			if not listing_variant is Dictionary:
				_fail("Merchant %s contains a non-dictionary listing" % merchant_id)
				return false
			var item_ref := str(listing_variant.get("item_ref", ""))
			if item_ref.is_empty() or not _item_definitions.has(item_ref):
				_fail("Merchant %s has unresolved item reference: %s" % [merchant_id, item_ref])
				return false
	for bundle_key in _faction_catalog.get("npc_faction_bundles_by_key", {}):
		var bundle: Dictionary = _faction_catalog["npc_faction_bundles_by_key"][bundle_key]
		var primary_ref := str(bundle.get("primary_faction_ref", ""))
		if not primary_ref.is_empty() and not _faction_catalog.get("factions_by_key", {}).has(primary_ref):
			_fail("NPC faction bundle %s has unresolved primary faction: %s" % [bundle_key, primary_ref])
			return false
	var npc_document: Dictionary = _documents.get("npcs", {})
	var npc_keys: Dictionary = {}
	for npc_variant in npc_document.get("npc_types", []):
		if not npc_variant is Dictionary:
			_fail("NPC dataset contains a non-dictionary npc_type")
			return false
		var npc_key := str(npc_variant.get("key", "peq:npc:%d" % int(npc_variant.get("id", 0))))
		if npc_key.is_empty() or npc_keys.has(npc_key):
			_fail("Duplicate or empty NPC definition key: %s" % npc_key)
			return false
		npc_keys[npc_key] = true
	var spawn_groups: Dictionary = npc_document.get("spawn_groups", {})
	var spawn_group_keys: Dictionary = {}
	for group_id in spawn_groups:
		var group: Dictionary = spawn_groups[group_id]
		var group_key := str(group.get("key", "peq:spawn_group:%s" % group_id))
		if group_key.is_empty() or spawn_group_keys.has(group_key):
			_fail("Duplicate or empty spawn-group key: %s" % group_key)
			return false
		spawn_group_keys[group_key] = true
		for candidate_variant in group.get("candidates", []):
			if not candidate_variant is Dictionary:
				_fail("Spawn group %s contains a non-dictionary candidate" % group_key)
				return false
			var npc_ref := str(candidate_variant.get("npc_ref", "peq:npc:%d" % int(candidate_variant.get("npc_type_id", 0))))
			if not npc_keys.has(npc_ref):
				_fail("Spawn group %s has unresolved NPC reference: %s" % [group_key, npc_ref])
				return false
	for spawn_variant in npc_document.get("spawns", []):
		if not spawn_variant is Dictionary:
			_fail("NPC dataset contains a non-dictionary spawn")
			return false
		var group_ref := str(spawn_variant.get("spawn_group_ref", "peq:spawn_group:%d" % int(spawn_variant.get("spawn_group_id", 0))))
		if not spawn_group_keys.has(group_ref):
			_fail("Spawn %s has unresolved spawn-group reference: %s" % [str(spawn_variant.get("key", spawn_variant.get("spawn2_id", "?"))), group_ref])
			return false
	return true


func _fail(message: String) -> Variant:
	last_error = message
	push_error(message)
	return null