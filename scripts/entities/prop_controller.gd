extends StaticBody2D
## Controls a single prop that can be moved by stagehands

signal picked_up(by_stagehand: CharacterBody2D)
signal put_down(at_position: Vector2)
signal reached_target
signal leg_completed(leg_index: int)
signal plan_completed

enum PropState { STORED, BEING_CARRIED, PLACED, IN_POSITION, BEING_PUSHED }
enum PropShape { RECT, CIRCLE, L_SHAPE }
enum PropTrait { FRAGILE, AWKWARD, WHEELED }

@export var prop_name: String = "Prop"
@export var weight: int = 1  # Combined strength needed to carry
@export var grid_footprint: Vector2i = Vector2i(1, 1)
@export var prop_color: Color = Color.SADDLE_BROWN
@export var prop_size: Vector2 = Vector2(60, 60)
@export var shape: PropShape = PropShape.RECT
@export var size_override: Vector2 = Vector2.ZERO  # When non-zero, skip weight-to-size auto-sizing

var traits: Array[int] = []

var current_state: PropState = PropState.STORED
var _base_target_position: Vector2 = Vector2.ZERO  # Original target from set_target()

# Push state (for wheeled props)
var _push_stagehand: CharacterBody2D = null
var _push_pivot: Vector2 = Vector2.ZERO  # World position of pivot end
var _push_destination: Vector2 = Vector2.ZERO
enum PushPhase { ROTATING, SLIDING, FINAL_ROTATING }
var _push_phase: PushPhase = PushPhase.ROTATING
var _push_speed: float = 90.0
var _push_rotation_speed: float = 2.0  # rad/s
var _push_paused: bool = false
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
	# Set prop size: use override if provided, else fall through to weight-based
	if size_override != Vector2.ZERO:
		prop_size = size_override
	else:
		match weight:
			1:
				prop_size = Vector2(45, 45)
			2:
				prop_size = Vector2(75, 75)
			3:
				prop_size = Vector2(105, 105)
			_:
				prop_size = Vector2(45 + weight * 22, 45 + weight * 22)

	# Update collision shape size to match prop_size
	var col_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if col_shape and col_shape.shape is RectangleShape2D:
		(col_shape.shape as RectangleShape2D).size = prop_size

	# Update navigation obstacle radius to match prop size
	if _nav_obstacle:
		_nav_obstacle.radius = max(prop_size.x, prop_size.y) / 2.0 + 8.0

	queue_redraw()


var is_being_dragged: bool = false

func _process(delta: float) -> void:
	# Redraw while being moved to keep ghost at fixed world position
	if _show_ghost and (current_state == PropState.BEING_CARRIED or current_state == PropState.BEING_PUSHED or is_being_dragged):
		queue_redraw()

	# Drive push animation (skip when paused)
	if current_state == PropState.BEING_PUSHED and not _push_paused:
		match _push_phase:
			PushPhase.ROTATING:
				_process_push_rotate(delta)
			PushPhase.SLIDING:
				_process_push_slide(delta)
			PushPhase.FINAL_ROTATING:
				_process_push_final_rotate(delta)


func _draw() -> void:
	# Draw target ghost at fixed world position with target rotation
	if _show_ghost:
		# Convert world offset to local draw coordinates (accounting for node rotation)
		var world_offset: Vector2 = target_position - global_position
		var local_offset: Vector2 = world_offset.rotated(-rotation)
		var ghost_local_rot: float = target_rotation - rotation
		var ghost_color: Color = Color(prop_color.r, prop_color.g, prop_color.b, 0.3)
		var ghost_border: Color = prop_color.darkened(0.2)
		draw_set_transform(local_offset, ghost_local_rot)
		_draw_shape(Vector2.ZERO, ghost_color, ghost_border)
		draw_set_transform(Vector2.ZERO)  # Reset

	# Main prop
	_draw_shape(Vector2.ZERO, prop_color, prop_color.darkened(0.3))

	# Assignment indicator: colored rings for each assigned stagehand
	var all_assigned := assigned_stagehands
	if all_assigned.size() > 0:
		var base_radius: float = max(prop_size.x, prop_size.y) / 2.0 + 4.0
		for i in range(all_assigned.size()):
			var sh: CharacterBody2D = all_assigned[i]
			draw_arc(Vector2.ZERO, base_radius + i * 3.0, 0, TAU, 32, sh.stagehand_color, 2.0)


