extends Node2D
## Main game session controller - manages stage, entities, and interaction

const StagehandRookieScene := preload("res://scenes/entities/stagehand_rookie.tscn")
const StagehandRegularScene := preload("res://scenes/entities/stagehand_regular.tscn")
const StagehandStrongScene := preload("res://scenes/entities/stagehand_strong.tscn")
const PropScene := preload("res://scenes/entities/prop_base.tscn")

@onready var stage_layout: Node2D = $StageLayout
@onready var pathfinding: Node = $PathfindingManager
@onready var camera: Camera2D = $Camera2D
@onready var stagehands_container: Node2D = $StageLayout/Stagehands
@onready var props_container: Node2D = $StageLayout/Props
@onready var grid_overlay: Node2D = $StageLayout/GridOverlay

var selected_stagehand: CharacterBody2D = null
var stagehands: Array[CharacterBody2D] = []
var props: Array[StaticBody2D] = []

# Cell size in pixels (must match grid_system and pathfinding)
var _cell_size: float = 50.0

# Wing section height (total wing height 500 / 3 sections)
const WING_SECTION_HEIGHT := 166.667

# Stage left wing sections (1st=closest to audience, 3rd=deepest backstage)
const STAGE_LEFT_1ST := Rect2(-500, -100, 150, 166.667)
const STAGE_LEFT_2ND := Rect2(-500, 66.667, 150, 166.667)
const STAGE_LEFT_3RD := Rect2(-500, 233.333, 150, 166.667)

# Stage right wing sections
const STAGE_RIGHT_1ST := Rect2(350, -100, 150, 166.667)
const STAGE_RIGHT_2ND := Rect2(350, 66.667, 150, 166.667)
const STAGE_RIGHT_3RD := Rect2(350, 233.333, 150, 166.667)

# Full wing bounds (union of all 3 sections per side)
const STAGE_LEFT_RECT := Rect2(-500, -100, 150, 500)
const STAGE_RIGHT_RECT := Rect2(350, -100, 150, 500)

# Track stagehands that should pick up a prop when they arrive
var _pending_pick_up: Dictionary = {}  # stagehand -> prop
# Track stagehands that should put down their prop when they arrive
var _pending_put_down: Dictionary = {}  # stagehand -> true


func _ready() -> void:
	# Initialize pathfinding
	pathfinding.initialize(Vector2i(20, 16), _cell_size)

	# Focus camera on stage center
	camera.focus_on(Vector2.ZERO)

	# Spawn initial stagehands for testing
	_spawn_test_entities()


func _spawn_test_entities() -> void:
	# Stage left stagehands - one per wing section
	_spawn_stagehand(StagehandRookieScene, _section_center(STAGE_LEFT_1ST), Color.LIGHT_BLUE)
	_spawn_stagehand(StagehandRegularScene, _section_center(STAGE_LEFT_2ND), Color.BLUE)
	_spawn_stagehand(StagehandStrongScene, _section_center(STAGE_LEFT_3RD), Color.DARK_BLUE)

	# Stage right stagehands - one per wing section
	_spawn_stagehand(StagehandRookieScene, _section_center(STAGE_RIGHT_1ST), Color.LIGHT_CORAL)
	_spawn_stagehand(StagehandRegularScene, _section_center(STAGE_RIGHT_2ND), Color.CORAL)
	_spawn_stagehand(StagehandStrongScene, _section_center(STAGE_RIGHT_3RD), Color.DARK_RED)

	# Stage left props - one per wing section
	_spawn_prop(_section_center(STAGE_LEFT_1ST) + Vector2(0, 30), Vector2(-50, -200), Color.SADDLE_BROWN, "Chair", 1)
	_spawn_prop(_section_center(STAGE_LEFT_2ND) + Vector2(0, 30), Vector2(-150, 0), Color.ANTIQUE_WHITE, "Dresser", 2)
	_spawn_prop(_section_center(STAGE_LEFT_3RD) + Vector2(0, 30), Vector2(-250, 200), Color.DARK_RED, "Piano", 3)

	# Stage right props - one per wing section
	_spawn_prop(_section_center(STAGE_RIGHT_1ST) + Vector2(0, 30), Vector2(50, -200), Color.NAVY_BLUE, "Stool", 1)
	_spawn_prop(_section_center(STAGE_RIGHT_2ND) + Vector2(0, 30), Vector2(150, 0), Color.FOREST_GREEN, "Couch", 2)
	_spawn_prop(_section_center(STAGE_RIGHT_3RD) + Vector2(0, 30), Vector2(250, 200), Color.PURPLE, "Bookshelf", 3)


func _spawn_stagehand(scene: PackedScene, pos: Vector2, color: Color) -> void:
	var stagehand: CharacterBody2D = scene.instantiate() as CharacterBody2D
	stagehand.stagehand_color = color
	stagehand.global_position = pos
	stagehand.set_pathfinding(pathfinding)
	stagehand.selected.connect(_on_stagehand_selected)
	stagehand.reached_destination.connect(_on_stagehand_arrived.bind(stagehand))
	stagehands_container.add_child(stagehand)
	stagehands.append(stagehand)
	print("Spawned ", stagehand.stagehand_name, " (str:", stagehand.strength, ") at: ", stagehand.global_position)


