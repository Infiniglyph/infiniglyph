extends RefCounted
## One batched native model and the same simple collision recipe per item.
## Every model uses a bottom-centred local origin and metres.
const Catalog=preload("res://scripts/item_catalog.gd")
const Chunk=preload("res://scripts/world_chunk.gd")

static func size_of(properties: Dictionary) -> Vector3:
	var value: Variant=properties.get("size",[.5,.5,.5])
	if not value is Array or value.size()!=3: return Vector3(.5,.5,.5)
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _part(at: Vector3,size: Vector3,accent: bool = false) -> Dictionary:
	return {"position":at,"size":size.max(Vector3.ONE*.008),"accent":accent}

static func _food(properties: Dictionary) -> Array[Dictionary]:
	var kind:=String(properties.get("food_shape",""))
	var result: Array[Dictionary]=[_part(Vector3(0,.025,0),Vector3(.5,.05,.42))]
	if properties.get("cuisine_kind")=="drink":
		var tall: bool=kind in ["liquid_light","data_smoothie","refresh_packet"]
		result=[_part(Vector3(0,.2 if tall else .15,0),Vector3(.17 if tall else .26,.4 if tall else .3,.17 if tall else .26)),_part(Vector3(0,.41 if tall else .31,0),Vector3(.20 if tall else .29,.025,.20 if tall else .29),true)]
		if kind in ["ion_tea","charged_coffee"]: result.append(_part(Vector3(.18,.18,0),Vector3(.12,.13,.08),true))
		if kind=="data_smoothie": result.append(_part(Vector3(.04,.48,0),Vector3(.025,.18,.025),true))
		return result
	if kind in ["byte_bites","data_dumplings","electron_rice","neon_sushi"]:
		for x in [-1,1]:
			for z in [-1,1]:
				result.append(_part(Vector3(x*.105,.115,z*.085),Vector3(.14,.12,.12),true))
				if kind=="neon_sushi": result.append(_part(Vector3(x*.105,.185,z*.085),Vector3(.12,.025,.10)))
	elif kind in ["circuit_noodles","quantum_ramen","voltage_stew","fractal_curry","binary_bowl"]:
		result.append(_part(Vector3(0,.15,0),Vector3(.37,.22,.32),true))
		for i in range(4): result.append(_part(Vector3(-.12+i*.08,.275,0),Vector3(.035,.025,.23)))
		if kind=="quantum_ramen": result.append(_part(Vector3(.14,.32,0),Vector3(.025,.03,.44),true))
	elif kind in ["photon_skewers","cache_fries"]:
		for i in range(5): result.append(_part(Vector3(-.16+i*.08,.14,0),Vector3(.04,.16 if kind=="cache_fries" else .09,.30),i%2==0))
	elif kind=="pixel_toast": result.append(_part(Vector3(0,.09,0),Vector3(.34,.08,.29),true)); result.append(_part(Vector3(0,.14,0),Vector3(.21,.02,.18)))
	elif kind=="bit_burger":
		for i in range(4): result.append(_part(Vector3(0,.08+i*.065,0),Vector3(.30,.06,.27),i%2==0))
	elif kind=="plasma_pizza":
		result.append(_part(Vector3(0,.08,0),Vector3(.39,.05,.34),true))
		for x in [-1,1]: result.append(_part(Vector3(x*.1,.12,0),Vector3(.065,.025,.12)))
	elif kind=="algorithmic_pasta":
		for i in range(5): result.append(_part(Vector3(-.14+i*.07,.10+i%2*.04,0),Vector3(.05,.08,.24),i%2==0))
	elif kind=="electron_feast":
		result[0].size=Vector3(.55,.05,.47)
		result.append(_part(Vector3(0,.14,0),Vector3(.25,.18,.2),true))
		for x in [-1,1]: result.append(_part(Vector3(x*.2,.09,0),Vector3(.09,.08,.32),true))
	elif kind=="glitch_gelato":
		result.append(_part(Vector3(0,.12,0),Vector3(.2,.18,.2)))
		result.append(_part(Vector3(-.055,.25,0),Vector3(.16,.13,.16),true))
		result.append(_part(Vector3(.055,.34,0),Vector3(.16,.13,.16),true))
	else:
		result.append(_part(Vector3(0,.17,0),Vector3(.32,.24,.27),true))
		result.append(_part(Vector3(0,.30,0),Vector3(.34,.035,.29)))
		if kind=="quantum_cake": result.append(_part(Vector3(0,.39,0),Vector3(.2,.16,.18),true))
	return result

