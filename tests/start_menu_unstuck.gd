extends SceneTree
## Actual input, live-world simulation and physical capsule recovery.
var world: Node3D
var actor: CharacterBody3D
var menu: CanvasLayer
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func tap(button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await ticks(2)
	event = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	await ticks(2)

func escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await ticks(2)
	event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = false
	Input.parse_input_event(event)
	await ticks(2)

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/system_"+label+".png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	menu = world.start_menu
	await ticks(20)
	await tap(JOY_BUTTON_START)
	check(menu.is_open and not paused and not world.controls.gameplay_enabled,"Start opens the system overlay without pausing the game")
	check(menu._home_controls[0].has_focus(),"Controller focus begins on Resume")
	await shot("menu")
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	check(menu.settings_open,"Controller navigation opens Settings")
	await shot("settings")
	var initial_mouse: float = actor.camera_rig.mouse_sensitivity
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(actor.camera_rig.mouse_sensitivity>initial_mouse,"Controller left/right changes real mouse sensitivity")
	menu._stick_speed.value = 3.1
	menu._fov.value = 80
	menu._volume.value = 33
	menu._shake.button_pressed = false
	check(is_equal_approx(actor.camera_rig.stick_sensitivity,3.1) and actor.camera_rig.camera.fov==80 and not actor.weapon_combat.rules.camera_shake_enabled,"Settings update camera look, FOV and impact shake")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(0))-0.33)<0.001,"Master volume updates the real audio bus")
	var path := "user://tests/system_settings.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	check(menu.save_settings(path),"Settings save to a native versioned configuration file")
	menu._fov.value = 60
	menu._volume.value = 100
	menu._shake.button_pressed = true
	check(menu.load_settings(path) and actor.camera_rig.camera.fov==80 and not actor.weapon_combat.rules.camera_shake_enabled,"Saved settings restore actual values")
	var slot: StringName = actor.combat.selected_slot
	await tap(JOY_BUTTON_X)
	await tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(actor.combat.selected_slot==slot and actor.combat.charge_action==&"" and actor.weapon_combat.active_move.is_empty() and not actor.dodge.active,"Menu inputs cannot attack, charge, dodge or switch a combat weapon")
	# A live timer and gravity must keep advancing behind this overlay.
	var fired := [false]
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.one_shot = true
	world.add_child(timer)
	timer.timeout.connect(func(): fired[0] = true)
	timer.start()
	actor.position = Vector3(0,8,-106)
	actor.velocity = Vector3.ZERO
	await ticks(ceili(0.4*hz))
	check(fired[0] and actor.position.y<7,"World timers and player gravity continue while Settings is open")
	await tap(JOY_BUTTON_B)
	check(menu.is_open and not menu.settings_open,"B returns from Settings to the main overlay")
	await tap(JOY_BUTTON_B)
	check(not menu.is_open and world.controls.gameplay_enabled and not actor.dodge.active,"B closes the overlay without leaking a dodge")
	actor.respawn()
	await ticks(20)
	await escape()
	check(menu.is_open and not paused,"Escape opens the same live menu")
	await escape()
	check(not menu.is_open,"Escape closes the system menu")
	world.inventory_session.ui.open_menu()
	check(not paused,"Single-player inventory also keeps the world live")
	await tap(JOY_BUTTON_START)
	check(menu.is_open and not world.inventory_session.ui.is_open and not paused,"Start switches live overlays without pausing")
	menu.close_menu()
	world.inventory_session.ui.open_menu()
	await escape()
	check(not menu.is_open and not world.inventory_session.ui.is_open and not paused,"Escape backs out of inventory without opening another menu")
	# Land the actual player on a thin handrail, then recover using the UI action.
	actor.respawn()
	actor.position = Vector3(-12.5,14.3,-36)
	actor.velocity = Vector3.ZERO
	await ticks(ceili(1.5*hz))
	check(actor.is_on_floor() and actor.position.y>13,"The railing fixture puts the actual capsule on the narrow top bar")
	check(actor.unstuck.needs_recovery(),"A thin railing is recognized as unsafe footing")
	var before: Vector3 = actor.position
	var owned: Dictionary = actor.inventory.serialize()
	var world_items: Array = world.loot.serialize_world()
	actor.weapon_combat.health = 743
	actor.weapon_combat.psi_meter = 28
	actor.weapon_combat.enter_forced(&"parried",0.8,actor.position+Vector3.FORWARD)
	menu.open_menu()
	menu.recover_player()
	check(not menu.is_open and actor.position.distance_to(before)>0.4 and actor.position.distance_to(before)<3,"Unstick pops off the rail onto nearby clear space and resumes play")
	check(actor.unstuck.clear_at(actor.position) and actor.unstuck.broad_support(actor.position),"The destination fits the whole capsule and a broad floor footprint")
	check(actor.health==743 and actor.weapon_combat.psi_meter==28 and actor.weapon_combat.is_staggered(),"Recovery preserves health, exhaustion and forced combat recovery")
	check(actor.inventory.serialize()==owned and world.loot.serialize_world()==world_items,"Unstick never respawns, drops, duplicates or restores equipment")
	await ticks(ceili(0.6*hz))
	check(actor.is_on_floor() and actor.position.y<12.4 and actor.health==743,"Recovered footing settles normally without phantom fall damage")
	# Ordinary freefall must continue to require sky-step braking.
	actor.respawn()
	actor.position = Vector3(0,80,-106)
	actor.velocity = Vector3(0,-20,0)
	await ticks(10)
	var velocity: Vector3 = actor.velocity
	var falling_position: Vector3 = actor.position
	var result: Dictionary = actor.unstuck.recover()
	check(not result.ok and actor.position==falling_position and actor.velocity==velocity,"Unstick cannot teleport or brake an ordinary unobstructed fall")
	actor.respawn()
	await ticks(ceili(0.4*hz))
	var clear_position: Vector3 = actor.position
	result = actor.unstuck.recover()
	check(not result.ok and actor.position==clear_position,"Clear ordinary ground does not trigger a needless relocation")
	check(actor.unstuck.has_safe,"Broad stable footing is remembered for a genuine embedded-body fallback")
	# Deep inside a solid building: local candidates are blocked, use verified history.
	actor.position = Vector3(-24,10,24)
	actor.velocity = Vector3.ZERO
	result = actor.unstuck.recover()
	check(result.ok and actor.unstuck.clear_at(actor.position) and actor.position.distance_to(clear_position)<0.2,"A body embedded in a solid building returns to verified safe footing")
	# Quit is the last action so the real engine can exercise its normal exit path.
	menu.open_menu()
	var quit_seen := [false]
	menu.quit_requested.connect(func(): quit_seen[0] = true)
	menu.quit_game()
	check(quit_seen[0],"Quit Game emits its request and exits through the normal engine path")
	print("Start menu/recovery verification: ",checks," checks, ",failures," failures @",hz," Hz")
	quit(1 if failures else 0)
