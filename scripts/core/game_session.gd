extends Node2D
## Main game session controller - manages stage, entities, and interaction
## Supports PLANNING phase (reposition + assign tasks) and EXECUTION phase (watch stagehands work)

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
@onready var planning_hud: CanvasLayer = $PlanningHUD

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

# Wing sections: 400px wide, 600px tall (3 sections of 200px), outside the ellipse
const WING_WIDTH := 400.0
const WING_SECTION_HEIGHT := 200.0

# Stage left wing sections (1st=closest to audience/top, 3rd=deepest backstage/bottom)
const STAGE_LEFT_1ST := Rect2(-1000, -100, 400, 200)
const STAGE_LEFT_2ND := Rect2(-1000, 100, 400, 200)
const STAGE_LEFT_3RD := Rect2(-1000, 300, 400, 200)

# Stage right wing sections
const STAGE_RIGHT_1ST := Rect2(600, -100, 400, 200)
const STAGE_RIGHT_2ND := Rect2(600, 100, 400, 200)
const STAGE_RIGHT_3RD := Rect2(600, 300, 400, 200)

# Full wing bounds (union of all 3 sections per side)
const STAGE_LEFT_RECT := Rect2(-1000, -100, 400, 600)
const STAGE_RIGHT_RECT := Rect2(600, -100, 400, 600)

# Backstage: 2000x600 rectangle overlapping wings and bottom of stage
const BACKSTAGE_RECT := Rect2(-1000, -100, 2000, 600)

# Phase state
var _is_planning: bool = true

# Drag state (planning phase)
var _dragging_entity: Node2D = null
var _dragging_target_prop: StaticBody2D = null  # When dragging a target ghost
var _drag_offset: Vector2 = Vector2.ZERO

# Execution tracking
var _pending_pick_up: Dictionary = {}  # stagehand -> prop
var _pending_put_down: Dictionary = {}  # stagehand -> true


func _ready() -> void:
	# Initialize pathfinding with larger grid for half-ellipse stage
	pathfinding.initialize(_grid_size, _cell_size)
	_mark_stage_bounds()

	# Configure grid overlay with ellipse shape
	grid_overlay.set_stage_ellipse(ELLIPSE_CENTER_Y, ELLIPSE_A, ELLIPSE_B)

	# Focus camera on stage center
	camera.focus_on(Vector2(0, 0))

	# Connect HUD
	planning_hud.start_pressed.connect(_start_execution)

	# Start in planning phase
	GameManager.change_state(GameManager.GameState.PLAYING)
	GameManager.change_phase(GameManager.Phase.PLANNING)

	# Spawn initial stagehands for testing
	_spawn_test_entities()
	_update_hud()


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


func _spawn_prop(pos: Vector2, target: Vector2, color: Color, prop_name: String, weight: int = 1) -> void:
	var prop: StaticBody2D = PropScene.instantiate() as StaticBody2D
	prop.prop_name = prop_name
	prop.prop_color = color
	prop.weight = weight
	prop.global_position = pos
	props_container.add_child(prop)
	props.append(prop)
	prop.set_target(target)


# =============================================================================
# INPUT HANDLING
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _is_planning:
		_planning_input(event)
	else:
		_execution_input(event)


# --- PLANNING PHASE INPUT ---

func _planning_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_planning_handle_click(get_global_mouse_position())
			else:
				_planning_handle_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_planning_handle_right_click(get_global_mouse_position())

	elif event is InputEventMouseMotion and (_dragging_entity or _dragging_target_prop):
		_planning_handle_drag(get_global_mouse_position())


func _planning_handle_click(world_pos: Vector2) -> void:
	# Check if clicked on a target ghost — start dragging the target position
	for prop in props:
		if prop._show_ghost:
			var half_size: Vector2 = prop.prop_size / 2.0
			var ghost_rect: Rect2 = Rect2(prop.target_position - half_size, prop.prop_size)
			if ghost_rect.has_point(world_pos):
				_dragging_target_prop = prop
				_drag_offset = prop.target_position - world_pos
				return

	# Check if clicked on stagehand — select and start drag
	for stagehand in stagehands:
		if world_pos.distance_to(stagehand.global_position) < stagehand.stagehand_radius + 5.0:
			_select_stagehand(stagehand)
			_dragging_entity = stagehand
			_drag_offset = stagehand.global_position - world_pos
			return

	# Check if clicked on prop — start drag
	for prop in props:
		var half_size: Vector2 = prop.prop_size / 2.0
		var prop_rect: Rect2 = Rect2(prop.global_position - half_size, prop.prop_size)
		if prop_rect.has_point(world_pos):
			_dragging_entity = prop
			prop.is_being_dragged = true
			_drag_offset = prop.global_position - world_pos
			_deselect_all()
			return

	# Clicked on nothing — deselect
	_deselect_all()


