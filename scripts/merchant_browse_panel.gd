class_name MerchantBrowsePanel
extends Control

signal closed

var selected_name: Label
var selected_price: Label
var merchant_name_label: Label
var rows: VBoxContainer
var selected_row: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.04, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-250, -330)
	panel.size = Vector2(500, 660)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("182129"), Color("aebd9b")))
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(labels)
	var title := Label.new()
	title.text = "MERCHANT"
	title.add_theme_font_size_override("font_size", 24)
	labels.add_child(title)
	merchant_name_label = Label.new()
	merchant_name_label.add_theme_font_size_override("font_size", 18)
	labels.add_child(merchant_name_label)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(54, 54)
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(_close)
	header.add_child(close)
	var columns := HBoxContainer.new()
	content.add_child(columns)
	var item_header := Label.new()
	item_header.text = "ITEM"
	item_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(item_header)
	var price_header := Label.new()
	price_header.text = "BASE PRICE"
	price_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	columns.add_child(price_header)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 365)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	var selected := VBoxContainer.new()
	selected.add_theme_stylebox_override("panel", _panel_style(Color("10171c"), Color("607063")))
	content.add_child(selected)
	selected_name = Label.new()
	selected_name.text = "Select an item"
	selected_name.add_theme_font_size_override("font_size", 19)
	selected.add_child(selected_name)
	selected_price = Label.new()
	selected_price.text = "Base price"
	selected.add_child(selected_price)
	var footer := HBoxContainer.new()
	content.add_child(footer)
	var browse_only := Label.new()
	browse_only.text = "Browse only — transactions unavailable"
	browse_only.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(browse_only)
	var done := Button.new()
	done.text = "CLOSE"
	done.custom_minimum_size = Vector2(118, 48)
	done.pressed.connect(_close)
	footer.add_child(done)

func show_merchant(merchant_name: String, listings: Array) -> void:
	merchant_name_label.text = merchant_name
	for child in rows.get_children():
		child.queue_free()
	selected_row = null
	selected_name.text = "Select an item"
	selected_price.text = "Base price"
	for listing in listings:
		_add_listing(listing)

func _add_listing(listing: Dictionary) -> void:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 54)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = "%s\n%s" % [str(listing.get("item_name", "Unknown item")), _format_price(int(listing.get("base_price", 0)))]
	row.add_theme_font_size_override("font_size", 18)
	row.pressed.connect(func(): _select_listing(row, listing))
	rows.add_child(row)

func _select_listing(row: Button, listing: Dictionary) -> void:
	if selected_row != null:
		selected_row.modulate = Color.WHITE
	selected_row = row
	row.modulate = Color("b9e8bd")
	selected_name.text = str(listing.get("item_name", "Unknown item"))
	selected_price.text = "Base price: %s" % _format_price(int(listing.get("base_price", 0)))

func _format_price(copper: int) -> String:
	var remaining := maxi(0, copper)
	var platinum := remaining / 1000
	remaining %= 1000
	var gold := remaining / 100
	remaining %= 100
	var silver := remaining / 10
	var parts: Array[String] = []
	if platinum > 0: parts.append("%dp" % platinum)
	if gold > 0: parts.append("%dg" % gold)
	if silver > 0: parts.append("%ds" % silver)
	if remaining > 0 or parts.is_empty(): parts.append("%dc" % remaining)
	return " ".join(parts)

func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func _close() -> void:
	closed.emit()
	queue_free()
