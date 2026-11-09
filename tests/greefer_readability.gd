extends "res://tests/greefer_encounter.gd"
## Real animated contacts, not direct calls that bypass the attack clock.
func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p = world.player
	boss = world.greefer
	encounter = world.boss_encounter
	input = TestIntent.new()
	input.source = world.controls
	root.add_child(input)
	p.controls = input
	world.camera_rig.controls = input
	p.visual.retrieval.enabled = false
	await frames(3)
	await fixture()
	var w: Node = boss.weapon_combat
	w._begin(Moves.move(&"rake"))
	await seconds(0.45)
	check(p.health == 1000 and boss.visual.attack_phase(w.active_move,w.elapsed) == "windup","Raised claw telegraphs before its active contact window")
	var raised: Vector3 = boss.visual.feet[0].global_position
	await seconds(0.32)
	check(p.health == 888 and w.total_hits == 1,"Animated talons contact once during their actual swipe")
	check(raised.distance_to(boss.visual.feet[0].global_position)>0.7,"Foreleg visibly sweeps across the opponent")
	await seconds(0.4)
	check(p.health == 888 and boss.visual.attack_phase(w.active_move,w.elapsed) == "recovery","Follow-through retains a harmless recovery window")
	await fixture()
	p.position.x = 2.1
	w._begin(Moves.move(&"rake"))
	await seconds(1.35)
	check(p.health == 1000,"A target inside the old reach sphere but outside the visible talons is missed")
	await fixture()
	p.position.y += 4
	w._begin(Moves.move(&"rake"))
	await seconds(1.35)
	check(p.health == 1000,"A claw cannot damage a target several meters above it")
	for style: StringName in [&"double",&"sweep",&"lunge",&"dive"]:
		await fixture()
		var move := Moves.move(style)
		w._begin(move)
		await seconds(float(move.duration)+0.10)
		print("CONTACT ",style," damage=",1000-p.health)
		check(p.health<1000,"Visible natural weapon makes contact: "+String(style))
		check(is_equal_approx(1000-p.health,float(move.damage)*move.hits.size()),"Each legitimate contact registers exactly once: "+String(style))
		check(w.active_move.is_empty(),"Attack completes its authored recovery: "+String(style))
	await fixture()
	boss.flight_mode = true
	boss.position.y += 26
	p.position.y += 25
	w._begin(Moves.move(&"rake"))
	await seconds(1.4)
	check(p.health<1000,"Aerial claw articulation can reach an airborne opponent")
	await fixture()
	w._begin(Moves.move(&"rake"))
	w.strike(0)
	check(p.health == 1000,"A manual strike outside its animation window cannot deal damage")
	await seconds(0.45)
	var heading: Vector3 = w._facing
	p.position.x += 5
	await seconds(0.9)
	check(p.health == 1000 and w._facing == heading,"Late repositioning evades a committed swipe without homing")
	await fixture()
	var wall := preload("res://scripts/neon.gd").block(world,boss.position+Vector3(0,1.5,1.6),Vector3(3,3,0.2))
	w._begin(Moves.move(&"rake"))
	await seconds(1.35)
	check(p.health == 1000,"Solid architecture blocks animated strikes")
	wall.queue_free()
	await fixture()
	w._begin(Moves.move(&"rake"))
	var supports: Array[Vector3] = boss.visual.foot_points()
	await seconds(0.43)
	check(boss.visual.feet[2].global_position.distance_to(supports[2])<0.12 and boss.visual.feet[3].global_position.distance_to(supports[3])<0.12,"Hind feet remain planted while the torso loads and turns")
	check(not boss.debug_combat and not is_instance_valid(w._debug),"Developer phase/contact display is absent in normal gameplay")
	await fixture()
	guard(p)
	w._begin(Moves.move(&"rake"))
	await seconds(1.35)
	check(is_equal_approx(p.health,983.2) and w.psi_meter>0 and is_equal_approx(p.weapon_combat.psi_meter,w.psi_meter*0.25),"Animated guarded impact preserves chip and shared exhaustion")
	await fixture()
	w._begin(Moves.move(&"rake"))
	await seconds(0.44)
	guard(p,true)
	await seconds(0.22)
	check(p.health == 1000 and p.weapon_combat.last_parried and w.forced_state == &"parried","A timed block parries the visible incoming claw")
	check(p.weapon_combat.psi_meter == 0 and w.psi_meter == 0,"Animated parry adds no guard strain")
	await fixture()
	w._begin(Moves.move(&"rake"))
	p.dodge.start(Vector3.RIGHT)
	p.dodge.elapsed = p.dodge.DURATION*0.5
	await seconds(0.80)
	check(p.health == 1000 and p.weapon_combat.last_evaded,"Hidden dodge phase remains invincible during a real animated contact")
	p.dodge.cancel()
	await fixture()
	boss.debug_combat = true
	w._begin(Moves.move(&"sweep"))
	await seconds(0.83)
	check(is_instance_valid(w._debug) and w._debug.caption.text.contains("active") and w._debug.mesh.get_surface_count() == 1,"Opt-in developer display follows the actual active wing capsules")
	boss.debug_combat = false
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Greefer readability verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