func _planning_handle_drag(world_pos: Vector2) -> void:
	# Dragging a target ghost — constrain to stage
	if _dragging_target_prop:
		var ghost_pos: Vector2 = world_pos + _drag_offset
		if is_on_stage(ghost_pos):
			_dragging_target_prop.set_target(ghost_pos)
			# Update the matching task's target in the assigned stagehand's queue
			if _dragging_target_prop.assigned_stagehand:
				var sh = _dragging_target_prop.assigned_stagehand
				for task in sh.task_queue:
					if task.prop == _dragging_target_prop:
						task.target = ghost_pos
						break
		return

	if not _dragging_entity:
		return

	var target_pos: Vector2 = world_pos + _drag_offset

	# Clamp to backstage area
	target_pos.x = clamp(target_pos.x, BACKSTAGE_RECT.position.x, BACKSTAGE_RECT.position.x + BACKSTAGE_RECT.size.x)
	target_pos.y = clamp(target_pos.y, BACKSTAGE_RECT.position.y, BACKSTAGE_RECT.position.y + BACKSTAGE_RECT.size.y)

	_dragging_entity.global_position = target_pos


func _planning_handle_release() -> void:
	if _dragging_entity and _dragging_entity is StaticBody2D:
		_dragging_entity.is_being_dragged = false
	_dragging_entity = null
	_dragging_target_prop = null
	_drag_offset = Vector2.ZERO


func _planning_handle_right_click(world_pos: Vector2) -> void:
	if not selected_stagehand:
		return

	# Check if right-clicked on a prop — assign it to the selected stagehand
	for prop in props:
		var half_size: Vector2 = prop.prop_size / 2.0
		var prop_rect: Rect2 = Rect2(prop.global_position - half_size, prop.prop_size)
		if prop_rect.has_point(world_pos):
			_assign_prop_to_stagehand(selected_stagehand, prop)
			return

	# Right-click on stage floor — set delivery target for the last task in queue
	if selected_stagehand.has_assignment and is_on_stage(world_pos):
		var last_task: Dictionary = selected_stagehand.task_queue.back()
		last_task.target = world_pos
		# Update the prop's ghost target to match
		if last_task.prop:
			last_task.prop.set_target(world_pos)
		_update_hud()
		return

	# Right-click in backstage — reposition via select-then-click (move directly, no pathfinding)
	if is_in_backstage(world_pos):
		selected_stagehand.global_position = world_pos


func _assign_prop_to_stagehand(stagehand: CharacterBody2D, prop: StaticBody2D) -> void:
	# Check if stagehand can carry this prop
	if not stagehand.can_carry(prop):
		print(stagehand.stagehand_name, " cannot carry ", prop.prop_name, " (too heavy)")
		return

	# If this prop is already in this stagehand's queue, remove it (toggle off)
	if stagehand.get_task_index_for_prop(prop) >= 0:
		stagehand.remove_task(prop)
		prop.assigned_stagehand = null
		prop.queue_redraw()
		_update_hud()
		print("Unassigned ", stagehand.stagehand_name, " -x- ", prop.prop_name)
		return

	# Clear any other stagehand assigned to this prop
	for sh in stagehands:
		if sh != stagehand and sh.get_task_index_for_prop(prop) >= 0:
			sh.remove_task(prop)

	# Append to queue
	stagehand.assign_task(prop, prop.target_position)
	prop.assigned_stagehand = stagehand
	prop.queue_redraw()
	_update_hud()
	print("Assigned ", stagehand.stagehand_name, " -> ", prop.prop_name, " (task #", stagehand.task_queue.size(), ")")


# --- EXECUTION PHASE INPUT ---

func _execution_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_execution_handle_click(get_global_mouse_position())


