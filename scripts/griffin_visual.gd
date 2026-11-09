extends Node3D
## Articulated low-poly griffin: opaque facets, cyan triangulation, violet tips.
## Geometry is built once per limb; animation only transforms those limbs.
const Neon = preload("res://scripts/neon.gd")
const CYAN := Color(0.05,0.95,1)
const VIOLET := Color(0.9,0.035,1)
const Moves = preload("res://scripts/greefer_moves.gd")
class Facets extends RefCounted:
	static var surface_material: StandardMaterial3D
	var faces := PackedVector3Array()
	var edges := PackedVector3Array()
	var tips := PackedVector3Array()
	func triangle(a: Vector3, b: Vector3, c: Vector3, accent: bool = false) -> void:
		if (b-a).cross(c-a).length_squared()<0.0000001: return
		faces.append_array([a,b,c])
		var lines := tips if accent else edges
		lines.append_array([a,b,b,c,c,a])
		if accent: tips = lines
		else: edges = lines
	func panel(a: Vector3, b: Vector3, c: Vector3, divisions: int = 4) -> void:
		# Subdivide broad wing facets so their cyan lattice remains visible between
		# the outer spars and violet feather tips at normal combat camera distance.
		var u := (b-a)/divisions
		var v := (c-a)/divisions
		for i in range(divisions):
			for j in range(divisions-i):
				var p := a+u*i+v*j
				triangle(p,p+u,p+v)
				if i+j<divisions-1: triangle(p+u,p+u+v,p+v)
	func ellipsoid(at: Vector3, radius: Vector3, sides: int = 9, rings: int = 5) -> void:
		for row in range(rings):
			for column in range(sides):
				var points: Array[Vector3] = []
				for corner: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
					var lat := (row+corner.y)*PI/rings
					var lon := (column+corner.x)*TAU/sides
					points.append(at+radius*Vector3(sin(lat)*cos(lon),cos(lat),sin(lat)*sin(lon)))
				triangle(points[0],points[1],points[2])
				triangle(points[0],points[2],points[3])
	func feather(a: Vector3, b: Vector3, width: float, accent: bool = true) -> void:
		var axis := (b-a).normalized()
		var side := axis.cross(Vector3.UP).normalized()*width*0.5
		if side.is_zero_approx(): side = Vector3.RIGHT*width*0.5
		var ridge := a.lerp(b,0.4)+Vector3.UP*width*0.25
		triangle(a-side,a+side,ridge)
		triangle(a-side,ridge,b,accent)
		triangle(ridge,a+side,b,accent)
	func attach(parent: Node3D, ink: Material, violet: Material) -> void:
		if not faces.is_empty():
			var surface := MeshInstance3D.new()
			var mesh := ArrayMesh.new()
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			# Inset opaque facets slightly so their surface cannot depth-fight the
			# overlaid lattice (which otherwise appears as broken/dotted lines).
			var center := Vector3.ZERO
			for vertex: Vector3 in faces: center += vertex
			center /= faces.size()
			var inset := PackedVector3Array()
			for vertex: Vector3 in faces: inset.append(center+(vertex-center)*0.995)
			arrays[Mesh.ARRAY_VERTEX] = inset
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			surface.mesh = mesh
			if surface_material == null:
				surface_material = Neon.dark.duplicate()
				surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			surface.material_override = surface_material
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(surface)
		if not edges.is_empty(): parent.add_child(Neon.lines(edges,ink))
		if not tips.is_empty(): parent.add_child(Neon.lines(tips,violet))

var torso: Node3D
var neck: Node3D
var head: Node3D
var tail: Node3D
var tail_links: Array[Node3D] = []
var wings: Array[Node3D] = []
var wingtips: Array[Node3D] = []
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var phase := 0.0
var ink: Material
var violet: Material
var _body_height := 0.0
var _was_flying := false
var _landing := 0.0
var _last_yaw := 0.0
var _turn := 0.0

func part(parent: Node3D, at: Vector3, label: String) -> Node3D:
	var joint := Node3D.new()
	joint.name = label
	parent.add_child(joint)
	joint.position = at
	return joint

