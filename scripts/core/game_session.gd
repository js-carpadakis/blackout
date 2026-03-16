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
@onready var path_preview: Node2D = $StageLayout/PathPreview

var selected_stagehand: CharacterBody2D = null
var selected_prop: StaticBody2D = null
var stagehands: Array[CharacterBody2D] = []
var props: Array[StaticBody2D] = []

# Cell size in pixels (must match grid_system and pathfinding)
var _cell_size: float = 50.0
var _grid_size: Vector2i = Vector2i(36, 17)

# Rectangular proscenium theater layout
# Main stage: 1300 wide centered, 600 deep (visible to audience)
const STAGE_RECT := Rect2(-650, -500, 1300, 600)

# Proscenium wall at Y=-500 (front of stage)
const PROSCENIUM_Y := -500.0

# Apron/forestage: half-ellipse extending past the proscenium opening toward the audience
# Curves outward only across the proscenium opening, flat at the sides where the wall exists
const APRON_A := 650.0   # semi-axis x (half of proscenium opening width)
const APRON_B := 200.0   # semi-axis y (max depth at center)
const APRON_CENTER_Y := -500.0  # flat edge at proscenium line

# Wing sections: 250px wide, 600px tall (4 sections of 150px)
const WING_WIDTH := 250.0
const WING_SECTION_HEIGHT := 150.0

# Stage left wing sections (1st=closest to audience/top, 4th=deepest/bottom)
const STAGE_LEFT_1ST := Rect2(-900, -500, 250, 150)
const STAGE_LEFT_2ND := Rect2(-900, -350, 250, 150)
const STAGE_LEFT_3RD := Rect2(-900, -200, 250, 150)
const STAGE_LEFT_4TH := Rect2(-900, -50, 250, 150)

# Stage right wing sections
const STAGE_RIGHT_1ST := Rect2(650, -500, 250, 150)
const STAGE_RIGHT_2ND := Rect2(650, -350, 250, 150)
const STAGE_RIGHT_3RD := Rect2(650, -200, 250, 150)
const STAGE_RIGHT_4TH := Rect2(650, -50, 250, 150)

# Full wing bounds (union of all 4 sections per side)
const STAGE_LEFT_RECT := Rect2(-900, -500, 250, 600)
const STAGE_RIGHT_RECT := Rect2(650, -500, 250, 600)

# World bounds: entire walkable area for drag clamping (includes apron)
const WORLD_BOUNDS := Rect2(-900, -700, 1800, 800)

# Blackout timing
const BLACKOUT_DURATION := 15.0
var _blackout_elapsed: float = 0.0
var _execution_started_props: Array[StaticBody2D] = []
var _score_showing: bool = false

# Phase state
var _is_planning: bool = true

# Drag state (planning phase)
var _dragging_entity: Node2D = null
var _dragging_target_prop: StaticBody2D = null  # When dragging a target ghost
var _drag_offset: Vector2 = Vector2.ZERO
var _launch_drag_stagehand: CharacterBody2D = null  # Stagehand whose launch vector is being drawn

# Execution tracking — prop-driven
enum LegPhase { DISPATCHING, GATHERING, CARRYING, DONE }
var _active_props: Array[StaticBody2D] = []
var _prop_execution: Dictionary = {}  # prop -> { "phase": LegPhase, "arrived": [stagehands] }
var _props_waiting_for_stagehand: Dictionary = {}  # stagehand -> [props waiting for this stagehand]
var _execution_ending: bool = false  # True once all props are done, waiting for stagehands to return

# Mid-execution pause state
var _execution_paused: bool = false


func _ready() -> void:
	# Initialize pathfinding grid covering entire walkable area
	pathfinding.initialize(_grid_size, _cell_size)
	_mark_stage_bounds()

	# Configure grid overlay with stage rect
	grid_overlay.set_stage_rect(STAGE_RECT)
	grid_overlay.set_grid_visible(false)

	# Fit camera to show entire playable area, reserving space for HUD panel
	var stage_bounds := WORLD_BOUNDS
	camera.fit_to_stage(stage_bounds, 260.0)  # 250px panel + 10px gap

	# Connect HUD signals
	planning_hud.score_dismissed.connect(_resume_from_score)
	# Start in planning phase
	GameManager.change_state(GameManager.GameState.PLAYING)
	GameManager.change_phase(GameManager.Phase.PLANNING)

	# Initialize path preview
	path_preview.setup(pathfinding)

	# Spawn entities from setup config or fallback to test entities
	if GameManager.has_setup_config():
		_spawn_from_config(GameManager.setup_config)
		GameManager.clear_setup_config()
	else:
		_spawn_test_entities()
	_update_hud()


func _process(delta: float) -> void:
	if not _is_planning and not _execution_paused and not _score_showing:
		if _blackout_elapsed < BLACKOUT_DURATION:
			_blackout_elapsed += delta
			var remaining := maxf(0.0, BLACKOUT_DURATION - _blackout_elapsed)
			planning_hud.show_countdown(remaining)
			if _blackout_elapsed >= BLACKOUT_DURATION:
				_on_blackout_expired()


