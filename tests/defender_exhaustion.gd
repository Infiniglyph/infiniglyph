extends "res://tests/defensive_interactions.gd"
## Exercise the real shared resolver and authored hit pulses, not a second meter.

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	check(world.sparring_duel.active,"Player and Ember use the real duel damage gates")
	await reset_pair()
	check(a.rules != b.rules and a.rules.defender_exhaustion_multiplier == 0.25 and b.rules.defender_exhaustion_multiplier == 0.25,"Independent actor rules default defender strain to 25%")
	var move := Library.move(&"down",&"attack_right")
	var strain := 18.424 # Existing stationary Royal Cleave against a shield.
	controls._keyboard_block = true
	guard(p)
	await seconds(2)
	check(p.combat.blocking and a.psi_meter == 0 and b.psi_meter == 0,"Holding guard indefinitely generates no strain for either participant")
	a.psi_meter = 50
	a._psi_delay = 0
	await seconds(0.5)
	check(p.combat.blocking and is_equal_approx(a.psi_meter,43),"Holding guard retains the existing 14-points-per-second recovery")
	await reset_pair()
	guard(npc)
	a._begin(move)
	var chip: float = npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(is_equal_approx(a.psi_meter,strain) and is_equal_approx(b.psi_meter,strain*0.25),"Confirmed basic block applies the unchanged full attacker penalty and quarter defender share")
	check(is_equal_approx(chip,3.6) and is_equal_approx(b.health,996.4),"Reduced defender strain still allows normal shield chip damage")
	check(not a.active_move.is_empty() and not a.is_staggered() and not b.is_staggered(),"Sub-threshold guard strain adds no new action lock")
	check(a._psi_delay == a.rules.psi_recovery_delay and b._psi_delay == b.rules.psi_recovery_delay,"A guarded impact restarts each participant's existing recovery delay")
	for slot: StringName in [&"down",&"left",&"right",&"up"]:
		await reset_pair()
		npc.combat.selected_slot = slot
		guard(npc)
		var expected: float = b.get_block_exhaustion(move)
		npc.receive_combat_hit(24,p.combat_point(),p,move)
		check(is_equal_approx(a.psi_meter,expected) and is_equal_approx(b.psi_meter,expected*0.25),"Weapon-specific guard strain shares consistently: "+String(slot))
	await reset_pair()
	b.rules.defender_exhaustion_multiplier = 0.5
	guard(npc)
	npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(is_equal_approx(a.psi_meter,strain) and is_equal_approx(b.psi_meter,strain*0.5),"Changing the defender multiplier preserves attacker balance")
	await reset_pair()
	b.rules.defender_exhaustion_multiplier = 0
	guard(npc)
	npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(is_equal_approx(a.psi_meter,strain) and b.psi_meter == 0 and b._psi_delay == 0,"Zero multiplier disables only defender strain")
	b.rules.defender_exhaustion_multiplier = 0.25
	await reset_pair()
	a.psi_meter = 99
	guard(npc)
	a._begin(move)
	npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(a.psi_meter == 100 and a.forced_state == &"exhausted" and is_equal_approx(b.psi_meter,strain*0.25),"Attacker saturation does not shrink the defender's nominal contact share")
	await reset_pair()
	b.psi_meter = 99
	guard(npc)
	chip = npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(b.psi_meter == 100 and b.forced_state == &"exhausted" and not npc.combat.blocking and b.stagger_remaining == b.rules.exhausted_duration,"Defender threshold uses the existing exhaustion state and duration")
	check(is_equal_approx(chip,3.6) and is_equal_approx(a.psi_meter,strain),"Threshold-crossing block keeps its chip result and full attacker penalty")
	var hp: float = b.health
	npc.receive_combat_hit(20,p.combat_point(),p,move)
	check(is_equal_approx(hp-b.health,27) and b.forced_state == &"exhausted","Exhausted defender retains existing damage vulnerability and state priority")
	await seconds(b.rules.exhausted_duration+0.02)
	check(not b.is_staggered() and is_equal_approx(b.psi_meter,25),"Defender recovery returns the existing meter to 25% capacity")
	for defender: Node in [p,npc]:
		await reset_pair()
		var attacker: Node = npc if defender == p else p
		a.psi_meter = 11
		b.psi_meter = 31
		guard(defender,true)
		attacker.weapon_combat._begin(move)
		chip = defender.receive_combat_hit(24,attacker.combat_point(),attacker,move)
		check(chip == 0 and defender.weapon_combat.health == 1000 and a.psi_meter == 11 and b.psi_meter == 31 and attacker.weapon_combat.forced_state == &"parried","Timed parry negates damage/strain and preserves attacker stagger: "+defender.name)
	await reset_pair()
	var clean := move.duplicate()
	clean.hit_stun_level = 0
	npc.receive_combat_hit(24,p.combat_point(),p,clean)
	check(b.health == 976 and a.psi_meter == 0 and b.psi_meter == 0,"An unguarded hit generates no guard exhaustion")
	await reset_pair()
	guard(npc)
	npc.receive_combat_hit(24,npc.combat_point()-b.aim_direction()*2,p,clean)
	check(not b.last_blocked and a.psi_meter == 0 and b.psi_meter == 0,"A hit behind an active guard generates no guard exhaustion")
	await reset_pair()
	guard(npc,true)
	npc.receive_combat_hit(0,p.combat_point(),p,move)
	check(a.psi_meter == 0 and b.psi_meter == 0 and b.parry_remaining>0,"Invalid contacts consume neither strain nor the parry window")
	npc.combat.blocking = false
	b.parry_remaining = 0
	npc.dodge.start(Vector3.RIGHT)
	npc.dodge.elapsed = npc.dodge.DURATION*0.5
	npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(b.last_evaded and a.psi_meter == 0 and b.psi_meter == 0,"Hidden teleport frames bypass exhaustion and damage")
	npc.dodge.cancel()
	await reset_pair()
	b._begin(Library.move(&"down",&"special_rt_x"))
	npc.receive_combat_hit(24,p.combat_point(),p,move)
	check(is_equal_approx(b.last_damage,1.2) and is_equal_approx(a.psi_meter,strain) and b.psi_meter == 0,"Automatic Aegis mitigation retains its existing behavior outside basic guard")
	await reset_pair()
	guard(p)
	p.receive_hit(24,npc.combat_point(),null,move)
	check(is_equal_approx(a.psi_meter,strain*0.25) and b.psi_meter == 0,"Legacy attackerless combat contacts still resolve defender guard strain locally")
	await reset_pair()
	# Add a second real body shape: both overlap the same authored hit volume.
	var extra := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	extra.shape = shape
	extra.position.y = 1.2
	p.add_child(extra)
	controls._keyboard_block = true
	guard(p)
	await frames(2)
	var multi := Library.move(&"up",&"special_x")
	var per_hit: float = a.get_block_exhaustion(multi)
	b._begin(multi)
	b.strike(0)
	check(is_equal_approx(b.psi_meter,per_hit) and is_equal_approx(a.psi_meter,per_hit*0.25),"Overlapping hurtboxes produce one guarded impact per pulse")
	b.strike(0)
	check(is_equal_approx(b.psi_meter,per_hit) and is_equal_approx(a.psi_meter,per_hit*0.25),"Repeating an already registered pulse cannot duplicate either penalty")
	await seconds(1.0)
	check(is_equal_approx(b.psi_meter,per_hit*3) and is_equal_approx(a.psi_meter,per_hit*3*0.25) and is_equal_approx(a.health,993.25),"All three timed multihit pulses count separately with chip damage")
	extra.queue_free()
	await reset_pair()
	guard(npc)
	p.position += Vector3.BACK*5
	a._begin(move)
	a.strike(0)
	check(a.psi_meter == 0 and b.psi_meter == 0,"A missed attack against a guarding opponent generates no exhaustion")
	await reset_pair()
	# Keep any existing strain from recovering while testing free actions.
	a.psi_meter = 40
	a._psi_delay = 20
	p.target_lock.clear()
	input.move = Vector2(0,1)
	input.sprint = true
	input.boost = true
	await seconds(0.6)
	check(p.boost_active and p.velocity.length()>5 and a.psi_meter == 40,"Movement, running and sprinting remain free with accumulated strain")
	controls.jump_requested = true
	await frames(2)
	await seconds(0.15)
	controls.jump_requested = true
	await frames(2)
	check(p.air_step_count>0 and p.velocity.y>0 and a.psi_meter == 40,"Ground jump and unlimited Sky Jump add no exhaustion")
	check(p.dodge.start(Vector3.BACK) and a.psi_meter == 40,"Teleport dodge is available without an exhaustion cost")
	p.dodge.cancel()
	input.move = Vector2.ZERO
	input.sprint = false
	input.boost = false
	p.position = npc.home+Vector3(0,0,7)
	a._on_action(&"attack_right",&"down")
	check(not a.active_move.is_empty() and a.psi_meter == 40,"Normal attacks remain free and available with accumulated strain")
	p.respawn()
	check(a.psi_meter == 0 and b.psi_meter == 0 and not world.sparring_duel.active,"Respawn and duel cleanup reset both existing exhaustion meters")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Defender exhaustion verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
