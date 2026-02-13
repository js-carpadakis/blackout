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

	return _smooth_path(result_path)


func _smooth_path(path: PackedVector2Array) -> PackedVector2Array:
	## Reduce turns by skipping waypoints when a straight line stays on walkable cells.
	if path.size() <= 2:
		return path

	var smoothed := PackedVector2Array()
	smoothed.append(path[0])
	var anchor: int = 0

	while anchor < path.size() - 1:
		var farthest: int = anchor + 1
		# Scan backwards from end to find farthest reachable point
		for i in range(path.size() - 1, anchor + 1, -1):
			if _walkable_line(path[anchor], path[i]):
				farthest = i
				break
		smoothed.append(path[farthest])
		anchor = farthest

	return smoothed


func _walkable_line(from_pos: Vector2, to_pos: Vector2) -> bool:
	## Check if a straight line between two world positions stays on walkable cells.
	var from_cell: Vector2i = world_to_cell(from_pos)
	var to_cell: Vector2i = world_to_cell(to_pos)
	if from_cell == to_cell:
		return true

	# Walk all cells the line passes through (supercover / grid traversal)
	var dx: int = abs(to_cell.x - from_cell.x)
	var dy: int = abs(to_cell.y - from_cell.y)
	var sx: int = 1 if from_cell.x < to_cell.x else -1
	var sy: int = 1 if from_cell.y < to_cell.y else -1
	var x: int = from_cell.x
	var y: int = from_cell.y
	var err: int = dx - dy

	while true:
		if is_cell_blocked(Vector2i(x, y)):
			return false
		if x == to_cell.x and y == to_cell.y:
			break
		var e2: int = 2 * err
		# For supercover: when crossing a corner, also check the adjacent cells
		if e2 > -dy and e2 < dx:
			# Diagonal step — check both adjacent cells to prevent corner-cutting
			if is_cell_blocked(Vector2i(x + sx, y)) and is_cell_blocked(Vector2i(x, y + sy)):
				return false
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

	return true


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
