extends Node3D
## Once-built, floor-owned temple dressing. Broad lanes and all stair apertures stay open.
const Chunk = preload("res://scripts/world_chunk.gd")
const Glyphs = preload("res://scripts/dungeon_glyphs.gd")
const Floor = preload("res://scripts/pyramid_floor.gd")
const Neon = preload("res://scripts/neon.gd")
var storey: Node3D
var batch: Node3D
var theme: String
var features: Array[Dictionary]=[]
var emitters: Array[Vector3]=[]
var motes: MultiMesh
var clock:=0.0
var gold:=Color("ffbd48")
var cyan:=Color("4df7ef")
var purple:=Color("be65fa")

func _ready() -> void:
	name="TempleFurnishings"
	var id: String=storey.definition.id
	theme={"hub":"Threshold Labyrinth","B1":"Hall of the Jackal Watch","B2":"Courts of the Sky Wardens","B3":"Flood Chambers","B4":"Archive of the Ibis","B5":"Burial Galleries","B6":"Court of the Lioness Champions","B7":"Serpent Pit","B8":"Throne of the Vile Pharaoh"}.get(id,"Upper Temple / "+storey.definition.title)
	batch=Chunk.new()
	add_child(batch)
	var half:=Floor.half_at(float(storey.definition.y)+5)-3
	var height: float=minf(10,storey.definition.ceiling-storey.definition.y-1)
	if id=="hub":
		for cell: Vector2i in [Vector2i(2,1),Vector2i(6,3),Vector2i(3,5)]:
			brazier(Vector3((cell.x-4)*8+2.7,.0,-cell.y*8+2.6),.5)
	else:
		if id!="B8" and half>25:
			for side in [-1,1]:
				for row in range(6):
					var p:=Vector3(side*14,storey.definition.y,-68+row*16)
					if absf(p.z+28)<half-5 and free_space(p,1.8): column(p,minf(height,9),1.25)
		var rows:=3 if half>25 else 2
		for side in [-1,1]:
			for row in range(rows):
				var p:=Vector3(side*half*.53,storey.definition.y,Floor.CENTER.z+lerpf(-half*.58,half*.55,float(row)/maxi(1,rows-1)))
				if not free_space(p,3.0): continue
				if id in ["B5","B7"]: sarcophagus(p,id=="B7")
				else: statue(p,3.5 if half>25 else 1.7,id)
			for z: float in [-.35,.3]:
				var p:=Vector3(side*half*.34,storey.definition.y,Floor.CENTER.z+half*z)
				if free_space(p,1.3): brazier(p,.85 if half>25 else .5)
		# Hieroglyphic columns line the processional routes without narrowing them.
		for side in [-1,1]:
			for row in range(3 if half>25 else 1):
				var p:=Vector3(side*half*.78,storey.definition.y,Floor.CENTER.z+(row-1)*half*.5)
				if free_space(p,1.8): column(p,minf(height,8.5),1.4)
		if id=="B3": flood_chambers(half)
		elif id=="B4": archive(half)
		elif id=="B5": burial(half)
		elif id=="B6": champion_court()
		elif id=="B7": serpent_pits(half)
		elif id=="B2": sky_courts(half)
		elif id=="B8": serpent_throne()
		else:
			floor_seal(Vector3(0,storey.definition.y+.025,-28),minf(8,half*.24),int(storey.definition.number)%6,cyan*.65)
			if String(id).begins_with("U"): upper_gallery(half)
		wall_relief(half,height,id)
		decorate_structural_columns()
	batch.commit()
	batch.body.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	_build_motes()
	storey.label.text=("ENTRY HUB" if id=="hub" else id)+"  /  "+theme

func free_space(point: Vector3, radius: float) -> bool:
	var area:=Rect2(Vector2(point.x,point.z)-Vector2.ONE*radius,Vector2.ONE*radius*2)
	if point.distance_to(storey.spawn_anchor.position)<radius+5: return false
	for hole: Rect2 in storey.floor_holes+storey.ceiling_holes:
		if area.intersects(hole.grow(2)): return false
	for lane: Rect2 in storey.traversal_lanes:
		if area.intersects(lane): return false
	for volume: Dictionary in storey.batch.volumes:
		if volume.kind not in ["Pillar","PillarBase","PartitionWall","GalleryLedge","ProcessionalScreen"]: continue
		var shape: Shape3D=volume.collider.shape
		if shape is BoxShape3D:
			var center: Vector3=volume.transform.origin
			if area.intersects(Rect2(Vector2(center.x,center.z)-Vector2(shape.size.x,shape.size.z)*.5,Vector2(shape.size.x,shape.size.z)).grow(.5)): return false
	return true

