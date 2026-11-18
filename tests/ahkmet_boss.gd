extends SceneTree
const Moves=preload("res://scripts/lorai_moves.gd")
const Store=preload("res://scripts/inventory_store.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Database=preload("res://scripts/equipment_database.gd")
const Preview=preload("res://scripts/equipment_preview.gd")
const Pickup=preload("res://scripts/item_pickup.gd")
const Arrow=preload("res://scripts/pyramid_arrow.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var manager: Node3D
var encounter: Node3D
var boss: CharacterBody3D
var hz:=60
var checks:=0
var failures:=0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)
func frames(n: int=2) -> void:
	for i in range(n):
		await physics_frame
		await process_frame
func wait_seconds(seconds: float) -> void: await frames(ceili(seconds*hz))
func enter() -> void:
	manager.reset_run()
	p.global_position=Vector3(0,-143.94,-34)
	p.velocity=Vector3.ZERO
	p.weapon_combat.reset()
	p.combat.reset()
	travel.interior.update_visibility(p.global_position,true)
	manager.ensure_spawned(&"B8")
	encounter=manager.b8
	boss=encounter.boss
	boss.think_enabled=false
	boss.engaged=true
	for e in manager.enemies:
		if is_instance_valid(e):
			e.controls.active=false
			e.set_physics_process(false)
	await frames()

func run() -> void:
	create_timer(150).timeout.connect(func():push_error("AHKMET WATCHDOG");quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	p=world.player
	var input:=Intent.new()
	root.add_child(input)
	p.controls=input
	world.camera_rig.controls=input
	world.inventory_session.controls=input
	p.visual.retrieval.enabled=false
	world.loot.death_drop_probability=0
	travel=world.dungeon_travel
	manager=travel.encounters
	await frames(4)
	travel._set_location(travel.pyramid_id)
	p.set_physics_process(false)
	await enter()
	if "--capture" in OS.get_cmdline_user_args():
		boss.set_physics_process(false)
		boss.weapon_combat.set_physics_process(false)
		p.global_position=Vector3(0,-143.94,-33)
		p.visual.rotation.y=PI
		p.visual.rebase_after_phase()
		p.fall_damage.reset()
		p.set_physics_process(true)
		p.target_lock.select(boss)
		for phase: int in [1,2]:
			boss.phase=phase
			boss.visual.pose({},0,phase,0)
			world.camera_rig.yaw=0
			world.camera_rig.reset_follow()
			await frames(20)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/ahkmet_gameplay_phase"+str(phase)+".png")
		print("AHKMET GAMEPLAY: two native captures")
		quit()
		return
	check(is_instance_valid(boss) and boss.phase==1 and boss.health==2400,"B8 lazily spawns one shared-health mounted boss")
	var original:=boss.get_instance_id()
	manager.ensure_spawned(&"B8")
	check(manager.b8.boss.get_instance_id()==original,"Repeated floor requests never duplicate the boss")
	check(boss.visual.ahkmet.get_parent()==boss.visual.rider and boss.visual.rider.get_parent()==boss.visual.head,"Ahkmet stands on the head socket, without a separate platform")
	check(boss.hurtboxes.size()==27 and boss.visual.links.size()==26,"Bounded compound hurtboxes follow a controlled continuous serpent")
	check(world.camera_rig._encounter_scale==1.8,"Boss framing expands the existing collision-aware camera")
	check(encounter.hud.get_viewport()==p.get_viewport(),"Boss health and transition UI render in the player's viewport, not the physics instance")
	var equipped_distance: float=world.camera_rig.get_follow_distance()
	var hp: float=boss.health
	# A real player weapon query must reach Lorai's low head/body from the floor.
	p.global_position=boss.visual.to_global(boss.visual.points[10])+Vector3(3.2,0,0)
	p.global_position.y=-143.94
	var toward: Vector3=(boss.combat_point()-p.combat_point()).normalized()
	p.camera_rig.yaw=atan2(-toward.x,-toward.z)
	var light: Dictionary=p.weapon_combat.move_for(&"down",&"attack_right")
	p.weapon_combat._begin(light)
	p.weapon_combat._facing=toward
	p.weapon_combat.strike(0)
	check(boss.health<hp,"Basic starter weapon geometry can damage the grounded serpent")
	p.weapon_combat.cancel()
	var moves_valid:=true
	for style: String in Moves.PHASE_ONE+Moves.PHASE_TWO:
		var move:=Moves.move(style)
		moves_valid=moves_valid and float(move.windup)>=.7 and float(move.duration)-float(move.hits[-1])>=.9 and move.parryable
	check(moves_valid,"All eleven attacks have readable windups and punishable recoveries")
	# Sweep the actual animated mouth through a fixed player; rates sample the same path.
	p.global_position=Vector3(0,-143.94,-39)
	p.weapon_combat.reset()
	boss.weapon_combat._begin(Moves.move("lunge"))
	await wait_seconds(2.7)
	check(p.health<1000,"Serpent Lunge deals real damage from its moving head geometry")
	boss.weapon_combat.cancel()
	p.weapon_combat.reset()
	p.global_position=Vector3(0,-143.94,-24)
	boss.start_attack("judgment")
	await wait_seconds(2.6)
	check(p.health<1000,"Radiant Judgment releases a shared physical golden projectile")
	boss.weapon_combat.cancel()
	p.weapon_combat.reset()
	boss.start_attack("spit")
	await wait_seconds(1.3)
	check(boss.weapon_combat.fields.size()==1 and boss.weapon_combat.arrows.size()<=2,"Venom Spit creates a bounded, warned venom field and projectile spray")
	boss.weapon_combat.cancel()
	check(boss.weapon_combat.fields.is_empty() and boss.weapon_combat.arrows.is_empty(),"Cancellation reclaims every boss field and projectile")
	# Direct shared hits test the phase lifecycle, never replace combat simulation above.
	boss.receive_combat_hit(99999,p.combat_point(),p,{"action":"attack_right"})
	var threshold_hp: float=boss.health
	check(boss.phase==0 and is_equal_approx(threshold_hp,1248) and not boss.dead,"A lethal-sized Phase 1 hit starts the union without a death or health refill")
	check(not manager.defeated_ids.has("ahkmet_lorai") and not p.inventory.boss_reward_claims.has("ahkmet_lorai"),"Transformation never counts as a clear or claims loot")
	check(boss.receive_hit(500,p.combat_point(),p)==0 and boss.health==threshold_hp,"Brief narrative transition preserves the shared remaining health")
	var saved: Dictionary=travel.location_state()
	var snapshot: Dictionary=Store.encode(p.inventory,world.loot.serialize_world(),[],world.loot.session_id,String(travel.pyramid_id),saved)
	check(not snapshot.is_empty() and snapshot.location_state.ahkmet.phase==2 and snapshot.location_state.ahkmet.hp==threshold_hp,"Saving during the union normalizes to stable Phase 2 without minting health")
	p.global_position+=Vector3.UP*5
	p._physics_process(1.0/hz)
	p.controls.jump_requested=true
	p._physics_process(1.0/hz)
	check(p.velocity.y>8 and p.air_step_count>0 and not p.transition_locked,"Real Sky Jump remains available during the union without an input lock")
	var original_staff: int=boss.visual.staff.get_instance_id()
	await wait_seconds(3)
	var right_hand: Vector3=boss.visual.ahkmet.joints.RightArm.to_global(Vector3(0,-.55,0))
	var left_hand: Vector3=boss.visual.ahkmet.joints.LeftArm.to_global(Vector3(0,-.55,0))
	check(boss.visual.ahkmet.visible and boss.visual.jaw.rotation.x>.5 and right_hand.distance_to(left_hand)>1.8,"Ahkmet visibly spreads both arms before entering Lorai's waiting jaws")
	await wait_seconds(5.6)
	check(boss.phase==2 and boss.health==threshold_hp and boss.get_instance_id()==original,"The same serpent completes Phase 2 with exactly the remaining health")
	check(not boss.visual.ahkmet.visible and boss.visual.arm_growth==1 and boss.visual.arms.size()==2,"Union leaves the serpent head/body intact and reveals two muscular arms")
	check(boss.visual.staff.get_instance_id()==original_staff and boss.visual.staff.get_parent()==boss.visual.hands[0],"Ahkmet's original staff is inherited by Lorai's hand")
	# Shared defense: one-second attacker stun, no parallel parry implementation.
	p.weapon_combat.reset()
	p.combat.blocking=true
	p.weapon_combat.parry_remaining=.18
	p.weapon_combat._facing=(boss.combat_point()-p.global_position).normalized()
	p.camera_rig.yaw=atan2(-p.weapon_combat._facing.x,-p.weapon_combat._facing.z)
	boss.weapon_combat.active_move=Moves.move("bite")
	boss.weapon_combat.resolve_strike(Moves.move("bite"),0,boss.combat_point(),[{"collider":p,"rid":p.get_rid(),"shape":0}],false)
	check(p.health==1000 and p.weapon_combat.last_parried and is_equal_approx(boss.weapon_combat.stagger_remaining,1),"Existing parry negates boss damage and stuns the attacker for one second")
	p.combat.blocking=false
	boss.weapon_combat.clear_stagger()
	boss.weapon_combat.cancel()
	p.weapon_combat.reset()
	p.combat.blocking=true
	p.weapon_combat.parry_remaining=0
	boss.weapon_combat.resolve_strike(Moves.move("bite"),-1,boss.combat_point(),[{"collider":p,"rid":p.get_rid(),"shape":0}],false,true)
	check(p.weapon_combat.last_blocked and p.health>840 and p.health<1000,"Existing weapon block power mitigates the boss bite")
	p.combat.blocking=false
	p.weapon_combat.reset()
	p.dodge.active=true
	p.dodge.elapsed=.15
	boss.weapon_combat.resolve_strike(Moves.move("grasp"),1,boss.combat_point(),[{"collider":p,"rid":p.get_rid(),"shape":0}],false,true)
	check(p.health==1000 and p.weapon_combat.last_evaded,"The normal dodge window evades Serpent Grasp")
	p.dodge.cancel()
	# A golden projectile physically reaches a fresh parry window.
	p.weapon_combat.reset()
	p.combat.blocking=true
	p.weapon_combat.parry_remaining=.18
	p.weapon_combat._facing=Vector3.FORWARD
	p.camera_rig.yaw=0
	var bolt:=Arrow.new()
	bolt.actor=boss
	bolt.combat=boss.weapon_combat
	bolt.move=Moves.move("judgment")
	bolt.glyph=true
	bolt.direction=Vector3.BACK
	boss.get_parent().add_child(bolt)
	bolt.global_position=p.combat_point()+Vector3.FORWARD*1.8
	boss.weapon_combat.arrows.append(bolt)
	await wait_seconds(.13)
	check(p.health==1000 and p.weapon_combat.last_parried and boss.weapon_combat.stagger_remaining>.75,"A real incoming golden light projectile can be parried")
	p.combat.blocking=false
	boss.weapon_combat.clear_stagger()
	boss.receive_combat_hit(1,p.combat_point(),p,{"action":"attack_right","hit_stun_level":9})
	check(not boss.weapon_combat.is_staggered(),"Light attacks preserve the global no-stunlock rule on the boss")
	boss.receive_combat_hit(1,p.combat_point(),p,{"action":"special_x","hit_stun_level":3,"hit_stagger":.3})
	check(boss.weapon_combat.is_staggered(),"Committed weapon arts can stagger the boss normally")
	boss.weapon_combat.clear_stagger()
	# Exercise the physical mouth, arm and inherited staff volumes at their
	# authored contact positions, including a target above the arena floor.
	var contact_hits:=true
	var contact_dedup:=true
	for style: String in ["sweep","grasp","annihilation","bite","inherited"]:
		p.weapon_combat.reset()
		boss.weapon_combat.cancel()
		boss.phase=1 if style=="sweep" else 2
		boss.attack_goal=boss.global_position+Vector3(0,1.3,11)
		var move:=Moves.move(style)
		boss.visual.pose(move,float(move.hits[0]),boss.phase,0)
		var segments: Array=boss.visual.attack_segments(move,0)
		var span: Dictionary=segments[0]
		p.global_position=(span.a as Vector3).lerp(span.b,.75)-Vector3.UP*.9
		await frames()
		var count_before: int=boss.weapon_combat.total_hits
		boss.weapon_combat._begin(move)
		await wait_seconds(float(move.hits[0])+.24)
		contact_hits=contact_hits and p.health<1000
		contact_dedup=contact_dedup and boss.weapon_combat.total_hits==count_before+1
		if p.health==1000: print("MISSED AUTHORED CONTACT ",style," p=",p.global_position)
	check(contact_hits,"Sweep, grasp, aerial staff cleave, bite and inherited command use real animated contacts")
	check(contact_dedup,"Each active contact window damages a target once across its temporal samples")
	boss.weapon_combat.cancel()
	boss.phase=2
	check(boss.choose_attack(35,8) in ["storm","inherited","annihilation"],"Observed aerial distance selects inherited ranged pressure")
	boss.cursor=0
	check(boss.choose_attack(10,0) in ["bite","grasp","coil","annihilation","inherited","storm"],"Observed grounded positioning selects close-range pressure")
	boss.start_attack("bite")
	check(not boss.start_attack("storm"),"The controller prevents overlapping attack animation states")
	boss.weapon_combat.cancel()
	# Invalid checkpoint data must not become an encounter or entitlement.
	var invalid: Dictionary=snapshot.duplicate(true)
	invalid.location_state.ahkmet.phase=0
	check(Store.decode(invalid).is_empty(),"Checkpoints reject a raw intermediate transformation state")
	invalid=snapshot.duplicate(true)
	invalid.location_state.ahkmet.hp=-1
	check(Store.decode(invalid).is_empty(),"Checkpoints reject invalid boss health")
	invalid=snapshot.duplicate(true)
	invalid.inventory.boss_reward_claims={"ahkmet_lorai":"yes"}
	check(Store.decode(invalid).is_empty(),"First-clear claims are validated owner inventory data")
	# Ground wave's live annulus excludes airborne feet.
	p.weapon_combat.reset()
	p.global_position=Vector3(0,-139.0,-29)
	boss.weapon_combat._begin(Moves.move("coil"))
	boss.weapon_combat.strike(0)
	await wait_seconds(2.2)
	check(p.health==1000,"Sky Jump height clears Cataclysmic Coil's expanding ground annulus")
	boss.weapon_combat.cancel()
	p.global_position.y=-143.94
	boss.weapon_combat._begin(Moves.move("coil"))
	boss.weapon_combat.strike(0)
	await wait_seconds(2.2)
	check(p.health<1000,"The same expanding annulus damages a grounded target")
	boss.weapon_combat.cancel()
	# All first-clear copies and checkpoint entitlements commit atomically.
	var before: int=world.loot.pickups.size()
	var factories: Array=[0]
	world.loot.spawn_factory=func():
		factories[0]+=1
		return Pickup.new() if factories[0]<3 else Node3D.new()
	boss.receive_combat_hit(99999,p.combat_point(),p,{"action":"attack_right"})
	await frames(3)
	check(world.loot.pickups.size()==before and not p.inventory.boss_reward_claims.has("ahkmet_lorai") and not manager.defeated_ids.has("ahkmet_lorai"),"A failed third reward factory rolls back the entire first-clear bundle")
	world.loot.spawn_factory=Callable()
	encounter.complete_rewards()
	check(encounter.finished and manager.defeated_ids.has("ahkmet_lorai") and world.loot.pickups.size()==before+9,"One genuine clear drops all first-clear keepsakes, a catalyst and a rare glyph")
	encounter.finish()
	await frames()
	check(world.loot.pickups.size()==before+9,"Reentrant completion cannot duplicate boss rewards")
	var persisted: Dictionary=Store.encode(p.inventory,world.loot.serialize_world(),[],world.loot.session_id,String(travel.pyramid_id),travel.location_state())
	check(not persisted.is_empty() and persisted.inventory.boss_reward_claims.ahkmet_lorai,"First-clear claims and world-drop ownership persist together")
	await frames(3)
	check(world.camera_rig._encounter_scale==1 and world.camera_rig.get_follow_distance()==equipped_distance,"Completion restores the user's saved camera distance")
	await enter()
	check(boss.phase==1 and boss.health==2400 and p.inventory.boss_reward_claims.ahkmet_lorai,"Reset restores the boss while retaining the earned first-clear claim")
	boss.receive_hit(99999,p.combat_point(),p,{"action":"attack_right"})
	p.weapon_combat.health=0
	manager._on_player_defeated()
	await frames()
	check(not is_instance_valid(manager.b8) and manager.boss_state.is_empty() and world.camera_rig._encounter_scale==1,"Player death during the union retires all attacks, state and camera framing")
	await enter()
	boss.receive_hit(99999,p.combat_point(),p,{"action":"attack_right"})
	var checkpoint: Dictionary=travel.location_state()
	check(travel.restore_location(travel.pyramid_id,checkpoint),"A checkpoint can reload in the live dungeon")
	encounter=manager.b8
	boss=encounter.boss
	boss.think_enabled=false
	check(boss.phase==2 and boss.health==1248,"Loading a transition checkpoint resumes stable Phase 2")
	var sleeping_id: int=boss.get_instance_id()
	manager.ensure_spawned(&"B2")
	manager.ensure_spawned(&"B3")
	manager.ensure_spawned(&"B4")
	manager._limit_loaded(&"B4")
	check(not is_instance_valid(manager.b8) and manager.boss_state.get("phase")==2 and manager.boss_state.get("hp")==1248,"Streaming an old B8 roster preserves primitive phase/health state")
	manager.ensure_spawned(&"B8")
	manager._limit_loaded(&"B8")
	encounter=manager.b8
	boss=encounter.boss
	boss.think_enabled=false
	check(boss.phase==2 and boss.health==1248 and boss.get_instance_id()!=sleeping_id,"Revisiting a streamed B8 resumes the same remaining encounter")
	before=world.loot.pickups.size()
	boss.receive_hit(99999,p.combat_point(),p,{"action":"attack_right"})
	await frames(3)
	check(world.loot.pickups.size()==before+3,"Repeat victory awards a fresh gear copy, catalyst and rare glyph")
	var gear_ok:=true
	for id: StringName in encounter.FIRST_CLEAR:
		var definition: Resource=Catalog.get_definition(id)
		gear_ok=gear_ok and definition!=null
		if not Database.get_item(id).is_empty():
			var copy: Resource=Catalog.create(id)
			gear_ok=gear_ok and p.inventory.add_item(copy)
			var item: Dictionary=Database.get_item(id)
			var slot:=StringName(item.slot)
			gear_ok=gear_ok and p.inventory.assign(slot,copy.instance_id)
			var preview: Node3D=Preview.model(item)
			root.add_child(preview)
			gear_ok=gear_ok and preview.find_children("*","MeshInstance3D",true,false).size()>0
			preview.queue_free()
	check(gear_ok,"All boss equipment equips, previews and uses the existing catalog")
	# Let the real controller carry both phases without issuing any attack
	# requests. The stationary test target gets extra health only as a fixture.
	await enter()
	boss.think_enabled=true
	p.global_position=boss.global_position+Vector3(0,0,25)
	p.weapon_combat.max_health=100000
	p.weapon_combat.reset()
	var decisions: Array=[]
	boss.weapon_combat.attack_started.connect(func(move: Dictionary): decisions.append(move.lorai_style))
	var start_point: Vector3=boss.global_position
	await wait_seconds(14)
	check(decisions.size()>=3 and boss.global_position.distance_to(start_point)>1,"Mounted AI independently approaches and executes multiple committed techniques")
	check(p.health<100000,"The live mounted AI lands genuine combat hits without scripted strikes")
	boss.weapon_combat.cancel()
	boss.decision_clock=100
	p.global_position=boss.home+Vector3(0,0,100)
	await wait_seconds(8)
	check(boss.global_position.distance_to(boss.home)<=boss.arena_roam_radius+.001,"Colossal locomotion leaves room for the body inside the inscribed pillars")
	p.global_position=boss.global_position+Vector3(0,0,14)
	boss.receive_hit(99999,p.combat_point(),p,{"action":"attack_right"})
	await wait_seconds(8.6)
	var decision_start:=decisions.size()
	await wait_seconds(15)
	var ascendant_decisions:=true
	for i in range(decision_start,decisions.size()): ascendant_decisions=ascendant_decisions and decisions[i] in Moves.PHASE_TWO
	check(decisions.size()>=decision_start+3 and ascendant_decisions,"The live Ascendant AI selects and completes its own distinct moveset")
	check(boss.weapon_combat.contact_checks>0 and boss.weapon_combat.arrows.size()<=8 and boss.weapon_combat.fields.size()<=4,"Sustained live combat keeps contact sampling, projectiles and fields bounded")
	p.weapon_combat.max_health=1000
	await enter()
	boss.phase_two_threshold=.63
	boss.receive_hit(99999,p.combat_point(),p,{"action":"attack_right"})
	check(boss.phase==0 and is_equal_approx(boss.health,1512) and not Store.encode(p.inventory,[],[],"singleplayer",String(travel.pyramid_id),travel.location_state()).is_empty(),"The configurable union threshold also survives checkpoint validation")
	travel._set_location(&"overworld")
	await frames()
	check(not is_instance_valid(manager.b8) and manager.defeated_ids.is_empty() and not travel.location_state().has("ahkmet"),"Leaving the dungeon during the union resets the entire encounter")
	check(not paused,"The boss encounter never pauses the world")
	print("AHKMET B8: ",checks," checks; failures=",failures,"; Hz=",hz)
	world.queue_free()
	await frames()
	quit(1 if failures else 0)
