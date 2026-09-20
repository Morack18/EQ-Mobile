extends SceneTree
const Authority = preload("res://scripts/domain/npc_source_authority.gd")
var failures: Array[String] = []
func _init() -> void:
	_expect(Authority.fields_for("appearance") == ["texture", "face", "size"], "Authority group lookup failed.")
	_expect(Authority.validate_review({"combat_reference": "unreviewed_peq", "roster": "confirmed_p1999_classic_scope"}), "Generic review contract rejected valid metadata.")
	_expect(not Authority.validate_review({"combat_reference": "confirmed_p1999"}), "Unresolved combat was incorrectly confirmed.")
	var derived := JSON.parse_string(FileAccess.get_file_as_string("res://data/halas_npcs.json")) as Dictionary
	_expect((derived.get("npc_types", []) as Array).size() == 68 and (derived.get("spawns", []) as Array).size() == 68, "Halas source roster cardinality changed.")
	_expect(str(derived.get("review", {}).get("roster", "")) == "confirmed_p1999_classic_scope", "Classic roster review missing from derived data.")
	_expect(str(derived.get("review", {}).get("combat_reference", "")) == "unreviewed_peq_conflicts_known", "Combat reference review changed.")
	if failures.is_empty(): print("PASS: NPC source-authority review contract holds.")
	else: for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
