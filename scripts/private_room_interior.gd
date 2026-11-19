extends Node3D
## Rendered instance only; rental identity, storage and furniture state persist
## in the establishment authority independently of this disposable geometry.
const Chunk = preload("res://scripts/world_chunk.gd")
const Furnish = preload("res://scripts/civilian_establishments.gd")
const SIZE := Vector3(18,4.5,14)
const FLOOR := .12
static var _layout: Array[Dictionary] = []
var spawn_anchor: Marker3D
var exit_anchor: Marker3D
var points: Array[Dictionary] = []
var seats: Array[Dictionary] = []
var structure: Node3D

static func _box(at: Vector3, size: Vector3, kind: String, color: Color, basis: Basis = Basis.IDENTITY) -> Dictionary:
	return {"at":at,"size":size,"kind":kind,"color":color,"basis":basis}

static func _table_boxes(at: Vector3, size: Vector2, color: Color) -> Array[Dictionary]:
	var result: Array[Dictionary] = [_box(at+Vector3(0,.82,0),Vector3(size.x,.12,size.y),"TableTop",color)]
	for x in [-1,1]:
		for z in [-1,1]: result.append(_box(at+Vector3(x*(size.x*.5-.18),.38,z*(size.y*.5-.18)),Vector3(.12,.76,.12),"TableLeg",color))
	return result

static func collision_layout() -> Array[Dictionary]:
	# One recipe drives both rendered geometry and cheap dormant support. A
	# dropped item on a mattress, desk or chair must see the same surface after
	# geometry unloads and when a checkpoint is validated during a cold load.
	if not _layout.is_empty(): return _layout
	_layout = [
		_box(Vector3.ZERO,Vector3(18,.24,14),"PrivateRoomFloor",Furnish.CYAN),
		_box(Vector3(0,4.62,0),Vector3(18,.24,14),"PrivateRoomCeiling",Furnish.CYAN),
		_box(Vector3(-9,2.37,0),Vector3(.22,4.5,14),"PrivateRoomSideWall",Furnish.CYAN),
		_box(Vector3(9,2.37,0),Vector3(.22,4.5,14),"PrivateRoomSideWall",Furnish.CYAN),
		_box(Vector3(0,2.37,-7),Vector3(18,4.5,.22),"PrivateRoomRearWall",Furnish.CYAN),
		_box(Vector3(0,2.37,7),Vector3(18,4.5,.22),"PrivateRoomFrontWall",Furnish.CYAN),
		_box(Vector3(0,1.62,6.84),Vector3(2.6,3,.12),"PrivateRoomExitDoor",Furnish.BLUE),
		_box(Vector3(-5.3,.43,-3.6),Vector3(3.3,.62,5.1),"BedFrame",Furnish.CYAN),
		_box(Vector3(-5.3,.84,-3.6),Vector3(3.1,.2,4.9),"BedSurface",Furnish.BLUE),
		_box(Vector3(-5.3,1.2,-6.15),Vector3(3.5,1.9,.18),"BedHeadboard",Furnish.CYAN),
		_box(Vector3(5.1,1.67,-5.35),Vector3(2.3,1.35,.15),"StorageComputer",Furnish.BLUE),
		_box(Vector3(7.3,.8,4.9),Vector3(1.1,1.36,1.1),"RoomPlanter",Furnish.BLUE)]
	_layout.append_array(_table_boxes(Vector3(5.1,FLOOR,-4.9),Vector2(4,1.7),Furnish.CYAN))
	_layout.append_array(_table_boxes(Vector3(-5,FLOOR,3),Vector2(2.7,1.7),Furnish.VIOLET))
	var at := Vector3(5.1,FLOOR,-2.5)
	var facing := Basis.looking_at(Vector3.FORWARD,Vector3.UP)
	_layout.append(_box(at+Vector3.UP*.48,Vector3(.68,.12,.68),"ChairSeat",Furnish.BLUE,facing))
	for x in [-1,1]:
		for z in [-1,1]: _layout.append(_box(at+facing*Vector3(x*.25,.22,z*.25),Vector3(.07,.44,.07),"ChairLeg",Furnish.BLUE,facing))
	_layout.append(_box(at+facing*Vector3(0,.91,.30),Vector3(.68,.78,.10),"ChairBack",Furnish.BLUE,facing))
	return _layout

