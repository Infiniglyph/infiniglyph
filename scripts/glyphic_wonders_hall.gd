extends Node3D
## Disposable commercial architecture. Stock, offers and identities live outside.
const Chunk = preload("res://scripts/world_chunk.gd")
const Furnish = preload("res://scripts/civilian_establishments.gd")
const SIZE := Vector3(100,45,140)
const FLOOR := .12
const CYAN := Color(.035,.9,1)
const MAGENTA := Color(1,.055,.66)
const VIOLET := Color(.55,.18,1)
const GOLD := Color(1,.68,.16)
const PEDESTAL_TOP := 1.22
const DISPLAY_Z := [40.0,24.0,8.0,-8.0,-24.0,-40.0]
static var _layout: Array[Dictionary] = []
var structure: Node3D
var spawn_anchor: Marker3D
var exit_anchor: Marker3D
var merchant_anchor: Marker3D
var pedestals: Array[Marker3D] = []
var counter_points: Array[Marker3D] = []
var ornament_motifs := [&"open_arches",&"rings",&"infinity"]

static func _box(at: Vector3,size: Vector3,kind: String,color: Color) -> Dictionary:
	return {"at":at,"size":size,"kind":kind,"color":color}

static func collision_layout() -> Array[Dictionary]:
	# One immutable recipe keeps cold-load and unloaded dropped-item support
	# identical to every displayed pedestal, counter, column and floor.
	if not _layout.is_empty(): return _layout
	_layout=[
		_box(Vector3.ZERO,Vector3(100,.24,140),"WondersFloor",CYAN),
		_box(Vector3(0,45.12,0),Vector3(100,.24,140),"WondersVaultRoof",VIOLET),
		_box(Vector3(-50,22.62,0),Vector3(.4,45,140),"WondersSideWall",VIOLET),
		_box(Vector3(50,22.62,0),Vector3(.4,45,140),"WondersSideWall",VIOLET),
		_box(Vector3(0,22.62,-70),Vector3(100,45,.4),"WondersRearWall",MAGENTA),
		_box(Vector3(0,22.62,70),Vector3(100,45,.4),"WondersEntryWall",MAGENTA),
		_box(Vector3(0,.65,-34),Vector3(22,1.06,2.4),"MerchantCounter",VIOLET),
		_box(Vector3(0,1.28,-34),Vector3(24,.2,2.8),"MerchantCounterTop",MAGENTA)]
	for side in [-1,1]:
		for z: float in [-48.0,-24.0,0.0,24.0,48.0]:
			_layout.append(_box(Vector3(side*37,.62,z),Vector3(5,1,5),"GrandColumnBase",MAGENTA))
			_layout.append(_box(Vector3(side*37,17.62,z),Vector3(2.8,33,2.8),"GrandColumn",CYAN))
			_layout.append(_box(Vector3(side*37,34.42,z),Vector3(4.2,.6,4.2),"GrandColumnCapital",VIOLET))
		for z: float in DISPLAY_Z:
			_layout.append(_box(Vector3(side*20,.24,z),Vector3(3.8,.24,3.8),"DisplayPlinthBase",VIOLET))
			_layout.append(_box(Vector3(side*20,.61,z),Vector3(3.2,.74,3.2),"DisplayPlinth",CYAN))
			_layout.append(_box(Vector3(side*20,1.1,z),Vector3(3.6,.24,3.6),"DisplayPlinthTop",MAGENTA))
	return _layout

static func create_support() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name="GlyphicWondersSupport"
	body.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	for entry: Dictionary in collision_layout():
		if not Chunk.boxes.has(entry.size):
			var box := BoxShape3D.new()
			box.size=entry.size
			Chunk.boxes[entry.size]=box
		var shape := CollisionShape3D.new()
		shape.name=entry.kind
		shape.shape=Chunk.boxes[entry.size]
		shape.position=entry.at
		body.add_child(shape)
	return body

