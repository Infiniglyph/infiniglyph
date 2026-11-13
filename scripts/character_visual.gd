extends Node3D
## Supported procedural gait; pose reactions never gate movement or collisions.
const Neon = preload("res://scripts/neon.gd")
const Spring = preload("res://scripts/pose_spring.gd")
const Retrieval = preload("res://scripts/motion_retrieval.gd")
const ScribeRobe = preload("res://scripts/eternal_scribe_robe.gd")
const Cosmetics = preload("res://scripts/equipment_cosmetics.gd")
var robe: Node3D
var equipment_cosmetics: Node3D
const REST_HIP_HEIGHT := 0.946
const MAX_LANDING_COMPRESSION := 0.34
@export var live_retrieval := true
var joints: Dictionary = {}
var phase := 0.0
var pelvis: Node3D
var chest: Node3D
var retrieval: Node
var pelvis_spring := Spring.new()
var chest_spring := Spring.new()
var weight_spring := Spring.new()
var gains := {"pitch_gain":1.0,"yaw_gain":1.0,"bank_gain":1.0,"sway_gain":1.0,"settle_gain":1.0}
var _speed := 0.0
var _travel_direction := Vector3.ZERO
var _acceleration := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _previous_yaw := 0.0
var _turn_rate := 0.0
var _landing := 0.0
var last_landing_height := 0.0
var last_landing_speed := 0.0
var _fall_peak_y := 0.0
var _fall_blend := 0.0
var _was_grounded := true
var _idle_time := 0.0
var _previous_position := Vector3.ZERO
var _previous_transform := Transform3D.IDENTITY
var _initialized := false
var _feet: Dictionary = {}
var _ankles: Dictionary = {}
var _boost_blend := 0.0
var _sky_step_remaining := 0.0
var _sky_step_side := -1
var _sky_impulse_local := Vector3.UP
var _sky_strength := 1.0
var _propulsion_context := 0.0
var _transition_context := 0.0
var _impact_context := 0.0
var _sprint_context := 0.0
var _reversal_context := 0.0
var _combat_rotations: Dictionary = {}
var _combat_positions: Dictionary = {}

func sync_clothing(inventory: Node) -> void:
	var item: Resource = inventory.equipped_item(&"body")
	var worn: bool = item!=null and item.item_type_id==&"eternal_scribe_robes"
	if worn and not is_instance_valid(robe):
		robe = ScribeRobe.new()
		robe.name = "EternalScribeRobe"
		chest.add_child(robe)
		# Source robes face -Z; this procedural figure faces +Z. Follow the
		# existing chest and pelvis without touching the controller or collider.
		robe.position.y = -REST_HIP_HEIGHT
		robe.rotation.y = PI
		robe.configure(get_parent(),self,chest,joints.LeftArm,joints.RightArm)
	if is_instance_valid(robe): robe.set_equipped(worn)
	if not is_instance_valid(equipment_cosmetics):
		equipment_cosmetics = Cosmetics.new()
		equipment_cosmetics.visual = self
		add_child(equipment_cosmetics)
	equipment_cosmetics.sync(inventory)

func clear_combat_pose() -> void:
	for joint: Node3D in _combat_positions:
		joint.position = _combat_positions[joint]
	_combat_positions.clear()
	for joint: Node3D in _combat_rotations:
		joint.quaternion = _combat_rotations[joint]
	_combat_rotations.clear()

func combat_rotation(joint: Node3D, target: Quaternion, weight: float) -> void:
	if not _combat_rotations.has(joint): _combat_rotations[joint] = joint.quaternion
	joint.quaternion = joint.quaternion.slerp(target,clampf(weight,0,1))

func combat_position(joint: Node3D, target: Vector3) -> void:
	if not _combat_positions.has(joint): _combat_positions[joint] = joint.position
	joint.position = target

func combat_leg(id: String, target: Vector3, pole: Vector3) -> void:
	var hip: Node3D = joints[id]
	var knee: Node3D = hip.get_node("Hinge")
	var hip_rest := hip.quaternion
	var knee_rest := knee.quaternion
	_solve_leg(id,target,pole)
	var hip_pose := hip.quaternion
	var knee_pose := knee.quaternion
	hip.quaternion = hip_rest
	knee.quaternion = knee_rest
	combat_rotation(hip,hip_pose,1.0)
	combat_rotation(knee,knee_pose,1.0)

func sphere(parent: Node3D, at: Vector3, radius: float) -> void:
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = Neon.body
	visual.mesh = mesh
	parent.add_child(visual)
	visual.position = at

