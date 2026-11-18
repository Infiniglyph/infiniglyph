extends SceneTree
const Library = preload("res://scripts/weapon_library.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
const Journal = preload("res://scripts/encounter_progress.gd")
const Progress = preload("res://scripts/kyren_progress.gd")
var world: Node3D
var p: CharacterBody3D
var boss: CharacterBody3D
var encounter: CanvasLayer
var home: Node3D
var hz := 60
var checks := 0
var failures := 0
var serial := 500
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)
func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func seconds(time: float) -> void: await frames(ceili(time*hz))
func guard(actor: Node, fresh: bool = true) -> void:
	actor.combat.blocking=true
	actor.combat.fresh_block=fresh
	actor.weapon_combat._on_block(true)
	if not fresh: actor.weapon_combat.parry_remaining=0
func contact(action: StringName = &"attack_right") -> Dictionary:
	serial+=1
	var move := Library.move(&"katana",action)
	move.attack_serial=serial
	move.pulse=0
	move.action=String(action)
	move.item_id="katana"
	return move
func arrange() -> void:
	boss.controls.stop()
	boss.weapon_combat.reset()
	boss.combat.reset()
	boss.combat.sheathed=false
	boss.weapon_combat.sync_rig()
	p.dodge.cancel()
	p.combat.reset()
	p.combat.sheathed=false
	p.weapon_combat.reset()
	p.set_physics_process(false)
	boss.set_physics_process(false)
	boss.global_position=home.global_position+Vector3(8,.06,10)
	p.global_position=boss.global_position+Vector3(0,0,2.5)
	p.velocity=Vector3.ZERO
	boss.velocity=Vector3.ZERO
	p.target_lock.select(boss)
	boss.target_lock.select(p)
	await frames()
