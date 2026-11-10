extends SceneTree
## Exercise the actual world, input routing, combat resolver and local checkpoint.
const Catalog = preload("res://scripts/item_catalog.gd")
const Library = preload("res://scripts/weapon_library.gd")
var world: Node3D
var session: Node
var actor: CharacterBody3D
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count): await process_frame

func pad(button: int, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()

func tap(button: int) -> void:
	await pad(button)
	await pad(button,false)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	session = world.inventory_session
	await frames(20)
	var inventory: Node = actor.inventory
	var loot: Node = world.loot
	check(inventory.equipment.size()==4 and inventory.items.size()==5 and inventory.count_type(&"health_glyph")==3,"Four owned loadouts and three Health Glyphs start in inventory")
	check(not session.persistence_enabled,"Command-line tools isolate their inventory from normal-game saves")
	actor.position = Vector3(13,0.15,16.4)
	actor.velocity = Vector3.ZERO
	await frames(8)
	await key(KEY_G)
	var collected := false
	for owned: Resource in inventory.items.values():
		if owned.item_type_id==&"light_shard" and owned.quantity==3: collected = true
	check(collected and session.notice.text.contains("Collected"),"G collects a physical level pickup and displays its notification")
	session.show_notice("Collected test fragment")
	session.save_checkpoint("user://tests/quiet_inventory_checkpoint.json",true)
	check(session.notice.text=="Collected test fragment","Background saves preserve the visible pickup notification")
	actor.position = Vector3(13,0.15,19)
	actor.velocity = Vector3.ZERO
	await frames(8)
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1
	Input.parse_input_event(trigger)
	await frames(5)
	trigger = InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0
	Input.parse_input_event(trigger)
	await frames(3)
	var trigger_collected := false
	for owned: Resource in inventory.items.values():
		if owned.item_type_id==&"signal_tonic": trigger_collected = true
	check(trigger_collected,"RT uses the same contextual pickup interaction")
	actor.position = actor.spawn
	actor.velocity = Vector3.ZERO
	await frames(8)
	await pad(JOY_BUTTON_X)
	check(actor.combat.charge_action!=&"","The input isolation test begins with a real held special")
	await tap(JOY_BUTTON_BACK)
	check(session.ui.is_open and not paused and not world.controls.gameplay_enabled,"View opens live inventory and suppresses local gameplay input")
	await pad(JOY_BUTTON_X,false)
	check(actor.combat.charge_action==&"" and actor.weapon_combat.active_move.is_empty(),"Opening inventory cancels a held special without casting on release")
	var start: Vector3 = actor.position
	var slot: StringName = actor.combat.selected_slot
	await tap(JOY_BUTTON_A)
	await tap(JOY_BUTTON_DPAD_RIGHT)
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	await frames(15)
	check(actor.position.is_equal_approx(start) and not actor.dodge.active and actor.weapon_combat.active_move.is_empty(),"Menu confirm/navigation cannot jump, dodge or attack")
	check(actor.combat.selected_slot==slot,"Menu D-pad navigation cannot switch the active combat weapon")
	await tap(JOY_BUTTON_BACK)
	check(not session.ui.is_open and not paused and world.controls.gameplay_enabled,"View closes inventory from a modal and restores gameplay")
	await frames(4)
	check(not actor.dodge.active and actor.velocity.y<=0,"Closing the menu leaks no queued dodge or Sky Jump")
	await key(KEY_B)
	check(session.ui.is_open,"Keyboard B opens the same inventory")
	await key(KEY_ESCAPE)
	check(not session.ui.is_open and not paused,"Escape closes inventory while keeping simulation live")
	world.controls.set_right_trigger(1.0)
	check(not world.controls.special_modified() and not world.controls.consume_interaction(),"A trigger held through menu close cannot leak a gameplay modifier or interaction")
	world.controls.set_right_trigger(0.0)
	world.controls.set_right_trigger(1.0)
	check(world.controls.special_modified(),"Releasing and pressing the trigger restores normal gameplay use")
	world.controls.set_right_trigger(0.0)
	await tap(JOY_BUTTON_BACK)
	await tap(JOY_BUTTON_B)
	check(not session.ui.is_open and not actor.dodge.active,"Controller B closes inventory without leaking a gameplay dodge")
	# Both solo and network inventory leave timers and actual player physics live.
	for network_mode: bool in [false,true]:
		session.live_session = network_mode
		actor.position = Vector3(0,8,-106)
		actor.velocity = Vector3.ZERO
		await tap(JOY_BUTTON_BACK)
		var timer := Timer.new()
		timer.wait_time = 0.04
		timer.one_shot = true
		world.add_child(timer)
		var fired := [false]
		timer.timeout.connect(func(): fired[0] = true)
		timer.start()
		await frames(24)
		check(session.ui.is_open and not paused and not world.controls.gameplay_enabled and fired[0] and actor.position.y<7,"Inventory keeps timers and gravity live in "+("network" if network_mode else "solo")+" mode")
		if network_mode:
			check(not session.save_checkpoint("user://tests/network_forbidden.json"),"A local checkpoint cannot authoritatively save network ownership")
		await tap(JOY_BUTTON_BACK)
	session.live_session = false
	actor.respawn()
	await frames(20)
	# Every moveset can be assigned to every direction without changing its data.
	var instances: Dictionary = {}
	for item: Resource in inventory.items.values(): instances[item.item_type_id] = item.instance_id
	var combinations := 0
	for direction: StringName in [&"up",&"down",&"left",&"right"]:
		for canonical: StringName in Library.LOADOUTS:
			var type: StringName = Library.loadout(canonical).id
			if not loot.request_equip(inventory,direction,instances[type]): continue
			actor.combat.selected_slot = direction
			actor.combat.refresh_equipment()
			var actual: Dictionary = actor.weapon_combat.move_for(direction,&"special_x")
			var expected: Dictionary = Library.move(canonical,&"special_x")
			if actor.weapon_combat.rig.selected==canonical and actual==expected: combinations += 1
	check(combinations==16,"All four owned movesets resolve correctly in all four D-pad slots")
	loot.request_equip(inventory,&"up",instances[&"katana"])
	actor.combat.selected_slot = &"up"
	actor.combat.refresh_equipment()
	actor.weapon_combat._begin(actor.weapon_combat.move_for(&"up",&"attack_right"))
	await frames(15)
	check(actor.weapon_combat.loadout(&"up").id==&"katana" and actor.weapon_combat.rig.selected==&"right","A reassigned katana keeps its existing two-hand model and combat profile")
	actor.weapon_combat.cancel()
	var item: Resource = inventory.get_item(instances[&"katana"])
	item.upgrade_level = 3
	item.custom_properties = {"engraving":"owned neon","nested":{"serial":17}}
	check(loot.request_drop(inventory,item.instance_id,1,actor.position+Vector3(1.2,0,0)),"An equipped instance drops through the host transaction")
	check(not inventory.items.has(item.instance_id) and actor.combat.resolve_slot(&"up")==&"" and actor.weapon_combat.rig.selected==&"","Dropping the active item clears its equipment and weapon model")
	world.controls._request(&"action",&"attack_right")
	actor.combat.poll(world.controls)
	check(actor.weapon_combat.active_move.is_empty(),"An empty slot cannot conjure a fallback weapon attack")
	var dropped: Node3D
	for pickup: Node3D in loot.pickups.values():
		if pickup.item_instance.instance_id==item.instance_id: dropped = pickup
	check(dropped != null and dropped.item_instance.upgrade_level==3,"Dropped equipment preserves its specific identity and upgrade")
	var checkpoint := "user://tests/inventory_integrated.json"
	check(session.save_checkpoint(checkpoint),"A versioned checkpoint saves owned equipment and physical world drops together")
	check(loot.request_pickup(inventory,dropped),"The actual player can recollect the dropped weapon")
	check(session.load_checkpoint(checkpoint),"The whole single-player checkpoint restores atomically")
	var copies := int(inventory.items.has(item.instance_id))
	var restored: Node3D
	for pickup: Node3D in loot.pickups.values():
		if pickup.item_instance.instance_id==item.instance_id:
			copies += 1
			restored = pickup
	check(copies==1 and restored != null and restored.item_instance.custom_properties==item.custom_properties,"Loading never duplicates a transferred weapon or loses custom properties")
	# The death callback is idempotent even after respawn resets health.
	loot.death_drop_probability = 1
	var eligible: int = inventory.eligible_equipped().size()
	if eligible==0: loot.request_equip(inventory,&"down",instances[&"sword_shield"])
	var before_count: int = inventory.items.size()
	actor.weapon_combat.health = 0
	actor.on_combat_defeat()
	var after_first: int = inventory.items.size()
	actor.on_combat_defeat()
	check(after_first==before_count-1 and inventory.items.size()==after_first,"Repeated death callbacks lose at most one equipped item")
	check(loot.markers.for_owner(inventory.owner_id).size()==1,"A real player death publishes a reusable lost-equipment map marker")
	check(actor.health==1000,"Respawn restores health without restoring the lost equipment")
	# Nonlethal sparring remains separate from actual death penalties.
	actor.position = world.sparring_partner.home+Vector3(-2,0,0)
	await frames(15)
	world.sparring_duel.start()
	var owned_before: int = inventory.items.size()
	await tap(JOY_BUTTON_START)
	check(world.start_menu.is_open and world.sparring_duel.active,"Start opens the live system menu during a duel")
	world.start_menu.yield_duel()
	check(not world.sparring_duel.active and inventory.items.size()==owned_before,"The Start menu preserves controller access to duel yielding")
	world.sparring_duel.start()
	actor.weapon_combat.health = 0
	actor.on_combat_defeat()
	check(not world.sparring_duel.active and inventory.items.size()==owned_before,"Nonlethal sparring never rolls a death equipment penalty")
	world.queue_free()
	await frames()
	print("Inventory integration verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