func _ready() -> void:
	name = "GriffinVisual"
	Neon.prepare()
	ink = Neon.material(CYAN)
	violet = Neon.material(VIOLET)
	torso = part(self,Vector3.ZERO,"Body")
	var core := Facets.new()
	core.ellipsoid(Vector3(0,1.65,-0.65),Vector3(0.86,0.66,1.52),11,6)
	core.ellipsoid(Vector3(0,1.92,0.52),Vector3(0.88,0.84,0.92),11,6)
	core.ellipsoid(Vector3(0,1.73,-1.45),Vector3(0.72,0.69,0.68),9,5)
	core.attach(torso,ink,violet)
	neck = part(torso,Vector3(0,2.12,0.70),"Neck")
	var mantle := Facets.new()
	mantle.ellipsoid(Vector3(0,0.24,0.26),Vector3(0.51,0.66,0.61),9,5)
	for side in [-1,1]:
		for row in range(7):
			var a := Vector3(side*(0.34+row*0.035),0.65-row*0.16,0.43-row*0.035)
			mantle.feather(a,a+Vector3(side*0.25,-0.45,-0.65),0.28,row%3 == 0)
	mantle.attach(neck,ink,violet)
	head = part(neck,Vector3(0,0.74,0.55),"EagleHead")
	var crown := Facets.new()
	crown.ellipsoid(Vector3(0,0,-0.10),Vector3(0.40,0.34,0.65),10,5)
	# A long angular eagle bill with a downward hook, rather than rounded beads.
	for side in [-1,1]:
		var cheek := Vector3(side*0.26,-0.10,0.43)
		var ridge := Vector3(0,0.16,0.51)
		var bridge := Vector3(side*0.15,0.02,0.93)
		var hook := Vector3(0,-0.13,1.23)
		crown.triangle(cheek,ridge,bridge)
		crown.triangle(ridge,Vector3(0,0.10,0.97),bridge)
		crown.triangle(bridge,Vector3(0,0.10,0.97),hook)
		crown.triangle(cheek,bridge,Vector3(0,-0.22,0.86))
		crown.triangle(bridge,hook,Vector3(0,-0.48,1.11))
		crown.triangle(bridge,Vector3(0,-0.48,1.11),Vector3(0,-0.22,0.86))
		for row in range(6):
			var a := Vector3(side*(0.23+row*0.015),0.27-row*0.105,-0.10-row*0.05)
			crown.feather(a,a+Vector3(side*(0.18+row*0.025),0.18-row*0.03,-1.1+row*0.06),0.27,row%3 == 0)
		crown.feather(Vector3(side*0.29,0.19,0.10),Vector3(side*0.40,0.12,0.55),0.20,false)
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.065
		sphere.height = 0.13
		sphere.radial_segments = 8
		sphere.rings = 4
		eye.mesh = sphere
		eye.material_override = violet
		head.add_child(eye)
		eye.position = Vector3(side*0.365,0.08,0.27)
		eye.scale = Vector3(1,0.55,1.45)
	crown.attach(head,ink,violet)
	for side in [-1,1]:
		var wing := part(torso,Vector3(side*0.65,2.2,0.25),"WingLeft" if side<0 else "WingRight")
		wings.append(wing)
		var plumage := Facets.new()
		plumage.panel(Vector3.ZERO,Vector3(side*1.55,0.8,-0.3),Vector3(side*1.3,-0.1,-1.8))
		for feather in range(6):
			var a := Vector3(side*(0.3+feather*0.23),0.17+feather*0.07,-0.25-feather*0.07)
			plumage.feather(a,a+Vector3(side*0.33,-0.25,-1.35),0.38,feather%3 == 0)
		plumage.attach(wing,ink,violet)
		var tip := part(wing,Vector3(side*1.55,0.8,-0.3),"WingWrist")
		wingtips.append(tip)
		var primaries := Facets.new()
		primaries.panel(Vector3.ZERO,Vector3(side*1.65,-0.05,-0.52),Vector3(side*0.25,-0.55,-1.48))
		for feather in range(9):
			var a := Vector3(side*feather*0.19,-feather*0.022,-feather*0.05)
			var b := a+Vector3(side*(0.36+feather*0.09),-0.45,-1.6+feather*0.06)
			primaries.feather(a,b,0.42,feather>=2)
		primaries.feather(Vector3(side*1.45,0,-0.4),Vector3(side*2.9,-0.3,-1.4),0.48)
		primaries.attach(tip,ink,violet)
	for front in [true,false]:
		for side in [-1,1]:
			var leg := part(torso,Vector3(side*0.65,1.60,0.95 if front else -1.40),"Foreleg" if front else "Hindleg")
			legs.append(leg)
			var upper := Facets.new()
			upper.ellipsoid(Vector3(0,-0.30,0),Vector3(0.24 if front else 0.33,0.47,0.29),8,4)
			upper.attach(leg,ink,violet)
			var knee := part(leg,Vector3(0,-0.78,0),"Knee")
			knees.append(knee)
			var lower := Facets.new()
			lower.ellipsoid(Vector3(0,-0.35,0),Vector3(0.15,0.42,0.15),7,4)
			lower.attach(knee,ink,violet)
			var paw := part(knee,Vector3(0,-0.78,0),"FootContact")
			feet.append(paw)
			var talons := Facets.new()
			talons.ellipsoid(Vector3(0,0.05,0.12),Vector3(0.25,0.13,0.28),7,3)
			for toe in range(-1,2):
				var a := Vector3(toe*0.17,0.06,0.18)
				talons.feather(a,a+Vector3(toe*0.08,-0.045,0.48),0.13,front)
			talons.attach(paw,ink,violet)
	tail = part(torso,Vector3(0,1.65,-1.98),"Tail")
	var previous := tail
	for i in range(7):
		var link := part(previous,Vector3.ZERO if i == 0 else Vector3(0,0,-0.38),"TailLink")
		tail_links.append(link)
		var plume := Facets.new()
		plume.ellipsoid(Vector3(0,0,-0.2),Vector3(0.12-i*0.008,0.12-i*0.008,0.25),6,3)
		if i == 6:
			for feather in range(5):
				plume.feather(Vector3.ZERO,Vector3((feather-2)*0.16,0.16,-0.85+absf(feather-2)*0.08),0.23)
		plume.attach(link,ink,violet)
		previous = link
	clear_combat_pose()

