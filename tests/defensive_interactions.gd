extends SceneTree
## Real player/Ember actors, collisions, input permissions, timed recovery and FX.
const Library = preload("res://scripts/weapon_library.gd")
const Shared = preload("res://tests/charge_sparring.gd")
var world: Node3D
var p: CharacterBody3D
var npc: CharacterBody3D
var a: Node
var b: Node
var controls: Node
var input: Node
var hz := 60
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func seconds(time: float) -> void: await frames(ceili(time*hz))

func reset_pair() -> void:
	controls.reset_combat_input()
	npc.controls.stop()
	p.combat.reset()
	npc.combat.reset()
	a.reset()
	b.reset()
	p.combat.selected_slot = &"down"
	npc.combat.selected_slot = &"down"
	p.combat.sheathed = false
	npc.combat.sheathed = false
	a.rig.equip(&"down",false)
	b.rig.equip(&"down",false)
	p.position = npc.home+Vector3(0,0,1.6)
	npc.position = npc.home
	p.velocity = Vector3.ZERO
	npc.velocity = Vector3.ZERO
	input.move = Vector2.ZERO
	p.target_lock.select(npc)
	npc.target_lock.select(p)
	world.camera_rig.yaw = 0
	await seconds(0.3)

func guard(actor: Node, fresh: bool = false) -> void:
	actor.combat.blocking = true
	actor.combat.fresh_block = fresh
	actor.weapon_combat._on_block(true)
	if not fresh: actor.weapon_combat.parry_remaining = 0

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
	root.get_texture().get_image().save_png("res://captures/defense_"+label+".png")
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
	p = world.player
	npc = world.sparring_partner
	a = p.weapon_combat
	b = npc.weapon_combat
	controls = world.controls
	input = Shared.Intent.new()
	input.source = controls
	root.add_child(input)
	p.controls = input
	world.camera_rig.controls = input
	p.visual.retrieval.enabled = false
	await seconds(0.2)
	p.position = npc.home+Vector3(-2,0,0)
	await seconds(0.3)
	world.sparring_duel.start()
	check(world.sparring_duel.active,"Real duel damage gates are open")
	await reset_pair()
	check(a.rules != b.rules and a.rules.parry_stagger == b.rules.parry_stagger,"Actors share tuning rules with independent resources/meters")
	var move := Library.move(&"down",&"attack_right")
	# Parry has exclusive priority and cancels even explicit multihit pulses.
	guard(npc,true)
	a._begin(Library.move(&"up",&"special_x"))
	a.strike(0)
	check(b.last_outcome == &"parry" and not b.last_blocked and b.health == 1000,"One parry outcome: no chip damage, block or clean-hit outcome")
	check(a.forced_state == &"parried" and a.active_move.is_empty() and a.psi_meter == 0,"Parry interrupts offense and bypasses exhaustion/fortitude")
	check(is_equal_approx(a.stagger_remaining,1.0),"Parry opens the configured 1.0-second punish window")
	var old_slot: StringName = p.combat.selected_slot
	controls._request(&"weapon",&"right")
	controls._request(&"sheathe",&"")
	controls._request(&"action",&"attack_right")
	controls._special(&"x")
	controls._keyboard_block = true
	p.combat.poll(input)
	check(p.combat.selected_slot == old_slot and not p.combat.sheathed and not p.combat.blocking and p.combat.charge_action == &"" and a.active_move.is_empty() and not p.dodge.start(Vector3.RIGHT),"Forced parry denies swap, sheath, attack, charge, guard and dodge before mutation")
	a.strike(1)
	check(b.health == 1000,"Interrupted later hit pulses cannot land")
	check(a.feedback.last_event.kind == "parry" and a.hitstop_remaining == a.rules.parry_hitstop,"Parry feedback uses seven reference frames, independent of physics rate")
	var fx: Dictionary = a.feedback.bursts[(a.feedback.cursor+11)%12]
	check(fx.primary_color.r>0.9 and fx.primary_color.g>0.7 and fx.mesh.global_position.distance_to(a.feedback.last_event.point)<0.001,"Gold parry sparks originate at the confirmed surface contact")
	await shot("gold_parry")
	var ticks := 0
	while a.is_staggered() and ticks<ceili(hz*2):
		await frames(1)
		ticks += 1
	check(absf(float(ticks)/hz-1.0)<2.1/hz,"Parry recovery is time-based and deterministic")
	controls._keyboard_block = false
	p.combat.poll(input)
	a._on_action(&"attack_right",&"down")
	check(not a.active_move.is_empty(),"Actions resume immediately at the end of forced recovery")
	# Normal block preserves offense; the defender takes a smaller strain share.
	await reset_pair()
	guard(npc)
	a._begin(move)
	a.elapsed = 0.22
	var damage: float = npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(is_equal_approx(damage,3.6) and b.last_outcome == &"block" and a.psi_meter>0 and is_equal_approx(b.psi_meter,a.psi_meter*0.25),"Guard retains 85% reduction and gives the defender 25% of attacker exhaustion")
	check(not a.active_move.is_empty() and a.elapsed == 0.22 and not a.is_staggered() and a.recoil_remaining>0,"Normal block adds brief recoil without resetting the attack or its timing")
	fx = a.feedback.bursts[(a.feedback.cursor+11)%12]
	check(fx.primary_color.r>0.9 and fx.primary_color.g<0.1,"Blocked chip damage also emits red/orange damage sparks")
	# A normal defensive cancel still works outside forced states.
	controls._keyboard_block = true
	p.combat.poll(input)
	check(a.active_move.is_empty() and p.combat.blocking,"Ordinary attack-to-block cancellation remains responsive")
	controls._keyboard_block = false
	p.combat.poll(input)
	var contacts := 1
	while not a.is_staggered() and contacts<12:
		a._begin(move)
		npc.receive_combat_hit(24,p.combat_point(),p,move)
		contacts += 1
	check(a.forced_state == &"exhausted" and contacts<=7 and a.active_move.is_empty(),"Repeated guarded strikes trigger attacker exhaustion and cancel offense")
	check(b.psi_meter>0 and b.psi_meter<b.rules.max_psi and b.forced_state == &"","Defender accumulates reduced strain without premature forced recovery")
	await seconds(0.35)
	check(p.visual.pelvis.position.y<p.visual.REST_HIP_HEIGHT-0.3,"Exhaustion visibly drops the pelvis into a one-knee recovery")
	var knee_height: float = p.visual.joints.RightLeg.get_node("Hinge").global_position.y-p.global_position.y
	check(knee_height<0.18 and knee_height>0,"Rear knee approaches the floor while the front leg supports the body")
	await shot("exhausted")
	var remaining: float = a.stagger_remaining
	var before: float = a.health
	p.receive_combat_hit(20,npc.combat_point(),npc,move)
	check(is_equal_approx(before-a.health,27) and a.forced_state == &"exhausted" and a.stagger_remaining == remaining,"Exhaustion takes 1.35x damage; lower-priority hit stun cannot replace or extend it")
	controls._request(&"weapon",&"up")
	controls._keyboard_block = true
	p.combat.poll(input)
	check(p.combat.selected_slot == &"down" and not p.combat.blocking and not p.dodge.start(Vector3.RIGHT),"Exhaustion cannot be escaped by swapping, blocking or teleporting")
	controls._keyboard_block = false
	await seconds(a.rules.exhausted_duration+0.3)
	check(not a.is_staggered() and a.psi_meter<=a.rules.max_psi*0.25 and a.forced_state == &"","Exhaustion exits deterministically with a reduced, recoverable meter")
	a.psi_meter = 60
	a._psi_delay = 0
	a.cancel()
	await seconds(0.5)
	check(a.psi_meter<55,"Reduced exertion recovers offensive exhaustion")
	# Clean hits compare move properties to context-sensitive fortitude.
	await reset_pair()
	b._begin(move)
	b.elapsed = 0.22
	var fortitude: float = b.effective_fortitude()
	var weak := move.duplicate()
	weak.hit_stun_level = fortitude-0.01
	damage = npc.receive_combat_hit(24,p.combat_point(),p,weak)
	check(damage == 24 and b.last_outcome == &"hyper_armor" and not b.active_move.is_empty() and b.elapsed == 0.22,"Fortitude resists interruption but still takes full damage and preserves attack timing")
	fx = a.feedback.bursts[(a.feedback.cursor+11)%12]
	check(fx.primary_color.r>0.9 and fx.primary_color.g<0.1,"Hyper-armor damage sparks retain neon red")
	weak.hit_stun_level = fortitude
	npc.receive_combat_hit(24,p.combat_point(),p,weak)
	check(b.last_outcome == &"stagger" and b.forced_state == &"hit" and b.active_move.is_empty(),"Equal hit-stun strength interrupts and cancels the defender's hitboxes")
	await seconds(0.1)
	await shot("red_hit_stagger")
	check(b.effective_fortitude() == 0,"Forced punish states do not retain active-attack hyper armor")
	var hit_window: float = b.stagger_remaining
	b.stagger(p.combat_point())
	check(b.forced_state == &"parried" and b.stagger_remaining>hit_window,"Parry has priority over an existing hit stagger")
	b.enter_forced(&"exhausted",1.8,p.combat_point())
	check(b.forced_state == &"parried","Lower-priority exhaustion cannot replace a parry")
	# Player and AI exchange the same attacks and outcomes in both directions.
	await reset_pair()
	guard(p)
	guard(npc)
	var player_chip: float = p.receive_combat_hit(24,npc.combat_point(),npc,move)
	var npc_chip: float = npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(player_chip == npc_chip and is_equal_approx(a.psi_meter,b.psi_meter),"Player and Ember have identical block damage and attacker exhaustion")
	await reset_pair()
	guard(p,true)
	b._begin(move)
	b.strike(0)
	check(a.last_parried and b.forced_state == &"parried" and b.stagger_remaining == a.rules.parry_stagger,"Ember receives the same full punish window when the player parries")
	# Timed contacts continue once each while visual progress is held.
	await reset_pair()
	b.rules.base_fortitude = 100 # Isolate pulse counting from hit interruption.
	a._begin(Library.move(&"up",&"special_x"))
	a.strike(0)
	var hp: float = b.health
	var contact_event: Dictionary = a.feedback.last_event.duplicate()
	check(contact_event.hurtbox_shape>=0 and contact_event.defender_id == npc.get_instance_id(),"Damage sparks identify the actual defender and registered body hurtbox")
	var body_point: Vector3 = contact_event.point
	var hips: Vector3 = npc.visual.pelvis.global_position
	var spine: Vector3 = npc.visual.chest.to_global(Vector3(0,0.56,0))-hips
	var along := clampf((body_point-hips).dot(spine)/spine.length_squared(),0,1)
	check(body_point.distance_to(hips+spine*along)<0.047 and body_point.distance_to(a.rig.right_hand.global_position)>0.5,"Damage spark origin lies on the defender's visible body, away from the attacking grip")
	var grip_transform: Transform3D = b.rig.right_hand.global_transform
	b.rig.right_hand.global_position += Vector3(3,2,1)
	check(npc.body_impact_point(contact_event.contact).is_equal_approx(body_point),"Moving a weapon hilt cannot move the damage emission point")
	b.rig.right_hand.global_transform = grip_transform
	var higher: Vector3 = npc.body_impact_point(contact_event.contact+Vector3.UP*0.3)
	check(higher.y>body_point.y+0.2,"Registered hit height selects the corresponding position along the body")
	a.strike(0)
	check(b.health == hp,"Repeating the same explicit pulse cannot damage a target twice")
	a.cancel()
	a._begin(Library.move(&"up",&"special_x"))
	hp = b.health
	await seconds(1.2)
	check(is_equal_approx(hp-b.health,45),"All three authored multihit pulses resolve once despite visual hitstop")
	check(not a.visual_frozen() and a.active_move.is_empty(),"Visual hitstop releases cleanly without a stuck animation")
	b.rules.base_fortitude = 0.8
	await reset_pair()
	var visual_only := move.duplicate(true)
	visual_only.hits = [10.0]
	a._begin(visual_only)
	a.freeze_visuals(0.1)
	await frames(1)
	var phase: float = p.visual.phase
	var pose: Quaternion = p.visual.chest.quaternion
	var time: float = a.elapsed
	await frames(1)
	check(a.elapsed>time and p.visual.phase == phase and p.visual.chest.quaternion.is_equal_approx(pose),"Hitstop holds procedural visual progression while gameplay attack time advances")
	await seconds(0.2)
	check(not a.visual_frozen() and a.elapsed>time,"Visual progression resumes on schedule")
	# Camera controls/collision framing never incorporate cosmetic shake.
	a.rules.camera_shake_enabled = false
	var yaw: float = world.camera_rig.yaw
	var pitch: float = world.camera_rig.pitch
	a.feedback.confirm("parry",p.combat_point(),Vector3.RIGHT,p,npc)
	await frames(1)
	check(world.camera_rig.camera.h_offset == 0 and world.camera_rig.camera.v_offset == 0 and absf(world.camera_rig.yaw-yaw)<0.01 and absf(world.camera_rig.pitch-pitch)<0.01,"Camera shake can be disabled without touching orbit/control orientation")
	a.rules.camera_shake_enabled = true
	var root_transform := p.transform
	var feedback_start := Time.get_ticks_usec()
	for i in range(100): a.feedback.confirm("hit",npc.combat_point(),Vector3.FORWARD,p,npc,true)
	print("100 pooled impact events CPU: %.3f ms" % ((Time.get_ticks_usec()-feedback_start)/1000.0))
	check(a.feedback.bursts.size() == 12 and a.feedback.voices.size() == 4 and p.transform == root_transform,"Rapid feedback reuses fixed effect/voice pools and never changes the collision root")
	var peak := 0.0
	for sound: AudioStreamWAV in a.feedback.sounds.values():
		for i in range(sound.data.size()/2): peak = maxf(peak,absf(sound.data.decode_s16(i*2)/32768.0))
	check(peak*4*db_to_linear(a.feedback.voices[0].max_db)<1,"Synthesized strike/bass layers have headroom for all four concurrent voices")
	await seconds(0.4)
	check(not a.visual_frozen(),"Rapid feedback cannot leave hitstop stuck")
	# Invalid contacts and hidden teleport frames bypass all damage feedback.
	await reset_pair()
	guard(npc,true)
	var events_before: int = a.feedback.cursor
	check(npc.receive_combat_hit(0,p.combat_point(),p,move) == 0 and b.last_outcome == &"invalid" and b.parry_remaining>0 and a.feedback.cursor == events_before,"Non-damaging contacts consume neither parry nor feedback")
	npc.combat.blocking = false
	b.parry_remaining = 0
	check(npc.dodge.start(Vector3.RIGHT),"Teleport remains available during ordinary combat")
	npc.dodge.elapsed = npc.dodge.DURATION*0.5
	check(npc.receive_combat_hit(24,p.combat_point(),p,move) == 0 and b.last_evaded and not b.is_staggered(),"Hidden teleport immunity precedes defensive impact resolution")
	npc.dodge.cancel()
	a.enter_forced(&"exhausted",1.8,npc.combat_point())
	p.respawn()
	check(not a.is_staggered() and a.psi_meter == 0 and a.hitstop_remaining == 0 and not world.sparring_duel.active,"Defeat/respawn and duel cleanup remove forced states, exhaustion and hitstop")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Defensive interactions verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
