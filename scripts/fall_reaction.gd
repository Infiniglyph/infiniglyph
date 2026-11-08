extends RefCounted
## Landing-only visual overlay. Collision, velocity, inputs and attack timing
## remain with the existing controller; all joint edits use its reversible pose.

const DURATIONS := {&"minor":0.64,&"heavy":0.84,&"severe":1.35,&"critical":1.35}
var actor: Node3D
var kind: StringName = &""
var remaining := 0.0
var duration := 0.0
var moving_roll := false
var _side := 1.0
var _strength := 1.0
var _before_positions: Dictionary = {}
var _before_rotations: Dictionary = {}
var _after_positions: Dictionary = {}
var _after_rotations: Dictionary = {}

func begin(requested_kind: StringName, impact: float = 0.0) -> void:
	cancel()
	if not is_instance_valid(actor) or not DURATIONS.has(requested_kind): return
	kind = requested_kind
	duration = DURATIONS[kind]
	remaining = duration
	_strength = clampf(impact/40.0,0.8,1.1) if impact>0 else 1.0
	var velocity: Vector3 = actor.get("velocity") if actor.get("velocity") is Vector3 else Vector3.ZERO
	var visual: Node3D = actor.get("visual")
	var local := visual.global_basis.inverse()*velocity if is_instance_valid(visual) else velocity
	moving_roll = Vector2(velocity.x,velocity.z).length()>1.0
	_side = -1.0 if local.x < -0.15 else 1.0

func active() -> bool:
	return remaining>0.000001

func advance(delta: float) -> void:
	if delta<=0 or not active(): return
	remaining = maxf(0,remaining-delta)
	if not active(): cancel()

func cancel() -> void:
	# Restore only edits that still belong to this overlay. If the regular pose
	# pass already reset them, never write an old landing pose over fresh motion.
	for joint: Node3D in _after_positions:
		if is_instance_valid(joint) and joint.position.is_equal_approx(_after_positions[joint]):
			joint.position = _before_positions[joint]
	for joint: Node3D in _after_rotations:
		if is_instance_valid(joint) and absf(joint.quaternion.dot(_after_rotations[joint]))>0.999999:
			joint.quaternion = _before_rotations[joint]
	_before_positions.clear()
	_before_rotations.clear()
	_after_positions.clear()
	_after_rotations.clear()
	remaining = 0
	duration = 0
	kind = &""
	moving_roll = false

