class_name PlayerStartContract
extends RefCounted

static func resolve(selection: Dictionary, source_catalog: Dictionary, overlay: Dictionary) -> Dictionary:
	for candidate in source_catalog.get("start_zones", []):
		if not candidate is Dictionary:
			continue
		var row := candidate as Dictionary
		if int(row.get("player_choice", -1)) != int(selection.get("player_choice", -1)) or int(row.get("player_race", -1)) != int(selection.get("race_id", -1)) or int(row.get("player_class", -1)) != int(selection.get("class_id", -1)) or int(row.get("player_deity", -1)) != int(selection.get("deity_id", -1)):
			continue
		var result := row.duplicate(true)
		result["baseline"] = row.duplicate(true)
		for correction_variant in overlay.get("corrections", []):
			if not correction_variant is Dictionary:
				continue
			var correction := correction_variant as Dictionary
			var match: Dictionary = correction.get("match", {})
			if int(match.get("player_choice", -1)) == int(row.get("player_choice", -2)) and int(match.get("race_id", -1)) == int(row.get("player_race", -2)) and int(match.get("class_id", -1)) == int(row.get("player_class", -2)) and int(match.get("deity_id", -1)) == int(row.get("player_deity", -2)) and int(match.get("start_zone", -1)) == int(row.get("start_zone", -2)):
				for key in ["x", "y", "z", "heading"]:
					if correction.get("override", {}).has(key): result[key] = correction["override"][key]
				result["evidence"] = correction.get("evidence", {})
				break
		result["source_position_eq"] = [float(result.x), float(result.y), float(result.z)]
		result["source_heading_eq"] = float(result.heading)
		result["initial_bind"] = {"zone_id": int(result.start_zone), "source_position_eq": result.source_position_eq, "source_heading_eq": result.source_heading_eq}
		return result
	return {}
