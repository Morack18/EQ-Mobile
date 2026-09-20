class_name NpcSourceAuthority
extends RefCounted

const GROUPS := {
	"structural_identity": ["name", "lastname", "race", "class", "gender", "level"],
	"appearance": ["texture", "face", "size"],
	"spawn_identity": ["spawn2_id", "spawn_group_id", "candidate_npc_refs", "zone_membership"],
	"position": ["source_position", "source_heading"],
	"patrol": ["grid_membership", "waypoint_coordinates", "waypoint_headings", "waypoint_pauses"],
	"combat_reference": ["hp", "mana", "armor_class", "mindmg", "maxdmg", "attack_speed", "attack_delay", "regen", "aggro_assist_radius"],
	"movement_reference": ["run_speed", "walk_speed"],
	"economy_reference": ["merchant_id", "loottable_id"],
	"faction_reference": ["npc_faction_id"],
}
const LABELS := ["confirmed_p1999", "confirmed_source_behavior", "peq_classic_baseline", "best_available_reference", "unreviewed_peq", "explicit_project_fixture", "confirmed_p1999_classic_scope", "reviewed_mixed_evidence", "source_preserved_with_runtime_model_contract", "best_available_reference_peq", "unreviewed_peq_conflicts_known", "review_deferred"]

static func fields_for(group: String) -> Array:
	assert(GROUPS.has(group), "Unknown NPC source-authority group: %s" % group)
	return (GROUPS[group] as Array).duplicate()

static func valid_label(label: String) -> bool:
	return label in LABELS

static func validate_review(review: Dictionary) -> bool:
	for group in review:
		if not str(group) in ["roster", "identity", "appearance", "patrol", "combat_reference", "movement_reference", "faction_reference", "economy_reference"] or not valid_label(str(review[group])):
			return false
	return str(review.get("combat_reference", "unreviewed_peq")) != "confirmed_p1999"
