extends "res://tests/greefer_encounter.gd"

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	encounter._input(event)

func pad(code: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = true
	encounter._input(event)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p = world.player
	boss = world.greefer
	encounter = world.boss_encounter
	p.visual.retrieval.enabled = false
	await frames(3)
	p.set_physics_process(false)
	encounter.start(true)
	encounter.register_contact()
	encounter.finish(false)
	p.position = encounter.challenge_point
	await frames(2)
	check(boss.state == &"returning" and encounter.can_challenge(),"A real loss offers retries while Greefer is still returning")
	check(encounter._beacon.visible and encounter._beacon.get_child(0).text.contains("REMATCH"),"Challenge sigil has a visible world-space interaction label")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.pressed = true
	world.controls._unhandled_input(event)
	await frames(2)
	check(encounter.dialogue_open and not encounter.active and not world.controls.gameplay_enabled and encounter.no.has_focus(),"G opens the Ember-style confirmation with Not now selected")
	var age: float = boss.state_age
	await seconds(0.3)
	check(not paused and boss.state_age>age+0.2,"Rematch dialogue leaves the world and boss return flight running")
	key(KEY_ENTER)
	check(not encounter.dialogue_open and not encounter.active and world.controls.gameplay_enabled,"Declining restores gameplay without restarting the fight")
	world.controls.set_right_trigger(0)
	world.controls.set_right_trigger(1)
	await frames(2)
	check(encounter.dialogue_open,"RT uses the same rematch interaction")
	pad(JOY_BUTTON_DPAD_LEFT)
	pad(JOY_BUTTON_A)
	check(encounter.active and not encounter.is_intro and boss.state == &"alert" and boss.health == boss.base_health,"Controller Yes starts a full-health retry during the return flight")
	check(world.controls.gameplay_enabled and not encounter.dialogue_open and encounter.progress.losses == 1,"Retry preserves the recorded result and restores controls")
	encounter.finish(true)
	await seconds(3.2)
	check(encounter.can_challenge() and encounter.progress.wins == 1,"Victory also offers a rematch after the defeat reaction")
	encounter.interact()
	world.start_menu.open_menu()
	check(not encounter.dialogue_open and world.start_menu.is_open and not world.controls.gameplay_enabled,"Start closes the confirmation without stacking input owners")
	world.start_menu.close_menu()
	encounter.interact()
	event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	check(not encounter.dialogue_open and not encounter.active,"Escape cancels the rematch without combat")
	check(not world.start_menu.is_open and world.controls.gameplay_enabled,"Escape routes through the real input stack without opening another menu")
	encounter.interact()
	encounter._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not encounter.dialogue_open and world.controls.gameplay_enabled,"Focus loss safely closes the live confirmation")
	encounter.interact()
	p.position += Vector3(8,0,0)
	await frames(2)
	check(not encounter.dialogue_open,"Leaving the sigil closes an invalid invitation")
	world.queue_free()
	await process_frame
	print("Greefer rematch verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
