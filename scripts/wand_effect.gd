extends Node3D
## Bounded wand casts. Shared strike resolution owns damage, dodge, guard,
## witnesses and parry recoil; this node owns only flight and laser geometry.
const Neon = preload("res://scripts/neon.gd")
const MAX_CASTS := 32
const MAX_TRAIL_POINTS := 9
const GROUND_WINDUP := .22
const GROUND_LIFETIME := 1.05
const DEFLECT_LIFETIME := .28
const HOMING_ANGLE := .65
const HOMING_TURN := .58
var actor: CharacterBody3D
var combat: Node
var move: Dictionary = {}
var attack := "flick"
var direction := Vector3.FORWARD
var color := Color.CYAN
var age := 0.0
var alive := true
var deflected := false
var cancelled_by_parry := false
var _origin := Vector3.ZERO
var _ground := Vector3.ZERO
var _target: WeakRef
var _bolts: Array[Dictionary] = []
var _visited: Dictionary = {}
var _rays: Array[Dictionary] = []
var _mesh := ImmediateMesh.new()
var _ink: StandardMaterial3D
var _shape := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _ground_clock := 0.0
var _deflect_age := 0.0
var _deflect_serial := 0

func configure(caster: CharacterBody3D, weapon: Node, definition: Dictionary, origin: Vector3, forward: Vector3, tint: Color, target: Node3D = null) -> void:
	actor = caster
	combat = weapon
	move = definition.duplicate(true)
	attack = String(move.get("wand_attack","flick"))
	_origin = origin
	direction = forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD
	color = tint
	if is_instance_valid(target): _target = weakref(target)

func _ready() -> void:
	name = "WandLaserCast"
	# Do not put gameplay projectiles in the cosmetic weapon_effects group:
	# the latter has an independent presentation-only eviction budget.
	var active := get_tree().get_nodes_in_group("wand_effects")
	while active.size()>=MAX_CASTS:
		var oldest: Node = active.pop_front()
		if is_instance_valid(oldest): oldest.expire()
	add_to_group("wand_effects")
	top_level = true
	global_position = Vector3.ZERO
	_ink = Neon.material(color)
	_ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ink.emission_energy_multiplier = 1.7
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	_shape.radius = .65 if attack=="wheel" else .13 if attack=="flick" else .17
	_query.shape = _shape
	_query.collision_mask = 6
	_query.exclude = [actor.get_rid()]
	if attack=="ground":
		_prepare_ground()
	else:
		if attack=="slither" and (_target==null or not is_instance_valid(_target.get_ref())): _acquire_target()
		var target_point := _target_point()
		if attack=="slither" and target_point!=Vector3.INF:
			var toward := (target_point-_origin).normalized()
			# Initial aim remains within the same limited acquisition cone.
			if direction.dot(toward)>=cos(HOMING_ANGLE): direction=direction.slerp(toward,.38).normalized()
			else: _target=null
		var lanes: Array = [-1,0,1] if attack=="volley" else [0]
		for lane: int in lanes:
			var heading := direction.rotated(Vector3.UP,float(lane)*.055).normalized()
			_bolts.append({"position":_origin,"heading":heading,"distance":0.0,"turn":0.0,"phase":float(lane)*1.7,"trail":[_origin],"visited":{},"live":true})
	_draw()

func expire() -> void:
	if not alive: return
	alive=false
	set_physics_process(false)
	remove_from_group("wand_effects")
	queue_free()

func _valid_caster() -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and is_instance_valid(combat) and actor.get("transition_locked")!=true and float(combat.get("health"))>0

func _target_point() -> Vector3:
	if _target==null: return Vector3.INF
	var target: Node3D = _target.get_ref()
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_visible_in_tree(): return Vector3.INF
	if target.get("health")!=null and float(target.get("health"))<=0: return Vector3.INF
	var weapon: Node = target.get("weapon_combat")
	if is_instance_valid(weapon) and float(weapon.get("health"))<=0: return Vector3.INF
	return target.combat_point() if target.has_method("combat_point") else target.global_position+Vector3.UP*.9

func _acquire_target() -> void:
	# One bounded acquisition at launch. No reacquisition after a dodge or miss.
	var sphere := SphereShape3D.new()
	sphere.radius = float(move.get("reach",12))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,_origin)
	query.collision_mask=6
	query.exclude=[actor.get_rid()]
	var best := INF
	var selected: Node3D
	var seen: Dictionary = {}
	for candidate: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,32):
		var target: Node3D = candidate.collider
		if seen.has(target): continue
		seen[target]=true
		if not target.has_method("receive_hit") or not actor.can_attack_target(target): continue
		var point: Vector3 = target.combat_point() if target.has_method("combat_point") else target.global_position+Vector3.UP*.9
		var offset := point-_origin
		if offset.is_zero_approx() or direction.dot(offset.normalized())<cos(HOMING_ANGLE): continue
		if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(_origin,point,9,[actor.get_rid(),target.get_rid()])).is_empty(): continue
		var score := offset.length_squared()
		if score<best:
			best=score
			selected=target
	if is_instance_valid(selected): _target=weakref(selected)

