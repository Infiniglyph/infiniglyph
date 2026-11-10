extends Node3D
## Shared physical pedestrian network and local social coordination.
## Simulation stays live regardless of menu state or distance from the player.
const Resident = preload("res://scripts/city_resident.gd")
const Profiles = preload("res://scripts/resident_profiles.gd")
@export var resident_count := 100
@export var max_outdoors := 64
@export var initial_outdoors := 44
@export var population_seed := 0
var player: CharacterBody3D
var duel: CanvasLayer
var residents: Array[CharacterBody3D] = []
var reserved_outdoors := 0 # Street-combat proxies reserve their civilian slot.
var active_residents: Array[CharacterBody3D] = []
var entrances: Dictionary = {}
var public_places: Array[StringName] = []
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var indoor_entries := 0
var indoor_exits := 0
var failed_entrances: Array[StringName] = []
var _service_time := 0.0
var _spatial_time := 0.0
var _indoor_cursor := 0
var by_id: Dictionary = {}
var points: Dictionary = {}
var point_ids: Dictionary = {}
var names: Dictionary = {}
var graph := AStar3D.new()
var edges: Array[Vector2i] = []
var blocked_edges: Array[String] = []
var ready_for_visitors := false
var social_events := 0
var observed_events := 0
var speaker: CharacterBody3D
var speaker_time := 0.0
var _clock := 0.0
var _last_attack := false
var _capsule := CapsuleShape3D.new()

func _ready() -> void:
	name = "CityPopulation"
	_capsule.radius = 0.34
	_capsule.height = 1.9
	# Physics must have registered every existing building before validating paths.
	call_deferred("build")

