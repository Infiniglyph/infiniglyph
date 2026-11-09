extends SceneTree
const Shared = preload("res://tests/charge_sparring.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Moves = preload("res://scripts/greefer_moves.gd")
const Journal = preload("res://scripts/encounter_progress.gd")
const BaseCombat = preload("res://scripts/weapon_combat.gd")
class TestIntent extends Shared.Intent:
	var gameplay_enabled := true
	func set_gameplay_enabled(value: bool) -> void:
		gameplay_enabled = value
		super.set_gameplay_enabled(value)
class ClientEncounter extends "res://scripts/territorial_encounter.gd":
	func has_authority() -> bool: return false
var world: Node3D
var p: CharacterBody3D
var boss: CharacterBody3D
var encounter: CanvasLayer
var input: TestIntent
var checks := 0
var failures := 0
var hz := 60

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

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func fixture() -> void:
	if encounter.active: encounter.disengage()
	boss.think_enabled = false
	boss.set_state(&"engaged")
	boss.flight_mode = false
	boss.position = Vector3(0,0.045,-20)
	boss.rotation = Vector3.ZERO
	boss.facing = Vector3.BACK
	boss.velocity = Vector3.ZERO
	p.dodge.cancel()
	p.combat.reset()
	p.weapon_combat.reset()
	p.combat.sheathed = false
	p.position = Vector3(0,0.045,-17.6)
	p.velocity = Vector3.ZERO
	p.set_physics_process(false)
	world.controls.reset_combat_input()
	check(encounter.start(true),"Controlled encounter can activate through actual aggression")
	p.target_lock.select(boss)
	await frames(2)

func guard(actor: Node, fresh: bool = false) -> void:
	actor.combat.blocking = true
	actor.combat.fresh_block = fresh
	actor.weapon_combat._on_block(true)
	if not fresh: actor.weapon_combat.parry_remaining = 0

func boss_pulse(pulse: int) -> void:
	# A focused resolver fixture still uses the real articulated contact pose.
	boss.weapon_combat.elapsed = float(boss.weapon_combat.active_move.hits[pulse])
	boss.weapon_combat.strike(pulse)

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = boss.position+Vector3(4,2.8,7)
	camera.look_at(boss.position+Vector3.UP*1.8)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/greefer_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current = true

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
	await seconds(0.5)
	check(boss.state == &"perched" and boss.is_on_floor() and absf(boss.position.y-86.65)<0.15,"Greefer rests visibly on the solid Central Tower roof")
	check(boss.visual.wings.size() == 2 and boss.visual.feet.size() == 4 and boss.visual.head.get_child_count()>2,"Articulated griffin has wings, four clawed feet, eagle head and hooked beak")
	check(boss.weapon_combat is BaseCombat and boss.weapon_combat.rules != p.weapon_combat.rules,"Boss inherits the shared combat resolver with independent tuning/meter")
	check(not encounter.can_progress(),"Ordinary exploration does not bypass the mandatory first confrontation")
	await capture("perched")
	encounter.auto_trigger = true
	p.position = Vector3(0,0.05,-32)
	p.velocity = Vector3.ZERO
	p.set_physics_process(false)
	await seconds(0.6)
	check(encounter.active and boss.state == &"alert" and encounter.result_text == encounter.introduction,"Visible tower approach triggers editable hostile dialogue and alert")
	var previous := boss.position
	var max_displacement := 0.0
	var landed := false
	for i in range(hz*14):
		await frames(1)
		max_displacement = maxf(max_displacement,previous.distance_to(boss.position))
		previous = boss.position
		if not boss.flight_mode and boss.state == &"engaged":
			landed = true
			break
	print("ARRIVAL: ",boss.state," flight=",boss.flight_mode," at=",boss.position," goal=",boss._land_goal," recoveries=",boss.navigation_recoveries)
	check(boss.position.y<20 and max_displacement<34.0/hz+0.15,"Launch and descent use continuous collision movement, without teleporting")
	check(landed,"Greefer descends to a supported street landing and enters ground combat")
	check(world.population.residents.size() == 100 and not paused,"Living population and world simulation remain active during arrival")
	await capture("arrival")
	encounter.auto_trigger = false
	await fixture()
	var w: Node = boss.weapon_combat
	var a: Node = p.weapon_combat
	var claw := Moves.move(&"rake")
	w._begin(claw)
	boss_pulse(0)
	check(is_equal_approx(a.health,888) and encounter.participated,"A real claw pulse damages the player and records participation")
	var hp: float = a.health
	boss_pulse(0)
	check(a.health == hp,"Repeated boss pulse cannot register duplicate damage")
	await fixture()
	guard(p)
	w._begin(claw)
	boss_pulse(0)
	check(is_equal_approx(a.last_damage,16.8) and is_equal_approx(a.psi_meter,w.psi_meter*0.25) and w.psi_meter>0,"Boss attacks respect chip and both participants' shared guard exhaustion")
	await fixture()
	guard(p,true)
	w._begin(claw)
	boss_pulse(0)
	check(a.health == 1000 and a.last_parried and w.forced_state == &"parried" and is_equal_approx(w.stagger_remaining,1),"Player can perfectly parry Greefer into the full one-second punish window")
	check(a.psi_meter == 0 and w.psi_meter == 0,"Perfect boss parry produces no guard exhaustion")
	await capture("parried")
	await fixture()
	guard(boss,true)
	a._begin(Library.move(&"down",&"attack_right"))
	a.strike(0)
	check(w.last_parried and w.health == boss.base_health and a.forced_state == &"parried","Greefer can use the same timed block against observable attacks")
	await fixture()
	guard(boss)
	a._begin(Library.move(&"down",&"attack_right"))
	a.strike(0)
	check(w.health<boss.base_health and a.psi_meter>0 and is_equal_approx(w.psi_meter,a.psi_meter*0.25),"Wing guard takes chip and reduced defender strain with normal attacker cost")
	await fixture()
	p.dodge.start(Vector3.RIGHT)
	p.dodge.elapsed = p.dodge.DURATION*0.5
	w._begin(claw)
	boss_pulse(0)
	check(a.health == 1000 and a.last_evaded,"Teleport's hidden invincibility window works against the boss")
	p.dodge.cancel()
	await fixture()
	var innocents: float = world.sparring_partner.health
	check(not boss.can_attack_target(world.sparring_partner) and not boss.can_attack_target(world.population.residents[0]) and boss.can_attack_target(p),"Boss targets only its human opponent, protecting Ember and residents")
	check(p.target_lock.living(boss) and not p.target_lock.living(world.get_node("CounterSentry")),"Lock-on honors the active encounter and excludes unrelated practice targets")
	w._begin(Moves.move(&"double"))
	boss_pulse(0)
	boss_pulse(0)
	boss_pulse(1)
	check(a.health == 816 and world.sparring_partner.health == innocents,"Two legitimate boss pulses each resolve once without collateral damage")
	await fixture()
	# An actual ordinary hit can cross zero HP; no scripted immunity/finisher.
	w.health = 20
	a._begin(Library.move(&"down",&"attack_right"))
	a.strike(0)
	check(not encounter.active and boss.state == &"defeated" and encounter.progress.first_victory and encounter.can_progress(),"A normal first-encounter weapon strike can win and unlock progression")
	check(encounter.progress.first_outcome == "victory" and encounter.progress.wins == 1,"First-attempt victory remains a distinct persistent outcome")
	var completed: Dictionary = encounter.progress.duplicate(true)
	encounter.finish(true)
	check(encounter.progress == completed,"Duplicate lethal/completion callbacks cannot grant another result")
	var path := "user://greefer_test_"+str(hz)+".json"
	check(encounter.save_checkpoint(path),"Owner-scoped encounter journal writes a verified victory")
	encounter.progress = Journal.fresh()
	check(encounter.load_checkpoint(path) and encounter.progress.first_victory,"Reload preserves the first-attempt victory and progression unlock")
	check(Journal.read(path,"another-owner").is_empty(),"Encounter flags cannot load into a different inventory owner")
	await fixture()
	a.health = 50
	w._begin(claw)
	boss_pulse(0)
	check(not encounter.active and encounter.progress.losses == 1 and encounter.progress.first_victory and encounter.progress.last_outcome == "defeat" and encounter.can_progress(),"Rematch defeat preserves the first victory while remembering the latest outcome")
	check(a.health == 1000 and p.position.distance_to(p.spawn)<0.1,"Boss defeat uses the existing safe player respawn transition")
	check(encounter.save_checkpoint(path) and encounter.load_checkpoint(path) and encounter.progress.first_victory and encounter.progress.last_outcome == "defeat","Reload distinguishes the first victory from the latest rematch defeat")
	var damaged_file := FileAccess.open(path,FileAccess.WRITE)
	damaged_file.store_string("interrupted save")
	damaged_file.close()
	check(encounter.load_checkpoint(path) and encounter.progress.first_victory and encounter.progress.last_outcome == "victory","A damaged current journal falls back to the previous valid checkpoint")
	encounter.progress = Journal.fresh()
	await fixture()
	a.health = 50
	w._begin(claw)
	boss_pulse(0)
	check(encounter.can_progress() and encounter.progress.first_outcome == "defeat" and not encounter.progress.first_victory,"Losing the first fight also advances without a required retry")
	await fixture()
	encounter.progress = Journal.fresh()
	encounter.participated = false
	p.weapon_combat.receive_environment_damage(2000)
	check(not encounter.can_progress() and not encounter.active,"A fall before combat participation cannot falsely complete the intro")
	# Perception must never follow the player's live location through a building.
	await fixture()
	p.position = Vector3(0,0.045,-12)
	var wall := preload("res://scripts/neon.gd").block(world,Vector3(0,2,-16),Vector3(8,4,0.35))
	await frames(2)
	boss.last_known = Vector3(2,0,-15)
	var known: Vector3 = boss.last_known
	boss.perception_clock = 0
	boss.perceive(0.2)
	check(not boss.visible_target and boss.last_known == known,"Opaque architecture blocks sight and preserves only the last observed position")
	p.position += Vector3(1,0,1)
	boss.perception_clock = 0
	boss.perceive(0.2)
	check(boss.last_known == known,"Moving while occluded cannot magically update boss awareness")
	wall.queue_free()
	await frames(2)
	boss.perception_clock = 0
	boss.perceive(0.2)
	check(boss.visible_target and boss.last_known.is_equal_approx(p.position),"The boss reacquires the player only after real line of sight returns")
	boss.think_enabled = true
	boss.set_state(&"searching")
	boss.unseen_time = boss.search_duration+1
	boss.perception_clock = 100
	await frames(2)
	check(not encounter.active and boss.state == &"returning" and not encounter.can_progress(),"Search timeout disengages without completing an unfinished introduction")
	# Reusable authority boundary blocks non-host decisions and result writes.
	var client := ClientEncounter.new()
	client.player = p
	client.boss = boss
	client.active = true
	var before := client.progress.duplicate(true)
	client.finish(true)
	check(not client.start(true) and client.progress == before and not client.save_checkpoint(path),"Non-authoritative encounter instances cannot start, finish or persist results")
	client.free()
	if encounter.active: encounter.disengage()
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Greefer encounter verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
