extends Node2D
## Visual representation of stage zones: rectangular proscenium stage, wings, and house (audience)

# Stage layout
@export var stage_width: float = 1300.0
@export var stage_depth: float = 600.0
@export var proscenium_y: float = -500.0  # front of stage (audience side)
@export var proscenium_left: float = -650.0   # left edge of proscenium opening
@export var proscenium_right: float = 650.0   # right edge of proscenium opening
@export var apron_depth: float = 200.0        # max depth of apron ellipse at center
@export var apron_segments: int = 48         # smoothness of ellipse curve

# Wing layout
@export var wing_width: float = 250.0
@export var wing_height: float = 600.0  # total height, 3 sections
@export var wing_top_y: float = -500.0  # wings start at proscenium line

# House (audience)
@export var house_height: float = 900.0
@export var house_top_width: float = 2000.0
@export var house_bottom_width: float = 1280.0

# Colors
@export var floor_color: Color = Color(0.2, 0.15, 0.1, 1)
@export var floor_border_color: Color = Color(0.35, 0.3, 0.25, 0.8)
@export var wing_color: Color = Color(0.15, 0.12, 0.08, 0.8)
@export var zone_border_color: Color = Color(0.4, 0.35, 0.3, 0.5)
@export var house_color: Color = Color(0.1, 0.08, 0.06, 0.9)
@export var audience_head_color: Color = Color(0.3, 0.25, 0.2, 0.7)
@export var proscenium_wall_color: Color = Color(0.25, 0.2, 0.15, 1.0)
@export var num_wing_sections: int = 4

@export var head_radius: float = 10.0
@export var head_spacing: float = 40.0
@export var row_offset: float = 40.0


func _draw() -> void:
	_draw_house()
	_draw_apron()
	_draw_floor()
	_draw_wings()
	_draw_proscenium_wall()


func _draw_apron() -> void:
	# Half-ellipse forestage: curves outward only across the proscenium opening
	var half_w: float = (proscenium_right - proscenium_left) / 2.0
	var center_x: float = (proscenium_left + proscenium_right) / 2.0
	var points := PackedVector2Array()

	# Arc from left to right (going through the front/audience side)
	for i in range(apron_segments + 1):
		var angle: float = PI + PI * float(i) / float(apron_segments)
		var x: float = center_x + half_w * cos(angle)
		var y: float = proscenium_y + apron_depth * sin(angle)
		points.append(Vector2(x, y))

	# Close with flat edge at proscenium line
	points.append(Vector2(proscenium_right, proscenium_y))
	points.append(Vector2(proscenium_left, proscenium_y))

	draw_colored_polygon(points, floor_color)

	# Draw curved border
	var arc_points := PackedVector2Array()
	for i in range(apron_segments + 1):
		var angle: float = PI + PI * float(i) / float(apron_segments)
		var x: float = center_x + half_w * cos(angle)
		var y: float = proscenium_y + apron_depth * sin(angle)
		arc_points.append(Vector2(x, y))
	draw_polyline(arc_points, floor_border_color, 2.0)


func _draw_floor() -> void:
	var rect := Rect2(
		Vector2(proscenium_left, proscenium_y),
		Vector2(stage_width, stage_depth)
	)
	draw_rect(rect, floor_color)
	# Border on left, right, bottom only — no top border (merges with apron)
	var left := proscenium_left
	var right := proscenium_right
	var top := proscenium_y
	var bottom := proscenium_y + stage_depth
	draw_line(Vector2(left, top), Vector2(left, bottom), floor_border_color, 2.0)
	draw_line(Vector2(right, top), Vector2(right, bottom), floor_border_color, 2.0)
	draw_line(Vector2(left, bottom), Vector2(right, bottom), floor_border_color, 2.0)


