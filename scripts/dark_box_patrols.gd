extends Node3D
## Law cases are dispatch reports, never a second wanted/crime implementation.
## Drivers and car partners are existing census members; no extra inhabitants.
const Officer=preload("res://scripts/dark_box_officer.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Item=preload("res://scripts/item_instance.gd")
const MAX_UNITS:=4
const MAX_ISSUES:=8192
signal changed
var world: Node3D
var units: Dictionary={}
var fighters: Dictionary={}
var issued: Dictionary={}
var defeated_until: Dictionary={}
var ready_for_patrols:=false
var _clock:=0.0
var _busy:=false
var _owns_player_target:=false
var _player_grace:=0.0
var _reported:=Vector3(INF,INF,INF)
var _report_until:=0.0
var _reserved: Dictionary={}
var _route_cursor:=0
var _roster_clock:=0.0

func _ready() -> void:
	name="DarkBoxPatrols"
	changed.connect(world.inventory_session._dirty)
	world.law.case_recorded.connect(_case_reported)
	world.player.defeated.connect(_player_reset)
	world.player.respawned.connect(_player_reset)

func _now() -> float: return float(world.civilization.world_seconds)
func _registry() -> RefCounted: return world.civilization.registry
func _orgs() -> RefCounted: return world.quest_system.organizations
func _economy() -> Node: return world.civilian_services.economy
func transaction_active() -> bool: return _busy

func _available(id: String) -> bool:
	return _member(id) and float(defeated_until.get(id,0))<=_now()

func _member(id: String) -> bool:
	return _registry().records.get(id,{}).get("active",false) and _orgs().is_member(id,"dark_box")

func _issue(id: String) -> bool:
	if _busy: return false
	var store: Node=_economy().npc_store(id)
	if not is_instance_valid(store): return false
	_busy=true
	var wand: Resource
	for item: Resource in store.items.values():
		if item.item_type_id==&"dark_box_arc_wand": wand=item; break
	if wand==null:
		# Issue provenance survives sale, loss and reentry. Gear is never copied
		# from the combat proxy or replenished by reopening an encounter.
		if issued.has(id) or issued.size()>=MAX_ISSUES: _busy=false; return false
		wand=Catalog.create(&"dark_box_arc_wand")
		if wand==null or not store.add_item(wand): _busy=false; return false
		issued[id]=wand.instance_id
		changed.emit()
	elif not issued.has(id):
		issued[id]=wand.instance_id
		changed.emit()
	preload("res://scripts/code_form_wardrobe.gd").issue(store,world.civilization.autonomy._state(id),true)
	var equipped: bool=store.assign(&"up",wand.instance_id)
	_busy=false
	return equipped

func bootstrap() -> bool:
	if _busy or world.inventory_session._loading or world.inventory_session._checkpoint_pending or not world.civic_interactions.initialized or not world.district_life._built: return false
	var candidates: Array[Dictionary]=[]
	var partners: Array[Dictionary]=[]
	for record: Dictionary in world.district_life.vehicle_records:
		var id:=String(record.driver.get("code_form_id",""))
		if not _member(id): continue
		if record.traffic and record.kind in ["car","motorcycle"] and not record.taken: candidates.append(record)
		elif not record.traffic and not record.taken: partners.append(record)
	var counts:={"car":0,"motorcycle":0}
	for record: Dictionary in candidates:
		if units.size()>=MAX_UNITS: break
		if int(counts[record.kind])>=2: continue
		var id:=String(record.driver.code_form_id)
		if _reserved.has(id) or _has_pedestrian(id) or not _issue(id) and not issued.has(id): continue
		var members: Array[String]=[id]
		if record.kind=="car":
			for candidate: Dictionary in partners:
				var partner:=String(candidate.driver.code_form_id)
				if _reserved.has(partner) or _has_pedestrian(partner) or not _issue(partner) and not issued.has(partner): continue
				members.append(partner)
				break
			if members.size()!=2: continue
		for member: String in members: _reserved[member]=record.id
		units[int(record.id)]={"members":members,"deployed":false,"route":record.route.duplicate(),"record":record,"last_seen":0.0}
		counts[record.kind]+=1
	ready_for_patrols=true
	return true

func _has_pedestrian(id: String) -> bool:
	for record: Dictionary in world.district_life.resident_records:
		if record.get("code_form_id")==id: return true
	return false

func _profile(id: String) -> Dictionary:
	for record: Dictionary in world.district_life.vehicle_records:
		if record.driver.get("code_form_id")==id:
			var result: Dictionary=record.driver.duplicate(true)
			result.tint=Color("75eaff")
			return result
	return {}

func _case_reported(row: Dictionary) -> void:
	if row.get("offender")!="player" or row.get("witnesses",[]).is_empty(): return
	_reported=world.player.global_position
	_report_until=float(Time.get_ticks_msec())/1000.0+30

func _player_reset() -> void:
	_player_grace=15.0
	_reported=Vector3(INF,INF,INF)
	for id: String in fighters.keys(): finish_fighter(id)

func can_fight() -> bool:
	if _player_grace>0 or world.player.health<=0 or world.law.wanted_level("player")==0: return false
	if is_instance_valid(world.dungeon_travel) and world.dungeon_travel.active_location!=world.dungeon_travel.OUTSIDE: return false
	return world.theft_reactions.can_fight() if is_instance_valid(world.theft_reactions) else true

func _visible_from(vehicle: CharacterBody3D) -> bool:
	if vehicle.global_position.distance_to(world.player.global_position)>65: return false
	var ray:=PhysicsRayQueryParameters3D.create(vehicle.combat_point(),world.player.combat_point(),1,[vehicle.get_rid(),world.player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func deploy(vehicle: CharacterBody3D) -> bool:
	if not can_fight() or not units.has(int(vehicle.record.id)) or vehicle.health<=0 or is_instance_valid(vehicle.player_driver) or not vehicle.has_driver: return false
	var unit: Dictionary=units[int(vehicle.record.id)]
	if unit.deployed or vehicle.global_position.distance_to(world.player.global_position)>32 or not _visible_from(vehicle): return false
	var locations: Array[Vector3]=[]
	var excluded: Array[RID]=[vehicle.get_rid()]
	for index in range(unit.members.size()):
		var at: Vector3=vehicle.to_global(Vector3(-1.7 if index==0 else 1.7,.05,0))
		at.y=world.district_life.regions.surface_at(at.x,at.z)+.05
		if not world.district_life.pedestrian_clear(at,false,excluded): return false
		locations.append(at)
	for id: String in unit.members:
		if not _available(id) or not _issue(id): return false
	unit.deployed=true
	vehicle.record.patrol_deployed=true
	unit.last_seen=0.0
	vehicle.has_driver=false
	vehicle.set_npc_driving(false)
	vehicle.signed_speed=0
	for index in range(unit.members.size()):
		var id:=String(unit.members[index])
		var fighter:=Officer.new()
		fighter.identity=id
		fighter.profile=_profile(id)
		fighter.store=_economy().npc_store(id)
		fighter.reactions=self
		fighter.opponent=world.player
		fighter.spawn=locations[index]
		fighter.position=locations[index]
		world.add_environment(fighter)
		fighters[id]=fighter
		world.civilization.autonomy._regional_records[id]={"combat":true,"point":vehicle.global_position,"patrol":true}
		world.civilization.autonomy._sources[id]=weakref(fighter)
	_sync_player()
	return true

func finish_fighter(id: String,defeated: bool=false,expected: Node=null) -> void:
	var fighter: CharacterBody3D=fighters.get(id)
	if not is_instance_valid(fighter) or expected!=null and fighter!=expected: return
	if world.player.target_lock.opponent==fighter: world.player.target_lock.clear()
	defeated=defeated or fighter.dead or fighter.health<=0
	if defeated:
		defeated_until[id]=_now()+600.0
		if not fighter.has_meta("native_defeat"): world.civilization.autonomy.on_combat(fighter,"defeated")
		changed.emit()
	fighters.erase(id)
	world.civilization.autonomy._sources.erase(id)
	fighter.controls.stop()
	fighter.weapon_combat.cancel()
	fighter.set_physics_process(false)
	fighter.weapon_combat.set_physics_process(false)
	fighter.process_mode=Node.PROCESS_MODE_DISABLED
	fighter.detach_store()
	fighter.collision_layer=0
	fighter.hide()
	fighter.queue_free()
	_sync_player()

func _sync_player() -> void:
	if not fighters.is_empty():
		if not world.player.is_in_group("combat_targets"): _owns_player_target=true
		world.player.add_to_group("combat_targets")
		world.player.set_collision_layer_value(2,true)
	elif _owns_player_target:
		if not is_instance_valid(world.theft_reactions) or world.theft_reactions.fighters.is_empty():
			world.player.remove_from_group("combat_targets")
			world.player.set_collision_layer_value(2,false)
		_owns_player_target=false

func _dispatch_route(vehicle: CharacterBody3D,goal: Vector3) -> void:
	if not goal.is_finite() or maxf(absf(goal.x),absf(goal.z))>650: return
	var record: Dictionary=vehicle.record
	var start: Vector3=record.route[int(record.cursor)]
	var end:=Vector3(roundf((goal.x-3)/64)*64+3,0,roundf((goal.z-3)/64)*64+3)
	end.y=world.district_life.regions.surface_at(end.x,end.z)+.04
	# Both Manhattan alternatives stay on the city's established open road grid.
	# A bounded static sweep rejects a route through a house, tree or hub wall.
	for corner: Vector3 in [Vector3(end.x,start.y,start.z),Vector3(start.x,start.y,end.z)]:
		var route:=PackedVector3Array([start,corner,end,corner,start])
		var clear:=true
		var probe:=PhysicsShapeQueryParameters3D.new()
		var box:=BoxShape3D.new()
		box.size=Vector3(vehicle.dimensions.x+.2,vehicle.dimensions.y,vehicle.dimensions.x+.2)
		probe.shape=box; probe.collision_mask=1
		for index in range(2):
			var a:=route[index]
			var b:=route[index+1]
			var samples:=mini(64,maxi(1,ceili(a.distance_to(b)/16)))
			for sample in range(samples+1):
				var p:=a.lerp(b,float(sample)/samples)
				p.y=world.district_life.regions.surface_at(p.x,p.z)+vehicle.dimensions.y*.5+.1
				probe.transform=Transform3D(Basis.IDENTITY,p)
				if not get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty(): clear=false; break
			if not clear: break
		if clear:
			record.route=route
			record.cursor=0
			return

func _physics_process(delta: float) -> void:
	_player_grace=maxf(0,_player_grace-delta)
	if not ready_for_patrols:
		_clock+=delta
		if _clock>=1: _clock=0; bootstrap()
		return
	if world.inventory_session._loading or world.inventory_session._checkpoint_pending: return
	_roster_clock+=delta
	if _roster_clock>=30 and fighters.is_empty():
		_roster_clock=0
		prepare_restore()
		bootstrap()
		return
	_clock+=delta
	if _clock<.5: return
	_clock=0
	var engaged:=can_fight()
	for id: String in fighters.keys():
		var fighter: CharacterBody3D=fighters[id]
		if not engaged or not _available(id) or fighter.global_position.distance_to(world.player.global_position)>110: finish_fighter(id)
	var dispatch: int=-1
	var distance:=INF
	var wanted: int=world.law.wanted_level("player")
	var active_units:=0
	for unit: Dictionary in units.values():
		if unit.deployed: active_units+=1
	for key: int in units:
		var unit: Dictionary=units[key]
		var vehicle: CharacterBody3D=world.district_life.vehicles.get(key)
		if not is_instance_valid(vehicle): continue
		if not vehicle.patrol:
			var partner: Dictionary=_profile(String(unit.members[1])) if unit.members.size()==2 else {}
			vehicle.configure_patrol(partner)
		var alive:=true
		for id: String in unit.members:
			if not _available(id): alive=false
			world.civilization.autonomy._regional_records[id]={"combat":true,"point":vehicle.global_position,"patrol":true}
		if unit.deployed:
			vehicle.has_driver=false
			var present:=false
			for id: String in unit.members:
				if fighters.has(id): present=true
			if not present:
				unit.deployed=false
				vehicle.record.patrol_deployed=false
				vehicle.has_driver=alive and vehicle.health>0 and not vehicle.record.taken and not is_instance_valid(vehicle.player_driver)
			continue
		if not alive or vehicle.health<=0 or is_instance_valid(vehicle.player_driver) or vehicle.record.taken:
			if not is_instance_valid(vehicle.player_driver): vehicle.has_driver=false
			vehicle.set_npc_driving(false)
			continue
		vehicle.has_driver=true
		if engaged and _visible_from(vehicle):
			_reported=world.player.global_position; _report_until=float(Time.get_ticks_msec())/1000.0+12
			if active_units<mini(3,1+wanted/2) and deploy(vehicle): active_units+=1; continue
		var reported:=engaged and _reported.is_finite() and float(Time.get_ticks_msec())/1000.0<_report_until
		var route: PackedVector3Array=vehicle.record.route
		var offset: Vector3=route[int(vehicle.record.cursor)]-vehicle.global_position
		var straight: bool=absf(wrapf(atan2(offset.x,offset.z)-vehicle.rotation.y,-PI,PI))<.12 and offset.length()>32 and not vehicle._blocked
		var behind: Vector3=world.player.global_position-vehicle.global_position
		var trail: bool=engaged and wanted>=3 and _visible_from(vehicle) and behind.dot(vehicle.global_basis.z)<-3 and behind.length()<22
		vehicle.set_npc_driving(straight and reported,trail)
		var d:=vehicle.global_position.distance_squared_to(_reported) if reported else INF
		if reported and d<distance: distance=d; dispatch=key
	if dispatch>=0:
		_route_cursor+=1
		if _route_cursor%4==0: _dispatch_route(world.district_life.vehicles[dispatch],_reported)
	_sync_player()

func serialize() -> Dictionary:
	return {"version":1,"issued":issued.duplicate(),"defeated_until":defeated_until.duplicate()}

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=3 or input.get("version")!=1 or not input.get("issued") is Dictionary or not input.get("defeated_until") is Dictionary or input.issued.size()>MAX_ISSUES or input.defeated_until.size()>MAX_ISSUES: return {}
	var seen: Dictionary={}
	for id: Variant in input.issued:
		if not Item.valid_text(id,false,128) or not Item.valid_text(input.issued[id],false,128) or seen.has(input.issued[id]): return {}
		seen[input.issued[id]]=true
	for id: Variant in input.defeated_until:
		var time: Variant=input.defeated_until[id]
		if not Item.valid_text(id,false,128) or not input.issued.has(id) or not (time is int or time is float) or not is_finite(float(time)) or float(time)<0 or float(time)>1e15: return {}
	return input.duplicate(true)

func restore(input: Variant) -> bool:
	if _busy: return false
	var clean: Dictionary={"version":1,"issued":{},"defeated_until":{}} if input==null else validate(input)
	if clean.is_empty(): return false
	prepare_restore()
	_busy=true
	issued=clean.issued
	defeated_until=clean.defeated_until
	ready_for_patrols=false
	_busy=false
	return true

func prepare_restore() -> void:
	# Economy.restore replaces store Nodes. Release the live combat users and
	# their signals synchronously before that swap; provenance stays untouched.
	for id: String in fighters.keys(): finish_fighter(id)
	for unit: Dictionary in units.values():
		var record: Dictionary=unit.record
		record.patrol_deployed=false
		# Keep the current validated road loop/cursor. A direct return to the
		# original block from an arbitrary dispatch point could cut through homes.
		var vehicle: CharacterBody3D=world.district_life.vehicles.get(int(record.id))
		if is_instance_valid(vehicle):
			vehicle.set_npc_driving(false)
			var available:=true
			for id: String in unit.members:
				if not _available(id): available=false
			vehicle.has_driver=available and record.traffic and not record.taken and vehicle.health>0 and not is_instance_valid(vehicle.player_driver)
			vehicle.clear_patrol()
	for id: String in _reserved:
		if world.civilization.autonomy._regional_records.get(id,{}).get("patrol",false): world.civilization.autonomy._regional_records.erase(id)
	units.clear(); _reserved.clear()
	ready_for_patrols=false
