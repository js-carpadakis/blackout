extends Control
## Top-down preview of the stage showing wing sections and assigned stagehands/props

# World coordinate bounds (from game_session.gd)
const STAGE_RECT := Rect2(-650, -500, 1300, 600)
const WING_SECTIONS: Array[Rect2] = [
	Rect2(-900, -500, 250, 150),  # L1
	Rect2(-900, -350, 250, 150),  # L2
	Rect2(-900, -200, 250, 150),  # L3
	Rect2(-900, -50, 250, 150),   # L4
	Rect2(650, -500, 250, 150),   # R1
	Rect2(650, -350, 250, 150),   # R2
	Rect2(650, -200, 250, 150),   # R3
	Rect2(650, -50, 250, 150),    # R4
]
const WING_LABELS: Array[String] = ["L1", "L2", "L3", "L4", "R1", "R2", "R3", "R4"]

# World bounds encompassing stage + wings
const WORLD_MIN := Vector2(-900, -500)
const WORLD_MAX := Vector2(900, 100)
const WORLD_SIZE := Vector2(1800, 600)

var _props: Array = []
var _stagehands: Array = []
var _assignments: Array = []  # Array of { prop_index, stagehand_index, wing_section }


func set_data(prop_defs: Array, stagehand_defs: Array, assignments: Array) -> void:
	_props = prop_defs
	_stagehands = stagehand_defs
	_assignments = assignments
	queue_redraw()


func _world_to_local_rect(world_rect: Rect2) -> Rect2:
	var draw_area := _get_draw_area()
	var scale_val := Vector2(draw_area.size.x / WORLD_SIZE.x, draw_area.size.y / WORLD_SIZE.y)
	var local_pos := Vector2(
		(world_rect.position.x - WORLD_MIN.x) * scale_val.x + draw_area.position.x,
		(world_rect.position.y - WORLD_MIN.y) * scale_val.y + draw_area.position.y
	)
	var local_size := Vector2(world_rect.size.x * scale_val.x, world_rect.size.y * scale_val.y)
	return Rect2(local_pos, local_size)


func _world_to_local_point(world_pos: Vector2) -> Vector2:
	var draw_area := _get_draw_area()
	var scale_val := Vector2(draw_area.size.x / WORLD_SIZE.x, draw_area.size.y / WORLD_SIZE.y)
	return Vector2(
		(world_pos.x - WORLD_MIN.x) * scale_val.x + draw_area.position.x,
		(world_pos.y - WORLD_MIN.y) * scale_val.y + draw_area.position.y
	)


func _get_draw_area() -> Rect2:
	var margin := 20.0
	return Rect2(margin, margin, size.x - margin * 2, size.y - margin * 2)


func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.1), true)

	# Stage rectangle
	var stage_local := _world_to_local_rect(STAGE_RECT)
	draw_rect(stage_local, Color(0.25, 0.25, 0.25), true)
	draw_rect(stage_local, Color(0.5, 0.5, 0.5), false, 2.0)

	# "STAGE" label
	var font := ThemeDB.fallback_font
	var stage_center := stage_local.position + stage_local.size / 2.0
	draw_string(font, Vector2(stage_center.x - 20, stage_center.y + 5), "STAGE", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.5, 0.5, 0.5))

	# Collect which wing sections have assignments
	var assigned_wings: Dictionary = {}  # wing_index -> Array of assignment dicts
	for a in _assignments:
		if not assigned_wings.has(a.wing_section):
			assigned_wings[a.wing_section] = []
		assigned_wings[a.wing_section].append(a)

	# Wing sections
	for i in range(WING_SECTIONS.size()):
		var section := WING_SECTIONS[i]
		var local_rect := _world_to_local_rect(section)
		var has_assignment := assigned_wings.has(i)

		# Fill color
		var fill_color := Color(0.15, 0.15, 0.15)
		if has_assignment:
			fill_color = Color(0.2, 0.25, 0.2)
		draw_rect(local_rect, fill_color, true)
		draw_rect(local_rect, Color(0.4, 0.4, 0.4), false, 1.0)

		# Wing label
		var label_pos := Vector2(local_rect.position.x + 4, local_rect.position.y + 14)
		draw_string(font, label_pos, WING_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.6))

		# Draw assigned entities
		if has_assignment:
			var entries: Array = assigned_wings[i]
			for j in range(entries.size()):
				var a: Dictionary = entries[j]
				var center := local_rect.position + Vector2(local_rect.size.x / 2.0, local_rect.size.y * (0.4 + j * 0.3))

				# Stagehand circles (multiple per assignment)
				if a.has("stagehand_colors"):
					var colors: Array = a.stagehand_colors
					for c_i in range(colors.size()):
						draw_circle(center + Vector2(-12 - c_i * 14, 0), 6.0, colors[c_i])

				# Prop color swatch
				if a.has("prop_color"):
					var swatch := Rect2(center.x + 2, center.y - 5, 10, 10)
					draw_rect(swatch, a.prop_color, true)
