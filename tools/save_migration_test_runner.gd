extends SceneTree

func _init() -> void:
	var game = load("res://scripts/main.gd").new()
	game.item_definitions = game._load_item_definitions()
	var migrated: Array = game._sanitized_inventory([
		{"item_key": "fixture:training_spark_fragment", "quantity": 7, "charges_remaining": null}
	])
	assert(migrated.size() == 1)
	assert(migrated[0]["item_key"] == "fixture:item:training_spark_fragment")
	assert(migrated[0]["quantity"] == 7)
	game.faction_definitions = game._load_faction_definitions()
	var factions: Dictionary = game._sanitized_faction_values({"223": 125, "peq:faction:1159": -25})
	assert(factions["peq:faction:223"] == 125)
	assert(factions["peq:faction:1159"] == -25)
	game.merchant_definitions = game._load_merchant_definitions()
	var merchant_target := {"merchant_ref": "peq:merchant:29000", "merchant_id": 29000}
	assert(not game._merchant_listings_for(merchant_target).is_empty())
	game.free()
	print("PASS: inventory and faction legacy-save keys migrate to typed references; merchant lookup resolves by key.")
	quit()
