extends Control

signal joystick_changed(value: Vector2)
signal look_changed(value: Vector2)
signal attack_requested
signal ability_requested
signal jump_changed(pressed: bool)

var left_touch := -1
var right_touch := -1
var attack_touch := -1
var ability_touch := -1
var jump_touch := -1
var stick_value := Vector2.ZERO
var look_stick_value := Vector2.ZERO
var status_label: Label
var attack_button: Button
var ability_button: Button
var jump_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label = Label.new()
	status_label.position = Vector2(18, 18)
	status_label.size = Vector2(640, 190)
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	attack_button = Button.new()
	attack_button.text = "ATTACK"
	attack_button.add_theme_font_size_override("font_size", 22)
	attack_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Keep the attack target above the fixed right look stick so both controls
	# remain reachable without competing for the same touch area.
	attack_button.position = Vector2(-176, -266)
	attack_button.size = Vector2(150, 88)
	attack_button.pressed.connect(attack_requested.emit)
	add_child(attack_button)
	ability_button = Button.new()
	ability_button.text = "TRAINING\nSTRIKE"
	ability_button.add_theme_font_size_override("font_size", 18)
	ability_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ability_button.position = Vector2(-176, -370)
	ability_button.size = Vector2(150, 88)
	ability_button.pressed.connect(ability_requested.emit)
	add_child(ability_button)
	jump_button = Button.new()
	jump_button.text = "JUMP"
	jump_button.add_theme_font_size_override("font_size", 22)
	jump_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump_button.position = Vector2(-176, -474)
	jump_button.size = Vector2(150, 88)
	jump_button.button_down.connect(func(): jump_changed.emit(true))
	jump_button.button_up.connect(func(): jump_changed.emit(false))
	add_child(jump_button)
	queue_redraw()

func set_status(text: String) -> void:
	status_label.text = text

func set_auto_attack(active: bool) -> void:
	attack_button.text = "ATTACK ON" if active else "ATTACK"
	attack_button.modulate = Color("9dffbd") if active else Color.WHITE

func set_ability(label: String, available: bool, cooldown_remaining: float) -> void:
	ability_button.disabled = not available
	if cooldown_remaining > 0.0:
		ability_button.text = "%s\n%.1fs" % [label, cooldown_remaining]
		ability_button.modulate = Color("a6a6a6")
	else:
		ability_button.text = label
		ability_button.modulate = Color.WHITE if available else Color("a6a6a6")

func handle_touch(index: int, position: Vector2, pressed: bool) -> void:
	if pressed:
		if _attack_rect().has_point(position):
			attack_touch = index
			attack_requested.emit()
		elif _ability_rect().has_point(position):
			ability_touch = index
			ability_requested.emit()
		elif _jump_rect().has_point(position):
			jump_touch = index
			jump_changed.emit(true)
		elif position.x < size.x * 0.46 and position.y > size.y * 0.48:
			left_touch = index
			_update_stick(position)
		elif position.x > size.x * 0.54 and position.y > size.y * 0.48:
			right_touch = index
			_update_look_stick(position)
	else:
		if index == left_touch:
			left_touch = -1
			stick_value = Vector2.ZERO
			joystick_changed.emit(stick_value)
			queue_redraw()
		if index == right_touch:
			right_touch = -1
			look_stick_value = Vector2.ZERO
			look_changed.emit(look_stick_value)
			queue_redraw()
		if index == attack_touch:
			attack_touch = -1
		if index == ability_touch:
			ability_touch = -1
		if index == jump_touch:
			jump_touch = -1
			jump_changed.emit(false)

func handle_drag(index: int, position: Vector2, _relative: Vector2) -> void:
	if index == left_touch:
		_update_stick(position)
	elif index == right_touch:
		_update_look_stick(position)

func _update_stick(position: Vector2) -> void:
	var center := _stick_center()
	stick_value = (position - center).limit_length(68.0) / 68.0
	# Forward screen movement maps to positive local-forward input.
	stick_value.y = -stick_value.y
	joystick_changed.emit(stick_value)
	queue_redraw()


func _update_look_stick(position: Vector2) -> void:
	var center := _look_stick_center()
	look_stick_value = (position - center).limit_length(68.0) / 68.0
	# Up on the right stick means lift the camera; right means turn right.
	look_stick_value.y = -look_stick_value.y
	look_changed.emit(look_stick_value)
	queue_redraw()

func _draw() -> void:
	var center := _stick_center()
	draw_circle(center, 78.0, Color(0.05, 0.12, 0.14, 0.42))
	draw_arc(center, 78.0, 0.0, TAU, 48, Color(0.75, 0.95, 0.85, 0.7), 2.0)
	var knob := center + Vector2(stick_value.x, -stick_value.y) * 56.0
	draw_circle(knob, 29.0, Color(0.35, 0.82, 0.63, 0.7))
	var look_center := _look_stick_center()
	draw_circle(look_center, 78.0, Color(0.10, 0.10, 0.20, 0.45))
	draw_arc(look_center, 78.0, 0.0, TAU, 48, Color(0.65, 0.78, 1.0, 0.75), 2.0)
	var look_knob := look_center + Vector2(look_stick_value.x, -look_stick_value.y) * 56.0
	draw_circle(look_knob, 29.0, Color(0.42, 0.63, 1.0, 0.72))

func _stick_center() -> Vector2:
	return Vector2(112.0, size.y - 122.0)


func _look_stick_center() -> Vector2:
	return Vector2(size.x - 112.0, size.y - 122.0)

func _attack_rect() -> Rect2:
	return Rect2(size.x - 176.0, size.y - 266.0, 150.0, 88.0)


func _jump_rect() -> Rect2:
	return Rect2(size.x - 176.0, size.y - 474.0, 150.0, 88.0)

func _ability_rect() -> Rect2:
	return Rect2(size.x - 176.0, size.y - 370.0, 150.0, 88.0)
