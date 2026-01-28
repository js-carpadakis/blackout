extends Node2D
## Visual grid overlay for the stage floor

@export var grid_size: Vector2i = Vector2i(20, 16)
@export var cell_size: float = 50.0
@export var grid_color: Color = Color(0.5, 0.5, 0.5, 0.3)
@export var grid_line_width: float = 1.0

var _grid_visible: bool = true


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if not _grid_visible:
		return

	var total_width: float = grid_size.x * cell_size
	var total_height: float = grid_size.y * cell_size
	var half_width: float = total_width / 2.0
	var half_height: float = total_height / 2.0

	# Draw vertical lines
	for i in range(grid_size.x + 1):
		var x: float = -half_width + i * cell_size
		draw_line(Vector2(x, -half_height), Vector2(x, half_height), grid_color, grid_line_width)

	# Draw horizontal lines
	for i in range(grid_size.y + 1):
		var y: float = -half_height + i * cell_size
		draw_line(Vector2(-half_width, y), Vector2(half_width, y), grid_color, grid_line_width)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	var half_width: float = grid_size.x * cell_size / 2.0
	var half_height: float = grid_size.y * cell_size / 2.0
	var local_x: float = world_pos.x + half_width
	var local_y: float = world_pos.y + half_height
	return Vector2i(
		clampi(int(local_x / cell_size), 0, grid_size.x - 1),
		clampi(int(local_y / cell_size), 0, grid_size.y - 1)
	)


func grid_to_world(grid_pos: Vector2i) -> Vector2:
	var half_width: float = grid_size.x * cell_size / 2.0
	var half_height: float = grid_size.y * cell_size / 2.0
	return Vector2(
		-half_width + (grid_pos.x + 0.5) * cell_size,
		-half_height + (grid_pos.y + 0.5) * cell_size
	)


func is_valid_grid_pos(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_size.x and grid_pos.y >= 0 and grid_pos.y < grid_size.y


func set_grid_visible(grid_visible: bool) -> void:
	_grid_visible = grid_visible
	queue_redraw()
