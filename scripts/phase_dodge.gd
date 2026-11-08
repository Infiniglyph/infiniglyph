extends Node
## Adapt the Library's phase-dash distance, timing, materialization and traces.
## Infiniglyph retains its carried velocity after the brief phase interval.
const Trace = preload("res://scripts/phase_trace.gd")
const Neon = preload("res://scripts/neon.gd")
const DISTANCE := 3.2
const MAX_DISTANCE := 6.4
const DURATION := 0.34
const SHIFT_POINT := 0.43
const VANISH_START := 0.30
const VANISH_END := 0.60
const COOLDOWN := 0.62
const CLEARANCE := 0.10
const MIN_DISTANCE := 0.35
signal started(origin: Vector3, destination: Vector3)
signal shifted(destination: Vector3)
signal finished
var actor: CharacterBody3D
var active := false
var has_shifted := false
var elapsed := 0.0
var cooldown := 0.0
var origin := Vector3.ZERO
var destination := Vector3.ZERO
var requested_distance := DISTANCE
var _direction := Vector3.ZERO
var _motion := Vector3.ZERO
var _saved_velocity := Vector3.ZERO
var _geometry: Array[GeometryInstance3D] = []
var _original_materials: Array[Material] = []
var _fade_material: StandardMaterial3D
var tint := Color(0.16,0.9,1.0)

func _ready() -> void:
	name = "PhaseDodge"
	cache_geometry()
	# Per-instance transparency is unavailable in Compatibility. Use a local
	# material during the phase, leaving the shared body material untouched.
	_fade_material = Neon.body.duplicate()
	_fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func set_tint(color: Color) -> void:
	tint = color
	_fade_material.albedo_color = color
	_fade_material.emission = color

func cache_geometry() -> void:
	_geometry.clear()
	_original_materials.clear()
	for node in actor.visual.find_children("*","GeometryInstance3D",true,false):
		_geometry.append(node)
		_original_materials.append(node.material_override)

func safe_motion(motion: Vector3) -> Vector3:
	var collision := actor.move_and_collide(motion,true)
	if collision == null: return motion
	var direction := motion.normalized()
	return direction*maxf(0,collision.get_travel().dot(direction)-CLEARANCE)

func start(direction: Vector3) -> bool:
	if is_instance_valid(actor.weapon_combat) and actor.weapon_combat.is_staggered(): return false
	if active or cooldown > 0 or direction.is_zero_approx(): return false
	_direction = Vector3(direction.x,0,direction.z).normalized()
	if _direction.is_zero_approx(): return false
	var momentum := Vector2(actor.velocity.x,actor.velocity.z).length()
	requested_distance = lerpf(DISTANCE,MAX_DISTANCE,clampf(momentum/actor.boost_speed,0,1))
	_motion = safe_motion(_direction*requested_distance)
	if _motion.length() < MIN_DISTANCE: return false
	cache_geometry()
	origin = actor.global_position
	destination = origin+_motion
	elapsed = 0.0
	has_shifted = false
	active = true
	cooldown = COOLDOWN
	_saved_velocity = actor.velocity
	actor.velocity = Vector3.ZERO
	trace(origin,false)
	started.emit(origin,destination)
	return true

func advance(delta: float) -> void:
	if not active: return
	elapsed = minf(DURATION,elapsed+delta)
	var progress := elapsed/DURATION
	if not has_shifted and progress >= SHIFT_POINT:
		# Repeat the full-capsule sweep when committing: a new blocker must also
		# stop the blink. Collision remains enabled throughout the phase.
		var motion := safe_motion(_motion)
		if motion.length() >= MIN_DISTANCE: actor.move_and_collide(motion)
		destination = actor.global_position
		has_shifted = true
		actor.camera_rig.reset_follow()
		trace(destination,true)
		shifted.emit(destination)
	present(phase_opacity())
	if progress >= 1:
		active = false
		present(1.0)
		actor.visual.rebase_after_phase()
		actor.velocity = _saved_velocity
		finished.emit()

func is_invulnerable() -> bool:
	var progress := elapsed/DURATION
	return active and progress>=VANISH_START and progress<=VANISH_END

func phase_opacity() -> float:
	if not active: return 1.0
	var progress := elapsed/DURATION
	if progress<VANISH_START: return 1-smoothstep(0,VANISH_START,progress)
	if progress<=VANISH_END: return 0.0
	return smoothstep(VANISH_END,1,progress)

func present(amount: float) -> void:
	var absence := 1-clampf(amount,0,1)
	actor.visual.scale = Vector3(lerpf(1,1.28,absence),maxf(0.035,amount),lerpf(1,1.28,absence))
	actor.visual.position.y = 0.95*absence
	_fade_material.albedo_color.a = amount
	for i in range(_geometry.size()):
		_geometry[i].material_override = _fade_material if active else _original_materials[i]

func trace(at: Vector3, materializing: bool) -> void:
	var effect := Trace.new()
	effect.color = tint
	effect.materializing = materializing
	actor.get_parent().add_child(effect)
	effect.global_position = at+Vector3.UP*0.95

func cancel() -> void:
	active = false
	has_shifted = false
	elapsed = 0.0
	cooldown = 0.0
	present(1.0)
