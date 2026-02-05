extends CharacterBody2D
class_name StagehandController
## Controls a single stagehand character

signal reached_destination
signal task_completed
signal selected(stagehand: CharacterBody2D)

enum State { IDLE, MOVING, PICKING_UP, CARRYING, PUTTING_DOWN, WAITING }

@export var movement_speed: float = 150.0
@export var rotation_speed: float = 10.0
@export var stagehand_color: Color = Color.BLUE
@export var stagehand_radius: float = 15.0
@export var strength: int = 1  # Weight capacity - how heavy a prop this stagehand can carry
@export var stagehand_name: String = "Stagehand"

var current_state: State = State.IDLE
var current_path: PackedVector2Array = []
var path_index: int = 0
var carried_props: Array[Node2D] = []
var is_selected: bool = false

# Planning phase: props this stagehand is assigned to (across any legs)
var assigned_props: Array[StaticBody2D] = []
var has_assignment: bool:
	get: return assigned_props.size() > 0

var _pathfinding: Node  # Reference to PathfindingManager
var _target_position: Vector2
var _facing_angle: float = 0.0  # Radians, 0 = right, PI/2 = down
var speed_override: float = 0.0  # When > 0, overrides normal speed (for cooperative carries)


func _ready() -> void:
	# Ensure we're visible and will be drawn
	show()
	z_index = 10  # Draw on top of other elements
	queue_redraw()
	print("Stagehand ready, visible: ", visible, " position: ", global_position)


func _draw() -> void:
	# Main body (circle)
	draw_circle(Vector2.ZERO, stagehand_radius, stagehand_color)

	# Direction indicator (triangle pointing in facing direction)
	var tip_offset: float = stagehand_radius + 8.0
	var base_offset: float = stagehand_radius - 2.0
	var half_width: float = 6.0

	var tip: Vector2 = Vector2(tip_offset, 0).rotated(_facing_angle)
	var base_left: Vector2 = Vector2(base_offset, -half_width).rotated(_facing_angle)
	var base_right: Vector2 = Vector2(base_offset, half_width).rotated(_facing_angle)

	var points: PackedVector2Array = PackedVector2Array([tip, base_left, base_right])
	draw_colored_polygon(points, stagehand_color.lightened(0.3))

	# Assignment indicator (dashed ring)
	if has_assignment:
		draw_arc(Vector2.ZERO, stagehand_radius + 3.0, 0, TAU, 32, Color.GREEN, 2.0)

	# Selection indicator (ring)
	if is_selected:
		draw_arc(Vector2.ZERO, stagehand_radius + 5.0, 0, TAU, 32, Color.YELLOW, 3.0)


func _physics_process(delta: float) -> void:
	match current_state:
		State.MOVING, State.CARRYING:
			_process_movement(delta)
		State.IDLE, State.WAITING:
			pass


func _process_movement(delta: float) -> void:
	if current_path.is_empty() or path_index >= current_path.size():
		_arrive_at_destination()
		return

	var target: Vector2 = current_path[path_index]
	var direction: Vector2 = target - global_position
	var is_final_waypoint: bool = path_index == current_path.size() - 1

	# Cone tip offset from center
	var tip_offset: float = stagehand_radius + 8.0

	if direction.length() < 5.0 + (tip_offset if is_final_waypoint else 0.0):
		if is_final_waypoint:
			# Stop so cone tip is at target (center is behind by tip_offset)
			var offset_dir: Vector2 = direction.normalized() if direction.length() > 0.1 else Vector2.RIGHT.rotated(_facing_angle)
			global_position = target - offset_dir * tip_offset
			_arrive_at_destination()
		else:
			path_index += 1
		return

	# Rotate to face movement direction
	var target_angle: float = direction.angle()
	_facing_angle = lerp_angle(_facing_angle, target_angle, rotation_speed * delta)
	queue_redraw()

	# Move — slower when carrying, scaled by load
	var speed: float = movement_speed
	if speed_override > 0.0:
		speed = speed_override
	elif current_state == State.CARRYING and carried_props.size() > 0:
		var load_ratio: float = float(get_carried_weight()) / float(strength)
		speed *= lerpf(0.9, 0.5, clampf(load_ratio, 0.0, 1.0))

	velocity = direction.normalized() * speed
	move_and_slide()


