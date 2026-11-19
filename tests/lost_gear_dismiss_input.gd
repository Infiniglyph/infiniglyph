extends "res://tests/lost_gear_hud.gd"
## Route real View/B events through the live inventory session, including
## short taps, long holds, menu handoff and interrupted input sources.
func button(pressed: bool, keyboard: bool = false, echo: bool = false) -> void:
	var event: InputEvent
	if keyboard:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_B
		key.keycode = KEY_B
		key.pressed = pressed
		key.echo = echo
		event = key
	else:
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_BACK
		pad.pressed = pressed
		event = pad
	Input.parse_input_event(event)
	await frames()

func loss(at: Vector3, owner: String = "") -> Node3D:
	var pickup := Pickup.new()
	pickup.item_instance = Catalog.create(&"katana")
	pickup.death_owner_id = owner if not owner.is_empty() else actor.inventory.owner_id
	loot.add_child(pickup)
	pickup.global_position = at
	check(loot.register_pickup(pickup),"Fixture creates an actual unclaimed death-loss pickup")
	return pickup

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	session = world.inventory_session
	loot = world.loot
	await frames(12)
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	actor.set_physics_process(false)
	session.set_process(false) # Drive the hold timer exactly, independent of render rate.
	await button(true)
	check(session.ui.is_open and not world.controls.gameplay_enabled,"Without a loss, View opens inventory on its normal press")
	await button(false)
	await button(true)
	await button(false)
	check(not session.ui.is_open and world.controls.gameplay_enabled,"View still closes inventory without leaking gameplay input")
	var first := loss(Vector3(0,0,11))
	var second := loss(Vector3(5,0,14))
	var foreign := loss(Vector3(-5,0,14),"other-player")
	check(session.loss_hint.visible and session.loss_hint.text.contains("2 unclaimed"),"Only the local outstanding losses appear before dismissal")
	await button(true)
	session._advance_inventory_hold(.15)
	check(not session.ui.is_open and session.loss_hint.visible and not first.loss_dismissed,"A pending hold keeps gameplay live and leaves lost gear intact")
	await button(false)
	check(session.ui.is_open and not first.loss_dismissed,"A short View release opens inventory without starting item expiry")
	await button(true)
	await button(false)
	check(not session.ui.is_open,"View closes the menu after a short lost-gear tap")
	await button(true)
	await button(true,true)
	session._advance_inventory_hold(.2)
	await button(false)
	check(not session.ui.is_open and session._inventory_pending,"Overlapping keyboard/controller sources stay one pending gesture")
	await button(false,true)
	check(session.ui.is_open,"The final release opens inventory exactly once across two input sources")
	await button(true)
	await button(false)
	var view := Camera3D.new()
	world.add_child(view)
	view.global_position = Vector3(2,1.6,6)
	view.look_at(first.global_position+Vector3.UP*.7)
	view.current = true
	await frames()
	await shot("before_dismiss")
	await button(true)
	session._advance_inventory_hold(.69)
	check(session.loss_hint.visible and not first.loss_dismissed,"Holding below 0.7 seconds does not dismiss or expire loot")
	session._advance_inventory_hold(.02)
	check(first.loss_dismissed and second.loss_dismissed and not foreign.loss_dismissed and not session.loss_hint.visible and session.loss_hint.text.is_empty(),"A completed View hold hides the HUD and times only the owner's outstanding losses")
	check(not session.ui.is_open and world.controls.gameplay_enabled and session.notice.text.contains("5 minutes"),"Dismissal leaves gameplay active and explains the five-minute grace period")
	var deadline: float = first.loss_expires_at
	session._advance_inventory_hold(2)
	await button(false)
	check(first.loss_expires_at==deadline and not session.ui.is_open,"Continued hold/release neither renews the deadline nor opens inventory")
	await frames()
	await shot("dismissed_countdown")
	var checkpoint := "user://tests/dismiss_input.json"
	check(session.save_checkpoint(checkpoint,true) and session.load_checkpoint(checkpoint),"Dismissed gear and its countdown pass through the real checkpoint")
	await frames()
	check(not session.loss_hint.visible and entries().all(func(entry: Dictionary): return entry.get("dismissed",false)),"Reload cannot restore a dismissed HUD or lose dismissal metadata")
	var third := loss(Vector3(-3,0,11))
	check(session.loss_hint.visible and session.loss_hint.text.contains("1 unclaimed"),"A new death-loss item restores guidance independently of previous dismissal")
	await button(true,true)
	session._advance_inventory_hold(.3)
	await button(true,true,true)
	check(session._inventory_hold_elapsed==.3,"Keyboard auto-repeat cannot reset the hold countdown")
	session._advance_inventory_hold(.41)
	await button(false,true)
	check(third.loss_dismissed and not session.loss_hint.visible and not session.ui.is_open,"Holding keyboard B performs the same dismissal without an inventory toggle")
	var fourth := loss(Vector3(3,0,11))
	await button(true)
	session._advance_inventory_hold(.3)
	session._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	session._advance_inventory_hold(1)
	await button(false)
	check(not fourth.loss_dismissed and not session.ui.is_open,"Focus loss cancels a pending hold and consumes its stale release")
	await button(true)
	session._advance_inventory_hold(.3)
	session._inventory_pad_connection_changed(0,false)
	session._advance_inventory_hold(1)
	await button(false)
	check(not fourth.loss_dismissed and not session.ui.is_open,"Controller disconnect cancels the hold without a delayed inventory or deletion action")
	await button(true)
	session._advance_inventory_hold(.3)
	world.start_menu.open_menu()
	session._advance_inventory_hold(1)
	await button(false)
	world.start_menu.close_menu()
	check(not fourth.loss_dismissed and not session.ui.is_open,"Opening Start interrupts a dismissal hold")
	await button(true)
	session._advance_inventory_hold(.71)
	await button(false)
	check(fourth.loss_dismissed and not paused,"A fresh hold works after interruptions and world simulation never pauses")
	var recovered := loss(Vector3(0,0,8))
	await button(true)
	session._advance_inventory_hold(.2)
	actor.global_position = recovered.global_position+Vector3(1,0,0)
	await frames()
	check(loot.request_pickup(actor.inventory,recovered),"Lost gear remains recoverable during a pending hold")
	session._advance_inventory_hold(1)
	await button(false)
	check(not session.loss_hint.visible and not session.ui.is_open,"Recovering the last visible loss cancels the pending hold without opening inventory")
	loss(Vector3(-3,0,11))
	actor.inventory.respawn_points = {"home":{"location":"overworld","position":[0,.025,6],"yaw":0.0,"camera_yaw":0.0,"camera_pitch":0.0}}
	loot.death_drop_probability = 0
	await button(true)
	session._advance_inventory_hold(.2)
	actor.weapon_combat.health = 0
	actor.on_combat_defeat()
	check(world.respawn_glyphs.waiting and session._inventory_sources.is_empty(),"Death clears held Select before the respawn chooser captures its release")
	await button(false)
	world.respawn_glyphs.choose("default")
	await button(true)
	session._advance_inventory_hold(.1)
	await button(false)
	check(session.ui.is_open,"The first Select press after respawn works even when its previous release was swallowed by the chooser")
	world.queue_free()
	await process_frame
	print("LOST GEAR DISMISS INPUT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
