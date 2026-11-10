extends SceneTree
const Library = preload("res://scripts/weapon_library.gd")
const Target = preload("res://scripts/practice_target.gd")
class Intent extends Node:
	var source: Node
	var move := Vector2.ZERO
	var look := Vector2.ZERO
	var mouse_look := Vector2.ZERO
	var sprint := false
	var boost := false
	func sample() -> void:
		if not source.gameplay_enabled: move = Vector2.ZERO
	func consume_jump() -> bool: return source.consume_jump()
	func consume_dodge() -> bool: return source.consume_dodge()
	func is_blocking() -> bool: return source.is_blocking()
	func update_combat_hold(delta: float) -> void: source.update_combat_hold(delta)
	func consume_combat_requests() -> Array[Dictionary]: return source.consume_combat_requests()
	func consume_lock_requests() -> Array[Vector2]: return source.consume_lock_requests()
	func consume_interaction() -> bool: return source.consume_interaction()
	func reset_combat_input() -> void: source.reset_combat_input()
	func set_gameplay_enabled(value: bool) -> void: source.set_gameplay_enabled(value)
var world: Node3D
var p: CharacterBody3D
var w: Node
var npc: CharacterBody3D
var duel: CanvasLayer
var controls: Node
var input: Intent
var dummy: StaticBody3D
var hz := 60
var checks := 0
var failures := 0
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

func seconds(value: float) -> void: await frames(ceili(value*hz))

func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	controls._unhandled_input(event)

