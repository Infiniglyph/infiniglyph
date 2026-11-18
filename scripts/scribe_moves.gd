extends RefCounted
## Original conducting vocabulary. Points are shared by writing and hit queries.
const Hat = preload("res://scripts/eturnull_hat.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
static var paths: Dictionary = {}

static func writing_basis(facing: Vector3) -> Basis:
	var forward := facing.normalized()
	if forward.is_zero_approx(): forward = Vector3.BACK
	var right := Vector3.UP.cross(forward).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	return Basis(right,forward.cross(right).normalized(),forward)

static func strokes(move: Dictionary) -> PackedVector3Array:
	var expression: String = move.get("equation","E=mc²")
	var key := expression+":"+String(move.get("scribe_shape","line"))+":"+str(move.reach)
	if paths.has(key): return paths[key]
	var points := PackedVector3Array()
	# Draw out from the caster to the far equation, so both the near and far
	# portions of the requested spear-length writing have visible hit geometry.
	var far := float(move.reach)-.11
	var shape: String = move.get("scribe_shape","line")
	for i in range(12):
		for j in [i,i+1]:
			var t: float = j/12.0
			var sway := sin(t*PI)*(.24 if shape=="cross" else .10)
			points.append(Vector3(sway,sin(t*TAU)*.08,lerpf(.65-far,0,t)))
	for index in range(expression.length()):
		var mesh: Mesh = Hat.glyph_mesh(expression[index])
		# ImmediateMesh surface arrays are available after construction.
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var offset := Vector3((index-(expression.length()-1)*0.5)*0.18,0,0)
		for vertex: Vector3 in vertices:
			points.append(vertex*1.25+offset)
	# Purposeful diagram strokes expand the readable equation into its attack region.
	if shape in ["circle","theorem","ward"]:
		for i in range(24):
			for j in [i,i+1]:
				var angle: float = TAU*j/24.0
				points.append(Vector3(cos(angle)*0.72,sin(angle)*0.52,0))
		if shape=="theorem":
			# A small self-similar proof diagram, with explicit coordinate axes.
			# These are real strokes, included in the same contact geometry.
			points.append_array([Vector3(-.60,-.34,0),Vector3(.60,-.34,0),Vector3(-.60,-.34,0),Vector3(-.60,.38,0)])
			for centre: Vector3 in [Vector3(-.36,.28,0),Vector3(.36,.28,0)]:
				for size: float in [.16,.08]:
					var a := centre+Vector3(-size,-size*.5,0)
					var b := centre+Vector3(size,-size*.5,0)
					var c := centre+Vector3(0,size*.85,0)
					points.append_array([a,b,b,c,c,a])
	elif shape=="descending":
		points.append_array([Vector3(0,0.65,0),Vector3(0,-0.65,0),Vector3(-.3,0,0),Vector3(.3,0,0)])
	elif shape=="cross":
		points.append_array([Vector3(-.70,-.35,0),Vector3(.70,.35,0),Vector3(-.70,.35,0),Vector3(.70,-.35,0)])
	paths[key] = points
	return points

static func progress(move: Dictionary, time: float) -> float:
	var start := 0.0
	for index in range(move.hits.size()):
		var hit := float(move.hits[index])
		if time<=hit+0.08:
			return clampf((time-start)/maxf(.02,hit-start-.015),0,1)
		start = hit+0.08
	return 1.0

static func stroke_transform(move: Dictionary, time: float = 0.0) -> Transform3D:
	var collapse := lerpf(1.20,.78,progress(move,time)) if float(move.get("charge",0))>0 else 1.0
	return Transform3D(Basis.IDENTITY.scaled(Vector3(collapse,collapse,1)),Vector3(0,0,float(move.reach)-.11))

static func pose(move: Dictionary, time: float, charging: bool, guarding: bool, clock: float) -> Dictionary:
	# Semantic right/left are mirrored relative to this +Z rig's historical
	# node labels. The actual right arm hangs relaxed; the left supports
	# the book. Authored clips have already been adapted into those rig fields.
	var conducting := Vector3(-.265,.872,.025)
	var supporting := Vector3(.30,1.26,.34)
	var wrist := Vector3(.03,0,.04)
	if guarding:
		conducting = Vector3(-.22,1.46,.36)
		wrist = Vector3(.4,0,-.45)
	elif charging:
		conducting = Vector3(-.28+sin(clock*8)*.04,1.78,.26)
		wrist = Vector3(-.5,0,.4)
	elif not move.is_empty():
		var authored := Motion.sample(move,time)
		if not authored.is_empty(): return authored
	return {"right":supporting,"left":conducting,"right_rotation":Vector3(.55,0,-.12),"left_rotation":wrist}

static func preview_ready(figure: Node3D, rig: Node3D) -> void:
	figure.pelvis.position += Vector3(.055,-.105,-.065)
	figure.pelvis.rotation.y = -.18
	figure.chest.rotation.y = .16
	# These historical node names are opposite the anatomical sides for +Z.
	figure.joints.RightArm.rotation.x = -.4
	figure.joints.RightArm.get_node("Hinge").rotation.x = -1.55
	figure.joints.LeftArm.rotation.x = .03
	figure.joints.LeftArm.get_node("Hinge").rotation.x = -.15
	figure._solve_leg("RightLeg",figure.to_global(Vector3(.18,.025,-.22)))
	figure._solve_leg("LeftLeg",figure.to_global(Vector3(-.18,.025,.22)))
	rig.orient(Vector3(.55,0,-.12),Vector3(.03,0,.04))
