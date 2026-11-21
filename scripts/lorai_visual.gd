extends Node3D
## Cached low-poly links, controlled curvature and two articulated arms. No rope physics.
const Neon = preload("res://scripts/neon.gd")
const Facets = preload("res://scripts/griffin_visual.gd").Facets
const Pharaoh = preload("res://scripts/character_visual.gd")
const Regalia = preload("res://scripts/ahkmet_regalia.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Glyphs = preload("res://scripts/dungeon_glyphs.gd")
const LINK_COUNT := 26
var links: Array[Node3D]=[]
var joins: Array[Node3D]=[]
var points: Array[Vector3]=[]
var radii: Array[float]=[]
var head: Node3D
var jaw: Node3D
var rider: Node3D
var ahkmet: Node3D
var arms: Array[Node3D]=[]
var elbows: Array[Node3D]=[]
var hands: Array[Node3D]=[]
var staff: Node3D
var staff_tip: Node3D
var glyph_energy: Node3D
var clock:=0.0
var selected: StringName=&"lorai"
var gold: Material
var cyan: Material
var violet: Material
var arm_growth:=0.0

func part(parent: Node3D, label: String, at: Vector3=Vector3.ZERO) -> Node3D:
	var node:=Node3D.new()
	node.name=label
	parent.add_child(node)
	node.position=at
	return node

func ellipsoid(parent: Node3D, at: Vector3, size: Vector3, ink: Material) -> void:
	var f:=Facets.new()
	f.ellipsoid(at,size,10,5)
	f.attach(parent,ink,cyan)

func _ready() -> void:
	name="LoraiVisual"
	Neon.prepare()
	gold=Neon.shared_material(Color("ffc943"))
	cyan=Neon.shared_material(Color("4cffff"))
	violet=Neon.shared_material(Color("bc49ff"))
	# A shared open-ended cylinder overlaps at joints. Continuous silhouette,
	# diamond scale lattice and exactly two shared surfaces for every body link.
	var faces:=PackedVector3Array()
	var lines:=PackedVector3Array()
	for row in range(3):
		for side in range(10):
			var corners: Array[Vector3]=[]
			for c: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var a: float=(side+c.x)*TAU/10
				corners.append(Vector3(cos(a),sin(a),float(row+c.y)/3))
			faces.append_array([corners[0]*.997,corners[1]*.997,corners[2]*.997,corners[0]*.997,corners[2]*.997,corners[3]*.997])
			lines.append_array([corners[0],corners[1],corners[1],corners[2],corners[0],corners[2]])
	var mesh:=ArrayMesh.new()
	for kind in [Mesh.PRIMITIVE_TRIANGLES,Mesh.PRIMITIVE_LINES]:
		var arrays:=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=faces if kind==Mesh.PRIMITIVE_TRIANGLES else lines
		mesh.add_surface_from_arrays(kind,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,Neon.dark if kind==Mesh.PRIMITIVE_TRIANGLES else gold)
	for i in range(LINK_COUNT):
		var link:=part(self,"ScaleLink%02d" % i)
		var skin:=MeshInstance3D.new()
		skin.mesh=mesh
		skin.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		link.add_child(skin)
		links.append(link)
		points.append(Vector3.ZERO)
		radii.append(1.8 if i<7 else lerpf(2.1,.20,float(i-7)/(LINK_COUNT-8)))
	# Shared faceted joint caps fill tight bends without rebuilding a skin mesh.
	var cap:=part(self,"JointTemplate")
	ellipsoid(cap,Vector3.ZERO,Vector3.ONE,gold)
	for i in range(LINK_COUNT):
		var joint:=cap.duplicate()
		add_child(joint)
		joins.append(joint)
	cap.queue_free()
	head=part(self,"LoraiHead")
	ellipsoid(head,Vector3(0,.12,.25),Vector3(2.05,1.15,2.35),gold)
	jaw=part(head,"OpeningJaw",Vector3(0,-.48,-.6))
	ellipsoid(jaw,Vector3(0,-.15,1.1),Vector3(1.84,.38,1.86),gold)
	for side in [-1,1]:
		ellipsoid(head,Vector3(side*1.69,.42,1.28),Vector3(.26,.17,.37),cyan)
		var f:=Facets.new()
		for z: float in [1.4,2.1]: f.feather(Vector3(side*1.4,-.35,z),Vector3(side*1.24,-1.38,z+.16),.24,false)
		f.attach(head,gold,violet)
		var hood:=part(head,"RoyalHood")
		ellipsoid(hood,Vector3(side*1.7,-.45,-1),Vector3(.65,2.05,.50),gold)
	rider=part(head,"HeadStandingSocket",Vector3(0,1.18,-.5))
	ahkmet=Pharaoh.new()
	ahkmet.live_retrieval=false
	rider.add_child(ahkmet)
	ahkmet.name="Ahkmet"
	for surface: MeshInstance3D in ahkmet.find_children("*","MeshInstance3D",true,false):
		if surface.mesh.surface_get_material(0)==Neon.body: surface.material_override=gold
	ahkmet.scale=Vector3.ONE*1.55
	var regalia:=Regalia.new()
	regalia.configure(ahkmet,"ahkmet_full")
	for side in [-1,1]:
		var shoulder:=part(self,"AscendantArm",Vector3(side*2.0,5.2,1.2))
		ellipsoid(shoulder,Vector3(0,-1.2,0),Vector3(1.15,1.65,1.05),gold)
		var elbow:=part(shoulder,"Elbow",Vector3(0,-2.6,0))
		ellipsoid(elbow,Vector3(0,-1.1,0),Vector3(.86,1.50,.85),gold)
		var hand:=part(elbow,"Hand",Vector3(0,-2.55,0))
		ellipsoid(hand,Vector3.ZERO,Vector3(.86,.68,.53),gold)
		for finger in range(4): ellipsoid(hand,Vector3((finger-1.5)*.39,-.65,.08),Vector3(.19,.55,.20),gold)
		arms.append(shoulder)
		elbows.append(elbow)
		hands.append(hand)
	staff=part(rider,"AhkmetsOriginalStaff",Vector3(1.0,1.5,.3))
	# The collectible is a player-sized wand. Ahkmet retains the original
	# ceremonial staff silhouette and focus height used by this encounter.
	var geometry: Dictionary={"family":"staff","length":2.18,"width":.134,"depth":.05,"guard":.32,"detail":5,"paired":false,"tint":"ffd051","style":"plate","bulk":.054,"serpent_focus":true,"light_surface":true}
	staff.add_child(Geometry.model(geometry))
	staff.scale=Vector3.ONE*2.2
	staff_tip=part(staff,"RadiantFocus",Vector3(0,1.65,0))
	glyph_energy=part(self,"UnionGlyphs")
	for i in range(12):
		var ink:=PackedVector3Array()
		for path: Array in Glyphs.paths(i):
			for j in range(1,path.size()):
				for p: Vector2 in [path[j-1],path[j]]: ink.append(Vector3(p.x*.55,p.y*.55,0))
		var mark:=Neon.lines(ink,gold)
		glyph_energy.add_child(mark)
		mark.position=Vector3(cos(i*TAU/12)*4.5,3+i%3, sin(i*TAU/12)*4.5)
		mark.rotation.y=-i*TAU/12
	pose({},0,1,0)

func clear_combat_pose() -> void: pass
func equip(_kind: StringName, _sheathed: bool) -> void: pass
func blade_segments() -> Array: return []

func pose(move: Dictionary, time: float, phase: int, union_time: float, delta: float=0) -> void:
	clock+=delta
	var style: String=move.get("lorai_style","")
	var contact: float=move.get("hits",[1.0])[0]
	var load:=smoothstep(0,maxf(.1,contact-.18),time) if not move.is_empty() else 0.0
	var drive:=smoothstep(contact-.18,contact+.08,time)*(1-smoothstep(contact+.28,float(move.get("duration",2)),time)) if not move.is_empty() else 0.0
	var lunge: bool=style in ["lunge","bite","command","inherited"]
	var sweeping: bool=style=="sweep"
	var head_height:=7.0 if phase==1 else 12.0
	if style=="coil": head_height+=load*3-drive*12.9
	if style in ["spit","storm","judgment","annihilation"]: head_height+=load*1.5
	var head_at:=Vector3(sin(clock*.65)*.32,head_height,5.5)
	if lunge:
		head_at+=Vector3(0,0,-load*2.4+drive*9)
		var lowering:=smoothstep(contact-.30,contact-.12,time)*(1-smoothstep(contact+.35,float(move.duration),time))
		head_at.y=lerpf(head_height+load*.6,2.65,lowering)
	if style=="annihilation": head_at.y-=drive*5
	if sweeping:
		var angle:=lerpf(-1.3,1.3,smoothstep(contact-.16,contact+.17,time))
		head_at=Vector3(sin(angle)*8,2.6,cos(angle)*8)
	if phase==0: head_at=Vector3(0,lerpf(7.0,9.2,smoothstep(0,1.3,union_time)),5.5)
	if phase==0: head_at.y=lerpf(head_at.y,12.0,smoothstep(5.8,8.2,union_time))
	head.position=head_at
	head.rotation=Vector3(-.08-load*.08,sin(clock*.6)*.05 if not sweeping else atan2(head_at.x,head_at.z)*.65,0)
	if phase==0:
		head.rotation.y+=sin(clampf((union_time-1.0)/3.2,0,1)*PI)*.22
		head.rotation.x-=smoothstep(2.0,3.1,union_time)*(1-smoothstep(4.3,5.3,union_time))*.20
	var mouth_open:=drive*.6 if lunge else load*.4 if style in ["spit","storm"] else .04
	if phase==0: mouth_open=smoothstep(2.3,3.3,union_time)*.95*(1-smoothstep(4.3,5.1,union_time))
	jaw.rotation.x=mouth_open
	for i in range(LINK_COUNT):
		if i<7:
			var t:=float(i)/7
			points[i]=head_at.lerp(Vector3(0,1.6,-3.5),t)
			points[i].x+=sin(t*PI)*sin(clock*.7)*.65
		else:
			var t:=float(i-7)/(LINK_COUNT-8)
			var angle:=t*TAU*1.18
			var radius:=lerpf(5.8,12,t)
			points[i]=Vector3(sin(angle)*radius,radii[i]+.06+sin(angle+clock*.8)*.12,-9+cos(angle)*5.8)
	for i in range(LINK_COUNT):
		var a:=points[i]
		var b:=points[mini(i+1,LINK_COUNT-1)] if i<LINK_COUNT-1 else a+Vector3(.6,0,-.5)
		var span:=b-a
		links[i].transform=Transform3D(Basis(Quaternion(Vector3.BACK,span.normalized()))*Basis.from_scale(Vector3(radii[i],radii[i],span.length()+.18)),a)
		joins[i].position=a
		joins[i].scale=Vector3.ONE*radii[i]*1.015
	arm_growth=1.0 if phase==2 else smoothstep(5.8,7.4,union_time) if phase==0 else 0.0
	for i in range(2):
		var side:=1 if i==0 else -1
		arms[i].visible=arm_growth>.01
		arms[i].scale=Vector3.ONE*maxf(.001,arm_growth)
		arms[i].position=Vector3(side*1.7,head_at.y-1.3,head_at.z-2.7)
		arms[i].rotation=Vector3(-.22,side*.15,side*.9)
		elbows[i].rotation=Vector3(-.55,0,0)
		if style=="grasp" and i==1:
			var target: Vector3=to_local(get_parent().attack_goal)
			var origin: Vector3=arms[i].position
			var reach: Vector3=(target-origin).limit_length(12.0)
			var direction:=reach.normalized()
			arms[i].quaternion=Quaternion(Vector3.DOWN,direction)
			arms[i].scale=Vector3(arm_growth,maxf(1,reach.length()/5.15)*arm_growth,arm_growth)
			elbows[i].rotation=Vector3(-.8*(1-drive),0,0)
		if style in ["annihilation","inherited"] and i==0:
			arms[i].rotation=Vector3(-1.2,lerpf(-1.2,1.2,smoothstep(contact-.25,contact+.3,time)),.7)
	ahkmet.visible=phase==1 or phase==0 and union_time<4.7
	if phase==0:
		# Open arms first. He steps willingly down into Lorai's waiting mouth;
		# no kill callback or second actor is used at this narrative beat.
		ahkmet.position=Vector3(0,-smoothstep(3.8,4.7,union_time)*3.7,smoothstep(3.1,3.8,union_time)*3.0)
		ahkmet.scale=Vector3.ONE*1.55*maxf(.02,1-smoothstep(4.2,4.7,union_time))
	else:
		ahkmet.position=Vector3.ZERO
		ahkmet.scale=Vector3.ONE*1.55
	var welcome:=smoothstep(1.5,2.5,union_time) if phase==0 else 0.0
	ahkmet.joints.RightArm.rotation=Vector3(-load*.8,0,.6+welcome*.85)
	ahkmet.joints.LeftArm.rotation=Vector3(-load*.6,0,-.5-welcome*.95)
	var inherited:=phase==2 or phase==0 and union_time>=7.5
	var wanted: Node3D=hands[0] if inherited else rider
	if staff.get_parent()!=wanted: staff.reparent(wanted,false)
	staff.visible=phase!=0 or union_time<3.35 or union_time>=7.5
	staff.position=Vector3(.1,-.4,.2) if inherited else Vector3(1,1.5,.3)
	if not inherited:
		staff.position.y+=load*1.1
		if phase==0: staff.position.y=lerpf(1.5,.15,smoothstep(.7,1.5,union_time))
	staff.scale=Vector3.ONE*(3.3 if inherited else 2.2)
	staff.rotation=Vector3(-.15,-.1,-.20) if inherited else Vector3(-load*.5,0,-.12)
	if inherited and style=="annihilation": staff.rotation.x=lerpf(.3,2.2,drive)
	glyph_energy.visible=phase==2 or phase==0 and union_time>4.6
	glyph_energy.position=Vector3(0,head_at.y-4,head_at.z-2)
	glyph_energy.rotation.y=clock*.24

func mouth() -> Vector3: return head.to_global(Vector3(0,-.35,2.5))

func attack_segments(move: Dictionary, pulse: int) -> Array[Dictionary]:
	var style: String=move.lorai_style
	if style in ["lunge","bite","sweep"] or style=="command" and pulse==0 or style=="inherited" and pulse==0:
		return [{"a":head.to_global(Vector3(0,-.6,0)),"b":mouth(),"radius":1.8}]
	if style=="grasp": return [{"a":arms[1].global_position,"b":hands[1].global_position,"radius":1.1}]
	if style=="annihilation" or style=="inherited" and pulse==1:
		return [{"a":staff.global_position,"b":staff_tip.global_position,"radius":.7}]
	return []
