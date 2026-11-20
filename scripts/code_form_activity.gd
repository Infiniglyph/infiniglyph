extends Node
## Full bodies and frequent decisions live near the player; distant identities
## keep their persistent records and a small round-robin background budget.
const PEOPLE_RADIUS:=128.0
const PEOPLE_RETIRE:=160.0
const VEHICLE_RADIUS:=192.0
const VEHICLE_RETIRE:=240.0
const AI_RADIUS:=160.0
const SCENERY_RADIUS:=384.0
const BACKGROUND_BUDGET:=2
const CELL_SIZE:=128.0
const INDEX_INTERVAL:=5.0
const JOURNEY_PADDING:=40.0 # Unloaded traffic moves 7 m/s; people are slower.
var world: Node3D
var enabled:=true
var local_ids: Array[String]=[]
var _local: Dictionary={}
var _clock:=0.0
var _last_origin:=Vector3.INF
var _serial:=-1
var _count:=-1
var _was_outside:=false
var scenery_count:=0
var index_rebuilds:=0
var _index_clock:=0.0
var _cells: Dictionary={}

func _ready() -> void:
	name="CodeFormActivity"
	apply_scenery_ranges()

func outside() -> bool:
	var travel: Node=world.get("dungeon_travel")
	return not is_instance_valid(travel) or travel.active_location==travel.OUTSIDE

func motion() -> Vector3:
	var actions: Node=world.get("world_actions")
	if is_instance_valid(actions) and is_instance_valid(actions.vehicle): return actions.vehicle.velocity
	return world.player.velocity

static func predictive_distance_squared(point: Vector3,origin: Vector3,velocity: Vector3) -> float:
	# A short swept sphere leads driving, Sky Jump and falling in all 3 axes.
	var lead:=velocity.limit_length(64.0)*1.5
	var length_sq:=lead.length_squared()
	if length_sq<.001: return point.distance_squared_to(origin)
	var t:=clampf((point-origin).dot(lead)/length_sq,0,1)
	return point.distance_squared_to(origin+lead*t)

func distance_squared(point: Vector3) -> float:
	if not outside(): return INF
	return predictive_distance_squared(point,world.player.global_position,motion())

func contains(point: Vector3,radius: float=PEOPLE_RADIUS) -> bool:
	return not enabled or distance_squared(point)<=radius*radius

func refresh(force: bool=false) -> void:
	var society: Node=world.get("civilization")
	if not is_instance_valid(society) or not society.ready_for_simulation: return
	var origin: Vector3=world.player.global_position
	var serial: int=society.registry.replacement_serial
	var count: int=society.registry.slots.size()
	var outdoors:=outside()
	if not force and _clock>0 and origin.distance_squared_to(_last_origin)<256 and _serial==serial and _count==count and outdoors==_was_outside: return
	var rebuild:=force or _index_clock<=0 or _serial!=serial or _count!=count
	_clock=1.0; _last_origin=origin; _serial=serial; _count=count
	_was_outside=outdoors
	_local.clear(); local_ids.clear()
	if not enabled or not outside(): return
	var velocity:=motion()
	if rebuild:
		_cells.clear(); _index_clock=INDEX_INTERVAL; index_rebuilds+=1
		for id: String in society.registry.active_ids():
			var point: Vector3=society.autonomy.simulation_position(id)
			if not point.is_finite(): continue
			var key:=Vector3i((point/CELL_SIZE).floor())
			if not _cells.has(key): _cells[key]=[]
			_cells[key].append(id)
	# Query only intersecting 3D cells. Padding covers coarse journey motion
	# between rebuilds; candidate positions are always checked live below.
	var ahead:=origin+velocity.limit_length(64.0)*1.5
	var padding:=Vector3.ONE*(AI_RADIUS+JOURNEY_PADDING)
	var low:=Vector3i(((origin.min(ahead)-padding)/CELL_SIZE).floor())
	var high:=Vector3i(((origin.max(ahead)+padding)/CELL_SIZE).floor())
	var candidates: Dictionary={}
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			for z in range(low.z,high.z+1):
				for id: String in _cells.get(Vector3i(x,y,z),[]): candidates[id]=true
	# Live bodies can be pushed, boosted or respawned faster than coarse route
	# records. Include the bounded loaded pools regardless of their old cell.
	var population: Node=world.get("population")
	if is_instance_valid(population):
		for source: Node in population.active_residents:
			var id:=String(source.get_meta("code_form_id",""))
			if not id.is_empty(): candidates[id]=true
	var life: Node=world.get("district_life")
	if is_instance_valid(life):
		for source: Node in life.people.values():
			var id:=String(source.record.get("code_form_id",""))
			if not id.is_empty(): candidates[id]=true
		for vehicle: Node in life.vehicles.values():
			var id:=String(vehicle.record.driver.get("code_form_id",""))
			if not id.is_empty(): candidates[id]=true
	for id: String in candidates:
		if not society.registry.records.get(id,{}).get("active",false): continue
		if predictive_distance_squared(society.autonomy.simulation_position(id),origin,velocity)<=AI_RADIUS*AI_RADIUS:
			local_ids.append(id); _local[id]=true
	local_ids.sort()

func is_local(id: String) -> bool:
	if not enabled: return true
	refresh()
	return outside() and _local.has(id)

func apply_scenery_ranges() -> void:
	scenery_count=0
	for visual: MeshInstance3D in get_tree().get_nodes_in_group("bubble_scenery"):
		# Bounds padding keeps entire roads/buildings visible while any part is
		# nearby. Engine-side range culling requires no scene walk each frame.
		visual.visibility_range_end=SCENERY_RADIUS+visual.get_aabb().size.length()*.5 if enabled else 0.0
		visual.visibility_range_end_margin=32.0 if enabled else 0.0
		scenery_count+=1

func _process(delta: float) -> void:
	_clock-=delta
	_index_clock-=delta
	refresh()
