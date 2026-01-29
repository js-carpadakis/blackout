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
var _grid_size: Vector2i = Vector2i(32, 20)

# Half-ellipse stage shape: flat edge at bottom (backstage), curve at top (audience)
# Center of full ellipse at (0, 500), semi-axis x=800, semi-axis y=1000
# Grid covers [-800, 800] x [-500, 500]
const ELLIPSE_CENTER_Y := 500.0
const ELLIPSE_A := 800.0   # semi-axis x (half of 1600)
const ELLIPSE_B := 1000.0  # semi-axis y (full 1000 depth)

# Wing sections: 150px wide, 600px tall (3 sections of 200px), outside the ellipse
const WING_WIDTH := 150.0
const WING_SECTION_HEIGHT := 200.0

# Stage left wing sections (1st=closest to audience/top, 3rd=deepest backstage/bottom)
const STAGE_LEFT_1ST := Rect2(-950, -100, 150, 200)
const STAGE_LEFT_2ND := Rect2(-950, 100, 150, 200)
const STAGE_LEFT_3RD := Rect2(-950, 300, 150, 200)

# Stage right wing sections
const STAGE_RIGHT_1ST := Rect2(800, -100, 150, 200)
const STAGE_RIGHT_2ND := Rect2(800, 100, 150, 200)
const STAGE_RIGHT_3RD := Rect2(800, 300, 150, 200)

# Full wing bounds (union of all 3 sections per side)
const STAGE_LEFT_RECT := Rect2(-950, -100, 150, 600)
const STAGE_RIGHT_RECT := Rect2(800, -100, 150, 600)

# Backstage: 2000x600 rectangle overlapping wings and bottom of stage
const BACKSTAGE_RECT := Rect2(-1000, -100, 2000, 600)

# Track stagehands that should pick up a prop when they arrive
var _pending_pick_up: Dictionary = {}  # stagehand -> prop
# Track stagehands that should put down their prop when they arrive
var _pending_put_down: Dictionary = {}  # stagehand -> true


func _ready() -> void:
	# Initialize pathfinding with larger grid for half-ellipse stage
	pathfinding.initialize(_grid_size, _cell_size)
	_mark_stage_bounds()

	# Configure grid overlay with ellipse shape
	grid_overlay.set_stage_ellipse(ELLIPSE_CENTER_Y, ELLIPSE_A, ELLIPSE_B)

	# Focus camera on stage center
	camera.focus_on(Vector2(0, 0))

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

	# Prop definitions: [name, color, weight]
	var prop_defs: Array = [
		["Chair", Color.SADDLE_BROWN, 1],
		["Stool", Color.NAVY_BLUE, 1],
		["Dresser", Color.ANTIQUE_WHITE, 2],
		["Couch", Color.FOREST_GREEN, 2],
		["Piano", Color.DARK_RED, 3],
		["Bookshelf", Color.PURPLE, 3],
	]
	prop_defs.shuffle()

	# All wing sections to distribute props into
	var wing_sections: Array[Rect2] = [
		STAGE_LEFT_1ST, STAGE_LEFT_2ND, STAGE_LEFT_3RD,
		STAGE_RIGHT_1ST, STAGE_RIGHT_2ND, STAGE_RIGHT_3RD,
	]

	for i in range(prop_defs.size()):
		var def: Array = prop_defs[i]
		var section: Rect2 = wing_sections[i]
		var spawn_pos: Vector2 = _random_point_in_rect(section)
		var target_pos: Vector2 = _random_stage_target_ellipse()
		_spawn_prop(spawn_pos, target_pos, def[1], def[0], def[2])


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


func _random_point_in_rect(rect: Rect2) -> Vector2:
	return Vector2(
		randf_range(rect.position.x + 20, rect.position.x + rect.size.x - 20),
		randf_range(rect.position.y + 20, rect.position.y + rect.size.y - 20)
	)


func _random_stage_target_ellipse() -> Vector2:
	# Rejection sampling: pick random points in bounding box until one is inside the ellipse
	# Shrink slightly to keep targets away from the edge
	var margin := 50.0
	for attempt in range(100):
		var x: float = randf_range(-ELLIPSE_A + margin, ELLIPSE_A - margin)
		var y: float = randf_range(ELLIPSE_CENTER_Y - ELLIPSE_B + margin, ELLIPSE_CENTER_Y - margin)
		if is_on_stage(Vector2(x, y)):
			return Vector2(x, y)
	# Fallback: center of stage
	return Vector2(0, 0)


static func is_on_stage(world_pos: Vector2) -> bool:
	# Flat edge at bottom (ELLIPSE_CENTER_Y), curve extends upward
	if world_pos.y > ELLIPSE_CENTER_Y:
		return false
	var nx: float = world_pos.x / ELLIPSE_A
	var ny: float = (world_pos.y - ELLIPSE_CENTER_Y) / ELLIPSE_B
	return (nx * nx + ny * ny) <= 1.0


static func is_in_backstage(world_pos: Vector2) -> bool:
	return BACKSTAGE_RECT.has_point(world_pos)


static func is_walkable(world_pos: Vector2) -> bool:
	return is_on_stage(world_pos) or is_in_backstage(world_pos)


func _mark_stage_bounds() -> void:
	# Block all pathfinding cells that fall outside the walkable area (stage + backstage)
	for x in range(_grid_size.x):
		for y in range(_grid_size.y):
			var world_pos: Vector2 = pathfinding.cell_to_world(Vector2i(x, y))
			if not is_walkable(world_pos):
				pathfinding.set_cell_blocked(Vector2i(x, y), true)


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
