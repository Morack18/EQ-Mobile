class_name ZoneEntityAdapter
extends RefCounted


static func runtime_entity_id(
	spawn2_id: int,
	context: Dictionary = {}
) -> String:
	assert(
		spawn2_id > 0,
		"Zone NPC runtime identity requires a positive spawn2 ID"
	)

	var id_namespace := str(
		context.get(
			"runtime_id_namespace",
			context.get(
				"zone_key",
				"zone"
			)
		)
	)

	if id_namespace.is_empty():
		id_namespace = "zone"

	return "%s:spawn:%d" % [
		id_namespace,
		spawn2_id,
	]


static func neutral_definitions_from_targets(
	targets: Array,
	context: Dictionary = {}
) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []

	for target_variant in targets:
		if not target_variant is Dictionary:
			continue

		definitions.append(
			neutral_definition_from_target(
				target_variant as Dictionary,
				context
			)
		)

	return definitions


static func neutral_definition_from_target(
	target: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	var spawn2_id := int(
		target.get(
			"spawn2_id",
			0
		)
	)
	var npc_type_id := int(
		target.get(
			"npc_type_id",
			0
		)
	)

	var node_variant: Variant = (
		target.get(
			"node"
		)
	)
	var position := Vector3.ZERO

	if node_variant is Node3D:
		var node := (
			node_variant as Node3D
		)

		position = (
			node.global_position
			if node.is_inside_tree()
			else node.position
		)

	var class_id := int(
		target.get(
			"class_id",
			target.get(
				"class",
				0
			)
		)
	)

	var controller_kind := str(
		context.get(
			"controller_kind",
			"zone_population_presentation"
		)
	)

	return {
		"entity_id":
			runtime_entity_id(
				spawn2_id,
				context
			),
		"definition_id":
			str(
				target.get(
					"definition_id",
					"peq:npc:%d"
					% npc_type_id
				)
			),
		"kind":
			"npc",
		"display_name":
			str(
				target.get(
					"name",
					context.get(
						"fallback_display_name",
						"Zone NPC"
					)
				)
			),
		"race_id":
			int(
				target.get(
					"race_id",
					0
				)
			),
		"race_ref":
			str(
				target.get(
					"race_ref",
					""
				)
			),
		"gender_id":
			int(
				target.get(
					"gender_id",
					0
				)
			),
		"class_id":
			class_id,
		"class_ref":
			str(
				target.get(
					"class_ref",
					""
				)
			),
		"level":
			maxi(
				1,
				int(
					target.get(
						"level",
						1
					)
				)
			),
		"base_stats":
			{},
		"derived_stats":
			{},
		"spawn_position":
			position,

		# Imported presentation/source size remains appearance provenance.
		# It is never promoted into gameplay melee range.
		"combat_size":
			8.0,

		# Imported PEQ combat remains disabled until reviewed classic
		# evidence explicitly authorizes gameplay values.
		"max_health":
			1.0,
		"max_mana":
			0.0,
		"max_endurance":
			0.0,
		"combat_enabled":
			false,
		"hostile":
			false,
		"respawn_seconds":
			-1.0,

		"faction_identity": {
			"npc_faction_ref":
				str(
					target.get(
						"npc_faction_ref",
						""
					)
				),
			"source_npc_faction_id":
				int(
					target.get(
						"npc_faction_id",
						0
					)
				),
		},

		"inventory_attachment":
			_source_inventory_attachment(
				target
			),

		"equipment_attachment":
			_source_equipment_attachment(),

		"controller_attachment": {
			"kind":
				controller_kind,
		},

		"appearance": {
			"model_name":
				str(
					target.get(
						"model_name",
						""
					)
				),
			"texture":
				int(
					target.get(
						"texture",
						0
					)
				),
			"face":
				int(
					target.get(
						"face",
						0
					)
				),
			"source_size":
				float(
					target.get(
						"source_size",
						0.0
					)
				),
		},

		"rewards":
			{},

		"metadata":
			_source_metadata(
				target,
				context
			),
	}


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
			"kind":
				GameplayEntity.ATTACHMENT_SOURCE_INVENTORY_UNREVIEWED,
		}

	return {
		"kind":
			GameplayEntity.ATTACHMENT_MERCHANT_CATALOG,
		"merchant_id":
			merchant_id,
		"merchant_ref":
			merchant_ref,
		"read_only":
			true,
	}


static func _source_equipment_attachment() -> Dictionary:
	return {
		"kind":
			GameplayEntity.ATTACHMENT_SOURCE_EQUIPMENT_UNREVIEWED,
	}


static func _source_metadata(
	target: Dictionary,
	context: Dictionary
) -> Dictionary:
	return {
		"source_kind":
			str(
				context.get(
					"source_kind",
					"peq_zone_npc"
				)
			),
		"source_zone_key":
			str(
				context.get(
					"zone_key",
					""
				)
			),
		"source_spawn2_id":
			int(
				target.get(
					"spawn2_id",
					0
				)
			),
		"source_npc_type_id":
			int(
				target.get(
					"npc_type_id",
					0
				)
			),
		"source_level":
			int(
				target.get(
					"level",
					1
				)
			),
		"source_race_id":
			int(
				target.get(
					"race_id",
					0
				)
			),
		"source_gender_id":
			int(
				target.get(
					"gender_id",
					0
				)
			),
		"source_class_id":
			int(
				target.get(
					"class_id",
					target.get(
						"class",
						0
					)
				)
			),
		"merchant_id":
			int(
				target.get(
					"merchant_id",
					0
				)
			),
		"merchant_ref":
			str(
				target.get(
					"merchant_ref",
					""
				)
			),
		"npc_faction_id":
			int(
				target.get(
					"npc_faction_id",
					0
				)
			),
		"npc_faction_ref":
			str(
				target.get(
					"npc_faction_ref",
					""
				)
			),
		"loottable_id":
			int(
				target.get(
					"loottable_id",
					0
				)
			),
		"loot_table_ref":
			str(
				target.get(
					"loot_table_ref",
					""
				)
			),
		"source_hp":
			int(
				target.get(
					"source_hp",
					1
				)
			),
		"source_mana":
			int(
				target.get(
					"source_mana",
					0
				)
			),
		"source_armor_class":
			int(
				target.get(
					"source_armor_class",
					0
				)
			),
		"source_min_damage":
			int(
				target.get(
					"source_min_damage",
					0
				)
			),
		"source_max_damage":
			int(
				target.get(
					"source_max_damage",
					0
				)
			),
		"source_attack_delay_raw":
			int(
				target.get(
					"attack_delay_raw",
					0
				)
			),
		"source_review_state":
			"current_unreviewed_peq",
		"source_combat_enabled":
			false,
	}
