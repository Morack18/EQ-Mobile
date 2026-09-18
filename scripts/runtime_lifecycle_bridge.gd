class_name RuntimeLifecycleBridge
extends Node

var _application_paused := false
var _previous_process_enabled := true
var _previous_physics_process_enabled := true
var _previous_unhandled_input_enabled := true


func _notification(what: int) -> void:
	match what:
		MainLoop.NOTIFICATION_APPLICATION_PAUSED:
			set_simulation_paused(true)
		MainLoop.NOTIFICATION_APPLICATION_RESUMED:
			set_simulation_paused(false)


func set_simulation_paused(paused: bool) -> void:
	if _application_paused == paused:
		return

	var game := get_parent()
	if game == null:
		_application_paused = paused
		return

	var clock_variant: Variant = game.get("simulation_clock")
	var clock := clock_variant as SimulationClock

	if paused:
		_previous_process_enabled = game.is_processing()
		_previous_physics_process_enabled = game.is_physics_processing()
		_previous_unhandled_input_enabled = game.is_processing_unhandled_input()

		_application_paused = true

		if clock != null:
			clock.set_paused(true)

		if game.has_method("_save_game"):
			game.call("_save_game")

		game.set_process(false)
		game.set_physics_process(false)
		game.set_process_unhandled_input(false)
		return

	_application_paused = false

	if clock != null:
		clock.set_paused(false)

	game.set_process(_previous_process_enabled)
	game.set_physics_process(_previous_physics_process_enabled)
	game.set_process_unhandled_input(_previous_unhandled_input_enabled)


func is_simulation_paused() -> bool:
	return _application_paused