func _spawn_test_entities() -> void:
	# Stage left stagehands - one per wing section
	_spawn_stagehand(StagehandRookieScene, _section_center(STAGE_LEFT_1ST), Color.LIGHT_BLUE)
	_spawn_stagehand(StagehandRegularScene, _section_center(STAGE_LEFT_2ND), Color.BLUE)
	_spawn_stagehand(StagehandStrongScene, _section_center(STAGE_LEFT_3RD), Color.DARK_BLUE)

	# Stage right stagehands - one per wing section
	_spawn_stagehand(StagehandRookieScene, _section_center(STAGE_RIGHT_1ST), Color.LIGHT_CORAL)
	_spawn_stagehand(StagehandRegularScene, _section_center(STAGE_RIGHT_2ND), Color.CORAL)
	_spawn_stagehand(StagehandStrongScene, _section_center(STAGE_RIGHT_3RD), Color.DARK_RED)

	# Prop definitions: { name, weight, color, shape, size, traits }
	var prop_defs: Array = [
		{ "name": "Chair", "weight": 1, "color": Color.SADDLE_BROWN, "shape": 0, "size": Vector2(45, 45), "traits": [] },
		{ "name": "Stool", "weight": 1, "color": Color.NAVY_BLUE, "shape": 1, "size": Vector2(42, 42), "traits": [] },
		{ "name": "Lamp", "weight": 1, "color": Color.GOLDENROD, "shape": 0, "size": Vector2(30, 60), "traits": [0] },
		{ "name": "Table", "weight": 2, "color": Color.BURLYWOOD, "shape": 1, "size": Vector2(75, 75), "traits": [] },
		{ "name": "Couch", "weight": 2, "color": Color.FOREST_GREEN, "shape": 0, "size": Vector2(105, 52), "traits": [2] },
		{ "name": "Dresser", "weight": 2, "color": Color.ANTIQUE_WHITE, "shape": 0, "size": Vector2(82, 60), "traits": [2] },
		{ "name": "Rug", "weight": 2, "color": Color.CRIMSON, "shape": 0, "size": Vector2(120, 22), "traits": [] },
		{ "name": "Piano", "weight": 3, "color": Color.DARK_RED, "shape": 2, "size": Vector2(105, 82), "traits": [0] },
		{ "name": "Bookshelf", "weight": 3, "color": Color.PURPLE, "shape": 0, "size": Vector2(52, 105), "traits": [] },
		{ "name": "Wardrobe", "weight": 3, "color": Color.DARK_OLIVE_GREEN, "shape": 0, "size": Vector2(75, 98), "traits": [1] },
		{ "name": "Statue", "weight": 2, "color": Color.SLATE_GRAY, "shape": 1, "size": Vector2(52, 52), "traits": [0, 1] },
		{ "name": "Bed", "weight": 3, "color": Color.MEDIUM_PURPLE, "shape": 0, "size": Vector2(112, 82), "traits": [2] },
		{ "name": "Black Scrim", "weight": 1, "color": Color(0.1, 0.1, 0.1, 0.7), "shape": 0, "size": Vector2(60, 8), "traits": [3] },
		{ "name": "White Drop", "weight": 1, "color": Color(0.9, 0.9, 0.85), "shape": 0, "size": Vector2(60, 8), "traits": [3] },
		{ "name": "Forest Drop", "weight": 2, "color": Color.DARK_GREEN, "shape": 0, "size": Vector2(60, 8), "traits": [3] },
	]
	prop_defs.shuffle()
	prop_defs.resize(6)

	# All wing sections to distribute props into
	var wing_sections: Array[Rect2] = [
		STAGE_LEFT_1ST, STAGE_LEFT_2ND, STAGE_LEFT_3RD, STAGE_LEFT_4TH,
		STAGE_RIGHT_1ST, STAGE_RIGHT_2ND, STAGE_RIGHT_3RD, STAGE_RIGHT_4TH,
	]

	for i in range(prop_defs.size()):
		var def: Dictionary = prop_defs[i]
		var section: Rect2 = wing_sections[i]
		var spawn_pos: Vector2 = _random_point_in_rect(section)
		var target_pos: Vector2 = _random_stage_target()
		_spawn_prop(spawn_pos, target_pos, def.color, def.name, def.weight, def.shape, def.size, def.traits)


func _spawn_from_config(config: Dictionary) -> void:
	var wing_sections: Array[Rect2] = [
		STAGE_LEFT_1ST, STAGE_LEFT_2ND, STAGE_LEFT_3RD, STAGE_LEFT_4TH,
		STAGE_RIGHT_1ST, STAGE_RIGHT_2ND, STAGE_RIGHT_3RD, STAGE_RIGHT_4TH,
	]
	var type_to_scene: Dictionary = {
		"rookie": StagehandRookieScene,
		"regular": StagehandRegularScene,
		"strong": StagehandStrongScene,
	}

	# First pass: spawn unique stagehands (identified by color) at their prop's wing
	var spawned_stagehands: Dictionary = {}  # Color -> CharacterBody2D
	for assignment in config.assignments:
		var section: Rect2 = wing_sections[assignment.wing_section]
		for crew_member in assignment.crew:
			if not spawned_stagehands.has(crew_member.color):
				var scene: PackedScene = type_to_scene[crew_member.type]
				_spawn_stagehand(scene, _section_center(section), crew_member.color)
				spawned_stagehands[crew_member.color] = stagehands.back()

	# Second pass: spawn props in their wing sections
	var spawned_props: Array[StaticBody2D] = []
	for assignment in config.assignments:
		var section: Rect2 = wing_sections[assignment.wing_section]
		var def: Dictionary = assignment.prop_def
		var spawn_pos: Vector2 = _random_point_in_rect(section)
		var target_pos: Vector2 = _random_stage_target()
		_spawn_prop(spawn_pos, target_pos, def.color, def.name, def.weight, def.shape, def.size, def.traits)
		spawned_props.append(props.back())

	# Third pass: create pre-attached assignments
	for i in range(config.assignments.size()):
		var assignment: Dictionary = config.assignments[i]
		if assignment.crew.is_empty():
			continue
		var prop: StaticBody2D = spawned_props[i]
		var leg_idx: int = prop.add_leg()
		for crew_member in assignment.crew:
			var stagehand: CharacterBody2D = spawned_stagehands[crew_member.color]
			prop.add_stagehand_to_leg(leg_idx, stagehand)
			stagehand.add_assigned_prop(prop)


