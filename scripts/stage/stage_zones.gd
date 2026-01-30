extends Node2D
## Visual representation of stage zones: half-ellipse floor, wings, and house (audience)

# Ellipse parameters (flat edge at bottom, curve at top toward audience)
@export var ellipse_center_y: float = 500.0
@export var ellipse_a: float = 800.0  # semi-axis x
@export var ellipse_b: float = 1000.0  # semi-axis y
@export var ellipse_segments: int = 64

# Wing layout
@export var wing_width: float = 400.0
@export var wing_height: float = 600.0  # total height, 3 sections
@export var wing_top_y: float = -100.0  # wings start here

# Backstage
@export var backstage_width: float = 2000.0
@export var backstage_height: float = 600.0
@export var backstage_top_y: float = -100.0

# House (audience)
@export var house_height: float = 900.0
@export var house_top_width: float = 2000.0
@export var house_bottom_width: float = 1280.0

# Colors
@export var backstage_color: Color = Color(0.12, 0.1, 0.07, 0.9)
@export var floor_color: Color = Color(0.2, 0.15, 0.1, 1)
@export var floor_border_color: Color = Color(0.35, 0.3, 0.25, 0.8)
@export var wing_color: Color = Color(0.15, 0.12, 0.08, 0.8)
@export var zone_border_color: Color = Color(0.4, 0.35, 0.3, 0.5)
@export var house_color: Color = Color(0.1, 0.08, 0.06, 0.9)
@export var audience_head_color: Color = Color(0.3, 0.25, 0.2, 0.7)

@export var head_radius: float = 10.0
@export var head_spacing: float = 40.0
@export var row_offset: float = 40.0


func _draw() -> void:
	_draw_backstage()
	_draw_house()
	_draw_floor()
	_draw_wings()


func _draw_backstage() -> void:
	var rect := Rect2(
		Vector2(-backstage_width / 2.0, backstage_top_y),
		Vector2(backstage_width, backstage_height)
	)
	draw_rect(rect, backstage_color)
	draw_rect(rect, zone_border_color, false, 2.0)


func _draw_floor() -> void:
	# Build half-ellipse polygon: flat edge at bottom, curve at top
	var points: PackedVector2Array = PackedVector2Array()

	# Arc from bottom-left to bottom-right (going counter-clockwise through the top)
	for i in range(ellipse_segments + 1):
		var angle: float = PI + PI * float(i) / float(ellipse_segments)  # PI to 2*PI
		var x: float = ellipse_a * cos(angle)
		var y: float = ellipse_center_y + ellipse_b * sin(angle)
		points.append(Vector2(x, y))

	# Close with flat edge at bottom
	points.append(Vector2(ellipse_a, ellipse_center_y))
	points.append(Vector2(-ellipse_a, ellipse_center_y))

	draw_colored_polygon(points, floor_color)

	# Draw border arc (just the curved part)
	var arc_points: PackedVector2Array = PackedVector2Array()
	for i in range(ellipse_segments + 1):
		var angle: float = PI + PI * float(i) / float(ellipse_segments)
		var x: float = ellipse_a * cos(angle)
		var y: float = ellipse_center_y + ellipse_b * sin(angle)
		arc_points.append(Vector2(x, y))
	draw_polyline(arc_points, floor_border_color, 2.0)

	# Draw flat edge at bottom
	draw_line(Vector2(-ellipse_a, ellipse_center_y), Vector2(ellipse_a, ellipse_center_y), floor_border_color, 2.0)


func _draw_wings() -> void:
	var section_height: float = wing_height / 3.0

	# Stage left wings (x: -1000 to -600)
	var sl_x: float = -backstage_width / 2.0
	for i in range(3):
		var section_y: float = wing_top_y + i * section_height
		var section_rect := Rect2(Vector2(sl_x, section_y), Vector2(wing_width, section_height))
		draw_rect(section_rect, wing_color)
		draw_rect(section_rect, zone_border_color, false, 2.0)

	# Stage right wings (x: 600 to 1000)
	var sr_x: float = backstage_width / 2.0 - wing_width
	for i in range(3):
		var section_y: float = wing_top_y + i * section_height
		var section_rect := Rect2(Vector2(sr_x, section_y), Vector2(wing_width, section_height))
		draw_rect(section_rect, wing_color)
		draw_rect(section_rect, zone_border_color, false, 2.0)


func _draw_house() -> void:
	# House wedge shape
	var y_top: float = -house_height - backstage_top_y
	var y_bottom: float = backstage_top_y

	var points := PackedVector2Array([
		Vector2(-house_top_width / 2.0, y_top),
		Vector2(house_top_width / 2.0, y_top),
		Vector2(house_bottom_width / 2.0, y_bottom),
		Vector2(-house_bottom_width / 2.0, y_bottom),
	])
	draw_colored_polygon(points, house_color)

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
			# Skip heads inside the stage ellipse
			var nx: float = x / ellipse_a
			var ny: float = (y - ellipse_center_y) / ellipse_b
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
