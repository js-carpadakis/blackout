extends StaticBody2D
## Controls a single prop that can be moved by stagehands

signal picked_up(by_stagehand: CharacterBody2D)
signal put_down(at_position: Vector2)
signal reached_target
signal leg_completed(leg_index: int)
signal plan_completed

enum PropState { STORED, BEING_CARRIED, PLACED, IN_POSITION }

@export var prop_name: String = "Prop"
@export var weight: int = 1  # Combined strength needed to carry
@export var grid_footprint: Vector2i = Vector2i(1, 1)
@export var prop_color: Color = Color.SADDLE_BROWN
@export var prop_size: Vector2 = Vector2(40, 40)

var current_state: PropState = PropState.STORED
var _base_target_position: Vector2 = Vector2.ZERO  # Original target from set_target()
var target_position: Vector2:
	get:
		if movement_plan.size() > 0:
			# Return last leg's destination if it has one
			for i in range(movement_plan.size() - 1, -1, -1):
				if movement_plan[i].has("destination"):
					return movement_plan[i].destination
		return _base_target_position
	set(value):
		_base_target_position = value
var target_rotation: float = 0.0
var carriers: Array[CharacterBody2D] = []  # All stagehands currently carrying this prop

# Movement plan: array of legs executed sequentially
# Each leg: { "stagehands": Array[CharacterBody2D], "destination": Vector2 }
var movement_plan: Array = []
var current_leg_index: int = -1  # -1 = not started

var assigned_stagehands: Array[CharacterBody2D]:
	get: return get_all_assigned_stagehands()

var _position_tolerance: float = 20.0
var _rotation_tolerance: float = 10.0  # Degrees
var _show_ghost: bool = false

@onready var _nav_obstacle: NavigationObstacle2D = $NavigationObstacle2D


func _ready() -> void:
	# Set prop size based on weight
	match weight:
		1:
			prop_size = Vector2(30, 30)
		2:
			prop_size = Vector2(50, 50)
		3:
			prop_size = Vector2(70, 70)
		_:
			prop_size = Vector2(30 + weight * 15, 30 + weight * 15)

	# Update navigation obstacle radius to match prop size
	if _nav_obstacle:
		_nav_obstacle.radius = max(prop_size.x, prop_size.y) / 2.0 + 5.0

	queue_redraw()


var is_being_dragged: bool = false

func _process(_delta: float) -> void:
	# Redraw while being moved to keep ghost at fixed world position
	if _show_ghost and (current_state == PropState.BEING_CARRIED or is_being_dragged):
		queue_redraw()


func _draw() -> void:
	# Draw target ghost at fixed world position (offset adjusts as prop moves)
	if _show_ghost:
		var offset: Vector2 = target_position - global_position
		var ghost_rect: Rect2 = Rect2(offset - prop_size / 2.0, prop_size)
		var ghost_color: Color = Color(prop_color.r, prop_color.g, prop_color.b, 0.3)
		draw_rect(ghost_rect, ghost_color)
		draw_rect(ghost_rect, prop_color.darkened(0.2), false, 2.0)

	# Main prop (rectangle)
	var rect: Rect2 = Rect2(-prop_size / 2.0, prop_size)
	draw_rect(rect, prop_color)

	# Border
	draw_rect(rect, prop_color.darkened(0.3), false, 2.0)

	# Assignment indicator: colored rings for each assigned stagehand
	var all_assigned := assigned_stagehands
	if all_assigned.size() > 0:
		var base_radius: float = max(prop_size.x, prop_size.y) / 2.0 + 4.0
		for i in range(all_assigned.size()):
			var sh: CharacterBody2D = all_assigned[i]
			draw_arc(Vector2.ZERO, base_radius + i * 3.0, 0, TAU, 32, sh.stagehand_color, 2.0)


func set_target(pos: Vector2, rot: float = 0.0) -> void:
	_base_target_position = pos
	target_rotation = rot
	_show_ghost = true
	queue_redraw()


func show_target_ghost(show_ghost: bool) -> void:
	_show_ghost = show_ghost
	queue_redraw()


func is_at_target() -> bool:
	var pos_diff: float = (global_position - target_position).length()
	var rot_diff: float = abs(rad_to_deg(rotation) - target_rotation)

	return pos_diff <= _position_tolerance and rot_diff <= _rotation_tolerance


func check_target_reached() -> void:
	if current_state == PropState.PLACED and is_at_target():
		current_state = PropState.IN_POSITION
		_show_ghost = false
		queue_redraw()
		reached_target.emit()


# =============================================================================
# MOVEMENT PLAN — leg-based planning
# =============================================================================

func add_leg(destination: Variant = null) -> int:
	var leg: Dictionary = { "stagehands": [] as Array[CharacterBody2D] }
	if destination != null:
		leg["destination"] = destination as Vector2
	movement_plan.append(leg)
	queue_redraw()
	return movement_plan.size() - 1