func _spawn_stagehand(scene: PackedScene, pos: Vector2, color: Color) -> void:
	var stagehand: CharacterBody2D = scene.instantiate() as CharacterBody2D
	stagehand.stagehand_color = color
	stagehand.global_position = pos
	stagehand.home_position = pos
	stagehand.set_pathfinding(pathfinding)
	stagehand.selected.connect(_on_stagehand_selected)
	stagehand.reached_destination.connect(_on_stagehand_arrived.bind(stagehand))
	stagehands_container.add_child(stagehand)
	stagehands.append(stagehand)


func _spawn_prop(pos: Vector2, target: Vector2, color: Color, prop_name: String, weight: int = 1, shape_id: int = 0, size: Vector2 = Vector2.ZERO, prop_traits: Array = []) -> void:
	var prop: StaticBody2D = PropScene.instantiate() as StaticBody2D
	prop.prop_name = prop_name
	prop.prop_color = color
	prop.weight = weight
	prop.shape = shape_id
	if size != Vector2.ZERO:
		prop.size_override = size
	var typed_traits: Array[int] = []
	for t in prop_traits:
		typed_traits.append(t as int)
	prop.traits = typed_traits
	prop.global_position = pos
	# Scrims are locked to their wing edge and have no stage destination
	if prop.is_scrim():
		prop._scrim_from_left = pos.x < 0.0
		prop.global_position.x = -650.0 if prop._scrim_from_left else 650.0
	props_container.add_child(prop)
	props.append(prop)
	if not prop.is_scrim():
		prop.set_target(target)


# =============================================================================
# INPUT HANDLING
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_execution"):
		if _is_planning and _execution_paused:
			_resume_execution()
		elif _is_planning:
			_start_execution()
		else:
			_pause_execution()
		get_viewport().set_input_as_handled()
		return

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
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_rotate_hovered_ghost(get_global_mouse_position(), deg_to_rad(15))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_rotate_hovered_ghost(get_global_mouse_position(), deg_to_rad(-15))

	elif event is InputEventMouseMotion and (_dragging_entity or _dragging_target_prop or _launch_drag_stagehand):
		_planning_handle_drag(get_global_mouse_position())


func _planning_handle_click(world_pos: Vector2) -> void:
	# Check if clicked on a target ghost — start dragging the target position
	for prop in props:
		if prop._show_ghost and not prop.is_scrim():
			var half_size: Vector2 = prop.prop_size / 2.0
			var ghost_rect: Rect2 = Rect2(prop.target_position - half_size, prop.prop_size)
			if ghost_rect.has_point(world_pos):
				_dragging_target_prop = prop
				_drag_offset = prop.target_position - world_pos
				return

	# Check if clicked on stagehand — select and begin launch-vector drag
	for stagehand in stagehands:
		if world_pos.distance_to(stagehand.global_position) < stagehand.stagehand_radius + 5.0:
			_select_stagehand(stagehand)
			_launch_drag_stagehand = stagehand  # Left-drag sets launch vector; reposition is right-click
			return

	# Check if clicked on prop — select prop; scrims are selectable but not draggable
	for prop in props:
		var half_size: Vector2 = prop.prop_size / 2.0
		var prop_rect: Rect2 = Rect2(prop.global_position - half_size, prop.prop_size)
		if prop_rect.has_point(world_pos):
			if not prop.is_scrim():
				_dragging_entity = prop
				prop.is_being_dragged = true
				_drag_offset = prop.global_position - world_pos
			_select_prop(prop)
			return

	# If a prop is selected and clicked on stage, set its target destination
	if selected_prop and not selected_prop.is_scrim() and is_on_stage(world_pos):
		var leg_idx: int = selected_prop.get_active_leg_index()
		if leg_idx >= 0:
			selected_prop.movement_plan[leg_idx]["destination"] = world_pos
			selected_prop.set_target(world_pos)
			_update_hud()
			path_preview.invalidate(true)
			return

	# Clicked on nothing — deselect
	_deselect_all()


func _planning_handle_drag(world_pos: Vector2) -> void:
	# Launch vector drag — slingshot: drag opposite to burst direction
	if _launch_drag_stagehand:
		var drag_vec: Vector2 = world_pos - _launch_drag_stagehand.global_position
		_launch_drag_stagehand.launch_vector = Vector2.ZERO if drag_vec.length() < 10.0 else (-drag_vec).limit_length(500.0)
		_launch_drag_stagehand.queue_redraw()
		path_preview.invalidate(true)
		return

	# Dragging a target ghost — constrain to walkable area (stage, wings, apron)
	if _dragging_target_prop:
		var ghost_pos: Vector2 = world_pos + _drag_offset
		if is_walkable(ghost_pos):
			# Update the last leg's destination (the one the ghost represents)
			var prop: StaticBody2D = _dragging_target_prop
			for i in range(prop.movement_plan.size() - 1, -1, -1):
				if prop.movement_plan[i].has("destination"):
					prop.movement_plan[i].destination = ghost_pos
					break
			prop.set_target(ghost_pos, prop.target_rotation)
		path_preview.invalidate(true)
		return

	if not _dragging_entity:
		return

	var target_pos: Vector2 = world_pos + _drag_offset

	# Clamp to world bounds (stage + wings + apron)
	target_pos.x = clamp(target_pos.x, WORLD_BOUNDS.position.x, WORLD_BOUNDS.position.x + WORLD_BOUNDS.size.x)
	target_pos.y = clamp(target_pos.y, WORLD_BOUNDS.position.y, WORLD_BOUNDS.position.y + WORLD_BOUNDS.size.y)

	_dragging_entity.global_position = target_pos

	if _is_dragging_affects_selected_path():
		path_preview.invalidate()


