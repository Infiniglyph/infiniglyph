extends Node3D
## Small active neighborhoods, persistent virtual journeys across the whole map.
## Architecture stays loaded. Only dynamic people/traffic use distance budgets.
const Regions = preload("res://scripts/world_regions.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
const Resident = preload("res://scripts/neighborhood_resident.gd")
const Profiles = preload("res://scripts/resident_profiles.gd")
const Chunk = preload("res://scripts/world_chunk.gd")
var actor: CharacterBody3D
var regions: Node3D
var session: Node
var vehicles: Dictionary = {}
var people: Dictionary = {}
var vehicle_records: Array[Dictionary] = []
var resident_records: Array[Dictionary] = []
@export var vehicle_budget := 22
@export var resident_budget := 28
var _clock := 0.0
var _built := false
var _profiles: Array[Dictionary] = []
var _capsule := CapsuleShape3D.new()
var driveways: Dictionary = {}

func _ready() -> void:
	name = "DistrictLife"
	_capsule.height = 1.85
	_capsule.radius = 0.29
	_profiles = Profiles.all(100)
	call_deferred("build")

func profile_for(id: int, driver: bool = false) -> Dictionary:
	var profile: Dictionary = _profiles[id%100].duplicate(true)
	profile.name += " " + str(id/100+1)
	profile.role = "driver" if driver else profile.role
	profile.body_profile = &"female" if id%2==0 else &"male"
	var colors: Array = Profiles.PALETTE.keys()
	profile.tint = Profiles.PALETTE[colors[id%colors.size()]]
	return profile

func point(x: float, z: float) -> Vector3:
	return Vector3(x,Regions.surface_at(x,z)+0.04,z)

func build() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(regions): return
	# Each outer block has residents; rural journeys follow real arterials.
	for x in range(-640,640,64):
		for z in range(-640,640,64):
			if maxf(absf(x+32),absf(z+32))<128: continue
			var route := PackedVector3Array([point(x+10,z+10),point(x+54,z+10),point(x+54,z+54),point(x+10,z+54)])
			for i in range(2): add_person(route,i*2,route[i*2])
			if Regions.code(x,z,9)%3==0:
				add_traffic(PackedVector3Array([point(x+3,z+3),point(x+61,z+3),point(x+61,z+61),point(x+3,z+61)]))
	for x in [-1024,-512,0,512]:
		for z in [-1024,-512,0,512]:
			if maxf(absf(x+256),absf(z+256))<704: continue
			add_traffic(PackedVector3Array([point(x+3,z+3),point(x+509,z+3),point(x+509,z+509),point(x+3,z+509)]))
			# Keep roadside walkers on one bank; the shoulder is outside the
			# bridge's twelve-metre deck at the northern ravine.
			var route := PackedVector3Array([point(x+10,z+80),point(x+10,z+120)])
			add_person(route,0,route[0])
	# Mark selected front driveways. Their slab and parked vehicle are physical.
	for i in range(regions.buildings.size()):
		var building: Dictionary = regions.buildings[i]
		if building.region not in ["home","farm"] or i%4!=0: continue
		var at: Vector3 = building.point+Vector3(9,0,15)
		at.y = Regions.height_at(at.x,at.z)
		# Validate before creating a driveway through a neighboring house/tree.
		if not clear_vehicle(at+Vector3.UP*0.1,Vector3(3,2.7,7),[]): continue
		var key := Vector2i(floori((at.x+128)/256),floori((at.z+128)/256))
		if not driveways.has(key):
			var batch := Chunk.new()
			batch.name = "Driveways_%d_%d" % [key.x,key.y]
			batch.position = Vector3(key.x*256-128,0,key.y*256-128)
			add_child(batch)
			driveways[key] = batch
		driveways[key].box(at+Vector3.UP*0.025,Vector3(3.4,0.05,7.4),"Driveway",Color(0.06,0.4,0.45))
		var id := vehicle_records.size()
		vehicle_records.append({"id":id,"kind":["car","motorcycle","truck"][id%3],"point":at+Vector3.UP*0.12,"yaw":0.0,"traffic":false,"taken":false,"route":PackedVector3Array(),"cursor":0,"color":Profiles.PALETTE.values()[id%11],"driver":profile_for(id,true)})
	for batch: Node3D in driveways.values(): batch.commit()
	_built = true
	refresh_active()

func add_person(route: PackedVector3Array, cursor: int, at: Vector3) -> void:
	var id := resident_records.size()
	resident_records.append({"id":id,"profile":profile_for(id),"point":at,"route":route,"cursor":(cursor+1)%route.size(),"meetings":0,"checked":false,"valid":true})

func add_traffic(route: PackedVector3Array) -> void:
	var id := vehicle_records.size()
	var start := id%4
	var forward := route[(start+1)%4]-route[start]
	vehicle_records.append({"id":id,"kind":["car","motorcycle","truck"][id%3],"point":route[start],"yaw":atan2(forward.x,forward.z),"traffic":true,"taken":false,"route":route,"cursor":(start+1)%4,"color":Profiles.PALETTE.values()[id%11],"driver":profile_for(id,true)})

func clear_vehicle(at: Vector3, size: Vector3, excluded: Array[RID]) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*(size.y*0.5+0.08))
	query.collision_mask = 13
	query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func pedestrian_clear(at: Vector3, static_only: bool = true) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*0.95)
	query.collision_mask = 1 if static_only else 13
	if static_only: query.exclude = [actor.get_rid()]
	query.margin = 0.005
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func validate_walk(record: Dictionary) -> bool:
	if record.checked: return record.valid
	record.checked = true
	var route: PackedVector3Array = record.route
	for n in range(route.size()):
		var a: Vector3 = route[n]
		var b: Vector3 = route[(n+1)%route.size()]
		for step in range(ceili(a.distance_to(b)/2)+1):
			var p := a.lerp(b,clampf(step*2/maxf(a.distance_to(b),0.01),0,1))
			p.y = Regions.surface_at(p.x,p.z)+0.04
			if not pedestrian_clear(p):
				if "--diagnose-life" in OS.get_cmdline_user_args(): print("BLOCKED WALK: ",record.id," at ",p," route=",record.route)
				record.valid = false
				return false
	return true

