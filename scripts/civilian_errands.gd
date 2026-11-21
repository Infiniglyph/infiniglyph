extends Node
## Local intention -> validated walk -> paid service -> owned item -> seated
## consumption. The existing regional walker moves every metre of the trip.
const Needs=preload("res://scripts/code_form_needs.gd")
const MAX_VISITS:=6
const MAX_DISTANCE:=96.0
var world: Node3D
var active: Dictionary={}
var meetings:=preload("res://scripts/civilian_meetings.gd").new()
var _work: Dictionary={}
var _supply_displays: Dictionary={}
var _clock:=0.0
var _cursor:=0
var _retry: Dictionary={}

func _ready() -> void: meetings.errands=self

func _autonomy(): return world.civilization.autonomy
func _economy(): return world.civilian_services.economy
func _now() -> float: return float(world.civilization.world_seconds)
func _outside() -> bool: return world.dungeon_travel.active_location==world.dungeon_travel.OUTSIDE

func describe(id: String) -> String:
	var visit: Dictionary=active.get(id,{})
	var meeting:=meetings.describe(id)
	if not meeting.is_empty(): return meeting
	match String(visit.get("phase","")):
		"counter": return "I'm going to the tavern for a meal and water."
		"shift": return "I'm helping at the tavern to earn my meal and water."
		"seat": return "I've bought my food. Now to find my seat."
		"eat": return "A meal and some water before I get back to work."
		"return": return "I've eaten. Time to get back to my plans."
	return ""

func _path(start: Vector3,door: Vector3) -> PackedVector3Array:
	# Keep probes strictly local and bounded. Failed routes remain failures;
	# no teleport, wall clipping, invisible purchase or global path flood.
	var y:=start.y
	var candidates: Array[Array]=[[start,door],[start,Vector3(start.x,y,door.z),door],[start,Vector3(door.x,y,start.z),door]]
	for x: float in [-26,-6]:
		candidates.append([start,Vector3(x,y,start.z),Vector3(x,y,door.z),door])
	for candidate: Array in candidates:
		var typed: Array[Vector3]=[]; typed.assign(candidate)
		var route: PackedVector3Array=world.career_commute._clean_path(typed)
		if world.career_commute._walkable(route): return route
	return PackedVector3Array()

func consider(id: String) -> bool:
	if active.has(id) or meetings.reserved.has(id): return true
	if active.size()>=MAX_VISITS or not _outside() or not world.civic_interactions.initialized or float(_retry.get(id,0))>_now(): return false
	var record: Dictionary=_autonomy()._regional_records.get(id,{})
	if record.is_empty() or not record.get("valid",false) or record.get("combat",false) or record.has("career_commute") or record.get("wonders_route",false) or _autonomy()._unavailable(id): return false
	var state: Dictionary=_autonomy()._state(id)
	var needs:=maxf(float(state.hunger),float(state.thirst))
	if needs<.5: return meetings.consider(id)
	var establishment: Node3D=world.civilian_services.establishments
	var door: Vector3=establishment.tavern_entry.global_position
	var start: Vector3=record.point
	if start.distance_to(door)>MAX_DISTANCE: return false
	_retry[id]=_now()+20*_autonomy()._scale()
	var approach:=_path(start,door)
	if approach.is_empty(): return false
	var counter: Vector3=establishment.tavern.to_global(Vector3(0,.16,-2.5))
	var indoor_points: Array[Vector3]=[door,counter]
	var inside: PackedVector3Array=world.career_commute._clean_path(indoor_points)
	if not world.career_commute._walkable(inside): return false
	var seat: Dictionary={}
	var chair_path:=PackedVector3Array()
	for chair: Dictionary in establishment.seats:
		if not String(chair.id).begins_with("tavern_table") or is_instance_valid(chair.get("occupant")): continue
		var target: Vector3=chair.point+chair.forward.cross(Vector3.UP)*.85
		target.y=.16
		for candidate: Array in [[counter,target],[counter,Vector3(target.x,.16,counter.z),target],[counter,Vector3(counter.x,.16,target.z),target]]:
			var typed: Array[Vector3]=[]; typed.assign(candidate)
			var path: PackedVector3Array=world.career_commute._clean_path(typed)
			if world.career_commute._walkable(path): chair_path=path; break
		if not chair_path.is_empty(): seat=chair; break
	if seat.is_empty(): return false
	var outbound:=approach.duplicate()
	for i in range(1,inside.size()): outbound.append(inside[i])
	var counter_index:=outbound.size()-1
	for i in range(1,chair_path.size()): outbound.append(chair_path[i])
	var route:=outbound.duplicate()
	for i in range(outbound.size()-2,-1,-1): route.append(outbound[i])
	var return_index:=route.size()-1
	var base: PackedVector3Array=record.route.duplicate()
	var cursor:=int(record.cursor)
	for i in range(base.size()): route.append(base[(cursor+i)%base.size()])
	seat.occupant=self # The reservation survives streaming the visitor body out.
	active[id]={"identity":id,"record":record,"phase":"counter","seat":seat,"counter_index":counter_index,"seat_index":outbound.size()-1,"return_index":return_index,"base_route":base,"base_cursor":cursor,"remaining":0.0,"types":[],"began":_now()}
	record.route=route; record.cursor=1; record.wait=0.0; record.checked=true
	world.civilization.registry.set_goal(id,"eat" if state.hunger>=state.thirst else "drink","tavern")
	return true

