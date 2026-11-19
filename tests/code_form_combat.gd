extends SceneTree
## Real civilian bodies, driver handoff, combat respawn and active-proxy retirement.
const Registry=preload("res://scripts/code_form_registry.gd")
const Vehicle=preload("res://scripts/traffic_vehicle.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var checks:=0
var failures:=0
func _initialize() -> void:
	Engine.physics_ticks_per_second=60
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for index in range(count): await physics_frame; await process_frame

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Civilian combat verification watchdog"); quit(2))
	var world: Node3D=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	var society: Node=world.civilization
	society.simulation_enabled=false
	var actor: CharacterBody3D=world.player
	var intent:=Intent.new()
	root.add_child(intent)
	actor.controls=intent; world.camera_rig.controls=intent; world.inventory_session.controls=intent
	actor.visual.retrieval.enabled=false
	for index in range(300):
		await frames(1)
		if society.ready_for_simulation: break
	check(society.ready_for_simulation,"The real civilian census is ready before physical lifecycle tests")
	if not society.ready_for_simulation: quit(1); return
	var life: Node3D=world.district_life
	var population: Node3D=world.population
	var reactions: Node3D=world.theft_reactions
	life.set_physics_process(false); population.set_physics_process(false)
	for source: CharacterBody3D in population.residents: source.set_physics_process(false)
	for source: CharacterBody3D in life.people.values(): source.set_physics_process(false); source.set_process(false)
	for vehicle: CharacterBody3D in life.vehicles.values(): vehicle.set_physics_process(false)
	reactions.retaliation_enabled=false
	reactions.set_physics_process(false)
	actor.global_position=Vector3(194,.05,128); actor.velocity=Vector3.ZERO
	await frames(3)
	var vehicle:=Vehicle.new()
	vehicle.life=life
	vehicle.record=life.vehicle_records[0].duplicate(true)
	vehicle.record.point=Vector3(190,.04,128)
	vehicle.record.traffic=true; vehicle.record.taken=false
	life.add_child(vehicle)
	vehicle.set_physics_process(false)
	var driver_id: String=vehicle.record.driver.code_form_id
	var census: int=society.registry.active_ids().size()
	var driver: CharacterBody3D=life.eject_driver(vehicle,Vector3(192.8,.04,128))
	driver.set_physics_process(false)
	check(driver.code_form_id==driver_id and society.id_for_source(driver)==driver_id and driver.record.code_form_slot=="driver/0","An ejected driver retains the vehicle driver's persistent identity and slot")
	check(society.registry.active_ids().size()==census and not vehicle.has_driver,"Driver ejection creates no extra logical inhabitant or wallet")
	society.bind_sources()
	check(society.id_for_source(driver)==driver_id,"Rebinding source records preserves an ejected driver's identity")
	var source: CharacterBody3D=population.residents[0]
	var id: String=society.id_for_source(source)
	var person: Dictionary=society.registry.records[id]
	source.activate(Vector3(196,.04,131)); source.set_physics_process(false)
	person.respawn={"location":"overworld","position":[196.0,.04,131.0],"yaw":0.0}
	var life_before: float=society.registry.remaining_lifetime(id)
	var level_before: int=person.level
	var xp_before: int=person.experience
	var damage: float=reactions.receive_assault(source,2000,actor.combat_point(),actor,{"attack_serial":71})
	var key: String=reactions.key_for(source)
	var entry: Dictionary=reactions.entries[key]
	check(damage>0 and entry.dead and entry.suspended and source.indoor_left==INF,"Civilian combat death suspends its existing physical slot")
	check(society.registry.for_slot("hub/"+String(source.profile.id)).id==id and person.level==level_before and person.experience==xp_before and society.registry.remaining_lifetime(id)==life_before,"Combat death preserves the same identity, progression and lifetime")
	society.registry.set_goal(id,"work")
	var wallet: int=society.economy.balance("resident:"+id)
	var state: Dictionary=society.autonomy._state(id)
	check(not society.autonomy.perform_action(person,state,false) and society.economy.balance("resident:"+id)==wallet,"A dead/suspended civilian cannot earn hidden wages")
	check(reactions.restore_source(entry,true) and source.global_position.distance_to(Vector3(196,.04,131))<.01 and entry.health==1000,"The existing respawn adapter uses the individual's safe designated point")
	source.set_physics_process(false)
	check(society.id_for_source(source)==id and population.reserved_outdoors==0 and entry.anger==0,"Respawning clears aggression and releases the reserved street slot")
	# Use a small, valid registry configuration to reach a real lifetime expiry
	# quickly; the original world's unrelated civilians are never advanced.
	var focused=Registry.new()
	focused.config.lifetime_years=.000001
	focused.config.level_years=.000001
	var rows: Array[Dictionary]=[{"slot":"hub/"+String(source.profile.id),"id":id,"name":source.profile.name,"occupation":source.profile.role,"personality":source.profile.attitude,"respawn":person.respawn}]
	check(focused.bootstrap(rows),"The accelerated expiry fixture uses a valid civilian registry")
	society.registry=focused
	society.autonomy.bind_sources()
	person=focused.records[id]
	entry.anger=reactions.enrage_threshold
	reactions.retaliation_enabled=true
	check(reactions.begin_fighter(key),"The same civilian enters the existing angry combat adapter")
	var fighter: CharacterBody3D=reactions.fighters.get(key)
	if fighter==null: world.free(); intent.free(); quit(1); return
	fighter.controls.stop(); fighter.set_physics_process(false); fighter.weapon_combat.set_physics_process(false)
	var door: Node3D
	for candidate: Node3D in population.entrances.values():
		if candidate.available(): door=candidate; break
	if door!=null: door.claim(source); source.travel_door=door
	check(population.reserved_outdoors==1 and not source.visible and fighter.is_in_group("combat_targets"),"Exactly one combat proxy owns the civilian's reserved street capacity")
	society.registry.set_goal(id,"guild")
	check(not society.autonomy.perform_action(person,state,false) and person.guild.is_empty(),"A living but suspended combatant cannot complete offscreen social or economic actions")
	var legacy: StringName=source.profile.id
	var advance: float=float(person.expires_at)*float(focused.config.real_seconds_per_day)/float(focused.config.day_seconds)
	check(society.advance_real(advance) and focused.replacement_serial==1,"A genuine lifetime expiration replaces exactly one active combatant")
	var next: Dictionary=focused.for_slot("hub/"+String(legacy))
	await frames(3)
	check(not reactions.fighters.has(key) and not reactions.entries.has(key) and population.reserved_outdoors==0 and not is_instance_valid(fighter),"Expiration retires the fighter, anger entry and reserved capacity without a resurrection loop")
	var inherited_combat:=false
	for memory: Dictionary in next.memories:
		if memory.type=="combat": inherited_combat=true
	check(source.code_form_id==next.id and next.id!=id and source.profile.id==legacy and next.level==1 and not inherited_combat,"One fresh individual inherits the physical route slot without inheriting personal state")
	check(door==null or door.available(),"Retiring a civilian releases any held doorway lease")
	check(focused.active_ids().size()==1 and not focused.records[id].active and source.indoor_left>0,"The replacement waits for the existing safe pedestrian spawn pipeline")
	check(not actor.has_meta("code_form_id") and not focused.records.has("kyren"),"The player and boss remain outside the civilian identity system")
	world.queue_free(); intent.queue_free()
	await frames(2)
	print("Code Form physical combat verification: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
