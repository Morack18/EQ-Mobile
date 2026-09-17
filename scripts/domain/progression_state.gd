class_name ProgressionState
extends RefCounted

var max_level := 50
var xp_total := 0
var level := 1


func configure(config: Dictionary) -> void:
	max_level = maxi(1, int(config.get("max_level", 50)))
	xp_total = 0
	level = 1


func restore(saved: Dictionary) -> void:
	xp_total = clampi(int(saved.get("xp_total", 0)), 0, xp_cap_total())
	level = level_for_xp(xp_total)


func snapshot() -> Dictionary:
	return {
		"xp_total": xp_total,
		"level": level,
		"max_level": max_level,
	}


func award_xp(amount: int) -> Dictionary:
	if amount <= 0:
		return {
			"awarded": 0,
			"previous_level": level,
			"level": level,
			"xp_total": xp_total,
		}
	var previous_level := level
	var previous_total := xp_total
	xp_total = mini(xp_cap_total(), xp_total + amount)
	level = level_for_xp(xp_total)
	return {
		"awarded": xp_total - previous_total,
		"previous_level": previous_level,
		"level": level,
		"xp_total": xp_total,
	}


func xp_threshold(target_level: int) -> int:
	var hell_modifier := 1.0
	if target_level >= 31 and target_level <= 35:
		hell_modifier = 1.1
	elif target_level >= 36 and target_level <= 40:
		hell_modifier = 1.2
	elif target_level >= 41 and target_level <= 45:
		hell_modifier = 1.3
	elif target_level >= 46 and target_level <= 51:
		hell_modifier = 1.4
	elif target_level == 52:
		hell_modifier = 1.5
	elif target_level == 53:
		hell_modifier = 1.6
	elif target_level == 54:
		hell_modifier = 1.7
	elif target_level == 55:
		hell_modifier = 1.9
	elif target_level == 56:
		hell_modifier = 2.1
	elif target_level == 57:
		hell_modifier = 2.3
	elif target_level == 58:
		hell_modifier = 2.5
	elif target_level == 59:
		hell_modifier = 2.7
	elif target_level == 60:
		hell_modifier = 3.0
	elif target_level >= 61:
		hell_modifier = 3.1
	return int(pow(maxi(0, target_level - 1), 3) * 1000.0 * hell_modifier)


func level_for_xp(total_xp: int) -> int:
	var result := 1
	while result < max_level and total_xp >= xp_threshold(result + 1):
		result += 1
	return result


func xp_cap_total() -> int:
	return xp_threshold(max_level + 1)


func xp_into_level() -> int:
	return xp_total - xp_threshold(level)


func xp_needed_for_next_level() -> int:
	if level >= max_level:
		return 0
	return xp_threshold(level + 1) - xp_threshold(level)