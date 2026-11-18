extends "res://scripts/character_visual.gd"
## Original jackal masks and articulated skeletal details on the existing rig.
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Wings = preload("res://scripts/pyramid_wings.gd")
const Regalia = preload("res://scripts/falcon_regalia.gd")
const Depth = preload("res://scripts/pyramid_depth_visual.gd")
const Types = preload("res://scripts/pyramid_bestiary.gd")
var enemy_kind := "skeleton"
var gold := Color("ffd170")
var wings: Node3D
var _depth_clock:=0.0

func detail(parent: Node3D, points: PackedVector3Array, color: Color) -> void:
	parent.add_child(Neon.lines(points,Neon.shared_material(color)))

func form(parent: Node3D, outline: Array, depth: float, at: Vector3, tint: Color) -> Node3D:
	var result := Geometry.model({"family":"sword","outline":outline,"depth":depth,"tint":tint.to_html(false)})
	parent.add_child(result)
	result.position = at
	return result

func _ready() -> void:
	super._ready()
	for mesh: MeshInstance3D in find_children("*","MeshInstance3D",true,false):
		if mesh.mesh.surface_get_material(0)==Neon.body: mesh.material_override = Neon.shared_material(gold)
		if enemy_kind in ["skeleton","winged_skeleton","archer"]:
			if mesh.mesh is CylinderMesh: mesh.scale = Vector3(.60,1,.60)
			elif mesh.mesh is SphereMesh: mesh.scale = Vector3.ONE*.72
	# Replace the spherical head; retain the same chest/head animation anchors.
	for mesh: Node in chest.get_children():
		if mesh is MeshInstance3D and mesh.position.y>.7: mesh.hide()
	if Types.TYPES.has(enemy_kind): Depth.decorate(self,enemy_kind,Types.get_type(enemy_kind))
	elif enemy_kind=="jackal": jackal()
	elif enemy_kind=="falcon": falcon()
	else: skeleton()
	if enemy_kind in ["falcon","winged_skeleton"]:
		wings=Wings.new()
		wings.bones=enemy_kind=="winged_skeleton"
		chest.add_child(wings)

func _process(delta: float) -> void:
	_depth_clock+=delta
	if is_visible_in_tree() and has_meta("beast_root"): Depth.animate(self,_depth_clock,get_parent().velocity.length())
	if is_instance_valid(wings) and is_visible_in_tree():
		var actor: CharacterBody3D=get_parent()
		wings.pose(delta,not actor.is_on_floor(),actor.weapon_combat.active_move.get("name","")=="Wing Slash")

func falcon() -> void:
	scale=Vector3.ONE*1.10
	var mask:=Node3D.new()
	mask.name="FalconMask"
	chest.add_child(mask)
	mask.position.y=.78
	# A hooked beak, swept brow and layered occipital plumes make a falcon
	# silhouette rather than a recoloured jackal. Positive Z is forward.
	var head:=form(mask,[[-.14,-.12],[-.15,.11],[-.05,.17],[.15,.12],[.37,.035],[.32,-.15],[.25,-.045],[.06,-.065]],.23,Vector3.ZERO,gold)
	head.rotation.y=-PI*.5
	for side: int in [-1,1]:
		for i in range(4):
			var plume:=form(mask,[[-.04,.04],[.04,.04],[.055,-.16],[0,-.27],[-.04,-.14]],.02,Vector3(side*.13,.10-i*.035,-.05-i*.042),gold)
			plume.rotation.x=-.8-i*.12
		var eye:=MeshInstance3D.new()
		var lens:=BoxMesh.new()
		lens.size=Vector3(.028,.042,.105)
		eye.mesh=lens
		eye.material_override=Neon.shared_material(Color("61ffff"))
		mask.add_child(eye)
		eye.position=Vector3(side*.123,.06,.08)
	form(chest,[[-.085,0],[.085,0],[.10,.25],[-.08,.25]],.14,Vector3(0,.52,0),gold)
	form(chest,[[-.15,.05],[.15,.05],[.19,.35],[.13,.44],[-.13,.44],[-.19,.35]],.16,Vector3(0,.01,0),gold)
	var ribbing:=PackedVector3Array()
	for i in range(4):
		var y: float=.12+i*.075
		ribbing.append_array([Vector3(-.13,y,.094),Vector3(0,y-.025,.12),Vector3(0,y-.025,.12),Vector3(.13,y,.094)])
	detail(chest,ribbing,gold)
	var mantle:=Regalia.new()
	mantle.configure(self,"falcon_mantle")
	var tassets:=Regalia.new()
	tassets.configure(self,"falcon_tassets")

