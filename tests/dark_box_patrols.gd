extends SceneTree
## Real census, shared combat equipment, wanted dispatch and native vehicle parity.
const Catalog=preload("res://scripts/item_catalog.gd")
const Vehicle=preload("res://scripts/traffic_vehicle.gd")
const Patrols=preload("res://scripts/dark_box_patrols.gd")
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
	create_timer(180).timeout.connect(func(): push_error("Dark Box fixture watchdog"); quit(2))
	var world: Node3D=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false; world.world_memory_enabled=false
	world.boss_encounters_enabled=false; world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.civilization.simulation_enabled=false
	var intent:=Intent.new(); root.add_child(intent)
	world.player.controls=intent; world.camera_rig.controls=intent; world.inventory_session.controls=intent
	world.player.visual.retrieval.enabled=false
	for index in range(600):
		await frames(1)
		if world.dark_box_patrols.ready_for_patrols: break
	var patrols: Node3D=world.dark_box_patrols
	check(patrols.ready_for_patrols and not patrols.units.is_empty(),"Dark Box patrols use the established census and guild roster")
	if not patrols.ready_for_patrols or patrols.units.is_empty(): world.free(); quit(1); return
	var count: int=world.civilization.registry.active_ids().size()
	world.district_life.set_physics_process(false); world.population.set_physics_process(false); patrols.set_physics_process(false)
	for person: Node in world.population.residents: person.set_physics_process(false)
	for person: Node in world.district_life.people.values(): person.set_physics_process(false); person.set_process(false)
	for car: Node in world.district_life.vehicles.values(): car.set_physics_process(false)
	var car_unit: Dictionary={}; var bike_unit: Dictionary={}
	for row: Dictionary in patrols.units.values():
		if row.record.kind=="car": car_unit=row
		if row.record.kind=="motorcycle": bike_unit=row
	check(not car_unit.is_empty() and car_unit.members.size()==2,"Patrol cars reserve exactly two actual officers")
	check(not bike_unit.is_empty() and bike_unit.members.size()==1,"Patrol bikes reserve one actual officer")
	var unique: Dictionary={}; var all_geared:=true
	for row: Dictionary in patrols.units.values():
		for id: String in row.members:
			if unique.has(id): all_geared=false
			unique[id]=true
			var store: Node=world.civilian_services.economy.npc_store(id)
			var wand: Resource=store.equipped_item(&"up")
			if wand==null or wand.item_type_id!=&"dark_box_arc_wand" or not world.quest_system.organizations.is_member(id,"dark_box"): all_geared=false
	check(all_geared,"Every assigned officer owns and equips one standard wand with unique identity")
	var before: Dictionary=patrols.serialize()
	check(not Patrols.validate(JSON.parse_string(JSON.stringify(before))).is_empty(),"Issue provenance survives strict JSON save validation")
	var sample_unit: Dictionary=car_unit if not car_unit.is_empty() else patrols.units.values()[0]
	var vehicle:=Vehicle.new()
	vehicle.life=world.district_life
	vehicle.record=sample_unit.record
	vehicle.record.point=Vector3(3,.05,130)
	vehicle.record.route=PackedVector3Array([Vector3(3,.05,130),Vector3(3,.05,630),Vector3(67,.05,630),Vector3(67,.05,130)])
	vehicle.record.cursor=1; vehicle.record.yaw=0
	world.district_life.add_child(vehicle); vehicle.set_physics_process(false)
	world.district_life.vehicles[vehicle.record.id]=vehicle
	vehicle.configure_patrol(patrols._profile(String(sample_unit.members[1])) if sample_unit.members.size()>1 else {})
	check(vehicle.emergency_markers.size()==2 and (vehicle.passenger_visual!=null)==(sample_unit.members.size()==2),"Cars/bikes retain red and blue emergency lenses and correct seated crew")
	world.player.global_position=Vector3(10,.05,140); world.player.velocity=Vector3.ZERO
	await frames(3)
	check(not patrols.deploy(vehicle),"Officers never attack without an existing witnessed wanted case")
	var witness: String=sample_unit.members[0]
	var case: Dictionary=world.law.record_crime({"event_id":"wand_patrol_fixture","kind":"assault","offender":"player","victim":witness,"witnesses":[witness]})
	check(not case.is_empty() and world.law.wanted_level("player")==1,"Dispatch consumes existing witness-based cases without changing five-Glyph rules")
	check(patrols.deploy(vehicle),"Visible wanted suspect triggers normal officer combat deployment")
	check(patrols.fighters.size()==sample_unit.members.size() and not vehicle.has_driver and world.civilization.registry.active_ids().size()==count,"Mounted-to-foot handoff duplicates neither civilians nor seats")
	var same_store:=true
	for id: String in patrols.fighters:
		var fighter: CharacterBody3D=patrols.fighters[id]
		fighter.controls.stop(); fighter.set_physics_process(false); fighter.weapon_combat.set_physics_process(false)
		if fighter.inventory!=world.civilian_services.economy.npc_store(id) or fighter.weapon_combat.equipment_key(&"up")!=&"dark_box_arc_wand": same_store=false
		fighter.on_parried(world.player.combat_point())
		if not fighter.weapon_combat.is_staggered(): same_store=false
	check(same_store,"Officers fight with authoritative owned wand and receive ordinary parry stagger")
	if not patrols.fighters.is_empty():
		var target: CharacterBody3D=patrols.fighters.values()[0]
		for candidate: CharacterBody3D in world.district_life.vehicles.values():
			if candidate==vehicle or not candidate.has_driver or candidate.record.driver.code_form_id==target.identity: continue
			candidate.driving_actor()
			target.weapon_combat.reset()
			var hp: float=target.health
			var applied: float=target.receive_hit(75,candidate.combat_point(),candidate,{"vehicle_wave":true,"parryable":false,"hit_stun_level":0.0})
			check(applied==75 and target.health==hp-75,"An engaged officer has no immunity to another native driver's light wave")
			break
	await officer_spell(world,patrols)
	var ordinary: WeakRef=await ordinary_owned_wand(world)
	# Checkpoint helper runs in this existing full world, never a second census.
	if FileAccess.file_exists("res://tests/dark_box_checkpoint_flow.gd"):
		var flow: RefCounted=load("res://tests/dark_box_checkpoint_flow.gd").new()
		await flow.run(world,patrols,vehicle,check)
		check(ordinary==null or ordinary.get_ref()==null,"Checkpoint replacement safely retires ordinary borrowed-inventory combat bodies too")
	patrols._player_reset(); await frames(2)
	check(patrols.fighters.is_empty() and patrols._player_grace>0,"Player death/respawn ends pursuit combat and grants reconstruction grace")
	check(patrols.serialize().issued==before.issued,"Ending an encounter never creates replacement copies of issued gear")
	vehicle.has_driver=true
	vehicle.set_npc_driving(true,true)
	check(vehicle.npc_boost and vehicle.wave_enabled and vehicle.light_wave.owner_actor.get_ref()==vehicle,"Native drivers enable the shared boosted laser wave with native attribution")
	var floor_body:=StaticBody3D.new(); var floor_shape:=CollisionShape3D.new(); var floor_box:=BoxShape3D.new()
	floor_box.size=Vector3(12,2,1024); floor_shape.shape=floor_box; floor_body.add_child(floor_shape)
	floor_body.position=Vector3(2000,-1,0); world.add_child(floor_body)
	vehicle.signed_speed=0; vehicle.rotation.y=0; vehicle.position=Vector3(2000,.05,-300)
	vehicle.record.route=PackedVector3Array([Vector3(2000,.05,-300),Vector3(2000,.05,300),Vector3(2003,.05,300),Vector3(2003,.05,-300)])
	vehicle.record.cursor=1
	await frames(3)
	vehicle.set_physics_process(true)
	await frames(240)
	vehicle.set_physics_process(false)
	check(vehicle.signed_speed>vehicle.top_speed and vehicle.signed_speed<=vehicle.top_speed*vehicle.boost_multiplier+.01,"Native traffic reaches the same bounded boosted top speed as the player")
	var victim: CharacterBody3D=world.population.residents[0]
	# This tests a physical civilian. Distant residents now intentionally have
	# no visible/collidable body; bring the observer to this isolated test road.
	world.player.global_position=Vector3(2005,.05,-296)
	victim.activate(Vector3(2005,.05,-300)); victim.set_physics_process(false)
	var victim_id: String=world.civilization.id_for_source(victim)
	var xp: int=world.civilization.registry.records[victim_id].experience
	var before_hp: float=victim.health
	var wand_damage: float=victim.receive_combat_hit(30,vehicle.combat_point(),vehicle,{"weapon_family":"wand","attack_serial":901})
	check(wand_damage==30 and victim.health==before_hp-30,"Native wand energy uses the existing civilian HP authority")
	var wave_damage: float=victim.receive_combat_hit(750,vehicle.combat_point(),vehicle,{"vehicle_wave":true,"attack_serial":902})
	check(wave_damage==750 and victim.health==before_hp-780,"A native-driven wave deals the same damage to physical civilians")
	victim.receive_combat_hit(750,vehicle.combat_point(),vehicle,{"vehicle_wave":true,"attack_serial":903})
	var victim_entry: Dictionary=world.theft_reactions.entries[world.theft_reactions.key_for(victim)]
	check(victim_entry.dead and victim_entry.suspended and world.civilization.registry.records[victim_id].experience==xp,"Native wave defeat follows safe civilian respawn without awarding synthetic XP")
	check(world.law.wanted_level(String(vehicle.record.driver.code_form_id))>0,"A surviving victim's actual witness report attributes native laser assault correctly")
	vehicle.has_driver=false
	vehicle.light_wave._physics_process(.1)
	check(not vehicle.light_wave.enabled,"A driverless wreck or handoff cannot keep emitting new wave segments")
	var id: String=sample_unit.members[0]
	var iid: String=patrols.issued[id]
	var store: Node=world.civilian_services.economy.npc_store(id)
	var removed: Resource=store.take_item(iid)
	check(removed!=null and not patrols._issue(id),"Selling or losing an issued wand cannot mint a fresh copy through reentry")
	removed.owner_id=store.owner_id; store.add_item(removed)
	check(store.assign(&"up",iid) and patrols._issue(id) and store.equipped_item(&"up").instance_id==iid,"Recovering the original issued item preserves its unique identity")
	world.free(); intent.free(); await frames(2)
	print("Dark Box patrol verification: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func officer_spell(world: Node3D,patrols: Node3D) -> void:
	if patrols.fighters.is_empty(): check(false,"An officer is present for actual wand AI checks"); return
	var officer: CharacterBody3D=patrols.fighters.values()[0]
	world.player.global_position=Vector3(3,.05,140); world.player.velocity=Vector3.ZERO
	world.player.weapon_combat.reset(); world.player.combat.sheathed=false
	officer.global_position=Vector3(3,.05,150); officer.velocity=Vector3.ZERO
	officer.weapon_combat.reset(); officer.combat.sheathed=false
	officer.controls.start(); officer.controls.cursor=3; officer.controls.decision=0
	officer.set_physics_process(true); officer.weapon_combat.set_physics_process(true)
	var cast: Node3D
	for step in range(80):
		await frames(1)
		for effect: Node3D in get_nodes_in_group("wand_effects"):
			if effect.actor==officer: cast=effect; break
		if is_instance_valid(cast): break
	check(is_instance_valid(cast) and cast.attack=="volley","The shared Code Form brain launches the officer's equipped wand volley")
	if is_instance_valid(cast):
		var model: Node3D=officer.weapon_combat.rig.models[officer.weapon_combat.rig.selected].right
		check(cast._origin.distance_to(model.get_node("WandEmitter").global_position)<.003,"An officer's actual AI cast releases from its solved wand tip")
	officer.controls.stop(); officer.set_physics_process(false)
	var before: float=world.player.health
	await frames(35)
	check(world.player.health<before,"An officer's actual wand projectile resolves shared damage on the wanted player")
	for effect: Node3D in get_nodes_in_group("wand_effects"): effect.expire()

	world.player.weapon_combat.reset(); world.player.velocity=Vector3.ZERO
	world.player.visual.rotation.y=0
	world.camera_rig.yaw=PI
	world.player.target_lock.select(officer)
	officer.weapon_combat.reset(); officer.global_position=Vector3(3,.05,148)
	officer.controls.start(); officer.controls.cursor=2; officer.controls.decision=0
	officer.set_physics_process(true)
	cast=null
	for step in range(80):
		await frames(1)
		for effect: Node3D in get_nodes_in_group("wand_effects"):
			if effect.actor==officer: cast=effect; break
		if is_instance_valid(cast): break
	officer.controls.stop(); officer.set_physics_process(false)
	var staggered:=false
	if is_instance_valid(cast):
		for step in range(40):
			if not is_instance_valid(cast): break
			var close:=false
			for bolt: Dictionary in cast._bolts:
				if Vector3(bolt.position).distance_to(world.player.combat_point())<2.2: close=true
			if close:
				world.player.controls._keyboard_block=true
				world.player.combat.blocking=true; world.player.combat.fresh_block=true
				world.player.weapon_combat._on_block(true)
			await frames(1)
			if officer.weapon_combat.forced_state==&"parried": staggered=true; break
	world.player.controls._keyboard_block=false
	world.player.combat.blocking=false
	check(staggered,"A fresh player parry of an actual officer spell staggers its original caster")
	officer.controls.stop(); officer.set_physics_process(false); officer.weapon_combat.set_physics_process(false)
	for effect: Node3D in get_nodes_in_group("wand_effects"): effect.expire()

func ordinary_owned_wand(world: Node3D) -> WeakRef:
	var source: CharacterBody3D=world.population.residents[1]
	var id: String=world.civilization.id_for_source(source)
	var inventory: Node=world.civilian_services.economy.npc_store(id)
	var wand: Resource=Catalog.create(&"arc_wand_gold")
	check(inventory.add_item(wand) and inventory.assign(&"up",wand.instance_id),"An ordinary Code Form can own and equip a nonstandard wand color")
	source.activate(Vector3(8,.05,145)); source.set_physics_process(false)
	var reactions: Node3D=world.theft_reactions
	var entry: Dictionary=reactions._entry_for(source)
	entry.anger=reactions.enrage_threshold
	var key: String=reactions.key_for(source)
	check(reactions.begin_fighter(key),"An ordinary wand owner enters the established civilian combat adapter")
	var fighter: CharacterBody3D=reactions.fighters.get(key)
	if not is_instance_valid(fighter): return null
	fighter.controls.stop(); fighter.set_physics_process(false); fighter.weapon_combat.set_physics_process(false)
	check(fighter.inventory==inventory and fighter.inventory.get_item(wand.instance_id)==wand and fighter.weapon_combat.equipment_key(fighter.combat.selected_slot)==&"arc_wand_gold","Ordinary combat borrows the exact owned wand inventory and preserves its item identity")
	fighter.controls.choose_attack(&"up",&"special_x")
	fighter.set_physics_process(true); fighter.weapon_combat.set_physics_process(true)
	var launched:=false
	for step in range(50):
		await frames(1)
		for effect: Node3D in get_nodes_in_group("wand_effects"):
			if effect.actor==fighter: launched=true; effect.expire()
		if launched: break
	check(launched,"The same shared Code Form combat controller casts an ordinary resident's owned wand")
	fighter.controls.stop(); fighter.set_physics_process(false); fighter.weapon_combat.set_physics_process(false)
	return weakref(fighter)