func equip(_slot: StringName, _sheathed: bool) -> void:
	# WeaponCombat's rig contract: the natural weapons remain part of the body.
	clear_combat_pose()

func blade_segments() -> Array:
	var result: Array = []
	for i in range(2): result.append({"a":feet[i].global_position,"b":feet[i].to_global(Vector3(0,0,0.45))})
	return result

func foot_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for foot: Node3D in feet: result.append(foot.global_position)
	return result

func clear_combat_pose() -> void:
	_body_height = 0

func rebase_after_phase() -> void:
	clear_combat_pose()

func solve_leg(index: int, target: Vector3) -> void:
	# Two-bone IK keeps support feet grounded while shoulders load and turn.
	var leg := legs[index]
	var knee := knees[index]
	var offset := to_global(target)-leg.global_position
	var distance := clampf(offset.length(),0.04,1.555)
	var direction := offset.normalized()
	var pole := global_basis*Vector3(-0.7 if index%2 == 0 else 0.7,0,0.55 if index<2 else -0.55)
	pole = (pole-direction*pole.dot(direction)).normalized()
	var upper := direction*distance*0.5+pole*sqrt(maxf(0,0.78*0.78-distance*distance*0.25))
	orient_bone(leg,upper,pole)
	orient_bone(knee,direction*distance-upper,pole)
	feet[index].global_basis = global_basis

func orient_bone(joint: Node3D, direction: Vector3, pole: Vector3) -> void:
	var up := -direction.normalized()
	var right := up.cross(pole).normalized()
	joint.global_basis = Basis(right,up,right.cross(up)).orthonormalized()