func ring(at: Vector3, radius: float, ink: Color, segments: int=48) -> void:
	for i in range(segments): batch.line(at+Vector3(cos(i*TAU/segments),0,sin(i*TAU/segments))*radius,at+Vector3(cos((i+1)*TAU/segments),0,sin((i+1)*TAU/segments))*radius,ink)

func floor_seal(at: Vector3, radius: float, kind: int, ink: Color) -> void:
	ring(at,radius,ink)
	ring(at,radius*.9,ink*.7)
	Glyphs.draw(batch,kind,at+Vector3.UP*.012,Vector3.RIGHT,radius*.7,ink,Vector3.FORWARD)
	for i in range(8):
		var a:=i*TAU/8
		Glyphs.draw(batch,i,at+Vector3(cos(a),0,sin(a))*radius*.72,Vector3.RIGHT,radius*.13,ink,Vector3.FORWARD)

func serpent_throne() -> void:
	var y: float=storey.definition.y
	# Entire center remains traversable; the ceremonial boundary is visual.
	floor_seal(Vector3(0,y+.03,-48),49,0,gold*.6)
	ring(Vector3(0,y+.04,-48),55,purple*.75,96)
	for side in [-1,1]:
		for z: float in [-3,-48,-93]:
			var p:=Vector3(side*43,y,z)
			if free_space(p,3): column(p,22,2.4)
		var at:=Vector3(side*17,y,-106)
		batch.box(at+Vector3.UP*.65,Vector3(7,1.3,7),"SerpentStatuePlinth",gold)
		# Low-poly raised serpent carvings are batched with the room, not actors.
		for row in range(15):
			var a:=row*.40
			var p:=at+Vector3(sin(a)*2.2,1.8+row*.6,cos(a)*1.4)
			for edge in range(8):
				var u:=edge*TAU/8
				var v: float=(edge+1)*TAU/8
				batch.line(p+Vector3(cos(u),0,sin(u))*.9,p+Vector3(cos(v),0,sin(v))*.9,gold)
		batch.box(at+Vector3(0,11,1.5),Vector3(3.2,1.5,3),"SerpentStatueHead",gold)
		Glyphs.draw(batch,3,at+Vector3(0,2,3.51),Vector3.RIGHT,1.0,cyan)
		brazier(Vector3(side*12,y,-100),1.3)
	# A royal platform beyond the battle circle. Steps stay below climbing height.
	for step in range(5): batch.box(Vector3(0,y+.13+step*.26,-108-step*1.1),Vector3(14-step*.9,.26,7-step*.3),"ThroneStep",gold)
	batch.box(Vector3(0,y+2.1,-115),Vector3(5,1.5,3.5),"CeremonialThrone",gold)
	batch.box(Vector3(0,y+5.1,-116.3),Vector3(5,.5+7, .7),"ThroneBack",gold)
	for side in [-1,1]: batch.box(Vector3(side*2.8,y+3.2,-115),Vector3(.7,3.2,3.8),"ThroneArm",gold)
	Glyphs.draw(batch,0,Vector3(0,y+5,-115.90),Vector3.RIGHT,2,cyan)
	features.append({"kind":"serpent_throne","point":Vector3(0,y,-115)})

func column(at: Vector3, height: float, width: float) -> void:
	batch.box(at+Vector3.UP*height*.5,Vector3(width,height,width),"InscribedColumn",gold)
	for y: float in [.18,height-.22]: batch.box(at+Vector3.UP*y,Vector3(width*1.55,.36,width*1.55),"LotusColumnRim",gold)
	for i in range(int(height/1.15)):
		Glyphs.draw(batch,i,at+Vector3(0,1.0+i*1.05,width*.505),Vector3.RIGHT,width*.6,cyan)
	features.append({"kind":"inscribed_column","point":at})

func brazier(at: Vector3, size: float) -> void:
	features.append({"kind":"brazier","point":at})
	batch.box(at+Vector3.UP*.15*size,Vector3(1,.3,1)*size,"BrazierFoot",gold)
	batch.box(at+Vector3.UP*.85*size,Vector3(.5,1.4,.5)*size,"BrazierStem",gold)
	batch.box(at+Vector3.UP*1.6*size,Vector3(1.2,.25,1.2)*size,"FireBowl",gold)
	for i in range(7):
		var a:=i*TAU/7
		batch.line(at+Vector3(cos(a)*.4,1.7,sin(a)*.4)*size,at+Vector3(cos(a+.4)*.15,2.4,sin(a+.4)*.15)*size,gold)
	emitters.append(at+Vector3.UP*1.9*size)

