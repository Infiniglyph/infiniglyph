extends "res://scripts/weapon_combat.gd"
## Articulated natural weapons; shared impact/guard/parry/exhaustion resolution.
var _previous_root := Transform3D.IDENTITY
var contact_checks := 0
const Moves = preload("res://scripts/greefer_moves.gd")
const Debug = preload("res://scripts/greefer_debug.gd")
var _debug: Node3D
var _contact_shape := CapsuleShape3D.new()
var _contact_query := PhysicsShapeQueryParameters3D.new()
class GriffinWeight extends "res://scripts/combat_body.gd":
	func begin(facing: Vector3) -> void:
		_stance_origin = actor.global_position
		_stance_basis = Basis(Vector3.UP,atan2(facing.x,facing.z))
		phase_label = "load"
		support_feet.clear()
		var feet: Array[Vector3] = actor.visual.foot_points()
		for i in range(feet.size()):
			var contact := floor_contact(feet[i])
			if not contact.is_empty(): support_feet[i] = contact

func _build_presentation() -> void:
	body = GriffinWeight.new()
	body.actor = actor
	rig = actor.visual
	trail = Trail.new()
	actor.add_child(trail)
	trail.top_level = true
	trail.global_transform = Transform3D.IDENTITY
	_contact_query.shape = _contact_shape
	_contact_query.collision_mask = 2
	_contact_query.exclude = [actor.get_rid()]

func loadout(_slot: StringName) -> Dictionary:
	return {"id":&"griffin","name":"Talons and Wings","short":"Greefer","guard":0.70,"color":Color(0.88,0.08,1)}

func aim_direction() -> Vector3:
	return actor.facing

func _begin(move: Dictionary) -> void:
	_previous_root = actor.global_transform
	super._begin(move)

func advance_strikes(previous: float) -> void:
	if is_staggered(): return
	var move := active_move.duplicate(true)
	var final_transform: Transform3D = rig.transform
	for pulse in range(move.hits.size()):
		var window := Moves.window(move,pulse)
		var start := maxf(previous,window.x)
		var finish := minf(elapsed,window.y)
		if finish<start or previous>window.y: continue
		# Bounded temporal samples sweep the animated talons even at 30 Hz and
		# during a fast aerial pass. Never use a root-centered reach sphere.
		var steps := maxi(1,ceili((finish-start)*180))
		for step in range(steps+1):
			var time := lerpf(start,finish,float(step)/steps)
			var fraction := clampf((time-previous)/maxf(elapsed-previous,0.0001),0,1)
			rig.global_transform = _previous_root.interpolate_with(actor.global_transform,fraction)
			rig.animate(0,actor,move,time,recoil_amount())
			resolve_contacts(move,pulse)
			if active_move.is_empty(): break
		if active_move.is_empty(): break
	rig.transform = final_transform
	rig.animate(0,actor,active_move,elapsed,recoil_amount())

func strike(pulse: int = -1) -> void:
	if not actor.encounter.has_authority() or active_move.is_empty() or is_staggered(): return
	if pulse<0 or pulse>=active_move.hits.size(): return
	var window := Moves.window(active_move,pulse)
	if elapsed<window.x or elapsed>window.y: return
	rig.animate(0,actor,active_move,elapsed,recoil_amount())
	resolve_contacts(active_move.duplicate(true),pulse)

func resolve_contacts(move: Dictionary, pulse: int) -> void:
	var candidates: Array = []
	for segment: Dictionary in rig.attack_segments(move,pulse):
		var span: Vector3 = segment.b-segment.a
		_contact_shape.radius = segment.radius
		_contact_shape.height = span.length()+_contact_shape.radius*2
		var up := span.normalized()
		var right := up.cross(Vector3.UP if absf(up.y)<0.95 else Vector3.RIGHT).normalized()
		_contact_query.transform = Transform3D(Basis(right,up,right.cross(up)),(segment.a+segment.b)*0.5)
		candidates.append_array(actor.get_world_3d().direct_space_state.intersect_shape(_contact_query,16))
		contact_checks += 1
	resolve_strike(move,pulse,actor.combat_point(),candidates,false)

func _physics_process(delta: float) -> void:
	if not actor.encounter.has_authority(): return
	super._physics_process(delta)
	_previous_root = actor.global_transform

func apply_pose(delta: float) -> void:
	if visual_frozen(): return
	body.phase_label = rig.attack_phase(active_move,elapsed)
	actor.visual.animate(delta,actor,active_move,elapsed,recoil_amount())
	if actor.debug_combat:
		if not is_instance_valid(_debug):
			_debug = Debug.new()
			actor.add_child(_debug)
		_debug.show()
		_debug.update(actor,active_move,elapsed)
	elif is_instance_valid(_debug): _debug.hide()
