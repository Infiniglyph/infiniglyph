extends Node3D
## Original merchant apparition. Floor origin, +Z front, no skeleton, combat,
## ordinary civilian identity, text nodes or per-frame geometry allocation.
const Lines = preload("res://scripts/robe_lines.gd")
const Garment = preload("res://scripts/garment_surface.gd")
const BinaryShader = preload("res://scripts/avat_ar_binary.gdshader")
const PURPLE := Color("a252ff")
const MAGENTA := Color("f155e6")
const CYAN := Color("59efff")
const GOLD := Color("e9bc68")
const FABRIC := Color("160d2b")
const SILK := Color("23123c")
const HEIGHT := 2.60
const EXPRESSIONS := [&"welcoming", &"excited", &"thoughtful", &"serious"]
static var _atlas: ImageTexture

var customer: Node3D
## Optional world-space facing point when no customer is assigned. Infinity
## means retain the current orientation; the default forward direction is +Z.
var target_position := Vector3(INF, INF, INF)
var expression: StringName = &"welcoming":
	set(value):
		expression = value if value in EXPRESSIONS else &"welcoming"
		_update_expression()
var elapsed := 0.0
var _hover: Node3D
var _head: Node3D
var _robe_tails: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _faces: Dictionary = {}
var _binary_materials: Array[ShaderMaterial] = []
var _brush: Node3D
var _welcome_left := 0.0
var _nearby := false
var _built := false

func _ready() -> void:
	name = "AvatArVisual"
	_build()
	animate(0.0)

func set_expression(value: StringName) -> void:
	expression = value

func welcome() -> void:
	_welcome_left = 2.4

func _process(delta: float) -> void:
	animate(delta)

func animate(delta: float) -> void:
	if not _built: return
	delta = clampf(delta, 0.0, 0.1)
	elapsed += delta
	var point := target_position
	if is_instance_valid(customer): point = customer.global_position
	if point.is_finite():
		var offset := point - global_position
		var near := offset.length_squared() < 49.0
		if near and not _nearby: welcome()
		_nearby = near
		if near and Vector2(offset.x, offset.z).length_squared() > 0.04:
			var local_offset: Vector3 = get_parent().to_local(point)-position if get_parent() is Node3D else offset
			rotation.y = lerp_angle(rotation.y, atan2(local_offset.x, local_offset.z), 1.0-exp(-delta*3.2))
	else: _nearby = false
	_welcome_left = maxf(0.0, _welcome_left-delta)
	var greeting := sin(clampf(_welcome_left/2.4, 0.0, 1.0)*PI)
	_hover.position.y = 0.055 + sin(elapsed*1.6)*0.045
	_hover.rotation.z = sin(elapsed*0.83)*0.018
	_head.rotation.z = sin(elapsed*0.67)*0.028
	_head.rotation.x = sin(elapsed*0.92)*0.018 - greeting*0.055
	for i in range(_robe_tails.size()):
		var tail := _robe_tails[i]
		tail.rotation.x = sin(elapsed*1.25+i*1.7)*0.035
		tail.rotation.z = sin(elapsed*1.05+i*1.3)*0.026
	# Elbows remain hidden inside the wide sleeves; only the open hands and
	# brush conduct the shopkeeper's small, readable theatrical gestures.
	_arms[0].rotation.z = -0.07 + sin(elapsed*0.8)*0.04 - greeting*0.24
	_arms[0].rotation.x = -0.12 + sin(elapsed*0.7)*0.04 - greeting*0.35
	_arms[1].rotation.z = 0.06 + sin(elapsed*0.9+1.0)*0.045 + greeting*0.40
	_arms[1].rotation.x = -0.10 - greeting*0.28
	_brush.rotation.z = 0.40 + sin(elapsed*0.9)*0.12 + greeting*0.17
	_brush.rotation.x = -0.12 + sin(elapsed*0.6)*0.09
	for material in _binary_materials: material.set_shader_parameter("flow_time", elapsed)
	if expression == &"excited": _faces[expression].scale = Vector3.ONE*(1.0+sin(elapsed*5.0)*0.035)

func _build() -> void:
	if _built: return
	_hover = Node3D.new()
	_hover.name = "HoveringApparition"
	_hover.scale = Vector3.ONE*.92
	add_child(_hover)
	_build_void()
	_build_robes()
	_build_hood()
	_build_arm(-1.0)
	_build_arm(1.0)
	_build_belt()
	_built = true
	_update_expression()

