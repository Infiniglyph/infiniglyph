extends Node3D
## A deterministic continuous region: dense city, housing, then rural terrain.
## Static chunk geometry/collision stays loaded; only lights fade with distance.
const Chunk = preload("res://scripts/world_chunk.gd")
const Gate = preload("res://scripts/outward_gate.gd")
const Neon = preload("res://scripts/neon.gd")
const HALF_EXTENT := 1152
const CHUNK_SIZE := 256
const TERRAIN_STEP := 16
const CITY_EDGE := 448
const SUBURB_EDGE := 704
const CYAN := Color(0.025,0.74,0.85)
const MINT := Color(0.06,0.58,0.40)
const GRID := Color(0.012,0.12,0.15)
var encounter: Node
var chunks: Dictionary = {}
var gates: Array[Node3D] = []
var lights: Array[SpotLight3D] = []
var buildings: Array[Dictionary] = []
var destinations: Array[Dictionary] = []
var counts := {"city":0,"homes":0,"farms":0,"trees":0,"rocks":0}
var build_ms := 0

static func code(x: int, z: int, salt: int = 0) -> int:
	# No shared/global RNG state: changing the map cannot reroll NPC identities.
	return absi((x*73856093) ^ (z*19349663) ^ ((salt+71)*83492791))

static func road_distance(value: float) -> float:
	return minf(absf(value),minf(absf(absf(value)-512),absf(absf(value)-1024)))

static func base_height(x: float, z: float) -> float:
	var radius := maxf(absf(x),absf(z))
	if radius<=SUBURB_EDGE: return 0.0
	var blend := smoothstep(SUBURB_EDGE,1000,radius)
	var distance := minf(road_distance(x),road_distance(z))
	var road := lerpf(smoothstep(24,80,distance),1.0,smoothstep(1060,1120,radius))
	var hills := (18+sin(x/143)*cos(z/173)*12+sin((x+z)/91)*5)*blend*road
	hills += smoothstep(1030,HALF_EXTENT,radius)*58*road
	var ravine := (1-smoothstep(10,32,absf(z+864)))*6
	return hills-ravine

static func vertex_height(x: float, z: float) -> float:
	var height := base_height(x,z)
	var px := floori(x/64)*64+32
	var pz := floori(z/64)*64+32
	var radius := maxi(absi(px),absi(pz))
	if radius<=SUBURB_EDGE or radius>1060 or absi(pz+864)<48: return height
	if minf(road_distance(px),road_distance(pz))<18: return height
	if code(floori(float(px)/64),floori(float(pz)/64))%19 != 0: return height
	# Flat farm plots are part of the actual terrain, not tall pillars placed
	# across a slope. Blend the pad back into the surrounding hillside.
	var blend := 1-smoothstep(24,32,maxf(absf(x-px),absf(z-pz)))
	return lerpf(height,base_height(px,pz),blend)

static func height_at(x: float, z: float) -> float:
	# Match the terrain's two triangles exactly, including between grid vertices.
	# Props, inlays and foundations consequently meet the visible solid ground.
	var gx := floorf(x/TERRAIN_STEP)*TERRAIN_STEP
	var gz := floorf(z/TERRAIN_STEP)*TERRAIN_STEP
	var u := (x-gx)/TERRAIN_STEP
	var v := (z-gz)/TERRAIN_STEP
	var a := vertex_height(gx,gz)
	if is_zero_approx(u) and is_zero_approx(v): return a
	var b := vertex_height(gx+TERRAIN_STEP,gz)
	var c := vertex_height(gx,gz+TERRAIN_STEP)
	if u+v<=1: return a+(b-a)*u+(c-a)*v
	var d := vertex_height(gx+TERRAIN_STEP,gz+TERRAIN_STEP)
	return d+(c-d)*(1-u)+(b-d)*(1-v)

static func surface_at(x: float, z: float) -> float:
	for bridge_x in [-512,0,512]:
		if absf(x-bridge_x)<=6.0 and z>=-896 and z<=-832: return 0.15
	return height_at(x,z)

static func region_at(point: Vector3) -> String:
	var radius := maxf(absf(point.x),absf(point.z))
	if radius<=112: return "Central District"
	if radius<CITY_EDGE: return "Outer City"
	if radius<SUBURB_EDGE: return "Suburbs"
	return "Countryside"

