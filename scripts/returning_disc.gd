extends Node3D
## Owner-controlled weapon flight, with swept contacts on each leg. Never AI.
const Equipment = preload("res://scripts/equipment_database.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
var combat: Node
var actor: CharacterBody3D
var held: Node3D
var hand: Node3D
var item_id: StringName
var move: Dictionary
var direction := Vector3.FORWARD
var spread := 0.0
var returning := false
var travelled := 0.0
var max_distance := 0.0
var alive := true
var _age := 0.0
var _start := Vector3.ZERO
var _return_start := Vector3.ZERO
var _return_progress := 0.0
var _return_duration := .5
var return_side := 1.0
var return_bend := 2.8
var _aim_distance := 7.0
var _visited: Dictionary = {}
var _mesh: Node3D
var _capsule := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	name = "ReturningDisc"
	_start = hand.global_position+Vector3.UP*.08
	var aim: Vector3=actor.combat_point()+direction*7
	if actor.target_lock.is_locked(): aim=actor.target_lock.point(actor.target_lock.opponent)
	_aim_distance=clampf(_start.distance_to(aim),.5,7)
	direction=(aim-_start).normalized()
	global_position = _start
	held.hide()
	var definition: Dictionary = Equipment.get_item(item_id)
	_mesh = Geometry.model(definition.geometry)
	_mesh.position.y = -.18
	add_child(_mesh)
	_capsule.radius = .28
	_query.shape = _capsule
	_query.collision_mask = 6
	_query.exclude = [actor.get_rid()]

func reclaim() -> void:
	if not alive: return
	alive = false
	if is_instance_valid(combat): combat.flying_discs.erase(self)
	if is_instance_valid(held) and is_instance_valid(combat) and combat.rig.selected==item_id and not combat.rig.sheathed: held.show()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(combat): combat.flying_discs.erase(self)
	if alive and is_instance_valid(held) and is_instance_valid(combat) and combat.rig.selected==item_id and not combat.rig.sheathed: held.show()

func _physics_process(delta: float) -> void:
	if not alive: return
	if not is_instance_valid(actor) or not is_instance_valid(combat) or not is_instance_valid(hand):
		reclaim()
		return
	_age += delta
	if _age>3.0 or actor.health<=0 or actor.transition_locked or combat.rig.selected!=item_id or combat.rig.sheathed:
		reclaim()
		return
	var previous := global_position
	var next: Vector3
	var right := Vector3(direction.z,0,-direction.x)
	if returning:
		_return_progress = minf(1,_return_progress+delta/_return_duration)
		var endpoint := hand.global_position
		var control_a := _return_start+right*return_side*return_bend-direction*.8
		var control_b := endpoint+right*return_side*return_bend+direction*1.2
		next = _return_start.bezier_interpolate(control_a,control_b,endpoint,_return_progress)
	else:
		travelled = minf(7,travelled+18*delta)
		var arc_phase := minf(1,travelled/_aim_distance)
		var mode := int(move.get("disc_flight",0))
		var bend := spread+(1.5*return_side if mode==2 else .65*return_side if mode==3 else 0.0)
		next = _start+direction*travelled+right*sin(arc_phase*PI)*bend
		if mode in [1,3]: next += Vector3.UP*sin(arc_phase*PI)*(.55 if mode==1 else 1.1)
		if mode==3: next += right*sin(arc_phase*TAU)*.55*return_side
		max_distance = maxf(max_distance,_start.distance_to(next))
	var wall := actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(previous,next,9,[actor.get_rid()]))
	if not wall.is_empty():
		combat.environment_contact.emit(wall.collider,int(move.attack_serial))
		if returning:
			reclaim() # A returning weapon cannot cut through an opaque wall.
			return
		next = wall.position+wall.normal*.29
		turn_back(next)
	var segment := next-previous
	if segment.length_squared()>.000001:
		_capsule.height = maxf(.56,segment.length()+.56)
		_query.transform = Transform3D(Basis(Quaternion(Vector3.UP,segment.normalized())),(previous+next)*.5)
		var candidates: Array = []
		for hit: Dictionary in actor.get_world_3d().direct_space_state.intersect_shape(_query,32):
			if _visited.has(hit.collider): continue
			_visited[hit.collider] = true
			hit.contact = previous.lerp(next,.5)
			candidates.append(hit)
		var contact := move.duplicate()
		contact.damage = float(move.damage)*(.55 if returning else 1.0)
		combat.resolve_strike(contact,-1,previous,candidates,false,true)
	if not alive: return # A parry can synchronously reclaim this projectile.
	global_position = next
	rotation.y += delta*24
	rotation.x = PI*.5
	if not returning and travelled>=7: turn_back(global_position)
	elif returning and _return_progress>=1: reclaim()

func turn_back(point: Vector3) -> void:
	if returning: return
	returning = true
	_return_start = point
	_return_duration = clampf(point.distance_to(hand.global_position)/22+.14,.32,.85)
	_visited.clear()