func rod(parent: Node3D, length: float, radius: float = 0.035) -> void:
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 8
	mesh.material = Neon.body
	visual.mesh = mesh
	parent.add_child(visual)
	visual.position.y = -length*0.5

func limb(parent: Node3D, id: String, at: Vector3, upper: float, lower: float) -> void:
	var pivot := Node3D.new()
	pivot.name = id
	parent.add_child(pivot)
	pivot.position = at
	sphere(pivot,Vector3.ZERO,0.058)
	rod(pivot,upper)
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	pivot.add_child(hinge)
	hinge.position.y = -upper
	sphere(hinge,Vector3.ZERO,0.052)
	rod(hinge,lower)
	sphere(hinge,Vector3(0,-lower,0),0.045)
	joints[id] = pivot

func _ready() -> void:
	Neon.prepare()
	pelvis = Node3D.new()
	pelvis.name = "Pelvis"
	add_child(pelvis)
	pelvis.position.y = REST_HIP_HEIGHT
	chest = Node3D.new()
	chest.name = "Chest"
	pelvis.add_child(chest)
	sphere(chest,Vector3(0,0.78,0),0.135)
	var spine := Node3D.new()
	chest.add_child(spine)
	spine.position.y = 0.56
	rod(spine,0.56,0.045)
	# Shoulder and pelvic crossbars use the same reusable cylinder primitive.
	for spec in [Vector2(0.51,0.46),Vector2(0.0,0.25)]:
		var cross := Node3D.new()
		(chest if spec.x > 0 else pelvis).add_child(cross)
		cross.position = Vector3(-spec.y*0.5,spec.x,0)
		cross.rotation.z = PI*0.5
		rod(cross,spec.y)
	limb(chest,"LeftArm",Vector3(-0.23,0.51,0),0.30,0.29)
	limb(chest,"RightArm",Vector3(0.23,0.51,0),0.30,0.29)
	limb(pelvis,"LeftLeg",Vector3(-0.125,0,0),0.45,0.45)
	limb(pelvis,"RightLeg",Vector3(0.125,0,0),0.45,0.45)
	retrieval = Retrieval.new()
	retrieval.enabled = live_retrieval
	add_child(retrieval)

func trigger_air_step(side: int, impulse: Vector3 = Vector3.UP*7.5, _chain: int = 1) -> void:
	_sky_step_side = side
	_sky_step_remaining = 0.25
	_sky_impulse_local = global_basis.inverse()*impulse.normalized()
	_sky_strength = clampf(impulse.length()/7.5,0.5,2.0)
	_propulsion_context = 0.6

func rebase_after_phase() -> void:
	# A horizontal blink changes foot anchors, while the current fall height and
	# impact history still belong to the same vertical arc.
	_feet.clear()
	_ankles.clear()
	_previous_position = global_position
	_previous_transform = global_transform
	_previous_yaw = rotation.y