static func binary_atlas() -> ImageTexture:
	if _atlas != null: return _atlas
	# Sixteen columns of hand-pixelled 0/1 glyphs, generated once and shared by
	# every body surface. Each white pixel is an original five-by-seven digit.
	var image := Image.create(128, 256, false, Image.FORMAT_L8)
	image.fill(Color.BLACK)
	var zero := [14, 17, 19, 21, 25, 17, 14]
	var one := [4, 12, 4, 4, 4, 4, 14]
	for row in range(21):
		for column in range(16):
			var glyph: Array = zero if ((column*13+row*7+row*column)%11)<5 else one
			for y in range(7):
				for x in range(5):
					if (int(glyph[y]) & (1 << (4-x))) != 0:
						image.set_pixel(column*8+x+1, row*12+y+2, Color.WHITE)
	_atlas = ImageTexture.create_from_image(image)
	return _atlas

func _binary(density: Vector2, tint: Color = CYAN, speed: float = 0.045) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BinaryShader
	material.set_shader_parameter("binary_atlas", binary_atlas())
	material.set_shader_parameter("density", density)
	material.set_shader_parameter("ink", tint)
	material.set_shader_parameter("second_ink", MAGENTA)
	material.set_shader_parameter("flow_speed", speed)
	_binary_materials.append(material)
	return material

func _mesh(label: String, vertices: PackedVector3Array, uv: PackedVector2Array, material: Material, parent: Node3D) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not uv.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _solid(label: String, vertices: PackedVector3Array, color: Color, parent: Node3D) -> MeshInstance3D:
	var instance := Garment.surface(label, vertices, color)
	parent.add_child(instance)
	return instance

func _line(label: String, points: PackedVector3Array, color: Color, parent: Node3D, energy: float = 1.4) -> MeshInstance3D:
	var node := Lines.segments(points, color, energy)
	node.name = label
	parent.add_child(node)
	return node

func _ribbon(label: String, segments: PackedVector3Array, color: Color, parent: Node3D, width: float = .003) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	for i in range(0,segments.size(),2):
		var a := segments[i]
		var b := segments[i+1]
		var n := Vector3(-(b-a).y,(b-a).x,0).normalized()*width
		vertices.append_array([a-n,b-n,b+n,a-n,b+n,a+n])
	var material := Lines.make_material(color,1.1)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mesh(label,vertices,PackedVector2Array(),material,parent)

func _path(batch: PackedVector3Array, points: Array) -> void:
	for i in range(1, points.size()): batch.append_array([points[i-1], points[i]])

func _circle(batch: PackedVector3Array, center: Vector3, right: Vector3, up: Vector3, radius: float, count: int = 20) -> void:
	for i in range(count):
		batch.append_array([center+(right*cos(i*TAU/count)+up*sin(i*TAU/count))*radius, center+(right*cos((i+1)*TAU/count)+up*sin((i+1)*TAU/count))*radius])

func _symbol(batch: PackedVector3Array, kind: int, center: Vector3, size: float, right: Vector3 = Vector3.RIGHT, up: Vector3 = Vector3.UP) -> void:
	var paths: Array = []
	match kind%5:
		0:
			var infinity: Array = []
			for i in range(25):
				var a := i*TAU/24.0
				infinity.append(Vector2(cos(a)*0.7, sin(2.0*a)*0.35))
			paths.append(infinity)
		1: paths = [[Vector2(.5,.6), Vector2(-.5,.6), Vector2(.1,0), Vector2(-.5,-.6), Vector2(.5,-.6)]]
		2: paths = [[Vector2(-.55,.4), Vector2(.55,.4)], [Vector2(-.3,.4), Vector2(-.3,-.55)], [Vector2(.3,.4), Vector2(.3,-.55)]]
		3: paths = [[Vector2(-.4,.18), Vector2(.4,.18)], [Vector2(-.4,-.18), Vector2(.4,-.18)]]
		4: paths = [[Vector2(-.3,-.6), Vector2(.3,.6)], [Vector2(-.4,.05), Vector2(.4,.05)]]
	for path: Array in paths:
		for i in range(1, path.size()): batch.append_array([center+(right*path[i-1].x+up*path[i-1].y)*size, center+(right*path[i].x+up*path[i].y)*size])

