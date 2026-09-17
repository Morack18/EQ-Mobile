class_name MerchantInteractionPopup
extends Control

signal trade_requested
signal closed

var merchant_name_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.04, 0.58)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-170, -116)
	panel.size = Vector2(340, 232)
	panel.add_theme_stylebox_override("panel", _style())
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	merchant_name_label = Label.new()
	merchant_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	merchant_name_label.add_theme_font_size_override("font_size", 22)
	content.add_child(merchant_name_label)
	var prompt := Label.new()
	prompt.text = "What would you like to do?"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(prompt)
	var trade := Button.new()
	trade.text = "TRADE"
	trade.custom_minimum_size = Vector2(0, 58)
	trade.add_theme_font_size_override("font_size", 21)
	trade.pressed.connect(func(): trade_requested.emit())
	content.add_child(trade)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(0, 46)
	cancel.pressed.connect(_close)
	content.add_child(cancel)

func show_for_merchant(merchant_name: String) -> void:
	merchant_name_label.text = merchant_name

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182129")
	style.border_color = Color("aebd9b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style

func _close() -> void:
	closed.emit()
	queue_free()
