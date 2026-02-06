extends Node2D
## Draws path preview lines for the selected stagehand's planned route

const PICKUP_LINE_WIDTH: float = 2.0
const CARRY_LINE_WIDTH: float = 3.0
const CLEAR_ZONE_LINE_WIDTH: float = 2.0
const EXECUTION_LINE_WIDTH: float = 2.5
const PICKUP_ALPHA: float = 0.5
const CARRY_ALPHA: float = 0.8
const EXECUTION_ALPHA: float = 0.7
const CLEAR_ZONE_COLOR: Color = Color(0.9, 0.9, 0.6, 0.4)
const DASH_LENGTH: float = 8.0
const GAP_LENGTH: float = 6.0
const WAYPOINT_RADIUS: float = 4.0
const DESTINATION_DIAMOND_SIZE: float = 6.0
const DRAG_RECOMPUTE_THRESHOLD: float = 25.0

var _selected_stagehand: CharacterBody2D = null
var _pathfinding: Node = null
var _is_execution: bool = false
var _dirty: bool = false
var _force_recompute: bool = false
# Each entry: { "points": PackedVector2Array, "color": Color, "width": float, "dashed": bool, "end_marker": String }
var _cached_paths: Array = []
var _clear_zone_path: PackedVector2Array = []
var _last_stagehand_pos: Vector2 = Vector2.ZERO
var _last_prop_positions: Dictionary = {}

var _clear_zone_left_stagehand: CharacterBody2D = null
var _clear_zone_right_stagehand: CharacterBody2D = null
var _clear_zone_left_center: Vector2 = Vector2.ZERO
var _clear_zone_right_center: Vector2 = Vector2.ZERO


func setup(pathfinding_node: Node, cz_left_center: Vector2, cz_right_center: Vector2) -> void:
	_pathfinding = pathfinding_node
	_clear_zone_left_center = cz_left_center
	_clear_zone_right_center = cz_right_center


func set_stagehand(stagehand: CharacterBody2D) -> void:
	_selected_stagehand = stagehand
	_force_recompute = true
	_recompute()


func clear() -> void:
	_selected_stagehand = null
	_cached_paths.clear()
	_clear_zone_path = PackedVector2Array()
	queue_redraw()


func set_execution_mode(is_exec: bool) -> void:
	_is_execution = is_exec
	if not is_exec:
		_force_recompute = true
		_recompute()
	else:
		_cached_paths.clear()
		queue_redraw()


func set_clear_zone_stagehands(left: CharacterBody2D, right: CharacterBody2D) -> void:
	_clear_zone_left_stagehand = left
	_clear_zone_right_stagehand = right
	invalidate()


func invalidate(force: bool = false) -> void:
	if _is_execution:
		return
	_force_recompute = _force_recompute or force
	if not _dirty:
		_dirty = true
		_recompute.call_deferred()


func _process(_delta: float) -> void:
	if _is_execution and _selected_stagehand:
		if _selected_stagehand.current_state in [
			StagehandController.State.MOVING,
			StagehandController.State.CARRYING,
		]:
			queue_redraw()


func _recompute() -> void:
	_dirty = false
	var should_force: bool = _force_recompute
	_force_recompute = false

	if not _selected_stagehand or not _pathfinding:
		_cached_paths.clear()
		_clear_zone_path = PackedVector2Array()
		queue_redraw()
		return

	if _is_execution:
		queue_redraw()
		return

	var sh_pos: Vector2 = _selected_stagehand.global_position

	# Drag throttle: skip if positions haven't moved enough
	if not should_force and _cached_paths.size() > 0:
		if sh_pos.distance_to(_last_stagehand_pos) < DRAG_RECOMPUTE_THRESHOLD:
			var any_moved: bool = false
			for prop in _selected_stagehand.assigned_props:
				var cached_pos: Variant = _last_prop_positions.get(prop)
				if cached_pos == null or prop.global_position.distance_to(cached_pos as Vector2) >= DRAG_RECOMPUTE_THRESHOLD:
					any_moved = true
					break
			if not any_moved:
				return

	_cached_paths.clear()
	_clear_zone_path = PackedVector2Array()
	_last_stagehand_pos = sh_pos
	_last_prop_positions.clear()

	# Track the last destination this stagehand will end up at (for clear zone pathing)
	var last_endpoint: Vector2 = sh_pos

	for prop in _selected_stagehand.assigned_props:
		var prop_pos: Vector2 = prop.global_position
		_last_prop_positions[prop] = prop_pos

		for leg_idx in range(prop.get_leg_count()):
			var leg: Dictionary = prop.get_leg(leg_idx)
			if _selected_stagehand not in leg.stagehands:
				continue

			# Pickup position depends on leg index
			var pickup_pos: Vector2 = prop_pos
			if leg_idx > 0:
				var prev_leg: Dictionary = prop.get_leg(leg_idx - 1)
				if prev_leg.has("destination"):
					pickup_pos = prev_leg.destination

			# Pickup path: stagehand -> prop
			var pickup_path: PackedVector2Array = _pathfinding.find_path(sh_pos, pickup_pos)
			if pickup_path.size() > 0:
				var pickup_color := Color(prop.prop_color.r, prop.prop_color.g, prop.prop_color.b, PICKUP_ALPHA)
				_cached_paths.append({
					"points": pickup_path,
					"color": pickup_color,
					"width": PICKUP_LINE_WIDTH,
					"dashed": true,
					"end_marker": "circle",
				})

			# Carry path: prop -> destination
			if leg.has("destination"):
				var carry_path: PackedVector2Array = _pathfinding.find_path(pickup_pos, leg.destination)
				if carry_path.size() > 0:
					var carry_color := Color(prop.prop_color.r, prop.prop_color.g, prop.prop_color.b, CARRY_ALPHA)
					_cached_paths.append({
						"points": carry_path,
						"color": carry_color,
						"width": CARRY_LINE_WIDTH,
						"dashed": false,
						"end_marker": "diamond",
					})
				last_endpoint = leg.destination

	# Clear zone path — starts from last delivery destination, not stagehand position
	var cz_target: Variant = _get_clear_zone_target()
	if cz_target != null:
		_clear_zone_path = _pathfinding.find_path(last_endpoint, cz_target as Vector2)

	queue_redraw()