func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/kyren_"+label+".png")
func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	root.add_child(world)
	p=world.player
	home=world.wider_world.kyren_home
	boss=home.kyren
	encounter=world.kyren_encounter
	p.visual.retrieval.enabled=false
	await frames(10)
	check(boss.state==&"resting" and not encounter.active and not encounter.debug_enabled,"Kyren rests peacefully; combat and developer UI require explicit activation")
	check(p.kyren_encounter==encounter and boss.controls.opponent==p,"World, interaction and shared combat hooks reference the same encounter")
	p.global_position=boss.global_position+Vector3(0,.05,3)
	p.velocity=Vector3.ZERO
	await seconds(.3)
	check(encounter.can_talk() and world.inventory_session.can_talk(),"G / RT discovers Kyren beside the tree")
	encounter.interact()
	check(encounter.dialogue_open and not p.controls.gameplay_enabled and not paused,"Challenge invitation captures local input while world physics remains live")
	var button := InputEventJoypadButton.new()
	button.button_index=JOY_BUTTON_B
	button.pressed=true
	encounter._input(button)
	check(not encounter.dialogue_open and p.controls.gameplay_enabled and not encounter.active,"Controller B safely declines the optional boss")
	encounter.interact()
	world.start_menu.open_menu()
	check(not encounter.dialogue_open and world.start_menu.is_open and not paused,"Start/Settings safely takes over a challenge invitation without pausing the world")
	world.start_menu.close_menu()
	encounter.interact()
	encounter.yes.grab_focus()
	button.button_index=JOY_BUTTON_A
	encounter._input(button)
	check(encounter.active and encounter.progress.kyren.challenges==1,"Controller A accepts and records a genuine challenge")
	await seconds(.6)
	check(boss.state==&"fighting" and boss.visual.visible and not boss.rest_visual.visible and boss.visual.scale==Vector3.ONE*2,"Kyren stands up on the shared player skeleton at twice the normal scale")
	check(boss.rest_visual.hat.get_parent()==boss.head_anchor and boss.scarf.anchor==boss.scarf_anchor,"The original fiery hat and three-metre scarf follow his fighting skeleton")
	var stored: Node3D=boss.weapon_combat.rig.models[&"kyren_katana"].stowed
	check(stored.get_parent()==boss.visual.pelvis and not stored.visible and boss.weapon_combat.rig.models[&"kyren_katana"].right.is_visible_in_tree(),"Waking restores the same sword to the combat rig and draws it without a duplicate")
	check(not world.boss_encounter.start(true) and not world.theft_reactions.can_fight(),"Other boss and civilian encounters cannot corrupt Kyren's combat membership")
	await arrange()
	var fighting_position := boss.global_position
	boss.start_return()
	check(encounter.active and boss.global_position==fighting_position,"A return request cannot teleport or heal Kyren during an active encounter")
	var salt_before: float = encounter.salt.value
	var hit := contact()
	var damage: float = boss.receive_combat_hit(10,p.combat_point(),p,hit)
	check(damage==10 and encounter.salt.value==salt_before+2,"Resolved real damage drives salt through the shared event pipeline")
	encounter._boss_contact({"event_id":str(p.get_instance_id())+":"+str(serial)+":0:"+str(boss.get_instance_id()),"attack_key":"repeat","attacker":p,"damage":10,"incoming":hit,"health_ratio":1})
	check(encounter.salt.value==salt_before+2,"An overlapping duplicate signal cannot award salt twice")
	boss.weapon_combat.clear_stagger()
	boss.combat.reset()
	guard(boss)
	salt_before=encounter.salt.value
	damage=boss.receive_combat_hit(100,p.combat_point(),p,contact())
	check(damage==0 and boss.weapon_combat.last_outcome==&"parry" and encounter.salt.value==salt_before-3,"Kyren's timed parry uses normal zero-damage resolution and reduces salt")
	check(is_equal_approx(p.weapon_combat.stagger_remaining,1),"A Kyren parry preserves the existing one-second attacker stun")
	await arrange()
	guard(p)
	salt_before=encounter.salt.value
	damage=p.receive_combat_hit(100,boss.combat_point(),boss,contact())
	check(damage==0 and p.weapon_combat.last_outcome==&"parry" and encounter.salt.value==salt_before+8,"The player's timed parry embarrasses Kyren through the same resolver")
	check(is_equal_approx(boss.weapon_combat.stagger_remaining,1),"Kyren obeys the same one-second parry stun")
	await arrange()
	guard(boss,false)
	salt_before=encounter.salt.value
	damage=boss.receive_combat_hit(100,p.combat_point(),p,contact())
	check(damage>0 and damage<100 and boss.weapon_combat.last_blocked and encounter.salt.value==salt_before,"Block uses weapon-specific power and chip damage is not a clean salt hit")
	await arrange()
	boss.dodge.start(Vector3.RIGHT)
	boss.dodge.elapsed=boss.dodge.DURATION*.45
	salt_before=encounter.salt.value
	damage=boss.receive_combat_hit(100,p.combat_point(),p,contact())
	check(damage==0 and boss.weapon_combat.last_evaded and encounter.salt.value==salt_before,"Kyren's phase dodge grants only the shared iframe window")
	boss.dodge.cancel()
	check(boss.visual.scale==Vector3.ONE*2,"Finishing or cancelling a phase dodge preserves Kyren's doubled fighting stature")
	await arrange()
	var names: Dictionary = {}
	var poses: Dictionary = {}
	var valid := true
	for action: StringName in [&"attack_right",&"attack_left",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
		for index in range(3 if String(action).begins_with("attack_") else 1):
			var move := Library.move(&"kyren_katana",action,index)
			names[move.name]=true
			poses[JSON.stringify(move.motion)]=true
			valid=valid and move.get("retargeted",false) and move.parryable and move.hits[-1]<move.duration
	check(names.size()==10 and poses.size()>=8 and valid,"Ten distinct Uchigatana-derived techniques retain full sampled body motions and valid parryable hit windows")
	var signature := Library.move(&"kyren_katana",&"special_rt_y")
	var charged := Library.charged_move(&"kyren_katana",&"special_rt_y",1)
	check(signature.has("dash") and signature.auto_sheathe and charged.dash.start<charged.hits[0] and charged.dash.end>charged.hits[0],"Silent Contour and its charged release align the speed strike with the actual impact")
	p.global_position+=Vector3(0,0,12)
	boss.set_physics_process(true)
	boss.state=&"fighting"
	var origin: Vector3 = boss.global_position
	boss.weapon_combat._begin(signature)
	await seconds(float(signature.duration)+.3)
	check(boss.global_position.distance_to(origin)>2 and boss.global_position.distance_to(origin)<6.5,"The speed strike travels through ordinary collision-checked player movement")
	check(boss.combat.sheathed and boss.weapon_combat.rig.sheathed and boss.weapon_combat.active_move.is_empty(),"The named weapon automatically sheathes after its finishing gesture")
	await arrange()
	boss.weapon_combat._begin(signature)
	boss.weapon_combat.elapsed=.25
	var velocity: Vector2 = boss.weapon_combat.drive_velocity(Vector2(1,2))
	check(velocity.length()>20,"Speed strike reaches its configured super-speed window")
	boss.weapon_combat.cancel()
	check(not boss.weapon_combat._dash_active and Vector2(boss.velocity.x,boss.velocity.z)==Vector2(1,2),"Cancelling the speed strike restores carried movement and clears its drive")
	await arrange()
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(12,6,.25)
	collider.shape=box
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position=boss.global_position+Vector3(0,3,1.6)
	p.global_position+=Vector3(0,0,12)
	boss.set_physics_process(true)
	origin=boss.global_position
	await frames()
	boss.weapon_combat._begin(signature)
	await seconds(float(signature.duration)+.2)
	check(boss.global_position.z<wall.global_position.z-.5 and boss.global_position.distance_to(origin)<1.3,"The full capsule stops a super-speed strike at a real wall")
	wall.queue_free()
	await frames()
	await arrange()
	boss.controls.start()
	boss.controls.defense_cooldown=0
	boss.controls.decision=100
	boss.controls.seen_serial=-1
	p.weapon_combat._begin(Library.move(&"katana",&"special_x"))
	boss.controls.sample()
	check(not boss.controls.dodge_requested and not boss.controls.is_blocking() and boss.controls.threat_time<boss.controls.reaction_delay,"Seeing a windup does not grant Kyren an instantaneous counter")
	p.weapon_combat.cancel()
	boss.controls.stop()
	p.set_physics_process(true)
	world.controls.jump_requested=true
	await frames(2)
	world.controls.jump_requested=true
	await frames(2)
	check(p.air_step_count>0 and p.velocity.y>0 and encounter._patterns.get("sky",0)>0,"A real unrestricted Sky Jump is observed as an aerial combat pattern")
	p.set_physics_process(false)
	await arrange()
	var alive: float = p.health
	boss.weapon_combat._begin(Library.move(&"kyren_katana",&"special_x"))
	boss.weapon_combat.elapsed=float(boss.weapon_combat.active_move.hits[0])
	guard(p)
	boss.weapon_combat.strike(0)
	check(p.health==alive and p.weapon_combat.last_parried and boss.weapon_combat.is_staggered(),"A genuine expansive named light-wave pulse is parried by normal hit detection")
	await arrange()
	encounter.salt.set_value(100)
	boss.controls.rng.seed=61277
	boss.controls.start()
	boss.set_physics_process(true)
	boss.weapon_combat.max_health=100000
	boss.weapon_combat.health=100000
	p.weapon_combat.health=100000
	var decisions: int = boss.controls.decisions
	await seconds(5)
	check(boss.controls.decisions>decisions and boss.controls.behavior!="resting" and p.health<100000,"At 100% salt Kyren still pursues, selects techniques and lands real combat hits")
	boss.controls.stop()
	boss.weapon_combat.max_health=boss.base_health
	p.weapon_combat.reset()
	var returning_from: Vector3 = boss.global_position
	encounter.disengage()
	check(boss.state==&"resting" and boss.global_position.is_equal_approx(boss.home_point) and returning_from.distance_to(boss.home_point)>1,"Disengagement teleports Kyren directly to his tree without pathfinding")
	check(stored.get_parent()==boss.rest_visual.sword_anchor and stored.is_visible_in_tree(),"Disengagement restores the visible sheathed sword to his seated hip")
	check(not p.is_in_group("combat_targets") and not p.get_collision_layer_value(2),"Disengagement restores ordinary player hurtbox membership")
	p.global_position=boss.global_position+Vector3(0,.1,3)
	p.set_physics_process(false)
	var challenges: int = encounter.progress.kyren.challenges
	boss.receive_combat_hit(1,p.combat_point(),p,contact())
	check(encounter.active and encounter.progress.kyren.challenges==challenges+1,"Attacking a resting Kyren starts the same optional encounter before applying damage")
	boss.controls.stop()
	boss.global_position+=Vector3(15,4,-8)
	boss.velocity=Vector3(12,-8,5)
	var lethal_health: float = boss.health
	var lethal_damage: float = boss.receive_combat_hit(100000,p.combat_point(),p,contact())
	check(lethal_damage==lethal_health,"A genuine lethal hit reports its damage correctly when Kyren resets home inside the defeat callback")
	check(encounter.progress.wins==1 and encounter.progress.kyren.consecutive_defeats==1 and boss.state==&"defeated","A genuine victory records the outcome and briefly defeats Kyren")
	check(boss.global_position.is_equal_approx(boss.home_point) and boss.velocity==Vector3.ZERO and boss.rest_visual.visible and not boss.visual.visible,"Losing immediately teleports Kyren home and restores his resting presentation")
	check(not boss.controls.active and boss.weapon_combat.active_move.is_empty() and not boss.dodge.active and not boss.target_lock.is_locked() and boss.combat.sheathed,"The return clears AI, attack, phase, lock and weapon state")
	check(encounter.dialogue.current_id=="perfect_victory","A no-damage victory triggers its genuine special reaction")
	check(not encounter.dialogue._important.is_empty(),"A real starter-only victory queues its additional equipment reaction")
	var path := "user://tests/kyren_encounter.json"
	Journal.store(path,p.inventory.owner_id,{"greefer":Journal.fresh()})
	check(encounter.save_checkpoint(path) and Journal.read(path,p.inventory.owner_id).has("greefer"),"Saving Kyren merges with existing Greefer history")
	encounter.progress=Progress.fresh()
	check(encounter.load_checkpoint(path) and encounter.progress.wins==1 and encounter.progress.kyren.challenges==challenges+1,"Owner-scoped persistence restores outcomes, challenges and lingering salt")
	await seconds(4)
	check(boss.state==&"resting" and boss.global_position.is_equal_approx(boss.home_point) and boss.health==boss.base_health,"Defeat recovery expires at home without restarting movement or looping")
	p.global_position=boss.global_position+Vector3(0,.1,3)
	encounter.start(true)
	boss.controls.stop()
	encounter.finish(true)
	await seconds(4)
	p.global_position=boss.global_position+Vector3(0,.1,3)
	encounter.start(true)
	boss.controls.stop()
	encounter.finish(true)
	check(encounter.progress.kyren.three_defeats_seen and encounter.dialogue.current_id=="three_defeats_first","Three consecutive recorded defeats trigger the rare exchange exactly once")
	await seconds(4)
	p.global_position=boss.global_position+Vector3(0,.1,3)
	encounter.start(true)
	boss.controls.stop()
	boss.global_position+=Vector3(-18,2,12)
	p.receive_combat_hit(100000,boss.combat_point(),boss,contact())
	check(not encounter.active and p.health==p.weapon_combat.max_health and encounter.progress.losses==1 and encounter.progress.kyren.consecutive_defeats==0,"Player defeat closes the encounter, respawns normally and resets the loss streak")
	check(encounter.dialogue.current_id=="revenge_victory","Kyren winning after previous losses selects his genuine revenge reaction")
	check(encounter._damaged,"The perfect-victory tracker records genuine incoming damage")
	check(boss.state==&"resting" and boss.global_position.is_equal_approx(boss.home_point) and boss.velocity==Vector3.ZERO,"Winning teleports Kyren home immediately and leaves no chase running")
	check(boss.visual.scale==Vector3.ONE*2,"Repeated fights, defeats and return transitions retain Kyren's original size")
	check(stored.get_parent()==boss.rest_visual.sword_anchor and stored.is_visible_in_tree() and stored.find_children("KyrenSaya","",true,false).size()==1,"Winning and losing repeatedly preserve a single visible sheathed sword and saya")
	await seconds(1)
	p.global_position=boss.global_position+Vector3(0,.1,3)
	encounter.start(true)
	boss.controls.stop()
	p.global_position=boss.global_position+Vector3(200,100,0)
	encounter.disengage_seconds=.3
	await seconds(.8)
	check(not encounter.active and boss.state==&"resting" and boss.global_position.is_equal_approx(boss.home_point),"Leaving sight and range closes combat before Kyren teleports home")
	encounter.debug_enabled=true
	var debugger := preload("res://scripts/kyren_debug.gd").new()
	debugger.encounter=encounter
	encounter.add_child(debugger)
	debugger.set_salt(75)
	check(encounter.salt.value==75 and encounter.salt.state()==&"meltdown","Explicit developer tools can exercise salt-state boundaries")
	debugger.preview_dialogue("three_defeats_second")
	check(encounter.dialogue.current_id=="three_defeats_second","Developer preview uses the same subtitle channel")
	debugger.reset_history()
	check(encounter.progress.kyren.challenges==0 and encounter.progress.wins==0 and encounter.salt.value==10,"Developer history reset clears Kyren metadata and learned patterns")
	debugger.queue_free()
	encounter.debug_enabled=false
	if "--capture" in OS.get_cmdline_user_args():
		p.global_position=boss.global_position+Vector3(-3,.1,3)
		p.set_physics_process(false)
		encounter.start(true)
		await seconds(.6)
		boss.controls.stop()
		boss.set_physics_process(false)
		boss.velocity=Vector3.ZERO
		boss.visual.animate(.2,Vector3.ZERO,true)
		boss.weapon_combat.apply_pose(.2)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.fov=55
		camera.position=boss.global_position+Vector3(4,2.5,5)
		camera.look_at(boss.global_position+Vector3.UP*1.9)
		camera.current=true
		print("KYREN RENDER: camera distance=",camera.global_position.distance_to(boss.global_position)," height=",boss.head_anchor.global_position.y-boss.global_position.y," scale=",boss.visual.global_basis.get_scale())
		encounter.salt.set_value(85)
		encounter.dialogue.preview("meltdown")
		await capture("master_stance")
		boss.weapon_combat._begin(signature)
		boss.weapon_combat.elapsed=.3
		boss.weapon_combat.set_physics_process(false)
		boss.weapon_combat.apply_pose(.2)
		await capture("draw_strike")
		boss.weapon_combat.elapsed=1.2
		boss.weapon_combat.apply_pose(.2)
		await capture("sheathing")
	world.queue_free()
	await process_frame
	print("KYREN ENCOUNTER: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
