extends CanvasLayer
## HUD for planning phase: shows current phase and prop movement plans

signal score_dismissed

@onready var phase_label: Label = $PhaseLabel
@onready var task_list: VBoxContainer = $TaskPanel/TaskList

var _countdown_label: Label = null
var _score_panel: Panel = null
var _score_content: VBoxContainer = null


func _ready() -> void:
	set_phase("PLANNING")
	_build_countdown_label()
	_build_score_panel()


func _build_countdown_label() -> void:
	_countdown_label = Label.new()
	_countdown_label.add_theme_font_size_override("font_size", 22)
	_countdown_label.visible = false
	add_child(_countdown_label)


func _build_score_panel() -> void:
	_score_panel = Panel.new()
	_score_panel.size = Vector2(360, 0)  # height grows with content
	_score_panel.visible = false
	add_child(_score_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_score_panel.add_child(margin)

	_score_content = VBoxContainer.new()
	_score_content.add_theme_constant_override("separation", 6)
	margin.add_child(_score_content)


func set_phase(phase_name: String) -> void:
	phase_label.text = phase_name
	if phase_name == "PLANNING" and _countdown_label:
		_countdown_label.visible = false


func show_countdown(remaining: float) -> void:
	if not _countdown_label:
		return
	_countdown_label.visible = true
	_countdown_label.text = "%.1fs" % remaining
	_countdown_label.add_theme_color_override("font_color",
		Color.RED if remaining < 5.0 else Color.YELLOW)
	# Position just below the phase label
	_countdown_label.position = Vector2(
		phase_label.position.x,
		phase_label.position.y + phase_label.size.y + 4)


func show_score(score: Dictionary) -> void:
	if not _score_panel:
		return
	for child in _score_content.get_children():
		child.queue_free()

	_add_score_label("LIGHTS UP", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_score_content.add_child(HSeparator.new())

	var pp: int = score.props_placed
	var pt: int = score.props_total
	var acc_color := Color.GREEN if pp == pt else (Color.YELLOW if pp * 2 >= pt else Color.RED)
	_add_score_label("Props in position: %d / %d" % [pp, pt], 14, acc_color)

	_score_content.add_child(HSeparator.new())
	_add_score_label("Crew:", 14, Color.WHITE)

	for sh_data in score.stagehand_data:
		var penalty: float = sh_data.penalty
		var sh_label: String
		var sh_color: Color
		if penalty < 0.05:
			sh_label = "  %s — clear" % sh_data.name
			sh_color = Color.GREEN
		else:
			sh_label = "  %s — spotted (%d%% exposed)" % [sh_data.name, int(penalty * 100)]
			sh_color = Color.RED if penalty > 0.5 else Color.YELLOW
		_add_score_label(sh_label, 13, sh_color)

	_score_content.add_child(HSeparator.new())
	var dismiss_btn := Button.new()
	dismiss_btn.text = "Dismiss"
	dismiss_btn.add_theme_font_size_override("font_size", 13)
	dismiss_btn.pressed.connect(func():
		hide_score()
		score_dismissed.emit())
	_score_content.add_child(dismiss_btn)

	# Size and center the panel on screen
	await get_tree().process_frame  # let VBox measure itself
	_score_panel.size.y = _score_content.get_combined_minimum_size().y + 24
	var vp := get_viewport().get_visible_rect().size
	_score_panel.position = (vp - _score_panel.size) / 2.0
	_score_panel.visible = true


func hide_score() -> void:
	if _score_panel:
		_score_panel.visible = false


func _add_score_label(text: String, font_size: int, color: Color,
		h_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = h_align
	_score_content.add_child(lbl)


func update_task_list(all_props: Array[StaticBody2D]) -> void:
	# Clear existing entries
	for child in task_list.get_children():
		child.queue_free()

	for prop in all_props:
		var entry := Label.new()
		entry.add_theme_font_size_override("font_size", 14)

		if prop.get_leg_count() > 0:
			var trait_labels: PackedStringArray = prop.get_trait_labels()
			var header: String = "%s (wt %d)" % [prop.prop_name, prop.weight]
			if trait_labels.size() > 0:
				header += " [%s]" % ", ".join(trait_labels)
			header += ":"
			var lines: PackedStringArray = [header]

			for i in range(prop.get_leg_count()):
				var leg: Dictionary = prop.get_leg(i)
				var stagehand_names: PackedStringArray = []
				for sh in leg.stagehands:
					stagehand_names.append(sh.stagehand_name)

				var dest_str: String = "?"
				if leg.has("destination"):
					var d: Vector2 = leg.destination
					dest_str = "(%d, %d)" % [int(d.x), int(d.y)]

				var names_str: String = ", ".join(stagehand_names) if stagehand_names.size() > 0 else "none"
				var leg_line: String = "  Leg %d: %s -> %s" % [i + 1, names_str, dest_str]

				# Color red if assigned strength < required strength
				var leg_strength: int = prop.get_leg_stagehand_strength(i)
				if leg_strength < prop.get_required_strength() and leg.stagehands.size() > 0:
					leg_line += " [weak!]"

				lines.append(leg_line)

			entry.text = "\n".join(lines)
			entry.add_theme_color_override("font_color", prop.prop_color.lightened(0.3))
		else:
			entry.text = "%s: unassigned" % prop.prop_name
			entry.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		task_list.add_child(entry)