func _planning_handle_release() -> void:
	if _dragging_entity and _dragging_entity is StaticBody2D:
		_dragging_entity.is_being_dragged = false
	_dragging_entity = null
	_dragging_target_prop = null
	_drag_offset = Vector2.ZERO
	_launch_drag_stagehand = null


func _rotate_hovered_ghost(world_pos: Vector2, angle_delta: float) -> void:
	for prop in props:
		if not prop._show_ghost:
			continue
		var radius: float = max(prop.prop_size.x, prop.prop_size.y) / 2.0
		if world_pos.distance_to(prop.target_position) < radius + 10.0:
			prop.target_rotation += angle_delta
			prop.queue_redraw()
			return


func _is_dragging_affects_selected_path() -> bool:
	if not selected_stagehand:
		return false
	if _dragging_entity == selected_stagehand:
		return true
	if _dragging_entity is StaticBody2D and _dragging_entity in selected_stagehand.assigned_props:
		return true
	return false


func _planning_handle_right_click(world_pos: Vector2) -> void:
	if not selected_stagehand:
		return

	# Check if right-clicked on a prop — toggle stagehand assignment on the active leg
	for prop in props:
		var half_size: Vector2 = prop.prop_size / 2.0
		var prop_rect: Rect2 = Rect2(prop.global_position - half_size, prop.prop_size)
		if prop_rect.has_point(world_pos):
			_toggle_stagehand_on_prop(selected_stagehand, prop)
			return

	# Right-click on walkable floor — set destination for the next incomplete leg (one at a time)
	if selected_stagehand.has_assignment and is_walkable(world_pos):
		for prop in selected_stagehand.assigned_props:
			var leg_idx: int = prop.find_incomplete_leg_with_stagehand(selected_stagehand)
			if leg_idx >= 0:
				prop.movement_plan[leg_idx]["destination"] = world_pos
				prop.show_target_ghost(true)
				print("Destination set for ", prop.prop_name, " leg ", leg_idx + 1, ": ", world_pos)
				_update_hud()
				path_preview.invalidate(true)
				return
		return

	# Right-click in wings — reposition stagehand directly
	if not is_on_stage(world_pos) and is_walkable(world_pos):
		selected_stagehand.global_position = world_pos


func _toggle_stagehand_on_prop(stagehand: CharacterBody2D, prop: StaticBody2D) -> void:
	# If stagehand is already on any leg of this prop, remove them (toggle off)
	if prop.is_stagehand_in_any_leg(stagehand):
		prop.remove_stagehand_from_all_legs(stagehand)
		stagehand.remove_assigned_prop(prop)
		_update_hud()
		path_preview.invalidate(true)
		print("Unassigned ", stagehand.stagehand_name, " -x- ", prop.prop_name)
		return

	# Find the active leg (one without destination), or create leg 0
	var active_leg: int = prop.get_active_leg_index()
	if active_leg == -1:
		# No incomplete leg — create a new one
		active_leg = prop.add_leg()

	prop.add_stagehand_to_leg(active_leg, stagehand)
	stagehand.add_assigned_prop(prop)
	_update_hud()
	path_preview.invalidate(true)
	print("Assigned ", stagehand.stagehand_name, " -> ", prop.prop_name, " leg ", active_leg + 1)


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
	_execution_paused = false
	GameManager.start_execution()
	planning_hud.set_phase("BLACKOUT")
	_deselect_all()
	path_preview.set_execution_mode(true)

	# Initialize prop-driven execution
	_active_props.clear()
	_prop_execution.clear()
	_props_waiting_for_stagehand.clear()
	_execution_ending = false
	_blackout_elapsed = 0.0
	_score_showing = false
	_execution_started_props.clear()
	planning_hud.hide_score()

	for prop in props:
		if prop.has_plan():
			prop.current_leg_index = 0
			_active_props.append(prop)
			_execution_started_props.append(prop)
			_start_leg(prop)


func _pause_execution() -> void:
	_is_planning = true
	_execution_paused = true
	GameManager.change_phase(GameManager.Phase.PLANNING)
	planning_hud.set_phase("PLANNING")
	_deselect_all()
	path_preview.set_execution_mode(false)

	# Stop all stagehand movement (preserve CARRYING/PUSHING state; freeze LAUNCHING in place)
	for sh in stagehands:
		sh.current_path = PackedVector2Array()
		sh.velocity = Vector2.ZERO
		if sh.current_state == StagehandController.State.LAUNCHING:
			sh.is_frozen = true  # Suspend burst; remaining distance preserved for resume
		elif sh.current_state == StagehandController.State.MOVING or sh.current_state == StagehandController.State.WAITING:
			sh.current_state = StagehandController.State.IDLE

	# Freeze pushed props
	for prop in props:
		if prop.current_state == prop.PropState.BEING_PUSHED:
			prop._push_paused = true


func _resume_execution() -> void:
	_is_planning = false
	_execution_paused = false
	GameManager.start_execution()
	planning_hud.set_phase("BLACKOUT")
	_deselect_all()
	path_preview.set_execution_mode(true)

	# Unfreeze pushed props
	for prop in props:
		if prop.current_state == prop.PropState.BEING_PUSHED:
			prop._push_paused = false

	# Unfreeze any stagehands that were mid-launch when paused
	for sh in stagehands:
		if sh.is_frozen and sh.current_state == StagehandController.State.LAUNCHING:
			sh.is_frozen = false

	# Re-route stagehands to (possibly updated) destinations
	for prop in _active_props:
		if not _prop_execution.has(prop):
			continue
		var exec: Dictionary = _prop_execution[prop]
		var leg: Dictionary = prop.get_current_leg()
		if leg.is_empty():
			continue

		if exec.phase == LegPhase.CARRYING:
			# Re-route dispatched stagehands to destination (picks up any changes made during pause)
			if leg.has("destination"):
				for sh in exec.dispatched:
					sh.move_to(leg.destination)
		elif exec.phase == LegPhase.DISPATCHING:
			# Skip re-routing if any dispatched stagehand is still mid-launch
			var any_launching := false
			for sh in exec.dispatched:
				if sh.current_state == StagehandController.State.LAUNCHING:
					any_launching = true
					break
			if not any_launching:
				# Re-attempt start_leg (handles stagehands that may have been reassigned)
				_prop_execution.erase(prop)
				_start_leg(prop)

	# Start any props that have remaining legs but aren't currently active
	for prop in props:
		if prop in _active_props:
			continue
		if not prop.has_plan():
			continue
		# Never started — initialize leg index
		if prop.current_leg_index < 0:
			prop.current_leg_index = 0
		# Has legs left to execute (includes completed props that got new legs during pause)
		if prop.current_leg_index < prop.get_leg_count():
			_active_props.append(prop)
			_start_leg(prop)


