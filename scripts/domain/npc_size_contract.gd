class_name NpcSizeContract
extends RefCounted

## EQEmu NPC size semantics. Default-height data is supplied by ContentService;
## this contract deliberately never opens a zone or source-data document.

const UNKNOWN_RACE_DEFAULT_SIZE := 6.0
const LAVA_DRAGON_RACE_ID := 49
const LAVA_DRAGON_SIZE := 5.0
const WURM_RACE_ID := 158
const WURM_SIZE := 15.0


static func default_size(default_heights: Dictionary, race_id: int, gender_id: int) -> float:
	var fixed := _fixed_race_size(race_id)
	if fixed > 0.0:
		return fixed
	var entry_variant: Variant = default_heights.get(str(race_id), {})
	if not entry_variant is Dictionary:
		return UNKNOWN_RACE_DEFAULT_SIZE
	var entry := entry_variant as Dictionary
	var gender_key := "female" if gender_id == 1 else "male"
	return maxf(0.01, float(entry.get(gender_key, UNKNOWN_RACE_DEFAULT_SIZE)))


static func effective_size(source_size: float, default_heights: Dictionary, race_id: int, gender_id: int) -> float:
	var fixed := _fixed_race_size(race_id)
	if fixed > 0.0:
		return fixed
	if source_size > 0.0:
		return source_size
	return default_size(default_heights, race_id, gender_id)


static func presentation_scale(raw_height: float, effective_size: float, default_size_value: float, scale_mode: String) -> float:
	assert(raw_height > 0.001, "Presentation model height must be positive")
	assert(effective_size > 0.0, "Effective NPC size must be positive")
	assert(default_size_value > 0.0, "Default NPC size must be positive")
	match scale_mode:
		"normalized_height":
			return effective_size / raw_height
		"native_units":
			return effective_size / default_size_value
		_:
			assert(false, "Unsupported NPC presentation scale mode: %s" % scale_mode)
			return 1.0


static func rendered_height(raw_height: float, visual_scale: float) -> float:
	return raw_height * visual_scale


static func _fixed_race_size(race_id: int) -> float:
	if race_id == LAVA_DRAGON_RACE_ID:
		return LAVA_DRAGON_SIZE
	if race_id == WURM_RACE_ID:
		return WURM_SIZE
	return 0.0
