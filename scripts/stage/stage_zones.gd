extends Node2D
## Visual representation of stage zones: wings and house (audience)

@export var stage_width: float = 1000.0
@export var stage_height: float = 800.0
@export var wing_width: float = 150.0
@export var house_height: float = 100.0

@export var wing_color: Color = Color(0.15, 0.12, 0.08, 0.8)
@export var wing_divider_color: Color = Color(0.4, 0.35, 0.3, 0.3)
@export var house_color: Color = Color(0.1, 0.08, 0.06, 0.9)
@export var audience_head_color: Color = Color(0.3, 0.25, 0.2, 0.7)
@export var zone_border_color: Color = Color(0.4, 0.35, 0.3, 0.5)

@export var head_radius: float = 8.0
@export var head_spacing: float = 25.0
@export var row_offset: float = 12.0  # Stagger rows for natural look


func _draw() -> void:
	var half_width: float = stage_width / 2.0
	var half_height: float = stage_height / 2.0

	# Wing dimensions
	var wing_top: float = -half_height + (house_height * 3)
	var wing_height: float = stage_height - (house_height * 3)
	var section_height: float = wing_height / 3.0

	# Draw stage left wings (1st, 2nd, 3rd from audience)
	var sl_x: float = -half_width
	for i in range(3):
		var section_y: float = wing_top + i * section_height
		var section_rect := Rect2(Vector2(sl_x, section_y), Vector2(wing_width, section_height))
		draw_rect(section_rect, wing_color)
		draw_rect(section_rect, zone_border_color, false, 2.0)
	_draw_zone_label("STAGE LEFT", Vector2(-half_width + wing_width / 2.0, 0), true)

	# Draw stage right wings (1st, 2nd, 3rd from audience)
	var sr_x: float = half_width - wing_width
	for i in range(3):
		var section_y: float = wing_top + i * section_height
		var section_rect := Rect2(Vector2(sr_x, section_y), Vector2(wing_width, section_height))
		draw_rect(section_rect, wing_color)
		draw_rect(section_rect, zone_border_color, false, 2.0)
	_draw_zone_label("STAGE RIGHT", Vector2(half_width - wing_width / 2.0, 0), true)

	# Draw house (audience area at top)
	var house_rect := Rect2(
		Vector2(-half_width, -half_height),
		Vector2(stage_width, house_height)
	)
	draw_rect(house_rect, house_color)
	draw_rect(house_rect, zone_border_color, false, 2.0)

	# Draw audience heads
	_draw_audience_heads(house_rect)


func _draw_audience_heads(house_rect: Rect2) -> void:
	var start_x: float = house_rect.position.x + head_spacing
	var end_x: float = house_rect.position.x + house_rect.size.x - head_spacing
	var start_y: float = house_rect.position.y + head_spacing
	var end_y: float = house_rect.position.y + house_rect.size.y - head_radius

	var row: int = 0
	var col: int = 0
	var y: float = start_y

	while y < end_y:
		var x_offset: float = row_offset if row % 2 == 1 else 0.0
		var x: float = start_x + x_offset
		col = 0

		while x < end_x:
			# Deterministic variation based on position for natural look
			var variation: float = sin(float(row * 7 + col * 13)) * 0.05
			var head_color := Color(
				audience_head_color.r + variation,
				audience_head_color.g + variation,
				audience_head_color.b + variation,
				audience_head_color.a
			)
			draw_circle(Vector2(x, y), head_radius, head_color)
			x += head_spacing
			col += 1

		y += head_spacing * 0.8  # Tighter vertical spacing
		row += 1


func _draw_zone_label(_text: String, _pos: Vector2, _vertical: bool) -> void:
	# Placeholder for zone labels - would require a font to implement
	pass