func statue(at: Vector3, size: float, id: String) -> void:
	batch.box(at+Vector3.UP*.2,Vector3(size*1.1,.4,size*.95),"StatuePlinth",gold)
	batch.box(at+Vector3.UP*size*.5,Vector3(size*.45,size*.7,size*.34),"TempleStatue",gold)
	for side in [-1,1]:
		batch.box(at+Vector3(side*size*.24,size*.54,0),Vector3(size*.12,size*.6,size*.14),"StatueArm",gold)
	var kind:=4 if id=="B2" else 1 if id=="B4" else 5 if id=="B7" else 0
	var face:=at+Vector3(0,size*.95,size*.19)
	batch.box(at+Vector3(0,size*.96,0),Vector3(size*.35,size*.33,size*.38),"StatueHead",gold)
	for side in [-1,1]:
		batch.line(face+Vector3(side*size*.08,.03,.02),face+Vector3(side*size*.03,.03,.02),cyan)
	if id=="B3": batch.box(at+Vector3(0,size*.91,size*.30),Vector3(size*.35,size*.17,size*.47),"CrocodileStatueSnout",gold)
	elif id in ["B2","B4"]:
		batch.line(face+Vector3(0,0,.02),face+Vector3(0,-size*.12,size*.37),gold)
	else:
		for side in [-1,1]: batch.line(face+Vector3(side*size*.12,size*.1,0),face+Vector3(side*size*.13,size*.30,0),gold)
	Glyphs.draw(batch,kind,at+Vector3(0,size*.55,size*.18),Vector3.RIGHT,size*.23,cyan)
	features.append({"kind":"statue","point":at})

func sarcophagus(at: Vector3, serpent: bool=false) -> void:
	batch.box(at+Vector3.UP*.55,Vector3(1.5,1.1,3.5),"BurialSarcophagus",gold)
	batch.box(at+Vector3.UP*1.14,Vector3(1.6,.16,3.6),"SarcophagusLid",gold)
	Glyphs.draw(batch,5 if serpent else 0,at+Vector3.UP*1.23,Vector3.RIGHT,.85,cyan,Vector3.FORWARD)
	features.append({"kind":"burrow" if serpent else "sarcophagus","point":at})

func flood_chambers(half: float) -> void:
	for side in [-1,1]:
		var at:=Vector3(side*half*.40,storey.definition.y+.025,-28)
		var w:=half*.22
		# Thin water lies over continuous collision: no swimming or movement restriction.
		for i in range(18):
			var z: float=-w+i*w*2/17
			batch.line(at+Vector3(-w,0,z),at+Vector3(w,0,z),cyan*.55)
		features.append({"kind":"shallow_water","point":at,"radius":w})
		var plane:=MeshInstance3D.new()
		var surface:=PlaneMesh.new()
		surface.size=Vector2(w*2,half*1.15)
		plane.mesh=surface
		var shader:=Shader.new()
		shader.code="shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; void fragment(){float ripple=sin(UV.x*140.0+TIME*1.2+sin(UV.y*70.0-TIME)*.8); ALBEDO=vec3(.03,.68,.65)*(0.7+ripple*.15); ALPHA=.12+ripple*.025;}"
		var water:=ShaderMaterial.new()
		water.shader=shader
		plane.material_override=water
		add_child(plane)
		plane.position=at+Vector3.UP*.018
		var fountain:=Vector3(side*half*.62,storey.definition.y,-28-half*.60)
		if free_space(fountain,3):
			statue(fountain,4,"B3")
			for j in range(6):
				var start:=fountain+Vector3((j-2.5)*.12,3.5,1.2)
				batch.line(start,start+Vector3(0,-3.4,1.6),cyan)
				emitters.append(start+Vector3(0,-2,1))

func archive(half: float) -> void:
	for side in [-1,1]:
		for row in range(4):
			var p:=Vector3(side*half*.48,storey.definition.y,-28+(row-1.5)*14)
			if not free_space(p,2.4): continue
			batch.box(p+Vector3.UP*1.2,Vector3(3.4,2.4,1.2),"ArchiveLectern",gold)
			for i in range(5):
				batch.box(p+Vector3((i-2)*.55,2.6,0),Vector3(.40,.7,.75),"SealedCodex",gold,Basis(Vector3.UP,.15*(i-2)),false)
				Glyphs.draw(batch,i,p+Vector3((i-2)*.55,2.6,.39),Vector3.RIGHT,.26,cyan)
			features.append({"kind":"archive","point":p})
	for p in [Vector3(-18,storey.definition.y+.03,-58),Vector3(18,storey.definition.y+.03,-78)]: floor_seal(p,5,1,cyan)