func _end_execution() -> void:
	_is_planning = true
	_execution_paused = false
	_score_showing = false
	GameManager.change_phase(GameManager.Phase.PLANNING)
	planning_hud.set_phase("PLANNING")

	# Reset all props — positions stay where they are
	for prop in props:
		prop.reset_for_planning()

	# Reset all stagehands — positions stay where they are
	for stagehand in stagehands:
		stagehand.reset_for_planning()

	# Clear execution tracking
	_active_props.clear()
	_prop_execution.clear()
	_props_waiting_for_stagehand.clear()
	_execution_ending = false

	_deselect_all()
	path_preview.set_execution_mode(false)
	_update_hud()


# =============================================================================
# SCORING
# =============================================================================

func _on_blackout_expired() -> void:
	_finish_blackout()


func _finish_blackout() -> void:
	## Snapshot score, freeze movement, highlight spotted stagehands, show panel.
	## Execution ends only after the player dismisses the score panel and all
	## stagehands have returned to the wings.
	if _is_planning or _score_showing:
		return
	_score_showing = true

	# Freeze all stagehands and highlight those still visible to the audience
	for sh in stagehands:
		sh.is_frozen = true
		if _compute_stagehand_visibility(sh.global_position) >= 0.05:
			sh.is_spotted = true
		sh.queue_redraw()

	# Freeze props that are mid-push (wheeled/scrim)
	for prop in props:
		if prop.current_state == prop.PropState.BEING_PUSHED:
			prop._push_paused = true

	var score := _compute_blackout_score()
	planning_hud.show_score(score)


func _resume_from_score() -> void:
	## Called when the score panel is dismissed. Unfreeze and let stagehands
	## finish routing to the wings; end execution once they're all idle.
	for sh in stagehands:
		sh.is_frozen = false
		sh.is_spotted = false
		sh.queue_redraw()
	for prop in props:
		prop._push_paused = false

	# Ensure the all-idle check will fire once everyone settles
	_execution_ending = true

	# If stagehands are already idle (all reached wings before timer), end now
	var all_idle := true
	for sh in stagehands:
		if sh.current_state in [StagehandController.State.MOVING, StagehandController.State.CARRYING, StagehandController.State.PUSHING, StagehandController.State.LAUNCHING]:
			all_idle = false
			break
	if all_idle:
		_end_execution()


func _compute_blackout_score() -> Dictionary:
	var props_placed := 0
	for prop in _execution_started_props:
		if prop.current_state == prop.PropState.IN_POSITION:
			props_placed += 1

	var stagehand_data: Array = []
	for sh in stagehands:
		stagehand_data.append({
			"name": sh.stagehand_name,
			"penalty": _compute_stagehand_visibility(sh.global_position),
		})

	return {
		"props_placed": props_placed,
		"props_total": _execution_started_props.size(),
		"elapsed": _blackout_elapsed,
		"stagehand_data": stagehand_data,
	}


func _compute_stagehand_visibility(pos: Vector2) -> float:
	## Returns 0.0 (safe in wings) to 1.0 (center stage / apron).
	## Scales linearly with distance to the nearest wing entrance.
	if STAGE_LEFT_RECT.has_point(pos) or STAGE_RIGHT_RECT.has_point(pos):
		return 0.0
	if is_on_apron(pos):
		return 1.0
	if STAGE_RECT.has_point(pos):
		var dist_left := pos.x - STAGE_RECT.position.x    # 0 at left wing edge
		var dist_right := STAGE_RECT.end.x - pos.x        # 0 at right wing edge
		var half_width := STAGE_RECT.size.x / 2.0         # 650
		return minf(dist_left, dist_right) / half_width
	return 0.0


# =============================================================================
# EXECUTION — prop-driven leg system
# =============================================================================

func _is_stagehand_busy(sh: CharacterBody2D) -> bool:
	## A stagehand is busy if they are moving, carrying, pushing, or have carried props.
	if sh.current_state == StagehandController.State.CARRYING:
		return true
	if sh.current_state == StagehandController.State.MOVING:
		return true
	if sh.current_state == StagehandController.State.PUSHING:
		return true
	if sh.current_state == StagehandController.State.LAUNCHING:
		return true
	if sh.carried_props.size() > 0:
		return true
	return false


