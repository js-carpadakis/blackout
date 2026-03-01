extends Control
## Pre-game setup menu for assigning stagehands to props and wing sections

const PROP_DEFS: Array[Dictionary] = [
	{ "name": "Chair", "weight": 1, "color": Color.SADDLE_BROWN, "shape": 0, "size": Vector2(45, 45), "traits": [] },
	{ "name": "Stool", "weight": 1, "color": Color.NAVY_BLUE, "shape": 1, "size": Vector2(42, 42), "traits": [] },
	{ "name": "Lamp", "weight": 1, "color": Color.GOLDENROD, "shape": 0, "size": Vector2(30, 60), "traits": [0] },
	{ "name": "Table", "weight": 2, "color": Color.BURLYWOOD, "shape": 1, "size": Vector2(75, 75), "traits": [] },
	{ "name": "Couch", "weight": 2, "color": Color.FOREST_GREEN, "shape": 0, "size": Vector2(105, 52), "traits": [2] },
	{ "name": "Dresser", "weight": 2, "color": Color.ANTIQUE_WHITE, "shape": 0, "size": Vector2(82, 60), "traits": [2] },
	{ "name": "Rug", "weight": 2, "color": Color.CRIMSON, "shape": 0, "size": Vector2(120, 22), "traits": [] },
	{ "name": "Piano", "weight": 3, "color": Color.DARK_RED, "shape": 2, "size": Vector2(105, 82), "traits": [0] },
	{ "name": "Bookshelf", "weight": 3, "color": Color.PURPLE, "shape": 0, "size": Vector2(52, 105), "traits": [] },
	{ "name": "Wardrobe", "weight": 3, "color": Color.DARK_OLIVE_GREEN, "shape": 0, "size": Vector2(75, 98), "traits": [1] },
	{ "name": "Statue", "weight": 2, "color": Color.SLATE_GRAY, "shape": 1, "size": Vector2(52, 52), "traits": [0, 1] },
	{ "name": "Bed", "weight": 3, "color": Color.MEDIUM_PURPLE, "shape": 0, "size": Vector2(112, 82), "traits": [2] },
]

const SCRIM_DEFS: Array[Dictionary] = [
	{ "name": "Black Scrim", "weight": 1, "color": Color(0.1, 0.1, 0.1, 0.7), "shape": 0, "size": Vector2(60, 8), "traits": [3] },
	{ "name": "White Drop", "weight": 1, "color": Color(0.9, 0.9, 0.85), "shape": 0, "size": Vector2(60, 8), "traits": [3] },
	{ "name": "Forest Drop", "weight": 2, "color": Color.DARK_GREEN, "shape": 0, "size": Vector2(60, 8), "traits": [3] },
]

const STAGEHAND_DEFS: Array[Dictionary] = [
	{ "type": "rookie", "name": "Rookie A", "color": Color.LIGHT_BLUE, "strength": 1, "speed": "Fast" },
	{ "type": "regular", "name": "Regular A", "color": Color.BLUE, "strength": 2, "speed": "Med" },
	{ "type": "strong", "name": "Strong A", "color": Color.DARK_BLUE, "strength": 3, "speed": "Slow" },
	{ "type": "rookie", "name": "Rookie B", "color": Color.LIGHT_CORAL, "strength": 1, "speed": "Fast" },
	{ "type": "regular", "name": "Regular B", "color": Color.CORAL, "strength": 2, "speed": "Med" },
	{ "type": "strong", "name": "Strong B", "color": Color.DARK_RED, "strength": 3, "speed": "Slow" },
]

const WING_LABELS: Array[String] = ["L1", "L2", "L3", "L4", "R1", "R2", "R3", "R4"]
const TRAIT_NAMES: Array[String] = ["Fragile", "Tall", "Wheeled", "Scrim"]

@onready var assignment_list: VBoxContainer = $HBoxContainer/SidePanel/MarginContainer/VBoxContainer/ScrollContainer/AssignmentList
@onready var stagehand_pool: VBoxContainer = $HBoxContainer/SidePanel/MarginContainer/VBoxContainer/StagehandPool
@onready var start_button: Button = $HBoxContainer/SidePanel/MarginContainer/VBoxContainer/StartButton
@onready var wing_preview: Control = $HBoxContainer/WingPreview