func on_arrival(record: Dictionary) -> bool:
	if meetings.on_arrival(record): return true
	var id:=String(record.get("code_form_id",""))
	var visit: Dictionary=active.get(id,{})
	if visit.is_empty(): return false
	var cursor:=int(record.cursor)
	if cursor==int(visit.counter_index) and visit.phase=="counter": _at_counter(visit)
	elif cursor==int(visit.seat_index) and visit.phase=="seat":
		visit.phase="eat"; visit.remaining=4.0
		record.wait=5.0
		_present(id,"Enjoying a meal and water.",true)
	elif cursor==int(visit.return_index): call_deferred("_finish",id)
	return true

func _at_counter(visit: Dictionary) -> void:
	var id:=String(visit.identity)
	var state: Dictionary=_autonomy()._state(id)
	var store: Node=_economy().npc_store(id)
	var types: Array[StringName]=[]
	if state.hunger>=.5: types.append(&"electron_meal")
	if state.thirst>=.5: types.append(&"electron_draught")
	var price:=0
	for type: StringName in types:
		if store.count_type(type)==0: price+=int(_economy().food_offer(type).price)
	if _economy().balance("resident:"+id)<price:
		visit.phase="shift"; visit.remaining=15.0; visit.record.wait=16.0
		_present(id,"Helping at the tavern to earn my next meal.")
		return
	visit.types.clear()
	for type: StringName in types:
		if store.count_type(type)>0 or _economy().npc_buy_food(id,type): visit.types.append(type)
	if visit.types.is_empty():
		_return(visit,"The tavern could not fill my order. I need another plan.")
		return
	visit.phase="seat"; visit.record.wait=.2
	_present(id,"Bought my food. I'll sit down to eat.")
	world.civilization.registry.remember(id,"errand","tavern_purchase","Walked to the tavern and bought my own food and water.",.5)

func _present(id: String,line: String,sitting: bool=false) -> void:
	var source: Node=_autonomy()._source(id)
	if not is_instance_valid(source): return
	source.state=line
	if is_instance_valid(source.get("caption")): source.caption.text=line
	if source.get("record") is Dictionary: source.record.meetings=maxi(1,int(source.record.get("meetings",0)))
	if is_instance_valid(source.get("visual")):
		source.visual.sitting=sitting
		source.visual.activity="meal" if sitting else "work" if active[id].phase=="shift" else "parcel" if active[id].phase=="seat" else ""
		if sitting:
			var chair: Dictionary=active[id].seat
			source.visual.position=chair.point-Vector3.UP*.946-source.global_position
			source.visual.rotation.y=atan2(chair.forward.x,chair.forward.z)

func _return(visit: Dictionary,reason: String="") -> void:
	var id:=String(visit.identity)
	visit.phase="return"; visit.record.wait=.25
	var source: Node=_autonomy()._source(id)
	if is_instance_valid(source) and is_instance_valid(source.get("visual")):
		source.visual.sitting=false; source.visual.position=Vector3.ZERO; source.visual.activity=""
	visit.seat.occupant=null
	if not reason.is_empty(): world.civilization.registry.remember(id,"errand","tavern",reason,.6)

func _finish(id: String) -> void:
	var visit: Dictionary=active.get(id,{})
	if visit.is_empty(): return
	_return(visit)
	visit.record.route=visit.base_route
	visit.record.cursor=int(visit.base_cursor)
	active.erase(id)
	_retry[id]=_now()+30*_autonomy()._scale()

