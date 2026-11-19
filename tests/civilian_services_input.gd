extends SceneTree
## Native service/inventory input routing and interaction isolation across worlds.
const Catalog = preload("res://scripts/item_catalog.gd")
const Store = preload("res://scripts/inventory_store.gd")
var world: Node3D
var services: Node
var actor: CharacterBody3D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	await frames()
	if not echo:
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
		await frames()

func pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	await frames()
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await frames()

func reception() -> void:
	if services.menu.is_open: services.menu.close_menu()
	actor.global_position = services.establishments.guild.to_global(Vector3(-12,.17,9.2))
	actor.velocity = Vector3.ZERO
	actor.visual.rebase_after_phase()
	world.controls.set_gameplay_enabled(true)
	await frames(15)
	await key(KEY_G)

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	# On the test Intel/ANGLE backend, viewport image readbacks can omit cached
	# font draws while text and bounds remain intact. Capture one page per process
	# to avoid adding repeated-readback artifacts during visual review.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-page=") and argument.get_slice("=",1)!=label: return
	# Wait for thirty actual rendered frames, rather than saving during a font
	# atlas update or immediately after a page's container layout changes.
	for index in range(30):
		await process_frame
		await RenderingServer.frame_post_draw
	var all_fit := true
	for control: Control in services.menu._screen.find_children("*","Control",true,false):
		if not control.is_visible_in_tree(): continue
		if not control is Label and not control is Button: continue
		if control.text.is_empty(): continue
		all_fit = all_fit and root.get_visible_rect().encloses(control.get_global_rect())
		print("CAPTURE TEXT ",label," ",control.text.replace("\n"," | ")," rect=",control.get_global_rect())
	check(all_fit,"Settled "+label+" service labels and buttons fit inside the rendering viewport")
	DirAccess.make_dir_recursive_absolute("res://captures")
	var path := "res://captures/civilian_settled_"+label+"_"+str(Time.get_ticks_msec())+".png"
	var error := root.get_texture().get_image().save_png(path)
	check(error==OK,"The settled "+label+" service page saves as a fresh native render")
	print("SETTLED CAPTURE: ",ProjectSettings.globalize_path(path))

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Civilian service input verification timed out"); quit(1))
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.world_memory_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.dungeon_enemies_enabled = false
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	services = world.civilian_services
	world.inventory_session.save_path = "user://tests/civilian_services_input.json"
	await frames(25)
	await reception()
	check(services.menu.is_open and not world.controls.gameplay_enabled and not world.start_menu.is_open,"Keyboard G opens the actual reception page and captures local gameplay controls")
	await capture("reception")
	var crystal: Resource = Catalog.create(&"monster_glyph_common",8)
	actor.inventory.add_item(crystal)
	check(services.economy.sell_crystal(crystal.instance_id,8,actor.inventory),"The input fixture earns rental funds through a real authorized crystal sale")
	await key(KEY_ENTER)
	var expires: float = services.economy.rental.get("expires_at",0)
	check(services.economy.balance(services.economy.player_account)==66 and services.economy.can_enter(0),"A native Enter press pays exactly one rental without GUI double acceptance")
	await key(KEY_ENTER,true)
	check(services.economy.balance(services.economy.player_account)==66 and services.economy.rental.get("expires_at")==expires,"Keyboard echo cannot renew and charge a second rental")
	var elapsed: float = world.population.elapsed
	var at: Vector3 = actor.global_position
	await key(KEY_S)
	await key(KEY_W)
	await frames(5)
	check(world.population.elapsed>elapsed and not paused and actor.global_position.distance_to(at)<.1,"Service navigation leaves city simulation live while preventing player movement")
	services._crystals()
	await key(KEY_B)
	check(services.menu.is_open and services.menu._title.text.contains("RECEPTION") and not world.inventory_session.ui.is_open,"Keyboard B returns from a child service page without opening Inventory")
	await key(KEY_ESCAPE)
	check(not services.menu.is_open and not world.start_menu.is_open and world.controls.gameplay_enabled,"Escape closes the home service page without opening Start")
	await reception()
	await pad(JOY_BUTTON_BACK)
	check(not services.menu.is_open and world.inventory_session.ui.is_open and not world.controls.gameplay_enabled,"Select/View hands the service menu to Inventory without leaking gameplay input")
	await pad(JOY_BUTTON_B)
	check(not world.inventory_session.ui.is_open and world.controls.gameplay_enabled,"Controller B closes Inventory after the service handoff")
	await reception()
	await pad(JOY_BUTTON_START)
	check(not services.menu.is_open and world.start_menu.is_open and not world.controls.gameplay_enabled,"Controller Start closes services and opens the existing system menu")
	await pad(JOY_BUTTON_B)
	check(not world.start_menu.is_open and world.controls.gameplay_enabled,"Controller Back resumes gameplay after Start")
	await reception()
	await key(KEY_F5)
	var saved := Store.load_snapshot(world.inventory_session.save_path)
	check(not saved.is_empty() and saved.civilian_state.balances[services.economy.player_account]==66,"Service F5 saves the exact wallet and room through the existing checkpoint")
	services.menu.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not services.menu.is_open and world.controls.gameplay_enabled,"Focus loss closes service pages without leaving local controls latched")
	var food: Resource = Catalog.create(&"electron_meal",2)
	actor.inventory.add_item(food)
	actor.weapon_combat.health -= 100
	var hp: float = actor.health
	await pad(JOY_BUTTON_BACK)
	world.inventory_session.ui.select_item(food.instance_id)
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	check(actor.inventory.count_type(&"electron_meal")==1 and not services.food_effect.is_empty() and world.inventory_session.ui.mode.is_empty(),"Inventory's real Eat action consumes exactly one meal and begins recovery")
	await frames(130)
	check(is_equal_approx(actor.health,hp+60) and world.inventory_session.ui.is_open,"Inventory stays usable while food recovery applies over time")
	await key(KEY_B)
	check(not world.inventory_session.ui.is_open and world.controls.gameplay_enabled,"Keyboard B closes Inventory once after using food")
	world.dungeon_travel._set_location(world.dungeon_travel.room_ids[0])
	actor.global_position = Vector3(0,.17,0)
	actor.velocity = Vector3.ZERO
	await frames(15)
	var foreign := Marker3D.new()
	world.dungeon_travel.outside_root.add_child(foreign)
	foreign.global_position=actor.global_position+Vector3.UP*1.2
	check(not services.near({"anchor":foreign}),"A service anchor at identical coordinates in another World3D remains inaccessible")
	var foreign_seat := {"point":actor.global_position+Vector3.UP*.6,"forward":Vector3.FORWARD,"occupant":null,"world":world.dungeon_travel.outside_root.get_world_3d()}
	world.world_actions.seats.append(foreign_seat)
	check(world.world_actions.nearest().is_empty(),"A same-coordinate outdoor chair cannot appear as a private-room seat")
	check(not world.inventory_session.can_talk(),"An empty room center cannot fall through to outdoor shop or resident interactions")
	await key(KEY_G)
	check(not services.menu.is_open and not world.inventory_session.shop.is_open and not world.inventory_session.resident_dialogue.visible,"Room interaction input does not activate a nearby outdoor service or conversation")
	check(actor.weapon_combat.active_move.is_empty() and not paused,"All service and inventory shortcuts avoid attacks and keep world time running")
	if "--capture" in OS.get_cmdline_user_args():
		actor.global_position = Vector3(3.4,.17,-3.3)
		actor.velocity = Vector3.ZERO
		await frames(15)
		await key(KEY_G)
		check(services.menu.is_open and services.current.kind==&"storage","The settled computer capture uses the actual reconstructed terminal")
		await capture("computer")
		services.menu.close_menu()
		world.dungeon_travel._set_location(&"overworld")
		actor.global_position = services.establishments.tavern.to_global(Vector3(0,.17,-5.3))
		actor.velocity = Vector3.ZERO
		await frames(15)
		await key(KEY_G)
		check(services.menu.is_open and services.current.kind==&"bartender","The settled tavern capture uses the actual public counter")
		await capture("tavern")
	world.queue_free()
	await frames(3)
	print("Civilian service input verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
