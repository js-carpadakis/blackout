extends Node
## Manages pathfinding using AStarGrid2D for grid-based navigation

signal path_requested(from: Vector2i, to: Vector2i)
signal obstacle_updated(cell: Vector2i, blocked: bool)

var astar_grid: AStarGrid2D
var grid_size: Vector2i
var cell_size: float = 50.0
var _grid_offset: Vector2  # Offset to center grid at origin


func initialize(size: Vector2i, cell_size_param: float = 50.0) -> void:
	grid_size = size
	cell_size = cell_size_param
	_grid_offset = Vector2(size.x * cell_size / 2.0, size.y * cell_size / 2.0)

	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(Vector2i.ZERO, grid_size)
	astar_grid.cell_size = Vector2(cell_size, cell_size)
	astar_grid.offset = Vector2(cell_size / 2.0, cell_size / 2.0)  # Center of cells
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_grid.update()


func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	if not astar_grid:
		push_error("PathfindingManager not initialized")
		return PackedVector2Array()

	var from_cell: Vector2i = world_to_cell(from_world)
	var to_cell: Vector2i = world_to_cell(to_world)

	# Clamp to valid range
	from_cell = from_cell.clamp(Vector2i.ZERO, grid_size - Vector2i.ONE)
	to_cell = to_cell.clamp(Vector2i.ZERO, grid_size - Vector2i.ONE)

	path_requested.emit(from_cell, to_cell)

	var path_2d: PackedVector2Array = astar_grid.get_point_path(from_cell, to_cell)
	var result_path: PackedVector2Array = PackedVector2Array()

	for i in range(path_2d.size()):
		var point: Vector2 = path_2d[i]
		result_path.append(Vector2(point.x - _grid_offset.x, point.y - _grid_offset.y))

	# Replace final waypoint with exact destination position
	if result_path.size() > 0:
		result_path[result_path.size() - 1] = to_world

	return result_path


func get_path_cells(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
	if not astar_grid:
		push_error("PathfindingManager not initialized")
		return PackedVector2Array()

	return astar_grid.get_point_path(from_cell, to_cell)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local_x: float = world_pos.x + _grid_offset.x
	var local_y: float = world_pos.y + _grid_offset.y
	return Vector2i(
		clampi(int(local_x / cell_size), 0, grid_size.x - 1),
		clampi(int(local_y / cell_size), 0, grid_size.y - 1)
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x + 0.5) * cell_size - _grid_offset.x,
		(cell.y + 0.5) * cell_size - _grid_offset.y
	)


func set_cell_blocked(cell: Vector2i, blocked: bool) -> void:
	if not astar_grid:
		return

	if cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y:
		astar_grid.set_point_solid(cell, blocked)
		obstacle_updated.emit(cell, blocked)


func set_cells_blocked(cells: Array[Vector2i], blocked: bool) -> void:
	for cell in cells:
		set_cell_blocked(cell, blocked)


func is_cell_blocked(cell: Vector2i) -> bool:
	if not astar_grid:
		return true

	if cell.x < 0 or cell.x >= grid_size.x or cell.y < 0 or cell.y >= grid_size.y:
		return true

	return astar_grid.is_point_solid(cell)


func is_cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y


func mark_prop_area(world_pos: Vector2, footprint: Vector2i, blocked: bool) -> void:
	var base_cell: Vector2i = world_to_cell(world_pos)
	for x in range(footprint.x):
		for y in range(footprint.y):
			set_cell_blocked(base_cell + Vector2i(x, y), blocked)
