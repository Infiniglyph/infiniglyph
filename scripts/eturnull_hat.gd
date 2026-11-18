extends Node3D
## Head-slot cosmetic. Fixed meshes and a bounded glyph pool; no gameplay queries.
const Lines = preload("res://scripts/robe_lines.gd")
const Robe = preload("res://scripts/eternal_scribe_robe.gd")
const EXPRESSIONS := ["E=mc²", "a²+b²=c²", "x²+y²=r²", "∫f(x)dx", "e^(iπ)+1=0", "∇·F"]
const GROUPS := 3
const GROUP_CAPACITY := 12
const SINGLE_COUNT := 8
const CROWN_COUNT := 16
const CROWN_CYCLE_SECONDS := 3.2
const CROWN_SYMBOLS := ["∑","∫","π","∞","=","+","∇","x"]
const RADIUS := 0.58
const RAIN_COLORS := [Robe.SILVER_BLUE,Robe.VIOLET,Robe.SILVER,Robe.GOLD,Robe.CYAN]
@export_range(0.1,2) var formation_seconds := 0.65
@export_range(0.1,2) var hold_seconds := 0.75
@export_range(0.1,2) var fade_seconds := 0.6
@export_range(0.1,2) var fall_seconds := 0.5
var figure: Node3D
var rain: Node3D
var crown: Node3D
var crown_glyphs: Array[MeshInstance3D] = []
var crown_inks: Array[StandardMaterial3D] = []
var crown_cycles: Array[int] = []
var groups: Array[Dictionary] = []
var singles: Array[MeshInstance3D] = []
var elapsed := 0.0
var trail := Vector3.ZERO
var _last_origin := Vector3.ZERO
var _configured := false
var _phase: Node
static var glyph_meshes: Dictionary = {}

func configure(value: Node3D) -> void:
	if _configured: return
	_configured = true
	figure = value
	_phase = value.get_parent().get("dodge")
	name = "EturnullHat"
	value.chest.add_child(self)
	position = Vector3(0,0.65,0)
	_build_hat()
	_build_rain()
	_build_crown()
	_last_origin = global_position
	process_priority = 45
	advance(0)

func _build_hat() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.015
	mesh.bottom_radius = RADIUS
	mesh.height = 0.24
	mesh.radial_segments = 48
	var fabric := Lines.make_material(Robe.FABRIC,0)
	fabric.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = fabric
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	surface.position.y = 0.22
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	var strokes := PackedVector3Array()
	for ring in range(5):
		var radius := RADIUS*(1.0-float(ring)/5.0)
		var height := 0.102+(1.0-radius/RADIUS)*0.24
		for i in range(48):
			for j in [i,i+1]:
				var angle: float = TAU*j/48.0
				strokes.append(Vector3(cos(angle)*radius,height,sin(angle)*radius))
	for i in range(24):
		var angle := TAU*i/24.0
		strokes.append(Vector3(cos(angle)*0.02,0.342,sin(angle)*0.02))
		strokes.append(Vector3(cos(angle)*RADIUS,0.102,sin(angle)*RADIUS))
	add_child(Lines.segments(strokes,Robe.SILVER_BLUE,1.1))