func refresh_active() -> void:
	var origin := actor.global_position
	for id: int in vehicles.keys():
		var vehicle: CharacterBody3D = vehicles[id]
		if not is_instance_valid(vehicle.player_driver) and vehicle.global_position.distance_to(origin)>280:
			vehicle.record.point = vehicle.global_position
			vehicle.record.yaw = vehicle.rotation.y
			vehicles.erase(id)
			vehicle.queue_free()
	for id: int in people.keys():
		var resident: CharacterBody3D = people[id]
		if resident.global_position.distance_to(origin)>155:
			resident.record.point = resident.global_position
			people.erase(id)
			resident.queue_free()
	var nearby: Array[Dictionary] = []
	for record: Dictionary in vehicle_records:
		if not vehicles.has(record.id) and record.point.distance_squared_to(origin)<240*240: nearby.append(record)
	nearby.sort_custom(func(a: Dictionary,b: Dictionary): return a.point.distance_squared_to(origin)<b.point.distance_squared_to(origin))
	for record: Dictionary in nearby:
		if vehicles.size()>=vehicle_budget: break
		var size := Vector3(2.3,2.5,5.4) if record.kind=="truck" else (Vector3(0.9,1.4,2.4) if record.kind=="motorcycle" else Vector3(1.9,1.85,4.2))
		# Use the yawed envelope for traffic spawn checks (long trucks at corners).
		if absf(sin(record.yaw))>0.7: size = Vector3(size.z,size.y,size.x)
		if not clear_vehicle(record.point,size,[]): continue
		var vehicle := Vehicle.new()
		vehicle.life = self
		vehicle.record = record
		add_child(vehicle)
		vehicles[record.id] = vehicle
	nearby.clear()
	for record: Dictionary in resident_records:
		if not people.has(record.id) and record.point.distance_squared_to(origin)<125*125 and record.valid: nearby.append(record)
	nearby.sort_custom(func(a: Dictionary,b: Dictionary): return a.point.distance_squared_to(origin)<b.point.distance_squared_to(origin))
	for record: Dictionary in nearby:
		if people.size()>=resident_budget: break
		if not validate_walk(record) or not pedestrian_clear(record.point,false): continue
		spawn_person(record)

func spawn_person(record: Dictionary) -> CharacterBody3D:
	var resident := Resident.new()
	resident.record = record
	resident.life = self
	add_child(resident)
	people[record.id] = resident
	return resident

func eject_driver(vehicle: CharacterBody3D, at: Vector3) -> void:
	vehicle.has_driver = false
	vehicle.record.taken = true
	var id := resident_records.size()
	var away := at-vehicle.global_position
	away.y = 0
	away = away.normalized()
	var destination := at
	for step in range(1,15):
		var candidate := at+away*step*0.5
		var ray := PhysicsRayQueryParameters3D.create(candidate+Vector3.UP,candidate-Vector3.UP*1.2,1,[actor.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<0.7 or absf(hit.position.y-destination.y)>0.4: break
		candidate = hit.position+Vector3.UP*0.04
		if not pedestrian_clear(candidate): break
		destination = candidate
	var route := PackedVector3Array([at,destination])
	var record := {"id":id,"profile":vehicle.record.driver.duplicate(true),"point":at,"route":route,"cursor":0,"meetings":0,"checked":true,"valid":true}
	resident_records.append(record)
	# Evict one distant pose if the neighborhood is already at budget.
	if people.size()>=resident_budget:
		var farthest: CharacterBody3D
		for resident: CharacterBody3D in people.values():
			if farthest==null or resident.global_position.distance_to(actor.global_position)>farthest.global_position.distance_to(actor.global_position): farthest = resident
		people.erase(farthest.record.id)
		farthest.queue_free()
	var resident := spawn_person(record)
	resident.wait = 2.5
	resident.caption.text = "That's my ride!"
	resident.record.meetings = 1

func nearest_talker() -> CharacterBody3D:
	var result: CharacterBody3D
	var best := 2.8
	for resident: CharacterBody3D in people.values():
		var distance := resident.global_position.distance_to(actor.global_position)
		if distance<best:
			best = distance
			result = resident
	return result

func _physics_process(delta: float) -> void:
	if not _built: return
	_clock += delta
	if _clock<0.5: return
	var elapsed := _clock
	_clock = 0
	# Distant traffic advances a lightweight route record, with no mesh/physics.
	for record: Dictionary in vehicle_records:
		if vehicles.has(record.id) or not record.traffic or record.taken: continue
		var route: PackedVector3Array = record.route
		var offset: Vector3 = route[record.cursor]-record.point
		if offset.length()<7*elapsed+0.1:
			record.point = route[record.cursor]
			record.cursor = (record.cursor+1)%route.size()
		else:
			record.point += offset.normalized()*7*elapsed
			record.point.y = Regions.surface_at(record.point.x,record.point.z)+0.04
			record.yaw = atan2(offset.x,offset.z)
	refresh_active()
