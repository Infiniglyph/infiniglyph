extends Node3D
## Public, seamless city interiors. Interactions and ownership live elsewhere.
const Chunk = preload("res://scripts/world_chunk.gd")
const Neon = preload("res://scripts/neon.gd")
const WindowLights = preload("res://scripts/window_lights.gd")
const GUILD_CENTER := Vector3(-32,0,-160)
const TAVERN_CENTER := Vector3(-16,0,-224)
const GUILD_SIZE := Vector3(40,9.8,34)
const TAVERN_SIZE := Vector3(16,5.2,26)
const GROUND := .12
const UPPER := 4.72
const CYAN := Color(.035,.83,1)
const BLUE := Color(.18,.38,1)
const VIOLET := Color(.72,.20,1)
const GOLD := Color(1,.64,.12)
var guild: Node3D
var tavern: Node3D
var points: Array[Dictionary] = []
var seats: Array[Dictionary] = []
var room_exit: Array[Marker3D] = []
var room_arrivals: Array[Marker3D] = []
var stair_route: Array[Vector3] = []
var guild_entry: Marker3D
var tavern_entry: Marker3D
var receptionist_anchor: Marker3D
var bartender_anchor: Marker3D

static func reserves_plot(at: Vector3) -> bool:
	# Replace entire generated scenery lots; never place an interior inside an
	# existing opaque skyscraper or leave its original collision behind.
	for center: Vector3 in [Vector3(-32,0,-160),Vector3(-32,0,-224)]:
		if absf(at.x-center.x)<32 and absf(at.z-center.z)<32: return true
	return false

func _ready() -> void:
	name = "CivilianEstablishments"
	guild = Node3D.new()
	guild.name = "AdventurersGuild"
	guild.position = GUILD_CENTER
	add_child(guild)
	build_guild()
	tavern = Node3D.new()
	tavern.name = "Tavern"
	tavern.position = TAVERN_CENTER
	add_child(tavern)
	build_tavern()
	for seat: Dictionary in seats: seat.world = get_world_3d()

static func marker(parent: Node3D, title: String, at: Vector3) -> Marker3D:
	var anchor := Marker3D.new()
	anchor.name = title
	anchor.position = at
	parent.add_child(anchor)
	return anchor

func point(parent: Node3D, id: StringName, kind: StringName, label: String, at: Vector3) -> Marker3D:
	var anchor := marker(parent,String(id),at)
	points.append({"id":id,"kind":kind,"label":label,"anchor":anchor})
	return anchor