func _arrive_at_destination() -> void:
	velocity = Vector2.ZERO
	current_path.clear()
	path_index = 0

	if current_state == State.MOVING:
		current_state = State.IDLE
	elif current_state == State.CARRYING:
		# Stay in carrying state until all props put down
		pass

	reached_destination.emit()


func set_pathfinding(pathfinding_node: Node) -> void:
	_pathfinding = pathfinding_node


func move_to(target_world_pos: Vector2) -> void:
	if not _pathfinding:
		push_error("Pathfinding not set for stagehand")
		return

	current_path = _pathfinding.find_path(global_position, target_world_pos)

	# Skip first waypoint (starting cell) since we're already there
	if current_path.size() > 1:
		path_index = 1
	else:
		path_index = 0

	if current_path.is_empty():
		# Already at destination or no valid path — signal arrival next frame
		_arrive_at_destination.call_deferred()
		return

	if current_state == State.CARRYING:
		pass  # Stay carrying
	elif current_state == State.WAITING:
		current_state = State.MOVING
	else:
		current_state = State.MOVING


func move_along_path(path: PackedVector2Array) -> void:
	current_path = path
	path_index = 0

	if current_path.size() > 0:
		if current_state != State.CARRYING:
			current_state = State.MOVING


func stop() -> void:
	current_path.clear()
	path_index = 0
	velocity = Vector2.ZERO
	if current_state != State.CARRYING:
		current_state = State.IDLE


# =============================================================================
# CARRYING — multi-prop support
# =============================================================================

func get_carried_weight() -> int:
	var total: int = 0
	for prop in carried_props:
		if prop and prop.get("weight") != null:
			total += prop.weight
	return total


func get_remaining_strength() -> int:
	return strength - get_carried_weight()


func can_carry(prop: Node2D) -> bool:
	if prop.get("weight") != null:
		return get_remaining_strength() >= prop.weight
	return true


func is_carrying(prop: Node2D) -> bool:
	return prop in carried_props


func pick_up(prop: Node2D) -> bool:
	if is_carrying(prop):
		return false

	if not can_carry(prop):
		print(stagehand_name, " (remaining str ", get_remaining_strength(), ") cannot lift ", prop.prop_name, " (weight ", prop.weight, ")")
		return false

	return _do_pick_up(prop)


func force_pick_up(prop: Node2D) -> bool:
	## Pick up without individual strength check (for cooperative carries).
	if is_carrying(prop):
		return false
	return _do_pick_up(prop)


func _do_pick_up(prop: Node2D) -> bool:
	current_state = State.PICKING_UP

	# Attach prop to stagehand
	if prop.get_parent():
		prop.get_parent().remove_child(prop)
	add_child(prop)
	carried_props.append(prop)
	_reposition_carried_props()

	current_state = State.CARRYING
	return true


func put_down_prop(prop: Node2D, target_parent: Node2D = null) -> Node2D:
	if not is_carrying(prop):
		return null

	current_state = State.PUTTING_DOWN
	carried_props.erase(prop)

	# Place prop at cone tip position (where the stagehand is "pointing")
	var tip_offset: float = stagehand_radius + 8.0
	var tip_position: Vector2 = global_position + Vector2(tip_offset, 0).rotated(_facing_angle)

	remove_child(prop)
	if target_parent:
		target_parent.add_child(prop)
		prop.global_position = tip_position
	else:
		get_parent().add_child(prop)
		prop.global_position = tip_position

	if carried_props.size() > 0:
		current_state = State.CARRYING
		_reposition_carried_props()
	else:
		current_state = State.IDLE

	return prop


func _reposition_carried_props() -> void:
	for i in range(carried_props.size()):
		carried_props[i].position = Vector2(0, -30 - i * 15)


# =============================================================================
# ASSIGNMENT TRACKING
# =============================================================================

func add_assigned_prop(prop: StaticBody2D) -> void:
	if prop not in assigned_props:
		assigned_props.append(prop)
		queue_redraw()


func remove_assigned_prop(prop: StaticBody2D) -> void:
	assigned_props.erase(prop)
	queue_redraw()


func clear_assignment() -> void:
	assigned_props.clear()
	queue_redraw()


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()
	if value:
		selected.emit(self)
