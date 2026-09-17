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
	var default_position := [1.0, 2.0, 3.0]
	assert(game._saved_position_or_default("invalid", default_position) == Vector3(1.0, 2.0, 3.0))
	assert(game._saved_position_or_default([1.0, "invalid", 3.0], default_position) == Vector3(1.0, 2.0, 3.0))
	var popup: MerchantInteractionPopup = preload("res://scripts/merchant_interaction_popup.gd").new()
	popup._ready()
	popup.show_for_merchant("Halas Provisioner")
	assert(popup.merchant_name_label.text == "Halas Provisioner")
	popup.free()
	game.free()
	print("PASS: inventory and faction legacy-save keys migrate to typed references; merchant lookup, popup label, and malformed-position fallback work.")
	quit()
