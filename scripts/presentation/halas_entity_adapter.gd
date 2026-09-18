class_name HalasEntityAdapter
extends RefCounted


static func runtime_entity_id(spawn2_id: int) -> String:
	return "halas:spawn:%d" % spawn2_id


static func neutral_definitions_from_targets(
	targets: Array
) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []

	for target_variant in targets:
		if not target_variant is Dictionary:
			continue

		var target: Dictionary = target_variant
		definitions.append(
			neutral_definition_from_target(
				target
			)
		)

	return definitions

static func neutral_definition_from_target(
	target: Dictionary
) -> Dictionary:
	var spawn2_id := int(
		target.get("spawn2_id", 0)
	)
	var npc_type_id := int(
		target.get("npc_type_id", 0)
	)

	var node_variant: Variant = target.get("node")
	var position := Vector3.ZERO

	if node_variant is Node3D:
		position = (
			node_variant as Node3D
		).global_position

	var class_id := int(
		target.get(
			"class_id",
			target.get("class", 0)
		)
	)

	return {
		"entity_id": runtime_entity_id(spawn2_id),
		"definition_id": "peq:npc:%d" % npc_type_id,
		"kind": "npc",
		"display_name": str(
			target.get(
				"name",
				"Halas NPC"
			)
		),
		"race_id": int(
			target.get("race_id", 0)
		),
		"race_ref": str(
			target.get("race_ref", "")
		),
		"gender_id": int(
			target.get("gender_id", 0)
		),
		"class_id": class_id,
		"class_ref": str(
			target.get("class_ref", "")
		),
		"level": maxi(
			1,
			int(target.get("level", 1))
		),
		"base_stats": {},
		"derived_stats": {},
		"spawn_position": position,
		# PEQ size is retained in appearance.source_size. Do not promote an
		# unreviewed source visual-size value into melee-range gameplay.
		"combat_size": 8.0,
		# Imported PEQ gameplay values remain provenance only. Runtime combat is
		# deliberately disabled until reviewed classic evidence authorizes them.
		"max_health": 1.0,
		"max_mana": 0.0,
		"max_endurance": 0.0,
		"combat_enabled": false,
		"hostile": false,
		"respawn_seconds": -1.0,
		"faction_identity": {
			"npc_faction_ref": str(
				target.get(
					"npc_faction_ref",
					""
				)
			),
			"source_npc_faction_id": int(
				target.get(
					"npc_faction_id",
					0
				)
			),
		},
		"inventory_attachment": _source_inventory_attachment(target),
		"equipment_attachment": _source_equipment_attachment(),
		"controller_attachment": {
			"kind": "halas_population_presentation",
		},
		"appearance": {
			"model_name": str(
				target.get(
					"model_name",
					""
				)
			),
			"texture": int(
				target.get("texture", 0)
			),
			"face": int(
				target.get("face", 0)
			),
			"source_size": float(
				target.get(
					"source_size",
					0.0
				)
			),
		},
		"rewards": {},
		"metadata": _source_metadata(target),
	}