func animate(delta: float, velocity: Vector3, grounded: bool, boosting: bool = false, facts: Dictionary = {}) -> void:
	if delta <= 0: return
	var combat = get_parent().get("weapon_combat")
	if is_instance_valid(combat) and combat.visual_frozen(): return
	clear_combat_pose()
	var planar := Vector3(velocity.x,0,velocity.z)
	var speed := planar.length()
	_travel_direction = planar.normalized() if speed > 0.05 else Vector3.ZERO
	var expected_travel := maxf(velocity.length(),_previous_velocity.length())*delta
	if not _initialized or global_position.distance_to(_previous_position) > maxf(2.0,expected_travel*3+0.25):
		_feet.clear()
		_ankles.clear()
		_previous_velocity = velocity
		_previous_yaw = rotation.y
		_previous_transform = global_transform
		# Spawn/teleport is not a drop; don't carry an old impact into the new pose.
		_landing = 0.0
		_fall_peak_y = global_position.y
		_fall_blend = 0.0
		last_landing_height = 0.0
		last_landing_speed = 0.0
		_was_grounded = grounded
		_initialized = true
	_previous_position = global_position
	var raw_acceleration := ((planar-Vector3(_previous_velocity.x,0,_previous_velocity.z))/delta).limit_length(45)
	_acceleration = _acceleration.lerp(raw_acceleration,1-exp(-12*delta))
	var previous_speed := _speed
	_speed = lerpf(_speed,speed,1-exp(-14*delta))
	if previous_speed <= 0.1 and _speed > 0.1: _feet.clear()
	_turn_rate = lerpf(_turn_rate,clampf(angle_difference(_previous_yaw,rotation.y)/delta,-8,8),1-exp(-14*delta))
	if not grounded:
		# A renewed ascent (including a sky step) starts a new descent arc.
		if _was_grounded or velocity.y > 0: _fall_peak_y = global_position.y
		else: _fall_peak_y = maxf(_fall_peak_y,global_position.y)
	_fall_blend = lerpf(_fall_blend,float(not grounded and velocity.y <= 0),1-exp(-10*delta))
	if grounded != _was_grounded:
		_feet.clear()
		if grounded:
			last_landing_height = maxf(0,_fall_peak_y-global_position.y)
			last_landing_speed = maxf(0,-_previous_velocity.y)
			_landing = minf(0.055*sqrt(minf(last_landing_height,25))+last_landing_speed*0.006,MAX_LANDING_COMPRESSION)
			_impact_context = clampf(last_landing_speed/30,0,1)
		else: _transition_context = 0.4
	# Bigger drops bend farther and take longer to settle, without a movement lock.
	# A fresh jump releases the landing pose rather than carrying a crouch upward.
	_landing = move_toward(_landing,0,delta*(0.45 if grounded else 1.8))
	var local_acceleration := Basis(Vector3.UP,rotation.y).inverse()*_acceleration
	var local_travel := Basis(Vector3.UP,rotation.y).inverse()*_travel_direction
	var amount := clampf(_speed/7.5,0,1)
	var gait := smoothstep(0.04,0.45,_speed)
	var walk_amount := clampf(_speed/3.5,0,1)
	var run_blend := smoothstep(3.5,5.4,_speed)
	_boost_blend = lerpf(_boost_blend,float(boosting and grounded)*gait,1-exp(-10*delta))
	# Locked strafes/backpedals retain the same world-space planted foot solver.
	# Their lean follows travel instead of always pitching toward the rig's front.
	var forward_travel := local_travel.z if speed>0.05 else 0.0
	var forward_boost := _boost_blend*maxf(0,forward_travel)
	# Walking slows the step clock with travel and keeps double-support contact.
	# Running retains the existing cadence, shorter contacts and higher recovery.
	var walk_cadence := 2.1*pow(walk_amount,0.65)
	var cadence := lerpf(walk_cadence,lerpf(1.8,3.0,amount),run_blend)
	var stance := lerpf(lerpf(0.62,0.52,walk_amount),lerpf(0.56,0.33,amount),run_blend)
	var step_lift := lerpf(lerpf(0.025,0.05,walk_amount),0.08+amount*0.10,run_blend)
	cadence = lerpf(cadence,3.3,_boost_blend)
	stance = lerpf(stance,0.26,_boost_blend)
	step_lift = lerpf(step_lift,0.15,_boost_blend)
	if _speed > 0.05 and grounded: phase = fposmod(phase+delta*TAU*cadence,TAU)
	_idle_time += delta
	# Keep brief events available to the asynchronous 4 Hz retrieval loop.
	var sprint_input := float(facts.get("boost",float(boosting)))
	_sprint_context = maxf(sprint_input,maxf(0,_sprint_context-delta*1.5))
	_reversal_context = maxf(float(facts.get("reversal",0.0)),maxf(0,_reversal_context-delta*2))
	var context_acceleration := 20.0 if sprint_input > 0.5 else 9.0
	retrieval.context = {"speed":amount,"acceleration":clampf(local_acceleration.z/context_acceleration,-1,1),"turn":clampf(absf(_turn_rate)/4,0,1),"grounded":grounded,"landing":clampf(_landing/0.13,0,1),"boost":_sprint_context,"transition":_transition_context/0.4,"propulsion":minf(_propulsion_context/0.25,1),"repetition":facts.get("repetition",0.0),"reversal":_reversal_context,"impact":_impact_context}
	for name in gains: gains[name] = lerpf(gains[name],retrieval.parameters[name],1-exp(-4*delta))
	# +Z is the rig's front. Positive pitch shifts the chest forward.
	var travel_lean := lerpf(walk_amount*0.025,amount*0.075,run_blend)
	var pitch := clampf(local_acceleration.z*0.006+travel_lean*forward_travel,-0.17,0.25)*float(gains.pitch_gain)
	# Fast run is a separate, deliberately exaggerated posture, not camera tilt.
	pitch = lerpf(pitch,0.86*(0.9+0.1*float(gains.pitch_gain))+clampf(local_acceleration.z*0.002,-0.05,0.05),forward_boost)
	var bank := clampf(-local_acceleration.x*0.004-_turn_rate*speed*0.002-local_travel.x*travel_lean,-0.18,0.18)*float(gains.bank_gain)
	var turn_lead := clampf(_turn_rate*0.035,-0.15,0.15)*float(gains.yaw_gain)
	var propulsion_pose := 1-smoothstep(0.10,0.25,0.25-_sky_step_remaining) if not grounded and _sky_step_remaining > 0 else 0.0
	pitch += _sky_impulse_local.z*0.12*propulsion_pose*float(gains.pitch_gain)
	bank -= _sky_impulse_local.x*0.10*propulsion_pose*float(gains.bank_gain)
	turn_lead += _sky_step_side*0.065*propulsion_pose*float(gains.yaw_gain)
	var wave := sin(phase)*gait if grounded else 0.0
	var support := (_support_weight(0,stance)-_support_weight(0.5,stance))*gait if grounded else 0.0
	# The rest height nearly extends the 0.9m legs. Crouch belongs to travel/impact.
	var compression := lerpf(0.115*sqrt(walk_amount),REST_HIP_HEIGHT-0.79,run_blend)
	compression = lerpf(compression,REST_HIP_HEIGHT-0.77,_boost_blend)
	var bob := lerpf(0.003,0.009,run_blend)
	# Bound the combined gait/impact compression even at maximum retrieval gain.
	var landing_compression := minf(_landing*float(gains.settle_gain),maxf(0,0.42-compression))
	var hip_target := Vector3(-support*0.027*float(gains.sway_gain),-compression-landing_compression+(cos(phase*2)-1)*gait*bob,0)
	# Subtle chest breathing continues after locomotion settles.
	var breath := sin(_idle_time*2.2)*0.003*(1-gait)
	pelvis.position = Vector3(0,REST_HIP_HEIGHT,0)+weight_spring.step(hip_target,18,delta)
	pelvis.rotation = pelvis_spring.step(Vector3(pitch*0.3,wave*0.015-_sky_step_side*0.035*propulsion_pose,bank+wave*0.012),18,delta)
	chest.rotation = chest_spring.step(Vector3(pitch*0.7+breath,turn_lead-wave*0.03,-bank*0.25),20,delta)
	for id in ["LeftArm","RightArm"]:
		var arm: Node3D = joints[id]
		var side := 1.0 if id == "LeftArm" else -1.0
		var target := wave*side*lerpf(0.10+walk_amount*0.20,amount*0.6,run_blend)*forward_travel
		var bend := lerpf(-0.12-walk_amount*0.13,-0.18-amount*0.65,run_blend)
		target = lerpf(target,0.95+wave*side*0.10,forward_boost)
		bend = lerpf(bend,-0.10,forward_boost)
		if not grounded:
			target = -0.5
			bend = -0.65
			# Opposite arm drives forward as the stepping leg extends down/back.
			var arm_side := -1.0 if id == "LeftArm" else 1.0
			var counter := _sky_step_side*arm_side
			var reach := (0.65+0.15*_sky_strength)*(0.9+0.1*float(gains.sway_gain))
			target = lerpf(target,counter*reach,propulsion_pose)
			bend = lerpf(bend,-0.65 if counter < 0 else -0.20,propulsion_pose)
		arm.rotation.x = lerpf(arm.rotation.x,target,1-exp(-16*delta))
		var spread := -_sky_impulse_local.x*0.12*propulsion_pose if not grounded else wave*side*local_travel.x*0.18
		arm.rotation.z = lerpf(arm.rotation.z,spread,1-exp(-16*delta))
		arm.get_node("Hinge").rotation.x = lerpf(arm.get_node("Hinge").rotation.x,bend,1-exp(-16*delta))
	for spec in [["LeftLeg",-1.0,0.0],["RightLeg",1.0,0.5]]:
		var id: String = spec[0]
		var side: float = spec[1]
		var target: Vector3
		if grounded:
			target = _grounded_foot(id,side,float(spec[2]),stance,cadence,gait,step_lift,delta)
		else:
			var foot_local := Vector3(side*0.125,0.23+amount*0.08,-side*0.12)
			# The anatomical front is local +Z. Both knees/ankles cradle forward on
			# descent, independent of camera yaw; faster falls deepen the tuck.
			var tuck := smoothstep(0,18,maxf(0,-velocity.y))
			var cradle := Vector3(side*0.125,lerpf(0.42,0.53,tuck),lerpf(0.36,0.47,tuck))
			foot_local = foot_local.lerp(cradle,_fall_blend)
			if _sky_step_remaining > 0:
				if int(side) == _sky_step_side:
					var recovery := smoothstep(0,1,1-_sky_step_remaining/0.25)
					var kick := Vector3(side*0.125,0.55,0)-_sky_impulse_local*(0.525+0.025*(_sky_strength-1))
					var recovery_target := Vector3(side*0.125,0.30,-0.06).lerp(cradle,_fall_blend)
					foot_local = kick.lerp(recovery_target,recovery)
				else: foot_local = Vector3(side*0.125,0.38,0.14)
			target = global_transform*foot_local
		# Smooth landing/air transitions without delaying input or moving the capsule.
		if not _ankles.has(id): _ankles[id] = target
		if not grounded and not _was_grounded:
			# Airborne feet travel with the body; world-space blending would drag
			# them backward/upward at high horizontal or downward velocity.
			_ankles[id] = global_transform*(_previous_transform.affine_inverse()*(_ankles[id] as Vector3))
		_ankles[id] = (_ankles[id] as Vector3).lerp(target,1-exp(-28*delta))
		_solve_leg(id,_ankles[id])
	_previous_velocity = velocity
	_previous_yaw = rotation.y
	_previous_transform = global_transform
	_was_grounded = grounded
	_sky_step_remaining = maxf(0,_sky_step_remaining-delta)
	_propulsion_context = maxf(0,_propulsion_context-delta)
	_transition_context = maxf(0,_transition_context-delta)
	_impact_context = maxf(0,_impact_context-delta*0.8)

