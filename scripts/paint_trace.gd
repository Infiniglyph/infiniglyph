extends "res://scripts/equation_trace.gd"
## Paint-specific pen motion; collision, ownership, fade and reflection are shared.
const Patterns = preload("res://scripts/paintbrush_patterns.gd")
const BrushMoves = preload("res://scripts/paintbrush_moves.gd")
const BrushSettings = preload("res://scripts/paintbrush_settings.gd")
var tint := Color("bc9aff")
var light: Dictionary = {}

func _init() -> void:
	mathematical = false
	settings = BrushSettings.new()

func nib_position() -> Vector3:
	return combat.rig.left_hand.to_global(BrushMoves.TIP)

func tap_mark(value: StringName, tip: Vector3, frame: Basis) -> PackedVector3Array:
	return Patterns.mark(Patterns.shape(value),tip,frame,settings.minimum_mark_size)

func begin(value: StringName) -> void:
	light = {}
	super.begin(value)

func start_light(move: Dictionary) -> void:
	stop()
	light = move
	action = StringName(move.action)
	_has_last = false
	_was_down = false
	_last_stroke_id = -1
	_sample_clock = 0
	set_physics_process(true)

func stop() -> void:
	light = {}
	super.stop()

func prepare(delta: float) -> void:
	if action==&"": return
	var frame := Moves.writing_basis(combat.trace_aim_direction())
	var point := Vector2.ZERO
	if not light.is_empty():
		age = combat.elapsed
		var start: float = light.windup
		var end: float = float(light.duration)*.76
		var progress := smoothstep(start,end,age)
		point = Vector2(1,-1 if action==&"attack_left" else 1).normalized()*(progress-.5)*settings.light_stroke_length
		_pen_down = age>=start and age<=end
		_stroke_id = 0
	else:
		age += delta
		var pattern := Patterns.shape(action)
		var period: float = {&"square":settings.square_frequency,&"triangle":settings.triangle_frequency,&"cross":settings.x_frequency,&"circle":settings.y_frequency}[pattern]
		var pen := Patterns.pen(pattern,fposmod(age/period,1))
		point = pen.point*lerpf(float(settings.minimum_mark_size),float(settings.pattern_radius),smoothstep(0,.15,age))
		_pen_down = pen.down
		_stroke_id = floori(age/period)*2+int(pen.stroke) if pattern==&"cross" else 0
	var target: Vector3 = actor.combat_point()+frame*Vector3(-.27+point.x,.65+point.y,.52)
	var offset: Vector3 = combat.paint_brush_basis()*BrushMoves.TIP
	var shoulder: Vector3 = actor.visual.joints.LeftArm.global_position
	var hand: Vector3 = shoulder+(target-offset-shoulder).limit_length(.565)
	desired_tip = hand+offset

func append_section(points: PackedVector3Array, metadata: Dictionary = {}) -> void:
	var paint := {"tint":tint,"damage":settings.damage if light.is_empty() else float(light.damage),"action":&"paint_trace" if light.is_empty() else action}
	paint.merge(metadata,true)
	super.append_section(points,paint)

func section_color(section: Dictionary) -> Color:
	# Retain the brush's pigment through reflection and after a color switch.
	return section.get("tint",tint)