func _start_leg(prop: StaticBody2D) -> void:
	var leg: Dictionary = prop.get_current_leg()
	if leg.is_empty():
		return

	var leg_stagehands: Array = leg.stagehands
	# "dispatched" tracks which stagehands were actually sent — only those
	# should be matched by _find_active_prop_for_stagehand on arrival
	_prop_execution[prop] = { "phase": LegPhase.DISPATCHING, "arrived": [], "dispatched": [] }

	# Check if all stagehands for this leg are free
	var all_free: bool = true
	for sh in leg_stagehands:
		if _is_stagehand_busy(sh):
			all_free = false
			# Register that this prop is waiting for this stagehand
			if not _props_waiting_for_stagehand.has(sh):
				_props_waiting_for_stagehand[sh] = []
			if prop not in _props_waiting_for_stagehand[sh]:
				_props_waiting_for_stagehand[sh].append(prop)

	if all_free:
		_prop_execution[prop].dispatched = leg_stagehands.duplicate()
		var prop_in_wings := STAGE_LEFT_RECT.has_point(prop.global_position) or STAGE_RIGHT_RECT.has_point(prop.global_position)
		if prop_in_wings and not leg_stagehands.is_empty():
			# Prop is in the wings: skip dispatch, begin carrying/pushing immediately
			# Teleport prop to lead stagehand so they start together
			prop.global_position = leg_stagehands[0].global_position
			# Push mechanics don't support launch — clear vectors for those stagehands
			if prop.is_wheeled() or prop.is_scrim():
				for sh in leg_stagehands:
					sh.launch_vector = Vector2.ZERO
					sh.queue_redraw()
			_do_pickup(prop)
		else:
			# Normal dispatch: send stagehands to pick-up position
			var pickup_pos: Vector2 = prop.get_pickup_position()
			for sh in leg_stagehands:
				sh.move_to(pickup_pos)


func _on_stagehand_arrived(stagehand: CharacterBody2D) -> void:
	if _is_planning:
		return

	# Find which active prop's current leg includes this stagehand
	var prop: StaticBody2D = _find_active_prop_for_stagehand(stagehand)
	if not prop:
		# Check if any props were waiting for this stagehand to become free
		if not _try_dispatch_waiting_prop(stagehand) and _execution_ending:
			# Check if all stagehands are idle — if so, end or score
			var all_idle: bool = true
			for sh in stagehands:
				if sh.current_state in [StagehandController.State.MOVING, StagehandController.State.CARRYING, StagehandController.State.PUSHING, StagehandController.State.LAUNCHING]:
					all_idle = false
					break
			if all_idle:
				if _score_showing:
					_end_execution()  # Post-score: stagehands finished returning
				else:
					_finish_blackout()  # All done before timer — show score now
		return

	var exec: Dictionary = _prop_execution[prop]
	var phase: LegPhase = exec.phase

	if phase == LegPhase.DISPATCHING or phase == LegPhase.GATHERING:
		# Stagehand arrived at prop for pickup
		if stagehand not in exec.arrived:
			exec.arrived.append(stagehand)

		var leg: Dictionary = prop.get_current_leg()
		var leg_stagehands: Array = leg.stagehands

		# Check if all stagehands for this leg have arrived
		if exec.arrived.size() >= leg_stagehands.size():
			_do_pickup(prop)

	elif phase == LegPhase.CARRYING:
		# Stagehand arrived at destination — drop off
		_do_dropoff(prop, stagehand)


func _do_pickup(prop: StaticBody2D) -> void:
	var leg: Dictionary = prop.get_current_leg()
	var leg_stagehands: Array = leg.stagehands

	# Scrims are pulled across the stage from their wing side
	if prop.is_scrim():
		var sh: CharacterBody2D = leg_stagehands[0]
		sh.start_pushing(prop)
		# Determine pull direction based on which wing the prop is in
		var from_left: bool = prop.global_position.x < 0.0
		prop.begin_scrim_pull(sh, from_left)

		_prop_execution[prop].phase = LegPhase.CARRYING
		_prop_execution[prop].arrived = []
		_prop_execution[prop].dispatched = [sh]
		return

	# Wheeled props are pushed, not carried
	if prop.is_wheeled():
		var sh: CharacterBody2D = leg_stagehands[0]
		var push_speed: float = sh.movement_speed * 0.6
		sh.start_pushing(prop)
		prop.begin_push(sh, leg.destination, push_speed)

		# Reuse CARRYING phase for tracking
		_prop_execution[prop].phase = LegPhase.CARRYING
		_prop_execution[prop].arrived = []
		_prop_execution[prop].dispatched = [sh]
		return

	if leg_stagehands.size() == 1:
		# Solo carry
		var sh: CharacterBody2D = leg_stagehands[0]
		if sh.get_remaining_strength() >= prop.weight:
			if sh.pick_up(prop):
				prop.on_picked_up(sh)
		else:
			sh.force_pick_up(prop)
			prop.on_picked_up(sh)
	else:
		# Cooperative carry — first stagehand is lead
		var lead: CharacterBody2D = leg_stagehands[0]
		if lead.force_pick_up(prop):
			prop.on_picked_up(lead)

		# Add all others as carriers
		for i in range(1, leg_stagehands.size()):
			prop.add_carrier(leg_stagehands[i])

		# Sync speed across all stagehands in the group
		var load_ratio: float = float(prop.weight) / float(lead.strength)
		var group_speed: float = lead.movement_speed * lerpf(0.9, 0.5, clampf(load_ratio, 0.0, 1.0))
		# Apply fragile speed modifier to group speed
		group_speed *= prop.get_carry_speed_modifier()
		for sh in leg_stagehands:
			sh.speed_override = group_speed

	# Transition to CARRYING phase
	_prop_execution[prop].phase = LegPhase.CARRYING
	_prop_execution[prop].arrived = []
	_prop_execution[prop].dispatched = leg_stagehands.duplicate()

	if leg_stagehands.size() == 1:
		# Solo carry — try to consolidate with nearby waiting props
		var sh: CharacterBody2D = leg_stagehands[0]
		if _try_consolidate_pickup(sh):
			return  # Routed to next pickup instead of delivering
		# No consolidation — route to nearest delivery
		_begin_deliveries(sh)
	else:
		# Cooperative carry — route all stagehands to destination
		var destination: Vector2 = leg.destination
		for sh in leg_stagehands:
			sh.move_to(destination)


