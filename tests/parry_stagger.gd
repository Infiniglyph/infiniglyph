extends SceneTree
## Real attacker identity, configured parry interruption, pose recovery and contextual RT.
const Library = preload("res://scripts/weapon_library.gd")
const Shared = preload("res://tests/charge_sparring.gd")
var world: Node3D
var p: CharacterBody3D
var npc: CharacterBody3D
var w: Node
var other: Node
var controls: Node
var input: Node
var duel: CanvasLayer
var checks := 0
var failures := 0
var hz := 60
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

func key(code: Key, held: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = held
	controls._unhandled_input(event)

func trigger(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	event.device = device
	controls._unhandled_input(event)

func guard(held: bool) -> void:
	key(KEY_F,held)
	p.combat.poll(input)

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = npc.position+Vector3(-3,1.5,3.8)
	camera.look_at(npc.position+Vector3.UP)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/parry_recoil_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current = true

func settle() -> void:
	guard(false)
	input.move = Vector2.ZERO
	controls.reset_combat_input()
	w.reset()
	other.reset()
	npc.controls.stop()
	npc.combat.blocking = false
	npc.position = npc.home
	npc.velocity = Vector3.ZERO
	p.position = npc.home+Vector3(-1.6,0,0)
	p.velocity = Vector3.ZERO
	p.target_lock.select(npc)
	npc.target_lock.select(p)
	await seconds(0.3)

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
	npc = world.sparring_partner
	other = npc.weapon_combat
	duel = world.sparring_duel
	controls = world.controls
	input = Shared.Intent.new()
	input.source = controls
	root.add_child(input)
	p.controls = input
	world.camera_rig.controls = input
	p.visual.retrieval.enabled = false
	var pads := Input.get_connected_joypads()
	if not pads.is_empty(): device = pads[0]
	for target in get_nodes_in_group("combat_targets"): target.counterattacks = false
	await seconds(0.5)
	check(w.health == 1000 and w.max_health == 1000 and npc.health == 1000 and other.max_health == 1000,"Player and Ember start with 1,000 base/max HP")
	w.health = 1
	p.respawn()
	check(w.health == 1000,"Respawn restores the new base health")
	var hud: Control = world.find_child("CombatHUD",true,false)
	w.changed.emit()
	check(hud.health.text.contains("1000 / 1000"),"HUD uses the actual maximum health")
	trigger(1)
	await frames(2)
	check(not duel.dialogue_open and controls.special_modified(),"RT away from Ember keeps its special modifier mapping")
	trigger(0)
	p.position = npc.home+Vector3(-2,0,0)
	await seconds(0.3)
	trigger(0.54)
	await frames(2)
	check(not duel.dialogue_open,"Trigger noise below RT threshold cannot open interaction")
	trigger(0.56)
	await frames(2)
	check(duel.dialogue_open and not duel.active,"RT opens the same nearby invitation as G/View")
	duel.answer(false)
	trigger(1)
	await frames(2)
	check(not duel.dialogue_open,"Holding RT across a declined invitation cannot reopen it")
	trigger(0)
	trigger(1)
	await frames(2)
	check(duel.dialogue_open,"Release and press RT rearms the interaction")
	duel.answer(true)
	npc.controls.stop()
	check(duel.active and w.health == 1000 and npc.health == 1000,"Accepted sparring round uses 1,000 HP for both fighters")
	trigger(0)
	trigger(1)
	controls._special(&"x",device,true)
	controls._special(&"x",device,false)
	await frames(1)
	check(duel.active and not duel.dialogue_open and p.combat.last_action == &"special_rt_x" and not w.active_move.is_empty(),"RT+X during combat remains a modified special and never yields")
	trigger(0)
	await settle()
	# Start a real multi-contact katana attack, then time the player's block.
	other._begin(Library.move(&"right",&"special_y"))
	other._queued = {"action":&"attack_right","slot":&"right","charge":0.0}
	other._queue_time = 1
	npc.controls.decision = 9
	npc.controls.charge_remaining = 1
	await seconds(float(other.active_move.hits[0])-0.1)
	guard(true)
	for i in range(ceili(hz*0.25)):
		await frames(1)
		if other.is_staggered(): break
	check(w.last_parried and w.health == 1000 and other.is_staggered(),"Actual parry negates damage and staggers the correct attacker")
	check(not w.is_staggered() and other.active_move.is_empty() and other._queued.is_empty(),"Defender stays responsive; interrupted attack and buffered follow-up are cleared")
	check(npc.controls.decision == 0 and npc.controls.charge_remaining == 0,"Old AI recovery/charge timers cannot extend the configured opening")
	check(npc.visual.chest.quaternion.angle_to(Quaternion.IDENTITY)>0.12 and npc.visual.pelvis.position.y<npc.visual.REST_HIP_HEIGHT-0.02,"Recoil opens the torso and loads the knees immediately")
	other._on_action(&"attack_right",&"right")
	npc.controls._special(&"x")
	npc.combat.poll(npc.controls)
	check(other.active_move.is_empty() and npc.combat.charge_action == &"" and not npc.dodge.start(Vector3.RIGHT),"Attack, charge and phase cannot escape the stagger")
	npc.controls._keyboard_block = true
	npc.combat.poll(npc.controls)
	check(other.parry_remaining == 0 and is_equal_approx(npc.receive_combat_hit(10,p.combat_point(),p),10) and not other.last_blocked,"The brief counter opening prevents guarding and parrying")
	npc.controls._keyboard_block = false
	npc.combat.poll(npc.controls)
	var ticks := 0
	while other.is_staggered() and ticks<ceili(hz*2):
		await frames(1)
		ticks += 1
	var duration := float(ticks)/hz
	check(duration>=other.rules.parry_stagger-0.0001 and duration<=other.rules.parry_stagger+1.0/hz+0.0001,"Control lock lasts configured duration within one physics tick (%.4f s)" % duration)
	check(other.recoil_remaining>0 and other.recoil_amount()>0,"Visual settling outlasts the counter window")
	other._on_action(&"attack_right",&"right")
	check(not other.active_move.is_empty(),"A new attack can start as soon as the parry lock ends")
	other.cancel()
	guard(false)
	await seconds(1)
	check(w.health == 1000,"Cancelled later contacts and queued attacks never deal delayed damage")
	# Whole-body recovery for each loadout, with the katana's shared grip intact.
	for slot: StringName in Library.LOADOUTS:
		npc.controls._request(&"weapon",slot)
		npc.combat.poll(npc.controls)
		await seconds(0.3)
		var root_position: Vector3 = npc.position
		var momentum: Vector3 = npc.velocity
		npc.on_parried(p.combat_point())
		await frames(1)
		check(npc.position.distance_to(root_position)<0.01 and npc.velocity.is_equal_approx(momentum) and npc.rotation.is_zero_approx(),"Recoil preserves root/capsule/momentum: "+String(slot))
		if slot == &"right":
			var wrist: Vector3 = npc.visual.joints.LeftArm.get_node("Hinge").to_global(Vector3(0,-0.29,0))
			check(wrist.distance_to(other.rig.right_hand.to_global(Vector3(0,-0.17,0)))<0.02,"Katana remains two-handed through parry recoil")
		await shot(String(slot))
		await seconds(other.rules.parry_stagger+0.25)
		check(not other.is_staggered() and other.recoil_remaining == 0 and npc.visual.chest.rotation.length()<0.03,"Pose returns to rest after the configured stun: "+String(slot))
	# Symmetric attacker notification, then airborne control and carry behavior.
	await settle()
	w._begin(Library.move(&"down",&"attack_right"))
	await seconds(0.1)
	npc.controls.active = true
	npc.controls.decision = 100
	npc.controls.defense_cooldown = 100
	npc.controls.guard_time = 0.4
	for i in range(ceili(hz*0.2)):
		await frames(1)
		if w.is_staggered(): break
	check(other.last_parried and w.is_staggered() and not other.is_staggered(),"Ember's successful parry interrupts the player by the same rule")
	npc.controls._keyboard_block = false
	npc.combat.poll(npc.controls)
	await settle()
	p.position += Vector3.UP*10
	await frames(1) # Establish airborne floor state after this test teleport.
	p.velocity = Vector3(4,-1,0)
	input.move = Vector2.RIGHT
	p.on_parried(npc.combat_point())
	controls.jump_requested = true
	controls.dodge_requested = true
	await frames(1)
	check(is_equal_approx(p.velocity.x,4) and is_equal_approx(p.velocity.z,0) and p.velocity.y<-1 and not p.dodge.active and p.air_step_count == 0,"Air stagger ignores steering/jump/dodge but preserves carry, gravity and collision")
	input.move = Vector2.ZERO
	p.respawn()
	check(not w.is_staggered() and w.recoil_remaining == 0 and not duel.active and w.health == 1000,"Respawn and duel cleanup remove stagger and restore base health")
	# No invented source: an old two-argument damage call cannot stagger a bystander.
	p.position = Vector3.ZERO
	world.camera_rig.yaw = 0
	guard(true)
	w.receive_hit(10,p.position+Vector3.FORWARD)
	check(w.last_parried and not other.is_staggered(),"Legacy damage without an attacker cannot stagger the lock target")
	w.stagger(p.position+Vector3.FORWARD)
	w._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not w.is_staggered() and w.recoil_remaining == 0 and w.status != "Staggered","Focus loss clears both stagger state and its HUD status")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Parry stagger / HP / RT verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
