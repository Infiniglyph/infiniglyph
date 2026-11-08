extends RefCounted
## Visual weight transfer: authored load/drive/follow-through over real floor
## contacts. The CharacterBody, collision capsule and velocity are never moved.
const Spring = preload("res://scripts/pose_spring.gd")
# Per profile: load depth, hip yaw, stance stagger, half-width, forward drive.
const PROFILES := {
	"sweep": [0.12,0.68,0.23,0.20,0.12],
	"crescent": [0.12,0.80,0.25,0.20,0.12],
	"thrust": [0.11,0.35,0.31,0.18,0.17],
	"spiral": [0.13,0.42,0.30,0.19,0.16],
	"beam": [0.15,0.45,0.29,0.20,0.17],
	"comets": [0.12,0.55,0.26,0.20,0.13],
	"slam": [0.19,0.42,0.22,0.24,0.11],
	"pillar": [0.17,0.48,0.24,0.22,0.12],
	"rain": [0.14,0.38,0.28,0.21,0.09],
	"orbit": [0.13,0.70,0.21,0.22,0.06],
	"cross": [0.14,0.72,0.24,0.21,0.11],
	"waltz": [0.12,0.70,0.20,0.22,0.06],
	"lattice": [0.12,0.75,0.23,0.21,0.07],
	"aegis": [0.14,0.23,0.23,0.25,0.08]}
var actor: CharacterBody3D
var translation := Spring.new()
var hips := Spring.new()
var shoulders := Spring.new()
var support_feet: Dictionary = {}
var plant_weight := 0.0
var hip_drive := 0.0
var shoulder_drive := 0.0
var phase_label := "rest"
var _sources: Dictionary = {}
var _stance_origin := Vector3.ZERO
var _stance_basis := Basis.IDENTITY
var _guarding := false
var _guard_time := 0.0
var _spin_base := 0.0

func begin(facing: Vector3) -> void:
	_sources.clear()
	support_feet.clear()
	_stance_origin = actor.global_position
	_stance_basis = Basis(Vector3.UP,atan2(facing.x,facing.z))
	_spin_base = roundf(hips.value.y/TAU)*TAU
	for id in ["LeftLeg","RightLeg"]:
		var knee: Node3D = actor.visual.joints[id].get_node("Hinge")
		_sources[id] = knee.to_global(Vector3(0,-0.45,0))

func release(immediate: bool = false) -> void:
	_sources.clear()
	support_feet.clear()
	plant_weight = 0
	if immediate:
		for spring in [translation,hips,shoulders]:
			spring.value = Vector3.ZERO
			spring.velocity = Vector3.ZERO
		_guarding = false
		_guard_time = 0
		phase_label = "rest"

func floor_contact(point: Vector3) -> Dictionary:
	var at := actor.global_position
	var from := Vector3(point.x,at.y+0.6,point.z)
	var to := Vector3(point.x,at.y-0.65,point.z)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,[actor.get_rid()]))
	if hit.is_empty() or hit.normal.y<0.68 or absf(hit.position.y-at.y)>0.36: return {}
	return {"point":hit.position+Vector3.UP*0.025,"rid":hit.rid}

func foot_target(id: String, side: float, lead: float, width: float, stagger: float, t: float, windup: float, contact: float, spin: float, rotary: bool) -> Dictionary:
	var initial: Vector3 = _sources[id]
	var local := Vector3(side*width,0,(-side*lead)*stagger)
	var destination := _stance_origin+_stance_basis*local
	var start := 0.0 if side == lead else windup*0.5
	var finish := windup*0.5 if side == lead else contact*0.92
	var step := smoothstep(start,maxf(start+0.02,finish),t)
	var planted := step <= 0 or step >= 1
	var point := initial.lerp(destination,step)
	var lift := sin(PI*step)*0.055
	if rotary:
		var steps := 4
		var cursor := clampf(spin*steps,0,steps-0.0001)
		var current := int(cursor)
		var foot_index := 0 if side == lead else 1
		var last := current if current%2 == foot_index else current-1
		if last < 0:
			point = destination
			lift = 0
			planted = true
		else:
			var previous_angle := maxf(0,(last-1)/float(steps))*TAU
			var next_angle := (last+1)/float(steps)*TAU
			var a := _stance_origin+_stance_basis*local.rotated(Vector3.UP,previous_angle)
			var b := _stance_origin+_stance_basis*local.rotated(Vector3.UP,next_angle)
			step = smoothstep(0,1,cursor-current) if current == last else 1.0
			point = a.lerp(b,step)
			lift = sin(PI*step)*0.075
			planted = current != last or step>=0.995 or step<=0.005
	var floor := floor_contact(point)
	if floor.is_empty(): return {}
	floor.point += Vector3.UP*lift
	floor.planted = planted
	return floor