static func neutral_definition_from_source_npc(
	npc_type: Dictionary,
	spawn2_id: int,
	position: Vector3,
	safe_test_override: Dictionary = {}
) -> Dictionary:
	var definition := {
		"entity_id": runtime_entity_id(spawn2_id),
		"definition_id": str(
			npc_type.get(
				"key",
				"peq:npc:%d"
				% int(
					npc_type.get(
						"id",
						0
					)
				)
			)
		),
		"kind": "npc",
		"display_name": str(
			npc_type.get(
				"name",
				"Halas NPC"
			)
		).replace("_", " "),
		"race_id": int(
			npc_type.get("race", 0)
		),
		"race_ref": str(
			npc_type.get(
				"race_ref",
				""
			)
		),
		"gender_id": int(
			npc_type.get("gender", 0)
		),
		"class_id": int(
			npc_type.get("class", 0)
		),
		"class_ref": str(
			npc_type.get(
				"class_ref",
				""
			)
		),
		"level": maxi(
			1,
			int(
				npc_type.get(
					"level",
					1
				)
			)
		),
		"base_stats": {},
		"derived_stats": {},
		"spawn_position": position,
		# PEQ size is retained in appearance.source_size. Do not promote an
		# unreviewed source visual-size value into melee-range gameplay.
		"combat_size": 8.0,
		"max_health": 1.0,
		"max_mana": 0.0,
		"max_endurance": 0.0,
		"combat_enabled": false,
		"hostile": false,
		"respawn_seconds": -1.0,
		"faction_identity": {
			"npc_faction_ref": str(
				npc_type.get(
					"npc_faction_ref",
					""
				)
			),
			"source_npc_faction_id": int(
				npc_type.get(
					"npc_faction_id",
					0
				)
			),
		},
		"inventory_attachment": _source_inventory_attachment(npc_type),
		"equipment_attachment": _source_equipment_attachment(),
		"controller_attachment": {},
		"appearance": {
			"texture": int(
				npc_type.get("texture", 0)
			),
			"face": int(
				npc_type.get("face", 0)
			),
			"source_size": float(
				npc_type.get("size", 0.0)
			),
		},
		"rewards": {},
		"metadata": {
			"source_kind": "peq_halas_npc",
			"source_npc_type_id": int(
				npc_type.get("id", 0)
			),
			"source_level": int(
				npc_type.get("level", 1)
			),
			"source_race_id": int(
				npc_type.get("race", 0)
			),
			"source_gender_id": int(
				npc_type.get("gender", 0)
			),
			"source_class_id": int(
				npc_type.get("class", 0)
			),
			"source_hp": int(
				npc_type.get("hp", 1)
			),
			"source_mana": int(
				npc_type.get("mana", 0)
			),
			"source_review_state": "current_unreviewed_peq",
			"source_combat_enabled": false,
		},
	}

	if safe_test_override.is_empty():
		return definition

	# Foundation-gate tests may supply project-owned safe values to exercise the
	# generic machinery. Never copy source hp/damage/loot into these fields.
	definition["max_health"] = maxf(
		1.0,
		float(
			safe_test_override.get(
				"max_health",
				1.0
			)
		)
	)
	definition["combat_size"] = maxf(
		0.01,
		float(
			safe_test_override.get(
				"combat_size",
				definition["combat_size"]
			)
		)
	)
	definition["combat_enabled"] = bool(
		safe_test_override.get(
			"combat_enabled",
			true
		)
	)
	definition["hostile"] = bool(
		safe_test_override.get(
			"hostile",
			true
		)
	)
	definition["death_delay_seconds"] = maxf(
		0.0,
		float(
			safe_test_override.get(
				"death_delay_seconds",
				0.0
			)
		)
	)
	definition["respawn_seconds"] = float(
		safe_test_override.get(
			"respawn_seconds",
			-1.0
		)
	)
	definition["rewards"] = (
		safe_test_override.get(
			"rewards",
			{}
		).duplicate(true)
		if safe_test_override.get(
			"rewards",
			{}
		) is Dictionary
		else {}
	)

	var metadata: Dictionary = definition["metadata"]
	metadata["architecture_test_override"] = true
	definition["metadata"] = metadata

	return definition


static func _source_inventory_attachment(
	source: Dictionary
) -> Dictionary:
	var merchant_id := int(
		source.get(
			"merchant_id",
			0
		)
	)
	var merchant_ref := str(
		source.get(
			"merchant_ref",
			""
		)
	)

	if (
		merchant_id <= 0
		and merchant_ref.is_empty()
	):
		return {
			"kind": GameplayEntity.ATTACHMENT_SOURCE_INVENTORY_UNREVIEWED,
		}

	return {
		"kind": GameplayEntity.ATTACHMENT_MERCHANT_CATALOG,
		"merchant_id": merchant_id,
		"merchant_ref": merchant_ref,
		"read_only": true,
	}


static func _source_equipment_attachment() -> Dictionary:
	return {
		"kind": GameplayEntity.ATTACHMENT_SOURCE_EQUIPMENT_UNREVIEWED,
	}

static func _source_metadata(
	target: Dictionary
) -> Dictionary:
	return {
		"source_kind": "peq_halas_npc",
		"source_spawn2_id": int(
			target.get("spawn2_id", 0)
		),
		"source_npc_type_id": int(
			target.get("npc_type_id", 0)
		),
		"source_level": int(
			target.get("level", 1)
		),
		"source_race_id": int(
			target.get("race_id", 0)
		),
		"source_gender_id": int(
			target.get("gender_id", 0)
		),
		"source_class_id": int(
			target.get(
				"class_id",
				target.get("class", 0)
			)
		),
		"merchant_id": int(
			target.get("merchant_id", 0)
		),
		"merchant_ref": str(
			target.get("merchant_ref", "")
		),
		"npc_faction_id": int(
			target.get("npc_faction_id", 0)
		),
		"npc_faction_ref": str(
			target.get("npc_faction_ref", "")
		),
		"loottable_id": int(
			target.get("loottable_id", 0)
		),
		"loot_table_ref": str(
			target.get("loot_table_ref", "")
		),
		"source_hp": int(
			target.get("source_hp", 1)
		),
		"source_mana": int(
			target.get("source_mana", 0)
		),
		"source_armor_class": int(
			target.get(
				"source_armor_class",
				0
			)
		),
		"source_min_damage": int(
			target.get(
				"source_min_damage",
				0
			)
		),
		"source_max_damage": int(
			target.get(
				"source_max_damage",
				0
			)
		),
		"source_attack_delay_raw": int(
			target.get(
				"attack_delay_raw",
				0
			)
		),
		"source_review_state": "current_unreviewed_peq",
		"source_combat_enabled": false,
	}