static func create_support() -> StaticBody3D:
	# No meshes, labels, materials, lights or room interactions are allocated.
	var body := StaticBody3D.new()
	body.name = "PrivateRoomSupport"
	body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	for entry: Dictionary in collision_layout():
		if not Chunk.boxes.has(entry.size):
			var box := BoxShape3D.new()
			box.size = entry.size
			Chunk.boxes[entry.size] = box
		var shape := CollisionShape3D.new()
		shape.name = entry.kind
		shape.shape = Chunk.boxes[entry.size]
		shape.transform = Transform3D(entry.basis,entry.at)
		body.add_child(shape)
	return body

func point(id: StringName, kind: StringName, label: String, at: Vector3) -> Marker3D:
	var anchor := Furnish.marker(self,String(id),at)
	points.append({"id":id,"kind":kind,"label":label,"anchor":anchor})
	return anchor

func _ready() -> void:
	name = "PrivateRentalRoom"
	structure = Chunk.new()
	structure.name = "RoomBatch"
	add_child(structure)
	var b := structure
	for entry: Dictionary in collision_layout(): b.box(entry.at,entry.size,entry.kind,entry.color,entry.basis)
	Furnish.floor_grid(b,Vector2(9,7),FLOOR+.014,2)
	# The exit is a solid authorization door, while the public buildings' front
	# entrances are physically open. Its marker invokes normal phase travel.
	exit_anchor = point(&"room_exit",&"exit","Return to guild hallway",Vector3(0,1.25,5.5))
	spawn_anchor = Furnish.marker(self,"RoomSafeArrival",Vector3(0,FLOOR+.05,4))
	spawn_anchor.rotation.y = PI
	# Low, broad bed, a clear central circulation lane, and a real workstation.
	b.box(Vector3(-5.3,.99,-5.2),Vector3(2.35,.12,.8),"BedPillow",Furnish.VIOLET,Basis.IDENTITY,false)
	point(&"bed",&"bed","Rest or sleep",Vector3(-3.2,1,-3.6))
	b.box(Vector3(5.1,1.66,-5.25),Vector3(2.04,1.1,.025),"ComputerDisplay",Furnish.CYAN,Basis.IDENTITY,false)
	var screen := Furnish.WindowLights.new()
	add_child(screen)
	screen.pane(Vector3(5.1,1.66,-5.23),Vector3.RIGHT,Vector2(2.04,1.1),Furnish.BLUE*.35)
	screen.commit()
	Furnish.inscription(self,"ROOM STORAGE",Vector3(5.1,1.67,-5.21),19,Furnish.CYAN)
	point(&"computer",&"storage","Room storage computer",Vector3(5.1,1.25,-3.3))
	var chair_at := Vector3(5.1,FLOOR,-2.5)
	var chair_anchor := point(&"room_chair",&"chair","Sit",chair_at+Vector3.UP*.56)
	seats.append({"id":&"room_chair","point":to_global(chair_at+Vector3.UP*.56),"forward":global_basis*Vector3.FORWARD,"occupant":null,"world":get_world_3d(),"anchor":chair_anchor})
	point(&"room_table",&"table","Personal table",Vector3(-5,1.1,3))
	for i in range(3): b.box(Vector3(-8.75,2.5,-1.5+i*1.5),Vector3(.04,1.1,.65),"RoomAccentWindow",[Furnish.CYAN,Furnish.BLUE,Furnish.VIOLET][i],Basis.IDENTITY,false)
	for offset in [-.3,0,.3]: b.line(Vector3(7.3,.9,4.9),Vector3(7.3+offset,2.7-absf(offset),4.9+offset),Furnish.CYAN)
	Furnish.inscription(self,"PRIVATE LODGING",Vector3(0,3.7,6.82),30,Furnish.BLUE,PI)
	b.commit()