func chunk_at(point: Vector3) -> Node3D:
	var key := Vector2i(floori((point.x+128)/CHUNK_SIZE),floori((point.z+128)/CHUNK_SIZE))
	return chunks.get(key)

func _ready() -> void:
	name = "WiderWorld"
	var started := Time.get_ticks_msec()
	for x in range(-4,5):
		for z in range(-4,5):
			var chunk := Chunk.new()
			chunk.name = "Region_%d_%d" % [x,z]
			chunk.position = Vector3(x*CHUNK_SIZE-128,0,z*CHUNK_SIZE-128)
			add_child(chunk)
			chunks[Vector2i(x,z)] = chunk
			build_terrain(chunk)
			build_roads(chunk)
			for dx in range(32,CHUNK_SIZE,64):
				for dz in range(32,CHUNK_SIZE,64):
					var at := chunk.position+Vector3(dx,0,dz)
					var radius := maxf(absf(at.x),absf(at.z))
					if radius<128: continue # Preserve the complete original hub.
					var seed := code(floori(at.x/64),floori(at.z/64))
					if radius<CITY_EDGE: build_city(chunk,at,seed)
					elif radius<SUBURB_EDGE: build_suburb(chunk,at,seed)
					else: build_country(chunk,at,seed)
	build_bridges()
	build_destinations()
	for chunk: Node3D in chunks.values(): chunk.commit()
	build_gates()
	build_ms = Time.get_ticks_msec()-started

func build_terrain(chunk: Node3D) -> void:
	var collision := PackedVector3Array()
	for x in range(int(chunk.position.x),int(chunk.position.x)+CHUNK_SIZE,TERRAIN_STEP):
		for z in range(int(chunk.position.z),int(chunk.position.z)+CHUNK_SIZE,TERRAIN_STEP):
			if absf(x+8)<112 and absf(z+8)<112: continue
			var a := Vector3(x,height_at(x,z),z)
			var b := Vector3(x+16,height_at(x+16,z),z)
			var c := Vector3(x,height_at(x,z+16),z+16)
			var d := Vector3(x+16,height_at(x+16,z+16),z+16)
			for tri: Array in [[a,b,c],[b,d,c]]:
				var normal: Vector3 = (tri[2]-tri[0]).cross(tri[1]-tri[0]).normalized()
				chunk.triangle(tri[0],tri[1],tri[2],normal)
				for point: Vector3 in tri: collision.append(point-chunk.position)
			var color := GRID if maxf(absf(x),absf(z))<SUBURB_EDGE else MINT*0.40
			chunk.line(a+Vector3.UP*0.014,b+Vector3.UP*0.014,color)
			chunk.line(a+Vector3.UP*0.014,c+Vector3.UP*0.014,color)
			if maxf(absf(x),absf(z))>=SUBURB_EDGE: chunk.line(b+Vector3.UP*0.014,c+Vector3.UP*0.014,color*0.65)
	# Visible physical cliffs finish the finite region instead of a paper edge.
	for axis: int in [0,2]:
		for side in [-1,1]:
			var fixed := float(side*HALF_EXTENT)
			var at_edge := chunk.position[axis] == fixed or chunk.position[axis]+CHUNK_SIZE == fixed
			if not at_edge: continue
			var other := 2-axis
			for along in range(int(chunk.position[other]),int(chunk.position[other])+CHUNK_SIZE,16):
				var a := Vector3.ZERO
				a[axis] = fixed
				a[other] = along
				a.y = height_at(a.x,a.z)
				var b := a
				b[other] += 16
				b.y = height_at(b.x,b.z)
				for tri: Array in [[a,b,Vector3(a.x,-20,a.z)],[b,Vector3(b.x,-20,b.z),Vector3(a.x,-20,a.z)]]:
					chunk.triangle(tri[0],tri[1],tri[2],Vector3.UP)
					for point: Vector3 in tri: collision.append(point-chunk.position)
	chunk.terrain(collision)