static func inscription(parent: Node3D, text: String, at: Vector3, size: int = 48, color: Color = CYAN, yaw: float = 0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.rotation.y = yaw
	label.font_size = size
	label.pixel_size = .008
	label.modulate = color
	label.outline_modulate = Color.BLACK
	label.no_depth_test = false
	parent.add_child(label)
	return label

static func table(batch: Node3D, at: Vector3, color: Color = CYAN, size: Vector2 = Vector2(2.4,1.7)) -> void:
	batch.box(at+Vector3(0,.82,0),Vector3(size.x,.12,size.y),"TableTop",color)
	for x in [-1,1]:
		for z in [-1,1]: batch.box(at+Vector3(x*(size.x*.5-.18),.38,z*(size.y*.5-.18)),Vector3(.12,.76,.12),"TableLeg",color)

static func chair(batch: Node3D, at: Vector3, forward: Vector3, color: Color = CYAN, stool: bool = false) -> void:
	var basis := Basis.looking_at(forward,Vector3.UP)
	batch.box(at+Vector3.UP*.48,Vector3(.68,.12,.68),"ChairSeat",color,basis)
	for x in [-1,1]:
		for z in [-1,1]: batch.box(at+basis*Vector3(x*.25,.22,z*.25),Vector3(.07,.44,.07),"ChairLeg",color,basis)
	if not stool:
		batch.box(at+basis*Vector3(0,.91,.30),Vector3(.68,.78,.10),"ChairBack",color,basis)

func seat(parent: Node3D, batch: Node3D, id: StringName, at: Vector3, forward: Vector3, color: Color = CYAN, stool: bool = false) -> void:
	chair(batch,at,forward,color,stool)
	var anchor := point(parent,id,&"chair","Sit",at+Vector3.UP*.56)
	seats.append({"id":id,"point":parent.to_global(at+Vector3.UP*.56),"forward":parent.global_basis*forward,"occupant":null,"anchor":anchor})

func table_group(parent: Node3D, batch: Node3D, id: String, at: Vector3, color: Color = CYAN) -> void:
	table(batch,at,color)
	point(parent,StringName(id),&"table","Common table",at+Vector3.UP*.95)
	for side: int in [-1,1]: seat(parent,batch,StringName(id+"_chair_"+str(side)),at+Vector3(0,0,side*1.65),Vector3(0,0,-side),color)

static func front(batch: Node3D, half_width: float, z: float, height: float, bottom: float = GROUND, door_width: float = 4.8) -> void:
	var side_width := half_width-door_width*.5
	for side in [-1,1]: batch.box(Vector3(side*(door_width*.5+side_width*.5),bottom+height*.5,z),Vector3(side_width,height,.24),"FrontWall",CYAN)
	batch.box(Vector3(0,bottom+3.5+(height-3.5)*.5,z),Vector3(door_width,height-3.5,.24),"EntranceLintel",CYAN)
	for side in [-1,1]: batch.box(Vector3(side*(door_width*.5+.1),bottom+1.7,z+.2),Vector3(.12,3.4,.12),"DoorFrame",CYAN,Basis.IDENTITY,false)
	# Feather the foundation into the street instead of requiring step-up logic
	# or a jump at the twelve-centimetre threshold.
	var a := Vector3(0,0,z+2)
	var b := Vector3(0,bottom,z-.2)
	var side := Vector3.RIGHT*(door_width*.5)
	var drop := Vector3.DOWN*.16
	batch.convex(PackedVector3Array([a-side+drop,a+side+drop,b-side+drop,b+side+drop,a-side,a+side,b-side,b+side]),[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]],Vector3.ZERO,"PublicEntranceThreshold",CYAN)

static func windows(batch: Node3D, half_width: float, z: float, levels: Array[float]) -> void:
	var panes := WindowLights.new()
	batch.get_parent().add_child(panes)
	for y: float in levels:
		for side in [-1,1]:
			for i in range(3):
				var x: float = side*(half_width*.45+i*1.25)
				batch.box(Vector3(x,y,z+.14),Vector3(.65,.85,.035),"ColoredWindow",[CYAN,BLUE,VIOLET][(i+(1 if side>0 else 0))%3],Basis.IDENTITY,false)
				panes.pane(Vector3(x,y,z+.17),Vector3.RIGHT,Vector2(.55,.75),[CYAN,BLUE,VIOLET][(i+(1 if side>0 else 0))%3]*.65)
	panes.commit()

static func floor_grid(batch: Node3D, half_size: Vector2, y: float, pitch: float = 4) -> void:
	for x in range(ceili(-half_size.x/pitch),floori(half_size.x/pitch)+1): batch.line(Vector3(x*pitch,y,-half_size.y),Vector3(x*pitch,y,half_size.y),CYAN*.25)
	for z in range(ceili(-half_size.y/pitch),floori(half_size.y/pitch)+1): batch.line(Vector3(-half_size.x,y,z*pitch),Vector3(half_size.x,y,z*pitch),CYAN*.25)