static func boxes(properties: Dictionary) -> Array[Dictionary]:
	var s:=size_of(properties)
	var kind:=String(properties.get("furniture_kind","crate"))
	var result: Array[Dictionary]=[]
	if properties.get("civilian_food",false): return _food(properties)
	if kind in ["bed","deluxe_bed"]:
		result=[_part(Vector3(0,s.y*.2,0),Vector3(s.x,s.y*.4,s.z)),_part(Vector3(0,s.y*.5,0),Vector3(s.x*.94,s.y*.2,s.z*.94),true),_part(Vector3(0,s.y*.65,-s.z*.46),Vector3(s.x,s.y*.7,s.z*.08)),_part(Vector3(0,s.y*.65,-s.z*.28),Vector3(s.x*.72,s.y*.15,s.z*.2),true)]
		if kind=="deluxe_bed": result.append(_part(Vector3(0,s.y*.4,s.z*.46),Vector3(s.x,s.y*.8,s.z*.08)))
	elif kind in ["chair","grand_chair","stool"]:
		var seat:=.42 if kind!="stool" else .9
		result.append(_part(Vector3(0,s.y*seat,0),Vector3(s.x,s.y*.12,s.z),true))
		for x in [-1,1]:
			for z in [-1,1]: result.append(_part(Vector3(x*s.x*.38,s.y*(seat-.06)*.5,z*s.z*.38),Vector3(s.x*.1,s.y*(seat-.06),s.z*.1)))
		if kind!="stool": result.append(_part(Vector3(0,s.y*.74,-s.z*.43),Vector3(s.x,s.y*.52,s.z*.14)))
		if kind=="grand_chair":
			for x in [-1,1]: result.append(_part(Vector3(x*s.x*.44,s.y*.58,0),Vector3(s.x*.12,s.y*.13,s.z*.9),true))
	elif kind=="sofa":
		result=[_part(Vector3(0,s.y*.13,0),Vector3(s.x,s.y*.26,s.z)),_part(Vector3(0,s.y*.4,0),Vector3(s.x*.88,s.y*.22,s.z*.9),true),_part(Vector3(0,s.y*.72,-s.z*.4),Vector3(s.x,s.y*.56,s.z*.2))]
		for x in [-1,1]: result.append(_part(Vector3(x*s.x*.44,s.y*.55,0),Vector3(s.x*.12,s.y*.5,s.z),true))
	elif kind in ["table","small_table","round_table","meeting_table","desk","workbench","repair","crafting","cooking"]:
		var top:=.72 if kind in ["crafting","cooking"] else .92
		result.append(_part(Vector3(0,s.y*top,0),Vector3(s.x,s.y*.16,s.z),true))
		for x in [-1,1]:
			for z in [-1,1]: result.append(_part(Vector3(x*s.x*.4,s.y*(top-.08)*.5,z*s.z*.38),Vector3(s.x*.065,s.y*(top-.08),s.z*.1)))
		if kind=="desk": result.append(_part(Vector3(s.x*.32,s.y*.55,0),Vector3(s.x*.26,s.y*.5,s.z*.85)))
		if kind in ["workbench","repair"]: result.append(_part(Vector3(s.x*.25,s.y*.99,0),Vector3(s.x*.28,s.y*.02,s.z*.5)))
		if kind=="crafting": result.append(_part(Vector3(0,s.y*.91,-s.z*.3),Vector3(s.x*.68,s.y*.18,s.z*.22)))
		if kind=="cooking": result.append(_part(Vector3(0,s.y*.91,-s.z*.4),Vector3(s.x,s.y*.18,s.z*.18)))
	elif kind in ["bookshelf","display_shelf","rack","wall_shelf"]:
		for x in [-1,1]: result.append(_part(Vector3(x*s.x*.47,s.y*.5,0),Vector3(s.x*.06,s.y,s.z)))
		for i in range(4 if kind!="wall_shelf" else 2):
			var y:=float(i)/3 if kind!="wall_shelf" else float(i)
			result.append(_part(Vector3(0,s.y*(.04+.92*y),0),Vector3(s.x,s.y*.06,s.z),true))
		if kind=="bookshelf":
			for i in range(7): result.append(_part(Vector3(s.x*(-.36+i*.12),s.y*.25,-s.z*.05),Vector3(s.x*.075,s.y*.26,s.z*.55),i%2==0))
	elif kind in ["wardrobe","food_storage","archive","storage_terminal"]:
		result=[_part(Vector3(0,s.y*.5,0),s),_part(Vector3(0,s.y*.5,s.z*.505),Vector3(s.x*.88,s.y*.9,.012),true)]
		if kind=="archive":
			for i in range(3): result.append(_part(Vector3(0,s.y*(.2+i*.25),s.z*.52),Vector3(s.x*.7,s.y*.13,.012)))
		else: result.append(_part(Vector3(0,s.y*.5,s.z*.52),Vector3(.04,s.y*.65,.012)))
	elif kind in ["counter","reception"]:
		result=[_part(Vector3(0,s.y*.44,0),Vector3(s.x*.94,s.y*.88,s.z*.88)),_part(Vector3(0,s.y*.94,0),Vector3(s.x,s.y*.12,s.z),true)]
		if kind=="reception": result.append(_part(Vector3(s.x*.25,s.y*.99,0),Vector3(s.x*.4,s.y*.02,s.z*.45)))
	elif kind=="stall":
		result=[_part(Vector3(0,s.y*.32,0),Vector3(s.x,s.y*.08,s.z*.9),true),_part(Vector3(0,s.y*.94,0),Vector3(s.x,s.y*.12,s.z))]
		for x in [-1,1]:
			for z in [-1,1]: result.append(_part(Vector3(x*s.x*.45,s.y*.45,z*s.z*.42),Vector3(.08,s.y*.9,.08)))
	elif kind in ["terminal","security","guild_terminal","trade_terminal"]:
		result=[_part(Vector3(0,s.y*.06,0),Vector3(s.x,s.y*.12,s.z)),_part(Vector3(0,s.y*.37,0),Vector3(s.x*.35,s.y*.62,s.z*.38)),_part(Vector3(0,s.y*.76,0),Vector3(s.x,s.y*.48,s.z*.35),true)]
		if kind=="security": result.append(_part(Vector3(0,s.y*.72,s.z*.19),Vector3(.05,s.y*.43,.02)))
	elif kind=="door_module":
		for x in [-1,1]: result.append(_part(Vector3(x*s.x*.46,s.y*.5,0),Vector3(s.x*.08,s.y,s.z)))
		result.append(_part(Vector3(0,s.y*.96,0),Vector3(s.x,s.y*.08,s.z),true))
	elif kind in ["painting","math_art","banner","contract_board","lighting_control","emblem","clock"]: result=[_part(Vector3(0,s.y*.5,0),s,true)]
	elif kind=="pillar": result=[_part(Vector3(0,s.y*.04,0),Vector3(s.x,s.y*.08,s.z)),_part(Vector3(0,s.y*.5,0),Vector3(s.x*.62,s.y*.84,s.z*.62),true),_part(Vector3(0,s.y*.96,0),Vector3(s.x,s.y*.08,s.z))]
	elif kind in ["lamp","lantern","hanging_light"]:
		result=[_part(Vector3(0,s.y*.04,0),Vector3(s.x*.7,s.y*.08,s.z*.7)),_part(Vector3(0,s.y*.43,0),Vector3(s.x*.08,s.y*.78,s.z*.08)),_part(Vector3(0,s.y*.86,0),Vector3(s.x,s.y*.28,s.z),true)]
	elif kind in ["plant","bonsai"]:
		result=[_part(Vector3(0,s.y*.17,0),Vector3(s.x*.55,s.y*.34,s.z*.55)),_part(Vector3(0,s.y*.57,0),Vector3(s.x*.08,s.y*.46,s.z*.08)),_part(Vector3(0,s.y*.8,0),Vector3(s.x,s.y*.4,s.z),true)]
		if kind=="bonsai":
			result=[_part(Vector3(0,s.y*.11,0),Vector3(s.x*.8,s.y*.22,s.z*.65)),_part(Vector3(0,s.y*.45,0),Vector3(s.x*.08,s.y*.5,s.z*.08)),_part(Vector3(-s.x*.24,s.y*.65,0),Vector3(s.x*.5,s.y*.22,s.z*.6),true),_part(Vector3(s.x*.12,s.y*.87,0),Vector3(s.x*.62,s.y*.25,s.z),true)]
	elif kind=="aquarium": result=[_part(Vector3(0,s.y*.16,0),Vector3(s.x,s.y*.32,s.z)),_part(Vector3(0,s.y*.66,0),Vector3(s.x,s.y*.68,s.z),true)]
	elif kind=="rug": result=[_part(Vector3(0,s.y*.5,0),s,true)]
	elif kind in ["crystal","crystal_display","orb","sculpture","infinity","metatron","fountain","pedestal"]:
		result=[_part(Vector3(0,s.y*.04,0),Vector3(s.x,s.y*.08,s.z)),_part(Vector3(0,s.y*.25,0),Vector3(s.x*.4,s.y*.42,s.z*.4))]
		if kind=="pedestal":
			result[1]=_part(Vector3(0,s.y*.5,0),Vector3(s.x*.4,s.y*.84,s.z*.4))
			result.append(_part(Vector3(0,s.y*.96,0),Vector3(s.x,s.y*.08,s.z),true))
		elif kind=="fountain": result.append(_part(Vector3(0,s.y*.5,0),Vector3(s.x,s.y*.1,s.z),true))
	else: result=[_part(Vector3(0,s.y*.5,0),s),_part(Vector3(0,s.y*.84,0),Vector3(s.x,s.y*.08,s.z),true)]
	return result