func _ready() -> void:
	name="GlyphicWondersGrandHall"
	structure=Chunk.new()
	structure.name="GrandHallBatch"
	add_child(structure)
	var b := structure
	for entry: Dictionary in collision_layout(): b.box(entry.at,entry.size,entry.kind,entry.color)
	Furnish.floor_grid(b,Vector2(50,70),FLOOR+.014,5)
	for side in [-1,1]:
		b.line(Vector3(side*8,FLOOR+.02,66),Vector3(side*8,FLOOR+.02,-29),MAGENTA)
		b.line(Vector3(side*8.35,FLOOR+.021,66),Vector3(side*8.35,FLOOR+.021,-29),VIOLET)
		for z: float in [-48.0,-24.0,0.0,24.0,48.0]:
			for inset in [-.85,.85]: b.line(Vector3(side*37+inset,1.2,z+1.42),Vector3(side*37+inset,33.9,z+1.42),MAGENTA)
		for z: float in DISPLAY_Z:
			var anchor := Furnish.marker(self,"Display_%02d" % pedestals.size(),Vector3(side*20,PEDESTAL_TOP+.05,z))
			pedestals.append(anchor)
			_ring(b,Vector3(side*20,PEDESTAL_TOP+.012,z),1.25,CYAN,false,32)
	# Pointed vault ribs and open side windows dominate the vertical scale.
	for z: float in [-48.0,-24.0,0.0,24.0,48.0]:
		_arch(b,z,37,18,44,CYAN)
		_arch(b,z+.25,35.9,18.4,43.3,MAGENTA)
	for side in [-1,1]:
		for z: float in [-54.0,-18.0,18.0,54.0]: _side_window(b,side,z)
	for z: float in [-38.0,-4.0,30.0]:
		_ring(b,Vector3(0,36,z),9,CYAN,false,64)
		_ring(b,Vector3(0,36.35,z),8.5,MAGENTA,false,64)
		for x in [-8.0,8.0]: b.line(Vector3(x,36,z),Vector3(x,44.8,z),VIOLET)
	_ring(b,Vector3(0,26,-69.7),14,MAGENTA,true,96)
	_ring(b,Vector3(0,26,-69.66),12.8,CYAN,true,96)
	_infinity(b,Vector3(0,26,-69.62),12,5,GOLD)
	# Only non-revealing calligraphy decorates the counter and its backdrop.
	_infinity(b,Vector3(0,.69,-32.77),1.55,.4,CYAN)
	Furnish.inscription(self,"GLYPHIC WONDERS",Vector3(0,14,-69.6),84,CYAN).pixel_size=.022
	Furnish.inscription(self,"THE SHOWCASE",Vector3(0,10,-69.6),40,MAGENTA).pixel_size=.016
	b.box(Vector3(0,2.82,69.7),Vector3(5.8,5.4,.1),"HallExitDoor",MAGENTA,Basis.IDENTITY,false)
	Furnish.inscription(self,"RETURN TO THE CITY",Vector3(0,6.2,69.6),35,CYAN,PI)
	spawn_anchor=Furnish.marker(self,"ShopSafeArrival",Vector3(0,FLOOR+.05,55))
	exit_anchor=Furnish.marker(self,"ShopExit",Vector3(0,1.25,65))
	merchant_anchor=Furnish.marker(self,"FirstMerchant",Vector3(0,FLOOR,-36.1))
	for x in [-2,0,2]: counter_points.append(Furnish.marker(self,"CounterCustomer_"+str(counter_points.size()),Vector3(x,1.25,-31.8)))
	b.commit()

func _arch(b: Node3D,z: float,radius: float,bottom: float,apex: float,color: Color) -> void:
	for side in [-1,1]:
		var previous := Vector3(side*radius,bottom,z)
		for step in range(1,33):
			var t := float(step)/32
			var p := Vector3(side*radius*pow(1-t,1.45),lerpf(bottom,apex,sin(t*PI*.5)),z)
			b.line(previous,p,color)
			previous=p