func apply(delta: float, move: Dictionary, time: float, guarding: bool, kind: StringName, facing: Vector3) -> void:
	var active := not move.is_empty()
	var visual: Node3D = actor.visual
	var speed := Vector2(actor.velocity.x,actor.velocity.z).length()
	var turn_replant := _stance_basis.z.dot(facing)<cos(deg_to_rad(50))
	var moved := actor.global_position.distance_to(_stance_origin)>0.45
	if guarding and (not _guarding or turn_replant or (moved and speed<0.6)):
		begin(facing)
		_guard_time = 0
	_guarding = guarding
	if guarding: _guard_time += delta
	var offset := Vector3.ZERO
	var rotation := Vector3.ZERO
	var chest := Vector3.ZERO
	var envelope := 0.0
	var width := 0.20
	var stagger := 0.23
	var side := 1.0
	var windup := 0.15
	var first := 0.24
	var spin := 0.0
	var rotary := false
	var t := _guard_time if guarding else time
	hip_drive = 0
	shoulder_drive = 0
	phase_label = "rest"
	if active:
		var profile: String = move.profile
		var values: Array = PROFILES.get(profile,PROFILES.sweep)
		windup = float(move.windup)
		first = float(move.hits[0])
		var last := float(move.hits[-1])
		var duration := float(move.duration)
		side = float(move.side)
		width = values[3]
		stagger = values[2]
		var load := smoothstep(0,maxf(0.03,windup*0.75),t)
		hip_drive = smoothstep(windup*0.60,first,t)
		shoulder_drive = smoothstep(windup*0.88,first+0.04,t)
		var recover := smoothstep(maxf(last+0.08,duration*0.74),duration,t)
		envelope = load*(1-recover)
		phase_label = "load" if t<windup*0.6 else ("drive" if t<first else ("follow-through" if recover<0.05 else "recover"))
		var mass := 0.82 if kind == &"twin_blades" else 1.0
		offset = Vector3(-side*0.045*(1-hip_drive),-float(values[0])*mass,lerpf(-0.07,float(values[4]),hip_drive))*envelope
		rotation = Vector3(lerpf(-0.05,0.11,hip_drive),side*lerpf(-0.48,float(values[1]),hip_drive),side*lerpf(-0.04,0.055,hip_drive))*envelope
		chest = Vector3(lerpf(-0.08,0.13,shoulder_drive),side*lerpf(0.23,-0.14,hip_drive)+side*lerpf(-0.38,0.38,shoulder_drive),-rotation.z*0.55)*envelope
		if profile in ["slam","pillar","rain"]:
			offset.y *= lerpf(0.65,1.0,hip_drive)
			chest.x = lerpf(-0.18,0.27,shoulder_drive)*envelope
		if profile == "cross":
			var alternation := sin(smoothstep(windup*0.7,last+0.07,t)*PI*3)
			rotation.y = alternation*0.62*envelope
			chest.y = -alternation*0.16*envelope
		rotary = profile in ["orbit","waltz","lattice"]
		if rotary:
			spin = smoothstep(windup*0.65,minf(duration*0.82,last+0.17),t)
			rotation.y = _spin_base+spin*TAU
			chest.y = -0.22*sin(spin*PI)*envelope
			if spin>=1: rotation.y = _spin_base+TAU
	elif guarding:
		envelope = smoothstep(0,0.18,t)
		offset = Vector3(0,-0.10,0.025)*envelope
		rotation = Vector3(0.02,-0.16,0)*envelope
		chest = Vector3(0.05,0.18,0)*envelope
		phase_label = "brace"
	# Release the lower-body lock as locomotion takes over. Airborne poses keep
	# the existing kick/cradle: hips can turn, but feet never seek a floor in air.
	var stationary := 1-smoothstep(0.15,1.6,speed)
	var grounded := actor.is_on_floor()
	plant_weight = stationary*envelope if grounded else 0.0
	if actor.global_position.distance_to(_stance_origin)>0.45: plant_weight = 0
	if grounded and envelope>0.01 and _sources.is_empty(): begin(facing)
	var body_scale := lerpf(0.32,1.0,stationary) if grounded else 0.30
	offset *= body_scale if grounded else 0.15
	rotation.x *= body_scale
	rotation.z *= body_scale
	if rotary and active and grounded and stationary>0.8:
		rotation.y = _spin_base+spin*TAU
	else:
		rotation.y = sin(spin*TAU)*0.55*envelope if rotary else rotation.y*body_scale
		rotation.y = hips.value.y+angle_difference(hips.value.y,rotation.y)
	var shift := translation.step(offset,24,delta)
	var hip_angles := hips.step(rotation,30,delta)
	var shoulder_angles := shoulders.step(chest,27,delta)
	support_feet.clear()
	if shift.length_squared()<0.00000001 and Quaternion.from_euler(hip_angles).angle_to(Quaternion.IDENTITY)<0.0001 and shoulder_angles.length_squared()<0.00000001: return
	var base_position: Vector3 = visual.pelvis.position
	var old_ankles: Dictionary = {}
	for id in ["LeftLeg","RightLeg"]:
		old_ankles[id] = visual.joints[id].get_node("Hinge").to_global(Vector3(0,-0.45,0))
	var posed_position := base_position+shift
	posed_position.y = maxf(posed_position.y,minf(base_position.y,0.62))
	visual.combat_position(visual.pelvis,posed_position)
	visual.combat_rotation(visual.pelvis,visual.pelvis.quaternion*Quaternion.from_euler(hip_angles),1.0)
	visual.combat_rotation(visual.chest,visual.chest.quaternion*Quaternion.from_euler(shoulder_angles),1.0)
	if grounded:
		for id in ["LeftLeg","RightLeg"]:
			var foot_side := -1.0 if id == "LeftLeg" else 1.0
			var target: Vector3 = old_ankles[id]
			if plant_weight>0.001 and _sources.has(id):
				var contact := foot_target(id,foot_side,side,width,stagger,t,windup,first,spin,rotary)
				if not contact.is_empty():
					target = target.lerp(contact.point,plant_weight)
					support_feet[id] = contact
			var pole := visual.global_basis.z.rotated(Vector3.UP,hip_angles.y)
			visual.combat_leg(id,target,pole)