func _draw_shape(center_offset: Vector2, fill_color: Color, border_color: Color) -> void:
	match shape:
		PropShape.RECT:
			var rect: Rect2 = Rect2(center_offset - prop_size / 2.0, prop_size)
			draw_rect(rect, fill_color)
			draw_rect(rect, border_color, false, 2.0)
		PropShape.CIRCLE:
			var radius: float = min(prop_size.x, prop_size.y) / 2.0
			draw_circle(center_offset, radius, fill_color)
			draw_arc(center_offset, radius, 0, TAU, 32, border_color, 2.0)
		PropShape.L_SHAPE:
			# L-shape: two overlapping rectangles
			# Vertical part: left half, full height
			var vert_size: Vector2 = Vector2(prop_size.x * 0.5, prop_size.y)
			var vert_pos: Vector2 = center_offset + Vector2(-prop_size.x / 2.0, -prop_size.y / 2.0)
			var vert_rect: Rect2 = Rect2(vert_pos, vert_size)
			draw_rect(vert_rect, fill_color)
			draw_rect(vert_rect, border_color, false, 2.0)
			# Horizontal part: full width, bottom half
			var horiz_size: Vector2 = Vector2(prop_size.x, prop_size.y * 0.5)
			var horiz_pos: Vector2 = center_offset + Vector2(-prop_size.x / 2.0, 0.0)
			var horiz_rect: Rect2 = Rect2(horiz_pos, horiz_size)
			draw_rect(horiz_rect, fill_color)
			draw_rect(horiz_rect, border_color, false, 2.0)


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
	var rot_diff: float = abs(rad_to_deg(angle_difference(rotation, target_rotation)))

	return pos_diff <= _position_tolerance and rot_diff <= _rotation_tolerance


func check_target_reached() -> void:
	if current_state == PropState.PLACED and is_at_target():
		current_state = PropState.IN_POSITION
		_show_ghost = false
		queue_redraw()
		reached_target.emit()


# =============================================================================
# TRAITS
# =============================================================================

func get_effective_weight() -> int:
	if PropTrait.AWKWARD in traits:
		return weight + 1
	return weight


func get_required_strength() -> int:
	if PropTrait.WHEELED in traits:
		return 1
	return get_effective_weight()


func get_carry_speed_modifier() -> float:
	if PropTrait.FRAGILE in traits:
		return 0.6
	return 1.0


func get_trait_labels() -> PackedStringArray:
	var labels: PackedStringArray = []
	for t in traits:
		match t:
			PropTrait.FRAGILE:
				labels.append("fragile")
			PropTrait.AWKWARD:
				labels.append("awkward")
			PropTrait.WHEELED:
				labels.append("wheeled")
	return labels


func is_wheeled() -> bool:
	return PropTrait.WHEELED in traits


# =============================================================================
# WHEELED PUSH MECHANIC
# =============================================================================

func begin_push(stagehand: CharacterBody2D, destination: Vector2, speed: float) -> void:
	_push_stagehand = stagehand
	_push_destination = destination
	_push_speed = speed
	current_state = PropState.BEING_PUSHED

	# Disable obstacle avoidance while being pushed
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = false

	# Determine pivot: choose the end of the prop (along its longest axis) that
	# requires the least rotation to align the prop toward the destination.
	var half_extent: float = max(prop_size.x, prop_size.y) / 2.0
	var forward: Vector2 = Vector2(half_extent, 0).rotated(rotation)

	var end_a: Vector2 = global_position + forward
	var end_b: Vector2 = global_position - forward

	# Pick whichever end, when used as pivot, requires least rotation
	var angle_a: float = _pivot_angle_needed(end_a, end_b, destination)
	var angle_b: float = _pivot_angle_needed(end_b, end_a, destination)

	if angle_a <= angle_b:
		_push_pivot = end_a
	else:
		_push_pivot = end_b

	_push_phase = PushPhase.ROTATING

	# Position stagehand at the push end (opposite of pivot)
	var push_end: Vector2 = global_position * 2.0 - _push_pivot
	_push_stagehand.global_position = push_end

	queue_redraw()


