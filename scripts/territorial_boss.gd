extends CharacterBody3D
## Collision-aware territorial creature. Perception only samples visible state;
## no player control/input object is inspected by its decision system.
const Visual = preload("res://scripts/griffin_visual.gd")
const Combat = preload("res://scripts/greefer_combat.gd")
const Intent = preload("res://scripts/combat_intent.gd")
const Dodge = preload("res://scripts/phase_dodge.gd")
const Lock = preload("res://scripts/target_lock.gd")
const Moves = preload("res://scripts/greefer_moves.gd")
const PERCH := Vector3(0,86.65,-62)
class BrainInterface extends Node:
	var owner_actor: CharacterBody3D
	func on_forced_reaction() -> void:
		owner_actor.guard_time = 0
		owner_actor.decision_clock = 0.3
class AimFrame extends Node3D:
	var yaw := 0.0
	func reset_follow() -> void: pass

@export var base_health := 1800.0
@export var ground_speed := 7.8
@export var flight_speed := 19.0
@export var awareness_range := 155.0
@export var search_duration := 12.0
@export var perch_point := PERCH
var encounter: Node
var visual: Node3D
var weapon_combat: Node
var combat: Node
var dodge: Node
var target_lock: Node3D
var camera_rig: Node3D
var controls: Node
var boost_active := false
var health: float:
	get: return weapon_combat.health if is_instance_valid(weapon_combat) else base_health
var state := &"perched"
var flight_mode := false
var facing := Vector3.BACK
var last_known := Vector3.ZERO
var visible_target := false
var unseen_time := 0.0
var perception_clock := 0.0
var decision_clock := 0.0
var state_age := 0.0
var guard_time := 0.0
var defense_cooldown := 0.0
var observed_windup := 0.0
var attack_cursor := 0
var attack_goal := Vector3.ZERO
var launch_point := Vector3.ZERO
var launch_cleared := false
var think_enabled := true
var _land_goal := Vector3.ZERO
var _landing_valid := false
var _landing_clock := 0.0
var _steer_clock := 0.0
var _steer := Vector3.ZERO
var _stall := 0.0
var _escape := 0.0
var _last_position := Vector3.ZERO
var _body_shape: CapsuleShape3D
var _return_high := false
var navigation_recoveries := 0
var decisions := 0

func _ready() -> void:
	name = "Greefer"
	position = perch_point
	collision_layer = 3
	collision_mask = 1 # Pedestrian layer is intentionally excluded.
	floor_snap_length = 0.30
	floor_max_angle = deg_to_rad(45)
	_body_shape = CapsuleShape3D.new()
	_body_shape.radius = 0.96
	_body_shape.height = 2.8
	var collision := CollisionShape3D.new()
	collision.shape = _body_shape
	collision.position.y = 1.42
	add_child(collision)
	var hurtbox := CollisionShape3D.new()
	var chest := SphereShape3D.new()
	chest.radius = 0.65
	hurtbox.shape = chest
	hurtbox.position = Vector3(0,2.1,0.70)
	add_child(hurtbox)
	visual = create_visual()
	add_child(visual)
	controls = BrainInterface.new()
	controls.owner_actor = self
	add_child(controls)
	camera_rig = AimFrame.new()
	add_child(camera_rig)
	combat = Intent.new()
	add_child(combat)
	combat.sheathed = false
	dodge = Dodge.new()
	dodge.actor = self
	add_child(dodge)
	target_lock = Lock.new()
	target_lock.actor = self
	target_lock.show_marker = false
	add_child(target_lock)
	weapon_combat = create_combat()
	weapon_combat.actor = self
	weapon_combat.max_health = base_health
	weapon_combat.health = base_health
	weapon_combat.rules.base_fortitude = 1.15
	add_child(weapon_combat)
	_last_position = position

# Future territorial creatures override their presentation/moves here while
# inheriting perception, flight, collision steering and encounter behavior.
func create_visual() -> Node3D: return Visual.new()
func create_combat() -> Node: return Combat.new()
func attack_for(style: StringName) -> Dictionary: return Moves.move(style)