func _side_window(b: Node3D,side: int,z: float) -> void:
	var x := side*49.75
	for direction in [-1,1]:
		b.line(Vector3(x,7,z+direction*5),Vector3(x,29,z+direction*5),MAGENTA)
		var previous := Vector3(x,29,z+direction*5)
		for step in range(1,17):
			var t := float(step)/16
			var next := Vector3(x,29+9*sin(t*PI*.5),z+direction*5*(1-t))
			b.line(previous,next,CYAN)
			previous=next
	for y in [12.0,20.0,28.0]: b.line(Vector3(x,y,z-5),Vector3(x,y,z+5),VIOLET)
	b.line(Vector3(x,7,z),Vector3(x,37.7,z),MAGENTA)

func _ring(b: Node3D,center: Vector3,radius: float,color: Color,vertical: bool,segments: int) -> void:
	for step in range(segments):
		var a := TAU*step/segments
		var c := TAU*(step+1)/segments
		var p := Vector3(cos(a),sin(a),0) if vertical else Vector3(cos(a),0,sin(a))
		var q := Vector3(cos(c),sin(c),0) if vertical else Vector3(cos(c),0,sin(c))
		b.line(center+p*radius,center+q*radius,color)

func _infinity(b: Node3D,center: Vector3,width: float,height: float,color: Color) -> void:
	var previous := center+Vector3(width,0,0)
	for step in range(1,97):
		var angle := TAU*step/96
		var next := center+Vector3(width*cos(angle),height*sin(2*angle),0)/(1+.35*pow(sin(angle),2))
		b.line(previous,next,color)
		previous=next

func resolve_saved_position(state: Dictionary,actor: CharacterBody3D) -> Vector3:
	var values: Variant=state.get("position",[])
	if not values is Array or values.size()!=3: return spawn_anchor.global_position
	for value: Variant in values:
		if not (value is int or value is float) or not is_finite(float(value)): return spawn_anchor.global_position
	var point := Vector3(float(values[0]),float(values[1]),float(values[2]))
	var local := to_local(point)
	if absf(local.x)>SIZE.x*.5-1 or absf(local.z)>SIZE.z*.5-1 or local.y<FLOOR-.15 or local.y>SIZE.y-2: return spawn_anchor.global_position
	# The matching dormant body may have just handed collision ownership to
	# this new geometry before the physics server's next synchronization. The
	# same recipe also validates that cold-load frame, including pedestal tops.
	var support := -INF
	for entry: Dictionary in collision_layout():
		var half: Vector3=entry.size*.5
		var top: float=entry.at.y+half.y
		if absf(local.x-entry.at.x)<=half.x and absf(local.z-entry.at.z)<=half.z and top<=local.y+.2 and top>=local.y-.65: support=maxf(support,top)
	if support>-INF: local.y=support+.05
	if not _recipe_clear(local): return spawn_anchor.global_position
	point=to_global(local)
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID]=[]
	if is_instance_valid(actor): exclude.append(actor.get_rid())
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.2,point-Vector3.UP*.65,1,exclude))
	if not hit.is_empty() and hit.normal.y>.65: point=hit.position+Vector3.UP*.05
	var shape := CapsuleShape3D.new()
	shape.radius=.28
	shape.height=1.85
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.95)
	query.collision_mask=1
	query.exclude=exclude
	return point if space.intersect_shape(query,1).is_empty() else spawn_anchor.global_position

static func _recipe_clear(feet: Vector3) -> bool:
	# Exact distance from each axis-aligned structural box to the capsule's
	# vertical centre segment. Its swept radius is the standing player radius.
	for entry: Dictionary in collision_layout():
		var half: Vector3=entry.size*.5
		var x := maxf(0,absf(feet.x-entry.at.x)-half.x)
		var z := maxf(0,absf(feet.z-entry.at.z)-half.z)
		var low: float=feet.y+.305
		var high: float=feet.y+1.595
		var y := maxf(0,maxf(entry.at.y-half.y-high,low-entry.at.y-half.y))
		if x*x+y*y+z*z<.28*.28: return false
	return true
