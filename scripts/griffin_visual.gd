extends Node3D
## Articulated low-poly griffin: opaque facets, cyan triangulation, violet tips.
## Geometry is built once per limb; animation only transforms those limbs.
const Neon = preload("res://scripts/neon.gd")
const CYAN := Color(0.05,0.95,1)
const VIOLET := Color(0.9,0.035,1)
class Facets extends RefCounted:
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
			arrays[Mesh.ARRAY_VERTEX] = faces
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			surface.mesh = mesh
			surface.material_override = Neon.dark
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(surface)
		if not edges.is_empty(): parent.add_child(Neon.lines(edges,ink))
		if not tips.is_empty(): parent.add_child(Neon.lines(tips,violet))

var torso: Node3D
var head: Node3D
var tail: Node3D
var wings: Array[Node3D] = []
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var phase := 0.0
var ink: Material
var violet: Material
var _body_height := 0.0

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
	core.ellipsoid(Vector3(0,1.5,-0.5),Vector3(0.82,0.72,1.45))
	core.ellipsoid(Vector3(0,1.95,0.55),Vector3(0.85,0.98,0.78))
	core.ellipsoid(Vector3(0,2.55,1.0),Vector3(0.48,0.7,0.52))
	for side in [-1,1]:
		for row in range(5):
			var a := Vector3(side*(0.38+row*0.055),2.65-row*0.22,1.22-row*0.08)
			core.feather(a,a+Vector3(side*0.22,-0.65,-0.24),0.24,row%2 == 0)
	core.attach(torso,ink,violet)
	head = part(torso,Vector3(0,2.95,1.18),"EagleHead")
	var crown := Facets.new()
	crown.ellipsoid(Vector3.ZERO,Vector3(0.49,0.48,0.58))
	# Hooked beak, brow and swept crown distinguish this from a winged quadruped.
	crown.ellipsoid(Vector3(0,0.08,0.5),Vector3(0.25,0.18,0.30),7,3)
	crown.ellipsoid(Vector3(0,-0.02,0.80),Vector3(0.18,0.16,0.24),7,3)
	crown.ellipsoid(Vector3(0,-0.21,0.93),Vector3(0.09,0.22,0.12),6,3)
	for side in [-1,1]:
		crown.triangle(Vector3(side*0.08,-0.17,0.98),Vector3(0,-0.50,0.90),Vector3(0,-0.23,0.80))
		for row in range(4):
			var a := Vector3(side*0.3,0.3-row*0.15,-0.15)
			crown.feather(a,a+Vector3(side*0.13,0.28,-0.85-row*0.08),0.23,row%2 == 0)
		crown.feather(Vector3(side*0.39,0.2,0.23),Vector3(side*0.48,0.26,0.66),0.15,false)
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.09
		sphere.height = 0.18
		sphere.radial_segments = 8
		sphere.rings = 4
		eye.mesh = sphere
		eye.material_override = violet
		head.add_child(eye)
		eye.position = Vector3(side*0.43,0.1,0.34)
	crown.attach(head,ink,violet)
	for side in [-1,1]:
		var wing := part(torso,Vector3(side*0.65,2.2,0.25),"WingLeft" if side<0 else "WingRight")
		wings.append(wing)
		var plumage := Facets.new()
		plumage.panel(Vector3.ZERO,Vector3(side*1.55,0.8,-0.3),Vector3(side*1.3,-0.1,-1.8))
		plumage.panel(Vector3(side*1.55,0.8,-0.3),Vector3(side*3.0,0.6,-1),Vector3(side*1.3,-0.1,-1.8))
		for feather in range(10):
			var a := Vector3(side*(0.55+feather*0.27),0.3+sin(feather*PI/9)*0.55,-0.25-feather*0.065)
			var b := a+Vector3(side*(0.4+feather*0.035),-0.65-feather*0.05,-1.5-feather*0.1)
			plumage.feather(a,b,0.42,feather>=3)
		plumage.feather(Vector3(side*2.7,0.6,-0.85),Vector3(side*4.1,0.2,-2.35),0.55)
		plumage.attach(wing,ink,violet)
	for front in [true,false]:
		for side in [-1,1]:
			var leg := part(torso,Vector3(side*0.62,1.45,0.80 if front else -1.25),"Foreleg" if front else "Hindleg")
			legs.append(leg)
			var upper := Facets.new()
			upper.ellipsoid(Vector3(0,-0.28,-0.05),Vector3(0.24,0.46,0.28),7,4)
			upper.attach(leg,ink,violet)
			var knee := part(leg,Vector3(0,-0.66,-0.03),"Knee")
			knees.append(knee)
			var lower := Facets.new()
			lower.ellipsoid(Vector3(0,-0.35,0.04),Vector3(0.14,0.39,0.15),6,4)
			for toe in range(-1,2):
				var a := Vector3(toe*0.13,-0.65,0.08)
				lower.feather(a,a+Vector3(toe*0.12,-0.04,0.48),0.13,true)
			lower.attach(knee,ink,violet)
			feet.append(part(knee,Vector3(0,-0.67,0.16),"FootContact"))
	tail = part(torso,Vector3(0,1.4,-1.7),"Tail")
	var plume := Facets.new()
	for i in range(6):
		plume.ellipsoid(Vector3(sin(i*0.55)*0.4,i*i*0.035,-i*0.3),Vector3(0.13,0.14,0.22),6,3)
	for i in range(5):
		plume.feather(Vector3(0.15,0.85,-1.6),Vector3((i-2)*0.20,1.25,-2.5+absf(i-2)*0.12),0.24)
	plume.attach(tail,ink,violet)
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