func _build_void() -> void:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	# A single tapering apparition: there are deliberately no leg/foot pieces.
	var rows := [Vector3(.11,.12,.08), Vector3(.34,.40,.22), Vector3(.42,.78,.25), Vector3(.28,1.19,.20), Vector3(.37,1.62,.22), Vector3(.23,1.83,.16)]
	for j in range(rows.size()-1):
		for i in range(24):
			var a := i*TAU/24.0
			var b := (i+1)*TAU/24.0
			var pa := Vector3(sin(a)*rows[j].x,rows[j].y,cos(a)*rows[j].z)
			var pb := Vector3(sin(b)*rows[j].x,rows[j].y,cos(b)*rows[j].z)
			var pc := Vector3(sin(b)*rows[j+1].x,rows[j+1].y,cos(b)*rows[j+1].z)
			var pd := Vector3(sin(a)*rows[j+1].x,rows[j+1].y,cos(a)*rows[j+1].z)
			vertices.append_array([pa,pb,pc,pa,pc,pd])
			uv.append_array([Vector2(i/24.0,1.0-rows[j].y/1.9),Vector2((i+1)/24.0,1.0-rows[j].y/1.9),Vector2((i+1)/24.0,1.0-rows[j+1].y/1.9),Vector2(i/24.0,1.0-rows[j].y/1.9),Vector2((i+1)/24.0,1.0-rows[j+1].y/1.9),Vector2(i/24.0,1.0-rows[j+1].y/1.9)])
	_mesh("FlowingBinaryBody", vertices, uv, _binary(Vector2(2.0,1.25)), _hover)
	var wisps := PackedVector3Array()
	for strand in range(5):
		var points: Array = []
		for j in range(17):
			var t := j/16.0
			var a := strand*TAU/5.0+t*2.5
			points.append(Vector3(sin(a)*(.10+t*.28),.11+t*.66,cos(a)*(.08+t*.20)))
		_path(wisps, points)
	_line("ApparitionFilaments", wisps, PURPLE, _hover, .7)

func _build_robes() -> void:
	# A fitted mantle, broad shoulders, split robe fronts and one sweeping back
	# drape preserve the dark opening instead of covering the binary with cloth.
	var mantle := Garment.new()
	mantle.loft([Vector3(.34,1.18,.23),Vector3(.45,1.57,.25),Vector3(.52,1.76,.25)], .72, Vector3.ZERO, 5)
	mantle.finish(_hover,"MerchantMantle",FABRIC,PURPLE,CYAN)
	for side: float in [-1.0,1.0]:
		var pivot := Node3D.new()
		pivot.name = "FlowingRobeFront"+("Left" if side<0 else "Right")
		pivot.position.y = 1.30
		_hover.add_child(pivot)
		_robe_tails.append(pivot)
		var panel := Garment.new()
		var a := Vector3(side*.17,-.04,.285)
		var b := Vector3(side*.34,-.03,.24)
		var c := Vector3(side*.61,-1.02,.27)
		var d := Vector3(side*.33,-1.13,.38)
		panel.quad(a,b,c,d,true)
		panel.line([a,Vector3(side*.28,-.62,.32),d],true)
		panel.line([Vector3(side*.23,-.07,.293),Vector3(side*.39,-.91,.35),Vector3(side*.49,-.88,.31)])
		panel.finish(pivot,"VioletSilkRobe",SILK,MAGENTA,CYAN)
		var glyphs := PackedVector3Array()
		for i in range(6): _symbol(glyphs,i,Vector3(side*(.25+i*.034),-.16-i*.16,.343+i*.009),.083)
		_ribbon("MathematicalRobeEmbroidery",glyphs,GOLD,pivot,.0021)
		var edging := PackedVector3Array()
		_path(edging,[a+Vector3(0,0,.012),Vector3(side*.28,-.62,.345),d+Vector3(0,0,.012)])
		_path(edging,[Vector3(side*.31,-.10,.30),Vector3(side*.53,-.98,.30)])
		_ribbon("CyanRobePiping",edging,CYAN,pivot,.0028)
		var collar := Garment.new()
		collar.quad(Vector3(side*.08,1.46,.31),Vector3(side*.24,1.80,.29),Vector3(side*.49,1.76,.27),Vector3(side*.22,1.30,.30),true)
		collar.line([Vector3(side*.19,1.46,.316),Vector3(side*.35,1.77,.302)],true)
		collar.finish(_hover,"LayeredMerchantLapel",Color("301748"),MAGENTA,GOLD)
		var lapel_glyphs := PackedVector3Array()
		for i in range(3): _symbol(lapel_glyphs,i+1,Vector3(side*(.29-i*.046),1.69-i*.105,.326),.06)
		_ribbon("LapelCalligraphy",lapel_glyphs,CYAN,_hover,.0023)
		var shoulder := Garment.new()
		shoulder.quad(Vector3(side*.24,1.82,.17),Vector3(side*.47,1.82,-.10),Vector3(side*.65,1.62,.18),Vector3(side*.40,1.60,.31),true)
		shoulder.line([Vector3(side*.28,1.77,.22),Vector3(side*.58,1.62,.215)],true)
		shoulder.finish(_hover,"EmbroideredShoulderMantle",SILK,GOLD,MAGENTA)
	var back := Node3D.new()
	back.name = "FlowingBackDrape"
	back.position.y = 1.60
	_hover.add_child(back)
	_robe_tails.append(back)
	var cloak := Garment.new()
	cloak.loft([Vector3(.43,.0,.28),Vector3(.41,-.53,.34),Vector3(.63,-1.35,.40)],.98,Vector3(0,0,-.05),6)
	cloak.finish(back,"DeepPurpleBackDrape",FABRIC,PURPLE,MAGENTA)
	var decoration := PackedVector3Array()
	_symbol(decoration,0,Vector3(0,-.48,-.407),.23)
	_circle(decoration,Vector3(0,-.48,-.408),Vector3.RIGHT,Vector3.UP,.27,28)
	_line("BackInfinitySeal",decoration,GOLD,back,.9)
	var back_glyphs := PackedVector3Array()
	for side: float in [-1.0,1.0]:
		for i in range(6): _symbol(back_glyphs,i+1,Vector3(side*(.22+i*.026),-.21-i*.17,-.37-i*.017),.075)
	_ribbon("BackDrapeCalligraphy",back_glyphs,CYAN,back,.002)

