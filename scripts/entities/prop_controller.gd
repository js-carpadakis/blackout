extends StaticBody2D
## Controls a single prop that can be moved by stagehands

signal picked_up(by_stagehand: CharacterBody2D)
signal put_down(at_position: Vector2)
signal reached_target

enum PropState { STORED, BEING_CARRIED, PLACED, IN_POSITION }

@export var prop_name: String = "Prop"
@export var weight: int = 1  # Number of stagehands needed
@export var grid_footprint: Vector2i = Vector2i(1, 1)
@export var prop_color: Color = Color.SADDLE_BROWN
@export var prop_size: Vector2 = Vector2(40, 40)

var current_state: PropState = PropState.STORED
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0
var carrier: CharacterBody2D = null
var assigned_stagehand: CharacterBody2D = null

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

	# Assignment indicator: colored ring using assigned stagehand's color
	if assigned_stagehand:
		var ring_radius: float = max(prop_size.x, prop_size.y) / 2.0 + 4.0
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 32, assigned_stagehand.stagehand_color, 2.0)


func set_target(pos: Vector2, rot: float = 0.0) -> void:
	target_position = pos
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


func on_picked_up(stagehand: CharacterBody2D) -> void:
	carrier = stagehand
	current_state = PropState.BEING_CARRIED
	# Disable obstacle avoidance while being carried
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = false
	picked_up.emit(stagehand)


func on_put_down(at_pos: Vector2) -> void:
	carrier = null
	current_state = PropState.PLACED
	# Re-enable obstacle avoidance when put down
	if _nav_obstacle:
		_nav_obstacle.avoidance_enabled = true
	put_down.emit(at_pos)
	check_target_reached()


func get_grab_position() -> Vector2:
	return global_position
