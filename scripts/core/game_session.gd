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

# Clear zones: 50x50 squares near the top of each wing
const CLEAR_ZONE_LEFT := Rect2(-825, -92, 50, 50)
const CLEAR_ZONE_RIGHT := Rect2(775, -92, 50, 50)

# Phase state
var _is_planning: bool = true

# Drag state (planning phase)
var _dragging_entity: Node2D = null
var _dragging_target_prop: StaticBody2D = null  # When dragging a target ghost
var _drag_offset: Vector2 = Vector2.ZERO

# Execution tracking — prop-driven
enum LegPhase { DISPATCHING, GATHERING, CARRYING, DONE }
var _active_props: Array[StaticBody2D] = []
var _prop_execution: Dictionary = {}  # prop -> { "phase": LegPhase, "arrived": [stagehands] }
var _props_waiting_for_stagehand: Dictionary = {}  # stagehand -> [props waiting for this stagehand]
var _execution_ending: bool = false  # True once all props are done, waiting for stagehands to return

# Clear zone stagehand assignments (planning phase)
var _clear_zone_left_stagehand: CharacterBody2D = null
var _clear_zone_right_stagehand: CharacterBody2D = null


func _ready() -> void:
	# Initialize pathfinding with larger grid for half-ellipse stage
	pathfinding.initialize(_grid_size, _cell_size)
	_mark_stage_bounds()

	# Configure grid overlay with ellipse shape
	grid_overlay.set_stage_ellipse(ELLIPSE_CENTER_Y, ELLIPSE_A, ELLIPSE_B)
	grid_overlay.set_grid_visible(false)

	# Fit camera to show entire playable area, reserving space for HUD panel
	# Playable area: wings + stage ellipse, x [-1000, 1000], y [-500, 500]
	var stage_bounds := Rect2(-1000, -500, 2000, 1000)
	camera.fit_to_stage(stage_bounds, 260.0)  # 250px panel + 10px gap

	# Connect HUD
	planning_hud.start_pressed.connect(_start_execution)
	planning_hud.add_leg_pressed.connect(_on_add_leg_pressed)

	# Start in planning phase
	GameManager.change_state(GameManager.GameState.PLAYING)
	GameManager.change_phase(GameManager.Phase.PLANNING)

	# Initialize path preview
	path_preview.setup(pathfinding, CLEAR_ZONE_LEFT.get_center(), CLEAR_ZONE_RIGHT.get_center())

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

	# Check if clicked on prop — select prop and start drag
	for prop in props:
		var half_size: Vector2 = prop.prop_size / 2.0
		var prop_rect: Rect2 = Rect2(prop.global_position - half_size, prop.prop_size)
		if prop_rect.has_point(world_pos):
			_dragging_entity = prop
			prop.is_being_dragged = true
			_drag_offset = prop.global_position - world_pos
			_select_prop(prop)
			return

	# Clicked on nothing — deselect
	_deselect_all()


func _planning_handle_drag(world_pos: Vector2) -> void:
	# Dragging a target ghost — constrain to stage
	if _dragging_target_prop:
		var ghost_pos: Vector2 = world_pos + _drag_offset
		if is_on_stage(ghost_pos):
			# Update the last leg's destination (the one the ghost represents)
			var prop: StaticBody2D = _dragging_target_prop
			for i in range(prop.movement_plan.size() - 1, -1, -1):
				if prop.movement_plan[i].has("destination"):
					prop.movement_plan[i].destination = ghost_pos
					break
			prop.set_target(ghost_pos)
		path_preview.invalidate(true)
		return

	if not _dragging_entity:
		return

	var target_pos: Vector2 = world_pos + _drag_offset

	# Clamp to backstage area
	target_pos.x = clamp(target_pos.x, BACKSTAGE_RECT.position.x, BACKSTAGE_RECT.position.x + BACKSTAGE_RECT.size.x)
	target_pos.y = clamp(target_pos.y, BACKSTAGE_RECT.position.y, BACKSTAGE_RECT.position.y + BACKSTAGE_RECT.size.y)

	_dragging_entity.global_position = target_pos

	if _is_dragging_affects_selected_path():
		path_preview.invalidate()


func _planning_handle_release() -> void:
	if _dragging_entity and _dragging_entity is StaticBody2D:
		_dragging_entity.is_being_dragged = false
	_dragging_entity = null
	_dragging_target_prop = null
	_drag_offset = Vector2.ZERO


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

	# Check if right-clicked inside a clear zone — toggle stagehand assignment
	if CLEAR_ZONE_LEFT.has_point(world_pos):
		_toggle_clear_zone_assignment(selected_stagehand, true)
		return
	if CLEAR_ZONE_RIGHT.has_point(world_pos):
		_toggle_clear_zone_assignment(selected_stagehand, false)
		return

	# Check if right-clicked on a prop — toggle stagehand assignment on the active leg
	for prop in props:
		var half_size: Vector2 = prop.prop_size / 2.0
		var prop_rect: Rect2 = Rect2(prop.global_position - half_size, prop.prop_size)
		if prop_rect.has_point(world_pos):
			_toggle_stagehand_on_prop(selected_stagehand, prop)
			return

	# Right-click on stage floor — set destination for the next incomplete leg (one at a time)
	if selected_stagehand.has_assignment and is_on_stage(world_pos):
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

	# Right-click in backstage — reposition stagehand directly
	if is_in_backstage(world_pos):
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