func _build_hood() -> void:
	_head = Node3D.new()
	_head.name = "PointedMerchantHood"
	_hover.add_child(_head)
	var outer := [Vector3(-.16,1.70,.10),Vector3(-.48,1.88,.10),Vector3(-.48,2.19,.05),Vector3(-.31,2.53,-.02),Vector3(-.10,2.72,-.13),Vector3(.23,2.54,-.02),Vector3(.47,2.19,.05),Vector3(.45,1.88,.10),Vector3(.16,1.70,.10)]
	var inner := [Vector3(-.12,1.82,.32),Vector3(-.30,1.93,.32),Vector3(-.31,2.15,.32),Vector3(-.20,2.35,.28),Vector3(-.04,2.49,.22),Vector3(.16,2.35,.28),Vector3(.31,2.15,.32),Vector3(.29,1.93,.32),Vector3(.12,1.82,.32)]
	var hood := Garment.new()
	for i in range(outer.size()-1):
		hood.quad(outer[i],outer[i+1],inner[i+1],inner[i])
		hood.quad(outer[i+1],outer[i],Vector3(-.06,2.16,-.34),Vector3(-.06,2.16,-.34))
	hood.quad(outer[0],outer[-1],inner[-1],inner[0])
	hood.quad(outer[0],outer[-1],Vector3(-.06,2.16,-.34),Vector3(-.06,2.16,-.34))
	hood.line(outer)
	hood.line(inner,true)
	hood.line([outer[1],outer[3],outer[4],outer[5],outer[7]],true)
	hood.finish(_head,"PointedHoodFabric",Color("211032"),PURPLE,MAGENTA)
	var rim := PackedVector3Array()
	_path(rim,inner)
	_ribbon("HoodGoldenInnerLip",rim,GOLD,_head,.0022)
	var folds := PackedVector3Array()
	_path(folds,[outer[1]+Vector3(0,0,.002),outer[3]+Vector3(0,0,.002),outer[4]+Vector3(0,0,.002)])
	_path(folds,[outer[4]+Vector3(0,0,.002),outer[5]+Vector3(0,0,.002),outer[7]+Vector3(0,0,.002)])
	_ribbon("HoodSilkenFoldEdges",folds,MAGENTA,_head,.003)
	var hood_glyphs := PackedVector3Array()
	for side: float in [-1.0,1.0]:
		for i in range(3): _symbol(hood_glyphs,i+1,Vector3(side*(.35-i*.055),2.0+i*.14,.25-i*.024),.053)
	_line("HoodEdgeNotation",hood_glyphs,GOLD,_head,.9)
	var face := PackedVector3Array()
	var uv := PackedVector2Array()
	var center := Vector3(0,2.12,.225)
	for i in range(inner.size()-1):
		for p: Vector3 in [center,inner[i]-Vector3(0,0,.045),inner[i+1]-Vector3(0,0,.045)]:
			face.append(p)
			uv.append(Vector2((p.x+.34)/.68,(2.50-p.y)/.74))
	face.append_array([center,inner[-1]-Vector3(0,0,.045),inner[0]-Vector3(0,0,.045)])
	uv.append_array([Vector2(.5,.51),Vector2(.68,.92),Vector2(.32,.92)])
	_mesh("BinaryBeneathHood",face,uv,_binary(Vector2(.48,.62),Color("7edbff"),.027),_head)
	for state: StringName in EXPRESSIONS:
		var features := PackedVector3Array()
		_build_face_strokes(features,state)
		# Small camera-independent ribbons give the expressions real width and
		# remain readable on integrated graphics without relying on post glow.
		var ribbons := PackedVector3Array()
		for i in range(0,features.size(),2):
			var a := features[i]
			var b := features[i+1]
			var normal := Vector3(-(b-a).y,(b-a).x,0).normalized()*.0043
			ribbons.append_array([a-normal,b-normal,b+normal,a-normal,b+normal,a+normal])
		var ink := Lines.make_material(CYAN if state!=&"thoughtful" else Color("e6bdff"),1.2)
		ink.cull_mode = BaseMaterial3D.CULL_DISABLED
		for i in range(ribbons.size()): ribbons[i] -= Vector3(0,2.12,0)
		_faces[state] = _mesh("Expression_"+String(state),ribbons,PackedVector2Array(),ink,_head)
		_faces[state].position.y = 2.12
	# Nod around the hood itself, and pulse eyes around their own center.
	_head.position.y = 2.12
	for child: Node3D in _head.get_children(): child.position.y -= 2.12

