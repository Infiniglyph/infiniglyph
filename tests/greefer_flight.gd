extends "res://tests/greefer_encounter.gd"
## Real district facades, roofs, Sky Jumps, collision steering and tower return.
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
	await seconds(0.3)
	await fixture()
	boss.position = Vector3(9,0.045,-43)
	p.position = Vector3(17.1,32.165,-47) # West edge of an existing 32m rooftop.
	p.weapon_combat.health = 100000 # Test observer survives while navigation runs.
	boss.last_known = p.position
	boss.launch_cleared = true
	boss.perception_clock = 0
	boss.set_state(&"engaged")
	boss.think_enabled = true
	await seconds(0.25)
	check(boss.flight_mode and boss.position.y>0.5,"Visible rooftop elevation causes a real takeoff")
	var landed := false
	var previous := boss.position
	var max_step := 0.0
	for i in range(hz*24):
		await frames(1)
		max_step = maxf(max_step,previous.distance_to(boss.position))
		previous = boss.position
		if not boss.flight_mode and boss.is_on_floor() and boss.position.y>31:
			landed = true
			break
	print("ROOF: state=",boss.state," flight=",boss.flight_mode," at=",boss.position," landing=",boss._land_goal," target=",boss.last_known," recoveries=",boss.navigation_recoveries)
	check(landed and boss.position.distance_to(p.position)<8,"Greefer navigates a real building facade and lands beside the rooftop player")
	check(max_step<34.0/hz+0.1,"Obstacle avoidance never warps through district geometry")
	var roof_hit: Dictionary = boss.landing_near(p.position)
	check(not roof_hit.is_empty() and roof_hit.point.y>32 and boss.clear_body_at(roof_hit.point),"Safe landing selection checks support and full body clearance on a rooftop")
	await capture("rooftop")
	# Give the real player controller actual Space/Sky Jump requests from the roof.
	p.set_physics_process(true)
	p.fall_damage.reset()
	world.controls.jump_requested = true
	await seconds(0.30)
	for i in range(5):
		world.controls.jump_requested = true
		await seconds(0.30)
	check(p.air_step_count>=4 and p.position.y>37,"Unrestricted player Sky Jump still gains altitude during boss combat")
	await seconds(2.0)
	print("AIR: player=",p.position," boss=",boss.position," flight=",boss.flight_mode," sees=",boss.visible_target)
	check(boss.flight_mode and boss.position.y>36,"Greefer takes off again and pursues the ascending player")
	check(boss.unseen_time<1 and boss.last_known.y>35,"Aerial pursuit follows genuine visible position updates")
	p.set_physics_process(false)
	p.velocity = Vector3.ZERO
	# With no floor within landing range, the boss must close to real hit range
	# rather than endlessly hover above the shared strike's vertical allowance.
	boss.weapon_combat.cancel()
	boss.position = p.position+Vector3(4,0.6,0)
	boss.velocity = Vector3.ZERO
	boss._landing_valid = false
	boss._landing_clock = 0
	boss.last_known = p.position
	boss.launch_cleared = true
	boss.set_state(&"engaged")
	var air_health: float = p.health
	await seconds(3)
	check(p.health<air_health and boss.flight_mode,"Open-air pursuit closes to a legitimate damaging strike without a rooftop")
	# A visible dive commits to a world position, allowing a late dodge to evade.
	boss.think_enabled = false
	boss.weapon_combat.reset()
	boss.position = p.position+Vector3(0,6,6)
	boss.facing = Vector3.FORWARD
	boss.flight_mode = true
	boss.attack_goal = p.position
	boss.weapon_combat._begin(Moves.move(&"dive"))
	var committed: Vector3 = boss.attack_goal
	p.position.x += 9
	boss.perception_clock = 0
	boss.perceive(0.2)
	check(boss.attack_goal == committed and boss.last_known != committed,"A committed dive does not home onto a newly observed dodge position")
	for style: StringName in [&"rake",&"double",&"sweep",&"lunge",&"dive"]:
		var move := Moves.move(style)
		check(move.windup>=0.48 and move.hits[0]>move.windup and move.duration>move.hits[-1]+0.35 and move.parryable,"Readable windup and punishable follow-through: "+String(style))
	boss.weapon_combat.cancel()
	boss.think_enabled = true
	encounter.disengage()
	previous = boss.position
	max_step = 0
	for i in range(hz*25):
		await frames(1)
		max_step = maxf(max_step,previous.distance_to(boss.position))
		previous = boss.position
		if boss.state == &"perched": break
	print("RETURN: ",boss.state," at=",boss.position," recoveries=",boss.navigation_recoveries)
	check(boss.state == &"perched" and boss.is_on_floor(),"Disengagement flies back and physically settles onto Central Tower")
	check(max_step<34.0/hz+0.1 and not encounter.can_progress(),"Returning never teleports or clears an unfinished encounter")
	encounter.progress = Journal.fresh()
	encounter.progress.intro_completed = true
	encounter.progress.first_outcome = "defeat"
	encounter.progress.last_outcome = "defeat"
	encounter.progress.losses = 1
	p.position = encounter.challenge_point
	p.weapon_combat.health = 1000
	check(encounter.can_challenge(),"The tower challenge sigil offers rematches after either initial outcome")
	world.inventory_session.interact()
	check(encounter.dialogue_open and not encounter.active,"G / RT opens a rematch confirmation before starting combat")
	encounter.answer(true)
	check(encounter.active and not encounter.is_intro and boss.state == &"alert" and boss.health == boss.base_health,"Existing G / RT interaction starts a full-strength rematch")
	var before: float = boss.state_age
	world.start_menu.open_menu()
	await seconds(0.5)
	check(world.start_menu.is_open and not paused and boss.state_age>before+0.3,"Start overlay continues the live boss/world simulation")
	world.start_menu.close_menu()
	encounter.disengage()
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Greefer flight verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
