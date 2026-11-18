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
const CLEARANCE := 0.10
const MIN_DISTANCE := 0.35
const GROUND_STEP := 0.5
const GROUND_SNAP := 0.65
signal started(origin: Vector3, destination: Vector3)
signal shifted(destination: Vector3)
signal finished
var actor: CharacterBody3D
var active := false
var has_shifted := false
var elapsed := 0.0
var origin := Vector3.ZERO
var destination := Vector3.ZERO
var requested_distance := DISTANCE
var _direction := Vector3.ZERO
var _motion := Vector3.ZERO
var _saved_velocity := Vector3.ZERO
var _follow_floor := false
var _geometry: Array[GeometryInstance3D] = []
var _original_materials: Array[Material] = []
var _fade_material: StandardMaterial3D
var tint := Color(0.16,0.9,1.0)
var rest_scale := Vector3.ONE
var rest_position := Vector3.ZERO

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

func _walkable(normal: Vector3) -> bool:
	return normal.dot(actor.up_direction)>=cos(actor.floor_max_angle)

func _support(pose: Transform3D, distance: float) -> KinematicCollision3D:
	var contact := KinematicCollision3D.new()
	if actor.test_move(pose,Vector3.DOWN*distance,contact) and _walkable(contact.get_normal()): return contact
	return null

func _plan_motion(horizontal: Vector3, follow_floor: bool) -> PackedVector3Array:
	# A horizontal sweep runs into the ground immediately when facing uphill.
	# Follow supported, walkable planes with short full-capsule sweeps instead.
	# Every leg is collision-tested; walls never become floor projections.
	var path := PackedVector3Array()
	var pose := actor.global_transform
	var contact := _support(pose,actor.floor_snap_length) if follow_floor else null
	if contact==null:
		path.append(pose.origin+safe_motion(horizontal))
		return path
	var normal := contact.get_normal()
	var distance := horizontal.length()
	var direction := horizontal.normalized()
	while distance>.0001:
		var length := minf(GROUND_STEP,distance)
		var motion := direction*length
		if not normal.is_zero_approx(): motion.y = -normal.dot(motion)/normal.y
		for redirect in range(4):
			var hit := KinematicCollision3D.new()
			if not actor.test_move(pose,motion,hit):
				pose.origin += motion
				path.append(pose.origin)
				break
			var travel := hit.get_travel()
			if not _walkable(hit.get_normal()):
				pose.origin += motion.normalized()*maxf(0,travel.dot(motion.normalized())-CLEARANCE)
				path.append(pose.origin)
				return path
			pose.origin += travel
			path.append(pose.origin)
			normal = hit.get_normal()
			motion -= travel
			motion.y = -normal.dot(Vector3(motion.x,0,motion.z))/normal.y
			if redirect==3: return path
		if not normal.is_zero_approx():
			contact = _support(pose,GROUND_SNAP)
			if contact!=null:
				pose.origin += contact.get_travel()
				path.append(pose.origin)
				normal = contact.get_normal()
			else:
				# Leaving a roof or cliff keeps the rest of the blink horizontal;
				# it cannot snap to distant ground beneath the ledge.
				normal = Vector3.ZERO
		distance -= length
	return path

func start(direction: Vector3) -> bool:
	if is_instance_valid(actor.weapon_combat) and not actor.weapon_combat.can_act(): return false
	if direction.is_zero_approx(): return false
	_direction = Vector3(direction.x,0,direction.z).normalized()
	if _direction.is_zero_approx(): return false
	if active:
		# A fresh press chains immediately, even during departure. Settle the old
		# swept displacement first so rapid presses cannot keep resetting its
		# clock before it travels. Restore materials before caching the new phase.
		if not has_shifted: commit_shift()
		finish_phase()
	var momentum := Vector2(actor.velocity.x,actor.velocity.z).length()
	requested_distance = lerpf(DISTANCE,MAX_DISTANCE,clampf(momentum/actor.boost_speed,0,1))
	# Uphill running itself has positive vertical velocity while still grounded.
	_follow_floor = actor.is_on_floor()
	var path := _plan_motion(_direction*requested_distance,_follow_floor)
	_motion = path[-1]-actor.global_position if not path.is_empty() else Vector3.ZERO
	if Vector2(_motion.x,_motion.z).length() < MIN_DISTANCE: return false
	cache_geometry()
	origin = actor.global_position
	destination = origin+_motion
	elapsed = 0.0
	has_shifted = false
	active = true
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
		commit_shift()
	present(phase_opacity())
	if progress >= 1: finish_phase()

func commit_shift() -> void:
	# Repeat the full-capsule sweep when committing: a new blocker must also
	# stop the blink. Collision remains enabled throughout the phase.
	var path := _plan_motion(Vector3(_motion.x,0,_motion.z),_follow_floor)
	if not path.is_empty() and Vector2(path[-1].x-actor.global_position.x,path[-1].z-actor.global_position.z).length()>=MIN_DISTANCE:
		for point: Vector3 in path:
			var hit := actor.move_and_collide(point-actor.global_position)
			if hit!=null and not _walkable(hit.get_normal()): break
	destination = actor.global_position
	has_shifted = true
	actor.camera_rig.reset_follow()
	trace(destination,true)
	shifted.emit(destination)

func finish_phase() -> void:
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
	actor.visual.scale = rest_scale*Vector3(lerpf(1,1.28,absence),maxf(0.035,amount),lerpf(1,1.28,absence))
	actor.visual.position = rest_position+Vector3.UP*(0.95*rest_scale.y*absence)
	_fade_material.albedo_color.a = amount
	for i in range(_geometry.size()):
		if is_instance_valid(_geometry[i]): _geometry[i].material_override = _fade_material if active else _original_materials[i]

func trace(at: Vector3, materializing: bool) -> void:
	var effect := Trace.new()
	effect.color = tint
	effect.stature = rest_scale
	effect.materializing = materializing
	actor.get_parent().add_child(effect)
	effect.global_position = at+Vector3.UP*(0.95*rest_scale.y)

func cancel() -> void:
	active = false
	has_shifted = false
	elapsed = 0.0
	present(1.0)