func _build_face_strokes(batch: PackedVector3Array,state: StringName) -> void:
	var z := .348
	if state==&"welcoming":
		_symbol(batch,0,Vector3(-.12,2.16,z),.075)
		_path(batch,[Vector3(.075,2.16,z),Vector3(.165,2.16,z)])
		_path(batch,[Vector3(.12,2.115,z),Vector3(.12,2.205,z)])
	elif state==&"excited":
		for x: float in [-.12,.12]:
			_path(batch,[Vector3(x-.05,2.16,z),Vector3(x+.05,2.16,z)])
			_path(batch,[Vector3(x,2.11,z),Vector3(x,2.21,z)])
			_path(batch,[Vector3(x-.035,2.125,z),Vector3(x+.035,2.195,z)])
			_path(batch,[Vector3(x-.035,2.195,z),Vector3(x+.035,2.125,z)])
	elif state==&"thoughtful":
		_path(batch,[Vector3(-.18,2.17,z),Vector3(-.08,2.18,z)])
		_circle(batch,Vector3(.12,2.16,z),Vector3.RIGHT,Vector3.UP,.037,14)
	else:
		_path(batch,[Vector3(-.18,2.19,z),Vector3(-.08,2.15,z),Vector3(-.04,2.16,z)])
		_path(batch,[Vector3(.04,2.16,z),Vector3(.08,2.15,z),Vector3(.18,2.19,z)])
	var smile: Array = []
	for i in range(17):
		var x := lerpf(-.16,.16,i/16.0)
		var depth := .073 if state==&"welcoming" else .10 if state==&"excited" else .012
		smile.append(Vector3(x,2.045-depth*(1.0-pow(x/.16,2)),z))
	_path(batch,smile)
	if state==&"excited": _path(batch,[Vector3(-.16,2.045,z),Vector3(.16,2.045,z)])
	if state==&"welcoming": _path(batch,[Vector3(.16,2.045,z),Vector3(.177,2.076,z)])

