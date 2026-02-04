extends CanvasLayer
## HUD for planning phase: shows current phase, start button, and task assignments

signal start_pressed

@onready var phase_label: Label = $PhaseLabel
@onready var start_button: Button = $StartButton
@onready var task_list: VBoxContainer = $TaskPanel/TaskList


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	set_phase("PLANNING")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_execution"):
		_on_start_pressed()
		get_viewport().set_input_as_handled()


func _on_start_pressed() -> void:
	start_pressed.emit()


func set_phase(phase_name: String) -> void:
	phase_label.text = phase_name
	start_button.visible = phase_name == "PLANNING"


func update_task_list(stagehands: Array[CharacterBody2D]) -> void:
	# Clear existing entries
	for child in task_list.get_children():
		child.queue_free()

	for stagehand in stagehands:
		var entry := Label.new()
		entry.add_theme_font_size_override("font_size", 14)

		if stagehand.has_assignment:
			var task_parts: PackedStringArray = []
			for i in range(stagehand.task_queue.size()):
				var task: Dictionary = stagehand.task_queue[i]
				var prop_name: String = task.prop.prop_name if task.prop else "?"
				if task.action == "pick_up":
					task_parts.append("%d. ^ %s" % [i + 1, prop_name])
				elif task.action == "drop_off":
					task_parts.append("%d. v %s" % [i + 1, prop_name])
			entry.text = "%s: %s" % [stagehand.stagehand_name, ", ".join(task_parts)]
			entry.add_theme_color_override("font_color", stagehand.stagehand_color)
		else:
			entry.text = "%s: unassigned" % stagehand.stagehand_name
			entry.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		task_list.add_child(entry)
