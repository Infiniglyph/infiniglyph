extends SceneTree
## Isolated actual Player receivers and shared strike resolution. No substitute
## defense implementation: spells must use the game's existing parry and dodge.
const Player = preload("res://scripts/player.gd")
const Wand = preload("res://scripts/wand_effect.gd")
class Intent extends "res://scripts/player_input.gd":
	func _ready() -> void: pass
	func sample() -> void: pass
class Aim extends Node3D:
	var yaw := 0.0
	var camera: Camera3D
	func reset_follow() -> void: pass
var arena: Node3D
var p: CharacterBody3D
var q: CharacterBody3D
var camera: Camera3D
var failures := 0
var checks := 0
var hz := 60
var serial := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks+=1
	if ok: print("PASS: ",title)
	else:
		failures+=1
		push_error("FAIL: "+title)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func fighter(point: Vector3) -> CharacterBody3D:
	var actor:=Player.new()
	actor.controls=Intent.new()
	actor.add_child(actor.controls)
	actor.camera_rig=Aim.new()
	actor.camera_rig.camera=camera
	actor.add_child(actor.camera_rig)
	actor.spawn=point
	actor.live_motion_retrieval=false
	arena.add_child(actor)
	actor.collision_layer=2
	actor.add_to_group("combat_targets")
	return actor

func reset(distance: float = 6) -> void:
	for effect in get_nodes_in_group("wand_effects"): effect.expire()
	p.weapon_combat.reset()
	q.weapon_combat.reset()
	p.combat.sheathed=false
	q.combat.sheathed=false
	p.combat.blocking=false
	q.combat.blocking=false
	p.dodge.cancel()
	q.dodge.cancel()
	p.position=Vector3(0,.02,0)
	q.position=Vector3(0,.02,distance)
	p.velocity=Vector3.ZERO
	q.velocity=Vector3.ZERO
	p.visual.rotation.y=0
	q.visual.rotation.y=PI
	p.target_lock.select(q)
	q.target_lock.select(p)