func build_roads(chunk: Node3D) -> void:
	for axis: int in [0,2]:
		var other := 2-axis
		for offset in range(0,CHUNK_SIZE,64):
			var fixed: float = chunk.position[axis]+offset
			for step in range(CHUNK_SIZE/8):
				var a := chunk.position
				a[axis] = fixed
				a[other] += step*8
				var radius := maxf(absf(a.x),absf(a.z))
				if radius<112 or radius>1088: continue
				if radius>=SUBURB_EDGE and road_distance(fixed)>0.01: continue
				for side in [-1,1]:
					var start := a
					start[axis] += side*(8 if radius<CITY_EDGE else 6)
					var end := start
					end[other] += 8
					start.y = surface_at(start.x,start.z)+0.022
					end.y = surface_at(end.x,end.z)+0.022
					chunk.line(start,end,CYAN*0.65 if radius<SUBURB_EDGE else MINT)
				if step%2 == 0:
					var end := a
					end[other] += 3
					a.y = surface_at(a.x,a.z)+0.025
					end.y = surface_at(end.x,end.z)+0.025
					chunk.line(a,end,CYAN*0.7)

func build_city(chunk: Node3D, at: Vector3, seed: int) -> void:
	if seed%11 == 0:
		park(chunk,at,seed)
		return
	var radius := maxf(absf(at.x),absf(at.z))
	var height := float(20+(seed%17)*4)*lerpf(1.0,0.55,smoothstep(280,CITY_EDGE,radius))
	if seed%3 == 0:
		urban_building(chunk,at+Vector3(-12,0,0),Vector3(17,height,32))
		urban_building(chunk,at+Vector3(12,0,3),Vector3(16,height*0.65,26))
	else:
		urban_building(chunk,at,Vector3(30,height,32))
	if seed%4 == 0: lamp(chunk,at+Vector3(-24,0,-24),false)

func urban_building(chunk: Node3D, at: Vector3, size: Vector3) -> void:
	chunk.box(at+Vector3.UP*size.y*0.5,size,"UrbanBuilding",CYAN)
	chunk.box(at+Vector3.UP*(size.y+1),Vector3(size.x*0.72,2,size.z*0.72),"UrbanCrown",CYAN)
	buildings.append({"point":at,"size":size,"region":"city"})
	counts.city += 1
	var x := size.x*0.5+0.012
	var z := size.z*0.5+0.012
	for y in range(4,int(size.y),4):
		for side in [-1,1]:
			chunk.line(at+Vector3(-x,y,side*z),at+Vector3(x,y,side*z),CYAN*0.72)
			chunk.line(at+Vector3(side*x,y,-z),at+Vector3(side*x,y,z),CYAN*0.72)
	for side in [-1,1]:
		chunk.line(at+Vector3(0,0,side*z),at+Vector3(0,size.y,side*z),CYAN*0.6)

func build_suburb(chunk: Node3D, at: Vector3, seed: int) -> void:
	if seed%7 == 0:
		park(chunk,at,seed)
		return
	house(chunk,at+Vector3(-12,0,-5),seed,false)
	if seed%3 == 0: house(chunk,at+Vector3(13,0,7),seed+3,false)
	else: tree(chunk,at+Vector3(16,0,10),seed)
	# Rear fences leave streets, front gardens and driveways open.
	chunk.box(at+Vector3(0,0.65,-25),Vector3(46,1.3,0.10),"GardenFence",CYAN*0.7)
	if seed%4 == 0: lamp(chunk,at+Vector3(24,0,24),true)