func combat_name() -> String: return "GREEFER"
func combat_point() -> Vector3: return global_position+Vector3.UP*1.3
func body_impact_point(point: Vector3) -> Vector3:
	var local := visual.to_local(point)
	var center := Vector3(0,1.6,clampf(local.z,-1.4,1.2))
	var radial := (local-center)/Vector3(0.78,0.75,1)
	return visual.to_global(center+radial.normalized()*Vector3(0.78,0.75,0.7))

func can_attack_target(target: Node) -> bool:
	return encounter.active and target == encounter.player and encounter.has_authority()

func receive_hit(amount: float, source: Vector3, attacker: Node = null, incoming: Dictionary = {}) -> float:
	if not encounter.has_authority() or amount<=0 or state == &"defeated": return 0
	if attacker != encounter.player: return 0
	if not encounter.active and not encounter.start(true): return 0
	encounter.register_contact()
	return weapon_combat.receive_hit(amount,source,attacker,incoming)

func receive_combat_hit(amount: float, source: Vector3, attacker: Node, incoming: Dictionary = {}) -> float:
	return receive_hit(amount,source,attacker,incoming)

func on_parried(source: Vector3) -> void: weapon_combat.stagger(source)
func on_combat_defeat() -> void: encounter.finish(true)

func set_state(next: StringName) -> void:
	if state == next: return
	state = next
	state_age = 0

func alert() -> void:
	weapon_combat.reset()
	combat.sheathed = false
	last_known = encounter.player.global_position
	unseen_time = 0
	guard_time = 0
	launch_point = global_position+Vector3(0,8,11)
	launch_cleared = global_position.distance_to(perch_point)>6
	visible_target = can_see_player()
	set_state(&"alert")