func animate(delta: float, actor: CharacterBody3D, move: Dictionary, elapsed: float, recoil: float) -> void:
	var flying: bool = actor.flight_mode
	var speed := Vector2(actor.velocity.x,actor.velocity.z).length()
	phase += delta*(5.2 if flying else 2+minf(speed,9)*0.9)
	var attacking := not move.is_empty()
	var load := 0.0
	var drive := 0.0
	var style: StringName = move.get("beast_style",&"")
	if attacking:
		load = sin(PI*clampf(elapsed/float(move.windup),0,1))*0.18
		drive = sin(PI*clampf((elapsed-float(move.windup))/0.4,0,1))
	var fallen: bool = actor.state == &"defeated"
	var compressed := 0.65 if actor.weapon_combat.forced_state == &"exhausted" else (0.9 if fallen else 0.0)
	_body_height = lerpf(_body_height,-load-compressed,1-exp(-12*delta))
	torso.position.y = _body_height+(sin(phase*2)*0.035 if not flying else sin(phase)*0.07)
	torso.rotation.x = lerpf(torso.rotation.x,(-0.18 if flying else -load)+drive*0.13-recoil*0.16,1-exp(-12*delta))
	torso.rotation.y = lerp_angle(torso.rotation.y,drive*0.5 if style == &"sweep" else 0,1-exp(-14*delta))
	head.rotation.x = lerpf(head.rotation.x,recoil*0.4-load*0.5,1-exp(-12*delta))
	tail.rotation.y = sin(phase*0.7)*0.16-drive*0.35
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var unfold := 1.0 if flying or style in [&"sweep",&"dive"] else (0.65 if actor.combat.blocking else 0.0)
		var yaw := side*lerpf(0.93,0.04,unfold)
		var flap := sin(phase)*0.40 if flying else 0.08*sin(phase*0.55)
		var fold := side*(flap+drive*0.35+(0.42 if actor.combat.blocking else 0.04))
		wings[i].rotation = wings[i].rotation.lerp(Vector3(0,yaw,fold),1-exp(-10*delta))
	for i in range(4):
		var gait := sin(phase+(PI if i in [0,3] else 0))
		var stride := gait*minf(speed/10.0,0.48) if not flying and not attacking else 0.0
		var claw := drive*(-0.85 if i == 0 else 0.3) if style in [&"rake",&"double",&"lunge"] else 0.0
		var tucked := 0.52 if flying else 0.0
		legs[i].rotation.x = lerpf(legs[i].rotation.x,stride+claw+tucked,1-exp(-16*delta))
		knees[i].rotation.x = lerpf(knees[i].rotation.x,-maxf(0,gait)*absf(stride)-tucked*1.3,1-exp(-16*delta))
