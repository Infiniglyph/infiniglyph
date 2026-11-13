extends SceneTree
## Real controller traversal, contextual inputs and authoritative shop transfers.
var world: Node3D
var actor: CharacterBody3D
var session: Node
var shop: CanvasLayer
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func key(code: int, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()

func tap_key(code: int) -> void:
	await key(code)
	await key(code,false)

func pad(button: int, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()

func tap_pad(button: int) -> void:
	await pad(button)
	await pad(button,false)

func _initialize() -> void: call_deferred("run")

func capture(name_value: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/"+name_value+".png")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.get_slice("=",1))
	Engine.physics_ticks_per_second = hz
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	session = world.inventory_session
	shop = session.shop
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(12)
	# Both edges of the full flight, walking and running, without a jump.
	for x: float in [-1.3,0,1.3]:
		actor.respawn()
		actor.position = Vector3(x,0.2,-47)
		world.camera_rig.yaw = 0
		await frames(10)
		if x>0: await key(KEY_SHIFT)
		await key(KEY_W)
		for tick in range(hz*6):
			await frames(1)
			if actor.position.z<-56: break
		await key(KEY_W,false)
		if x>0: await key(KEY_SHIFT,false)
		check(actor.position.y>3.0 and actor.position.z<-56,"%s climbs all tower steps at x=%.1f without jumping (%s)" % ["Running" if x>0 else "Walking",x,actor.position])
		check(actor.air_step_count==0,"Stair ascent never invokes Sky Jump")
	await capture("tower_stairs")
	await key(KEY_S)
	for tick in range(hz*6):
		await frames(1)
		if actor.position.z>-47: break
	await key(KEY_S,false)
	check(actor.position.z>-47 and actor.position.y<0.1,"Backward movement descends the entire flight to the avenue")
	# Continue across the top platform to the solid crystal pedestal.
	actor.position = shop.anchor()+Vector3(0,0.1,3.2)
	actor.velocity = Vector3.ZERO
	await frames(8)
	check(shop.can_use(actor) and session.can_talk(),"The pedestal is reachable and participates in the existing interaction context")
	await tap_key(KEY_G)
	check(shop.is_open and not world.controls.gameplay_enabled and not paused,"G opens a live shop and gates local gameplay only")
	var inventory: Node = actor.inventory
	var original_equipment: Dictionary = inventory.equipment.duplicate()
	var start_count: int = inventory.count_type(&"sword_shield")
	await tap_key(KEY_ENTER) # Weapons department
	await tap_key(KEY_ENTER)
	check(inventory.count_type(&"sword_shield")==start_count+1,"One keyboard selection grants exactly one sword and shield")
	var spear_count: int = inventory.count_type(&"spear")
	await tap_pad(JOY_BUTTON_DPAD_DOWN)
	await tap_pad(JOY_BUTTON_A)
	check(inventory.count_type(&"spear")==spear_count+1,"Controller selection grants one spear without a duplicate GUI press")
	for id: StringName in [&"katana",&"twin_blades",&"health_glyph"]:
		var before: int = inventory.count_type(id)
		check(shop.buy(id) and inventory.count_type(id)==before+1,"Exchange adds one owned %s" % id)
	check(inventory.equipment==original_equipment,"Buying gear preserves existing equipped weapons")
	var valid := true
	for item: Resource in inventory.items.values():
		valid = valid and item.is_valid() and item.owner_id==inventory.owner_id
	check(valid,"All purchased items retain valid unique identity and local ownership")
	check(world.world_actions.glyph_count.text.ends_with(str(inventory.count_type(&"health_glyph"))),"Purchases update the existing Health Glyph HUD")
	await capture("tower_exchange")
	var glyphs: int = inventory.count_type(&"health_glyph")
	var reentered := [false]
	var attempt := func(): reentered[0] = reentered[0] or world.loot.request_shop_purchase(inventory,shop.SHOP_ID,&"health_glyph")
	inventory.changed.connect(attempt)
	world.loot.changed.connect(attempt)
	check(shop.buy(&"health_glyph") and not reentered[0] and inventory.count_type(&"health_glyph")==glyphs+1,"Inventory signal callbacks cannot duplicate a guarded purchase transaction")
	inventory.changed.disconnect(attempt)
	world.loot.changed.disconnect(attempt)
	world.loot.host_enabled = false
	check(not shop.buy(&"health_glyph"),"A non-authoritative client cannot mint shop items")
	world.loot.host_enabled = true
	world.loot.validator = func(operation: StringName, _inventory: Node, _payload: Dictionary): return operation!=&"shop_purchase"
	check(not shop.buy(&"health_glyph"),"Host validation can reject a shop transaction")
	world.loot.validator = Callable()
	check(not shop.buy(&"civic_key") and not world.loot.request_shop_purchase(inventory,&"forged_shop",&"health_glyph"),"Unknown offers and unregistered shops cannot grant items")
	shop.prices["health_glyph"] = 5
	check(not shop.buy(&"health_glyph"),"Future nonzero prices never silently grant free goods")
	shop.prices["health_glyph"] = 0
	shop.refresh()
	var snapshot: Dictionary = inventory.serialize()
	check(session.save_checkpoint("user://tests/tower-shop.json",true),"Purchases save through the existing checkpoint pipeline")
	inventory.take_item(inventory.equipment[&"down"],1)
	check(session.load_checkpoint("user://tests/tower-shop.json") and inventory.serialize()==snapshot,"Purchased gear and Glyphs survive checkpoint reload")
	var time_node := Timer.new()
	time_node.wait_time = 0.05
	time_node.one_shot = true
	world.add_child(time_node)
	var elapsed := [false]
	time_node.timeout.connect(func(): elapsed[0] = true)
	time_node.start()
	await frames(hz/4)
	check(elapsed[0] and not paused and not actor.dodge.active and actor.combat.charge_action==&"","World timers keep running and UI selections do not trigger combat")
	await tap_pad(JOY_BUTTON_B)
	check(shop.is_open and not shop.browser.visible,"B returns from a department to the exchange lobby")
	await tap_pad(JOY_BUTTON_B)
	check(not shop.is_open and world.controls.gameplay_enabled and not actor.dodge.active,"B leaves the shop without dodging")
	world.controls.set_right_trigger(0)
	world.controls.set_right_trigger(1)
	# Assert the press edge before native hardware polling can report the
	# real controller's neutral trigger and synthesize a release in this fixture.
	check(not shop.is_open,"Holding RT alone does not open the shop early")
	world.controls.set_right_trigger(0)
	await frames()
	check(shop.is_open,"A bare RT release opens the exchange")
	await tap_key(KEY_ESCAPE)
	check(not shop.is_open and not world.start_menu.is_open,"Escape leaves the exchange without also opening Start")
	# The healing chord has precedence even in range of the exchange.
	actor.weapon_combat.health = 500
	var glyphs_before: int = inventory.count_type(&"health_glyph")
	world.controls.set_right_trigger(0)
	world.controls.set_right_trigger(1)
	var chord := InputEventJoypadButton.new()
	chord.button_index = JOY_BUTTON_B
	chord.pressed = true
	world.controls._unhandled_input(chord)
	world.controls.set_right_trigger(0)
	chord.pressed = false
	world.controls._unhandled_input(chord)
	await frames()
	check(not shop.is_open and not actor.dodge.active and actor.health==850 and inventory.count_type(&"health_glyph")==glyphs_before-1,"RT+B near the pedestal heals without opening the shop or dodging")
	await tap_key(KEY_G)
	await tap_pad(JOY_BUTTON_BACK)
	check(not shop.is_open and session.ui.is_open and not world.controls.gameplay_enabled,"View transfers from shop to the live inventory")
	session.ui.close_menu()
	await tap_key(KEY_G)
	await tap_pad(JOY_BUTTON_START)
	check(not shop.is_open and world.start_menu.is_open and not world.controls.gameplay_enabled,"Start transfers cleanly to the system overlay")
	world.start_menu.close_menu()
	await tap_key(KEY_G)
	actor.position = Vector3(0,0.2,10)
	actor.velocity = Vector3.ZERO
	await frames(5)
	check(not shop.is_open and not world.loot.request_shop_purchase(inventory,shop.SHOP_ID,&"health_glyph"),"Leaving the tower closes the shop and authority rejects remote purchases")
	actor.position = shop.anchor()+Vector3(0,0.1,3.2)
	actor.velocity = Vector3.ZERO
	await frames(8)
	await tap_key(KEY_G)
	actor.weapon_combat.health = 0
	check(not world.loot.request_shop_purchase(inventory,shop.SHOP_ID,&"health_glyph"),"Defeated players cannot purchase")
	await frames(3)
	check(not shop.is_open,"Defeat closes the exchange")
	world.queue_free()
	await frames()
	print("Tower shop verification at %d Hz: %d checks, %d failures" % [hz,checks,failures])
	quit(1 if failures else 0)