func house(chunk: Node3D, at: Vector3, seed: int, rural: bool) -> void:
	var width := 14.0 if rural else 12.0
	var depth := 18.0 if rural else 12.0
	var height := 6.0 if rural else (4.5 if seed%2 == 0 else 6.5)
	var floor_y := 0.0
	var lowest := INF
	for x in [-width*0.5,width*0.5]:
		for z in [-depth*0.5,depth*0.5]:
			var ground := height_at(at.x+x,at.z+z)
			floor_y = maxf(floor_y,ground)
			lowest = minf(lowest,ground)
	at.y = floor_y+0.10
	if rural:
		chunk.box(Vector3(at.x,(at.y+lowest-0.4)*0.5,at.z),Vector3(width+2,at.y-lowest+0.4,depth+2),"FarmFoundation",MINT)
	chunk.box(at+Vector3.UP*height*0.5,Vector3(width,height,depth),"FarmBuilding" if rural else "Home",MINT if rural else CYAN)
	var roof := PackedVector3Array([Vector3(-width*0.55,0,-depth*0.55),Vector3(width*0.55,0,-depth*0.55),Vector3(0,2.8,-depth*0.55),Vector3(-width*0.55,0,depth*0.55),Vector3(width*0.55,0,depth*0.55),Vector3(0,2.8,depth*0.55)])
	chunk.convex(roof,[[0,2,1],[3,4,5],[0,1,4,3],[0,3,5,2],[1,2,5,4]],at+Vector3.UP*height,"GabledRoof",MINT if rural else CYAN)
	chunk.box(at+Vector3(0,0.1,depth*0.5+1.1),Vector3(4,0.2,2.2),"Porch",CYAN)
	# Flush windows and doors are facade inlays, not pretend open interiors.
	for x in [-3.5,3.5]:
		var a := at+Vector3(x-0.9,1.7,depth*0.5+0.015)
		var b := a+Vector3(1.8,1.5,0)
		chunk.line(a,Vector3(b.x,a.y,a.z),CYAN)
		chunk.line(a,Vector3(a.x,b.y,a.z),CYAN)
		chunk.line(b,Vector3(b.x,a.y,a.z),CYAN)
		chunk.line(b,Vector3(a.x,b.y,a.z),CYAN)
	buildings.append({"point":at,"size":Vector3(width,height+2.8,depth),"region":"farm" if rural else "home"})
	counts["farms" if rural else "homes"] += 1

func build_country(chunk: Node3D, at: Vector3, seed: int) -> void:
	if maxf(absf(at.x),absf(at.z))>1060 or absf(at.z+864)<48: return
	if minf(road_distance(at.x),road_distance(at.z))<18: return
	if seed%19 == 0:
		house(chunk,at,seed,true)
		for side in [-1,1]:
			for row in range(7):
				var a := at+Vector3(side*12,0,row*3-9)
				var b := a+Vector3(side*12,0,0)
				a.y = height_at(a.x,a.z)+0.03
				b.y = height_at(b.x,b.z)+0.03
				chunk.line(a,b,MINT*0.6)
	elif seed%5 == 0:
		for offset: Vector3 in [Vector3(-9,0,-8),Vector3(7,0,8),Vector3(-12,0,12)]: tree(chunk,at+offset,seed+int(offset.x))
	elif seed%13 == 0: rock(chunk,at,seed)

func tree(chunk: Node3D, at: Vector3, seed: int) -> void:
	at.y = height_at(at.x,at.z)
	var height := 5.0+float(seed%4)
	chunk.box(at+Vector3.UP*height*0.35,Vector3(0.4,height*0.7,0.4),"TreeTrunk",MINT)
	var width := 2.0+float(seed%3)*0.4
	var crown := PackedVector3Array([Vector3(0,height*0.35,0),Vector3(0,height,0),Vector3(-width,height*0.68,0),Vector3(width,height*0.68,0),Vector3(0,height*0.68,-width),Vector3(0,height*0.68,width)])
	chunk.convex(crown,[[0,2,4],[0,4,3],[0,3,5],[0,5,2],[1,4,2],[1,3,4],[1,5,3],[1,2,5]],at,"TreeCrown",MINT)
	counts.trees += 1

func rock(chunk: Node3D, at: Vector3, seed: int) -> void:
	at.y = height_at(at.x,at.z)
	var width := 3.0+seed%4
	chunk.convex(PackedVector3Array([Vector3(-width,-1,-width),Vector3(width,-1,-width),Vector3(width,-1,width),Vector3(-width,-1,width),Vector3(-1,width*0.9,0),Vector3(width*0.5,width*0.65,1)]),[[0,3,2,1],[0,1,4],[1,5,4],[1,2,5],[2,3,5],[3,4,5],[3,0,4]],at,"Outcrop",MINT*0.8)
	counts.rocks += 1

func park(chunk: Node3D, at: Vector3, seed: int) -> void:
	for offset: Vector3 in [Vector3(-14,0,-12),Vector3(14,0,12),Vector3(14,0,-12)]: tree(chunk,at+offset,seed)
	for side in [-1,1]:
		chunk.box(at+Vector3(side*9,0.55,0),Vector3(1,0.15,3),"ParkSeat",CYAN)
		chunk.box(at+Vector3(side*9,0.25,0),Vector3(0.4,0.5,2),"ParkSeatSupport",CYAN)

