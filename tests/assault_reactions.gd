extends SceneTree
## Real hit volumes -> measured annoyance -> the shared resident fighter.
const Catalog = preload("res://scripts/item_catalog.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Neon = preload("res://scripts/neon.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var actor: CharacterBody3D
var reactions: Node3D
var controls: Intent
var view: Camera3D
var hz := 60
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func seconds(time: float) -> void:
	for i in range(ceili(time/.2)): reactions._physics_process(.2)

func hit(source: CharacterBody3D) -> void:
	var combat: Node = actor.weapon_combat
	combat.cancel()
	combat.clear_stagger()
	combat._begin(combat.move_for(actor.combat.selected_slot,&"attack_right"))
	combat._facing = (source.global_position-actor.global_position).normalized()
	combat.elapsed = float(combat.active_move.hits[0])
	combat.strike(0)
	combat.cancel()

func shot(label: String, source: Node3D) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	view.global_position = source.global_position+Vector3(2.2,2.6,4.6)
	view.look_at(source.global_position+Vector3.UP*1.9)
	view.current = true
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/assault_"+label+".png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	await frames(10)
	reactions = world.theft_reactions
	reactions.set_physics_process(false)
	world.district_life.set_physics_process(false)
	world.population.set_physics_process(false)
	for source: CharacterBody3D in world.population.active_residents.duplicate(): source.deactivate()
	for source: CharacterBody3D in world.district_life.people.values(): source.queue_free()
	world.district_life.people.clear()
	for vehicle: CharacterBody3D in world.district_life.vehicles.values(): vehicle.queue_free()
	world.district_life.vehicles.clear()
	controls = Intent.new()
	root.add_child(controls)
	actor.controls = controls
	actor.set_physics_process(false)
	actor.weapon_combat.set_physics_process(false)
	actor.position = Vector3(0,.05,8)
	actor.velocity = Vector3.ZERO
	actor.combat.selected_slot = &"down"
	actor.combat.sheathed = false
	actor.weapon_combat.sync_rig()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	view = Camera3D.new()
	view.fov = 48
	world.add_child(view)
	var source: CharacterBody3D = world.population.residents[0]
	source.activate(Vector3(0,.05,9.6))
	source.set_physics_process(false)
	source.profile.attitude = "friendly"
	await frames(3)
	check(source.collision_layer==4 and not source.is_in_group("combat_targets"),"Calm residents retain their lightweight physical/scheduling contract")
	var wall := Neon.block(world,Vector3(0,1.1,9.25),Vector3(1,3,.15))
	await frames()
	hit(source)
	var key: String = reactions.key_for(source)
	check(not reactions.entries.has(key) and source.health==1000,"Architecture blocks attacks and cannot provoke citizens through a wall")
	wall.queue_free()
	await frames()
	hit(source)
	check(reactions.entries.has(key) and source.health<1000 and actor.weapon_combat.total_hits>0,"An actual weapon query damages a calm civilian and creates personal annoyance")
	if not reactions.entries.has(key):
		world.queue_free()
		quit(1)
		return
	var entry: Dictionary = reactions.entries[key]
	var anger: float = entry.anger
	var hp: float = source.health
	check(anger>0 and anger<reactions.enrage_threshold*.3 and reactions.fighters.is_empty(),"One attack builds annoyance without immediately starting a fight")
	check(entry.bubble.visible and entry.bubble.text.contains("ANNOYED [") and not entry.line.is_empty(),"The victim answers with trash talk and a visible filling annoyance meter")
	var reply: String = source.talk()
	check(reply.contains(entry.line) and source.caption.text==entry.line and entry.anger==anger,"Talking to an annoyed resident returns its taunt without resetting anger")
	await shot("annoyed",source)
	source.receive_combat_hit(5,actor.combat_point(),actor,{"attack_serial":actor.weapon_combat.attack_serial})
	check(is_equal_approx(source.health,hp-5) and entry.anger==anger,"Extra pulses from one attack deal damage without multiplying its anger gain")
	reactions.react(source,true)
	check(is_equal_approx(entry.anger-anger,anger/reactions.assault_anger_scale),"Attacking builds anger at 22 percent of the same resident's car-theft gain")
	entry.anger = anger
	entry.hold = 6
	entry.assault = true
	seconds(5.6)
	check(entry.speech==0 and entry.bubble.visible and not entry.bubble.text.contains("\n"),"The meter stays readable after the spoken taunt expires")
	seconds(7)
	await frames()
	check(entry.anger==0 and not is_instance_valid(entry.bubble) and reactions.fighters.is_empty(),"Leaving the NPC alone lets annoyance decay and removes the meter")
	var stages: Dictionary = {}
	var blows := 0
	while entry.anger<reactions.enrage_threshold and blows<20:
		hit(source)
		blows += 1
		stages[entry.taunt_stage] = true
		if entry.taunt_stage==1 and stages.size()==2: await shot("irritated",source)
		if entry.taunt_stage==2 and stages.size()==3: await shot("furious",source)
	check(blows>=4 and stages.size()==4 and entry.anger==100 and not reactions.fighters.has(key),"Several fresh attacks escalate through distinct taunts to a final warning")
	await shot("warning",source)
	for i in range(5):
		if reactions.fighters.has(key): break
		hit(source)
		reactions._physics_process(.2)
	check(reactions.fighters.has(key),"Continuous attacks cannot keep resetting the retaliation warning")
	if not reactions.fighters.has(key):
		world.queue_free()
		quit(1)
		return
	var fighter: CharacterBody3D = reactions.fighters[key]
	fighter.controls.stop()
	check(fighter.health==entry.health and fighter.health<1000 and fighter.health>0,"Civilian injuries carry into combat without healing on transformation")
	check(not source.active and world.population.reserved_outdoors==1 and actor.get_collision_layer_value(2),"Retaliation uses one existing fighter and reserves the civilian's outdoor slot")
	await shot("retaliation",fighter)
	fighter.weapon_combat.clear_stagger()
	actor.weapon_combat.clear_stagger()
	actor.weapon_combat.health = 1000
	actor.set_physics_process(true)
	actor.weapon_combat.set_physics_process(true)
	fighter.controls.start()
	await frames(hz*3)
	check(actor.health<1000 and fighter.controls.decisions>0,"The provoked NPC genuinely attacks and damages the player through shared combat")
	actor.set_physics_process(false)
	actor.weapon_combat.set_physics_process(false)
	actor.position = Vector3(0,.05,5)
	reactions.finish_fighter(key)
	await frames()
	check(source.active and not reactions.fighters.has(key) and world.population.reserved_outdoors==0,"Disengagement restores the same resident without duplicating the street population")
	entry.anger = 0
	source.deactivate()
	actor.weapon_combat.clear_stagger()
	actor.weapon_combat.health = 1000
	actor.position = Vector3(0,.05,8)
	var life: Node3D = world.district_life
	var profile: Dictionary = life.profile_for(9800)
	var record := {"id":9800,"profile":profile,"point":Vector3(0,.05,9.6),"spawn":Vector3(5,.05,12),"route":PackedVector3Array([Vector3(0,.05,9.6),Vector3(5,.05,12)]),"cursor":1,"meetings":0,"checked":true,"valid":true}
	life.resident_records.append(record)
	var regional: CharacterBody3D = life.spawn_person(record)
	regional.set_physics_process(false)
	await frames()
	world.sparring_duel.active = true
	check(regional.receive_hit(50,actor.combat_point(),actor)==0 and regional.health==1000,"Protected sparring encounters cannot provoke or damage outside civilians")
	world.sparring_duel.active = false
	check(regional.receive_hit(50,actor.combat_point(),source)==0,"Non-player contacts do not forge player assault events")
	hit(regional)
	var regional_key: String = reactions.key_for(regional)
	check(reactions.entries.has(regional_key) and regional.health<1000 and record.anger>0,"Neighborhood and countryside residents use the same damage and annoyance path")
	var regional_health: float = regional.health
	regional.queue_free()
	life.people.erase(9800)
	await frames()
	regional = life.spawn_person(record)
	regional.set_physics_process(false)
	await frames()
	check(regional.health==regional_health and reactions.entries[regional_key].source.get_ref()==regional,"Rematerializing a regional NPC preserves its injury, anger and identity binding")
	reactions.respawn_delay = .5
	regional.receive_hit(5000,actor.combat_point(),actor)
	check(reactions.entries[regional_key].dead and not regional.visible and record.combat,"A lethal civilian hit schedules the existing respawn flow even before retaliation")
	actor.position = record.spawn
	await frames()
	seconds(1)
	check(not regional.visible,"Occupied NPC respawn points remain blocked")
	actor.position = Vector3(0,.05,8)
	await frames()
	seconds(1)
	check(regional.visible and regional.health==1000 and not record.combat and record.anger==0,"Respawn restores the same regional identity at full health with anger cleared")
	regional.set_physics_process(false)
	var manuscript: Resource = Catalog.create(&"eturnull_manuscript")
	check(actor.inventory.add_item(manuscript) and actor.inventory.assign(&"down",manuscript.instance_id),"Equip the Eturnull Manuscript through normal ownership")
	actor.weapon_combat.sync_rig()
	regional.position = actor.position+Vector3.BACK*6.9
	await frames()
	hit(regional)
	check(regional.health<1000 and reactions.entries[regional_key].anger>0,"Real Scribe equation contacts damage and annoy peaceful regional NPCs")
	regional_health = regional.health
	var regional_anger: float = reactions.entries[regional_key].anger
	regional.position = actor.position+Vector3(2,0,1)
	await frames()
	# Keep aim fixed: being inside seven metres alone is not a written hit.
	var move := Library.move(&"eturnull_manuscript",&"attack_right")
	actor.weapon_combat._begin(move)
	actor.weapon_combat._facing = Vector3.BACK
	actor.weapon_combat.elapsed = float(move.hits[0])
	actor.weapon_combat.strike(0)
	actor.weapon_combat.cancel()
	check(regional.health==regional_health and reactions.entries[regional_key].anger==regional_anger,"A Scribe whiff near a civilian adds neither damage nor annoyance")
	regional.position = actor.position+Vector3.BACK*6.9
	wall = Neon.block(world,actor.position+Vector3(0,1,3),Vector3(3,3,.15))
	await frames()
	hit(regional)
	check(regional.health==regional_health and reactions.entries[regional_key].anger==regional_anger,"Walls also prevent mathematical strokes from provoking citizens")
	world.queue_free()
	await frames()
	print("Assault reactions: %d checks, %d failures at %d Hz" % [checks,failures,hz])
	quit(1 if failures else 0)