static func glyph_mesh(character: String) -> Mesh:
	if glyph_meshes.has(character): return glyph_meshes[character]
	# Reuse the robe's exact hand-drawn notation where it already exists.
	var existing := {"∫":1,"=":4,"π":5,"∞":6,"∑":0}
	var points := PackedVector3Array()
	if existing.has(character):
		var source := Robe.new()
		points = source._get_symbol_points(existing[character])
		source.free()
	else:
		var paths := {
			"E":[[-0.6,1,-0.6,-1,0.6,-1],[-0.6,1,0.6,1],[-0.6,0,0.4,0]],
			"m":[[-0.7,-1,-0.7,0.5,-0.1,0.5,0,-1],[0,0.5,0.65,0.5,0.65,-1]],
			"c":[[0.6,0.5,-0.4,0.5,-0.6,0,-0.4,-1,0.6,-1]],
			"a":[[-0.5,0.5,0.5,0.5,0.5,-1,-0.5,-1,-0.5,-0.2,0.5,-0.2]],
			"b":[[-0.5,1,-0.5,-1,0.4,-1,0.6,-0.3,0.4,0.4,-0.5,0.4]],
			"x":[[-0.6,0.6,0.6,-1],[-0.6,-1,0.6,0.6]],
			"y":[[-0.6,0.6,0,-0.2,0.6,0.6],[0,-0.2,-0.2,-1]],
			"r":[[-0.5,-1,-0.5,0.5,-0.1,0.5,0.6,0.2]],
			"²":[[-0.25,0.9,0,1.2,0.4,1.1,0.4,0.8,-0.2,0.35,0.5,0.35]],
			"+":[[-0.65,0,0.65,0],[0,-0.65,0,0.65]],
			"∇":[[-0.75,0.8,0.75,0.8,0,-0.8,-0.75,0.8]],
			"·":[[-0.08,0,0.08,0]],
			"F":[[-0.6,-1,-0.6,1,0.6,1],[-0.6,0,0.4,0]],
			"f":[[-0.1,-1,-0.1,0.8,0.3,1,0.6,0.8],[-0.6,0.2,0.5,0.2]],
			"d":[[0.5,1,0.5,-1,-0.4,-1,-0.6,-0.3,-0.4,0.4,0.5,0.4]],
			"(":[[0.25,1,-0.2,0.5,-0.3,0,-0.2,-0.5,0.25,-1]],
			")":[[-0.25,1,0.2,0.5,0.3,0,0.2,-0.5,-0.25,-1]],
			"e":[[-0.5,-0.2,0.5,-0.2,0.4,0.5,-0.3,0.5,-0.6,0,-0.4,-1,0.5,-1]],
			"i":[[0,-1,0,0.4],[-0.05,0.8,0.05,0.8]],
			"1":[[-0.3,0.5,0,1,0,-1],[-0.4,-1,0.4,-1]],
			"0":[[-0.5,-0.8,-0.5,0.8,0,1,0.5,0.8,0.5,-0.8,0,-1,-0.5,-0.8]],
			"^":[[-0.4,0.4,0,0.9,0.4,0.4]]
		}
		for path: Array in paths.get(character,paths["·"]):
			for i in range(0,path.size()-2,2):
				points.append(Vector3(path[i]*0.07,path[i+1]*0.07,0))
				points.append(Vector3(path[i+2]*0.07,path[i+3]*0.07,0))
	var sample := Lines.segments(points,Robe.SILVER_BLUE,1.4)
	glyph_meshes[character] = sample.mesh
	sample.free()
	return glyph_meshes[character]

func _ink(color: Color = Robe.SILVER_BLUE) -> StandardMaterial3D:
	var ink := Lines.make_material(color,1.4)
	ink.vertex_color_use_as_albedo = false
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return ink

func _build_rain() -> void:
	# Prewarm every shape once, including future expressions. Cycles allocate no meshes.
	for expression: String in EXPRESSIONS:
		for character in expression: glyph_mesh(character)
	rain = Node3D.new()
	rain.name = "BrimMathematics"
	add_child(rain)
	for group in range(GROUPS):
		var nodes: Array[MeshInstance3D] = []
		var inks: Array[StandardMaterial3D] = []
		for i in range(GROUP_CAPACITY):
			var ink := _ink(RAIN_COLORS[(group*2+i)%RAIN_COLORS.size()])
			inks.append(ink)
			var node := MeshInstance3D.new()
			node.mesh = glyph_mesh("=")
			node.material_override = ink
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rain.add_child(node)
			nodes.append(node)
		groups.append({"nodes":nodes,"ink":inks[0],"inks":inks,"cycle":-1,"expression":"","formation":0.0})
	for i in range(SINGLE_COUNT):
		var node := MeshInstance3D.new()
		node.mesh = glyph_mesh(["∫","π","∞","∑"][i%4])
		node.material_override = _ink(RAIN_COLORS[i%RAIN_COLORS.size()])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rain.add_child(node)
		singles.append(node)

func _build_crown() -> void:
	# Like the robe inscriptions, flat notation stays fitted to its fabric.
	# Prewarm the finite shapes and keep every instance/material for its lifetime.
	for character: String in CROWN_SYMBOLS: glyph_mesh(character)
	crown = Node3D.new()
	crown.name = "CrownMathematics"
	add_child(crown)
	for i in range(CROWN_COUNT):
		var node := MeshInstance3D.new()
		node.name = "CrownSymbol%02d" % (i+1)
		node.mesh = glyph_mesh(CROWN_SYMBOLS[i%CROWN_SYMBOLS.size()])
		var ink := _ink(RAIN_COLORS[i%RAIN_COLORS.size()])
		node.material_override = ink
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crown.add_child(node)
		crown_glyphs.append(node)
		crown_inks.append(ink)
		crown_cycles.append(-1)