func jackal() -> void:
	scale = Vector3.ONE*1.12
	var mask := Node3D.new()
	chest.add_child(mask)
	mask.position.y = .76
	# Profile is built in XY and rotated into the forward-facing YZ plane.
	var head := form(mask,[[-.12,-.14],[.11,-.16],[.34,-.025],[.28,.035],[.10,.12],[-.1,.13]],.22,Vector3.ZERO,gold)
	head.rotation.y = -PI*.5
	for side in [-1,1]:
		form(mask,[[-.045,0],[.055,0],[.02,.27],[-.035,.17]],.07,Vector3(side*.10,.10,-.03),gold)
		var eye := MeshInstance3D.new()
		var lens := BoxMesh.new()
		lens.size = Vector3(.05,.022,.045)
		eye.mesh = lens
		eye.material_override = Neon.shared_material(Color("55ffff"))
		mask.add_child(eye)
		eye.position = Vector3(side*.08,.09,.115)
	var cuirass := Geometry.model({"family":"body","bulk":.9,"tint":gold.to_html(false)})
	chest.add_child(cuirass)
	cuirass.position.y = .02
	form(chest,[[-.16,0],[.16,0],[.20,.34],[.10,.42],[-.10,.42],[-.20,.34]],.045,Vector3(0,.04,.14),gold)
	var collar := PackedVector3Array()
	for i in range(15):
		var angle := i*TAU/14
		var next := (i+1)*TAU/14
		collar.append_array([Vector3(cos(angle)*.26,.45,sin(angle)*.19),Vector3(cos(next)*.26,.45,sin(next)*.19),Vector3(cos(angle)*.20,.52,sin(angle)*.15),Vector3(cos(angle)*.26,.45,sin(angle)*.19)])
	detail(chest,collar,Color("59ffff"))
	for side in [-1,1]:
		var plate := form(chest,[[-.09,0],[.10,0],[.13,.16],[-.12,.20]],.19,Vector3(side*.23,.38,0),gold)
		plate.rotation.z = side*-.25
	form(pelvis,[[-.14,.05],[.14,.05],[.19,-.62],[0,-.75],[-.19,-.62]],.025,Vector3(0,0,.17),gold)
	var script := PackedVector3Array()
	for i in range(6):
		var y := -.04-i*.10
		script.append_array([Vector3(-.055,y,.19),Vector3(.055,y,.19),Vector3(0,y+.035,.19),Vector3(0,y-.035,.19)])
	detail(pelvis,script,Color("55ffff"))

func skeleton() -> void:
	var skull := form(chest,[[-.12,-.08],[-.14,.08],[-.08,.16],[.08,.16],[.14,.08],[.12,-.08],[.07,-.14],[-.07,-.14]],.18,Vector3(0,.79,0),gold)
	var sockets := PackedVector3Array()
	for side in [-1,1]:
		var center := Vector3(side*.065,.015,.10)
		for j in range(8):
			var a := j*TAU/8
			var b := (j+1)*TAU/8
			sockets.append_array([center+Vector3(cos(a)*.031,sin(a)*.032,0),center+Vector3(cos(b)*.031,sin(b)*.032,0)])
	detail(skull,sockets,Color("65ffff"))
	var teeth := PackedVector3Array([Vector3(-.022,-.025,.102),Vector3(0,-.06,.102),Vector3(0,-.06,.102),Vector3(.022,-.025,.102),Vector3(-.07,-.082,.102),Vector3(.07,-.082,.102)])
	for i in range(6):
		var x := (i-2.5)*.022
		teeth.append_array([Vector3(x,-.067,.102),Vector3(x,-.105,.102)])
	detail(skull,teeth,gold)
	var bones := PackedVector3Array()
	for row in range(6):
		var y := .16+row*.055
		var width := .12+sin(row/5.0*PI)*.065
		for side in [-1,1]:
			var last := Vector3(0,y,.05)
			for segment in range(1,6):
				var t := segment/5.0
				var next := Vector3(side*width*sin(t*PI*.7),y+.035*sin(t*PI),.05+.09*sin(t*PI))
				bones.append_array([last,next])
				last = next
	detail(chest,bones,gold)
	form(pelvis,[[-.15,0],[.14,0],[.17,-.25],[.09,-.19],[.04,-.35],[-.03,-.22],[-.13,-.31]],.04,Vector3(0,0,.025),gold)
	# Small finger bones follow the same hand hinges as the equipped weapons.
	for arm: String in ["LeftArm","RightArm"]:
		var fingers := PackedVector3Array()
		for i in range(3): fingers.append_array([Vector3((i-1)*.022,-.29,0),Vector3((i-1)*.03,-.37,.03)])
		detail(joints[arm].get_node("Hinge"),fingers,gold)
