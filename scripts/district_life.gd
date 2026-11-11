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
var reactions: Node3D
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
@export var simulation_lod_enabled := true
var _vehicle_queue: Array[Dictionary] = []
var _people_queue: Array[Dictionary] = []
var _lod_clock := 0.0
var _pose_policy := {"near_range":28.0,"mid_hz":20.0,"far_hz":10.0}
var _view_camera: Camera3D
var _vehicle_query := PhysicsShapeQueryParameters3D.new()
var _vehicle_box := BoxShape3D.new()
var _pedestrian_query := PhysicsShapeQueryParameters3D.new()
var validation_probes := 0
var spawned_this_tick := 0

func _ready() -> void:
	name = "DistrictLife"
	_capsule.height = 1.85
	_capsule.radius = 0.29
	_vehicle_query.shape = _vehicle_box
	_vehicle_query.collision_mask = 13
	_pedestrian_query.shape = _capsule
	_pedestrian_query.margin = 0.005
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
	_vehicle_box.size = size
	_vehicle_query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*(size.y*0.5+0.08))
	_vehicle_query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_shape(_vehicle_query,1).is_empty()

func pedestrian_clear(at: Vector3, static_only: bool = true, excluded: Array[RID] = []) -> bool:
	_pedestrian_query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*0.95)
	_pedestrian_query.collision_mask = 1 if static_only else 13
	_pedestrian_query.exclude = [actor.get_rid()] if static_only else excluded
	return get_world_3d().direct_space_state.intersect_shape(_pedestrian_query,1).is_empty()

func validate_walk(record: Dictionary) -> bool:
	if record.checked: return record.valid
	var route: PackedVector3Array = record.route
	# At most twelve ground/clearance samples per frame, shared by the queue.
	while int(record.get("check_segment",0))<route.size() and validation_probes<12:
		var n := int(record.get("check_segment",0))
		var step := int(record.get("check_step",0))
		var a: Vector3 = route[n]
		var b: Vector3 = route[(n+1)%route.size()]
		var p := a.lerp(b,clampf(step*2/maxf(a.distance_to(b),0.01),0,1))
		p.y = Regions.surface_at(p.x,p.z)+0.04
		validation_probes += 1
		if not pedestrian_clear(p):
			record.valid = false
			record.checked = true
			return false
		step += 1
		if step>ceili(a.distance_to(b)/2):
			record.check_segment = n+1
			record.check_step = 0
		else: record.check_step = step
	if int(record.get("check_segment",0))>=route.size(): record.checked = true
	return record.checked and record.valid

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
		if resident.record.get("combat",false): continue
		if resident.global_position.distance_to(origin)>155:
			resident.record.point = resident.global_position
			people.erase(id)
			resident.queue_free()
	var nearby: Array[Dictionary] = []
	for record: Dictionary in vehicle_records:
		if not vehicles.has(record.id) and record.point.distance_squared_to(origin)<240*240: nearby.append(record)
	nearby.sort_custom(func(a: Dictionary,b: Dictionary): return a.point.distance_squared_to(origin)<b.point.distance_squared_to(origin))
	_vehicle_queue.assign(nearby)
	nearby.clear()
	for record: Dictionary in resident_records:
		if not people.has(record.id) and not record.get("combat",false) and record.point.distance_squared_to(origin)<125*125 and record.valid: nearby.append(record)
	nearby.sort_custom(func(a: Dictionary,b: Dictionary): return a.point.distance_squared_to(origin)<b.point.distance_squared_to(origin))
	_people_queue.assign(nearby)