func build_guild() -> void:
	var b := Chunk.new()
	b.name = "GuildBatch"
	guild.add_child(b)
	b.box(Vector3(0,GROUND-.12,0),Vector3(40,.24,34),"GuildGroundFloor",CYAN)
	floor_grid(b,Vector2(20,17),GROUND+.014)
	# Continuous slabs surround the open stairwell, with a full rear landing.
	b.box(Vector3(-5,UPPER-.12,0),Vector3(30,.24,34),"GuildUpperFloor",CYAN)
	b.box(Vector3(15,UPPER-.12,-13.5),Vector3(10,.24,7),"GuildUpperRearLanding",CYAN)
	b.box(Vector3(15,UPPER-.12,14.5),Vector3(10,.24,5),"GuildUpperFrontLanding",CYAN)
	b.box(Vector3(19,UPPER-.12,1),Vector3(2,.24,22),"GuildStairSideLanding",CYAN)
	# The upper gallery inlays stop at the stairwell's solid floor edges.
	for x in range(-16,10,4): b.line(Vector3(x,UPPER+.014,-17),Vector3(x,UPPER+.014,17),CYAN*.25)
	for z in range(-16,17,4): b.line(Vector3(-20,UPPER+.014,z),Vector3(10,UPPER+.014,z),CYAN*.25)
	b.box(Vector3(0,9.92,0),Vector3(40.5,.24,34.5),"GuildRoof",CYAN)
	b.box(Vector3(0,4.98,-17),Vector3(40,9.72,.24),"GuildRearWall",CYAN)
	for side in [-1,1]: b.box(Vector3(side*20,4.98,0),Vector3(.24,9.72,34),"GuildSideWall",CYAN)
	front(b,20,17,9.72)
	windows(b,20,17,[2.6,7.2])
	for y in [GROUND,UPPER,9.8]:
		b.line(Vector3(-20,y,17.15),Vector3(20,y,17.15),CYAN)
	# Single broad flight: shallow slope, flush endpoints, smooth full-body
	# ramp collision and visible treads. No tiny step risers to snag a capsule.
	var start := Vector3(14,GROUND,10)
	var end := Vector3(14,UPPER,-10)
	var side := Vector3.RIGHT*2
	var drop := Vector3.DOWN*.22
	b.convex(PackedVector3Array([start-side+drop,start+side+drop,end-side+drop,end+side+drop,start-side,start+side,end-side,end+side]),[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]],Vector3.ZERO,"GuildStairRamp",CYAN)
	for i in range(25):
		var tread := start.lerp(end,float(i)/24)+Vector3.UP*.012
		b.line(tread-side,tread+side,CYAN if i%4 else BLUE)
	for offset: float in [-2.1,2.1]: b.rail(start+Vector3.RIGHT*offset,end+Vector3.RIGHT*offset,1.05,"GuildStairRail",CYAN,.12)
	b.rail(Vector3(10,UPPER,-10),Vector3(10,UPPER,12),1.05,"GuildGalleryGuard",CYAN,.12)
	b.rail(Vector3(10,UPPER,12),Vector3(18,UPPER,12),1.05,"GuildGalleryEndGuard",CYAN,.12)
	stair_route = [guild.to_global(Vector3(14,GROUND,13)),guild.to_global(start),guild.to_global(end),guild.to_global(Vector3(14,UPPER,-13)),guild.to_global(Vector3(0,UPPER,-13))]
	# Reception and a separate, readable board leave the central entry clear.
	b.box(Vector3(-12,1.1,7),Vector3(8,1.95,1.8),"ReceptionCounter",CYAN)
	b.box(Vector3(-12,2.4,3.4),Vector3(7,1.8,.16),"GuildServicePanel",BLUE)
	inscription(guild,"RECEPTION  /  CRYSTAL EXCHANGE",Vector3(-12,2.4,3.51),24)
	point(guild,&"reception",&"reception","Guild receptionist",Vector3(-12,1.3,9.2))
	receptionist_anchor = marker(guild,"ReceptionistStanding",Vector3(-12,GROUND,4.9))
	b.box(Vector3(-18,2.05,-5.5),Vector3(.18,3.3,5),"ContractBoard",CYAN)
	for i in range(3): b.box(Vector3(-17.88,2.1,-7+i*1.5),Vector3(.035,1.9,.9),"ContractNotice",[CYAN,BLUE,GOLD][i],Basis.IDENTITY,false)
	point(guild,&"board",&"board","Contracts and bounties",Vector3(-16.8,1.5,-5.5))
	inscription(guild,"CONTRACTS",Vector3(-17.7,3.9,-5.5),28,CYAN,PI*.5)
	table_group(guild,b,"guild_table_1",Vector3(-8,GROUND,-7))
	table_group(guild,b,"guild_table_2",Vector3(0,GROUND,1),BLUE)
	table_group(guild,b,"guild_table_3",Vector3(-8,GROUND,-.5))
	for i in range(3):
		var x := -12.0+i*12
		var ink: Color = [CYAN,BLUE,VIOLET][i]
		b.box(Vector3(x,UPPER+1.6,-16.79),Vector3(3.2,3.2,.16),"RentalRoomDoor",ink)
		for edge in [-1,1]: b.line(Vector3(x+edge*1.65,UPPER,-16.66),Vector3(x+edge*1.65,UPPER+3.3,-16.66),ink)
		b.line(Vector3(x-1.65,UPPER+3.3,-16.66),Vector3(x+1.65,UPPER+3.3,-16.66),ink)
		var anchor := point(guild,StringName("room_"+str(i+1)),&"room","Private room "+str(i+1),Vector3(x,UPPER+1.2,-15.5))
		room_exit.append(anchor)
		room_arrivals.append(marker(guild,"RoomArrival"+str(i+1),Vector3(x,UPPER+.05,-13.4)))
		inscription(guild,"ROOM %02d" % (i+1),Vector3(x,UPPER+3.65,-16.6),32,ink)
	inscription(guild,"ADVENTURERS GUILD",Vector3(0,6.65,17.18),60).pixel_size = .022
	inscription(guild,"LODGING  /  UPSTAIRS",Vector3(14,3.3,11),25,BLUE)
	guild_entry = marker(guild,"GuildPublicEntrance",Vector3(0,GROUND+.05,19))
	b.commit()