func _spawn_prop(pos: Vector2, target: Vector2, color: Color, prop_name: String, weight: int = 1) -> void:
	var prop: StaticBody2D = PropScene.instantiate() as StaticBody2D
	prop.prop_name = prop_name
	prop.prop_color = color
	prop.weight = weight
	prop.global_position = pos
	props_container.add_child(prop)
	props.append(prop)
	prop.set_target(target)
	print("Spawned prop ", prop_name, " (weight:", weight, ") at: ", prop.global_position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click()


func _handle_click() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	print("Click at world pos: ", world_pos)

	# Check if clicked on stagehand
	for stagehand in stagehands:
		print("  Stagehand at: ", stagehand.global_position, " distance: ", world_pos.distance_to(stagehand.global_position))
		if world_pos.distance_to(stagehand.global_position) < stagehand.stagehand_radius + 5.0:
			_select_stagehand(stagehand)
			return

	# Clicked on nothing - deselect
	_deselect_all()


func _handle_right_click() -> void:
	if not selected_stagehand:
		return

	var world_pos: Vector2 = get_global_mouse_position()

	# Check if clicked on prop
	for prop in props:
		var half_size: Vector2 = prop.prop_size / 2.0
		var prop_rect: Rect2 = Rect2(prop.global_position - half_size, prop.prop_size)
		if prop_rect.has_point(world_pos):
			if selected_stagehand:
				_pending_pick_up[selected_stagehand] = prop
				print("Stagehand will pick up prop: ", prop.prop_name)

	# If carrying prop, mark for put down when arrived
	if selected_stagehand.current_state == selected_stagehand.State.CARRYING:
		_pending_put_down[selected_stagehand] = true

	# Move to position
	selected_stagehand.move_to(world_pos)


func _try_pickup_prop(stagehand: CharacterBody2D, prop: StaticBody2D) -> void:
	if stagehand.carried_prop != null:
		return  # Already carrying something

	# Check if close enough
	var distance: float = stagehand.global_position.distance_to(prop.global_position)
	if distance > 75.0:
		# Move to prop first, then pick up
		stagehand.move_to(prop.global_position)
		return

	# Try to pick up the prop (may fail if too heavy)
	if stagehand.pick_up(prop):
		prop.on_picked_up(stagehand)


func _select_stagehand(stagehand: CharacterBody2D) -> void:
	_deselect_all()
	selected_stagehand = stagehand
	stagehand.set_selected(true)


func _deselect_all() -> void:
	if selected_stagehand:
		selected_stagehand.set_selected(false)
		selected_stagehand = null


func _on_stagehand_selected(stagehand: CharacterBody2D) -> void:
	if stagehand != selected_stagehand:
		_deselect_all()
		selected_stagehand = stagehand


func _on_stagehand_arrived(stagehand: CharacterBody2D) -> void:
	# Check if this stagehand should pick up a prop
	if _pending_pick_up.has(stagehand):
		var prop = _pending_pick_up[stagehand]
		_try_pickup_prop(stagehand, prop)
		_pending_pick_up.erase(stagehand)

	# Check if this stagehand should put down their prop
	if _pending_put_down.has(stagehand):
		_pending_put_down.erase(stagehand)
		if stagehand.carried_prop != null:
			var prop: Node2D = stagehand.put_down(props_container)
			if prop:
				prop.on_put_down(prop.global_position)
			# Move to nearest wing after putting down
			_return_to_nearest_wing(stagehand)


func _section_center(rect: Rect2) -> Vector2:
	return rect.position + rect.size / 2.0


func _get_nearest_wing_position(from_pos: Vector2) -> Vector2:
	var left_center_x: float = STAGE_LEFT_RECT.position.x + STAGE_LEFT_RECT.size.x / 2.0
	var right_center_x: float = STAGE_RIGHT_RECT.position.x + STAGE_RIGHT_RECT.size.x / 2.0
	var left_dist: float = abs(from_pos.x - left_center_x)
	var right_dist: float = abs(from_pos.x - right_center_x)

	# Clamp Y to wing bounds
	var wing_rect: Rect2 = STAGE_LEFT_RECT if left_dist < right_dist else STAGE_RIGHT_RECT
	var target_x: float = wing_rect.position.x + wing_rect.size.x / 2.0
	var target_y: float = clamp(from_pos.y, wing_rect.position.y, wing_rect.position.y + wing_rect.size.y)

	return Vector2(target_x, target_y)


func _return_to_nearest_wing(stagehand: CharacterBody2D) -> void:
	var wing_pos: Vector2 = _get_nearest_wing_position(stagehand.global_position)
	stagehand.move_to(wing_pos)