func _toggle_clear_zone_assignment(stagehand: CharacterBody2D, is_left: bool) -> void:
	if is_left:
		if _clear_zone_left_stagehand == stagehand:
			_clear_zone_left_stagehand = null
			print("Unassigned ", stagehand.stagehand_name, " from Clear (L)")
		else:
			# If stagehand was on the other zone, remove them from it
			if _clear_zone_right_stagehand == stagehand:
				_clear_zone_right_stagehand = null
			_clear_zone_left_stagehand = stagehand
			print("Assigned ", stagehand.stagehand_name, " -> Clear (L)")
	else:
		if _clear_zone_right_stagehand == stagehand:
			_clear_zone_right_stagehand = null
			print("Unassigned ", stagehand.stagehand_name, " from Clear (R)")
		else:
			if _clear_zone_left_stagehand == stagehand:
				_clear_zone_left_stagehand = null
			_clear_zone_right_stagehand = stagehand
			print("Assigned ", stagehand.stagehand_name, " -> Clear (R)")
	_update_hud()
	path_preview.set_clear_zone_stagehands(_clear_zone_left_stagehand, _clear_zone_right_stagehand)


func _on_add_leg_pressed() -> void:
	# Add a new leg to the selected prop (or the first prop the selected stagehand is assigned to)
	var prop: StaticBody2D = selected_prop
	if not prop and selected_stagehand and selected_stagehand.assigned_props.size() > 0:
		prop = selected_stagehand.assigned_props[0]

	if not prop:
		print("No prop selected for Add Leg")
		return

	# Only add a new leg if the current active leg already has a destination
	if prop.get_active_leg_index() >= 0:
		print("Current leg still needs a destination before adding another")
		return

	var leg_idx: int = prop.add_leg()
	_update_hud()
	print("Added leg ", leg_idx + 1, " to ", prop.prop_name)


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
	path_preview.set_execution_mode(true)

	# Initialize prop-driven execution
	_active_props.clear()
	_prop_execution.clear()
	_props_waiting_for_stagehand.clear()
	_execution_ending = false

	for prop in props:
		if prop.has_plan():
			prop.current_leg_index = 0
			_active_props.append(prop)
			_start_leg(prop)


func _end_execution() -> void:
	_is_planning = true
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

	# Clear zone assignments — must be reassigned each round
	_clear_zone_left_stagehand = null
	_clear_zone_right_stagehand = null

	_deselect_all()
	path_preview.set_execution_mode(false)
	_update_hud()


# =============================================================================
# EXECUTION — prop-driven leg system
# =============================================================================

func _is_stagehand_busy(sh: CharacterBody2D) -> bool:
	## A stagehand is busy if they are moving, carrying, or have carried props.
	if sh.current_state == StagehandController.State.CARRYING:
		return true
	if sh.current_state == StagehandController.State.MOVING:
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
		# Send all stagehands to pick-up position
		var pickup_pos: Vector2 = prop.get_pickup_position()
		_prop_execution[prop].dispatched = leg_stagehands.duplicate()
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
			_check_execution_end_condition()
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

	# Lead drops the prop
	if lead.is_carrying(prop):
		var dropped: Node2D = lead.put_down_prop(prop, props_container)
		if dropped:
			dropped.on_put_down(dropped.global_position)

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


func _check_execution_end_condition() -> void:
	# Both clear zones must have an assigned stagehand standing inside
	if not _clear_zone_left_stagehand or not _clear_zone_right_stagehand:
		return
	if not CLEAR_ZONE_LEFT.has_point(_clear_zone_left_stagehand.global_position):
		return
	if not CLEAR_ZONE_RIGHT.has_point(_clear_zone_right_stagehand.global_position):
		return
	# All other stagehands must be idle
	for sh in stagehands:
		if sh == _clear_zone_left_stagehand or sh == _clear_zone_right_stagehand:
			continue
		if sh.current_state == StagehandController.State.MOVING or sh.current_state == StagehandController.State.CARRYING:
			return
	_end_execution()


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
		planning_hud.update_task_list(props, _clear_zone_left_stagehand, _clear_zone_right_stagehand)


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
	var zone_target: Variant = _get_clear_zone_target(stagehand)
	if zone_target != null:
		stagehand.move_to(zone_target as Vector2)
		return
	var wing_pos: Vector2 = _get_nearest_wing_position(stagehand.global_position)
	stagehand.move_to(wing_pos)


func _get_clear_zone_target(stagehand: CharacterBody2D) -> Variant:
	if stagehand == _clear_zone_left_stagehand:
		return CLEAR_ZONE_LEFT.get_center()
	if stagehand == _clear_zone_right_stagehand:
		return CLEAR_ZONE_RIGHT.get_center()
	return null