func build_tavern() -> void:
	var b := Chunk.new()
	b.name = "TavernBatch"
	tavern.add_child(b)
	b.box(Vector3(0,GROUND-.12,0),Vector3(16,.24,26),"TavernGroundFloor",CYAN)
	floor_grid(b,Vector2(8,13),GROUND+.014,2)
	b.box(Vector3(0,5.3,0),Vector3(16.4,.24,26.4),"TavernRoof",CYAN)
	b.box(Vector3(0,2.65,-13),Vector3(16,5.06,.24),"TavernRearWall",CYAN)
	for side in [-1,1]: b.box(Vector3(side*8,2.65,0),Vector3(.24,5.06,26),"TavernSideWall",CYAN)
	front(b,8,13,5.06,GROUND,4.6)
	windows(b,8,13,[2.1])
	b.box(Vector3(0,1.12,-7),Vector3(11,2,1.3),"BarCounter",CYAN)
	for x in [-4,0,4]:
		b.box(Vector3(x,2.8,-12.6),Vector3(2.9,2.3,.5),"BarShelving",BLUE)
		for i in range(3):
			b.box(Vector3(x-1+i,2.35,-12.15),Vector3(.35,.65,.35),"ElectronContainer",[CYAN,VIOLET,GOLD][i],Basis.IDENTITY,false)
			b.line(Vector3(x-1.4,2.9,-12.25),Vector3(x+1.4,2.9,-12.25),CYAN)
	point(tavern,&"bartender",&"bartender","Electron meals and drinks",Vector3(0,1.35,-5.3))
	bartender_anchor = marker(tavern,"BartenderStanding",Vector3(0,GROUND,-9.2))
	for i in range(3): seat(tavern,b,StringName("bar_stool_"+str(i+1)),Vector3(-3+i*3,GROUND,-4),Vector3.FORWARD,BLUE,true)
	table_group(tavern,b,"tavern_table_1",Vector3(-3.6,GROUND,4.5))
	table_group(tavern,b,"tavern_table_2",Vector3(3.6,GROUND,.5),VIOLET)
	inscription(tavern,"THE ELECTRON TAVERN",Vector3(0,4.45,13.18),39).pixel_size = .016
	inscription(tavern,"ELECTRON MEALS  /  DRINKS",Vector3(0,4.3,-12.45),25,BLUE)
	tavern_entry = marker(tavern,"TavernPublicEntrance",Vector3(0,GROUND+.05,15))
	b.commit()
