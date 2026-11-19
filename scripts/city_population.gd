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
var reactions: Node3D
var duel: CanvasLayer
var residents: Array[CharacterBody3D] = []
var reserved_outdoors := 0 # Street-combat proxies reserve their civilian slot.
var active_residents: Array[CharacterBody3D] = []
var entrances: Dictionary = {}
var public_places: Array[StringName] = []
var neighborhood_places: Dictionary = {}
var place_neighborhood: Dictionary = {}
var outer_neighborhoods: Array[StringName] = []
var initial_street_residents: Dictionary = {}
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
@export var simulation_lod_enabled := true
@export var physical_range := 140.0
var virtual_count := 0
var _floor_query := PhysicsRayQueryParameters3D.new()
var _clear_query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	name = "CityPopulation"
	_capsule.radius = 0.34
	_capsule.height = 1.9
	_floor_query.collision_mask = 1
	_floor_query.exclude = [player.get_rid(),duel.partner.get_rid()]
	_clear_query.shape = _capsule
	_clear_query.collision_mask = 1
	_clear_query.exclude = [player.get_rid(),duel.partner.get_rid()]
	_clear_query.margin = 0.01
	# Physics must have registered every existing building before validating paths.
	call_deferred("build")

func floor_at(at: Vector3) -> Dictionary:
	_floor_query.from = at+Vector3.UP*0.55
	_floor_query.to = at-Vector3.UP*0.65
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	if hit.is_empty() or hit.normal.y<0.8 or hit.collider is CharacterBody3D: return {}
	return {"point":hit.position+Vector3.UP*0.045}

func clear_at(at: Vector3) -> bool:
	_clear_query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*0.96)
	return get_world_3d().direct_space_state.intersect_shape(_clear_query,1).is_empty()

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
	place_neighborhood[id] = &"hub"
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
	build_quiet_streets()
	build_outer_neighborhoods()
	public_places.assign(points.keys())
	for id: StringName in public_places:
		var neighborhood: StringName = place_neighborhood[id]
		if not neighborhood_places.has(neighborhood): neighborhood_places[neighborhood] = []
		neighborhood_places[neighborhood].append(id)
	for door: Node3D in get_tree().get_nodes_in_group("resident_entrances"):
		var at: Vector3 = door.outside()
		var candidates: Array = points.keys()
		candidates.sort_custom(func(a: StringName,b: StringName): return points[a].distance_squared_to(at)<points[b].distance_squared_to(at))
		var links: Array[StringName] = []
		for candidate: StringName in candidates:
			if place_neighborhood[candidate]!=&"hub": continue
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
	var startup_budget := maxi(0,mini(max_outdoors,initial_outdoors))
	# These residents have street-side routines in the wider city. Their small,
	# independent networks never route through a locked progression gate or back
	# to a hub-only lobby. Identities, contacts and combat remain on the same body.
	var relocated := mini(32,mini(startup_budget,maxi(0,profiles.size()-18))) if not outer_neighborhoods.is_empty() else 0
	var relocated_start := profiles.size()-relocated
	for i in range(profiles.size()):
		var resident := Resident.new()
		resident.population = self
		resident.profile = profiles[i]
		resident.profile["serial"] = i
		resident.profile["color_name"] = colors[i%colors.size()]
		resident.profile["tint"] = Profiles.PALETTE[colors[i%colors.size()]]*rng.randf_range(0.87,1)
		if i>=relocated_start:
			var district: StringName = outer_neighborhoods[((i-relocated_start)/2)%outer_neighborhoods.size()]
			var stops: Array = neighborhood_places[district]
			var home: StringName = stops[(i-relocated_start)%stops.size()]
			resident.profile["neighborhood"] = district
			resident.profile.home = home
			resident.profile.routine = [stops[(i+2)%stops.size()],stops[(i+5)%stops.size()],home]
			resident.profile.meeting = stops[0]
		resident.home_building = homes[(i*7)%homes.size()]
		resident.indoor_left = 0.5 if resident.profile.has("neighborhood") else rng.randf_range(3,65)
		resident.position = entrances[resident.home_building].concealed()
		add_child(resident)
		residents.append(resident)
		by_id[resident.profile.id] = resident
	# Give relocated identities real outdoor routes from startup. They replace
	# hub street slots rather than increasing the total outdoor population budget.
	for i in range(relocated_start,residents.size()):
		spawn_on_street(residents[i],residents[i].profile.neighborhood)
	for i in range(mini(relocated_start,maxi(0,startup_budget-active_residents.size()))):
		spawn_on_street(residents[i],&"hub")
	advance_simulation_lod(0)
	rebuild_neighbours()
	ready_for_visitors = true

