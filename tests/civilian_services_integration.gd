extends SceneTree
## Actual world routing, ownership authority, rented World3D and furniture.
const Catalog = preload("res://scripts/item_catalog.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var controls: Intent
var services: Node
var economy: Node
var travel: Node
var checks := 0
var failures := 0
var hz := 60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	Engine.max_physics_steps_per_frame = 1
	call_deferred("run")

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func place(at: Vector3) -> void:
	if services.menu.is_open: services.menu.close_menu()
	if world.world_actions.attached(): world.world_actions.detach()
	p.weapon_combat.cancel()
	controls.reset_combat_input()
	controls.move = Vector2.ZERO
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.fall_damage.reset()
	p.unstuck.reset_history()
	p.visual.rebase_after_phase()
	await frames(ceili(.65*hz))

func point(id: StringName) -> Dictionary:
	for data: Dictionary in services._points():
		if data.id==id: return data
	return {}

func foot(anchor: Node3D, y: float) -> Vector3:
	var at := anchor.global_position
	at.y = y+.05
	return at

func key_g() -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_G
		event.physical_keycode = KEY_G
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)
	await frames(3)

func finish_transition() -> void:
	for i in range(hz*4):
		if not travel.busy: break
		await frames(1)
	await frames(ceili(.65*hz))

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	for content: Node3D in travel.room_contents.values():
		for geometry: GeometryInstance3D in content.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
	var pose_camera: Camera3D
	if label=="bed_rest":
		pose_camera = Camera3D.new()
		world.add_child(pose_camera)
		pose_camera.cull_mask = 2
		pose_camera.fov = 60
		pose_camera.global_position = Vector3(0,3,0)
		pose_camera.look_at(Vector3(-5.3,1,-3.6))
		pose_camera.current = true
	await frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/civilian_services_"+label+".png")
	print("CIVILIAN SERVICES CAPTURE: ",label)
	if is_instance_valid(pose_camera):
		world.camera_rig.camera.current = true
		pose_camera.queue_free()

