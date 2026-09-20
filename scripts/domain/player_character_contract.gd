class_name PlayerCharacterContract
extends RefCounted

## Canonical player character visual/combat stature by EQ race identity.

static func size_for_race(race_id: int) -> float:
	match race_id:
		1, 3, 5, 128, 522:
			return 6.0
		2, 130:
			return 7.0
		4, 6:
			return 5.0
		7:
			return 5.5
		8:
			return 4.0
		9:
			return 8.0
		10:
			return 9.0
		11:
			return 3.5
		12:
			return 3.0
		330:
			return 5.0
		_:
			return 0.0