func _update_expression() -> void:
	for state: StringName in _faces:
		_faces[state].visible = state==expression
		_faces[state].scale = Vector3.ONE

func _build_arm(side: float) -> void:
	var arm := Node3D.new()
	arm.name = "BrushArm" if side<0 else "WelcomingArm"
	arm.position = Vector3(side*.41,1.63,0)
	_hover.add_child(arm)
	_arms.append(arm)
	var sleeve := Garment.new()
	var rows := [Vector3(.10,.02,.11),Vector3(.16,-.22,.19),Vector3(.22,-.39,.23)]
	sleeve.loft(rows,0.0,Vector3(side*.17,0,.07),4)
	sleeve.finish(arm,"BellSleeve",SILK,PURPLE,CYAN)
	var cuff := PackedVector3Array()
	_circle(cuff,Vector3(side*.17,-.39,.07),Vector3.RIGHT,Vector3.BACK,.205,24)
	_line("GoldenSleeveCuff",cuff,GOLD,arm,.8)
	var hand := Node3D.new()
	hand.name = "GlowingHand"
	hand.position = Vector3(side*.18,-.28,.32)
	arm.add_child(hand)
	var palm := MeshInstance3D.new()
	palm.name = "SimplifiedPalm"
	var sphere := SphereMesh.new()
	sphere.radius = .068
	sphere.height = .14
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = Lines.make_material(CYAN, .8)
	palm.mesh = sphere
	palm.scale = Vector3(.83,1.0,.52)
	palm.rotation.z = side*.35
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.add_child(palm)
	var fingers := PackedVector3Array()
	for i in range(3): _path(fingers,[Vector3((i-1)*.028,.01,.01),Vector3((i-1)*.036,.095,.025)])
	_line("SimplifiedFingers",fingers,CYAN,hand,.8)
	if side<0:
		_brush = Node3D.new()
		_brush.name = "MulticolorMerchantPaintbrush"
		_brush.position = Vector3(0,.045,.045)
		hand.add_child(_brush)
		_build_brush(_brush)

func _build_brush(parent: Node3D) -> void:
	var edges := PackedVector3Array()
	var facets := PackedVector3Array()
	for i in range(8):
		var a := i*TAU/8.0
		var b := (i+1)*TAU/8.0
		var low := Vector3(cos(a)*.020,-.40,sin(a)*.020)
		var high := Vector3(cos(a)*.029,.29,sin(a)*.029)
		var next_low := Vector3(cos(b)*.020,-.40,sin(b)*.020)
		var next_high := Vector3(cos(b)*.029,.29,sin(b)*.029)
		facets.append_array([low,next_low,next_high,low,next_high,high])
		edges.append_array([low,high])
	for y: float in [-.30,-.05,.23,.29]: _circle(edges,Vector3(0,y,0),Vector3.RIGHT,Vector3.BACK,.035,12)
	_solid("BrushObsidianShaft",facets,Color("102032"),parent)
	_line("BrushGoldenFerrules",edges,GOLD,parent,1.0)
	var colors := [CYAN,PURPLE,MAGENTA,Color("ffe172"),Color("70ffb3")]
	for i in range(colors.size()):
		var bristles := PackedVector3Array()
		for strand in range(3):
			var angle := (i*3+strand)*TAU/15.0
			var path: Array = []
			for j in range(7):
				var t := j/6.0
				var r := sin(t*PI)*.075+.024*(1.0-t)
				path.append(Vector3(cos(angle)*r+.055*t*t,.29+t*.34,sin(angle)*r))
			_path(bristles,path)
		_ribbon("PrismaticBrushFibers"+str(i),bristles,colors[i],parent,.0025)

func _build_belt() -> void:
	var belt := PackedVector3Array()
	for y: float in [1.23,1.29]: _circle(belt,Vector3(0,y,.0),Vector3.RIGHT,Vector3.BACK,.31,28)
	_line("MerchantWaistRings",belt,GOLD,_hover,.9)
	var brooch := PackedVector3Array()
	_circle(brooch,Vector3(0,1.47,.33),Vector3.RIGHT,Vector3.UP,.10,24)
	_symbol(brooch,0,Vector3(0,1.47,.334),.10)
	_line("InfinityBrooch",brooch,GOLD,_hover,1.1)