var _selected_props: Array[Dictionary] = []
# _crew_toggles[prop_index][stagehand_index] = Button
var _crew_toggles: Array[Array] = []
var _wing_buttons: Array[OptionButton] = []


func _ready() -> void:
	# Pick 5 random regular props
	var all_props := PROP_DEFS.duplicate()
	all_props.shuffle()
	for i in range(5):
		_selected_props.append(all_props[i])
	# Pick 1 random scrim (always included, separate from prop pool)
	var all_scrims := SCRIM_DEFS.duplicate()
	all_scrims.shuffle()
	_selected_props.append(all_scrims[0])

	_build_stagehand_pool()
	_build_assignment_cards()
	_update_preview()

	start_button.pressed.connect(_on_start_pressed)


func _build_stagehand_pool() -> void:
	for def in STAGEHAND_DEFS:
		var hbox := HBoxContainer.new()

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.color = def.color
		hbox.add_child(swatch)

		var label := Label.new()
		label.text = "  %s  (Str %d, %s)" % [def.name, def.strength, def.speed]
		label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(label)

		stagehand_pool.add_child(hbox)


func _build_assignment_cards() -> void:
	_crew_toggles.clear()
	_wing_buttons.clear()

	var scrim_header_added := false
	for i in range(_selected_props.size()):
		var def: Dictionary = _selected_props[i]

		# Insert a section header before the first scrim
		if def.traits.has(3) and not scrim_header_added:
			scrim_header_added = true
			var section_sep := HSeparator.new()
			assignment_list.add_child(section_sep)
			var section_label := Label.new()
			section_label.text = "Scrims"
			section_label.add_theme_font_size_override("font_size", 13)
			section_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			assignment_list.add_child(section_label)

		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)

		# Header with prop color swatch and info
		var header := HBoxContainer.new()

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.color = def.color
		header.add_child(swatch)

		var trait_str := ""
		if def.traits.size() > 0:
			var trait_labels: Array[String] = []
			for t in def.traits:
				if t < TRAIT_NAMES.size():
					trait_labels.append(TRAIT_NAMES[t])
			trait_str = " [%s]" % ", ".join(trait_labels)

		var name_label := Label.new()
		name_label.text = "  %s  (wt %d)%s" % [def.name, def.weight, trait_str]
		name_label.add_theme_font_size_override("font_size", 14)
		header.add_child(name_label)
		card.add_child(header)

		# Crew toggle buttons row
		var crew_row := HBoxContainer.new()
		crew_row.add_theme_constant_override("separation", 3)
		var crew_label := Label.new()
		crew_label.text = "  Crew: "
		crew_label.add_theme_font_size_override("font_size", 13)
		crew_row.add_child(crew_label)

		var prop_toggles: Array = []
		for sh_i in range(STAGEHAND_DEFS.size()):
			var sh: Dictionary = STAGEHAND_DEFS[sh_i]
			var btn := Button.new()
			btn.text = sh.name.substr(0, 3)  # "Roo", "Reg", "Str"
			btn.toggle_mode = true
			btn.custom_minimum_size = Vector2(36, 24)
			btn.add_theme_font_size_override("font_size", 10)
			btn.toggled.connect(_on_crew_toggled.bind(i, sh_i))
			_apply_toggle_style(btn, sh.color, false)
			crew_row.add_child(btn)
			prop_toggles.append(btn)

		_crew_toggles.append(prop_toggles)
		card.add_child(crew_row)

		# Wing dropdown
		var wing_row := HBoxContainer.new()
		var wing_label := Label.new()
		wing_label.text = "  Wing: "
		wing_label.add_theme_font_size_override("font_size", 13)
		wing_row.add_child(wing_label)

		var wing_btn := OptionButton.new()
		wing_btn.custom_minimum_size.x = 140
		wing_btn.add_theme_font_size_override("font_size", 13)
		wing_btn.add_item("-- Select --", 100)
		for w in range(WING_LABELS.size()):
			wing_btn.add_item(WING_LABELS[w], w)
		wing_btn.item_selected.connect(_on_wing_changed.bind(i))
		_wing_buttons.append(wing_btn)
		wing_row.add_child(wing_btn)
		card.add_child(wing_row)

		# Separator
		var sep := HSeparator.new()
		card.add_child(sep)

		assignment_list.add_child(card)