static func _line(batch: Node3D,a: Vector3,b: Vector3,ink: Color) -> void: batch.line(a,b,ink)

static func _details(batch: Node3D,properties: Dictionary,s: Vector3,ink: Color) -> void:
	var kind:=String(properties.get("furniture_kind",""))
	if kind=="sculpture":
		var top:=Vector3(0,s.y,0)
		for i in range(3):
			var a:=Vector3(cos(i*TAU/3)*s.x*.4,s.y*.52,sin(i*TAU/3)*s.z*.4)
			var b:=Vector3(cos((i+1)*TAU/3)*s.x*.4,s.y*.52,sin((i+1)*TAU/3)*s.z*.4)
			_line(batch,a,b,ink); _line(batch,a,top,ink)
	elif kind in ["crystal","crystal_display","fountain"]:
		var center:=Vector3(0,s.y*.74,0)
		var points: Array[Vector3]=[center+Vector3(0,s.y*.26,0),center-Vector3(0,s.y*.22,0),center+Vector3(s.x*.32,0,0),center-Vector3(s.x*.32,0,0),center+Vector3(0,0,s.z*.32),center-Vector3(0,0,s.z*.32)]
		for pole in [0,1]:
			for side in range(2,6): _line(batch,points[pole],points[side],ink)
	elif kind=="infinity":
		for i in range(48):
			var a:=float(i)*TAU/48; var b:=float(i+1)*TAU/48
			_line(batch,Vector3(sin(a)*s.x*.44,s.y*(.7+sin(2*a)*.22),0),Vector3(sin(b)*s.x*.44,s.y*(.7+sin(2*b)*.22),0),ink)
	elif kind=="metatron":
		var centers: Array[Vector3]=[Vector3(0,s.y*.72,0)]
		for i in range(6): centers.append(centers[0]+Vector3(cos(i*TAU/6),sin(i*TAU/6),0)*minf(s.x,s.y)*.3)
		for i in range(centers.size()):
			for j in range(i+1,centers.size()): _line(batch,centers[i],centers[j],ink)
			for segment in range(12):
				var a:=float(segment)*TAU/12; var b:=float(segment+1)*TAU/12
				_line(batch,centers[i]+Vector3(cos(a),sin(a),0)*s.x*.09,centers[i]+Vector3(cos(b),sin(b),0)*s.x*.09,ink)
	elif kind in ["orb","clock","round_table"]:
		var rings:=3 if kind=="orb" else 1
		for ring in range(rings):
			var radius:=minf(s.x,s.z)*.44 if kind=="round_table" else minf(s.x,s.y)*.36
			var center:=Vector3(0,s.y*(1.01 if kind=="round_table" else .7 if kind!="clock" else .5),s.z*.52 if kind=="clock" else 0)
			for i in range(24):
				var a:=float(i)*TAU/24; var b:=float(i+1)*TAU/24
				var first:=Vector3(cos(a),0,sin(a)) if kind=="round_table" or ring==1 else Vector3(0,cos(a),sin(a)) if ring==2 else Vector3(cos(a),sin(a),0)
				var second:=Vector3(cos(b),0,sin(b)) if kind=="round_table" or ring==1 else Vector3(0,cos(b),sin(b)) if ring==2 else Vector3(cos(b),sin(b),0)
				_line(batch,center+first*radius,center+second*radius,ink)
		if kind=="clock": _line(batch,Vector3(0,s.y*.5,s.z*.54),Vector3(s.x*.2,s.y*.68,s.z*.54),ink)
	elif kind=="aquarium":
		for i in range(3):
			var c:=Vector3(s.x*(-.27+i*.26),s.y*(.55+i%2*.15),s.z*.51)
			_line(batch,c-Vector3(s.x*.09,0,0),c+Vector3(s.x*.06,s.y*.06,0),ink)
			_line(batch,c+Vector3(s.x*.06,s.y*.06,0),c+Vector3(s.x*.06,-s.y*.06,0),ink)
			_line(batch,c+Vector3(s.x*.06,-s.y*.06,0),c-Vector3(s.x*.09,0,0),ink)
	elif kind in ["painting","math_art","banner","contract_board","emblem","terminal","security","guild_terminal","trade_terminal","lighting_control","archive","storage_terminal"]:
		var center:=Vector3(0,s.y*(.76 if "terminal" in kind or kind=="security" else .5),s.z*.54)
		var radius:=minf(s.x,s.y)*.22
		if kind=="math_art":
			var points: Array[Vector3]=[Vector3(radius,radius,0),Vector3(-radius,radius,0),Vector3(0,0,0),Vector3(-radius,-radius,0),Vector3(radius,-radius,0)]
			for i in range(points.size()-1): _line(batch,center+points[i],center+points[i+1],ink)
			return
		if kind=="painting":
			for i in range(24):
				var a: float=-.4+i/30.0; var b: float=-.4+(i+1)/30.0
				_line(batch,center+Vector3(a*s.x,sin(a*TAU*2)*s.y*.26,0),center+Vector3(b*s.x,sin(b*TAU*2)*s.y*.26,0),ink)
			return
		if kind=="banner":
			for i in range(3):
				var at:=center+Vector3(0,s.y*(i-1)*.2,0)
				_line(batch,at-Vector3(radius,0,0),at-Vector3(0,radius*.6,0),ink)
				_line(batch,at-Vector3(0,radius*.6,0),at+Vector3(radius,0,0),ink)
			return
		if kind=="contract_board" or kind=="lighting_control":
			for i in range(3):
				var at:=center+Vector3((i-1)*s.x*.26,0,0)
				_line(batch,at-Vector3(0,s.y*.3,0),at+Vector3(0,s.y*.3,0),ink)
				_line(batch,at+Vector3(-s.x*.08,s.y*(i-1)*.12,0),at+Vector3(s.x*.08,s.y*(i-1)*.12,0),ink)
			return
		for i in range(4):
			var a:=float(i)*TAU/4; var b:=float(i+1)*TAU/4
			_line(batch,center+Vector3(cos(a)*radius,sin(a)*radius,0),center+Vector3(cos(b)*radius,sin(b)*radius,0),ink)
		_line(batch,center+Vector3(-radius,0,0),center+Vector3(radius,0,0),ink)
	elif kind=="rug":
		for i in range(5):
			var x: float=s.x*(-.4+i*.2)
			_line(batch,Vector3(x,s.y+.003,-s.z*.4),Vector3(-x,s.y+.003,s.z*.4),ink)

static func model(properties: Dictionary,with_collision: bool = false) -> Node3D:
	var batch:=Chunk.new()
	batch.name="CivicItemModel"
	var ink:=Color(String(properties.get("tint","75eaff")))
	for part: Dictionary in boxes(properties): batch.box(part.position,part.size,"FurniturePart",ink if not part.accent else ink.lightened(.35),Basis.IDENTITY,with_collision)
	_details(batch,properties,size_of(properties),ink)
	if not with_collision: batch.body.free()
	batch.commit()
	return batch

static func for_id(type: StringName,with_collision: bool = false) -> Node3D:
	var definition: Resource=Catalog.get_definition(type)
	return model(definition.custom_properties,with_collision) if definition!=null else Node3D.new()