func _prepare_ground() -> void:
	var distance := minf(6,float(move.get("reach",9)))
	var target_point := _target_point()
	if target_point!=Vector3.INF: distance=clampf((_origin-target_point).length(),1,float(move.get("reach",9)))
	var flat := Vector3(direction.x,0,direction.z).normalized()
	if flat.is_zero_approx(): flat=Vector3.FORWARD
	var destination := _origin+flat*distance
	var space := get_world_3d().direct_space_state
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(_origin,destination,9,[actor.get_rid()]))
	if not wall.is_empty(): destination=wall.position+wall.normal*.4
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(destination+Vector3.UP*2,destination-Vector3.UP*8,9,[actor.get_rid()]))
	# No floating AoE if a cast misses all walkable ground.
	if floor_hit.is_empty() or floor_hit.normal.y<.55:
		expire()
		return
	_ground=floor_hit.position+Vector3.UP*.045

func _physics_process(delta: float) -> void:
	if not alive: return
	if not _valid_caster():
		expire()
		return
	age+=delta
	if deflected:
		_deflect_age+=delta
		if _deflect_age>=DEFLECT_LIFETIME: expire()
	elif attack=="ground":
		_ground_clock-=delta
		if age>=GROUND_WINDUP and _ground_clock<=0:
			_ground_clock=.05
			_ground_contacts()
		if age>=GROUND_LIFETIME: expire()
	else:
		for bolt in _bolts:
			if not bool(bolt.live): continue
			_advance_bolt(bolt,delta)
			if deflected: break
		var remaining := false
		for bolt in _bolts: remaining=remaining or bool(bolt.live)
		if not remaining and not deflected: expire()
		if age>1.4 and not deflected: expire()
	if alive: _draw()

func _advance_bolt(bolt: Dictionary, delta: float) -> void:
	var previous: Vector3 = bolt.position
	var heading: Vector3 = bolt.heading
	var speed := 34.0 if attack=="flick" else 30.0 if attack=="volley" else 20.0
	var reach := float(move.get("reach",12))
	var step := minf(speed*delta,maxf(0,reach-float(bolt.distance)))
	if attack=="slither":
		var target_point := _target_point()
		if target_point!=Vector3.INF:
			var offset := target_point-previous
			# A target behind this outbound projectile has been missed. It cannot
			# orbit, turn around, acquire a replacement or make a second pass.
			if float(bolt.distance)>1 and heading.dot(offset)<=0:
				bolt.live=false
				return
			var desired := offset.normalized()
			var angle := heading.angle_to(desired)
			var turn := minf(minf(angle,1.2*delta),maxf(0,HOMING_TURN-float(bolt.turn)))
			if angle>.00001 and heading.dot(direction)>.45:
				heading=heading.slerp(desired,turn/angle).normalized()
				bolt.turn=float(bolt.turn)+turn
		bolt.heading=heading
	var right := heading.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right=Vector3.RIGHT
	# Integrate the derivative of a small sinusoid, rather than repeatedly
	# adding its offset. This preserves a clean forward trajectory.
	var distance_before := float(bolt.distance)
	var distance_after := distance_before+step
	var weave := (sin(distance_after*2.1)-sin(distance_before*2.1))*.17 if attack=="slither" else 0.0
	var next := previous+heading*step+right*weave
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(previous,next,9,[actor.get_rid()]))
	if not wall.is_empty():
		next=wall.position
		bolt.live=false
		combat.environment_contact.emit(wall.collider,int(move.get("attack_serial",0)))
	var segment := next-previous
	if segment.length_squared()>.000001:
		_shape.height=maxf(_shape.radius*2,segment.length()+_shape.radius*2)
		_query.transform=Transform3D(Basis(Quaternion(Vector3.UP,segment.normalized())),(previous+next)*.5)
		var contacts: Array = get_world_3d().direct_space_state.intersect_shape(_query,32)
		# Closest contact first: compound hurtboxes never reorder a near parry
		# behind a farther victim along the same projectile sweep.
		contacts.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return previous.distance_squared_to(a.collider.global_position)<previous.distance_squared_to(b.collider.global_position))
		for candidate: Dictionary in contacts:
			if bolt.visited.has(candidate.collider): continue
			var target: Node3D = candidate.collider
			if target==actor or not target.has_method("receive_hit") or not actor.can_attack_target(target): continue
			bolt.visited[target]=true
			candidate.contact=previous.lerp(next,.5)
			if _resolve(candidate,previous):
				deflect(candidate.contact)
				return
			# One outbound contact per bolt, including a successful dodge/block.
			bolt.live=false
			break
	bolt.position=next
	bolt.distance=distance_after
	bolt.trail.append(next)
	while bolt.trail.size()>MAX_TRAIL_POINTS: bolt.trail.pop_front()
	if distance_after>=reach: bolt.live=false

