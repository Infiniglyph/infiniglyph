extends SceneTree
const Catalog=preload("res://scripts/item_catalog.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Store=preload("res://scripts/inventory_store.gd")
const Encoder=preload("res://scripts/checkpoint_encoder.gd")
const Regions=preload("res://scripts/world_regions.gd")
var world: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func place(at: Vector3) -> void:
	world.communication.close_conversation("fixture")
	world.building_civilization.menu.close_menu()
	world.player.global_position=at
	world.player.velocity=Vector3.ZERO
	world.player.fall_damage.reset()
	world.player.visual.rebase_after_phase()
	world.controls.set_gameplay_enabled(true)
	await frames(4)
func send(intent: String,parameters: Dictionary={}) -> Dictionary:
	return world.communication.send("player",world.civic_interactions._speaker,intent,parameters,{},false,world.communication.conversation_id)
func door_ray(descriptor: Dictionary) -> Dictionary:
	var at: Vector3=descriptor.point
	var depth: float=descriptor.shell.dimensions.z
	return world.player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3(0,1,depth*.5+1),at+Vector3(0,1,depth*.5-1),1,[world.player.get_rid()]))
func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Civic expansion watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=true
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	world.neon_glow_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	world.civilization.simulation_enabled=false
	world.player.visual.retrieval.enabled=false
	world.sparring_partner.visual.retrieval.enabled=false
	for i in range(400):
		await frames(1)
		if world.civic_interactions.initialized and world.building_civilization.ready_for_use and world.building_civilization._guild_premises_ready: break
	var civic: Node=world.civic_interactions
	var properties: Node=world.building_civilization
	var quests: Node=world.quest_system
	var economy: Node=world.civilian_services.economy
	check(civic.initialized and properties.ready_for_use,"Real civic institutions and physical building manifests become ready")
	if not civic.initialized or not properties.ready_for_use: world.queue_free(); await frames(); quit(1); return
	civic.set_process(false)
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	world.district_life.set_physics_process(false)
	for resident: Node in world.district_life.people.values(): resident.set_physics_process(false)
	for vehicle: Node in world.district_life.vehicles.values(): vehicle.set_physics_process(false)
	var org: RefCounted=quests.organizations
	check(org.factions.size()==4 and org.guilds.size()==12 and economy.guilds.size()==12,"The real world owns four factions and twelve independently financed guilds")
	var native_leaders:=true
	for faction: String in org.factions:
		var rows: Array=org.guilds_for_faction(faction)
		var generalists:=0
		for row: Dictionary in rows:
			if row.classification=="generalist": generalists+=1
			native_leaders=native_leaders and civic.identity(row.leader).get("kind")=="code_form" and economy.balances.has(row.treasury) and row.treasury!="faction:"+faction
		check(rows.size()==3 and generalists==1,"Actual "+faction+" institutions contain one generalist and two specialists")
	check(native_leaders,"Guilds retain native leaders and their own finite treasury accounts")
	var coins:=0
	for amount: int in economy.balances.values(): coins+=amount
	check(coins==economy.issued_total-economy.destroyed_total,"Founding guild finance conserves the total issued coin supply")
	var sequence: int=economy.sequence
	civic.bootstrap()
	check(economy.sequence==sequence,"Reentrant bootstrap cannot refill the twelve treasuries")
	var board: Dictionary={}
	for point: Dictionary in world.civilian_services.establishments.points:
		if point.get("id")=="board_security": board=point; break
	await place(board.anchor.global_position+Vector3(0,.3,1.4))
	check(civic.begin_service(board,""),"An actual faction board routes membership through universal communication")
	send("accept_guild",{"guild_id":"dark_box"})
	check(org.is_member("player","dark_box") and not org.is_member("player","iron_wardens"),"Joining Dark Box does not grant another Security guild's membership")
	var own: Dictionary={}; var other: Dictionary={}
	for row: Dictionary in quests.available("player","security",true):
		if row.get("guild_id")=="dark_box": own=row
		elif row.get("guild_id")=="iron_wardens": other=row
	check(not own.is_empty() and not other.is_empty() and quests.accept(own.id,"player",civic._now()) and not quests.accept(other.id,"player",civic._now()),"Funded contracts enforce their issuing guild rather than a broad faction membership")
	check(not quests.join_guild("player","veil") and not org.change_leader("dark_box","player",String(org.guild("dark_box").leader)),"Private introductions and native leadership rules remain enforced")
	var guild_sites: Dictionary={}
	for guild: Dictionary in org.guilds.values():
		if guild.id=="adventurers_guild": continue
		var premises: Dictionary=properties.model.records.get(String(guild.headquarters),{})
		if not premises.is_empty() and premises.owner=="guild/"+String(guild.id) and premises.usage=="guild_headquarters" and not premises.manual_review: guild_sites[guild.headquarters]=true
	check(guild_sites.size()==11 and org.guild("adventurers_guild").headquarters=="establishment/adventurers_guild","Eleven other starter guilds occupy distinct real shells while the existing Adventurers Guild remains in place")
	var founding_locations: Array=[]
	for guild: Dictionary in org.guilds.values():
		if not properties.descriptors.has(String(guild.headquarters)): continue
		var at: Vector3=properties.descriptors[String(guild.headquarters)].point
		founding_locations.append({"kind":"guild","id":guild.id,"name":guild.name,"building_id":guild.headquarters,"position":[at.x,at.y,at.z],"grid":Regions.grid_label(Regions.grid_at(at))})
	var faction_sites:=0
	for key: String in org.factions:
		var faction: Dictionary=org.factions[key]
		var premises: Dictionary=properties.model.records.get(String(faction.get("headquarters","")),{})
		if not premises.is_empty() and premises.owner=="faction/"+key and premises.usage=="office" and not premises.manual_review and not guild_sites.has(premises.id): faction_sites+=1
		if properties.descriptors.has(String(faction.get("headquarters",""))):
			var at: Vector3=properties.descriptors[String(faction.headquarters)].point
			founding_locations.append({"kind":"faction","id":key,"name":faction.name,"building_id":faction.headquarters,"position":[at.x,at.y,at.z],"grid":Regions.grid_label(Regions.grid_at(at))})
	check(faction_sites==4,"All four factions have separate real city offices rather than reusing a guild shell")
	var location_file:=FileAccess.open("res://.godot/founding-headquarters.json",FileAccess.WRITE)
	if location_file!=null: location_file.store_string(JSON.stringify(founding_locations,"\t")); location_file.close()
	var seeded_property_count: int=properties.serialize().records.size()
	var careers: Node=world.careers
	var worker:=""; var work_offer: Dictionary={}
	for candidate: String in org.guild("cartographers").members:
		if not civic.identity(candidate).get("active",false) or world.civilization.autonomy._unavailable(candidate): continue
		for offer: Dictionary in quests.available(candidate,"exploration",true,"cartographers"):
			if civic.position_for(candidate).distance_to(civic.destination(String(offer.objective.target_id)))>10:
				worker=candidate; work_offer=offer; break
		if not worker.is_empty(): break
	var worker_before: Dictionary=world.civilization.registry.records.get(worker,{}).duplicate(true)
	var worker_coins: int=economy.balance("resident:"+worker)
	check(not worker.is_empty() and quests.accept(String(work_offer.get("id","")),worker,civic._now()),"An active native accepts a real funded contract from their own specialist guild")
	if not worker.is_empty(): careers.npc_step(worker,civic._now())
	var employment: Dictionary={}
	for job: Dictionary in careers.records_for(worker,false):
		if job.quest_id==work_offer.get("id",""): employment=job; break
	check(not employment.is_empty() and employment.compensation.type=="contract" and employment.compensation.amount==work_offer.get("reward") and employment.employer=="guild/cartographers","The real career adapter hires against the existing shared quest and its reserved compensation")
	check(economy.balance("resident:"+worker)==worker_coins and world.civilization.registry.records.get(worker,{}).get("experience")==worker_before.get("experience") and quests.model.instances.get(work_offer.get("id",""),{}).get("status")=="active","Choosing and waiting on a profession cannot fabricate wages, XP or discovery completion")
	check(careers.select_career("player","merchant").is_empty() and careers.select_career("avat_ar","merchant").is_empty() and careers.select_career("kyren","merchant").is_empty(),"Career registration remains exclusive to native civilian identities")
	var guild_leader: String=org.guild("dark_box").leader
	careers.model.synchronize_positions(guild_leader)
	check(careers.records_for(guild_leader,false).any(func(job: Dictionary): return job.career=="guild_leader" and job.role_ref=="dark_box" and job.status=="office"),"Actual guild leadership synchronizes its native career office")
	var descriptor: Dictionary={}; var private_descriptor: Dictionary={}
	for row: Dictionary in properties.descriptors.values():
		if row.manual_review or row.region!="city" or not properties.model.records[row.id].owner.is_empty(): continue
		if descriptor.is_empty(): descriptor=row
		elif private_descriptor.is_empty(): private_descriptor=row; break
	check(not descriptor.is_empty() and properties.model.records.size()==600,"The integrated authority binds all stable physical building records")
	var id: String=descriptor.id
	await place(descriptor.point+Vector3(0,.04,0))
	properties._process(1)
	check(properties.interact(),"A physically occupied empty room exposes renovation actions")
	properties._claim(); properties._set_use("workshop")
	check(properties.model.records[id].owner=="player" and properties.model.records[id].usage=="workshop","Claiming and changing a building's purpose use the real authority")
	var bed: Resource=Catalog.create(&"basic_bed",2)
	var food: Resource=Catalog.create(&"byte_bites",3)
	world.player.inventory.add_item(bed); world.player.inventory.add_item(food)
	var foreign:=Inventory.new(); foreign.owner_id="foreign"
	var foreign_bed: Resource=Catalog.create(&"basic_bed"); foreign.add_item(foreign_bed)
	check(not properties.install(id,"player",foreign,foreign_bed.instance_id,[-4.0,0.0,-4.0],0) and foreign.count_type(&"basic_bed")==1,"A player cannot install items from an unrelated inventory")
	foreign.free()
	check(not properties.install(id,"player",world.player.inventory,bed.instance_id,[0.0,0.0,0.0],0) and world.player.inventory.count_type(&"basic_bed")==2,"A blocked placement leaves the owned item stack untouched")
	check(properties.install(id,"player",world.player.inventory,bed.instance_id,[-4.0,0.0,-4.0],0) and world.player.inventory.count_type(&"basic_bed")==1,"Installing a bed transfers exactly one actual owned item into the property")
	var placement: Dictionary=properties.model.records[id].placements.values()[0]
	check(placement.item.owner_id=="building:"+id and placement.item.instance_id!=bed.instance_id,"A split furnishing retains its real unique identity and property owner")
	properties._process(1)
	check(properties._rendered.has(id) and properties._rendered[id].get_child_count()==1,"The actual installed bed appears through the streamed physical furniture renderer")
	properties._transfer(food.instance_id,true)
	check(world.player.inventory.count_type(&"byte_bites")==2 and properties.model.records[id].storage.items[0].quantity==1,"Property storage deposits one real owned meal and conserves the remaining stack")
	var stored_id: String=properties.model.records[id].storage.items[0].instance_id
	properties._transfer(stored_id,false)
	check(world.player.inventory.count_type(&"byte_bites")==3 and properties.model.records[id].storage.items.is_empty(),"Withdrawing property storage returns its actual item without duplication")
	properties._transfer(food.instance_id,true)
	properties.menu.close_menu()
	var native: String=String(org.guild("iron_wardens").leader)
	var private_id: String=private_descriptor.id
	properties.model.claim(private_id,native,civic._now())
	properties.model.admit(private_id,native,"player",civic._now())
	properties.model.set_access(private_id,native,"owner",civic._now())
	await place(private_descriptor.exit)
	properties._process(1); await frames()
	check(not door_ray(private_descriptor).is_empty(),"Owner-only access remains physically closed to a registered tenant")
	properties.model.set_access(private_id,native,"tenants",civic._now())
	properties._process(1); await frames()
	check(door_ray(private_descriptor).is_empty(),"Tenant access opens the real door when the owner permits tenants")
	properties.model.set_access(private_id,native,"owner",civic._now())
	await place(private_descriptor.point+Vector3(0,.04,0))
	properties._process(1); await frames()
	check(door_ray(private_descriptor).is_empty(),"An already-inside visitor retains a safe physical exit after permissions change")
	await place(descriptor.point+Vector3(0,.04,0))
	properties.current=id
	var snapshot: Dictionary=world.inventory_session._capture_checkpoint()
	check(snapshot.has("building_state") and snapshot.building_state.records.size()==seeded_property_count+2 and not Store.decode(snapshot).is_empty(),"A whole checkpoint validates sparse property records alongside guild finance and citizen state")
	check(snapshot.has("career_state") and not snapshot.career_state.employments.is_empty() and not Store.decode(JSON.parse_string(JSON.stringify(snapshot))).is_empty(),"Native offices and funded employment validate in an actual JSON checkpoint")
	var legacy: Dictionary=snapshot.duplicate(true); legacy.erase("career_state")
	check(not Store.decode(legacy).is_empty(),"A legacy checkpoint without optional occupational state remains valid")
	var corrupt: Dictionary=snapshot.duplicate(true)
	var duplicate: Dictionary=placement.item.duplicate(true); duplicate.owner_id=corrupt.inventory.owner_id
	corrupt.inventory.items.append(duplicate)
	check(Store.decode(corrupt).is_empty(),"Checkpoint crosschecks reject one item appearing in both inventory and installed furniture")
	corrupt=snapshot.duplicate(true); corrupt.building_state.records[id].owner="unknown_civilian"
	check(Store.decode(corrupt).is_empty(),"Property ownership cannot reference an invented civilian")
	corrupt=snapshot.duplicate(true); corrupt.career_state.world_seconds=float(snapshot.civilization_state.registry.world_seconds)+1
	check(Store.decode(corrupt).is_empty(),"Occupational state cannot advance beyond its linked civilization clock")
	corrupt=snapshot.duplicate(true); corrupt.quest_state.organizations.guilds.dark_box.headquarters=id
	check(Store.decode(corrupt).is_empty(),"A forged headquarters cannot point a guild at an unrelated player-owned building")
	var encoder:=Encoder.new()
	check(encoder.start(snapshot)==OK,"The real background checkpoint encoder accepts the expanded immutable snapshot")
	for i in range(2000):
		if encoder.ready(): break
		await process_frame
	var result: Dictionary=encoder.take_result()
	check(result.get("error") == OK and not Store.decode(JSON.parse_string(result.get("bytes",PackedByteArray()).get_string_from_utf8())).is_empty(),"Worker JSON preserves linked guilds, items, property ownership and placements")
	var path:="user://tests/civic_expansion_integration.json"
	check(world.inventory_session.save_checkpoint(path,true) and world.inventory_session.load_checkpoint(path),"The real manual save/load path restores the expanded property and institution state")
	check(properties.model.records[id].owner=="player" and properties.model.records[id].usage=="workshop" and properties.model.records[id].placements.size()==1 and properties.model.records[id].storage.items[0].quantity==1 and quests.organizations.is_member("player","dark_box"),"Owned workshop contents, stored food and specific guild membership survive load")
	check(not employment.is_empty() and careers.model.employments.has(employment.id) and careers.model.employments[employment.id].quest_id==work_offer.get("id"),"The loaded employment still references its exact funded shared quest")
	await place(descriptor.point+Vector3(0,.04,0))
	properties.current=id
	properties._remove(String(placement.id))
	check(properties.model.records[id].placements.is_empty() and world.player.inventory.count_type(&"basic_bed")==2,"Removing a loaded furnishing returns one real bed and merges safely with its remaining stack")
	var headquarters: String=org.guild("dark_box").headquarters
	var ordinary:=""
	for member: String in org.guild("dark_box").members:
		if member!=guild_leader and member!="player": ordinary=member; break
	check(properties._can_manage(headquarters,guild_leader) and not properties._can_manage(headquarters,ordinary),"The actual native guild leader can manage its institution while ordinary membership grants no furnishing authority")
	var citizen: String=world.civilization.autonomy._regional_records.keys()[0]
	var journey: Dictionary=world.civilization.autonomy._regional_records[citizen]
	var old_point: Vector3=journey.point
	var workshop: Dictionary={}
	for row: Dictionary in properties.descriptors.values():
		if row.manual_review or row.region!="city" or not properties.model.records[row.id].owner.is_empty() or row.size.x<18 or row.size.z<18: continue
		workshop=row; break
	var home: String=workshop.id
	# Stage this authority fixture's existing unloaded identity in its actual
	# property. Separate CareerCommute tests cover every metre of physical travel.
	journey.point=workshop.point+Vector3(-5,.04,5)
	properties.model.claim(home,citizen,civic._now())
	properties.model.set_use(home,citizen,"workshop",civic._now())
	var citizen_store: Node=economy.npc_store(citizen)
	var chairs: Resource=Catalog.create(&"single_chair",5); citizen_store.add_item(chairs)
	var installed:=0
	for z: float in [-7.0,-3.5,0.0,3.5,7.0]:
		if properties.install(home,citizen,citizen_store,chairs.instance_id,[-4.0,0.0,z],0): installed+=1
	civic._flush_career_events()
	check(installed==5 and citizen_store.count_type(&"single_chair")==0 and careers.model.candidates.get("furnishing_installation",{}).get("count")==5 and careers.definitions.has("furnishing_installation"),"Five unique real native installations consume five owned chairs and establish the Interior Furnisher career")
	civic._flush_career_events()
	check(careers.model.candidates.get("furnishing_installation",{}).get("count")==5 and careers.definitions.furnishing_installation.capabilities==careers.definitions.artificer.capabilities,"Replaying an empty proof queue cannot inflate the emerging profession or introduce arbitrary capabilities")
	properties.model.set_use(home,citizen,"tavern",civic._now())
	var cooker: Resource=Catalog.create(&"cooking_station"); citizen_store.add_item(cooker)
	check(properties.install(home,citizen,citizen_store,cooker.instance_id,[4.0,0.0,4.0],0),"The native tavern owner installs an actual owned cooking station")
	journey.point=workshop.point+Vector3(2.3,.04,4)
	var chef: String=careers.select_career(citizen,"chef",home)
	var chef_job: Dictionary=careers.model.employments.get(chef,{})
	var coins_before_need: int=economy.balance("resident:"+citizen)
	var xp_before_need: int=world.civilization.registry.records[citizen].experience
	var meals_before: int=citizen_store.count_type(&"electron_meal")
	var needed: Dictionary=civic.career_perform(citizen,"food_preparation",chef_job)
	var supply: Dictionary={}
	for row: Dictionary in quests.model.instances.values():
		if row.issuer==citizen and row.kind=="delivery" and row.objective.item_type=="light_shard": supply=row; break
	check(not chef.is_empty() and needed.get("action")=="posted_supply_request" and not supply.is_empty() and economy.balance("resident:"+citizen)==coins_before_need-3 and citizen_store.count_type(&"electron_meal")==meals_before and world.civilization.registry.records[citizen].experience==xp_before_need,"A real kitchen short of material reserves the owner's finite reward for a delivery without creating food or idle XP")
	var contract_count: int=quests.model.instances.size()
	civic.career_perform(citizen,"food_preparation",chef_job)
	check(quests.model.instances.size()==contract_count and economy.balance("resident:"+citizen)==coins_before_need-3,"Repeated same-day business need checks cannot mint duplicate funded requests")
	var enterprise: String=careers.register_business(citizen,"Fixture Corner Kitchen",home,"tavern")
	var supplier: String=world.civilization.autonomy._regional_records.keys()[1]
	var courier_journey: Dictionary=world.civilization.autonomy._regional_records[supplier]
	var old_courier_point: Vector3=courier_journey.point
	courier_journey.point=journey.point+Vector3(0,0,1)
	economy.npc_store(supplier).add_item(Catalog.create(&"light_shard"))
	var accepted: bool=not supply.is_empty() and quests.accept(String(supply.id),supplier,civic._now())
	var offer: Dictionary=civic._career_offer(quests.model.instances.get(String(supply.get("id","")),{}),supplier) if accepted else {}
	var hire: String=careers.hire(citizen,supplier,"courier",home,String(supply.get("id","")),enterprise) if not enterprise.is_empty() else ""
	check(not enterprise.is_empty() and offer.get("business")==enterprise and not hire.is_empty() and hire in careers.model.businesses[enterprise].employees,"A real native kitchen hires a native courier against its funded material request and retains the employment in its business roster")
	var fulfilled: bool=accepted and civic.complete_delivery(quests.model.instances[String(supply.id)],supplier)
	quests.advance_to(civic._now())
	var prepared: Dictionary=civic.career_perform(citizen,"food_preparation",chef_job)
	check(fulfilled and prepared.get("action")=="food_preparation" and citizen_store.count_type(&"electron_meal")==meals_before+1 and citizen_store.count_type(&"light_shard")==0 and quests.model.instances[String(supply.id)].status=="completed","Actual native delivery transfers the requested owned material, pays its reserved contract and enables one real cooked meal")
	careers.npc_step(supplier,civic._now())
	check(not hire.is_empty() and careers.model.employments[hire].status=="ended" and not hire in careers.model.businesses[enterprise].employees,"Completed shared work ends its hired employment and releases the business roster without a second wage")
	var business_checkpoint: Dictionary=world.inventory_session._capture_checkpoint()
	check(not Store.decode(JSON.parse_string(JSON.stringify(business_checkpoint))).is_empty(),"Actual business ownership, ended hired work, cooked inventory and the emergent profession remain a valid linked JSON checkpoint")
	journey.point=old_point
	courier_journey.point=old_courier_point
	print("Civic expansion integration: ",checks," checks, ",failures," failures")
	world.queue_free(); await frames(3)
	quit(1 if failures else 0)