func _do_dropoff(prop: StaticBody2D, stagehand: CharacterBody2D) -> void:
	var leg: Dictionary = prop.get_current_leg()
	var leg_stagehands: Array = leg.stagehands

	# Track arrival
	if stagehand not in _prop_execution[prop].arrived:
		_prop_execution[prop].arrived.append(stagehand)

	# Wait for lead carrier (first stagehand) to arrive
	var lead: CharacterBody2D = leg_stagehands[0]
	if lead not in _prop_execution[prop].arrived:
		stagehand.current_state = StagehandController.State.WAITING
		return

	# Only the lead performs the actual drop — but only once
	if _prop_execution[prop].phase != LegPhase.CARRYING:
		return
	_prop_execution[prop].phase = LegPhase.DONE

	# Lead drops the prop (or for wheeled props, just mark as placed)
	var is_final_leg: bool = prop.current_leg_index >= prop.get_leg_count() - 1
	if lead.is_carrying(prop):
		var dropped: Node2D = lead.put_down_prop(prop, props_container)
		if dropped:
			# Set rotation to target on the final leg
			if is_final_leg:
				dropped.rotation = prop.target_rotation
			dropped.on_put_down(dropped.global_position)
	elif prop.current_state == prop.PropState.PLACED or prop.current_state == prop.PropState.IN_POSITION:
		# Wheeled push already placed the prop — just emit for tracking
		prop.on_put_down(prop.global_position)

	# Clear all carriers and speed overrides
	for sh in leg_stagehands:
		prop.remove_carrier(sh)
		sh.speed_override = 0.0

	# Advance to next leg
	var next_leg_stagehands: Array = []
	if prop.current_leg_index + 1 < prop.get_leg_count():
		next_leg_stagehands = prop.get_leg(prop.current_leg_index + 1).stagehands

	prop.advance_leg()

	# Start next leg of this prop if it exists
	if prop.current_leg_index < prop.get_leg_count():
		_start_leg(prop)
	else:
		# Prop is complete
		_active_props.erase(prop)
		_prop_execution.erase(prop)
		if _active_props.is_empty():
			_execution_ending = true

	# For each freed stagehand: deliver remaining carried props, dispatch waiting, or return
	for sh in leg_stagehands:
		if sh in next_leg_stagehands:
			continue  # Still needed for this prop's next leg
		if _route_to_next_carried_prop(sh):
			continue  # Still has other props to deliver
		if not _try_dispatch_waiting_prop(sh):
			_return_to_nearest_wing(sh)


func _find_active_prop_for_stagehand(stagehand: CharacterBody2D) -> StaticBody2D:
	var best_carry_prop: StaticBody2D = null
	var best_carry_dist: float = INF

	for prop in _active_props:
		if not _prop_execution.has(prop):
			continue
		var exec: Dictionary = _prop_execution[prop]
		if exec.phase == LegPhase.DONE:
			continue
		# During DISPATCHING, only match stagehands that were actually sent
		if exec.phase == LegPhase.DISPATCHING:
			if stagehand in exec.dispatched:
				return prop
		else:
			# CARRYING phase — prefer the prop whose destination is closest
			# so multi-prop carriers drop the right prop at each stop
			var leg: Dictionary = prop.get_current_leg()
			if not leg.is_empty() and stagehand in leg.stagehands:
				if leg.has("destination"):
					var dist: float = stagehand.global_position.distance_to(leg.destination)
					if dist < best_carry_dist:
						best_carry_dist = dist
						best_carry_prop = prop
				elif best_carry_prop == null:
					best_carry_prop = prop

	return best_carry_prop


func _try_dispatch_waiting_prop(stagehand: CharacterBody2D) -> bool:
	## Try to dispatch this stagehand to a prop that was waiting for them.
	## Returns true if the stagehand was sent somewhere, false if idle.
	if not _props_waiting_for_stagehand.has(stagehand):
		return false

	var waiting_props: Array = _props_waiting_for_stagehand[stagehand]
	_props_waiting_for_stagehand.erase(stagehand)

	var dispatched: bool = false
	for prop in waiting_props:
		if prop in _active_props and _prop_execution.has(prop):
			if _prop_execution[prop].phase == LegPhase.DISPATCHING:
				# Re-attempt starting the leg now that this stagehand is free
				_prop_execution.erase(prop)
				_start_leg(prop)
				# Check if the stagehand was actually dispatched this time
				if _prop_execution.has(prop) and stagehand in _prop_execution[prop].dispatched:
					dispatched = true
	return dispatched


func _route_to_next_carried_prop(stagehand: CharacterBody2D) -> bool:
	## If stagehand is still carrying other active props, route to the nearest destination.
	## Returns true if routed, false if no more deliveries needed.
	if stagehand.carried_props.is_empty():
		return false

	var best_prop: StaticBody2D = null
	var best_dist: float = INF

	for prop in _active_props:
		if not stagehand.is_carrying(prop):
			continue
		if not _prop_execution.has(prop):
			continue
		if _prop_execution[prop].phase != LegPhase.CARRYING:
			continue
		var leg: Dictionary = prop.get_current_leg()
		if leg.is_empty() or not leg.has("destination"):
			continue
		var dist: float = stagehand.global_position.distance_to(leg.destination)
		if dist < best_dist:
			best_dist = dist
			best_prop = prop

	if best_prop:
		var leg: Dictionary = best_prop.get_current_leg()
		stagehand.move_to(leg.destination)
		return true
	return false


