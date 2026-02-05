extends CanvasLayer
## HUD for planning phase: shows current phase, start button, and prop movement plans

signal start_pressed
signal add_leg_pressed

@onready var phase_label: Label = $PhaseLabel
@onready var start_button: Button = $StartButton
@onready var add_leg_button: Button = $AddLegButton
@onready var task_list: VBoxContainer = $TaskPanel/TaskList


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	add_leg_button.pressed.connect(_on_add_leg_pressed)
	set_phase("PLANNING")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_execution"):
		_on_start_pressed()
		get_viewport().set_input_as_handled()


func _on_start_pressed() -> void:
	start_pressed.emit()


func _on_add_leg_pressed() -> void:
	add_leg_pressed.emit()


func set_phase(phase_name: String) -> void:
	phase_label.text = phase_name
	start_button.visible = phase_name == "PLANNING"
	add_leg_button.visible = phase_name == "PLANNING"


func update_task_list(all_props: Array[StaticBody2D]) -> void:
	# Clear existing entries
	for child in task_list.get_children():
		child.queue_free()

	for prop in all_props:
		var entry := Label.new()
		entry.add_theme_font_size_override("font_size", 14)

		if prop.get_leg_count() > 0:
			var header: String = "%s (wt %d):" % [prop.prop_name, prop.weight]
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

				# Color red if assigned strength < prop weight
				var leg_strength: int = prop.get_leg_stagehand_strength(i)
				if leg_strength < prop.weight and leg.stagehands.size() > 0:
					leg_line += " [weak!]"

				lines.append(leg_line)

			entry.text = "\n".join(lines)
			entry.add_theme_color_override("font_color", prop.prop_color.lightened(0.3))
		else:
			entry.text = "%s: unassigned" % prop.prop_name
			entry.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		task_list.add_child(entry)