func _pivot_angle_needed(pivot: Vector2, push_end: Vector2, destination: Vector2) -> float:
	## Angle the prop must rotate around `pivot` so that push_end->pivot direction
	## points toward destination.
	var current_dir: Vector2 = (pivot - push_end).normalized()
	var desired_dir: Vector2 = (destination - pivot).normalized()
	return abs(current_dir.angle_to(desired_dir))


func _process_push_rotate(delta: float) -> void:
	if not _push_stagehand:
		return

	# Desired direction: from pivot toward destination
	var push_end: Vector2 = global_position * 2.0 - _push_pivot
	var current_dir: Vector2 = (_push_pivot - push_end).normalized()
	var desired_dir: Vector2 = (_push_destination - _push_pivot).normalized()

	var angle_diff: float = current_dir.angle_to(desired_dir)

	# Check if aligned enough to transition to sliding
	if abs(angle_diff) < 0.05:
		_push_phase = PushPhase.SLIDING
		return

	# Rotate around pivot
	var rotate_amount: float = sign(angle_diff) * min(_push_rotation_speed * delta, abs(angle_diff))

	# Move center around pivot
	var offset_from_pivot: Vector2 = global_position - _push_pivot
	offset_from_pivot = offset_from_pivot.rotated(rotate_amount)
	global_position = _push_pivot + offset_from_pivot
	rotation += rotate_amount

	# Update pivot position (it stays at the same end of the prop)
	var half_extent: float = max(prop_size.x, prop_size.y) / 2.0
	var forward: Vector2 = Vector2(half_extent, 0).rotated(rotation)
	# Pivot is whichever end is closest to old pivot
	var end_a: Vector2 = global_position + forward
	var end_b: Vector2 = global_position - forward
	if end_a.distance_to(_push_pivot) < end_b.distance_to(_push_pivot):
		_push_pivot = end_a
	else:
		_push_pivot = end_b

	# Position stagehand at push end
	push_end = global_position * 2.0 - _push_pivot
	_push_stagehand.global_position = push_end

	queue_redraw()


func _process_push_slide(delta: float) -> void:
	if not _push_stagehand:
		return

	var direction: Vector2 = _push_destination - global_position
	var dist: float = direction.length()

	if dist < 10.0:
		global_position = _push_destination
		# On the final leg, rotate in place to match target rotation
		if current_leg_index >= get_leg_count() - 1:
			var rot_diff: float = angle_difference(rotation, target_rotation)
			if abs(rot_diff) > 0.05:
				_push_phase = PushPhase.FINAL_ROTATING
				return
		_finish_push()
		return

	var move_amount: float = _push_speed * delta
	if move_amount > dist:
		move_amount = dist

	var move_vec: Vector2 = direction.normalized() * move_amount
	global_position += move_vec
	_push_pivot += move_vec

	# Position stagehand at push end (behind the prop)
	var push_end: Vector2 = global_position * 2.0 - _push_pivot
	_push_stagehand.global_position = push_end

	queue_redraw()


func _process_push_final_rotate(delta: float) -> void:
	if not _push_stagehand:
		return

	var rot_diff: float = angle_difference(rotation, target_rotation)
	if abs(rot_diff) < 0.05:
		rotation = target_rotation
		_finish_push()
		return

	var rotate_amount: float = sign(rot_diff) * min(_push_rotation_speed * delta, abs(rot_diff))
	rotation += rotate_amount

	# Keep stagehand at the push end as prop rotates in place
	var half_extent: float = max(prop_size.x, prop_size.y) / 2.0
	var forward: Vector2 = Vector2(half_extent, 0).rotated(rotation)
	_push_pivot = global_position + forward
	_push_stagehand.global_position = global_position - forward

	queue_redraw()


func _finish_push() -> void:
	current_state = PropState.PLACED
	# Re-enable obstacle avoidance
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = true

	var stagehand := _push_stagehand
	_push_stagehand = null
	queue_redraw()

	if stagehand:
		stagehand.on_push_completed()

	check_target_reached()


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


func reset_for_planning() -> void:
	clear_plan()
	_show_ghost = false
	current_state = PropState.STORED
	carriers.clear()
	_push_stagehand = null
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
	return get_carrier_strength() >= get_required_strength()


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