func _update_crown() -> void:
	var slope := .24/(RADIUS-.015)
	for i in range(crown_glyphs.size()):
		var clock := elapsed/CROWN_CYCLE_SECONDS+float(i)/CROWN_COUNT
		var cycle := int(floor(clock))
		var phase := fposmod(clock,1.0)
		var glyph := crown_glyphs[i]
		if crown_cycles[i]!=cycle:
			crown_cycles[i] = cycle
			glyph.mesh = glyph_mesh(CROWN_SYMBOLS[(i+cycle*3)%CROWN_SYMBOLS.size()])
		var angle := i*2.399963+cycle*.47
		var radial := Vector3(cos(angle),0,sin(angle))
		var radius := lerpf(.015,RADIUS*.87,phase)
		var height := .34-(radius-.015)*slope
		var normal := (Vector3.UP+radial*slope).normalized()
		var outward := (radial-Vector3.UP*slope).normalized()
		var fade := smoothstep(0,.14,phase)*(1-smoothstep(.80,1,phase))
		var pulse := .92+sin(elapsed*1.15+i*.91)*.08
		glyph.position = radial*radius+Vector3.UP*height+normal*.008
		glyph.basis = Basis(outward.cross(normal),outward,normal)*Basis(Vector3.BACK,sin(elapsed*.27+i)*.08)
		glyph.scale = Vector3.ONE*.58*pulse*maxf(.015,fade)
		crown_inks[i].albedo_color.a = fade*.88

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not _configured or not is_inside_tree(): return
	elapsed += delta
	var origin := global_position
	if is_instance_valid(_phase) and _phase.active:
		# PhaseDodge temporarily overrides every material with one shared fade.
		# Freeze local glyph poses/inks so world-facing rain cannot undo the
		# body's compression or overwrite that fade through material_override.
		_last_origin = origin
		return
	var velocity := (origin-_last_origin)/maxf(delta,0.001) if delta>0 else Vector3.ZERO
	_last_origin = origin
	var camera := get_viewport().get_camera_3d()
	var onscreen := visible and (camera==null or (camera.global_position.distance_to(origin)<36 and not camera.is_position_behind(origin)))
	if camera!=null and onscreen:
		var screen := camera.unproject_position(origin)
		onscreen = get_viewport().get_visible_rect().grow(120).has_point(screen)
	rain.visible = onscreen
	crown.visible = onscreen
	if not onscreen: return
	_update_crown()
	var wanted := -velocity.limit_length(18)*0.03
	trail = trail.lerp(wanted,1-exp(-6*delta))
	# Upright, camera-facing equations remain legible through torso turns.
	var facing := Basis(Vector3.UP,camera.global_rotation.y) if camera!=null else Basis.IDENTITY
	rain.global_transform = Transform3D(facing,origin)
	var local_trail := facing.inverse()*trail
	var lifetime := fall_seconds+formation_seconds+hold_seconds+fade_seconds
	for index in range(groups.size()):
		var group: Dictionary = groups[index]
		var clock := elapsed+index*lifetime/GROUPS
		var cycle := int(clock/lifetime)
		var t := fmod(clock,lifetime)
		if group.cycle!=cycle:
			group.cycle = cycle
			group.expression = EXPRESSIONS[(cycle*GROUPS+index)%EXPRESSIONS.size()]
			for i in range(GROUP_CAPACITY):
				var node: MeshInstance3D = group.nodes[i]
				node.visible = i<group.expression.length()
				if node.visible: node.mesh = glyph_mesh(group.expression[i])
		var formation := smoothstep(fall_seconds,fall_seconds+formation_seconds,t)
		group.formation = formation
		var fade := 1-smoothstep(lifetime-fade_seconds,lifetime,t)
		for ink: StandardMaterial3D in group.inks: ink.albedo_color.a = minf(1,t/0.16)*fade*0.8
		for i in range(group.expression.length()):
			var node: MeshInstance3D = group.nodes[i]
			var angle := i*2.399+index*1.8+cycle*0.7
			var start := Vector3(cos(angle)*RADIUS,0.10+sin(angle*3)*0.045,sin(angle)*RADIUS)
			start.y -= t*0.28
			var target := Vector3((i-(group.expression.length()-1)*0.5)*0.079,0.10-t*0.28,-0.40+index*0.34)
			node.position = start.lerp(target,formation)+local_trail*clampf(t,0,1)
			node.rotation.z = (1-formation)*sin(angle)*0.28+(1-fade)*sin(angle)*0.3
			node.scale = Vector3.ONE*0.55*lerpf(0.65,1.0,fade)
			if fade<1: node.position.x += (1-fade)*sin(angle)*0.05
	for i in range(singles.size()):
		var phase := fmod(elapsed*0.48+i*0.618,1.0)
		var angle := i*2.399
		singles[i].position = Vector3(cos(angle)*RADIUS,0.1-phase*0.9,sin(angle)*RADIUS)+local_trail*phase
		singles[i].scale = Vector3.ONE*0.40
		singles[i].material_override.albedo_color.a = sin(phase*PI)*0.55