func lamp(chunk: Node3D, at: Vector3, small: bool) -> void:
	at.y = surface_at(at.x,at.z)
	var height := 4.5 if small else 7.0
	chunk.box(at+Vector3.UP*height*0.5,Vector3(0.16,height,0.16),"WorkingLampPost",Neon.ORANGE)
	chunk.box(at+Vector3(0,height,0.8),Vector3(0.8,0.22,1.9),"WorkingLuminaire",Neon.ORANGE)
	var light := SpotLight3D.new()
	light.name = "ExpansionOrangeLight"
	light.position = at+Vector3(0,height-0.15,0.8)
	light.rotation.x = -PI*0.5
	light.light_color = Neon.ORANGE
	light.light_energy = 5
	light.spot_range = 10
	light.spot_angle = 52
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 32
	light.distance_fade_length = 20
	add_child(light)
	lights.append(light)

func build_bridges() -> void:
	for x in [-512,0,512]:
		var chunk: Node3D = chunk_at(Vector3(x,0,-864))
		chunk.box(Vector3(x,-0.45,-864),Vector3(12,1.2,64),"CountryBridgeDeck",CYAN)
		for side in [-1,1]:
			chunk.box(Vector3(x+side*5.8,1.2,-864),Vector3(0.12,0.12,64),"BridgeRail",CYAN)
			for z in range(-894,-832,8):
				chunk.box(Vector3(x+side*5.8,0.65,z),Vector3(0.12,1.1,0.12),"BridgeBaluster",CYAN)
			for z in [-880,-848]:
				chunk.box(Vector3(x+side*4,-3,z),Vector3(0.7,5.4,0.7),"BridgePier",CYAN)
		lamp(chunk,Vector3(x+7,0,-828),false)
		lamp(chunk,Vector3(x-7,0,-900),false)
		destinations.append({"name":"Country Viaduct","point":Vector3(x,0.15,-864)})

func sign_at(at: Vector3, text: String) -> void:
	var chunk: Node3D = chunk_at(at)
	at.y = surface_at(at.x,at.z)
	chunk.box(at+Vector3.UP*1.7,Vector3(0.16,3.4,0.16),"RoadSignPost",CYAN)
	chunk.box(at+Vector3(0,3.3,0),Vector3(5.5,1.1,0.12),"RoadSign",CYAN)
	var label := Label3D.new()
	label.text = text
	label.position = at+Vector3(0,3.3,0.07)
	label.font_size = 34
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func build_destinations() -> void:
	for spec in [[Vector3(12,0,-136),"OUTER CITY"],[Vector3(12,0,-464),"RESIDENTIAL QUARTERS"],[Vector3(12,0,-720),"COUNTRY ROAD"],[Vector3(12,0,-928),"COUNTRY LOOKOUT  /  NORTH"]]: sign_at(spec[0],spec[1])
	for point: Vector3 in [Vector3(0,0,-256),Vector3(0,0,-576),Vector3(0,0,-768),Vector3(0,0,-1008)]:
		destinations.append({"name":region_at(point),"point":point})
	var at := Vector3(0,0,-1048)
	var chunk: Node3D = chunk_at(at)
	chunk.box(at+Vector3.UP*0.05,Vector3(30,0.1,20),"CountryLookout",CYAN)
	for side in [-1,1]:
		chunk.box(at+Vector3(side*14,0.7,0),Vector3(0.12,1.4,20),"LookoutRail",CYAN)
	chunk.box(at+Vector3(0,0.7,-10),Vector3(28,1.4,0.12),"LookoutRail",CYAN)
	sign_at(Vector3(20,0,-1040),"COUNTRY LOOKOUT")
	destinations.append({"name":"Country Lookout","point":at+Vector3.UP*0.1})

func build_gates() -> void:
	for spec in [[Vector3(0,0,-112),0.0],[Vector3(0,0,112),PI],[Vector3(112,0,16),PI*0.5],[Vector3(-112,0,16),-PI*0.5]]:
		var gate := Gate.new()
		gate.encounter = encounter
		gate.position = spec[0]
		gate.rotation.y = spec[1]
		add_child(gate)
		gates.append(gate)