func service_spawns() -> void:
	spawned_this_tick = 0
	var attempts := 0
	while not _vehicle_queue.is_empty() and vehicles.size()<vehicle_budget and attempts<2:
		var record: Dictionary = _vehicle_queue.pop_front()
		attempts += 1
		if vehicles.has(record.id) or record.point.distance_squared_to(actor.global_position)>240*240: continue
		var size := Vector3(2.3,2.5,5.4) if record.kind=="truck" else (Vector3(0.9,1.4,2.4) if record.kind=="motorcycle" else Vector3(1.9,1.85,4.2))
		# Use the yawed envelope for traffic spawn checks (long trucks at corners).
		if absf(sin(record.yaw))>0.7: size = Vector3(size.z,size.y,size.x)
		if not clear_vehicle(record.point,size,[]): continue
		var vehicle := Vehicle.new()
		vehicle.life = self
		vehicle.record = record
		# Enter physics at the real spawn, avoiding a transient origin collider.
		vehicle.position = record.point
		vehicle.rotation.y = record.get("yaw",0.0)
		add_child(vehicle)
		vehicles[record.id] = vehicle
		spawned_this_tick += 1
		break # Construct at most one vehicle per frame.
	if _people_queue.is_empty() or people.size()>=resident_budget: return
	var record: Dictionary = _people_queue[0]
	if people.has(record.id) or record.get("combat",false) or record.point.distance_squared_to(actor.global_position)>125*125:
		_people_queue.pop_front()
		return
	if validate_walk(record):
		_people_queue.pop_front()
		if pedestrian_clear(record.point,false):
			spawn_person(record)
			spawned_this_tick += 1
	elif record.checked: _people_queue.pop_front()

func pose_interval(at: Vector3) -> float:
	var distance := at.distance_squared_to(actor.global_position)
	if distance<64: return 0
	if is_instance_valid(_view_camera) and not _view_camera.is_position_in_frustum(at+Vector3.UP): return INF
	if distance<float(_pose_policy.near_range)*float(_pose_policy.near_range): return 0.033
	return 1.0/float(_pose_policy.mid_hz if distance<3025 else _pose_policy.far_hz)

func spawn_person(record: Dictionary) -> CharacterBody3D:
	var resident := Resident.new()
	resident.record = record
	resident.life = self
	resident.position = record.point
	add_child(resident)
	people[record.id] = resident
	return resident

func eject_driver(vehicle: CharacterBody3D, at: Vector3) -> CharacterBody3D:
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
			if resident.record.get("combat",false): continue
			if farthest==null or resident.global_position.distance_to(actor.global_position)>farthest.global_position.distance_to(actor.global_position): farthest = resident
		people.erase(farthest.record.id)
		farthest.queue_free()
	var resident := spawn_person(record)
	resident.wait = 2.5
	resident.caption.text = "That's my ride!"
	resident.record.meetings = 1
	return resident

func nearest_talker() -> CharacterBody3D:
	var result: CharacterBody3D
	var best := 2.8
	for resident: CharacterBody3D in people.values():
		if not resident.is_visible_in_tree() or resident.virtualized or resident.record.get("combat",false): continue
		var distance := resident.global_position.distance_to(actor.global_position)
		if distance<best:
			best = distance
			result = resident
	return result

func _physics_process(delta: float) -> void:
	if not _built: return
	validation_probes = 0
	service_spawns()
	_lod_clock += delta
	if _lod_clock>=0.2:
		_view_camera = get_viewport().get_camera_3d()
		_pose_policy = actor.visual.retrieval.world_policy()
		for resident: CharacterBody3D in people.values():
			if resident.record.get("combat",false): continue
			var offset := resident.global_position-actor.global_position
			var distance := Vector2(offset.x,offset.z).length()
			var range_now := 65.0+minf(100,Vector2(actor.velocity.x,actor.velocity.z).length()*0.75)
			if not simulation_lod_enabled or distance<range_now or resident.wait>0 and resident.record.meetings>0:
				resident.set_virtualized(false)
			elif distance>range_now+25: resident.set_virtualized(true)
			if resident.virtualized: resident.advance_virtual(_lod_clock)
		_lod_clock = 0
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
	for record: Dictionary in resident_records:
		if people.has(record.id) or record.get("combat",false) or not record.valid: continue
		advance_journey(record,elapsed)
	refresh_active()

func advance_journey(record: Dictionary, delta: float) -> void:
	var wait := maxf(0,float(record.get("wait",0))-delta)
	record.wait = wait
	if wait>0: return
	var route: PackedVector3Array = record.route
	var speed := 1.25+float(record.id%4)*0.12
	var distance: float = record.point.distance_to(route[record.cursor])
	if distance<=speed*delta:
		record.point = route[record.cursor]
		record.cursor = (record.cursor+1)%route.size()
		record.wait = 1.0+float(record.id%5)
	else:
		record.point = record.point.move_toward(route[record.cursor],speed*delta)
		if maxf(absf(record.point.x),absf(record.point.z))>704:
			record.point.y = Regions.surface_at(record.point.x,record.point.z)+0.04
