gdscript
class_name RuntimeLifecycleBridge
extends Node

var _application_paused := false


func _notification(what: int) -> void:
	match what:
		MainLoop.NOTIFICATION_APPLICATION_PAUSED:
			set_simulation_paused(true)
		MainLoop.NOTIFICATION_APPLICATION_RESUMED:
			set_simulation_paused(false)


func set_simulation_paused(paused: bool) -> void:
	if _application_paused == paused:
		return

	_application_paused = paused

	var game := get_parent()
	if game == null:
		return

	var clock_variant: Variant = game.get(
		"simulation_clock"
	)
	var clock := clock_variant as SimulationClock

	if paused:
		if clock != null:
			clock.set_paused(true)

		if game.has_method("_save_game"):
			game.call("_save_game")

		game.set_process(false)
		game.set_physics_process(false)
		return

	game.set_process(true)
	game.set_physics_process(true)

	if clock != null:
		clock.set_paused(false)


func is_simulation_paused() -> bool:
	return _application_paused