func burial(half: float) -> void:
	for side in [-1,1]:
		for row in range(5):
			var p:=Vector3(side*half*.30,storey.definition.y,-28+(row-2)*16)
			if free_space(p,2.5): sarcophagus(p)
		for i in range(5):
			var at:=Vector3(side*(18+i*7),storey.definition.y+.03,-56-i*9)
			for j in range(6):
				var a:=j*2.4
				batch.line(at+Vector3(cos(a),0,sin(a)),at+Vector3(cos(a+.5)*2,.3,sin(a+.5)*2),gold*.6)

func champion_court() -> void:
	var y: float=storey.definition.y
	floor_seal(Vector3(0,y+.035,-55),21,1,gold)
	for side in [-1,1]:
		var p:=Vector3(side*27,y,-63)
		if free_space(p,4): statue(p,6,"B6")
	# The central reliquary illuminates when all three champions fall.
	features.append({"kind":"champion_reliquary","point":Vector3(0,y+.08,-76)})

func serpent_pits(half: float) -> void:
	for side in [-1,1]:
		for row in range(3):
			var at:=Vector3(side*(18+row*8),storey.definition.y+.035,-48-row*27)
			floor_seal(at,4.5,5,purple)
			features.append({"kind":"venom_mist","point":at,"radius":3.5})
			for i in range(3): emitters.append(at+Vector3((i-1)*1.8,.18,0))
		var at:=Vector3(side*half*.46,storey.definition.y,-28-half*.55)
		if free_space(at,3): statue(at,5,"B7")

func sky_courts(half: float) -> void:
	for side in [-1,1]:
		var p:=Vector3(side*half*.36,storey.definition.y,-28-half*.4)
		if not free_space(p,3): continue
		for i in range(3): batch.box(p+Vector3(0,.15+i*.22,0),Vector3(5.0-i,.3,4.5-i),"SkyguardDais",gold)
		floor_seal(p+Vector3.UP*.75,1.5,4,cyan)
		features.append({"kind":"sky_dais","point":p})

func upper_gallery(half: float) -> void:
	for side in [-1,1]:
		var p:=Vector3(side*half*.45,storey.definition.y,-28-half*.48)
		if free_space(p,1.3):
			column(p,minf(5.5,storey.definition.ceiling-storey.definition.y-1),.65)
			features.append({"kind":"votive_gallery","point":p})

func wall_relief(half: float, height: float, id: String) -> void:
	var at:=Vector3(0,storey.definition.y+height*.52,-28-half*.94)
	# A floating wall medallion uses lines only and cannot obstruct a flight.
	var r:=minf(7,half*.20)
	for i in range(48):
		var a:=i*TAU/48
		var b:=(i+1)*TAU/48
		batch.line(at+Vector3(cos(a),sin(a),0)*r,at+Vector3(cos(b),sin(b),0)*r,gold)
	if id in ["B3","B4","B6","B7"]: animal_relief(at,r*.8,id)
	else: Glyphs.draw(batch,{"B2":4,"B5":0}.get(id,2),at,Vector3.RIGHT,r*1.15,cyan)
	features.append({"kind":"relief","point":at})

