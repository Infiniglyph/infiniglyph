extends SceneTree
## Real input queues, physics timers, the sentry damage path and phase materials.
const Library = preload("res://scripts/weapon_library.gd")
class Intent extends Node:
	var source: Node
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	func sample() -> void: pass
	func consume_jump() -> bool: return source.consume_jump()
	func consume_dodge() -> bool: return source.consume_dodge()
	func is_blocking() -> bool: return source.is_blocking()
	func update_combat_hold(delta: float) -> void: source.update_combat_hold(delta)
	func consume_combat_requests() -> Array[Dictionary]: return source.consume_combat_requests()
	func reset_combat_input() -> void: source.reset_combat_input()
var failures := 0
var checks := 0
var hz := 60
var world: Node3D
var p: CharacterBody3D
var w: Node
var controls: Node
var input: Intent
var camera: Camera3D
var action_count := 0
var parry_count := 0
var device := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func seconds(value: float) -> void:
	await frames(ceili(value*hz))

func flush() -> void:
	p.combat.poll(input)

func key(code: Key, held: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = held
	controls._unhandled_input(event)

func pad(button: JoyButton, held: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = held
	controls._unhandled_input(event)

func trigger(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	controls._unhandled_input(event)

func equip(slot: StringName) -> void:
	controls._request(&"weapon",slot)
	flush()

func toggle() -> void:
	controls._request(&"sheathe",&"")
	flush()

func attack(action: StringName) -> void:
	var button: JoyButton = JOY_BUTTON_RIGHT_SHOULDER
	if action==&"attack_left": button = JOY_BUTTON_LEFT_SHOULDER
	elif action in [&"special_x",&"special_rt_x"]: button = JOY_BUTTON_X
	elif action in [&"special_y",&"special_rt_y"]: button = JOY_BUTTON_Y
	trigger(JOY_AXIS_TRIGGER_RIGHT,0.9 if String(action).contains("rt_") else 0)
	pad(button)
	pad(button,false)
	trigger(JOY_AXIS_TRIGGER_RIGHT,0)
	flush()

func front_hit(amount: float = 10) -> float:
	return w.receive_hit(amount,p.position+w.aim_direction()*2+Vector3.UP)

func reset(slot: StringName = &"right") -> void:
	controls.reset_combat_input()
	p.respawn()
	p.position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.camera_rig.yaw = 0
	p.visual.rotation.y = PI
	input.move = Vector2.ZERO
	equip(slot)
	await frames(3)

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if camera==null:
		camera = Camera3D.new()
		camera.fov = 50
		root.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute("res://captures")
	camera.position = p.position+Vector3(-2.2,1.6,-3.6)
	camera.look_at(p.position+Vector3.UP*0.95)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/defense_"+label+".png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	w = p.weapon_combat
	controls = world.controls
	p.visual.retrieval.enabled = false
	input = Intent.new()
	input.source = controls
	root.add_child(input)
	p.controls = input
	var pads := Input.get_connected_joypads()
	if not pads.is_empty(): device = pads[0]
	for target in get_nodes_in_group("combat_targets"): target.counterattacks = false
	p.combat.action_requested.connect(func(_id: StringName,_slot: StringName): action_count+=1)
	w.parried.connect(func(_point: Vector3): parry_count+=1)
	await reset()
	for slot: StringName in Library.LOADOUTS:
		await reset(slot)
		key(KEY_DOWN)
		await seconds(0.49)
		check(p.combat.sheathed and p.combat.selected_slot==slot,"Held Down sheathes current loadout: "+String(slot))
		await seconds(0.6)
		check(p.combat.sheathed,"Continuing to hold Down does not toggle repeatedly")
		key(KEY_DOWN,false)
		await frames(1)
		pad(JOY_BUTTON_DPAD_DOWN)
		await seconds(0.49)
		check(not p.combat.sheathed and p.combat.selected_slot==slot and w.rig.models[slot].right.visible,"Held D-pad Down redraws that same loadout: "+String(slot))
		pad(JOY_BUTTON_DPAD_DOWN,false)
		await frames(1)
		check(p.combat.selected_slot==slot,"Releasing a draw hold does not select longsword")
		for action: StringName in p.combat.ACTIONS:
			equip(slot)
			toggle()
			var previous := action_count
			attack(action)
			flush()
			check(not p.combat.sheathed and p.combat.selected_slot==slot and w.active_move.get("name","")==Library.move(slot,action).name and action_count==previous+1 and w._queued.is_empty(),"One input draws and executes the current weapon art: "+String(slot)+" / "+String(action))
	await reset()
	toggle()
	key(KEY_Q)
	key(KEY_Q,false)
	await frames(1)
	check(not p.combat.sheathed and w.active_move.get("name","")=="Neon Crescent","Keyboard special draws and executes through the live player tick")
	# Each weapon can perfect-block; a held or already-spent press is normal guard.
	for slot: StringName in Library.LOADOUTS:
		await reset(slot)
		key(KEY_F)
		await seconds(0.10)
		var previous := parry_count
		var velocity := p.velocity
		var damage := front_hit(20)
		check(damage==0 and w.health==w.max_health and w.last_parried and not w.last_blocked and parry_count==previous+1 and p.velocity==velocity,"Timed front block parries with no chip or momentum change: "+String(slot))
		damage = front_hit(10)
		check(not w.last_parried and is_equal_approx(damage,10*(1-float(Library.loadout(slot).guard))),"The same press cannot parry a second hit: "+String(slot))
		await seconds(0.30)
		key(KEY_F) # Duplicate press without a release.
		flush()
		check(w.parry_remaining==0,"Holding/repeating block does not reopen its timing window")
		key(KEY_F,false)
		flush()
		key(KEY_F)
		flush()
		check(front_hit()==0 and w.last_parried,"Releasing then pressing block opens a new parry attempt")
	await reset()
	key(KEY_F)
	await seconds(0.24)
	check(is_equal_approx(front_hit(),3) and not w.last_parried,"Blocking too early keeps the katana's existing 70-percent guard")
	key(KEY_F,false)
	flush()
	key(KEY_F)
	flush()
	key(KEY_F,false)
	flush()
	check(front_hit()==10 and w.parry_remaining==0,"Releasing block before contact does not parry or guard")
	key(KEY_F)
	flush()
	check(w.receive_hit(10,p.position+Vector3.BACK*2)==10 and not w.last_blocked and w.parry_remaining>0,"A fresh block leaves the rear exposed")
	check(front_hit()==0 and w.last_parried,"Rear damage does not turn the timing window into omnidirectional immunity")
	await reset()
	key(KEY_F)
	flush()
	check(front_hit(0)==0 and w.parry_remaining>0 and not w.last_parried,"Zero-damage contacts cannot consume a parry")
	p.camera_rig.yaw = PI/2
	check(front_hit()==0 and w.last_parried,"Parry coverage follows camera yaw")
	await reset()
	trigger(JOY_AXIS_TRIGGER_LEFT,0.54)
	flush()
	check(not p.combat.blocking and w.parry_remaining==0,"Noisy LT input below threshold does not arm a parry")
	trigger(JOY_AXIS_TRIGGER_LEFT,0.56)
	flush()
	check(front_hit()==0 and w.last_parried,"LT threshold crossing arms the same timed parry")
	for value in [0.50,0.44,0.54,0.56]:
		trigger(JOY_AXIS_TRIGGER_LEFT,value)
		flush()
	check(w.parry_remaining==0 and p.combat.blocking,"LT hysteresis prevents noise from rearming a used parry")
	key(KEY_F)
	flush()
	trigger(JOY_AXIS_TRIGGER_LEFT,0)
	flush()
	check(w.parry_remaining==0 and p.combat.blocking,"Overlapping keyboard/controller block does not create extra presses")
	key(KEY_F,false)
	flush()
	trigger(JOY_AXIS_TRIGGER_LEFT,0.8)
	flush()
	check(front_hit()==0 and w.last_parried,"Fully releasing all guard sources permits the next parry")
	await reset()
	key(KEY_F)
	flush()
	toggle()
	attack(&"attack_right")
	check(not p.combat.sheathed and p.combat.blocking and w.active_move.is_empty() and w.parry_remaining>0,"Attack-to-draw retains an already held guard and its original window")
	controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	w._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	flush()
	check(not p.combat.blocking and w.parry_remaining==0,"Focus loss clears guard and pending parry timing")
	# Phase defense: the central hidden plateau alone rejects incoming damage.
	await reset()
	p.position = Vector3(0,10,0)
	p.velocity = Vector3(4,1,-2)
	var carried := p.velocity
	key(KEY_F)
	flush()
	controls.dodge_requested = true
	await frames(1)
	key(KEY_F,false)
	flush()
	check(p.dodge.active and not p.dodge.is_invulnerable() and w.parry_remaining==0,"Dodge starts visibly vulnerable and cancels pending parry timing")
	check(front_hit()==10 and not w.last_evaded,"Damage applies during visible dodge departure")
	var hidden_checks := true
	var return_checks := true
	var hidden_count := 0
	var before_shift := false
	var after_shift := false
	var returning := 0
	while p.dodge.active:
		await frames(1)
		if p.dodge.is_invulnerable():
			var health: float = w.health
			var parries := parry_count
			hidden_checks = hidden_checks and p.dodge.phase_opacity()==0 and p.dodge._fade_material.albedo_color.a==0 and front_hit(1000)==0 and w.last_evaded and not w.last_parried and w.health==health and parry_count==parries and not p.get_child(0).disabled
			hidden_count += 1
			before_shift = before_shift or not p.dodge.has_shifted
			after_shift = after_shift or p.dodge.has_shifted
			if hidden_count==1: await shot("dodge_hidden")
		elif p.dodge.active and hidden_count>0:
			return_checks = return_checks and p.dodge.phase_opacity()>0 and front_hit(1)==1 and not w.last_evaded
			returning += 1
	check(hidden_checks and hidden_count>0 and before_shift and after_shift,"The fully invisible middle protects before and after the teleport, with collision enabled")
	check(return_checks and returning>0,"Visible rematerialization is vulnerable again")
	check(not p.dodge.is_invulnerable() and front_hit()==10 and p.velocity.is_equal_approx(carried),"Dodge exit ends immunity and restores the original momentum")
	await reset()
	check(p.dodge.start(Vector3.RIGHT),"A neutral phase can start for exact boundary inspection")
	var boundaries := true
	for spec in [[0.2999,false],[0.30,true],[0.43,true],[0.60,true],[0.6001,false]]:
		p.dodge.elapsed = float(spec[0])*p.dodge.DURATION
		boundaries = boundaries and p.dodge.is_invulnerable()==spec[1] and (front_hit(1)==0)==spec[1]
	check(boundaries,"Invincibility is confined to the defined 30-to-60-percent phase interval")
	p.dodge.cancel()
	check(not p.dodge.is_invulnerable() and front_hit(1)==1,"Cancelling a phase cannot leave invincibility behind")
	p.dodge.cooldown = 1
	check(not p.dodge.start(Vector3.RIGHT) and not p.dodge.is_invulnerable(),"A rejected dodge grants no invincibility")
	p.dodge.cooldown = 0
	p.dodge.start(Vector3.RIGHT)
	p.dodge.advance(p.dodge.DURATION*0.43)
	p.respawn()
	check(not p.dodge.is_invulnerable() and w.parry_remaining==0 and w.health==w.max_health,"Respawn clears phase immunity and parry state")
	# Exercise a real sentry strike, not just direct damage calls.
	await reset()
	var sentry: Node3D
	for target in get_nodes_in_group("combat_targets"):
		if target.name=="CounterSentry": sentry = target
	p.position = sentry.position+Vector3.BACK*1.8
	await frames(2)
	sentry.counterattacks = true
	sentry._counter_time = 0.12
	key(KEY_F)
	await seconds(0.15)
	check(w.health==w.max_health and w.last_parried and w.parry_feedback>0,"A correctly timed LT/F block parries the actual counter sentry")
	var hud: Control = world.find_child("CombatHUD",true,false)
	check(hud.guard.text=="PARRY!","A successful parry has persistent HUD feedback")
	await shot("parry")
	await seconds(0.3)
	sentry._counter_time = 0.08
	await seconds(0.12)
	check(is_equal_approx(w.health,w.max_health-3) and not w.last_parried,"Holding that block turns the next sentry hit into normal chip damage")
	sentry.counterattacks = false
	await seconds(0.8)
	check(get_nodes_in_group("weapon_effects").is_empty() and w.parry_feedback==0,"Parry flash and feedback expire without accumulating")
	world.queue_free()
	input.queue_free()
	if camera!=null: camera.queue_free()
	await process_frame
	print("Defense/draw verification: ",checks," checks at ",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