func cast(kind: String, target: Node3D = q) -> Node3D:
	serial+=1
	var definition := {"name":"Wand Test "+kind,"wand_attack":kind,"weapon_family":"wand","profile":"wand_"+kind,"action":&"attack_right" if kind=="flick" else &"special_x","reach":4.0 if kind=="flick" else 12.0,"arc":360.0,"damage":30.0,"parryable":true,"hit_stun_level":0.0,"hit_stagger":0.0,"attack_serial":serial}
	var effect := Wand.new()
	effect.configure(p,p.weapon_combat,definition,p.combat_point(),Vector3.BACK,Color.CYAN,target)
	arena.add_child(effect)
	return effect

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("TEST WATCHDOG");quit(2))
	arena=Node3D.new()
	root.add_child(arena)
	camera=Camera3D.new()
	arena.add_child(camera)
	var floor:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(60,1,60)
	collider.shape=box
	floor.add_child(collider)
	floor.position.y=-.5
	arena.add_child(floor)
	p=fighter(Vector3(0,.02,0))
	q=fighter(Vector3(0,.02,6))
	await frames(5)
	for actor in [p,q]:
		actor.set_physics_process(false)
		actor.weapon_combat.set_physics_process(false)
	for kind in ["flick","slither","volley","ground","wheel"]:
		reset(2.5 if kind=="flick" else 6)
		await frames(2)
		cast(kind)
		await frames(ceili(hz*.85))
		check(q.health<q.weapon_combat.max_health,"Shared receiver takes actual "+kind+" laser contact")
		var expected := 90.0 if kind=="volley" else 30.0
		check(is_equal_approx(q.weapon_combat.max_health-q.health,expected),kind+" deals one bounded contact per bolt without duplicate melee damage")
		# A fresh frontal guard at impact, using ordinary receive_hit recoil.
		reset(2.5 if kind=="flick" else 6)
		q.combat.blocking=true
		q.weapon_combat.parry_remaining=.18
		await frames(2)
		var effect:=cast(kind)
		for i in range(ceili(hz*.8)):
			await frames(1)
			if not is_instance_valid(effect) or effect.deflected: break
		check(q.weapon_combat.last_parried and q.health==q.weapon_combat.max_health,kind+" obeys the universal frontal parry without damage")
		check(p.weapon_combat.forced_state==&"parried" and is_equal_approx(p.weapon_combat.stagger_remaining,p.weapon_combat.rules.parry_stagger),kind+" staggers the original caster at full normal duration across distance")
		check(is_instance_valid(effect) and effect.deflected and effect._target==null and effect._bolts.is_empty(),kind+" parry cancels its entire active cast and target acquisition")
		var health: float=q.health
		await frames(ceili(hz*.4))
		check(q.health==health and not is_instance_valid(effect),kind+" random deflected energy expires without an active or reacquiring hitbox")
	# Ground telegraph gives time to react and respects true airborne clearance.
	reset()
	await frames(2)
	cast("ground")
	await frames(ceili(hz*.12))
	check(q.health==q.weapon_combat.max_health,"Ground pattern telegraphs before its first damage contact")
	q.position.y=3
	await frames(ceili(hz*.7))
	check(q.health==q.weapon_combat.max_health,"Jumping above the ground cast avoids its low laser field")
	# Dodge immunity remains owned by the existing phase system.
	reset()
	q.dodge.start(Vector3.RIGHT)
	q.dodge.elapsed=q.dodge.DURATION*.43
	await frames(2)
	cast("volley")
	await frames(ceili(hz*.5))
	check(q.weapon_combat.last_evaded and q.health==q.weapon_combat.max_health,"Real phase invulnerability evades all incoming volley bolts")
	reset()
	q.combat.blocking=true
	q.weapon_combat.parry_remaining=0
	await frames(2)
	cast("slither")
	await frames(ceili(hz*.6))
	check(q.weapon_combat.last_blocked and not q.weapon_combat.last_parried and is_equal_approx(q.weapon_combat.max_health-q.health,30*(1-q.weapon_combat.guard_strength())),"An expired parry window applies ordinary guard mitigation instead of remote caster stagger")
	check(not p.weapon_combat.is_staggered(),"A normal blocked wand hit does not become a successful parry")
	# Old patterns have their own contact set after a fresh move resets the
	# melee resolver's pulse table; overlapping casts remain independent.
	reset()
	await frames(2)
	cast("ground")
	await frames(ceili(hz*.35))
	p.weapon_combat._pulse_targets.clear()
	cast("ground")
	await frames(ceili(hz*.6))
	check(is_equal_approx(q.weapon_combat.max_health-q.health,60),"Overlapping ground casts retain independent one-hit caches across later attacks")
	# Homing uses one launch acquisition; moving behind cannot create an orbit.
	reset()
	q.position.x=.9
	await frames(2)
	var homing:=cast("slither",null)
	check(homing._target!=null,"Free Slither Shot acquires an eligible target inside its limited forward cone")
	await frames(ceili(hz*.18))
	q.position=Vector3(0,.02,-4)
	await frames(ceili(hz*.22))
	check(not is_instance_valid(homing),"Slither Shot expires after its target passes behind and cannot circle for another attack")
	reset()
	q.position=Vector3(8,.02,0)
	await frames(2)
	homing=cast("slither",null)
	check(homing._target==null,"Slither Shot cannot acquire a target outside its initial forward cone")
	await frames(ceili(hz*.9))
	check(not is_instance_valid(homing),"An unacquired Slither Shot expires after one outbound miss")
	# Swept collision rejects architecture before any target behind it.
	reset()
	var wall:=StaticBody3D.new()
	var wall_shape:=CollisionShape3D.new()
	var slab:=BoxShape3D.new()
	slab.size=Vector3(10,5,.3)
	wall_shape.shape=slab
	wall.add_child(wall_shape)
	wall.position=Vector3(0,2,3)
	arena.add_child(wall)
	await frames(2)
	for kind in ["flick","slither","volley","ground","wheel"]:
		cast(kind)
	await frames(hz)
	check(q.health==q.weapon_combat.max_health,"Opaque architecture blocks every wand attack before the hidden opponent")
	wall.queue_free()
	reset()
	await frames(2)
	for i in range(40): cast("volley")
	check(get_nodes_in_group("wand_effects").size()==Wand.MAX_CASTS,"Global cast cap deterministically evicts old laser casts")
	await frames(hz*2)
	check(get_nodes_in_group("wand_effects").is_empty(),"All wand projectile nodes and laser geometry expire after finite lifetimes")
	reset()
	var retiring_cast:=cast("ground")
	p.queue_free()
	check(not retiring_cast._valid_caster(),"A queued officer or replaced caster invalidates its effects before deferred deletion")
	await frames(ceili(hz*.4))
	check(not is_instance_valid(retiring_cast) and q.health==q.weapon_combat.max_health,"A checkpoint-retired caster cannot leave an active damaging ground pattern")
	arena.queue_free()
	await frames(2)
	print("WAND PROJECTILES ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