func animal_relief(at: Vector3, size: float, id: String) -> void:
	var paths: Array=[]
	if id=="B6":
		paths=[[Vector2(-.65,.5),Vector2(-.5,.9),Vector2(-.2,.66),Vector2(.2,.66),Vector2(.5,.9),Vector2(.65,.5),Vector2(.54,-.4),Vector2(0,-.78),Vector2(-.54,-.4),Vector2(-.65,.5)], [Vector2(-.4,.25),Vector2(-.13,.12)], [Vector2(.4,.25),Vector2(.13,.12)], [Vector2(-.18,-.15),Vector2(.18,-.15),Vector2(0,-.33),Vector2(-.18,-.15)], [Vector2(0,-.33),Vector2(0,-.5),Vector2(-.24,-.4)],[Vector2(0,-.5),Vector2(.24,-.4)]]
		for i in range(16):
			var a:=i*TAU/16
			batch.line(at+Vector3(cos(a),sin(a),0)*size*.96,at+Vector3(cos(a),sin(a),0)*size*1.14,gold)
	elif id=="B3":
		paths=[[Vector2(-.7,-.3),Vector2(-.55,.55),Vector2(-.1,.65),Vector2(.25,.38),Vector2(.9,.3),Vector2(1,.03),Vector2(.25,-.12),Vector2(-.5,-.4)], [Vector2(-.05,.37),Vector2(.13,.32)], [Vector2(.1,.1),Vector2(.85,.12)]]
		for i in range(7):
			var p:=Vector2(.15+i*.1,.12)
			paths.append([p,p+Vector2(.03,-.12),p+Vector2(.07,0)])
	elif id=="B4":
		paths=[[Vector2(-.45,-.6),Vector2(-.65,-.1),Vector2(-.55,.4),Vector2(-.15,.65),Vector2(.23,.48),Vector2(.64,.12),Vector2(.84,-.45),Vector2(.6,-.18),Vector2(.18,.1),Vector2(-.15,-.12),Vector2(-.15,-.6)], [Vector2(-.17,.37),Vector2(.04,.36)]]
	else:
		paths=[[Vector2(-.6,-.65),Vector2(.2,-.65),Vector2(.52,-.4),Vector2(.25,-.12),Vector2(-.28,.05),Vector2(-.42,.36),Vector2(-.16,.65),Vector2(.13,.68),Vector2(.39,.48),Vector2(.27,.22),Vector2(.05,.37),Vector2(-.16,.3),Vector2(-.18,.15),Vector2(.40,-.04),Vector2(.72,-.34),Vector2(.55,-.69),Vector2(-.6,-.65)], [Vector2(-.4,.42),Vector2(-.68,.20),Vector2(-.62,-.12),Vector2(-.20,.08)],[Vector2(.1,.48),Vector2(.22,.47)]]
	for path: Array in paths:
		for i in range(1,path.size()):
			var a: Vector2=path[i-1]
			var b: Vector2=path[i]
			batch.line(at+Vector3(a.x,a.y,0)*size,at+Vector3(b.x,b.y,0)*size,cyan if path.size()==2 else gold)

func decorate_structural_columns() -> void:
	for volume: Dictionary in storey.batch.volumes:
		if volume.kind!="Pillar": continue
		var at: Vector3=volume.transform.origin
		var size: Vector3=volume.collider.shape.size
		for i in range(int(size.y/1.15)):
			Glyphs.draw(batch,i,Vector3(at.x,at.y-size.y*.5+.9+i*1.1,at.z+size.z*.51),Vector3.RIGHT,size.x*.65,cyan)

func _build_motes() -> void:
	if emitters.is_empty(): return
	motes=MultiMesh.new()
	motes.transform_format=MultiMesh.TRANSFORM_3D
	var shard:=PrismMesh.new()
	shard.size=Vector3(.09,.28,.09)
	motes.mesh=shard
	motes.instance_count=mini(96,emitters.size()*6)
	var view:=MultiMeshInstance3D.new()
	view.multimesh=motes
	view.material_override=Neon.shared_material(purple if storey.definition.id==&"B7" else cyan if storey.definition.id==&"B3" else gold)
	if storey.definition.id==&"B7":
		var cloud:=QuadMesh.new()
		cloud.size=Vector2(1.6,1.0)
		motes.mesh=cloud
		var mist:=StandardMaterial3D.new()
		mist.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mist.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		mist.albedo_color=Color(.55,.15,.85,.12)
		mist.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
		mist.cull_mode=BaseMaterial3D.CULL_DISABLED
		var gradient:=Gradient.new()
		gradient.set_color(0,Color.WHITE)
		gradient.set_color(1,Color(1,1,1,0))
		var cloud_texture:=GradientTexture2D.new()
		cloud_texture.width=32
		cloud_texture.height=32
		cloud_texture.gradient=gradient
		cloud_texture.fill=GradientTexture2D.FILL_RADIAL
		cloud_texture.fill_from=Vector2(.5,.5)
		cloud_texture.fill_to=Vector2(1,.5)
		mist.albedo_texture=cloud_texture
		view.material_override=mist
	add_child(view)

func _process(delta: float) -> void:
	if motes==null or not is_visible_in_tree(): return
	clock+=delta
	for i in range(motes.instance_count):
		var t:=fmod(clock*.55+i*.177,1.0)
		var at:=emitters[i%emitters.size()]+Vector3(sin(i*2.4+clock)*.18,t*.8,cos(i*2.4)*.18)
		motes.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3.ONE*sin(t*PI)),at))