func apply(_delta: float) -> void:
	if not active() or not is_instance_valid(actor): return
	if actor.has_method("is_on_floor") and not actor.is_on_floor(): return
	var visual: Node3D = actor.get("visual")
	if not is_instance_valid(visual): return
	var weapon = actor.get("weapon_combat")
	if is_instance_valid(weapon) and weapon.forced_state in [&"parried",&"exhausted"]:
		cancel()
		return
	if is_instance_valid(weapon) and weapon.has_method("visual_frozen") and weapon.visual_frozen(): return
	var combat = actor.get("combat")
	var occupied := false
	var two_handed := false
	if is_instance_valid(weapon):
		occupied = not weapon.active_move.is_empty()
	if is_instance_valid(combat):
		occupied = occupied or combat.blocking or combat.charge_action != &""
		two_handed = weapon.loadout(combat.selected_slot).id == &"katana" and not combat.sheathed
	var t := clampf(1.0-remaining/maxf(duration,0.001),0,1)
	var envelope := smoothstep(0,0.13,t)*(1-smoothstep(0.53,1,t))
	var tumble := sin(PI*smoothstep(0.06,0.76,t))*envelope
	var height := 0.55
	var pelvis_angles := Vector3(0.20,0.0,0.0)
	var chest_angles := Vector3(0.26,0,0)
	var offset := Vector3(0,0,0.035)
	var half_width := 0.21
	var stagger := 0.18
	var trailing_lift := 0.0
	var left_hand := Vector3(-0.27,0.56,0.40)
	var right_hand := Vector3(0.27,0.56,0.40)
	match kind:
		&"minor":
			if moving_roll:
				# A low shoulder-tumble, never a whole-body 360-degree spin. The
				# leading foot catches the landing while the rear foot tucks through.
				height = 0.51
				pelvis_angles = Vector3(0.32+0.33*tumble,_side*0.18*tumble,_side*0.24*tumble)
				chest_angles = Vector3(0.30,-_side*0.14*tumble,-_side*0.06*tumble)
				offset = Vector3(_side*0.045*tumble,0,0.09)
				stagger = 0.25
				trailing_lift = 0.11*tumble
				left_hand = Vector3(-0.25,0.47,0.55)
				right_hand = Vector3(0.25,0.39,0.55)
			else:
				# A stationary drop absorbs vertically instead of inventing travel.
				height = 0.56
				stagger = 0.08
		&"heavy":
			envelope = smoothstep(0,0.11,t)*(1-smoothstep(0.43,1,t))
			height = 0.43
			pelvis_angles = Vector3(0.22,0,_side*0.06)
			chest_angles = Vector3(0.40,0,-_side*0.035)
			offset = Vector3(0,0,0.065)
			half_width = 0.25
			stagger = 0.24
			left_hand = Vector3(-0.31,0.32,0.48)
			right_hand = Vector3(0.31,0.32,0.48)
		&"severe", &"critical":
			# Collapse to a low three-point brace, then push through one planted
			# leg and the opposite hand. Head and torso stay above the surface.
			envelope = smoothstep(0,0.12,t)*(1-smoothstep(0.48,1,t))
			var push := smoothstep(0.39,0.66,t)*(1-smoothstep(0.72,0.96,t))
			height = lerpf(0.30,0.42,push)
			pelvis_angles = Vector3(0.64,_side*0.12,_side*0.22)
			chest_angles = Vector3(0.43,-_side*0.14,-_side*0.06)
			offset = Vector3(-_side*0.055,0,0.055)
			half_width = 0.245
			stagger = 0.34
			left_hand = Vector3(-0.29,lerpf(0.24,0.43,push),0.55)
			right_hand = Vector3(0.29,0.19,0.64)
	# Ordinary attacks keep their authored chest and hand articulation. Landing
	# weight still passes through the hips/feet, without replacing active swings.
	if occupied and kind in [&"minor",&"heavy"]:
		pelvis_angles *= 0.35
		chest_angles = Vector3.ZERO
		height = lerpf(visual.pelvis.position.y,height,0.55)
	var ankles: Dictionary = {}
	for id in ["LeftLeg","RightLeg"]:
		ankles[id] = visual.joints[id].get_node("Hinge").to_global(Vector3(0,-0.45,0))
	_before_positions.clear()
	_before_rotations.clear()
	_after_positions.clear()
	_after_rotations.clear()
	remember_position(visual.pelvis)
	remember_rotation(visual.pelvis)
	remember_rotation(visual.chest)
	var base: Vector3 = visual.pelvis.position
	var position := base+offset*envelope
	position.y = lerpf(base.y,minf(base.y,height),envelope)
	visual.combat_position(visual.pelvis,position)
	visual.combat_rotation(visual.pelvis,visual.pelvis.quaternion*Quaternion.from_euler(pelvis_angles*envelope*_strength),1.0)
	visual.combat_rotation(visual.chest,visual.chest.quaternion*Quaternion.from_euler(chest_angles*envelope*_strength),1.0)
	for id in ["LeftLeg","RightLeg"]:
		var side := -1.0 if id == "LeftLeg" else 1.0
		var leading := side == _side
		var desired := visual.to_global(Vector3(side*half_width,0.025,stagger if leading else -stagger*0.7))
		var floor := floor_contact(desired)
		if not floor.is_empty():
			desired.y = floor.point.y+(0.0 if leading else trailing_lift)
		else: desired = ankles[id]
		remember_rotation(visual.joints[id])
		remember_rotation(visual.joints[id].get_node("Hinge"))
		visual.combat_leg(id,(ankles[id] as Vector3).lerp(desired,envelope),visual.global_basis.z)
	# Drawn katana keeps both hands on its hilt. All weapons remain attached to
	# the actual wrist hierarchy, and active attack/block arms are untouched.
	if not occupied and not two_handed:
		solve_arm(visual,"LeftArm",left_hand,envelope)
		solve_arm(visual,"RightArm",right_hand,envelope)
	for joint: Node3D in _before_positions: _after_positions[joint] = joint.position
	for joint: Node3D in _before_rotations: _after_rotations[joint] = joint.quaternion

func floor_contact(point: Vector3) -> Dictionary:
	if not actor.is_inside_tree(): return {}
	var excluded: Array[RID] = []
	if actor is CollisionObject3D: excluded.append(actor.get_rid())
	var from := Vector3(point.x,actor.global_position.y+0.8,point.z)
	var to := Vector3(point.x,actor.global_position.y-1.1,point.z)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,excluded))
	if hit.is_empty() or hit.normal.y<0.65: return {}
	return {"point":hit.position+Vector3.UP*0.025}

func remember_position(joint: Node3D) -> void:
	if not _before_positions.has(joint): _before_positions[joint] = joint.position

func remember_rotation(joint: Node3D) -> void:
	if not _before_rotations.has(joint): _before_rotations[joint] = joint.quaternion

func solve_arm(visual: Node3D, id: String, target_local: Vector3, weight: float) -> void:
	var arm: Node3D = visual.joints[id]
	var hinge: Node3D = arm.get_node("Hinge")
	remember_rotation(arm)
	remember_rotation(hinge)
	var target: Vector3 = visual.to_global(target_local)
	var offset := target-arm.global_position
	var distance := clampf(offset.length(),0.06,0.585)
	var direction := offset.normalized()
	target = arm.global_position+direction*distance
	var side := -1.0 if id == "LeftArm" else 1.0
	var pole: Vector3 = visual.global_basis*Vector3(side,0.35,-0.25)
	pole -= direction*pole.dot(direction)
	if pole.length_squared()<0.0001: pole = visual.global_basis.x*side
	pole = pole.normalized()
	var along := (0.30*0.30-0.29*0.29+distance*distance)/(2*distance)
	var upper := direction*along+pole*sqrt(maxf(0,0.30*0.30-along*along))
	var up := -upper.normalized()
	var right := up.cross(pole).normalized()
	var desired := Basis(right,up,right.cross(up)).orthonormalized()
	var local: Basis = arm.get_parent().global_basis.inverse()*desired
	visual.combat_rotation(arm,local.get_rotation_quaternion(),weight)
	var lower_up := (hinge.global_position-target).normalized()
	right = lower_up.cross(pole).normalized()
	desired = Basis(right,lower_up,right.cross(lower_up)).orthonormalized()
	local = arm.global_basis.inverse()*desired
	visual.combat_rotation(hinge,local.get_rotation_quaternion(),weight)
