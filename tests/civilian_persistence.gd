extends SceneTree
## Whole-world service authority, rental storage and atomic checkpoint rollback.
const Catalog = preload("res://scripts/item_catalog.gd")
const Store = preload("res://scripts/inventory_store.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var services: Node
var economy: Node
var session: Node
var travel: Node
var controls: Intent
var checks := 0
var failures := 0
var callback_count := 0
var callback_accepts := 0
var callback_saves := 0
var checkpoint := "user://tests/civilian_persistence.json"
var expired_checkpoint := "user://tests/civilian_expired.json"
var callback_checkpoint := "user://tests/civilian_reentrant.json"

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 1
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func add(type: StringName,quantity: int = 1) -> Resource:
	var item: Resource = Catalog.create(type,quantity)
	p.inventory.add_item(item)
	if item.quantity>0: return item
	for owned: Resource in p.inventory.items.values():
		if owned.item_type_id==type: return owned
	return null

func owned_type(type: StringName) -> Resource:
	for item: Resource in p.inventory.items.values():
		if item.item_type_id==type: return item
	return null

func service_point(kind: StringName) -> Dictionary:
	for point: Dictionary in services._points():
		if point.kind==kind: return point
	return {}

func open_service(kind: StringName) -> bool:
	services.menu.close_menu()
	var point := service_point(kind)
	if point.is_empty(): return false
	var at: Vector3 = point.anchor.global_position
	p.global_position = Vector3(at.x,.17,at.z)+ (Vector3(-1.6,0,0) if kind==&"storage" else Vector3(0,0,.5))
	p.velocity = Vector3.ZERO
	p.fall_damage.reset()
	p.visual.rebase_after_phase()
	await frames(8)
	var opened: bool = services.interact()
	return opened and services.current.kind==kind and services.menu.is_open

func write_snapshot(path: String,snapshot: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()

func ledger_total() -> int:
	var amount := 0
	for coins: int in economy.balances.values(): amount += coins
	return amount

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Civilian persistence watchdog"); quit(2))
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.world_memory_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.dungeon_enemies_enabled = false
	world.death_drop_probability = 0
	root.add_child(world)
	p = world.player
	services = world.civilian_services
	economy = services.economy
	session = world.inventory_session
	travel = world.dungeon_travel
	controls = Intent.new()
	root.add_child(controls)
	p.controls = controls
	world.camera_rig.controls = controls
	session.controls = controls
	p.visual.retrieval.enabled = false
	await frames(20)
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	check(services!=null and travel.ready_for_travel and travel.room_ids.size()==3,"The real world connects civilian services, ledger and three private room contexts")
	var opening_equal: bool = economy.natural_ids.size()==world.population.residents.size()+4
	for resident: Node in world.population.residents:
		opening_equal = opening_equal and economy.natural_ids.has(String(resident.profile.id)) and economy.balance(economy.resident_account(String(resident.profile.id)))==100
	check(opening_equal and economy.last_cycle==0 and economy.balance(economy.player_account)==0,"Opening blessing includes every natural city resident equally while excluding the human visitor")
	check(economy.balance(economy.guild_account)==100 and economy.balance(economy.tavern_account)==100 and ledger_total()==economy.issued_total,"Founders fund independent businesses through conserved opening-capital transfers")
	var opening_total: int = economy.issued_total
	var common := add(&"monster_glyph_common",8)
	var rare := add(&"monster_glyph_rare",1)
	check(await open_service(&"reception"),"Reception opens through the actual nearby in-world interaction")
	check(economy.sell_crystal(rare.instance_id,1,p.inventory) and economy.sell_crystal(common.instance_id,1,p.inventory),"The real receptionist purchases owned crystals through treasury-funded authority calls")
	check(economy.balance(economy.player_account)==87 and economy.balance(economy.guild_account)==13 and economy.guild_stock.count_type(&"monster_glyph_rare")==1,"Reception sales conserve coins and persist actual purchased crystal stock")
	check(economy.rent(0) and economy.can_enter(0) and economy.balance(economy.player_account)==57,"The receptionist accepts payment and grants the selected room")
	var rental_deadline: float = economy.rental.expires_at
	check(await open_service(&"bartender"),"The Tavern opens its independent service interface at the bar")
	check(economy.buy_food(&"electron_meal",p.inventory) and economy.buy_food(&"electron_draught",p.inventory),"Real tavern purchases deliver usable food instances")
	check(economy.balance(economy.player_account)==37 and economy.balance(economy.guild_account)==43 and economy.balance(economy.tavern_account)==120 and ledger_total()==opening_total,"Rent and food settle to the appropriate independent accounts without issuing money")
	var inventory_before: Dictionary = p.inventory.serialize()
	var economy_before: Dictionary = economy.serialize()
	world.loot._busy = true
	check(not economy.buy_food(&"electron_meal",p.inventory) and p.inventory.serialize()==inventory_before and economy.serialize()==economy_before,"An active loot transaction prevents nested economic inventory mutation")
	world.loot._busy = false
	services.menu.close_menu()
	var room_id: StringName = travel.room_ids[0]
	check(travel.restore_location(room_id),"Authorized room construction uses the existing instanced travel context")
	await frames(6)
	check(travel.active_location==room_id and travel.room_contents.has(room_id) and travel.room_contents[room_id].get_world_3d()==p.get_world_3d(),"The room renders in a separate world while the same player and services persist")
	check(await open_service(&"storage"),"The actual private-room computer opens its storage interface")
	var sword: Resource = owned_type(&"katana")
	sword.upgrade_level = 9
	sword.custom_properties = {"engraving":"A journey kept safe"}
	var sword_id: String = sword.instance_id
	p.weapon_combat.health = 700
	var callback := func():
		callback_count += 1
		if world.loot.request_health_glyph(p.inventory): callback_accepts += 1
		if session.save_checkpoint(callback_checkpoint,true): callback_saves += 1
	p.inventory.changed.connect(callback)
	check(economy.transfer_storage(0,sword_id,1,true,p.inventory),"The terminal transfers the selected equipped sword into persistent room storage")
	p.inventory.changed.disconnect(callback)
	check(callback_count>0 and callback_accepts==0 and callback_saves==0 and p.health==700,"Inventory callbacks cannot heal, mutate other authorities, or checkpoint a half-completed storage transaction")
	check(p.inventory.get_item(sword_id)==null and economy.room_stores[0].get_item(sword_id).upgrade_level==9,"The stored sword leaves player ownership with its unique ID and upgrades intact")
	services.menu.close_menu()
	check(session.save_checkpoint(checkpoint,true),"A real whole-world checkpoint saves rented location, balances and stored gear together")
	var saved: Dictionary = Store.load_snapshot(checkpoint)
	check(not saved.is_empty() and saved.location_context==String(room_id) and saved.civilian_state.rental.expires_at==rental_deadline,"Checkpoint serialization preserves the exact rental deadline and active private-room context")
	check(await open_service(&"storage") and economy.transfer_storage(0,sword_id,1,false,p.inventory),"Room storage remains usable after saving")
	services.menu.close_menu()
	check(travel.restore_location(travel.OUTSIDE),"Leaving returns to the public guild world")
	await frames(4)
	check(not travel.room_contents.has(room_id) and p.inventory.get_item(sword_id)!=null,"Room geometry deconstructs while the withdrawn item stays owned")
	check(await open_service(&"bartender") and economy.buy_food(&"electron_meal",p.inventory),"A later real transaction changes the live wallet and food stack")
	services.menu.close_menu()
	check(session.load_checkpoint(checkpoint),"Whole-world reload restores player inventory, ledger, storage and location atomically")
	await frames(5)
	check(travel.active_location==room_id and travel.room_contents.has(room_id) and economy.balance(economy.player_account)==37 and economy.balance(economy.tavern_account)==120,"Reload reconstructs the rented room and restores the saved business balances")
	var stored: Resource = economy.room_stores[0].get_item(sword_id)
	check(p.inventory.get_item(sword_id)==null and stored!=null and stored.upgrade_level==9 and stored.custom_properties.engraving=="A journey kept safe" and p.inventory.count_type(&"electron_meal")==1,"Reload places unique stored gear and food in exactly their saved owners without duplication")
	var invalid: Dictionary = saved.duplicate(true)
	var duplicate: Dictionary = invalid.civilian_state.room_stores["0"].items[0].duplicate(true)
	duplicate.owner_id = p.inventory.owner_id
	invalid.inventory.items.append(duplicate)
	check(Store.decode(invalid).is_empty(),"Canonical checkpoint validation rejects a room item duplicated into player ownership")
	invalid = saved.duplicate(true)
	duplicate = invalid.civilian_state.room_stores["0"].items[0].duplicate(true)
	duplicate.owner_id = ""
	invalid.world_drops.append({"pickup_id":"duplicated-room-item","item":duplicate,"position":[0,0,10],"death_owner_id":""})
	check(Store.decode(invalid).is_empty(),"Canonical checkpoint validation rejects a stored item duplicated into world drops")
	invalid = saved.duplicate(true)
	invalid.civilian_state.balances[economy.player_account] += 1
	invalid.civilian_state.issued_total += 1
	check(Store.decode(invalid).is_empty(),"An internally consistent coin sum still fails if its journal cannot account for the extra currency")
	var invalid_path := "user://tests/civilian_duplicate.json"
	write_snapshot(invalid_path,invalid)
	inventory_before = p.inventory.serialize()
	economy_before = economy.serialize()
	check(not session.load_checkpoint(invalid_path) and p.inventory.serialize()==inventory_before and economy.serialize()==economy_before and travel.active_location==room_id,"Rejected checkpoint data leaves live inventory, room access and ledger untouched")
	economy.rental.expires_at = Time.get_unix_time_from_system()-1
	check(session.save_checkpoint(expired_checkpoint,true),"An expired rental can still persist its room contents while the player is inside")
	economy.rental.expires_at = rental_deadline
	check(session.load_checkpoint(expired_checkpoint),"Loading an expired rental succeeds without granting expired access")
	await frames(5)
	var arrival: Vector3 = services.establishments.room_arrivals[0].global_position
	check(travel.active_location==travel.OUTSIDE and p.global_position.distance_to(arrival)<.6 and not travel.room_contents.has(room_id),"An expired-room checkpoint safely returns the player to the public guild hallway")
	check(not economy.can_enter(0) and economy.room_stores[0].get_item(sword_id)!=null and economy.rental.expires_at<Time.get_unix_time_from_system(),"Expired access remains expired after reload while its stored gear survives")
	# Valid data with an unsupported world-drop position fails later in the
	# restore pipeline, after player and economy replacement have begun.
	invalid = saved.duplicate(true)
	if invalid.world_drops.is_empty():
		var ghost: Resource = Catalog.create(&"light_shard")
		invalid.world_drops.append({"pickup_id":"unsupported-test-drop","item":ghost.to_dict(),"position":[900000,100,900000],"death_owner_id":""})
	else: invalid.world_drops[0].position = [900000,100,900000]
	var unsupported_path := "user://tests/civilian_unsupported.json"
	write_snapshot(unsupported_path,invalid)
	inventory_before = p.inventory.serialize()
	economy_before = economy.serialize()
	var world_before: Array = world.loot.serialize_world()
	check(not session.load_checkpoint(unsupported_path) and p.inventory.serialize()==inventory_before and economy.serialize()==economy_before and world.loot.serialize_world()==world_before and travel.active_location==travel.OUTSIDE,"A later physics-validation failure rolls back player, ledger and world-drop state together")
	check(await open_service(&"reception") and economy.rent(0),"The expired room can be renewed through the receptionist using existing player funds")
	services.menu.close_menu()
	check(travel.restore_location(room_id),"Renewal reconstructs the same logical private room")
	await frames(5)
	check(await open_service(&"storage") and economy.transfer_storage(0,sword_id,1,false,p.inventory),"Renewal restores terminal access to the exact gear kept through expiry and deconstruction")
	services.menu.close_menu()
	p.weapon_combat.health = 700
	var meal: Resource = owned_type(&"electron_meal")
	check(meal!=null and services.consume_food(meal.instance_id),"A saved Tavern meal starts actual timed consumption through the player service")
	check(not services.consume_food(owned_type(&"electron_draught").instance_id),"A second food cannot overlap the currently active timed effect")
	await frames(125)
	check(is_equal_approx(p.health,760) and services.food_effect.is_empty() and p.inventory.count_type(&"electron_meal")==0,"The real consumption controller applies exactly 60 healing over two seconds and consumes one meal")
	# A legitimate item may rest on furniture above the floor. Logical room
	# support must validate it even while the rendered bedroom is unloaded.
	var bed_item := add(&"paintbrush_gold")
	var bed_item_id: String = bed_item.instance_id
	p.global_position = Vector3(-5.3,1.0,-3.6)
	p.velocity = Vector3.ZERO
	p.fall_damage.reset()
	p.visual.rebase_after_phase()
	await frames(8)
	check(world.loot.request_drop(p.inventory,bed_item_id,1,p.global_position+Vector3(0,0,1.0)),"Standing on the room bed permits a real ordinary item drop onto its upper surface")
	var bed_pickup: Node3D
	for pickup: Node3D in world.loot.pickups.values():
		if pickup.item_instance.instance_id==bed_item_id: bed_pickup = pickup
	check(is_instance_valid(bed_pickup) and bed_pickup.global_position.y>.85 and bed_pickup.location_id==room_id,"The actual dropped item rests on the mattress rather than being moved to the floor")
	var bed_inside := "user://tests/civilian_bed_inside.json"
	var bed_outside := "user://tests/civilian_bed_outside.json"
	check(session.save_checkpoint(bed_inside,true) and travel.restore_location(travel.OUTSIDE),"A furniture-supported room drop saves before normal room deconstruction")
	await frames(4)
	check(not travel.room_contents.has(room_id) and session.save_checkpoint(bed_outside,true),"Unloaded-room drops remain part of a valid whole-world checkpoint")
	check(session.load_checkpoint(bed_outside),"A checkpoint restores furniture-supported gear while its room geometry is dormant")
	await frames(3)
	check(session.load_checkpoint(bed_inside),"A checkpoint reconstructs a room containing a mattress-supported drop without a support-validation failure")
	await frames(3)
	check(ledger_total()==opening_total and not paused,"Full service, reconstruction and checkpoint lifecycle conserves issued currency without pausing the world")
	# Cold restart: no furniture from the first room may supply cached shapes.
	world.queue_free()
	controls.queue_free()
	await frames(3)
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.world_memory_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.dungeon_enemies_enabled = false
	world.death_drop_probability = 0
	root.add_child(world)
	p = world.player
	services = world.civilian_services
	economy = services.economy
	session = world.inventory_session
	travel = world.dungeon_travel
	controls = Intent.new()
	root.add_child(controls)
	p.controls = controls
	world.camera_rig.controls = controls
	session.controls = controls
	p.visual.retrieval.enabled = false
	await frames(20)
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	check(travel.room_contents.is_empty(),"A fresh world starts with no rendered or previously cached private-room geometry")
	check(session.load_checkpoint(bed_outside),"A cold-world checkpoint restores a dormant room's mattress-supported item before the room ever renders")
	await frames(3)
	check(travel.room_contents.is_empty() and travel.active_location==travel.OUTSIDE,"Cold restoration of an outside save leaves private-room geometry unloaded")
	check(session.load_checkpoint(bed_inside),"A cold-world room checkpoint validates furniture-supported loot and then reconstructs its room")
	await frames(3)
	var recovered_bed: Node3D
	for pickup: Node3D in world.loot.pickups.values():
		if pickup.item_instance.instance_id==bed_item_id: recovered_bed = pickup
	check(is_instance_valid(recovered_bed) and recovered_bed.global_position.y>.85 and travel.active_location==room_id and p.inventory.get_item(bed_item_id)==null,"Cold room reconstruction retains the exact dropped item at its saved furniture height without duplicating it")
	world.queue_free()
	controls.queue_free()
	await process_frame
	print("Civilian persistence verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
