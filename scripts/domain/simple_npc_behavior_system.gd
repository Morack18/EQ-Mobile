gdscript
class_name SimpleNpcBehaviorSystem
extends RefCounted

## Generic deterministic chase-and-attack behavior for simple autonomous actors.
## Content supplies the movement/aggro profile and attack profile; combat rules
## remain in Simulation so this behavior cannot award damage, death, loot, or XP.


func update_entity(
	simulation: Simulation,
	actor_id: String,
	target_id: String,
	delta: float,
	context: Dictionary = {}
) -> Dictionary:
	if simulation.is_paused():
		return {"state": "paused"}

	var actor := simulation.entity(actor_id)
	var target := simulation.entity(target_id)

	if (
		actor == null
		or target == null
		or not actor.is_active()
		or not target.is_active()
	):
		return {"state": "inactive"}

	var behavior: Dictionary = actor.metadata.get("behavior", {})
	var attack_profile: Dictionary = actor.metadata.get(
		"combat_profile",
		{}
	)

	if behavior.is_empty() or attack_profile.is_empty():
		return {"state": "idle"}

	var think_interval_seconds := maxf(
		0.0,
		float(
			behavior.get(
				"think_interval_seconds",
				context.get("think_interval_seconds", 0.0)
			)
		)
	)

	if (
		think_interval_seconds > 0.0
		and not simulation.claim_ai_think(
			actor_id,
			think_interval_seconds
		)
	):
		return {
			"state": "waiting",
			"remaining": simulation.ai_think_remaining(actor_id),
		}

	var effective_delta := delta
	if think_interval_seconds > 0.0:
		effective_delta = maxf(
			delta,
			think_interval_seconds
		)

	var offset := target.position - actor.position
	var distance := offset.length()
	var aggro_range := maxf(
		0.0,
		float(behavior.get("aggro_range", 0.0))
	)

	if distance > aggro_range:
		return {"state": "idle"}

	var attack_range := maxf(
		0.0,
		float(attack_profile.get("range", 0.0))
	)

	if distance > attack_range:
		var flat_direction := Vector3(
			offset.x,
			0.0,
			offset.z
		)

		if flat_direction.length_squared() > 0.000001:
			flat_direction = flat_direction.normalized()
			actor.facing = flat_direction
			actor.position += flat_direction * minf(
				distance,
				maxf(
					0.0,
					float(
						behavior.get("move_speed", 0.0)
					)
				) * maxf(0.0, effective_delta)
			)

		return {
			"state": "moving",
			"position": actor.position,
		}

	var cooldown_group := str(
		attack_profile.get("cooldown_group", "")
	)

	if (
		simulation.cooldown_remaining(
			actor_id,
			cooldown_group
		) > 0.0
	):
		return {"state": "cooldown"}

	var result := simulation.request_attack(
		actor_id,
		target_id,
		attack_profile,
		context
	)

	return {
		"state": "attacking",
		"attack": result,
	}