func floor_at(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.55,at-Vector3.UP*0.65,1)
	ray.exclude = [player.get_rid(),duel.partner.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<0.8 or hit.collider is CharacterBody3D: return {}
	return {"point":hit.position+Vector3.UP*0.045}

func clear_at(at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*0.96)
	query.collision_mask = 1
	query.exclude = [player.get_rid(),duel.partner.get_rid()]
	query.margin = 0.01
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func segment_clear(a: Vector3, b: Vector3) -> bool:
	var count := maxi(1,ceili(a.distance_to(b)/0.65))
	var previous := a
	for i in range(count+1):
		var result := floor_at(a.lerp(b,float(i)/count))
		if result.is_empty(): return false
		var point: Vector3 = result.point
		# Up to 22 cm of real curb is traversed by the resident's swept step-up.
		if absf(point.y-previous.y)>0.22 or not clear_at(point+Vector3.UP*0.22): return false
		previous = point
	return true

func node_at(id: StringName, at: Vector3, title: String = "") -> void:
	var result := floor_at(at)
	if result.is_empty() or not clear_at(result.point):
		push_warning("Resident destination lacks clear footing: "+String(id))
		return
	var index := graph.get_available_point_id()
	points[id] = result.point
	point_ids[id] = index
	names[id] = title if title!="" else "the avenue"
	graph.add_point(index,result.point)

func connect_places(a: StringName, b: StringName) -> void:
	if not points.has(a) or not points.has(b): return
	if not segment_clear(points[a],points[b]):
		blocked_edges.append(String(a)+" -> "+String(b))
		return
	graph.connect_points(point_ids[a],point_ids[b])
	edges.append(Vector2i(point_ids[a],point_ids[b]))

func build() -> void:
	await get_tree().physics_frame
	if population_seed==0: rng.randomize()
	else: rng.seed = population_seed
	var z_values: Array[float] = [74,64,44,24,6,-6,-24,-44]
	var west: Array[StringName] = [&"south_w",&"south_crossing_w",&"south_lane_w",&"south_walk_w",&"plaza_w",&"plaza_nw",&"north_w",&"boulevard_w"]
	var east: Array[StringName] = [&"south_e",&"south_crossing_e",&"south_lane_e",&"south_walk_e",&"plaza_e",&"plaza_ne",&"north_e",&"boulevard_e"]
	for side in range(2):
		var ids: Array[StringName] = west if side==0 else east
		for i in range(ids.size()):
			var title := "the south arrival court" if i==0 else ("the central plaza" if i in [4,5] else ("the north boulevard" if i>5 else "the south avenue"))
			node_at(ids[i],Vector3(-3.5 if side==0 else 3.5,0,z_values[i]),title)
			if i>0: connect_places(ids[i-1],ids[i])
	for i in range(west.size()): connect_places(west[i],east[i])
	for side: String in ["west","east"]:
		var sign_x := -1.0 if side=="west" else 1.0
		var previous: StringName = &"plaza_w" if side=="west" else &"plaza_e"
		for spec in [["crossing",18.0],["avenue",36.0],["outer_turn",52.0],["outer",68.5]]:
			var id := StringName(side+"_"+spec[0])
			node_at(id,Vector3(sign_x*float(spec[1]),0,6),"the "+side+" avenue")
			connect_places(previous,id)
			previous = id
		for spec in [["court",38.0],["outer_south",64.0],["outer_north",-30.0],["north_turn",-62.5]]:
			node_at(StringName(side+"_"+spec[0]),Vector3(sign_x*68.5,0,float(spec[1])),"the "+side+" lantern court" if spec[0]=="court" else "the outer promenade")
		connect_places(StringName(side+"_outer"),StringName(side+"_court"))
		connect_places(StringName(side+"_court"),StringName(side+"_outer_south"))
		connect_places(StringName(side+"_outer_south"),&"south_crossing_w" if side=="west" else &"south_crossing_e")
		connect_places(StringName(side+"_outer"),StringName(side+"_outer_north"))
		connect_places(StringName(side+"_outer_north"),StringName(side+"_north_turn"))
		node_at(StringName(side+"_garden_turn"),Vector3(sign_x*43,0,-62.5),"the northern cross street")
		node_at(StringName(side+"_garden"),Vector3(sign_x*43,0,-71.5),"the north-"+side+" garden")
		connect_places(StringName(side+"_north_turn"),StringName(side+"_garden_turn"))
		connect_places(StringName(side+"_garden_turn"),StringName(side+"_garden"))
		# Ground-level inner passage passes between the civic dais and old blocks.
		# Its diagonal entrance stays clear of the physical banner at x=+/-9.7.
		node_at(StringName(side+"_inner_turn"),Vector3(sign_x*14,0,-48),"the north boulevard")
		node_at(StringName(side+"_inner_north"),Vector3(sign_x*14,0,-62.5),"the northern cross street")
		connect_places(&"boulevard_w" if side=="west" else &"boulevard_e",StringName(side+"_inner_turn"))
		connect_places(StringName(side+"_inner_turn"),StringName(side+"_inner_north"))
		connect_places(StringName(side+"_inner_north"),StringName(side+"_garden_turn"))
	# A second cross-street lane and north/south access points serve the facades.
	for side: String in ["west","east"]:
		var sign_x := -1.0 if side=="west" else 1.0
		var previous: StringName = &"plaza_nw" if side=="west" else &"plaza_ne"
		for spec in [["crossing",18.0],["avenue",36.0],["outer_turn",52.0],["outer",68.5]]:
			var id := StringName(side+"_north_"+spec[0])
			node_at(id,Vector3(sign_x*float(spec[1]),0,-7.5),"the "+side+" avenue")
			connect_places(previous,id)
			connect_places(id,StringName(side+"_"+spec[0]))
			previous = id
	public_places.assign(points.keys())
	for door: Node3D in get_tree().get_nodes_in_group("resident_entrances"):
		var at: Vector3 = door.outside()
		var candidates: Array = points.keys()
		candidates.sort_custom(func(a: StringName,b: StringName): return points[a].distance_squared_to(at)<points[b].distance_squared_to(at))
		var links: Array[StringName] = []
		for candidate: StringName in candidates:
			if points[candidate].distance_to(at)>65: continue
			if segment_clear(at,points[candidate]): links.append(candidate)
			if links.size()==2: break
		var valid := true
		var passage: PackedVector3Array = door.passage(true)
		for i in range(passage.size()-1):
			if not segment_clear(passage[i],passage[i+1]): valid = false
		if links.is_empty() or not valid:
			failed_entrances.append(door.entrance_id)
			continue
		node_at(door.entrance_id,at,"a building lobby")
		if not points.has(door.entrance_id): continue
		entrances[door.entrance_id] = door
		for link: StringName in links: connect_places(door.entrance_id,link)
	if entrances.is_empty():
		push_error("No physical building entrance can serve the population.")
		return
	var profiles := Profiles.all(resident_count)
	var colors: Array = Profiles.PALETTE.keys()
	# Shuffle locally without changing gameplay/global randomness; cover every color.
	for i in range(colors.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var swap: String = colors[i]
		colors[i] = colors[j]
		colors[j] = swap
	var homes: Array = entrances.keys()
	for i in range(profiles.size()):
		var resident := Resident.new()
		resident.population = self
		resident.profile = profiles[i]
		resident.profile["serial"] = i
		resident.profile["color_name"] = colors[i%colors.size()]
		resident.profile["tint"] = Profiles.PALETTE[colors[i%colors.size()]]*rng.randf_range(0.87,1)
		resident.home_building = homes[(i*7)%homes.size()]
		resident.indoor_left = rng.randf_range(3,65)
		resident.position = entrances[resident.home_building].concealed()
		add_child(resident)
		residents.append(resident)
		by_id[resident.profile.id] = resident
	# Spread the initial street population over real route segments, not a plaza pile.
	for i in range(mini(max_outdoors,mini(initial_outdoors,residents.size()))):
		var resident: CharacterBody3D = residents[i]
		for attempt in range(80):
			var edge := edges[rng.randi_range(0,edges.size()-1)]
			var at := graph.get_point_position(edge.x).lerp(graph.get_point_position(edge.y),rng.randf_range(0.12,0.88))
			var floor := floor_at(at)
			if floor.is_empty() or not clear_at(floor.point): continue
			var crowded := at.distance_to(player.position)<2
			for other: CharacterBody3D in active_residents:
				if other.position.distance_to(at)<2: crowded = true
			if crowded: continue
			resident.activate(floor.point)
			resident.wait = rng.randf_range(0.1,3)
			break
	rebuild_neighbours()
	ready_for_visitors = true

func rebuild_neighbours() -> void:
	var buckets: Dictionary = {}
	for resident: CharacterBody3D in active_residents:
		var cell := Vector2i(floori(resident.position.x/4),floori(resident.position.z/4))
		if not buckets.has(cell): buckets[cell] = []
		buckets[cell].append(resident)
	for resident: CharacterBody3D in active_residents:
		resident.neighbours.clear()
		var cell := Vector2i(floori(resident.position.x/4),floori(resident.position.z/4))
		for x in range(-1,2):
			for z in range(-1,2):
				for other: CharacterBody3D in buckets.get(cell+Vector2i(x,z),[]):
					if other!=resident: resident.neighbours.append(other)

func goal_load(id: StringName) -> int:
	var count := 0
	for resident: CharacterBody3D in active_residents:
		if resident.goal==id: count += 1
	return count

func choose_destination(resident: CharacterBody3D) -> StringName:
	if resident.outdoor_stops>=resident.stops_before_indoor:
		var doors: Array = entrances.keys()
		doors.sort_custom(func(a: StringName,b: StringName): return points[a].distance_squared_to(resident.position)<points[b].distance_squared_to(resident.position))
		if rng.randf()<0.3 and goal_load(resident.home_building)<2: return resident.home_building
		for id: StringName in doors:
			if goal_load(id)<2: return id
	var choices: Array = public_places.duplicate()
	choices.sort_custom(func(a: StringName,b: StringName): return points[a].distance_squared_to(resident.position)<points[b].distance_squared_to(resident.position))
	var candidates: Array[StringName] = []
	for id: StringName in choices:
		if id==resident.goal or goal_load(id)>=3: continue
		if points[id].distance_to(resident.position)<5: continue
		candidates.append(id)
		if candidates.size()==8: break
	# Personal routines still influence errands, without synchronizing the whole city.
	var personal: StringName = resident.profile.routine[rng.randi_range(0,2)]
	if rng.randf()<0.25 and points.has(personal) and goal_load(personal)<3: return personal
	return candidates[rng.randi_range(0,candidates.size()-1)] if not candidates.is_empty() else resident.profile.home

func hidden_from_player(at: Vector3) -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera==null: camera = player.camera_rig.camera
	for height: float in [0.1,0.95,1.8]:
		var sample := at+Vector3.UP*height
		if not camera.is_position_in_frustum(sample): continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,sample,1,[player.get_rid(),duel.partner.get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return false
	return true

func finish_indoor(resident: CharacterBody3D) -> bool:
	var door: Node3D = resident.travel_door
	if not hidden_from_player(resident.global_position): return false
	door.entries += 1
	indoor_entries += 1
	resident.home_building = door.entrance_id
	door.release(resident)
	active_residents.erase(resident)
	resident.deactivate()
	resident.indoor_left = rng.randf_range(12,45)
	return true

func spawn_space_free(resident: CharacterBody3D, at: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*0.96)
	query.collision_mask = 5
	query.exclude = [resident.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func service_indoors(delta: float) -> void:
	var start := _indoor_cursor
	_indoor_cursor = (_indoor_cursor+1)%residents.size()
	for offset in range(residents.size()):
		var index := (start+offset)%residents.size()
		var resident: CharacterBody3D = residents[index]
		if resident.active: continue
		resident.indoor_left -= delta
		if resident.indoor_left>0 or active_residents.size()+reserved_outdoors>=max_outdoors: continue
		var door: Node3D = entrances[resident.home_building]
		if not door.available() or not hidden_from_player(door.concealed()): continue
		if not spawn_space_free(resident,door.concealed()): continue
		var blocked := false
		for other: CharacterBody3D in active_residents:
			if other.position.distance_to(door.concealed())<0.9 or other.position.distance_to(door.outside())<1.2: blocked = true
		if blocked or not door.claim(resident): continue
		resident.activate(door.concealed())
		resident.travel_door = door
		resident.transit = &"exiting"
		resident.state = "leaving a building"
		resident.path = door.passage(false)
		resident.cursor = 0
		resident.wait = 0
		resident.outdoor_stops = 0
		resident.stops_before_indoor = rng.randi_range(1,3)
		_indoor_cursor = (index+1)%residents.size()

func place_name(id: StringName) -> String:
	return names.get(id,"the avenue")

func nearest_id(at: Vector3) -> StringName:
	var best := INF
	var id: StringName
	for key: StringName in points:
		var distance := at.distance_squared_to(points[key])
		if distance<best:
			best = distance
			id = key
	return id

func route(at: Vector3, destination: StringName) -> PackedVector3Array:
	if not points.has(destination): return PackedVector3Array()
	var candidates: Array = points.keys()
	candidates.sort_custom(func(a: StringName,b: StringName): return points[a].distance_squared_to(at)<points[b].distance_squared_to(at))
	for i in range(mini(6,candidates.size())):
		var start: StringName = candidates[i]
		if not segment_clear(at,points[start]): continue
		return graph.get_point_path(point_ids[start],point_ids[destination])
	return PackedVector3Array()

func escape_stop(at: Vector3, source: Vector3) -> StringName:
	var nearest := nearest_id(at)
	var result := nearest
	var best := -INF
	for neighbour: int in graph.get_point_connections(point_ids[nearest]):
		var point := graph.get_point_position(neighbour)
		var value := point.distance_to(source)-at.distance_to(point)*0.15
		if value>best:
			best = value
			for id: StringName in point_ids:
				if point_ids[id]==neighbour: result = id
	return result

func steer(resident: CharacterBody3D, requested: Vector3) -> Vector3:
	var result := requested
	# Yield before physical contact; civilians never become immovable roadblocks.
	for other: CharacterBody3D in resident.neighbours:
		if not other.active: continue
		if other==resident: continue
		var away := resident.global_position-other.global_position
		away.y = 0
		var distance := away.length()
		if distance>0.001 and distance<1.15:
			result += away/distance*(1.15-distance)*2.8
			if requested.length()>0.1 and requested.normalized().dot(-away/distance)>0.2:
				result += Vector3(requested.z,0,-requested.x).normalized()*0.85
	var away := resident.global_position-player.global_position
	away.y = 0
	if absf(resident.global_position.y-player.global_position.y)<1.8 and away.length()<1.7:
		if away.length()<0.05: away = Vector3.RIGHT
		result += away.normalized()*(1.7-away.length())*2.5
	result = result.limit_length(resident.speed*(1.5 if resident.reaction_time>0 else 1.0))
	if result.length()<0.03: return Vector3.ZERO
	if resident.probe_clock>0 and result.normalized().dot(resident.probe_requested)>0.85:
		return resident.probe_heading*result.length()
	resident.probe_clock = 0.12 if resident.position.distance_to(player.position)<25 else 0.22
	resident.probe_requested = result.normalized()
	# Don't let avoidance steer off a supported route or into architecture.
	for turn: float in [0.0,0.45,-0.45,0.9,-0.9,1.3,-1.3]:
		var candidate := result.rotated(Vector3.UP,turn)
		var probe := floor_at(resident.global_position+candidate.normalized()*0.5)
		if not probe.is_empty() and clear_at(probe.point+Vector3.UP*0.22):
			resident.probe_heading = candidate.normalized()
			return candidate
	resident.probe_heading = Vector3.ZERO
	return Vector3.ZERO

func visible_between(a: Vector3, b: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a+Vector3.UP,b+Vector3.UP,1,[player.get_rid()])).is_empty()

func nearest_talker() -> CharacterBody3D:
	if not ready_for_visitors or player.dodge.active or not player.is_on_floor(): return null
	var result: CharacterBody3D
	var distance := 2.8
	for resident: CharacterBody3D in active_residents:
		if resident.transit!=&"outdoor": continue
		var next := resident.global_position.distance_to(player.global_position)
		if next<distance and visible_between(player.global_position,resident.global_position):
			distance = next
			result = resident
	return result

func converse(a: CharacterBody3D, b: CharacterBody3D) -> void:
	var place := place_name(nearest_id(a.global_position))
	for pair: Array in [[a,b],[b,a]]:
		pair[0].wait = maxf(pair[0].wait,5.5)
		pair[0].state = "chatting"
		pair[0].social_cooldown = 28
		pair[0].partner_id = pair[1].profile.id
		pair[0].last_meeting = place
		pair[0].conversations += 1
		pair[0].face(pair[1].global_position,1)
	a.say("%s! How is your route today?" % b.profile.name,2.6)
	b.reply = "Quiet near %s. I'll catch you here later." % place_name(b.goal)
	if a.profile.attitude=="dismissive" and b.profile.attitude in ["curious","friendly"] and a.global_position.distance_to(player.global_position)<12 and visible_between(a.global_position,player.global_position):
		a.say("Another human. Doesn't that bother you, %s?" % b.profile.name,2.6)
		b.reply = "They haven't stopped me from finishing my day."
	b.reply_time = 2.9
	social_events += 1

func _physics_process(delta: float) -> void:
	if not ready_for_visitors: return
	elapsed += delta
	_service_time += delta
	_spatial_time -= delta
	if _spatial_time<=0:
		_spatial_time = 0.2
		rebuild_neighbours()
	speaker_time = maxf(0,speaker_time-delta)
	_clock -= delta
	var attacking: bool = not player.weapon_combat.active_move.is_empty()
	var fresh_attack := attacking and not _last_attack
	_last_attack = attacking
	if _clock>0 and not fresh_attack: return
	_clock = 0.25
	service_indoors(_service_time)
	_service_time = 0
	# Read visible world actions, never player input requests or hidden decisions.
	var partner_attacking: bool = duel.active and not duel.partner.weapon_combat.active_move.is_empty()
	var fighter: CharacterBody3D = player if attacking else (duel.partner if partner_attacking else null)
	if is_instance_valid(fighter):
		for resident: CharacterBody3D in active_residents:
			if resident.transit!=&"outdoor": continue
			if resident.global_position.distance_to(fighter.global_position)<7 and visible_between(resident.global_position,fighter.global_position):
				if resident.reaction_cooldown<=0: observed_events += 1
				resident.react_to_fight(fighter.global_position)
	for a: CharacterBody3D in active_residents:
		if a.transit!=&"outdoor": continue
		if a.social_cooldown>0 or a.reaction_time>0 or a.state=="talking": continue
		for id: StringName in a.profile.contacts:
			var b: CharacterBody3D = by_id.get(id)
			if not is_instance_valid(b) or not b.active or b.transit!=&"outdoor" or b.social_cooldown>0 or b.reaction_time>0 or b.state=="talking": continue
			if a.global_position.distance_to(b.global_position)<2.6 and visible_between(a.global_position,b.global_position):
				converse(a,b)
				return # Stagger ambient exchanges rather than a chorus each tick.