func add_stagehand_to_leg(leg_index: int, stagehand: CharacterBody2D) -> void:
	if leg_index < 0 or leg_index >= movement_plan.size():
		return
	var leg_stagehands: Array = movement_plan[leg_index].stagehands
	if stagehand not in leg_stagehands:
		leg_stagehands.append(stagehand)
		queue_redraw()


func remove_stagehand_from_leg(leg_index: int, stagehand: CharacterBody2D) -> void:
	if leg_index < 0 or leg_index >= movement_plan.size():
		return
	movement_plan[leg_index].stagehands.erase(stagehand)
	# Remove leg if empty of stagehands and it's the last leg
	if movement_plan[leg_index].stagehands.is_empty() and leg_index == movement_plan.size() - 1:
		movement_plan.remove_at(leg_index)
	queue_redraw()


func remove_stagehand_from_all_legs(stagehand: CharacterBody2D) -> void:
	for i in range(movement_plan.size() - 1, -1, -1):
		movement_plan[i].stagehands.erase(stagehand)
		# Clean up empty trailing legs
		if movement_plan[i].stagehands.is_empty() and i == movement_plan.size() - 1:
			movement_plan.remove_at(i)
	queue_redraw()


func get_current_leg() -> Dictionary:
	if current_leg_index >= 0 and current_leg_index < movement_plan.size():
		return movement_plan[current_leg_index]
	return {}


func get_leg(index: int) -> Dictionary:
	if index >= 0 and index < movement_plan.size():
		return movement_plan[index]
	return {}


func get_leg_count() -> int:
	return movement_plan.size()


func advance_leg() -> void:
	var old_index := current_leg_index
	current_leg_index += 1
	leg_completed.emit(old_index)
	if current_leg_index >= movement_plan.size():
		plan_completed.emit()


func get_pickup_position() -> Vector2:
	if current_leg_index <= 0:
		return global_position
	# For subsequent legs, pickup is at the previous leg's destination
	var prev_leg: Dictionary = movement_plan[current_leg_index - 1]
	if prev_leg.has("destination"):
		return prev_leg.destination
	return global_position


func get_all_assigned_stagehands() -> Array[CharacterBody2D]:
	var result: Array[CharacterBody2D] = []
	for leg in movement_plan:
		for sh in leg.stagehands:
			if sh not in result:
				result.append(sh)
	return result


func has_plan() -> bool:
	for leg in movement_plan:
		if leg.stagehands.size() > 0 and leg.has("destination"):
			return true
	return false


func clear_plan() -> void:
	movement_plan.clear()
	current_leg_index = -1
	queue_redraw()


func get_active_leg_index() -> int:
	## Returns the index of the leg that doesn't yet have a destination, or -1
	for i in range(movement_plan.size()):
		if not movement_plan[i].has("destination"):
			return i
	return -1


func get_leg_stagehand_strength(leg_index: int) -> int:
	if leg_index < 0 or leg_index >= movement_plan.size():
		return 0
	var total: int = 0
	for sh in movement_plan[leg_index].stagehands:
		total += sh.strength
	return total


func is_stagehand_in_any_leg(stagehand: CharacterBody2D) -> bool:
	for leg in movement_plan:
		if stagehand in leg.stagehands:
			return true
	return false


func find_leg_with_stagehand(stagehand: CharacterBody2D) -> int:
	## Returns the index of the first leg containing this stagehand, or -1
	for i in range(movement_plan.size()):
		if stagehand in movement_plan[i].stagehands:
			return i
	return -1


func find_incomplete_leg_with_stagehand(stagehand: CharacterBody2D) -> int:
	## Returns index of first leg without destination that contains this stagehand, or -1
	for i in range(movement_plan.size()):
		if stagehand in movement_plan[i].stagehands and not movement_plan[i].has("destination"):
			return i
	return -1


# =============================================================================
# CARRIER MANAGEMENT — cooperative carrying
# =============================================================================

func get_carrier_strength() -> int:
	var total: int = 0
	for sh in carriers:
		total += sh.strength
	return total


func can_be_lifted() -> bool:
	return get_carrier_strength() >= weight


func get_lead_carrier() -> CharacterBody2D:
	if carriers.is_empty():
		return null
	return carriers[0]


func add_carrier(stagehand: CharacterBody2D) -> void:
	if stagehand not in carriers:
		carriers.append(stagehand)


func remove_carrier(stagehand: CharacterBody2D) -> void:
	carriers.erase(stagehand)


func on_picked_up(stagehand: CharacterBody2D) -> void:
	add_carrier(stagehand)
	current_state = PropState.BEING_CARRIED
	# Disable obstacle avoidance while being carried
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = false
	picked_up.emit(stagehand)


func on_put_down(at_pos: Vector2) -> void:
	carriers.clear()
	current_state = PropState.PLACED
	# Re-enable obstacle avoidance when put down
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = true
	put_down.emit(at_pos)
	check_target_reached()


func get_grab_position() -> Vector2:
	return global_position