func attack_phase(move: Dictionary, time: float) -> String:
	if move.is_empty(): return "rest"
	for i in range(move.hits.size()):
		var window := Moves.window(move,i)
		if time>=window.x and time<=window.y: return "active"
		if time<window.x: return "windup"
	return "recovery"

func attack_segments(move: Dictionary, pulse: int) -> Array:
	if move.is_empty(): return []
	# Exactly the rendered natural weapon, with a small thickness allowance.
	match move.beast_style:
		&"sweep":
			return [
				{"a":wings[0].to_global(Vector3(-0.3,0.1,-0.3)),"b":wingtips[0].global_position,"radius":0.22},
				{"a":wingtips[0].to_global(Vector3(0,-0.2,-0.3)),"b":wingtips[0].to_global(Vector3(-2.9,-0.3,-1.4)),"radius":0.24},
				{"a":wingtips[0].to_global(Vector3(0,-0.3,-0.5)),"b":wingtips[0].to_global(Vector3(-0.6,-0.6,-2.2)),"radius":0.22}]
		&"lunge":
			return [{"a":torso.to_global(Vector3(-0.50,1.55,1.05)),"b":torso.to_global(Vector3(0.50,1.55,1.05)),"radius":0.55}]
		&"dive": return [claw_segment(0),claw_segment(1)]
		&"double": return [claw_segment(pulse%2)]
		_: return [claw_segment(0)]

func claw_segment(index: int) -> Dictionary:
	return {"a":feet[index].to_global(Vector3(0,0.05,0.10)),"b":feet[index].to_global(Vector3(0,0.05,0.65)),"radius":0.20}