func clear() -> void:
	meetings.clear()
	for id: String in active.keys(): _return(active[id])
	_retry.clear()

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.25 or not world.civilization.ready_for_simulation or world.inventory_session._loading or world.inventory_session._checkpoint_pending: return
	var elapsed:=_clock; _clock=0
	meetings.process(elapsed)
	_process_work(elapsed)
	_update_supplies()
	# Nearby visible needs get attention promptly; distant brains retain their
	# existing bounded scheduler. No entire census or global path search here.
	if _outside() and not _autonomy()._sources.is_empty():
		var ids: Array=_autonomy()._sources.keys()
		for i in range(mini(2,ids.size())):
			var id:=String(ids[_cursor%ids.size()]); _cursor+=1
			var source: Node=_autonomy()._source(id)
			if is_instance_valid(source) and source.global_position.distance_to(world.player.global_position)<48:
				_refresh_parcel(id,source)
				consider(id)
	for id: String in active.keys():
		var visit: Dictionary=active[id]
		if _autonomy()._unavailable(id):
			_return(visit,"My tavern visit was interrupted.")
			continue
		if visit.phase not in ["shift","eat"]: continue
		visit.remaining=maxf(0,float(visit.remaining)-elapsed)
		visit.record.wait=1.0
		var body: Node=_autonomy()._source(id)
		if is_instance_valid(body): body.wait=1.0
		if visit.remaining>0: continue
		if visit.phase=="shift":
			var serial:=floori(_now()/(_autonomy()._day()*.5))
			if _economy().npc_service_wage(id,"tavern_work",serial,20):
				world.civilization.registry.remember(id,"work","tavern_shift","Helped at the tavern and earned coins for food and water.",.6)
				_at_counter(visit)
			else:
				_return(visit,"The tavern had no funded work available. I will look for a contract.")
				world.civilization.registry.set_goal(id,"work","")
		else:
			for type: StringName in visit.types: _economy().npc_consume_food(id,type)
			_return(visit,"A real visit: worked when needed, paid for my meal, sat down and ate.")

func show_work(id: String,action: String) -> void:
	var source: Node=_autonomy()._source(id)
	if not is_instance_valid(source) or not source.is_visible_in_tree() or not is_instance_valid(source.get("visual")) or source.visual.get("activity")==null or active.has(id): return
	_work[id]={"source":weakref(source),"remaining":3.0}
	source.visual.activity="work"
	source.wait=3.0
	if source.get("record") is Dictionary: source.record.wait=3.0; source.record.meetings=maxi(1,int(source.record.get("meetings",0)))
	if is_instance_valid(source.get("caption")): source.caption.text={"production":"Made a furnishing at my workbench.","food_preparation":"Prepared a meal at the cooking station.","delivery":"Delivery completed. The supplies are here."}.get(action,"Finished "+action.replace("_"," ")+".")

func _process_work(delta: float) -> void:
	for id: String in _work.keys():
		var row: Dictionary=_work[id]
		row.remaining=maxf(0,float(row.remaining)-delta)
		var source: Node=row.source.get_ref()
		if row.remaining>0 and not _autonomy()._unavailable(id): continue
		if is_instance_valid(source) and is_instance_valid(source.get("visual")): source.visual.activity=""
		_work.erase(id)

func _refresh_parcel(id: String,source: Node) -> void:
	if active.has(id) or _work.has(id) or not is_instance_valid(source.get("visual")) or source.visual.get("activity")==null: return
	var carrying:=false
	var store: Node=_economy().npc_stores.get(id)
	if is_instance_valid(store):
		for row: Dictionary in world.quest_system.for_participant(id,false):
			if row.kind=="delivery" and row.status=="active" and store.count_type(StringName(row.objective.item_type))>0: carrying=true; break
	source.visual.activity="parcel" if carrying else ""

func supply_arrived(id: String,type: StringName) -> void:
	if _supply_displays.has(id):
		_supply_displays[id].type=type
		return
	var anchor:=Vector3.INF
	var store: Node
	if id=="guild":
		anchor=world.civilian_services.establishments.guild_entry.global_position+Vector3(2,0,-3)
		store=_economy().guild_stock
	else:
		for business: Dictionary in world.careers.model.businesses.values():
			if business.status!="active" or business.owner!=id: continue
			var descriptor: Dictionary=world.building_civilization.descriptors.get(String(business.workplace),{})
			if not descriptor.is_empty(): anchor=descriptor.get("exit",descriptor.point)+Vector3(1,0,0); break
		store=_economy().npc_stores.get(id)
	if not anchor.is_finite() or not is_instance_valid(store) or _supply_displays.size()>=8: return
	var root:=Node3D.new(); root.name="ActualBusinessStock"
	world.add_environment(root); root.global_position=anchor
	var box:=MeshInstance3D.new(); var mesh:=BoxMesh.new(); mesh.size=Vector3(.42,.36,.42); box.mesh=mesh
	box.position.y=.18; box.material_override=preload("res://scripts/neon.gd").shared_material(Color(.24,.65,.85)); root.add_child(box)
	var label:=Label3D.new(); label.position.y=.75; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.pixel_size=.004; label.font_size=26
	root.add_child(label)
	_supply_displays[id]={"root":root,"label":label,"store":weakref(store),"type":type}

func _update_supplies() -> void:
	for id: String in _supply_displays.keys():
		var display: Dictionary=_supply_displays[id]
		var store: Node=display.store.get_ref()
		if not is_instance_valid(store): display.root.queue_free(); _supply_displays.erase(id); continue
		var count: int=store.count_type(display.type)
		display.root.visible=count>0 and _outside() and display.root.global_position.distance_to(world.player.global_position)<32
		display.label.text="%s stock: %d" % [preload("res://scripts/item_catalog.gd").get_definition(display.type).display_name,count]