func build_quiet_streets() -> void:
	# Ground-level perimeter streets already exist behind the skyline. They
	# spread hub errands beyond the tutorial plaza without changing architecture.
	for side: String in ["west","east"]:
		var sign_x := -1.0 if side=="west" else 1.0
		var approach := StringName(side+"_quiet_approach")
		node_at(approach,Vector3(sign_x*68.5,0,16),"the outer avenue")
		connect_places(StringName(side+"_outer"),approach)
		var previous: StringName
		for z in [-104,-72,-40,-8,16,48,80,104]:
			var id := StringName(side+"_quiet_"+str(z))
			node_at(id,Vector3(sign_x*102,0,z),"the outer promenade")
			if previous!=&"": connect_places(previous,id)
			if z==16: connect_places(approach,id)
			previous = id
		var north := StringName(side+"_quiet_north")
		node_at(north,Vector3(sign_x*14,0,-104),"the northern cross street")
		connect_places(StringName(side+"_inner_north"),north)
		connect_places(north,StringName(side+"_quiet_-104"))
		var south := StringName(side+"_quiet_south")
		node_at(south,Vector3(sign_x*3.5,0,104),"the south avenue")
		connect_places(&"south_w" if side=="west" else &"south_e",south)
		connect_places(south,StringName(side+"_quiet_104"))
	connect_places(&"west_quiet_north",&"east_quiet_north")
	connect_places(&"west_quiet_south",&"east_quiet_south")

func build_outer_neighborhoods() -> void:
	if get_parent().get_node_or_null("WiderWorld")==null: return
	# Walk the existing 64 m city block pavements. Independent neighborhoods
	# preserve the actual closed road gates; residents do not teleport across them.
	for base: Vector2 in [Vector2(-320,-192),Vector2(-320,128),Vector2(-128,256),Vector2(128,256),Vector2(256,128),Vector2(256,-192),Vector2(128,-320),Vector2(-128,-320)]:
		var neighborhood := StringName("city_%d_%d" % [int(base.x),int(base.y)])
		var route_points: Array[Vector3] = []
		for offset: Vector2 in [Vector2(10,10),Vector2(32,10),Vector2(54,10),Vector2(54,32),Vector2(54,54),Vector2(32,54),Vector2(10,54),Vector2(10,32)]:
			route_points.append(Vector3(base.x+offset.x,0,base.y+offset.y))
		var valid := true
		for i in range(route_points.size()):
			if not segment_clear(route_points[i],route_points[(i+1)%route_points.size()]): valid = false
		if not valid:
			push_warning("No clear resident circuit in outer block "+String(neighborhood))
			continue
		for i in range(route_points.size()):
			var id := StringName(String(neighborhood)+"_"+str(i))
			node_at(id,route_points[i],"the outer city streets")
			place_neighborhood[id] = neighborhood
			if i>0: connect_places(StringName(String(neighborhood)+"_"+str(i-1)),id)
		connect_places(StringName(String(neighborhood)+"_7"),StringName(String(neighborhood)+"_0"))
		outer_neighborhoods.append(neighborhood)

func spawn_on_street(resident: CharacterBody3D, neighborhood: StringName, concealed_only: bool = false) -> bool:
	var options: Array[Vector2i] = []
	for edge: Vector2i in edges:
		var at := graph.get_point_position(edge.x).lerp(graph.get_point_position(edge.y),0.5)
		if place_neighborhood[nearest_id(at)]!=neighborhood: continue
		# Startup errands leave the plaza clear for the tutorial's existing actors.
		if neighborhood==&"hub" and Vector2(at.x,at.z).length()<35: continue
		options.append(edge)
	if options.is_empty(): return false
	for attempt in range(80):
		var edge := options[rng.randi_range(0,options.size()-1)]
		var at := graph.get_point_position(edge.x).lerp(graph.get_point_position(edge.y),rng.randf_range(0.12,0.88))
		var floor := floor_at(at)
		if floor.is_empty() or not clear_at(floor.point): continue
		if concealed_only and not hidden_from_player(floor.point): continue
		if not spawn_space_free(resident,floor.point): continue
		var crowded := at.distance_to(player.position)<2
		for other: CharacterBody3D in active_residents:
			if other.position.distance_to(at)<2: crowded = true
		if crowded: continue
		resident.activate(floor.point)
		if not concealed_only: initial_street_residents[resident.profile.id] = true
		resident.wait = rng.randf_range(0.1,3)
		return true
	return false