func can_see_player() -> bool:
	var target: Node3D = encounter.player
	if global_position.distance_to(target.global_position)>awareness_range: return false
	# Two actual eye positions avoid a thin tower spoke blinding both eyes along
	# a single artificial center ray. A solid facade still occludes both rays.
	for side in [-1,1]:
		var eye: Vector3 = visual.head.to_global(Vector3(side*0.43,0.1,0.34))
		var query := PhysicsRayQueryParameters3D.create(eye,target.combat_point(),1,[get_rid(),target.get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return true
	return false

func perceive(delta: float) -> void:
	perception_clock -= delta
	unseen_time += delta
	if perception_clock>0: return
	perception_clock = 0.18
	visible_target = can_see_player()
	if visible_target:
		last_known = encounter.player.global_position
		unseen_time = 0
		if state in [&"searching",&"pursuing"]: set_state(&"engaged")
	elif state == &"engaged": set_state(&"searching")

func start_return() -> void:
	weapon_combat.cancel()
	combat.blocking = false
	guard_time = 0
	flight_mode = true
	_return_high = false
	set_state(&"returning")

func in_district(point: Vector3) -> bool:
	return absf(point.x)<110 and absf(point.z)<110 and point.y<195 and point.y>-8

func clear_body_at(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body_shape
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*1.42)
	query.collision_mask = 1
	query.margin = 0.035
	query.exclude = [get_rid(),encounter.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func landing_near(point: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	for offset in [Vector3(0,0,3.4),Vector3(3.4,0,0),Vector3(-3.4,0,0),Vector3(0,0,-3.4),Vector3(5,0,3),Vector3(-5,0,3),Vector3.ZERO]:
		var at: Vector3 = point+offset
		var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*6,at-Vector3.UP*9,1,[get_rid(),encounter.player.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<0.85 or hit.collider is CharacterBody3D: continue
		var floor_point: Vector3 = hit.position+Vector3.UP*0.045
		if not in_district(floor_point) or not clear_body_at(floor_point): continue
		var supported := true
		for probe in [Vector3(0.82,0,0),Vector3(-0.82,0,0),Vector3(0,0,0.82),Vector3(0,0,-0.82)]:
			var support := space.intersect_ray(PhysicsRayQueryParameters3D.create(floor_point+probe+Vector3.UP*0.3,floor_point+probe-Vector3.UP*0.3,1,[get_rid(),encounter.player.get_rid()]))
			if support.is_empty() or support.normal.y<0.85 or absf(support.position.y-hit.position.y)>0.12: supported = false
		if supported: return {"point":floor_point}
	return {}

func steer_to(goal: Vector3, speed: float, delta: float) -> void:
	var toward := goal-global_position
	if toward.length()<0.12:
		velocity = velocity.move_toward(Vector3.ZERO,30*delta)
		return
	_stall = _stall+delta if global_position.distance_to(_last_position)<speed*delta*0.1 else maxf(0,_stall-delta)
	_last_position = global_position
	_escape = maxf(0,_escape-delta)
	if _stall>0.65:
		_escape = 1.4
		_stall = 0
		navigation_recoveries += 1
	_steer_clock -= delta
	if _steer_clock<=0:
		_steer_clock = 0.12
		var desired := toward.normalized()
		if _escape>0: desired = (Vector3.UP+desired*0.15).normalized()
		var side := desired.cross(Vector3.UP).normalized()
		var options := [desired,(desired+Vector3.UP*1.6).normalized(),(desired+side*1.8).normalized(),(desired-side*1.8).normalized(),Vector3.UP,side,-side,Vector3.DOWN]
		var best := -INF
		var previous := _steer
		_steer = Vector3.ZERO
		for candidate: Vector3 in options:
			if candidate.is_zero_approx() or not in_district(global_position+candidate*4): continue
			if test_move(global_transform,candidate*minf(3.0,toward.length())): continue
			var score := candidate.dot(desired)+candidate.dot(previous)*0.12
			if score>best:
				best = score
				_steer = candidate
	velocity = velocity.move_toward(_steer*minf(speed,maxf(2,toward.length()*2)),35*delta)

func decide(delta: float) -> void:
	decision_clock = maxf(0,decision_clock-delta)
	defense_cooldown = maxf(0,defense_cooldown-delta)
	guard_time = maxf(0,guard_time-delta)
	if combat.blocking and guard_time<=0:
		combat.blocking = false
		weapon_combat._on_block(false)
	if weapon_combat.is_staggered() or not visible_target: return
	var distance := global_position.distance_to(last_known)
	var incoming: Dictionary = encounter.player.weapon_combat.active_move
	var telegraph: bool = not incoming.is_empty() and encounter.player.weapon_combat.elapsed<float(incoming.hits[0]) and distance<float(incoming.reach)+1
	observed_windup = observed_windup+delta if telegraph else 0.0
	if observed_windup>=0.17 and defense_cooldown<=0 and weapon_combat.active_move.is_empty() and distance<5.5:
		# Reaction is to an already visible windup, never a queued button press.
		combat.fresh_block = true
		combat.blocking = true
		weapon_combat._on_block(true)
		guard_time = 0.62
		defense_cooldown = 1.65
		return
	if combat.blocking or not weapon_combat.active_move.is_empty() or decision_clock>0: return
	decision_clock = 0.22
	decisions += 1
	var planar := Vector2(last_known.x-position.x,last_known.z-position.z).length()
	var elevation := last_known.y-position.y
	if flight_mode:
		# Finish a nearby supported landing before choosing another airborne
		# attack; otherwise short claw recoveries could hold a perpetual hover.
		if _landing_valid and global_position.distance_to(_land_goal)<5: return
		if distance<12 and distance>4.5:
			attack_goal = last_known
			weapon_combat._begin(attack_for(&"dive"))
			decision_clock = 0.4
		elif distance<3.5 and absf(elevation)<1.6:
			weapon_combat._begin(attack_for(&"rake"))
	elif absf(elevation)<1.6 and planar<5.5:
		var styles := [&"rake",&"double",&"sweep",&"rake",&"lunge"]
		var style: StringName = &"lunge" if planar>3.5 else styles[attack_cursor%styles.size()]
		attack_cursor += 1
		attack_goal = last_known
		weapon_combat._begin(attack_for(style))

func _physics_process(delta: float) -> void:
	if not encounter.has_authority() or not think_enabled: return
	weapon_combat.advance_stagger(delta)
	state_age += delta
	if state == &"perched":
		velocity = Vector3(0,-2,0)
		move_and_slide()
		return
	if state == &"defeated":
		velocity = velocity.move_toward(Vector3(0,velocity.y-22*delta,0),20*delta)
		move_and_slide()
		if state_age>3:
			weapon_combat.reset()
			start_return()
		return
	if state == &"returning":
		var approach := perch_point+Vector3(0,10,8)
		if global_position.distance_to(approach)<2: _return_high = true
		var goal := perch_point if _return_high else approach
		steer_to(goal,flight_speed,delta)
		if _return_high and global_position.distance_to(perch_point)<1.5:
			velocity = Vector3((perch_point.x-position.x)*3,-3,(perch_point.z-position.z)*3)
		move_and_slide()
		if _return_high and global_position.distance_to(perch_point)<0.7 and is_on_floor():
			flight_mode = false
			set_state(&"perched")
		return
	if not encounter.active: return
	if state == &"alert":
		velocity = Vector3.ZERO
		if state_age>1.5:
			flight_mode = true
			set_state(&"pursuing")
		return
	perceive(delta)
	if unseen_time>search_duration or not in_district(last_known):
		encounter.disengage()
		return
	if weapon_combat.is_staggered():
		velocity = velocity.move_toward(Vector3(0,velocity.y-12*delta,0),15*delta)
		move_and_slide()
		return
	var offset := last_known-global_position
	if weapon_combat.active_move.is_empty():
		var horizontal := Vector3(offset.x,0,offset.z)
		if horizontal.length()>0.2: facing = horizontal.normalized()
		rotation.y = lerp_angle(rotation.y,atan2(facing.x,facing.z),1-exp(-9*delta))
	decide(delta)
	var move: Dictionary = weapon_combat.active_move
	if not move.is_empty():
		facing = weapon_combat._facing
		rotation.y = lerp_angle(rotation.y,atan2(facing.x,facing.z),1-exp(-14*delta))
		var t: float = weapon_combat.elapsed
		var driving: bool = t>=float(move.windup) and t<float(move.hits[-1])+0.06
		if move.beast_style == &"dive" and driving:
			velocity = ((attack_goal-global_position)/maxf(0.07,float(move.hits[0])-t)).limit_length(32)
		elif move.beast_style == &"lunge" and driving:
			velocity = facing*13+Vector3.UP*velocity.y
		else: velocity = velocity.move_toward(Vector3.ZERO,45*delta)
		if not flight_mode: velocity.y -= 22*delta
		move_and_slide()
		return
	if not launch_cleared:
		steer_to(launch_point,flight_speed,delta)
		if global_position.distance_to(launch_point)<2: launch_cleared = true
	elif flight_mode:
		_landing_clock -= delta
		if _landing_clock<=0 and visible_target:
			_landing_clock = 0.75
			var landing := landing_near(last_known)
			_landing_valid = not landing.is_empty()
			if _landing_valid: _land_goal = landing.point
		var goal := _land_goal if _landing_valid else last_known+Vector3.UP
		if not visible_target: goal = last_known+Vector3(sin(state_age)*3,3,cos(state_age)*3)
		steer_to(goal,flight_speed,delta)
		if _landing_valid and visible_target and global_position.distance_to(_land_goal)<1.5:
			velocity = Vector3((_land_goal.x-position.x)*3,-3,(_land_goal.z-position.z)*3)
		if _landing_valid and global_position.distance_to(_land_goal)<1.5 and is_on_floor():
			flight_mode = false
			set_state(&"engaged")
	else:
		if absf(offset.y)>2.5 or Vector2(offset.x,offset.z).length()>10 or (offset.length()>4 and test_move(global_transform,offset.normalized()*1.6)):
			flight_mode = true
			_landing_valid = false
			velocity.y = 10
			set_state(&"pursuing")
		else:
			var direction := Vector3(offset.x,0,offset.z).normalized()
			var desired := direction*ground_speed if offset.length()>3 else direction.cross(Vector3.UP)*2.5
			if combat.blocking: desired *= 0.20
			velocity.x = move_toward(velocity.x,desired.x,24*delta)
			velocity.z = move_toward(velocity.z,desired.z,24*delta)
			velocity.y -= 22*delta
	move_and_slide()
