class_name CharacterModelContract
extends RefCounted

## Resolves a character identity and appearance against a zone presentation profile.
## The profile owns model families, asset availability, and orientation conventions.

static func resolve(
	identity: Dictionary,
	appearance: Dictionary,
	presentation_profile: Dictionary
) -> Dictionary:
	var race_id := int(identity.get("race_id", 0))
	var gender_id := int(identity.get("gender_id", 0))
	var texture := int(appearance.get("texture", 0))
	var face := int(appearance.get("face", 0))
	var explicit_model_name := str(appearance.get("model_name", ""))
	if not explicit_model_name.is_empty():
		return {
			"race_id": race_id,
			"gender_id": gender_id,
			"family": "",
			"model_name": explicit_model_name,
			"texture": texture,
			"face": face,
			"skin_count": 1,
			"head_count": 1,
			"default_size": float(presentation_profile.get("default_height", 1.0)),
			"heading_yaw_offset_degrees": 0.0,
		}
	var rules_variant: Variant = presentation_profile.get("model_rules", [])
	if not rules_variant is Array:
		return {}

	for rule_variant in rules_variant as Array:
		if not rule_variant is Dictionary:
			continue
		var rule := rule_variant as Dictionary
		if int(rule.get("race_id", -1)) != race_id:
			continue
		if rule.has("gender_id") and int(rule.get("gender_id", -1)) != gender_id:
			continue

		var skin_count := maxi(1, int(rule.get("skin_count", 1)))
		var head_count := maxi(1, int(rule.get("head_count", 1)))
		var clamped_texture := clampi(texture, 0, skin_count - 1)
		var clamped_face := clampi(face, 0, head_count - 1)
		var family := str(rule.get("family", ""))
		var model_name := str(rule.get("model_name", ""))
		if model_name.is_empty():
			if family.is_empty():
				return {}
			model_name = "%s_s%d_h%d" % [family, clamped_texture, clamped_face]

		var descriptor := rule.duplicate(true)
		descriptor["race_id"] = race_id
		if rule.has("gender_id"):
			descriptor["gender_id"] = gender_id
		descriptor["family"] = family
		descriptor["model_name"] = model_name
		descriptor["texture"] = clamped_texture
		descriptor["face"] = clamped_face
		descriptor["skin_count"] = skin_count
		descriptor["head_count"] = head_count
		descriptor["heading_yaw_offset_degrees"] = float(
			rule.get("heading_yaw_offset_degrees", 0.0)
		)
		return descriptor

	return {}


static func visual_facing_offset_degrees(
	presentation_profile: Dictionary,
	descriptor: Dictionary
) -> float:
	return float(presentation_profile.get("visual_facing_offset_degrees", 0.0)) + float(
		descriptor.get("heading_yaw_offset_degrees", 0.0)
	)
