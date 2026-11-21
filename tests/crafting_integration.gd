extends SceneTree
const Catalog=preload("res://scripts/item_catalog.gd")
const Craft=preload("res://scripts/terminal_crafting.gd")
const Passives=preload("res://scripts/equipment_passives.gd")
var checks:=0
var failures:=0
var world: Node3D
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=1):
	for i in range(count): await physics_frame; await process_frame
func capture(label: String,view: Camera3D):
	if "--capture" not in OS.get_cmdline_user_args(): return
	view.make_current(); await frames(3); await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures"); root.get_texture().get_image().save_png("res://captures/crafting_"+label+".png")
func run():
	create_timer(180).timeout.connect(func(): quit(2))
	world=load("res://scenes/main.tscn").instantiate(); world.inventory_persistence_enabled=false; world.dungeon_enemies_enabled=false; root.add_child(world)
	for i in range(900):
		await frames()
		if world.civilization.ready_for_simulation and world.building_civilization.ready_for_use and not world.population.active_residents.is_empty(): break
	world.civilization.simulation_enabled=false
	var player: CharacterBody3D=world.player
	player.set_physics_process(false); player.weapon_combat.set_physics_process(false)
	player.global_position=Vector3(0,.05,10); player.velocity=Vector3.ZERO
	world.theft_reactions.retaliation_enabled=true
	var source: CharacterBody3D=world.population.active_residents[0]
	var id: String=world.civilization.id_for_source(source)
	var store: Node=world.civilization.economy.npc_store(id)
	preload("res://scripts/code_form_wardrobe.gd").issue(store,world.civilization.autonomy._state(id))
	var original: Dictionary=store.equipment.duplicate()
	for slot: StringName in store.SLOTS:
		if store.equipment.has(slot): store.unequip(slot)
	source.global_position=Vector3(4,.05,10); source.wait=120; source.show(); source.visual.show()
	var entry: Dictionary=world.theft_reactions._entry_for(source); entry.anger=world.theft_reactions.enrage_threshold
	var key: String=world.theft_reactions.key_for(source)
	var began: bool=world.theft_reactions.begin_fighter(key)
	check(began,"An ordinary unarmed resident enters the real anger combat handoff")
	if not began:
		print("Handoff diagnostic: ",world.theft_reactions.can_fight()," visible=",source.is_visible_in_tree()," distance=",source.global_position.distance_to(player.global_position)," entry=",entry)
		world.queue_free(); await frames(2); quit(1); return
	var fighter: CharacterBody3D=world.theft_reactions.fighters[key]
	fighter.controls.stop(); fighter.set_physics_process(false); fighter.weapon_combat.set_physics_process(false)
	check(fighter.inventory==store and fighter.visual.equipment_cosmetics.worn.get(&"body")==store.equipped_item(&"body").item_type_id,"The combat body borrows the actual Civic wardrobe instead of becoming naked")
	check(not fighter.combat.resolve_slot(fighter.combat.selected_slot).is_empty(),"An unarmed resident retains the previous responsive fallback combat choices")
	var ring: Resource=Catalog.create(&"eq_r_20004e5c"); store.add_item(ring); var native_max: float=fighter.weapon_combat.max_health; store.assign(&"ring1",ring.instance_id)
	check(fighter.weapon_combat.max_health>native_max and store.equipment.get(&"body")==original.get(&"body"),"A fighting Code Form receives the same ring bonuses without changing its owned clothes")
	var before: float=player.weapon_combat.max_health; var health: float=player.health
	var player_ring: Resource=Catalog.create(&"eq_r_20004e5c"); player.inventory.add_item(player_ring); player.inventory.assign(&"ring1",player_ring.instance_id)
	check(player.weapon_combat.max_health>before and player.health==health,"Equipped HP rings increase the real player maximum without healing on equip")
	var boost:=Passives.total(player.inventory)
	check(is_equal_approx(player.weapon_combat.damage_multiplier(0),1+float(boost.damage)),"Ring damage integrates with the shared strike multiplier")
	player.inventory.unequip(&"ring1"); check(is_equal_approx(player.weapon_combat.max_health,before),"Unequipping restores the previous HP maximum")
	var camera:=Camera3D.new(); world.add_child(camera); camera.position=Vector3(1.3,1.8,14); camera.look_at(fighter.position+Vector3.UP*1.1)
	await capture("resident_fighting",camera)
	world.theft_reactions.finish_fighter(key)
	check(store.equipment.get(&"body")==original.get(&"body") and store.actor==null,"Leaving combat preserves original clothing identities and releases the borrowed inventory")
	# Use the existing service menu rather than a separate crafting surface.
	var menu: CanvasLayer=world.civilian_services.menu
	world.civilian_services.set_process(false) # Isolated page review; real proximity is covered by the room fixture.
	var storage: Node=world.civilian_services.economy.room_stores[0]
	var ui:=preload("res://scripts/terminal_crafting_menu.gd").new(menu,func(): return {"inventory":player.inventory,"storage":storage},func(): menu.close_menu())
	ui.open(); check(menu.is_open and menu._choices.size()==5 and menu._rows[0].disabled==false,"Existing terminal controls expose crafting categories and material/recycling pages")
	menu._rows[0].pressed.emit(); check(menu._choices.size()>=24,"The same terminal lists every existing meal, drink and dessert recipe")
	ui.detail("forge_tomb_blade"); check(menu._body.text.contains("Bone Shards") and menu._body.text.contains("MISSING") and menu._rows[0].disabled,"Terminal details display exact missing dungeon ingredients and disable crafting")
	for pair: Array in [[&"melted_ore",3],[&"glyph_crystal",2],[&"bone_shards",2]]: storage.add_item(Catalog.create(pair[0],pair[1]))
	ui.detail("forge_tomb_blade"); check(not menu._rows[0].disabled,"Supplying actual accessible storage enables the same Craft control")
	await capture("terminal",camera)
	menu._rows[0].pressed.emit(); check(player.inventory.count_type(&"tomb_blade")==1 and storage.count_type(&"bone_shards")==0,"The real terminal page invokes the shared atomic material transaction")
	menu.close_menu()
	var buildings: Node=world.building_civilization
	var shell: String=buildings.model.records.keys().filter(func(key): return buildings.model.records[key].owner.is_empty() and not buildings.model.records[key].manual_review)[0]
	check(buildings.model.claim(shell,id,0),"A registered Code Form owns its crafting fixture property")
	var terminal: Resource=Catalog.create(&"storage_terminal"); terminal.owner_id=buildings.model.owner_key(shell)
	check(buildings.model.install(shell,id,terminal.to_dict(),[2.0,0.0,0.0],0,0),"The existing storage terminal installs with normal footprint and ownership rules")
	check(buildings.crafting_options_for_native(id,shell).is_empty() and not buildings.craft_for_native("player",shell,"forge_starter_sword"),"Remote actors and nonowners cannot access a native terminal")
	var native_storage:=Craft.Inventory.new(); native_storage.restore(buildings.model.records[shell].storage)
	native_storage.add_item(Catalog.create(&"melted_ore",3)); native_storage.add_item(Catalog.create(&"glyph_crystal",1)); buildings.model.records[shell].storage=native_storage.serialize(); native_storage.free()
	var point: Array=buildings.model.records[shell].position
	source.global_position=Vector3(float(point[0])+2,float(point[1]),float(point[2])+2)
	var options: Array=buildings.crafting_options_for_native(id,shell)
	check(options.any(func(row): return row.recipe_id=="forge_starter_sword" and row.ready),"A Code Form at its actual terminal sees the shared recipes and accessible ingredient quantities")
	var sequence: int=world.civilian_services.economy.sequence
	var xp: int=world.civilization.registry.records[id].experience
	check(buildings.craft_for_native(id,shell,"forge_starter_sword") and store.count_type(&"sword_shield")==1,"A Code Form crafts the same owned sword using property storage and the shared transaction")
	var crafted: Resource=store.items.values().filter(func(item): return item.item_type_id==&"sword_shield")[0]
	check(buildings.recycle_for_native(id,shell,crafted.instance_id) and store.count_type(&"melted_ore")==2,"The same native terminal recycles owned equipment at the reduced recovery yield")
	check(world.civilian_services.economy.sequence==sequence and world.civilization.registry.records[id].experience==xp,"Terminal crafting and recycling neither issue coins nor award synthetic XP")
	var encounter: Node=world.boss_encounter
	var access:=preload("res://scripts/civic_access.gd").new(); access.world=world; world.add_child(access)
	check(not encounter.can_progress() and not access.unlocked and not world.wider_world.pyramid.visible,"Before the first Greefer confrontation, the outer city is concealed and requires a pass")
	player.global_position=Vector3(150,.05,0); access._physics_process(0)
	check(maxf(absf(player.global_position.x),absf(player.global_position.z))<128,"The locked civic boundary safely returns a bypassed exterior checkpoint to the starter district")
	camera.position=Vector3(0,32,80); camera.look_at(Vector3(0,20,-80)); camera.far=1800
	await capture("city_locked",camera)
	encounter.active=true; encounter.is_intro=true; encounter.finish(false)
	check(player.inventory.count_type(&"civic_key")==1 and encounter.can_progress() and access.unlocked and world.wider_world.pyramid.visible,"Completing Greefer's first fight grants the bound pass and reveals/opens the existing outer world")
	await capture("city_unlocked",camera)
	encounter.ensure_civic_pass(); encounter.ensure_civic_pass()
	check(player.inventory.count_type(&"civic_key")==1 and not Catalog.get_definition(&"civic_key").is_droppable,"Repeated outcomes cannot duplicate the non-droppable Civic Pass")
	var saved: Dictionary=player.inventory.serialize(); player.inventory.restore(JSON.parse_string(JSON.stringify(saved)))
	check(encounter.can_progress() and player.inventory.count_type(&"civic_key")==1,"Civic access survives ordinary inventory reload")
	var missing_pass: Dictionary=saved.duplicate(true)
	missing_pass.items=missing_pass.items.filter(func(item): return item.item_type_id!="civic_key")
	player.inventory.restore(missing_pass)
	check(encounter.can_progress() and player.inventory.count_type(&"civic_key")==1,"A completed encounter repairs an older inventory without its bound pass")
	var full: Dictionary={"version":1,"owner_id":player.inventory.owner_id,"items":[],"equipment":{}}
	for i in range(Craft.Inventory.MAX_ITEMS):
		var item: Resource=Catalog.create(&"echo_fragment"); item.owner_id=player.inventory.owner_id; item.custom_properties={"fixture":i}; full.items.append(item.to_dict())
	player.inventory.restore(full)
	check(not encounter.can_progress() and player.inventory.count_type(&"civic_key")==0,"A full inventory defers the Civic Pass without losing the completed encounter milestone")
	player.inventory.take_item(player.inventory.items.keys()[0])
	check(encounter.can_progress() and player.inventory.count_type(&"civic_key")==1,"Freeing one slot issues the deferred pass exactly once")
	player.inventory.restore(saved)
	var hall:=preload("res://scripts/glyphic_wonders_hall.gd").new(); world.add_child(hall)
	var crowns: MultiMeshInstance3D=hall.get_node("RotatingColumnCrowns")
	check(crowns.multimesh.instance_count==10 and crowns.multimesh.mesh.get_surface_count()==1,"Every grand hall pillar has a large geometric crown in one shared animated draw batch")
	camera.position=Vector3(0,34,63); camera.look_at(Vector3(0,31,-20)); camera.far=200
	await capture("wonders_crowns",camera)
	world.queue_free(); await frames(2)
	print("CRAFTING INTEGRATION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