func _draw_wings() -> void:
	var section_height: float = wing_height / float(num_wing_sections)

	# Stage left wings
	var sl_x: float = proscenium_left - wing_width
	for i in range(num_wing_sections):
		var section_y: float = wing_top_y + i * section_height
		var section_rect := Rect2(Vector2(sl_x, section_y), Vector2(wing_width, section_height))
		draw_rect(section_rect, wing_color)
		_draw_wing_section_border(sl_x, section_y, wing_width, section_height, i == num_wing_sections - 1)

	# Stage right wings (x: 400 to 900)
	var sr_x: float = proscenium_right
	for i in range(num_wing_sections):
		var section_y: float = wing_top_y + i * section_height
		var section_rect := Rect2(Vector2(sr_x, section_y), Vector2(wing_width, section_height))
		draw_rect(section_rect, wing_color)
		_draw_wing_section_border(sr_x, section_y, wing_width, section_height, i == num_wing_sections - 1)


func _draw_wing_section_border(x: float, y: float, w: float, h: float, skip_bottom: bool) -> void:
	draw_line(Vector2(x, y), Vector2(x + w, y), zone_border_color, 2.0)          # top
	draw_line(Vector2(x, y), Vector2(x, y + h), zone_border_color, 2.0)          # left
	draw_line(Vector2(x + w, y), Vector2(x + w, y + h), zone_border_color, 2.0)  # right
	if not skip_bottom:
		draw_line(Vector2(x, y + h), Vector2(x + w, y + h), zone_border_color, 2.0)


func _draw_house() -> void:
	# House wedge shape — audience area in front of proscenium
	var y_top: float = proscenium_y - house_height
	var y_bottom: float = proscenium_y

	var points := PackedVector2Array([
		Vector2(-house_top_width / 2.0, y_top),
		Vector2(house_top_width / 2.0, y_top),
		Vector2(house_bottom_width / 2.0, y_bottom),
		Vector2(-house_bottom_width / 2.0, y_bottom),
	])
	draw_colored_polygon(points, house_color)

	# Apron ellipse parameters for head exclusion
	var apron_half_w: float = (proscenium_right - proscenium_left) / 2.0

	# Fill with audience heads in rows
	var row_index: int = 0
	var y: float = y_bottom - head_spacing
	while y > y_top + head_radius:
		# Interpolate width at this y
		var t: float = (y - y_top) / (y_bottom - y_top)
		var half_w: float = lerp(house_top_width / 2.0, house_bottom_width / 2.0, t) - head_radius
		var x_off: float = row_offset if row_index % 2 == 1 else 0.0

		var col: int = 0
		var x: float = -half_w + x_off
		while x <= half_w:
			# Skip heads inside the apron ellipse
			var nx: float = x / apron_half_w
			var ny: float = (y - proscenium_y) / apron_depth
			if (nx * nx + ny * ny) > 1.0:
				var variation: float = sin(float(row_index * 7 + col * 13)) * 0.05
				var head_color := Color(
					audience_head_color.r + variation,
					audience_head_color.g + variation,
					audience_head_color.b + variation,
					audience_head_color.a
				)
				draw_circle(Vector2(x, y), head_radius, head_color)
			x += head_spacing
			col += 1
		y -= head_spacing
		row_index += 1


func _draw_proscenium_wall() -> void:
	# Thick wall sections on either side of the proscenium opening at Y=proscenium_y
	var wall_thickness: float = 12.0
	var half_stage: float = (stage_width + 2.0 * wing_width) / 2.0

	# Left wall
	var left_wall := Rect2(
		Vector2(-half_stage, proscenium_y - wall_thickness / 2.0),
		Vector2(proscenium_left + half_stage, wall_thickness)
	)
	draw_rect(left_wall, proscenium_wall_color)

	# Right wall
	var right_wall := Rect2(
		Vector2(proscenium_right, proscenium_y - wall_thickness / 2.0),
		Vector2(half_stage - proscenium_right, wall_thickness)
	)
	draw_rect(right_wall, proscenium_wall_color)