func _get_clear_zone_target() -> Variant:
	if _selected_stagehand == _clear_zone_left_stagehand:
		return _clear_zone_left_center
	if _selected_stagehand == _clear_zone_right_stagehand:
		return _clear_zone_right_center
	return null


# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	if not _selected_stagehand:
		return

	if _is_execution:
		_draw_execution_path()
		return

	# Planning paths
	for path_data in _cached_paths:
		if path_data.dashed:
			_draw_dashed_polyline(path_data.points, path_data.color, path_data.width)
		else:
			_draw_polyline_safe(path_data.points, path_data.color, path_data.width)

		# End marker
		if path_data.points.size() > 0:
			var end_pos: Vector2 = path_data.points[path_data.points.size() - 1]
			match path_data.end_marker:
				"circle":
					draw_arc(end_pos, WAYPOINT_RADIUS, 0, TAU, 16, path_data.color, 2.0)
				"diamond":
					_draw_diamond(end_pos, DESTINATION_DIAMOND_SIZE, path_data.color)

	# Clear zone path
	if _clear_zone_path.size() > 1:
		_draw_dashed_polyline(_clear_zone_path, CLEAR_ZONE_COLOR, CLEAR_ZONE_LINE_WIDTH)
		var cz_end: Vector2 = _clear_zone_path[_clear_zone_path.size() - 1]
		var half: float = 4.0
		draw_rect(Rect2(cz_end - Vector2(half, half), Vector2(half * 2, half * 2)), CLEAR_ZONE_COLOR, false, 2.0)


func _draw_execution_path() -> void:
	var sh: CharacterBody2D = _selected_stagehand
	if sh.current_path.is_empty() or sh.path_index >= sh.current_path.size():
		return

	var color := Color(sh.stagehand_color.r, sh.stagehand_color.g, sh.stagehand_color.b, EXECUTION_ALPHA)

	var remaining := PackedVector2Array()
	remaining.append(sh.global_position)
	for i in range(sh.path_index, sh.current_path.size()):
		remaining.append(sh.current_path[i])

	if remaining.size() >= 2:
		_draw_polyline_safe(remaining, color, EXECUTION_LINE_WIDTH)


func _draw_polyline_safe(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() >= 2:
		draw_polyline(points, color, width, true)


func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return

	var accumulated: float = 0.0
	var drawing: bool = true

	for i in range(points.size() - 1):
		var from_pt: Vector2 = points[i]
		var to_pt: Vector2 = points[i + 1]
		var segment_dir: Vector2 = to_pt - from_pt
		var segment_len: float = segment_dir.length()
		if segment_len < 0.1:
			continue
		var segment_unit: Vector2 = segment_dir / segment_len
		var pos: float = 0.0

		while pos < segment_len:
			var pattern_len: float = DASH_LENGTH if drawing else GAP_LENGTH
			var remaining_in_pattern: float = pattern_len - accumulated
			var remaining_in_segment: float = segment_len - pos
			var step: float = min(remaining_in_pattern, remaining_in_segment)

			if drawing:
				var start: Vector2 = from_pt + segment_unit * pos
				var end: Vector2 = from_pt + segment_unit * (pos + step)
				draw_line(start, end, color, width, true)

			pos += step
			accumulated += step

			if accumulated >= pattern_len:
				accumulated = 0.0
				drawing = not drawing


func _draw_diamond(center: Vector2, half_size: float, color: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -half_size),
		center + Vector2(half_size, 0),
		center + Vector2(0, half_size),
		center + Vector2(-half_size, 0),
	])
	draw_colored_polygon(pts, color)