func _support_weight(offset: float, stance: float) -> float:
	var cycle := fposmod(phase/TAU+offset,1.0)
	return sin(PI*cycle/stance) if cycle < stance else 0.0

func _floor_point(point: Vector3) -> Vector3:
	var from := Vector3(point.x,global_position.y+1.0,point.z)
	var to := Vector3(point.x,global_position.y-1.2,point.z)
	var query := PhysicsRayQueryParameters3D.create(from,to,1,[get_parent().get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): point.y = hit.position.y+0.025
	return point

func _grounded_foot(id: String, side: float, offset: float, stance: float, cadence: float, gait: float, step_lift: float, delta: float) -> Vector3:
	var cycle := fposmod(phase/TAU+offset,1.0)
	var planted := cycle < stance
	var lead := minf(0.45,_speed*stance/maxf(cadence,0.01)*0.5)
	var nominal := _floor_point(global_transform*Vector3(side*0.125,0.025,0))
	var ahead := _floor_point(nominal+_travel_direction*lead)
	if not _feet.has(id): _feet[id] = {"planted":planted,"anchor":ahead,"from":nominal,"last":nominal}
	var foot: Dictionary = _feet[id]
	if planted and not foot.planted: foot.anchor = ahead
	if not planted and foot.planted: foot.from = foot.last
	var point: Vector3
	if planted:
		point = foot.anchor
	else:
		var progress := (cycle-stance)/(1-stance)
		point = (foot.from as Vector3).lerp(ahead,smoothstep(0,1,progress))
		point.y += pow(sin(PI*progress),1.5)*step_lift*gait
	if gait < 0.1:
		point = (foot.last as Vector3).lerp(nominal,1-exp(-10*delta))
		foot.anchor = point
	foot.last = point
	foot.planted = planted
	return point

func _solve_leg(id: String, target: Vector3, pole_direction: Vector3 = Vector3.ZERO) -> void:
	var hip: Node3D = joints[id]
	var knee: Node3D = hip.get_node("Hinge")
	var offset := target-hip.global_position
	var distance := clampf(offset.length(),0.08,0.898)
	var direction := offset.normalized()
	# The knee points forward (+Z); the shin folds back, preserving rig anatomy.
	var forward := global_basis.z if pole_direction.is_zero_approx() else pole_direction
	var pole := forward-direction*forward.dot(direction)
	if pole.length_squared() < 0.001: pole = global_basis.y-direction*global_basis.y.dot(direction)
	pole = pole.normalized()
	var upper := direction*(distance*0.5)+pole*sqrt(maxf(0,0.45*0.45-distance*distance*0.25))
	var knee_point := hip.global_position+upper
	var ankle := hip.global_position+direction*distance
	var up := -upper.normalized()
	var right := up.cross(pole).normalized()
	# A global-basis assignment also rebuilds the node's local origin through
	# world-space floats. Repeating that every frame slowly walks a hinge away
	# from its rod, especially on elevated routes. IK changes rotation only.
	var desired := Basis(right,up,right.cross(up))
	hip.quaternion = (hip.get_parent().global_basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
	var lower_up := -(ankle-knee_point).normalized()
	desired = Basis(right,lower_up,right.cross(lower_up))
	knee.quaternion = (hip.global_basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
