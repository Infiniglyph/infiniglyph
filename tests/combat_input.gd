extends SceneTree
## Verify the input-to-player contract. Timed execution is covered by weapons.gd.
var failures := 0
var world: Node3D
var controls: Node
var combat: Node
var actions: Array[Dictionary] = []
var selected: Array[StringName] = []
var blocks: Array[bool] = []
var device := 0

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func tick() -> void:
	await physics_frame
	await process_frame

func pad(button: JoyButton, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	controls._unhandled_input(event)

func tap(button: JoyButton) -> void:
	pad(button)
	pad(button,false)

func trigger(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	controls._unhandled_input(event)

func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	controls._unhandled_input(event)

func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	controls._unhandled_input(event)

func flush() -> void:
	combat.poll(controls)

func reset() -> void:
	controls.reset_combat_input()
	combat.reset()
	combat.selected_slot = &"down"
	actions.clear()
	selected.clear()
	blocks.clear()

func action_ids() -> Array:
	return actions.map(func(action: Dictionary): return action.id)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	controls = world.controls
	combat = world.player.combat
	world.player.visual.retrieval.enabled = false
	world.player.set_physics_process(false)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty(): device = pads[0]
	combat.action_requested.connect(func(id: StringName, slot: StringName): actions.append({"id":id,"slot":slot}))
	combat.weapon_slot_selected.connect(func(slot: StringName): selected.append(slot))
	combat.block_changed.connect(func(held: bool): blocks.append(held))
	for i in range(20): await tick()
	var hud: Control = world.find_child("CombatHUD",true,false)
	check(root.get_visible_rect().encloses(hud.get_global_rect()),"Compact player HUD stays inside the viewport")
	reset()
	tap(JOY_BUTTON_RIGHT_SHOULDER)
	tap(JOY_BUTTON_LEFT_SHOULDER)
	flush()
	check(action_ids() == [&"attack_right",&"attack_left"],"RB and LB route to the correct anatomical attack side")
	check(actions[0].slot == &"down" and actions[1].slot == &"down","Attacks include the currently selected weapon slot")
	reset()
	pad(JOY_BUTTON_RIGHT_SHOULDER)
	pad(JOY_BUTTON_RIGHT_SHOULDER)
	flush()
	flush()
	check(actions.size() == 1,"Holding a bumper emits one request, not automatic repeated attacks")
	pad(JOY_BUTTON_RIGHT_SHOULDER,false)
	tap(JOY_BUTTON_RIGHT_SHOULDER)
	flush()
	check(actions.size() == 2,"Releasing and pressing a bumper permits the next attack")
	reset()
	tap(JOY_BUTTON_X)
	tap(JOY_BUTTON_Y)
	trigger(JOY_AXIS_TRIGGER_RIGHT,0.9)
	tap(JOY_BUTTON_X)
	tap(JOY_BUTTON_Y)
	trigger(JOY_AXIS_TRIGGER_RIGHT,0)
	flush()
	check(action_ids() == [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"],"X/Y and held RT+X/Y produce four exclusive special commands")
	check(not controls.special_modified(),"Releasing RT before the physics tick does not change already requested specials")
	reset()
	trigger(JOY_AXIS_TRIGGER_RIGHT,1)
	flush()
	check(actions.is_empty(),"RT by itself does not cast a special")
	pad(JOY_BUTTON_X)
	pad(JOY_BUTTON_X)
	flush()
	check(actions.is_empty() and combat.charge_action == &"special_rt_x","Holding X with RT charges its special without firing or repeating")
	trigger(JOY_AXIS_TRIGGER_RIGHT,0)
	trigger(JOY_AXIS_TRIGGER_RIGHT,1)
	flush()
	check(actions.is_empty() and combat.charge_action == &"special_rt_x","Changing RT while X remains held preserves the original charge")
	pad(JOY_BUTTON_X,false)
	flush()
	check(action_ids() == [&"special_rt_x"],"Releasing X casts the originally selected modified special once")
	reset()
	trigger(JOY_AXIS_TRIGGER_LEFT,0.54)
	flush()
	check(not combat.blocking,"A partial/noisy LT press below threshold does not start a block")
	trigger(JOY_AXIS_TRIGGER_LEFT,0.56)
	flush()
	check(combat.blocking,"LT starts a held block after crossing the press threshold")
	for value in [0.5,0.53,0.44]:
		trigger(JOY_AXIS_TRIGGER_LEFT,value)
		flush()
	check(combat.blocking and blocks == [true],"Trigger hysteresis keeps block stable around the press threshold")
	trigger(JOY_AXIS_TRIGGER_LEFT,0.39)
	flush()
	check(not combat.blocking and blocks == [true,false],"Releasing LT ends block exactly once")
	reset()
	key(KEY_F)
	trigger(JOY_AXIS_TRIGGER_LEFT,1)
	flush()
	key(KEY_F,false)
	flush()
	check(combat.blocking,"Releasing keyboard block keeps guard held while LT is still down")
	trigger(JOY_AXIS_TRIGGER_LEFT,0)
	flush()
	check(not combat.blocking,"Guard releases when both block sources are released")
	reset()
	key(KEY_Q)
	key(KEY_Q,false)
	key(KEY_R)
	key(KEY_R,false)
	key(KEY_V)
	key(KEY_Q)
	key(KEY_Q,false)
	key(KEY_R)
	key(KEY_R,false)
	key(KEY_V,false)
	flush()
	check(action_ids() == [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"],"Q/R and held V+Q/R match all four controller specials")
	reset()
	key(KEY_Q)
	key(KEY_Q,true,true)
	key(KEY_Q)
	key(KEY_Q,false)
	flush()
	check(actions.size() == 1,"Keyboard repeat and duplicate pressed events do not repeat a special")
	reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse(MOUSE_BUTTON_LEFT,true)
	mouse(MOUSE_BUTTON_LEFT,false)
	flush()
	check(actions.is_empty(),"Clicking to capture the cursor does not also attack")
	if DisplayServer.get_name() == "headless":
		print("SKIP: Native mouse capture requires a display; run without --headless for mouse attack checks")
	else:
		mouse(MOUSE_BUTTON_LEFT,true)
		mouse(MOUSE_BUTTON_LEFT,false)
		mouse(MOUSE_BUTTON_RIGHT,true)
		mouse(MOUSE_BUTTON_RIGHT,false)
		flush()
		check(action_ids() == [&"attack_left",&"attack_right"],"Left/right mouse buttons map to left/right attacks after capture")
	reset()
	for button in [JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_UP]:
		tap(button)
		flush()
	check(selected == [&"down",&"left",&"right",&"up"] and combat.selected_slot == &"up","D-pad directly selects each of the four weapon slots")
	reset()
	for code in [KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_UP]:
		key(code)
		key(code,false)
		flush()
	check(selected == [&"down",&"left",&"right",&"up"],"Keyboard arrows directly select the matching slots")
	check(controls.move.is_zero_approx(),"Weapon selection does not turn arrow keys into movement input")
	reset()
	tap(JOY_BUTTON_DPAD_LEFT)
	tap(JOY_BUTTON_RIGHT_SHOULDER)
	tap(JOY_BUTTON_DPAD_RIGHT)
	trigger(JOY_AXIS_TRIGGER_RIGHT,1)
	tap(JOY_BUTTON_X)
	flush()
	check(actions.size() == 2 and actions[0].slot == &"left" and actions[1].slot == &"right","A quick swap and attack in one tick preserve the input order and correct slot")
	flush()
	check(actions.size() == 2,"Consumed commands do not replay on later physics ticks")
	reset()
	key(KEY_F)
	trigger(JOY_AXIS_TRIGGER_LEFT,1)
	trigger(JOY_AXIS_TRIGGER_RIGHT,1)
	tap(JOY_BUTTON_X)
	key(KEY_Q)
	controls._on_joy_connection_changed(device,false)
	flush()
	check(combat.blocking and not controls._pad_block and not controls._pad_modifier,"Disconnecting the controller clears its triggers while retaining keyboard guard")
	# Guard prevents starting a charge; release it, then verify keyboard holds
	# survive removal of an unrelated controller without changing the modifier.
	key(KEY_F,false)
	key(KEY_Q,false)
	flush()
	key(KEY_V)
	key(KEY_Q)
	flush()
	controls._on_joy_connection_changed(device,false)
	key(KEY_V,false)
	key(KEY_Q,false)
	flush()
	check(action_ids() == [&"special_rt_x"],"Disconnect drops controller commands while a keyboard special still releases with its original modifier")
	reset()
	key(KEY_F)
	key(KEY_V)
	flush()
	key(KEY_R)
	controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	flush()
	check(not combat.blocking and not controls.special_modified() and actions.is_empty(),"Losing application focus releases held actions and clears pending attacks")
	# Verify the real player's physics tick drains the contract, including while phasing.
	reset()
	world.player.set_physics_process(true)
	key(KEY_DOWN)
	key(KEY_DOWN,false)
	key(KEY_Q)
	key(KEY_Q,false)
	await tick()
	check(actions.size() == 1 and combat.last_action == &"special_x","The live player consumes combat commands during normal physics")
	controls.dodge_requested = true
	await tick()
	check(world.player.dodge.active,"Existing phase dodge still starts")
	key(KEY_F)
	key(KEY_LEFT)
	key(KEY_LEFT,false)
	key(KEY_R)
	key(KEY_R,false)
	await tick()
	check(combat.selected_slot == &"left" and combat.blocking and combat.charge_action == &"","Slot selection and held guard remain responsive during a dodge without starting a guarded charge")
	world.player.respawn()
	check(not combat.blocking and controls.consume_combat_requests().is_empty(),"Respawn clears held combat state and pending commands")
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(25): await tick()
		key(KEY_RIGHT)
		key(KEY_RIGHT,false)
		key(KEY_F)
		key(KEY_V)
		key(KEY_R)
		key(KEY_R,false)
		await tick()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/combat_bindings.png")
	world.queue_free()
	await process_frame
	print("Combat input verification: ",failures," failures")
	quit(1 if failures else 0)
