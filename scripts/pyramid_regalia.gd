extends "res://scripts/falcon_regalia.gd"
## Shared original temple clothing for NPCs and player-sized loot previews.
const Glyphs = preload("res://scripts/dungeon_glyphs.gd")
var style: String

func configure(visual: Node3D, kind: String) -> void:
	figure=visual
	style=kind.trim_prefix("temple_")
	figure.add_child(self)
	name=kind.to_pascal_case()
	if style.ends_with("sash") or style.ends_with("tassets"):
		skirt()
	elif style.ends_with("hood"):
		hood()
	elif style in ["sobek_emblem","thoths_quill","tomb_charm","sekhmet_sigil","serpent_idol"]:
		charm()
	else: torso()
	for root: Node3D in external: batch_panels(root)

func inscription(root: Node3D, at: Vector3, count: int, seed: int=0) -> void:
	var points:=PackedVector3Array()
	for i in range(count):
		for path: Array in Glyphs.paths(i+seed):
			for j in range(1,path.size()):
				for p: Vector2 in [path[j-1],path[j]]: points.append(at+Vector3(p.x*.09,-i*.115+p.y*.09,0))
	root.add_child(Neon.lines(points,Neon.shared_material(Color("6cffff"))))

func torso() -> void:
	var root:=anchor(figure.chest,"TempleTorso")
	var ragged: bool=style in ["mummified_wraps","cultist_wraps"]
	var ibis: bool=style=="ibis_scribe_robes"
	panel(root,[[-.19,0],[.19,0],[.23,.36],[.12,.46],[-.12,.46],[-.23,.36]],Vector3(0,.02,0),.34)
	for side in [-1,1]:
		for i in range(4):
			var plate:=panel(root,[[-.07,.04],[.08,.04],[.10,-.14],[0,-.23],[-.08,-.12]],Vector3(side*(.19+i*.045),.46-i*.035,0),.20)
			plate.rotation.z=side*(.3+i*.15)
		if ibis:
			panel(root,[[-.10,.1],[.10,.1],[.17,-.61],[0,-.78],[-.12,-.52]],Vector3(side*.15,.12,-.21),.025)
	if ragged:
		for i in range(7):
			var strip:=panel(root,[[-.24,.018],[.24,.018],[.24,-.018],[-.24,-.018]],Vector3(0,.08+i*.05,.19),.012)
			strip.rotation.z=.15 if i%2==0 else -.13
	elif style=="crocodile_cuirass":
		for row in range(4):
			for col in range(5): panel(root,[[-.04,.02],[.04,.02],[.035,-.04],[0,-.07],[-.035,-.04]],Vector3((col-2)*.075,.36-row*.085,.19),.025)
	inscription(root,Vector3(0,.35,.21),3,2 if ibis else 0)
	var rim:=PackedVector3Array()
	for i in range(24):
		var a:=i*TAU/24
		var b:=(i+1)*TAU/24
		rim.append_array([Vector3(cos(a)*.28,.49,sin(a)*.20),Vector3(cos(b)*.28,.49,sin(b)*.20)])
	root.add_child(Neon.lines(rim,Neon.shared_material(Color("6cffff"))))

func skirt() -> void:
	tassets() # Articulated closed greaves are shared with the skyguard.
	var root:=anchor(figure.pelvis,"TempleSash")
	var length:=.85 if style in ["glyphweaver_sash","viperbinding_sash"] else .68
	for side in [-1,1]:
		for i in range(4):
			var p:=panel(root,[[-.055,0],[.065,0],[.08,-length*.7],[0,-length],[-.065,-length*.78]],Vector3(side*(.065+i*.065),0,.19-i*.025),.025)
			p.rotation.z=side*i*.13
	panel(root,[[-.075,.04],[.075,.04],[.08,-length],[0,-length-.06],[-.08,-length]],Vector3(0,0,.225),.02)
	inscription(root,Vector3(0,-.08,.242),5,3 if style=="floodguard_tassets" else 1)

func hood() -> void:
	var root:=anchor(figure.chest,"SerpentCultistHood")
	for side in [-1,1]:
		var p:=panel(root,[[-.09,.18],[.09,.18],[.15,-.20],[.08,-.40],[-.09,-.24]],Vector3(side*.15,.78,-.03),.12)
		p.rotation.z=side*.13
	panel(root,[[-.22,0],[.22,0],[.15,.12],[-.14,.12]],Vector3(0,.96,-.03),.27)
	inscription(root,Vector3(.18,.79,.05),3,0)

func charm() -> void:
	var root:=anchor(figure.joints.RightArm.get_node("Hinge"),"TempleKeepsake")
	root.position=Vector3(0,-.22,.065)
	inscription(root,Vector3(0,0,.02),1,["sobek_emblem","thoths_quill","tomb_charm","sekhmet_sigil","serpent_idol"].find(style))
	var rim:=PackedVector3Array()
	for i in range(16): rim.append_array([Vector3(cos(i*TAU/16)*.10,sin(i*TAU/16)*.08,0),Vector3(cos((i+1)*TAU/16)*.10,sin((i+1)*TAU/16)*.08,0)])
	root.add_child(Neon.lines(rim,Neon.shared_material(Color("ffd170"))))