func _try_consolidate_pickup(stagehand: CharacterBody2D) -> bool:
	## After a solo pickup, check if there's a nearby waiting prop worth grabbing
	## before delivering. Only consolidate if the pickup is closer than the nearest delivery.
	var sh_pos: Vector2 = stagehand.global_position

	# Find nearest delivery destination among currently carried active props
	var nearest_delivery_dist: float = INF
	for prop in _active_props:
		if not stagehand.is_carrying(prop):
			continue
		if not _prop_execution.has(prop):
			continue
		if _prop_execution[prop].phase != LegPhase.CARRYING:
			continue
		var leg: Dictionary = prop.get_current_leg()
		if leg.is_empty() or not leg.has("destination"):
			continue
		var dist: float = sh_pos.distance_to(leg.destination)
		if dist < nearest_delivery_dist:
			nearest_delivery_dist = dist

	# Find nearest waiting prop this stagehand can solo-carry
	var best_waiting_prop: StaticBody2D = null
	var best_pickup_dist: float = INF
	if _props_waiting_for_stagehand.has(stagehand):
		for prop in _props_waiting_for_stagehand[stagehand]:
			if prop not in _active_props or not _prop_execution.has(prop):
				continue
			if _prop_execution[prop].phase != LegPhase.DISPATCHING:
				continue
			# Only consolidate solo-carry legs
			var leg: Dictionary = prop.get_current_leg()
			if leg.is_empty() or leg.stagehands.size() != 1:
				continue
			# Check if stagehand can carry this prop
			if not stagehand.can_carry(prop):
				continue
			var pickup_pos: Vector2 = prop.get_pickup_position()
			var dist: float = sh_pos.distance_to(pickup_pos)
			if dist < best_pickup_dist:
				best_pickup_dist = dist
				best_waiting_prop = prop

	if best_waiting_prop == null:
		return false

	# Only consolidate if pickup is closer than delivering
	if best_pickup_dist >= nearest_delivery_dist:
		return false

	# Consolidate: remove from waiting list and dispatch to pickup
	_props_waiting_for_stagehand[stagehand].erase(best_waiting_prop)
	if _props_waiting_for_stagehand[stagehand].is_empty():
		_props_waiting_for_stagehand.erase(stagehand)
	_prop_execution[best_waiting_prop].dispatched = [stagehand]
	stagehand.move_to(best_waiting_prop.get_pickup_position())
	return true


func _begin_deliveries(stagehand: CharacterBody2D) -> void:
	## Route stagehand to the nearest destination among all carried active props.
	var best_prop: StaticBody2D = null
	var best_dist: float = INF

	for prop in _active_props:
		if not stagehand.is_carrying(prop):
			continue
		if not _prop_execution.has(prop):
			continue
		if _prop_execution[prop].phase != LegPhase.CARRYING:
			continue
		var leg: Dictionary = prop.get_current_leg()
		if leg.is_empty() or not leg.has("destination"):
			continue
		var dist: float = stagehand.global_position.distance_to(leg.destination)
		if dist < best_dist:
			best_dist = dist
			best_prop = prop

	if best_prop:
		var leg: Dictionary = best_prop.get_current_leg()
		stagehand.move_to(leg.destination)


# =============================================================================
# SELECTION
# =============================================================================

func _select_stagehand(stagehand: CharacterBody2D) -> void:
	_deselect_all()
	selected_stagehand = stagehand
	stagehand.set_selected(true)
	path_preview.set_stagehand(stagehand)


func _select_prop(prop: StaticBody2D) -> void:
	_deselect_all()
	selected_prop = prop


func _deselect_all() -> void:
	if selected_stagehand:
		selected_stagehand.set_selected(false)
		selected_stagehand = null
	selected_prop = null
	path_preview.clear()


func _on_stagehand_selected(stagehand: CharacterBody2D) -> void:
	if stagehand != selected_stagehand:
		_deselect_all()
		selected_stagehand = stagehand


# =============================================================================
# HUD
# =============================================================================

func _update_hud() -> void:
	if planning_hud:
		planning_hud.update_task_list(props)


# =============================================================================
# UTILITIES
# =============================================================================

func _random_point_in_rect(rect: Rect2) -> Vector2:
	return Vector2(
		randf_range(rect.position.x + 20, rect.position.x + rect.size.x - 20),
		randf_range(rect.position.y + 20, rect.position.y + rect.size.y - 20)
	)


func _random_stage_target() -> Vector2:
	var margin := 50.0
	return Vector2(
		randf_range(STAGE_RECT.position.x + margin, STAGE_RECT.position.x + STAGE_RECT.size.x - margin),
		randf_range(STAGE_RECT.position.y + margin, STAGE_RECT.position.y + STAGE_RECT.size.y - margin)
	)


static func is_on_stage(world_pos: Vector2) -> bool:
	return STAGE_RECT.has_point(world_pos)


static func is_on_apron(world_pos: Vector2) -> bool:
	if world_pos.y > APRON_CENTER_Y or world_pos.y < APRON_CENTER_Y - APRON_B:
		return false
	var nx: float = world_pos.x / APRON_A
	var ny: float = (world_pos.y - APRON_CENTER_Y) / APRON_B
	return (nx * nx + ny * ny) <= 1.0


static func is_walkable(world_pos: Vector2) -> bool:
	return is_on_stage(world_pos) or is_on_apron(world_pos) or STAGE_LEFT_RECT.has_point(world_pos) or STAGE_RIGHT_RECT.has_point(world_pos)


func _mark_stage_bounds() -> void:
	for x in range(_grid_size.x):
		for y in range(_grid_size.y):
			var world_pos: Vector2 = pathfinding.cell_to_world(Vector2i(x, y))
			if not is_walkable(world_pos):
				pathfinding.set_cell_blocked(Vector2i(x, y), true)


func _section_center(rect: Rect2) -> Vector2:
	return rect.position + rect.size / 2.0


func _return_to_nearest_wing(stagehand: CharacterBody2D) -> void:
	stagehand.move_to(stagehand.get_return_position())