func rebuild_neighbours() -> void:
	var buckets: Dictionary = {}
	for resident: CharacterBody3D in active_residents:
		if resident.virtualized: continue
		var cell := Vector2i(floori(resident.position.x/4),floori(resident.position.z/4))
		if not buckets.has(cell): buckets[cell] = []
		buckets[cell].append(resident)
	for resident: CharacterBody3D in active_residents:
		resident.neighbours.clear()
		if resident.virtualized: continue
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
	var neighborhood: StringName = place_neighborhood[nearest_id(resident.position)]
	if neighborhood==&"hub" and resident.outdoor_stops>=resident.stops_before_indoor:
		var doors: Array = entrances.keys()
		doors.sort_custom(func(a: StringName,b: StringName): return points[a].distance_squared_to(resident.position)<points[b].distance_squared_to(resident.position))
		if rng.randf()<0.3 and goal_load(resident.home_building)<2: return resident.home_building
		for id: StringName in doors:
			if goal_load(id)<2: return id
	var choices: Array = neighborhood_places.get(neighborhood,public_places).duplicate()
	choices.sort_custom(func(a: StringName,b: StringName): return points[a].distance_squared_to(resident.position)<points[b].distance_squared_to(resident.position))
	var candidates: Array[StringName] = []
	for id: StringName in choices:
		if id==resident.goal or goal_load(id)>=3: continue
		if points[id].distance_to(resident.position)<5: continue
		candidates.append(id)
		if candidates.size()==8: break
	# Personal routines still influence errands, without synchronizing the whole city.
	var personal: StringName = resident.profile.routine[rng.randi_range(0,2)]
	if rng.randf()<0.15 and points.has(personal) and place_neighborhood[personal]==neighborhood and goal_load(personal)<3: return personal
	return candidates[rng.randi_range(0,candidates.size()-1)] if not candidates.is_empty() else nearest_id(resident.position)

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
	if not resident.virtualized and not hidden_from_player(resident.global_position): return false
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
	query.collision_mask = 13
	query.exclude = [resident.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func service_indoors(delta: float) -> void:
	var start := _indoor_cursor
	_indoor_cursor = (_indoor_cursor+1)%residents.size()
	var pending_street_slots := 0
	var waiting: Array[CharacterBody3D] = []
	for resident: CharacterBody3D in residents:
		if not resident.active and resident.profile.has("neighborhood") and not is_inf(resident.indoor_left): pending_street_slots += 1
	for offset in range(residents.size()):
		var index := (start+offset)%residents.size()
		var resident: CharacterBody3D = residents[index]
		if resident.active: continue
		resident.indoor_left -= delta
		if resident.indoor_left<=0: waiting.append(resident)
	# Longer perimeter walks must not let a few returners repeatedly take the
	# available hub slots while other identities never get an outdoor turn.
	waiting.sort_custom(func(a: CharacterBody3D,b: CharacterBody3D):
		var a_turns: int = a.exits+(1 if initial_street_residents.has(a.profile.id) else 0)
		var b_turns: int = b.exits+(1 if initial_street_residents.has(b.profile.id) else 0)
		if a_turns!=b_turns: return a_turns<b_turns
		return (int(a.profile.serial)-start+residents.size())%residents.size()<(int(b.profile.serial)-start+residents.size())%residents.size())
	for resident: CharacterBody3D in waiting:
		if active_residents.size()+reserved_outdoors>=max_outdoors: continue
		if resident.profile.has("neighborhood"):
			# A blocked startup placement retries its own streets out of view.
			# Combat suspensions use INF and remain owned by the combat adapter.
			if spawn_on_street(resident,resident.profile.neighborhood,true): pending_street_slots -= 1
			else: resident.indoor_left = 1.0
			continue
		# A delayed street placement keeps its slot; a lobby exit must not take
		# that last space and leave the outer identity waiting indefinitely.
		if active_residents.size()+reserved_outdoors+pending_street_slots>=max_outdoors: continue
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
		var distance_from_player := resident.global_position-player.global_position
		if simulation_lod_enabled and Vector2(distance_from_player.x,distance_from_player.z).length()>physical_range+160:
			resident.set_virtualized(true)
		_indoor_cursor = (int(resident.profile.serial)+1)%residents.size()

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

func route(at: Vector3, destination: StringName, virtual: bool = false) -> PackedVector3Array:
	if not points.has(destination): return PackedVector3Array()
	if virtual: return graph.get_point_path(point_ids[nearest_id(at)],point_ids[destination])
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
	var passing := false
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
				passing = true
	var away := resident.global_position-player.global_position
	away.y = 0
	if absf(resident.global_position.y-player.global_position.y)<1.8 and away.length()<1.7:
		if away.length()<0.05: away = Vector3.RIGHT
		result += away.normalized()*(1.7-away.length())*2.5
		if requested.length()>0.1 and requested.normalized().dot(-away.normalized())>0.2: passing = true
	# One passing bias, regardless of crowd size. Summing it per neighbour
	# creates a persistent tangential force around occupied waypoints.
	if passing: result += Vector3(requested.z,0,-requested.x).normalized()*0.85
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
		if resident.virtualized: continue
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
	advance_simulation_lod(_service_time)
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

func advance_simulation_lod(delta: float) -> void:
	virtual_count = 0
	# Activation leads fast travel; vertical Sky Jump height cannot retire the
	# people directly beneath the player. Hysteresis avoids boundary churn.
	var range_now := physical_range+minf(120,Vector2(player.velocity.x,player.velocity.z).length()*0.75)
	for resident: CharacterBody3D in active_residents.duplicate():
		var offset := resident.global_position-player.global_position
		var distance := Vector2(offset.x,offset.z).length()
		var protected: bool = resident.state=="talking" or resident.reaction_time>0 or resident.is_in_group("combat_targets")
		if not simulation_lod_enabled or protected or distance<range_now:
			resident.set_virtualized(false)
		elif distance>range_now+40: resident.set_virtualized(true)
		if resident.virtualized:
			virtual_count += 1
			resident.advance_virtual(delta)
