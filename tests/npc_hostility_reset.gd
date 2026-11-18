extends "res://tests/assault_reactions.gd"
## Death/respawn must close the whole civilian incident, including deferred work.

func calm(entry: Dictionary) -> bool:
	return entry.anger==0 and entry.hold==0 and entry.challenge==0 and entry.away==0 and entry.speech==0 and entry.line=="" and not entry.assault and entry.last_attack==-1 and entry.taunt_stage==-1 and not is_instance_valid(entry.bubble)

func provoke(source: CharacterBody3D) -> String:
	var key: String=reactions.key_for(source)
	for i in range(3): reactions.react(source,true)
	return key

func freeze_fighter(key: String) -> CharacterBody3D:
	var fighter: CharacterBody3D=reactions.fighters[key]
	fighter.controls.stop()
	fighter.set_physics_process(false)
	fighter.weapon_combat.set_physics_process(false)
	return fighter

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.boss_encounters_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	actor=world.player
	actor.visual.retrieval.enabled=false
	await frames(5)
	reactions=world.theft_reactions
	reactions.set_physics_process(false)
	reactions.respawn_delay=.5
	world.district_life.set_physics_process(false)
	world.population.set_physics_process(false)
	for source: CharacterBody3D in world.population.active_residents.duplicate(): source.deactivate()
	for source: CharacterBody3D in world.district_life.people.values(): source.queue_free()
	world.district_life.people.clear()
	for vehicle: CharacterBody3D in world.district_life.vehicles.values(): vehicle.queue_free()
	world.district_life.vehicles.clear()
	controls=Intent.new()
	root.add_child(controls)
	actor.controls=controls
	world.camera_rig.controls=controls
	actor.set_physics_process(false)
	actor.weapon_combat.set_physics_process(false)
	actor.position=Vector3(0,.05,8)
	actor.velocity=Vector3.ZERO
	await frames(2)
	var hub: CharacterBody3D=world.population.residents[0]
	hub.activate(Vector3(-3,.05,11))
	hub.set_physics_process(false)
	var life: Node3D=world.district_life
	var profile: Dictionary=life.profile_for(9900)
	var record: Dictionary={"id":9900,"profile":profile,"point":Vector3(3,.05,11),"spawn":Vector3(5,.05,12),"route":PackedVector3Array([Vector3(3,.05,11),Vector3(5,.05,12)]),"cursor":1,"meetings":0,"checked":true,"valid":true}
	life.resident_records.append(record)
	var regional: CharacterBody3D=life.spawn_person(record)
	regional.set_physics_process(false)
	await frames(2)
	var hub_key:=provoke(hub)
	var region_key:=provoke(regional)
	check(reactions.begin_fighter(hub_key) and reactions.begin_fighter(region_key),"Hub and countryside civilians enter the real hostile combat adapter")
	var hub_fighter:=freeze_fighter(hub_key)
	var region_fighter:=freeze_fighter(region_key)
	# A lethal NPC hit resets that incident, without forgiving other aggressors.
	hub_fighter.receive_hit(5000,actor.combat_point(),actor,{"action":"special_y","parryable":false})
	await frames(2)
	check(reactions.entries[hub_key].dead and calm(reactions.entries[hub_key]),"NPC defeat clears anger, taunts, timers, deduplication and its meter")
	check(reactions.fighters.has(region_key) and reactions.entries[region_key].anger==100,"One NPC's defeat leaves the unrelated active fight intact")
	seconds(.8)
	await frames(2)
	check(hub.active and hub.health==1000 and calm(reactions.entries[hub_key]) and world.population.reserved_outdoors==0,"Hub NPC respawns calm with full health and one outdoor body")
	hub.set_physics_process(false)
	# A pending warning and stale caption must also disappear on player death.
	provoke(hub)
	reactions.entries[hub_key].assault=true
	reactions.entries[hub_key].last_attack=42
	reactions.entries[hub_key].taunt_stage=3
	hub.caption.text="stale angry reply"
	hub.speech_time=5
	region_fighter.weapon_combat.health=713
	region_fighter.weapon_combat._begin(Library.move(&"down",&"attack_right"))
	region_fighter.weapon_combat._queued={"action":&"attack_right","slot":&"down","charge":0.0}
	actor.target_lock.select(region_fighter)
	actor.combat.blocking=false
	actor.receive_combat_hit(5000,region_fighter.combat_point(),region_fighter,{"action":"attack_right","parryable":false})
	check(actor.health==1000 and actor.global_position.is_equal_approx(actor.spawn),"An actual hostile hit kills the player and completes normal respawn")
	check(reactions.fighters.is_empty() and region_fighter.weapon_combat.active_move.is_empty() and region_fighter.weapon_combat._queued.is_empty() and not region_fighter.controls.active and region_fighter.collision_layer==0,"Player death stops every hostile AI, active hitbox and queued attack immediately")
	check(calm(reactions.entries[hub_key]) and calm(reactions.entries[region_key]) and record.anger==0,"Player death clears both active fights and pending retaliation warnings")
	check(hub.caption.text=="" and hub.speech_time==0 and hub.reply_time==0,"Old angry captions and delayed replies cannot survive respawn")
	check(not actor.target_lock.is_locked() and not actor.is_in_group("combat_targets") and not actor.get_collision_layer_value(2),"Street fight target locks and player hurt registration are released")
	await frames(2)
	seconds(1)
	check(regional.visible and not record.combat and regional.health==713,"A surviving opponent resumes civilian life with its existing injury")
	regional.set_physics_process(false)
	seconds(8)
	check(reactions.fighters.is_empty() and calm(reactions.entries[hub_key]) and calm(reactions.entries[region_key]),"Expired warning timers cannot restart combat after the player's death")
	# The next provocation must be a fresh incident, rather than a stale instant fight.
	actor.position=Vector3(0,.05,8)
	regional.receive_hit(1,actor.combat_point(),actor,{"attack_serial":42,"action":"attack_right"})
	check(regional.health==712 and reactions.entries[region_key].anger>0 and reactions.entries[region_key].anger<100 and not reactions.fighters.has(region_key),"A fresh assault builds normal annoyance again, including a reused old attack serial")
	actor.respawn()
	check(calm(reactions.entries[region_key]),"Fall/out-of-world respawn also clears civilian annoyance")
	# A zero-HP fighter awaiting its deferred finish must stay dead if the
	# player's death occurs in the same frame. Do not revive it accidentally.
	actor.position=Vector3(0,.05,8)
	provoke(regional)
	check(reactions.begin_fighter(region_key),"A new incident can still escalate normally after the reset")
	region_fighter=freeze_fighter(region_key)
	region_fighter.receive_hit(5000,actor.combat_point(),actor,{"action":"special_y","parryable":false})
	actor.weapon_combat.receive_environment_damage(5000)
	check(reactions.fighters.is_empty() and reactions.entries[region_key].dead and reactions.entries[region_key].suspended and reactions.entries[region_key].respawn>0,"Same-frame deaths preserve the NPC's delayed respawn instead of restoring a zero-HP civilian")
	await frames(2)
	check(reactions.entries[region_key].dead and calm(reactions.entries[region_key]),"A late lethal callback cannot revive hostility or repeat the cleanup")
	actor.position=record.spawn
	await frames(2)
	seconds(1)
	check(not regional.visible and reactions.entries[region_key].dead and calm(reactions.entries[region_key]),"Blocked NPC respawn waits safely while remaining calm")
	actor.position=Vector3(0,.05,8)
	await frames(2)
	seconds(1)
	check(regional.visible and regional.health==1000 and not record.combat and record.anger==0 and calm(reactions.entries[region_key]),"Countryside NPC respawns with full health and a fully reset incident")
	regional.set_physics_process(false)
	# A civilian killed before escalation follows the same reset path.
	regional.receive_hit(5000,actor.combat_point(),actor,{"attack_serial":99})
	check(reactions.entries[region_key].dead and calm(reactions.entries[region_key]),"Lethal hits before retaliation also reset the civilian's behavior")
	seconds(1)
	check(regional.visible and regional.health==1000 and calm(reactions.entries[region_key]),"A peaceful civilian returns without resuming its old warning")
	# Persisted journey records outlive unloaded regional presentation nodes.
	provoke(regional)
	regional.queue_free()
	life.people.erase(9900)
	await frames(2)
	actor.respawn()
	check(record.anger==0 and calm(reactions.entries[region_key]),"Player respawn clears unloaded regional identities as well as visible NPCs")
	regional=life.spawn_person(record)
	check(regional!=null and not reactions.is_annoyed(regional),"Rematerializing a regional identity does not restore stale anger")
	world.queue_free()
	controls.queue_free()
	await process_frame
	print("NPC hostility reset: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