func enter_room() -> bool:
	await place(services.establishments.room_arrivals[0].global_position)
	await key_g()
	var began: bool = travel.busy
	await finish_transition()
	return began and travel.is_rental() and travel.room_number()==0

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.world_memory_enabled = false
	# This fixture isolates fixed service prices and treasury settlement.
	world.civilization_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.dungeon_enemies_enabled = false
	world.death_drop_probability = 0
	world.neon_glow_enabled = false
	root.add_child(world)
	p = world.player
	services = world.civilian_services
	economy = services.economy
	travel = world.dungeon_travel
	world.controls.set_process_unhandled_input(false)
	controls = Intent.new()
	root.add_child(controls)
	controls.interaction_context = world.inventory_session
	world.controls = controls
	p.controls = controls
	world.camera_rig.controls = controls
	world.inventory_session.controls = controls
	p.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		world.camera_rig.camera.cull_mask = 2
		for parent: Node3D in [services.establishments,p]:
			for geometry: GeometryInstance3D in parent.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
	await frames(10)
	check(travel.ready_for_travel and travel.contexts.size()==6 and travel.room_ids.size()==3 and not is_instance_valid(travel.hall_content),"Actual world integrates the overworld, pyramid, three lodging contexts and dormant shop")
	check(services._people.size()==4 and economy.natural_ids.size()==104 and economy.balance(economy.player_account)==0,"Service keepers and two seated adventurers join the resident census without giving visitors a blessing")
	var issued: int = economy.issued_total
	check(not economy.rent(0) and economy.rental.is_empty(),"Remote rental requests fail outside a live reception interaction")
	await place(foot(point(&"reception").anchor,.12))
	await key_g()
	check(services.menu.is_open and services.current.id==&"reception" and not controls.gameplay_enabled and not paused,"G opens the actual reception service menu and captures local controls while time stays live")
	await capture("reception")
	services.menu._rows[0].pressed.emit()
	check(economy.rental.is_empty() and economy.balance(economy.player_account)==0,"Choosing an unaffordable rental creates neither access nor currency")
	var crystal: Resource = Catalog.create(&"monster_glyph_common")
	crystal.quantity = 4
	check(p.inventory.add_item(crystal),"Fixture earns its rental budget from four real owned monster crystals")
	var iid := String(crystal.instance_id)
	for i in range(4): services._sell(iid)
	check(economy.balance(economy.player_account)==48 and economy.balance(economy.guild_account)==52 and p.inventory.get_item(iid)==null,"Reception buys actual crystals with finite guild money and removes the sold stack")
	services._home()
	services.menu._rows[0].pressed.emit()
	check(economy.can_enter(0) and economy.balance(economy.player_account)==18 and economy.balance(economy.guild_account)==82 and economy.balance(economy.tavern_account)==100,"Rental UI grants room1 by transferring thirty coins to the independent guild treasury")
	services.menu.close_menu()
	await place(services.establishments.room_arrivals[1].global_position)
	await key_g()
	check(not travel.busy and not travel.inside() and not travel.room_contents.has(travel.room_ids[1]),"An unrented upstairs door shows its refusal without constructing private geometry")
	var inventory_before: Dictionary = p.inventory.serialize()
	var outdoor_world: World3D = p.get_world_3d()
	check(await enter_room(),"G at the rented upstairs door performs the normal deconstruction and reconstruction sequence")
	check(p.get_world_3d()!=outdoor_world and travel.room_contents.has(travel.room_ids[0]) and p.is_on_floor() and p.inventory.serialize()==inventory_before and controls.gameplay_enabled,"Authorized room entry preserves inventory and safely changes the player's real World3D")
	var private_seats := 0
	for data: Dictionary in world.world_actions.seats:
		if data.get("world")==p.get_world_3d(): private_seats += 1
	check(private_seats==1,"The private chair registers once with shared seating in its own World3D")
	var content: Node3D = travel.room_contents[travel.active_location]
	await place(content.to_global(Vector3(6.2,.17,-2.5)))
	var candidate: Dictionary = world.world_actions.nearest()
	check(candidate.get("kind")=="seat","The private chair is reachable through the shared contextual seating search")
	await key_g()
	check(world.world_actions.attached() and not services.menu.is_open,"G beside the private chair sits rather than opening a farther furniture service")
	if services.menu.is_open: services.menu.close_menu()
	if not world.world_actions.attached(): world.world_actions.interact()
	check(world.world_actions.attached() and p.collision_mask==0,"Shared chair attachment applies its normal safe seated pose and collision state")
	if world.world_actions.attached():
		controls.move = Vector2.RIGHT
		await frames(3)
		controls.move = Vector2.ZERO
	check(not world.world_actions.attached() and p.collision_mask!=0,"Moving stands up and restores ordinary collision after private seating")
	await place(content.to_global(Vector3(5.1,.17,-3.3)))
	await key_g()
	check(services.menu.is_open and services.current.kind==&"storage","The room computer opens its room-specific storage through the normal G interaction")
	await capture("computer")
	var gear: Resource = Catalog.create(&"paintbrush_violet")
	check(p.inventory.add_item(gear),"Add one unique owned weapon for real room storage transfer")
	var gear_id := String(gear.instance_id)
	check(economy.transfer_storage(0,gear_id,1,true,p.inventory) and p.inventory.get_item(gear_id)==null and economy.room_stores[0].get_item(gear_id)!=null,"Computer deposit transfers the weapon's exact identity to the room owner without duplication")
	services.menu.close_menu()
	check(not economy.transfer_storage(0,gear_id,1,false,p.inventory),"Closing the computer removes storage transaction authorization")
	await place(content.to_global(Vector3(-3.2,.17,-3.6)))
	p.weapon_combat.health = 800
	await key_g()
	check(services.menu.is_open and services.current.kind==&"bed","The furnished bed exposes its live resting and sleeping choices")
	services.menu._rows[0].pressed.emit()
	await frames(hz)
	check(world.world_actions.attached() and world.world_actions.seat.get("bed",false) and p.health>810 and p.health<815 and not paused,"Rest lies on the bed and restores health over elapsed live simulation time")
	await capture("bed_rest")
	controls.move = Vector2.RIGHT
	await frames(4)
	controls.move = Vector2.ZERO
	check(not world.world_actions.attached() and services.food_effect.is_empty(),"Moving gets out of bed and cancels its recovery effect")
	await place(content.spawn_anchor.global_position)
	await key_g()
	check(travel.busy,"G at the private exit begins return to the public guild hallway")
	await finish_transition()
	check(not travel.inside() and not travel.room_contents.has(travel.room_ids[0]) and p.global_position.distance_to(services.establishments.room_arrivals[0].global_position)<.3 and economy.room_stores[0].get_item(gear_id)!=null,"Exit unloads room geometry, retains stored ownership and returns to the correct upstairs door")
	check(await enter_room(),"A still-authorized rental can reconstruct a second time")
	check(economy.room_stores[0].get_item(gear_id)!=null,"Stored gear survives private-room deconstruction and reconstruction")
	content = travel.room_contents[travel.active_location]
	await place(content.to_global(Vector3(5.1,.17,-3.3)))
	await key_g()
	check(economy.transfer_storage(0,gear_id,1,false,p.inventory) and p.inventory.get_item(gear_id)!=null and economy.room_stores[0].get_item(gear_id)==null,"Reconstructed computer returns the same unique weapon without loss or duplication")
	services.menu.close_menu()
	await place(content.spawn_anchor.global_position)
	p.receive_hit(5000,p.combat_point()+Vector3.BACK)
	await frames(ceili(.7*hz))
	check(not travel.inside() and p.health>0 and p.is_on_floor() and not travel.room_contents.has(travel.room_ids[0]) and p.global_position.distance_to(services.establishments.room_arrivals[0].global_position)<.3,"Death inside lodging safely respawns in the public hallway and unloads the room")
	var stale_seats := 0
	for data: Dictionary in world.world_actions.seats:
		if data.get("id")==&"room_chair": stale_seats += 1
	check(stale_seats==0 and not world.world_actions.attached(),"Leaving or dying removes the private chair's stale world references")
	await place(foot(point(&"bartender").anchor,.12))
	await key_g()
	check(services.menu.is_open and services.current.kind==&"bartender","The independent tavern keeper can be reached through normal world interaction")
	await capture("tavern")
	services.menu._rows[0].pressed.emit()
	check(p.inventory.count_type(&"electron_meal")==1 and economy.balance(economy.player_account)==10 and economy.balance(economy.tavern_account)==108 and economy.balance(economy.guild_account)==82,"Tavern meal purchase transfers only the stated price to the tavern treasury")
	var meal_id := ""
	for item: Resource in p.inventory.items.values():
		if item.item_type_id==&"electron_meal": meal_id = item.instance_id
	p.weapon_combat.health = 800
	check(services.consume_food(meal_id),"A purchased electron meal can begin its configured timed consumption effect")
	check(not services.consume_food(meal_id) and p.inventory.count_type(&"electron_meal")==0,"Repeated consume input neither duplicates a meal nor restarts its active recovery")
	await frames(ceili(2.2*hz))
	check(is_equal_approx(p.health,860) and services.food_effect.is_empty(),"Electron meal recovery integrates over its duration and finishes at the configured sixty health")
	services.menu.close_menu()
	check(economy.issued_total==issued and not paused,"All service transactions conserve issued currency and leave the world running")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	print("Civilian services integration: ",checks," checks, ",failures," failures @",hz," Hz")
	quit(1 if failures else 0)