func animate(delta: float, actor: CharacterBody3D, move: Dictionary, elapsed: float, recoil: float) -> void:
	var flying: bool = actor.flight_mode
	var speed := Vector2(actor.velocity.x,actor.velocity.z).length()
	phase += delta*(5.2 if flying else 1.8+minf(speed,10)*0.85)
	if delta>0:
		if _was_flying and not flying: _landing = 1.0
		_was_flying = flying
		_landing = maxf(0,_landing-delta*3)
		_turn = lerpf(_turn,clampf(angle_difference(_last_yaw,actor.rotation.y)/maxf(delta,0.001),-2,2),1-exp(-8*delta))
		_last_yaw = actor.rotation.y
	var attacking := not move.is_empty()
	var style: StringName = move.get("beast_style",&"")
	var load := 0.0
	var cut := 0.0
	var settle := 0.0
	var stroke := 0
	if attacking:
		if style == &"double" and elapsed>0.88: stroke = 1
		var window := Moves.window(move,stroke)
		var start := 0.88 if stroke == 1 else 0.0
		load = smoothstep(start,window.x,elapsed)
		cut = smoothstep(window.x,window.y,elapsed)
		var finish := 0.88 if style == &"double" and stroke == 0 else float(move.duration)
		settle = smoothstep(window.y,finish,elapsed)
		load *= 1-settle
	var compressed := 0.38 if actor.weapon_combat.forced_state == &"exhausted" else (0.65 if actor.state == &"defeated" else 0.0)
	var position_goal := Vector3(0,-load*0.15-compressed-_landing*0.17,0)
	var rotation_goal := Vector3(-0.12 if flying else 0,0,-_turn*0.055)
	if attacking:
		match style:
			&"rake",&"double":
				var side := 1.0 if stroke == 0 else -1.0
				rotation_goal += Vector3(-load*0.10,side*lerpf(-0.28,0.38,cut)*load,-side*0.08*load)
			&"sweep":
				rotation_goal += Vector3(-load*0.08,lerpf(-0.38,0.50,cut)*load,lerpf(-0.10,0.14,cut)*load)
				position_goal.y -= 0.12*load
			&"lunge":
				rotation_goal.x += lerpf(-0.20,0.27,cut)*load
				position_goal.z += lerpf(-0.25,0.4,cut)*load
				position_goal.y -= 0.12*load
			&"dive":
				rotation_goal.x += lerpf(0.1,0.48,cut)*load
				position_goal.y -= cut*load*0.22
	position_goal.y += sin(phase*2)*0.018 if not flying else sin(phase)*0.045
	# Attacks are deterministic poses, so collision sampling sees the same pose
	# at every frame rate. Locomotion/reaction transitions retain damping.
	var blend := 1.0 if attacking else 1-exp(-12*delta)
	torso.position = torso.position.lerp(position_goal,blend)
	torso.rotation = torso.rotation.lerp(rotation_goal+Vector3(-recoil*0.18,0,recoil*0.10),blend)
	neck.rotation = Vector3(-0.10-load*0.12+recoil*0.2,-torso.rotation.y*0.5,0)
	head.rotation = Vector3(load*0.14-recoil*0.3,-torso.rotation.y*0.25,0)
	tail.rotation.y = sin(phase*0.65)*0.13-torso.rotation.y*0.55
	for i in range(tail_links.size()):
		tail_links[i].rotation = Vector3(0.12+float(i)*0.028,sin(phase*0.7-i*0.5)*0.10,0)
	for i in range(2):
		var old_wing := wings[i].rotation
		var old_tip := wingtips[i].rotation
		var side := -1.0 if i == 0 else 1.0
		var unfold := 1.0 if flying else (0.6 if actor.combat.blocking else 0.0)
		var flap := sin(phase)*0.40 if flying else 0.04*sin(phase*0.55)
		wings[i].rotation = Vector3(0,side*lerpf(1.08,0.02,unfold),side*(flap+0.10))
		wingtips[i].rotation = Vector3(0,side*lerpf(1.0,0.05,unfold),side*(sin(phase-0.5)*0.18 if flying else 0.10))
		if attacking and style == &"sweep" and i == 0:
			wings[i].rotation = Vector3(0,lerpf(-1.08,lerpf(-0.55,1.65,cut),load),lerpf(-0.10,lerpf(-0.60,0.45,cut),load))
			wingtips[i].rotation = Vector3(0,-1.0*(1-load),lerpf(-0.10,lerpf(-0.18,0.14,cut),load))
		elif attacking and style == &"dive":
			var folded := smoothstep(0.2,float(move.windup),elapsed)*(1-settle)
			wings[i].rotation = Vector3(0,side*lerpf(0.05,1.0,folded),side*lerpf(-0.45,0.30,folded))
			wingtips[i].rotation = Vector3(0,side*folded*0.8,side*0.15)
		elif attacking and style == &"lunge":
			wings[i].rotation.z += side*load*0.38
		if not attacking:
			wings[i].rotation = old_wing.lerp(wings[i].rotation,1-exp(-9*delta))
			wingtips[i].rotation = old_tip.lerp(wingtips[i].rotation,1-exp(-9*delta))
	for i in range(4):
		var side := -1.0 if i%2 == 0 else 1.0
		var gait := sin(phase+(PI if i in [0,3] else 0))
		var target := Vector3(side*0.65,0.09,0.95 if i<2 else -1.4)
		if flying:
			target += Vector3(0,0.55,-0.6 if i<2 else -0.3)
		elif not attacking:
			target.z += gait*minf(speed/10,0.5)
			target.y += maxf(0,cos(phase+(PI if i in [0,3] else 0)))*minf(speed/12,0.25)
		var striking_claw := attacking and ((style == &"rake" and i == 0) or (style == &"double" and i == stroke))
		if striking_claw:
			var raised := Vector3(side*1.45,1.25 if flying else 2.35,1.45)
			var through := Vector3(-side*1.15,-0.25 if flying else 0.65,2.5)
			target = target.lerp(raised,load).lerp(through,cut*(1-settle)).lerp(target,settle)
		elif attacking and style == &"dive" and i<2:
			target = target.lerp(Vector3(side*0.7,1.6,2.0),load).lerp(Vector3(side*0.35,0.18,2.1),cut*(1-settle))
		elif attacking and style == &"lunge" and i<2:
			target += Vector3(0,sin(cut*PI)*0.9,cut*0.6)*load
		elif attacking and not flying:
			var supports: Dictionary = actor.weapon_combat.body.support_feet
			if supports.has(i): target = to_local(supports[i].point)
		solve_leg(i,target)