func _apply_toggle_style(btn: Button, color: Color, pressed: bool) -> void:
	var style := StyleBoxFlat.new()
	if pressed:
		style.bg_color = color
	else:
		style.bg_color = Color(0.2, 0.2, 0.2)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", style)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = color
	pressed_style.corner_radius_top_left = 3
	pressed_style.corner_radius_top_right = 3
	pressed_style.corner_radius_bottom_left = 3
	pressed_style.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = color.lightened(0.3) if pressed else Color(0.3, 0.3, 0.3)
	hover_style.corner_radius_top_left = 3
	hover_style.corner_radius_top_right = 3
	hover_style.corner_radius_bottom_left = 3
	hover_style.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("hover", hover_style)


func _on_crew_toggled(is_pressed: bool, prop_index: int, stagehand_index: int) -> void:
	if is_pressed:
		# Exclusive: un-toggle this stagehand from any other prop
		for p in range(_crew_toggles.size()):
			if p != prop_index:
				var other_btn: Button = _crew_toggles[p][stagehand_index]
				if other_btn.button_pressed:
					other_btn.set_pressed_no_signal(false)
					_apply_toggle_style(other_btn, STAGEHAND_DEFS[stagehand_index].color, false)

	# Update style for the toggled button
	var btn: Button = _crew_toggles[prop_index][stagehand_index]
	_apply_toggle_style(btn, STAGEHAND_DEFS[stagehand_index].color, is_pressed)

	_update_preview()


func _on_wing_changed(_item_index: int, _card_index: int) -> void:
	_update_preview()


func _get_crew_for_prop(prop_index: int) -> Array[int]:
	var result: Array[int] = []
	for sh_i in range(STAGEHAND_DEFS.size()):
		if _crew_toggles[prop_index][sh_i].button_pressed:
			result.append(sh_i)
	return result


func _get_wing_for_prop(prop_index: int) -> int:
	var wing_btn: OptionButton = _wing_buttons[prop_index]
	if wing_btn.selected >= 0 and wing_btn.selected < wing_btn.item_count:
		var id: int = wing_btn.get_item_id(wing_btn.selected)
		if id < WING_LABELS.size():
			return id
	return -1


func _get_assignments() -> Array:
	var result: Array = []
	for i in range(_selected_props.size()):
		var wing: int = _get_wing_for_prop(i)
		if wing < 0:
			continue
		var crew: Array[int] = _get_crew_for_prop(i)
		var stagehand_colors: Array[Color] = []
		for sh_i in crew:
			stagehand_colors.append(STAGEHAND_DEFS[sh_i].color)
		result.append({
			"prop_index": i,
			"prop_color": _selected_props[i].color,
			"wing_section": wing,
			"stagehand_colors": stagehand_colors,
		})
	return result


func _update_preview() -> void:
	wing_preview.set_data(_selected_props, STAGEHAND_DEFS, _get_assignments())


func _on_start_pressed() -> void:
	var assignments: Array = []
	for i in range(_selected_props.size()):
		var wing: int = _get_wing_for_prop(i)
		if wing < 0:
			continue  # No wing selected — skip this prop entirely

		var crew_indices: Array[int] = _get_crew_for_prop(i)
		var crew: Array[Dictionary] = []
		for sh_i in crew_indices:
			crew.append({
				"type": STAGEHAND_DEFS[sh_i].type,
				"color": STAGEHAND_DEFS[sh_i].color,
			})

		assignments.append({
			"prop_def": _selected_props[i],
			"wing_section": wing,
			"crew": crew,
		})

	GameManager.setup_config = { "assignments": assignments }
	get_tree().change_scene_to_file("res://scenes/main/game_session.tscn")
