extends Camera2D
## Top-down 2D camera with view switching between stage-left and stage-right

signal view_switched(new_view: ViewSide)

enum ViewSide { STAGE_LEFT, STAGE_RIGHT }

@export var pan_speed: float = 300.0
@export var zoom_speed: float = 0.5
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var transition_duration: float = 0.5

var current_view: ViewSide = ViewSide.STAGE_LEFT
var _is_transitioning: bool = false


func _ready() -> void:
	make_current()
	zoom = Vector2(0.75, 0.75)


func _process(delta: float) -> void:
	if _is_transitioning:
		return

	_handle_pan_input(delta)
	_handle_zoom_input(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Tab to switch views
	if event.is_action_pressed("switch_view"):
		switch_view()


func _handle_pan_input(delta: float) -> void:
	var pan_direction: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("pan_left"):
		pan_direction.x -= 1
	if Input.is_action_pressed("pan_right"):
		pan_direction.x += 1
	if Input.is_action_pressed("pan_up"):
		pan_direction.y -= 1
	if Input.is_action_pressed("pan_down"):
		pan_direction.y += 1

	if pan_direction != Vector2.ZERO:
		pan_direction = pan_direction.normalized()
		# Flip X direction when viewing from stage-right
		if current_view == ViewSide.STAGE_RIGHT:
			pan_direction.x *= -1
		position += pan_direction * pan_speed * delta


func _handle_zoom_input(delta: float) -> void:
	var zoom_direction: float = 0.0

	if Input.is_action_pressed("zoom_in"):
		zoom_direction += 1
	if Input.is_action_pressed("zoom_out"):
		zoom_direction -= 1

	if zoom_direction != 0:
		var new_zoom: float = clamp(zoom.x + zoom_direction * zoom_speed * delta, min_zoom, max_zoom)
		zoom = Vector2(new_zoom, new_zoom)


func switch_view() -> void:
	if _is_transitioning:
		return

	_is_transitioning = true

	var target_scale_x: float
	if current_view == ViewSide.STAGE_LEFT:
		target_scale_x = -1.0
		current_view = ViewSide.STAGE_RIGHT
	else:
		target_scale_x = 1.0
		current_view = ViewSide.STAGE_LEFT

	# Flip the view by scaling the viewport horizontally
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(get_viewport(), "canvas_transform:x:x", target_scale_x, transition_duration)
	tween.tween_callback(_on_transition_complete)

	view_switched.emit(current_view)


func _on_transition_complete() -> void:
	_is_transitioning = false


func focus_on(world_position: Vector2) -> void:
	position = world_position