func _resolve(candidate: Dictionary, source: Vector3) -> bool:
	var target: Node3D = candidate.collider
	var defender: Node = target.get("weapon_combat")
	var previous_parries := int(defender.get("total_parries")) if is_instance_valid(defender) else 0
	combat.resolve_strike(move,-1,source,[candidate],false,true)
	# A prior parry flag may remain set while shared resolution rejects an
	# obstructed contact. Only a new, confirmed receiver parry deflects this cast.
	return is_instance_valid(defender) and int(defender.get("total_parries"))>previous_parries

func _ground_contacts() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius=2.35
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,_ground+Vector3.UP*.65)
	query.collision_mask=6
	query.exclude=[actor.get_rid()]
	for candidate: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,32):
		var target: Node3D = candidate.collider
		if _visited.has(target) or target==actor or not target.has_method("receive_hit") or not actor.can_attack_target(target): continue
		# Only the near-ground part of this volume is active; airborne evasion
		# and ordinary dodge invulnerability both remain effective.
		if target.global_position.y-_ground.y>1.35: continue
		_visited[target]=true
		candidate.contact=target.global_position+Vector3.UP*.3
		if _resolve(candidate,_origin):
			deflect(candidate.contact)
			break

func deflect(point: Vector3) -> void:
	if deflected or not alive: return
	deflected=true
	cancelled_by_parry=true
	_target=null
	_bolts.clear()
	_visited.clear()
	# The normal receiver already called original_caster.on_parried(). Do
	# not replace its stagger/recovery duration or trigger a second recoil.
	# Remaining energy is presentation only: no target query or hurt volume.
	_deflect_serial+=1
	var random := RandomNumberGenerator.new()
	random.seed=int(get_instance_id())+int(move.get("attack_serial",0))*7919+_deflect_serial
	for i in range(3):
		var azimuth := random.randf_range(-PI,PI)
		var ray := Vector3(sin(azimuth),random.randf_range(-.3,.65),cos(azimuth)).normalized()
		_rays.append({"origin":point,"direction":ray,"length":random.randf_range(1.4,2.8)})

func _draw() -> void:
	_mesh.clear_surfaces()
	var points := PackedVector3Array()
	if deflected:
		var travel := _deflect_age*13
		for ray in _rays:
			points.append_array([ray.origin+ray.direction*travel,ray.origin+ray.direction*(travel+float(ray.length))])
		_ink.albedo_color.a=1-smoothstep(0,DEFLECT_LIFETIME,_deflect_age)
	elif attack=="ground":
		var radius := 2.35
		for i in range(32):
			var a := i*TAU/32
			var b := (i+1)*TAU/32
			points.append_array([_ground+Vector3(cos(a),0,sin(a))*radius,_ground+Vector3(cos(b),0,sin(b))*radius])
		for i in range(8):
			var a := i*TAU/8
			var b := a+TAU*3/8
			points.append_array([_ground+Vector3(cos(a),0,sin(a))*radius,_ground+Vector3(cos(b),0,sin(b))*radius])
		if age>=GROUND_WINDUP:
			for i in range(8):
				var point := _ground+Vector3(cos(i*TAU/8),0,sin(i*TAU/8))*1.7
				points.append_array([point,point+Vector3.UP*(.3+sin(age*15+i)*.15)])
		_ink.albedo_color.a=(.28 if age<GROUND_WINDUP else 1.0)*(1-smoothstep(.7,GROUND_LIFETIME,age))
	else:
		for bolt in _bolts:
			var trail: Array = bolt.trail
			for i in range(1,trail.size()): points.append_array([trail[i-1],trail[i]])
			var tip: Vector3 = bolt.position
			var heading: Vector3 = bolt.heading
			if attack=="wheel":
				var side := heading.cross(Vector3.UP).normalized()
				if side.is_zero_approx(): side=Vector3.RIGHT
				for i in range(20):
					for ring in [1.0,.78]:
						var a := i*TAU/20+age*22
						var b := (i+1)*TAU/20+age*22
						points.append_array([tip+(side*cos(a)+Vector3.UP*sin(a))*.65*ring,tip+(side*cos(b)+Vector3.UP*sin(b))*.65*ring])
				for i in range(4):
					var a := i*TAU/4+age*22
					points.append_array([tip,tip+(side*cos(a)+Vector3.UP*sin(a))*.65])
			elif attack=="flick":
				var side := heading.cross(Vector3.UP).normalized()
				for i in range(6):
					var a := lerpf(-1.0,1.0,i/6.0)
					var b := lerpf(-1.0,1.0,(i+1)/6.0)
					points.append_array([tip+side*sin(a)*.42-heading*(1-cos(a))*.3,tip+side*sin(b)*.42-heading*(1-cos(b))*.3])
			else: points.append_array([tip-heading*.45,tip+heading*.15])
	if points.is_empty(): return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES,_ink)
	for point in points: _mesh.surface_add_vertex(point)
	_mesh.surface_end()