func pad(button: JoyButton, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	controls._unhandled_input(event)

func trigger(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	event.device = device
	controls._unhandled_input(event)

func special(action: StringName, pressed: bool = true) -> void:
	trigger(1 if String(action).contains("rt_") else 0)
	pad(JOY_BUTTON_X if String(action).ends_with("x") else JOY_BUTTON_Y,pressed)

func equip(slot: StringName) -> void:
	controls._request(&"weapon",slot)
	p.combat.poll(input)

func reset() -> void:
	if duel.active: duel.finish(false)
	if duel.dialogue_open: duel.answer(false)
	controls.set_gameplay_enabled(true)
	p.respawn()
	p.position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	input.move = Vector2.ZERO
	input.boost = false
	input.sprint = false
	world.camera_rig.yaw = 0
	world.camera_rig.pitch = -0.22
	await seconds(0.3)

func approach() -> void:
	p.position = npc.home+Vector3(-2,0,0)
	p.velocity = Vector3.ZERO
	await seconds(0.35)

func shot(label: String, focus: Vector3) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = focus+Vector3(-4,2.5,5)
	camera.look_at(focus+Vector3.UP)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/sparring_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current = true

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	# The stationary damage fixture measures animation/weapon timing, while
	# civilian bodies can physically push it during this long sampling loop.
	world.player.set_collision_mask_value(3,false)
	world.player.set_collision_mask_value(4,false)
	p = world.player
	w = p.weapon_combat
	controls = world.controls
	npc = world.sparring_partner
	duel = world.sparring_duel
	p.visual.retrieval.enabled = false
	input = Intent.new()
	input.source = controls
	root.add_child(input)
	p.controls = input
	world.camera_rig.controls = input
	var pads := Input.get_connected_joypads()
	if not pads.is_empty(): device = pads[0]
	await reset()
	check(npc.is_on_floor() and npc.position.distance_to(npc.home)<0.1,"Ember stands on the solid east sidewalk beside the sentries")
	check(npc.body_ink.albedo_color.r>0.9 and npc.light.light_energy>0 and npc.light.omni_range>0,"Orange partner has local body material and emits real light")
	var body_sphere: MeshInstance3D = npc.visual.joints.RightLeg.get_child(0)
	check(body_sphere.material_override == npc.body_ink,"The rendered body stays orange after the initial dodge/reset restoration")
	check(not npc.is_in_group("combat_targets") and npc.collision_layer == 1 and npc.receive_hit(500,p.position) == 0,"Idle partner is solid, friendly and immune to stray attacks")
	check(npc.weapon_combat.rig.models.size() == 4 and npc.sky_jump_lift == p.sky_jump_lift and npc.boost_speed == p.boost_speed,"Partner shares all four loadouts, sky steps and movement tuning")
	# Every normal/RT special, and all charged variants, use real timed hit windows.
	dummy = Target.new()
	dummy.health = 100000
	dummy.max_health = 100000
	world.add_child(dummy)
	dummy.position = Vector3(0,0,-1.5)
	await frames(2)
	for slot: StringName in Library.LOADOUTS:
		equip(slot)
		for action: StringName in [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			var base := Library.move(slot,action)
			var before: float = dummy.total_damage
			special(action)
			special(action,false)
			await seconds(float(base.duration)+0.08)
			check(is_equal_approx(dummy.total_damage-before,float(base.damage)*base.hits.size()),"Tap preserves existing special: "+base.name)
			before = dummy.total_damage
			var before_hits: int = dummy.hit_count
			special(action)
			await seconds(1.3)
			check(dummy.total_damage == before and w.active_move.is_empty() and p.combat.charge_elapsed>=1.19,"Hold charges without an early hit or auto-release: "+base.name)
			if slot == &"right" and action == &"special_x":
				var wrist: Vector3 = p.visual.joints.LeftArm.get_node("Hinge").to_global(Vector3(0,-0.29,0))
				check(wrist.distance_to(w.rig.right_hand.to_global(Vector3(0,-0.17,0)))<0.02,"Katana charge keeps both hands on the shared hilt")
				await shot("charge",p.position)
			special(action,false)
			await frames(1)
			var charged := Library.charged_move(slot,action,1)
			check(w.active_move.get("charge",0)>0.99 and float(w.active_move.reach)>float(base.reach) and float(w.active_move.duration)>float(base.duration),"Release selects the extended version: "+base.name)
			await seconds(float(charged.duration)+0.1)
			check(is_equal_approx(dummy.total_damage-before,float(charged.damage)*charged.hits.size()) and dummy.hit_count-before_hits == charged.hits.size(),"Higher damage and one extra finishing contact: "+base.name)
			check(p.position.distance_to(Vector3.ZERO)<0.04 and p.velocity.length()<0.01,"Charge pose adds no root motion: "+base.name)
	# Timing and input cancellation edge cases cannot produce a delayed ghost attack.
	equip(&"right")
	key(KEY_V)
	key(KEY_Q)
	await seconds(0.6)
	key(KEY_V,false)
	key(KEY_Q,true,true)
	key(KEY_Q)
	await frames(1)
	check(p.combat.charge_action == &"special_rt_x" and w.active_move.is_empty(),"Modifier is captured on press and key repeat cannot discharge a hold")
	key(KEY_Q,false)
	await frames(1)
	check(w.active_move.name == "Extended Afterimage Waltz" and float(w.active_move.charge)>0.25 and float(w.active_move.charge)<1,"Partial keyboard hold releases the matching modified special")
	await seconds(1.6)
	for cancellation in ["weapon","sheathe","block","dodge","focus","disconnect"]:
		equip(&"right")
		controls.reset_combat_input()
		special(&"special_x")
		await seconds(0.55)
		if cancellation == "weapon": equip(&"left")
		elif cancellation == "sheathe": controls._request(&"sheathe",&"")
		elif cancellation == "block": key(KEY_F)
		elif cancellation == "dodge": controls.dodge_requested = true
		elif cancellation == "focus":
			controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			w._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif cancellation == "disconnect": controls._on_joy_connection_changed(device,false)
		await frames(2)
		var hits: int = dummy.hit_count
		special(&"special_x",false)
		key(KEY_F,false)
		await seconds(0.8)
		check(p.combat.charge_action == &"" and w.active_move.is_empty() and dummy.hit_count == hits,"Cancelled charge cannot fire on release: "+cancellation)
		await reset()
	# Movement and impact momentum remain live while the special is held.
	equip(&"left")
	input.move = Vector2.RIGHT
	key(KEY_Q)
	await seconds(0.8)
	check(p.position.x>1 and p.velocity.x>3.4 and p.combat.charge_action == &"special_x","Movement remains responsive during charging")
	key(KEY_Q,false)
	await frames(1)
	check(w.active_move.get("charge",0)>0,"Moving release retains accumulated charge")
	await reset()
	equip(&"left")
	p.set_physics_process(false)
	w.set_physics_process(false)
	key(KEY_Q)
	p.combat.poll(input)
	p.combat.advance_charge(3.0)
	check(is_equal_approx(p.combat.charge_elapsed,1.2) and w.active_move.is_empty(),"Overholding clamps charge at full without automatically attacking")
	key(KEY_Q,false)
	p.combat.poll(input)
	p.velocity = Vector3.FORWARD*10.2
	var before_momentum: float = dummy.total_damage
	w._physics_process(0.11)
	check(is_equal_approx(dummy.total_damage-before_momentum,16*1.65*1.5),"Charged damage multiplies with speed sampled at impact")
	w.cancel()
	p.velocity = Vector3.ZERO
	p.set_physics_process(true)
	w.set_physics_process(true)
	await reset()
	dummy.queue_free()
	await frames(2)
	p.set_collision_mask_value(3,true)
	p.set_collision_mask_value(4,true)
	# Invitation: distant input, decline, controller navigation and explicit Yes.
	key(KEY_G)
	key(KEY_G,false)
	await frames(2)
	check(not duel.dialogue_open and not duel.active,"Distant interaction cannot open or start a fight")
	await approach()
	key(KEY_G)
	key(KEY_G,false)
	await frames(2)
	check(duel.dialogue_open and duel.panel.visible and not controls.gameplay_enabled and not duel.active,"Nearby G opens a real invitation without starting combat")
	key(KEY_Q)
	pad(JOY_BUTTON_A)
	check(controls.consume_combat_requests().is_empty() and not controls.consume_jump(),"Dialogue suspends attack and jump input")
	await shot("invitation",npc.home)
	duel.answer(false)
	check(not duel.active and controls.gameplay_enabled and not duel.panel.visible,"Declining restores play and keeps Ember friendly")
	controls.set_right_trigger(0.0) # Neutral after the previous modal input gate.
	controls.set_right_trigger(1.0)
	controls.set_right_trigger(0.0)
	await frames(2)
	check(duel.dialogue_open and duel.no.has_focus(),"Controller RT opens invitation with Not now selected")
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = JOY_BUTTON_DPAD_LEFT
	event.pressed = true
	duel._input(event)
	check(duel.yes.has_focus(),"Controller direction chooses the Yes button")
	event.button_index = JOY_BUTTON_A
	w.health = 63
	duel._input(event)
	check(duel.active and npc.controls.active and w.health == w.max_health and npc.health == npc.weapon_combat.max_health,"Confirming Yes starts a fresh round with equal health")
	check(p.target_lock.opponent == npc and npc.target_lock.opponent == p and p.get_collision_layer_value(2) and npc.get_collision_layer_value(2),"Both duelists share real hurt volumes and target-facing movement")
	await shot("duel",npc.position)
	# Let the actual AI pursue, attack and defend a stationary player.
	var initial: Vector3 = npc.position
	await seconds(2.8)
	check(npc.controls.decisions>0 and npc.position.distance_to(initial)>0.1,"AI approaches/orbits and starts real weapon attacks")
	check(w.health<w.max_health or w.last_blocked or w.last_evaded,"Partner's timed attacks can actually hit the player")
	key(KEY_G)
	key(KEY_G,false)
	await frames(2)
	check(not duel.active and w.health == 63 and not p.is_in_group("combat_targets") and not npc.is_in_group("combat_targets"),"Yield ends hostility and restores the player's pre-duel health")
	check(not npc.controls.active and npc.position.distance_to(npc.home)<0.1 and not npc.dodge.active and npc.combat.sheathed,"Partner returns home with no held attacks or lingering dodge")
	check(body_sphere.material_override == npc.body_ink,"End-of-round reset preserves Ember's orange body")
	# Exercise every AI-issued action through the same combat controller.
	await approach()
	duel.interact()
	duel.answer(true)
	npc.controls.stop()
	npc.position = Vector3(0,0,0)
	p.position = Vector3(0,0,-1.5)
	p.velocity = Vector3.ZERO
	p.set_physics_process(false)
	w.set_physics_process(false)
	npc.set_physics_process(false)
	for slot: StringName in Library.LOADOUTS:
		for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			w.health = 100000
			npc.weapon_combat.cancel()
			npc.controls.reset_combat_input()
			npc.controls.decisions = 0 # direct action branch; charged path tested separately.
			npc.controls.choose_attack(slot,action)
			npc.combat.poll(npc.controls)
			npc.velocity = Vector3.ZERO
			var before: float = w.health
			await seconds(float(Library.move(slot,action).duration)+0.1)
			check(npc.combat.last_action == action and npc.combat.selected_slot == slot and w.health<before,"AI has an executable shared skill: %s / %s" % [slot,action])
	# Actual brain-driven traversal and defensive decisions, beyond command parity.
	npc.set_physics_process(true)
	npc.controls.start()
	npc.controls.decision = 100
	p.position = Vector3(0,12,-1.5)
	npc.position = Vector3.ZERO
	npc.velocity = Vector3.ZERO
	await seconds(1.1)
	check(npc.position.y>2 and npc.air_step_count>=1,"AI jumps and sky-steps to pursue an elevated opponent")
	npc.controls.start()
	npc.controls.decision = 100
	p.position = Vector3(0,0,-16)
	npc.position = Vector3.ZERO
	npc.velocity = Vector3.ZERO
	await seconds(0.5)
	check(npc.boost_active and Vector2(npc.velocity.x,npc.velocity.z).length()>9,"AI uses the shared fast run to close a long gap")
	npc.controls.start()
	npc.controls.decision = 100
	npc.controls.defense_cooldown = 0
	npc.controls.decisions = 0
	p.position = Vector3(0,0,-1.5)
	npc.position = Vector3.ZERO
	npc.velocity = Vector3.ZERO
	w.set_physics_process(true)
	w.clear_stagger() # The attack-deck fixture suspended this defender's timers.
	w._begin(Library.move(&"down",&"attack_right"))
	var parries: int = npc.weapon_combat.total_parries
	await seconds(0.28)
	check(npc.combat.blocking and npc.weapon_combat.total_parries>parries,"AI reacts to a telegraph using the same timed-block parry")
	w.cancel()
	w.clear_stagger() # Begin an independent defensive-choice scenario.
	npc.weapon_combat.cancel()
	npc.controls.start()
	npc.controls.decision = 100
	npc.controls.defense_cooldown = 0
	npc.controls.decisions = 1
	w._begin(Library.move(&"down",&"attack_right"))
	await seconds(0.24)
	check(npc.dodge.active and npc.weapon_combat.last_evaded,"AI can phase-dodge an actual strike during its hidden window")
	check(npc.dodge._fade_material.emission.r>0.9,"Partner's teleport retains its orange identity")
	await seconds(0.6)
	w.cancel()
	w.set_physics_process(false)
	p.position = Vector3(0,0,-2)
	npc.position = Vector3.ZERO
	npc.velocity = Vector3.ZERO
	npc.controls.start()
	npc.controls.defense_cooldown = 100
	npc.controls.decisions = 2
	npc.controls.choose_attack(&"right",&"special_rt_x")
	npc.combat.poll(npc.controls)
	await seconds(1.0)
	check(npc.combat.charge_action == &"special_rt_x" and npc.weapon_combat.active_move.is_empty(),"AI can hold a modified weapon special without an early strike")
	await seconds(0.28)
	check(npc.weapon_combat.active_move.get("charge",0)>0.99,"AI releases the same full-charge extended special as the player")
	duel.finish(true)
	p.set_physics_process(true)
	w.set_physics_process(true)
	npc.set_physics_process(true)
	await approach()
	duel.interact()
	duel.answer(true)
	npc.controls.stop()
	npc.weapon_combat.health = 1
	controls._request(&"weapon",&"down")
	controls._request(&"action",&"attack_right")
	await seconds(0.3)
	check(not duel.active and duel.result_text.begins_with("You win") and npc.health == npc.weapon_combat.max_health and w.active_move.is_empty(),"A real lethal strike ends a nonlethal win safely inside its hit callback")
	await approach()
	duel.interact()
	duel.answer(true)
	npc.controls.stop()
	w.health = 1
	npc.weapon_combat._begin(Library.move(npc.combat.selected_slot,&"attack_right"))
	await seconds(0.3)
	check(not duel.active and duel.result_text.begins_with("Ember wins") and w.health>0 and npc.weapon_combat.active_move.is_empty(),"A real AI knockout ends the round safely without a respawn or death loop")
	await approach()
	duel.interact()
	duel.answer(true)
	duel._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not duel.active and not npc.controls.active,"Focus loss safely ends an active duel")
	await approach()
	duel.interact()
	duel._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not duel.dialogue_open and controls.gameplay_enabled,"Focus loss closes the invitation and restores input")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Charge/sparring verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
