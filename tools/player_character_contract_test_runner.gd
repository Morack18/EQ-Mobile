extends SceneTree

const PlayerCharacterContractScript = preload("res://scripts/domain/player_character_contract.gd")
const CharacterModelContractScript = preload("res://scripts/presentation/character_model_contract.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_player_race_sizes()
	_test_generic_model_resolution()
	_test_halas_player_fixture_integration()
	if _failures.is_empty():
		print("PASS: Player character size and model contracts hold.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FAIL: Player character contract tests (%d failures)." % _failures.size())
	quit(1)


func _test_player_race_sizes() -> void:
	var expected := {
		1: 6.0, 2: 7.0, 3: 6.0, 4: 5.0, 5: 6.0, 6: 5.0,
		7: 5.5, 8: 4.0, 9: 8.0, 10: 9.0, 11: 3.5, 12: 3.0,
		128: 6.0, 130: 7.0, 330: 5.0, 522: 6.0,
	}
	for race_id_variant in expected:
		var race_id := int(race_id_variant)
		_expect(
			is_equal_approx(PlayerCharacterContractScript.size_for_race(race_id), float(expected[race_id])),
			"Race %d size did not resolve." % race_id
		)
	_expect(is_equal_approx(PlayerCharacterContractScript.size_for_race(2), 7.0), "Barbarian size is not 7.")
	_expect(is_equal_approx(PlayerCharacterContractScript.size_for_race(999), 0.0), "Unsupported race did not resolve to 0.")


func _test_generic_model_resolution() -> void:
	var profile := {
		"visual_facing_offset_degrees": 15.0,
		"model_rules": [
			{"race_id": 71, "gender_id": 1, "family": "synthetic_f", "skin_count": 2, "head_count": 3, "heading_yaw_offset_degrees": 20.0},
			{"race_id": 71, "family": "synthetic_m", "skin_count": 4, "head_count": 2, "heading_yaw_offset_degrees": -10.0},
		],
	}
	var female := CharacterModelContractScript.resolve(
		{"race_id": 71, "gender_id": 1}, {"texture": 8, "face": -1}, profile
	)
	_expect(str(female.get("family", "")) == "synthetic_f", "Gender-specific model rule was not selected.")
	_expect(str(female.get("model_name", "")) == "synthetic_f_s1_h0", "Texture/face were not clamped for family model.")
	_expect(int(female.get("race_id", 0)) == 71 and int(female.get("gender_id", -1)) == 1, "Resolved identity fields are missing.")
	_expect(int(female.get("skin_count", 0)) == 2 and int(female.get("head_count", 0)) == 3, "Resolved family counts are missing.")
	_expect(is_equal_approx(CharacterModelContractScript.visual_facing_offset_degrees(profile, female), 35.0), "Visual-facing offsets did not combine.")
	var male := CharacterModelContractScript.resolve(
		{"race_id": 71, "gender_id": 0}, {"texture": 3, "face": 9}, profile
	)
	_expect(str(male.get("model_name", "")) == "synthetic_m_s3_h1", "Fallback gender model rule did not resolve.")
	_expect(not male.has("gender_id"), "Gender-agnostic model rule exposed a gender match.")


func _test_halas_player_fixture_integration() -> void:
	var zone := _read_json("res://data/halas.json")
	var fixture := _read_json("res://data/player_fixture.json")
	_expect(not fixture.has("combat_size"), "Player fixture still authors combat_size.")
	var appearance: Dictionary = fixture.get("appearance", {})
	_expect(not appearance.has("model_path"), "Player fixture still authors a model path.")
	_expect(not appearance.has("model_name"), "Player fixture still authors a model name.")
	var descriptor := CharacterModelContractScript.resolve(
		fixture.get("identity", {}), appearance, zone.get("npc_presentation", {})
	)
	_expect(str(descriptor.get("model_name", "")) == "bam_s0_h0", "Halas Barbarian player did not resolve bam_s0_h0.")
	_expect(is_equal_approx(CharacterModelContractScript.visual_facing_offset_degrees(zone.get("npc_presentation", {}), descriptor), 90.0), "Halas visual-facing offset did not resolve to +90 degrees.")
	_expect(ResourceLoader.exists("res://assets/imported/halas/characters/bam_s0_h0.glb"), "Required local bam_s0_h0.glb resource is missing.")


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("Unable to read %s." % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_failures.append("Invalid object JSON in %s." % path)
		return {}
	return parsed as Dictionary


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