func _execution_handle_click(world_pos: Vector2) -> void:
	# Selection only — no commands during execution
	for stagehand in stagehands:
		if world_pos.distance_to(stagehand.global_position) < stagehand.stagehand_radius + 5.0:
			_select_stagehand(stagehand)
			return
	_deselect_all()


# =============================================================================
# PHASE TRANSITIONS
# =============================================================================

func _start_execution() -> void:
	if not _is_planning:
		return

	_is_planning = false
	GameManager.start_execution()
	planning_hud.set_phase("BLACKOUT")
	_deselect_all()

	# Kick off first task for all assigned stagehands
	for stagehand in stagehands:
		if stagehand.has_assignment:
			_start_next_task(stagehand)


# =============================================================================
# EXECUTION CALLBACKS
# =============================================================================

func _start_next_task(stagehand: CharacterBody2D) -> void:
	var task: Dictionary = stagehand.get_current_task()
	if task.is_empty():
		_return_to_nearest_wing(stagehand)
		return
	_pending_pick_up[stagehand] = task.prop
	stagehand.move_to(task.prop.global_position)


func _on_stagehand_arrived(stagehand: CharacterBody2D) -> void:
	# Check if this stagehand should pick up a prop
	if _pending_pick_up.has(stagehand):
		var prop = _pending_pick_up[stagehand]
		_pending_pick_up.erase(stagehand)
		_try_pickup_prop(stagehand, prop)
		return

	# Check if this stagehand should put down their prop
	if _pending_put_down.has(stagehand):
		_pending_put_down.erase(stagehand)
		if stagehand.carried_prop != null:
			var prop: Node2D = stagehand.put_down(props_container)
			if prop:
				prop.on_put_down(prop.global_position)
			# Advance to next task in queue
			stagehand.advance_task()
			_start_next_task(stagehand)


func _try_pickup_prop(stagehand: CharacterBody2D, prop: StaticBody2D) -> void:
	if stagehand.carried_prop != null:
		return

	# Check if close enough
	var distance: float = stagehand.global_position.distance_to(prop.global_position)
	if distance > 75.0:
		_pending_pick_up[stagehand] = prop
		stagehand.move_to(prop.global_position)
		return

	# Pick up the prop
	if stagehand.pick_up(prop):
		prop.on_picked_up(stagehand)
		# Move to delivery target from current task
		var task: Dictionary = stagehand.get_current_task()
		if not task.is_empty():
			_pending_put_down[stagehand] = true
			stagehand.move_to(task.target)


# =============================================================================
# SELECTION
# =============================================================================

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


# =============================================================================
# HUD
# =============================================================================

func _update_hud() -> void:
	if planning_hud:
		planning_hud.update_task_list(stagehands)


# =============================================================================
# UTILITIES
# =============================================================================

func _random_point_in_rect(rect: Rect2) -> Vector2:
	return Vector2(
		randf_range(rect.position.x + 20, rect.position.x + rect.size.x - 20),
		randf_range(rect.position.y + 20, rect.position.y + rect.size.y - 20)
	)


func _random_stage_target_ellipse() -> Vector2:
	var margin := 50.0
	for attempt in range(100):
		var x: float = randf_range(-ELLIPSE_A + margin, ELLIPSE_A - margin)
		var y: float = randf_range(ELLIPSE_CENTER_Y - ELLIPSE_B + margin, ELLIPSE_CENTER_Y - margin)
		if is_on_stage(Vector2(x, y)):
			return Vector2(x, y)
	return Vector2(0, 0)


static func is_on_stage(world_pos: Vector2) -> bool:
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

	var wing_rect: Rect2 = STAGE_LEFT_RECT if left_dist < right_dist else STAGE_RIGHT_RECT
	var target_x: float = wing_rect.position.x + wing_rect.size.x / 4.0 if left_dist > right_dist else wing_rect.position.x + 3 * wing_rect.size.x / 4.0
	var target_y: float = clamp(from_pos.y, wing_rect.position.y, wing_rect.position.y + wing_rect.size.y)

	return Vector2(target_x, target_y)


func _return_to_nearest_wing(stagehand: CharacterBody2D) -> void:
	var wing_pos: Vector2 = _get_nearest_wing_position(stagehand.global_position)
	stagehand.move_to(wing_pos)
