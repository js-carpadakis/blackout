extends Node2D
## Physics chain simulating a stage scrim curtain on a horizontal track.
## All segments are kinematic; X positions are solved by a chain constraint.
## Pull mode: constraint solves backward from lead — segments bunch at anchor.
## Retract mode: constraint solves forward from anchor — segments bunch at lead.

const SEGMENT_COUNT := 52
const VISUAL_HEIGHT := 10.0
const FOLD_AMPLITUDE := 30.0       # Max Y deviation when fully bunched (px)
const FOLD_HALF_LOOP_SEGS := 2.0   # Segments per half sine period (controls loop width)

var _segments: Array[RigidBody2D] = []

var _full_width: float = 1300.0
var _seg_w: float = 0.0
var _color: Color = Color.BLACK
var _wing_x: float = -650.0
var _wing_y: float = 0.0
var _dir: float = 1.0  # +1 = extends rightward, -1 = extends leftward
var _retracting: bool = false


func setup(full_width: float, seg_color: Color) -> void:
	_full_width = full_width
	_seg_w = _full_width / SEGMENT_COUNT
	_color = seg_color


func place_at_wing(wing_x: float, y: float, from_left: bool) -> void:
	_wing_x = wing_x
	_wing_y = y
	_dir = 1.0 if from_left else -1.0
	_clear_chain()
	_build_chain()


func set_lead_progress(progress: float) -> void:
	if _segments.is_empty():
		return
	_segments[-1].global_position = Vector2(_wing_x + progress * _full_width * _dir, _wing_y)


func set_lead_position(world_pos: Vector2) -> void:
	if _segments.is_empty():
		return
	# Lead stays on track Y; only X follows the stagehand
	_segments[-1].global_position = Vector2(world_pos.x, _wing_y)


func set_retracting(value: bool) -> void:
	_retracting = value


func get_lead_position() -> Vector2:
	if _segments.is_empty():
		return Vector2(_wing_x, _wing_y)
	return _segments[-1].global_position


# =============================================================================
# INTERNAL
# =============================================================================

func _clear_chain() -> void:
	for seg in _segments:
		if is_instance_valid(seg):
			remove_child(seg)
			seg.free()
	_segments.clear()


func _build_chain() -> void:
	for i in range(SEGMENT_COUNT):
		var seg := RigidBody2D.new()
		seg.freeze = true
		seg.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		seg.gravity_scale = 0.0
		seg.collision_layer = 0
		seg.collision_mask = 0

		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(_seg_w, VISUAL_HEIGHT)
		col.shape = shape
		seg.add_child(col)

		seg.global_position = Vector2(_wing_x, _wing_y)
		add_child(seg)
		_segments.append(seg)


func _process(_delta: float) -> void:
	if _segments.is_empty():
		return

	# --- Step 1: Solve X positions ---
	var x: Array[float] = []
	x.resize(_segments.size())

	if _retracting:
		# Retract: solve forward from anchor — segments bunch at the lead (stagehand).
		var lead_x: float = _segments[-1].global_position.x
		x[0] = _wing_x
		for i in range(1, _segments.size()):
			var unconstrained := x[i - 1] + _seg_w * _dir
			if _dir > 0.0:
				x[i] = min(lead_x, unconstrained)
			else:
				x[i] = max(lead_x, unconstrained)
	else:
		# Pull: solve backward from lead — segments bunch at the anchor.
		x[-1] = _segments[-1].global_position.x
		for i in range(_segments.size() - 2, -1, -1):
			var unconstrained := x[i + 1] - _seg_w * _dir
			if _dir > 0.0:
				x[i] = max(_wing_x, unconstrained)
			else:
				x[i] = min(_wing_x, unconstrained)

	# --- Step 2: Compute Y offsets (smooth fold curve) ---
	# Compression at segment i: 0 = fully deployed (flat), 1 = fully bunched.
	# Phase indexes from the lead end during retract so folds appear at the stagehand.
	var y: Array[float] = []
	y.resize(_segments.size())
	y[-1] = _wing_y  # Lead stays on track

	for i in range(_segments.size() - 1):
		var gap := absf(x[i + 1] - x[i])
		var compression: float = 1.0 - clamp(gap / _seg_w, 0.0, 1.0)
		var phase_idx: int = (_segments.size() - 1 - i) if _retracting else i
		var phase := float(phase_idx) * PI / FOLD_HALF_LOOP_SEGS
		y[i] = _wing_y + FOLD_AMPLITUDE * sin(phase) * compression

	# --- Step 3: Apply positions ---
	for i in range(_segments.size()):
		_segments[i].global_position = Vector2(x[i], y[i])
		_segments[i].rotation = 0.0

	queue_redraw()


func _draw() -> void:
	if _segments.size() < 2:
		return

	# Draw the entire chain as a single ribbon — gives continuous fabric look
	var pts := PackedVector2Array()
	pts.resize(_segments.size())
	for i in range(_segments.size()):
		pts[i] = to_local(_segments[i].global_position)

	draw_polyline(pts, _color, VISUAL_HEIGHT, true)
