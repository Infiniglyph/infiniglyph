extends RefCounted
## Distinct silhouettes on the shared animated rig; beasts replace its visible body.
const Regalia = preload("res://scripts/pyramid_regalia.gd")
const Glyphs = preload("res://scripts/dungeon_glyphs.gd")
const Neon = preload("res://scripts/neon.gd")
const Surface = preload("res://scripts/garment_surface.gd")

static func cloth(v: Node3D, style: String) -> void:
	var piece:=Regalia.new()
	piece.configure(v,"temple_"+style)

static func decorate(v: Node3D, kind: String, data: Dictionary) -> void:
	if data.get("beast",false):
		for mesh: MeshInstance3D in v.find_children("*","MeshInstance3D",true,false): mesh.hide()
		beast(v,kind)
		return
	v.scale=Vector3.ONE*float(data.get("scale",1.0))
	if kind in ["crocodile","ibis","acolyte","renu","tefet","sakhra"]:
		var mask:=Node3D.new()
		mask.name=kind.to_pascal_case()+"Mask"
		v.chest.add_child(mask)
		mask.position.y=.79
		var outline: Array
		if kind=="crocodile": outline=[[-.17,-.12],[-.18,.11],[.10,.15],[.47,.09],[.57,-.04],[.46,-.13],[.05,-.09]]
		elif kind in ["ibis","acolyte"]: outline=[[-.16,-.11],[-.15,.12],[.03,.18],[.22,.11],[.52,.02],[.68,-.17],[.57,-.10],[.38,-.01],[.05,-.05]]
		else: outline=[[-.15,-.12],[-.19,.05],[-.10,.17],[.08,.16],[.17,.08],[.24,-.05],[.15,-.16],[0,-.18]]
		var head: Node3D=v.form(mask,outline,.26,Vector3.ZERO,v.gold)
		head.rotation.y=-PI*.5
		for side in [-1,1]:
			var eye:=MeshInstance3D.new()
			var mesh:=BoxMesh.new()
			mesh.size=Vector3(.025,.035,.085)
			eye.mesh=mesh
			eye.material_override=Neon.shared_material(Color("5effff"))
			mask.add_child(eye)
			eye.position=Vector3(side*.137,.065,.09)
			if kind=="crocodile":
				var teeth:=PackedVector3Array()
				for i in range(7): teeth.append_array([Vector3(side*.14,-.04,.08+i*.065),Vector3(side*.14,-.095,.10+i*.065),Vector3(side*.14,-.095,.10+i*.065),Vector3(side*.14,-.04,.13+i*.065)])
				v.detail(mask,teeth,v.gold)
			elif kind in ["ibis","acolyte"]:
				v.form(mask,[[-.07,.06],[.07,.06],[.14,-.45],[.02,-.55],[-.09,-.25]],.03,Vector3(side*.15,-.03,-.04),v.gold)
			else:
				v.form(mask,[[-.06,0],[.07,0],[.08,.13],[0,.18],[-.07,.10]],.08,Vector3(side*.14,.11,-.02),v.gold)
				for i in range(5):
					var mane: Node3D=v.form(mask,[[-.04,.04],[.05,.04],[.07,-.20],[0,-.32],[-.05,-.17]],.035,Vector3(side*(.12+i*.025),.04-i*.035,-.07),v.gold)
					mane.rotation.z=side*(.2+i*.15)
	else: v.skeleton()
	if kind=="crocodile":
		cloth(v,"crocodile_cuirass")
		cloth(v,"floodguard_tassets")
		var tail:=Node3D.new()
		v.pelvis.add_child(tail)
		for i in range(7):
			var p: Node3D=v.form(tail,[[-.10+i*.01,0],[.10-i*.01,0],[.08-i*.008,-.22],[-.08+i*.008,-.22]],.16-i*.018,Vector3(0,-i*.075,-.15-i*.16),v.gold)
			p.rotation.x=-1.1
	elif kind in ["ibis","acolyte","skeletal_scribe"]:
		cloth(v,"ibis_scribe_robes")
		cloth(v,"glyphweaver_sash")
	elif kind in ["renu","tefet","sakhra"]:
		cloth(v,"lioness_champion_armor")
		cloth(v,"champion_tassets")
	elif kind=="charmer":
		cloth(v,"serpent_cultist_hood")
		cloth(v,"cultist_wraps")
		cloth(v,"viperbinding_sash")
	else:
		cloth(v,"mummified_wraps")
		cloth(v,"burial_sash")
		if kind=="cursed_warden": cloth(v,"serpent_cultist_hood")

static func beast(v: Node3D, kind: String) -> void:
	var root:=Node3D.new()
	root.name=kind.to_pascal_case()+"Body"
	v.add_child(root)
	v.set_meta("beast_root",root)
	var segments: Array[Node3D]=[]
	if kind in ["construct","charm_obelisk"]:
		for i in range(3 if kind=="construct" else 1):
			var crystal: Node3D=v.form(root,[[0,.9],[.33,.2],[.25,-.45],[0,-.7],[-.25,-.45],[-.33,.2]],.38,Vector3((i-1)*.45 if kind=="construct" else 0,1.0,.0),v.gold)
			crystal.scale=Vector3.ONE*(.7 if kind=="construct" else 1.8)
			segments.append(crystal)
		v.set_meta("beast_segments",segments)
		return
	if kind=="scorpion":
		v.form(root,[[-.28,0],[.28,0],[.37,.22],[.22,.42],[-.22,.42],[-.37,.22]],.8,Vector3(0,.12,0),v.gold)
		var legs:=PackedVector3Array()
		for side in [-1,1]:
			for i in range(4):
				var a:=Vector3(side*.25,.30,(i-1.5)*.23)
				var b:=Vector3(side*.60,.43,(i-1.5)*.36)
				var c:=Vector3(side*.82,.04,(i-1.5)*.48)
				legs.append_array([a,b,b,c])
			v.form(root,[[-.09,-.10],[.10,-.08],[.18,.12],[.07,.24],[0,.09],[-.09,.17]],.10,Vector3(side*.43,.28,.55),v.gold)
		v.detail(root,legs,v.gold)
		for i in range(6):
			var p: Node3D=v.form(root,[[-.07,0],[.07,0],[.06,.23],[-.06,.23]],.13,Vector3(0,.25+i*.13,-.35-i*.07),v.gold)
			p.rotation.x=-.8+i*.30
	else:
		var large: bool=kind=="burial_serpent"
		root.scale=Vector3.ONE*(1.6 if large else 1.0)
		snake_body(root,v.gold)
		var head: Node3D=v.form(root,[[-.12,-.02],[.12,-.02],[.16,.15],[.10,.25],[-.10,.25],[-.16,.15]],.28,Vector3(0,.18,.18),v.gold)
		segments.append(head)
		if kind=="cobra":
			v.form(root,[[-.12,0],[-.32,.28],[-.26,.63],[0,.77],[.26,.63],[.32,.28],[.12,0]],.06,Vector3(0,.15,-.08),v.gold)
			head.position.y=.62
		if kind=="horned_viper":
			for side in [-1,1]: v.detail(head,PackedVector3Array([Vector3(side*.08,.16,.12),Vector3(side*.11,.32,.12)]),v.gold)
		for side in [-1,1]:
			v.detail(head,PackedVector3Array([Vector3(side*.05,.14,.15),Vector3(side*.11,.14,.15),Vector3(side*.06,.01,.16),Vector3(side*.055,-.07,.17)]),Color("5effff"))
	v.set_meta("beast_segments",segments)

static func snake_body(root: Node3D, gold: Color) -> void:
	# One tapered, continuous tube replaces separate cuboid links. The static
	# topology uses two surfaces; the head supplies restrained secondary motion.
	var rings: Array[PackedVector3Array]=[]
	for i in range(15):
		var t:=i/14.0
		var center:=Vector3(sin(t*TAU*1.1)*.18,.12,-t*1.85)
		var radius:=lerpf(.15,.012,pow(t,1.5))
		var ring:=PackedVector3Array()
		for j in range(8): ring.append(center+Vector3(cos(j*TAU/8)*radius,sin(j*TAU/8)*radius*.78,0))
		rings.append(ring)
	var faces:=PackedVector3Array()
	var edges:=PackedVector3Array()
	for i in range(14):
		for j in range(8):
			var a: Vector3=rings[i][j]
			var b: Vector3=rings[i][(j+1)%8]
			var c: Vector3=rings[i+1][(j+1)%8]
			var d: Vector3=rings[i+1][j]
			faces.append_array([a,b,c,a,c,d])
			edges.append_array([a,b,a,d])
	root.add_child(Surface.surface("ContinuousSerpentBody",faces,Color("030507")))
	root.add_child(Neon.lines(edges,Neon.shared_material(gold)))

static func animate(v: Node3D, time: float, speed: float) -> void:
	if not v.has_meta("beast_segments"): return
	var parts: Array=v.get_meta("beast_segments")
	for i in range(parts.size()):
		var part: Node3D=parts[i]
		if v.enemy_kind=="construct":
			part.rotation.y=time*.7+i*TAU/3
		else: part.rotation.y=sin(time*(2+minf(speed,5))+i*.65)*.18
