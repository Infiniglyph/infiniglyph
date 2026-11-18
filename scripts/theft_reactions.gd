extends Node3D
## Personal theft/assault anger feeds the existing civilian combat adapter.
const Fighter = preload("res://scripts/resident_fighter.gd")
const Combat = preload("res://scripts/weapon_combat.gd")
const DamageNumber = preload("res://scripts/damage_number.gd")
const ASSAULT_LINES := [
	["Watch your damn hands.","I'm not your training dummy, human.","Was that supposed to impress me?","Back off. You're getting on my nerves."],
	["Keep swinging, genius. See where it gets you.","You really are a pain in the ass.","All that empty space in your skull, and you still chose this.","Cut that shit out, human."],
	["Last warning. Swing again and you're going down.","You're one bad decision from the pavement.","I've had about enough of your shit.","Keep pushing. I dare you."],
	["That's it. You wanted a fight? You've got one.","Enough. I'm putting you on the pavement.","Now you've pissed me off.","All right, human. Let's see you back that up."]
]
const WITNESS_LINES := [
	"Humans. Always taking what someone else built.",
	"Not your world. Not your ride, human.",
	"A human thief. There's a surprise.",
	"You visitors really think everything here belongs to you."
]
const OWNER_LINES := [
	"Get out of my vehicle, human parasite!",
	"Can't build a thing, so you steal ours. Typical human.",
	"I made room for you, human. This is how you repay it?",
	"Give it back, human. We aren't props in your little visit."
]
var actor: CharacterBody3D
var life: Node3D
var population: Node3D
var entries: Dictionary = {}
var fighters: Dictionary = {}
@export_range(1,200,1) var enrage_threshold := 100.0
@export_range(0,20,0.5) var anger_recovery := 5.0
@export_range(0.5,60,0.5) var respawn_delay := 6.0
@export var retaliation_enabled := true
@export_range(0.05,0.5,0.01) var assault_anger_scale := 0.22
var _owns_player_target := false
var _clock := 0.0

func _ready() -> void:
	name = "TheftReactions"
	if is_instance_valid(life): life.reactions = self
	if is_instance_valid(population): population.reactions = self
	actor.defeated.connect(reset_hostility)
	actor.respawned.connect(reset_hostility)

func _clear_anger(entry: Dictionary) -> void:
	var provoked: bool = entry.anger>0 or entry.assault or not String(entry.line).is_empty()
	entry.anger = 0.0
	entry.hold = 0.0
	entry.challenge = 0.0
	entry.away = 0.0
	entry.speech = 0.0
	entry.line = ""
	entry.assault = false
	entry.last_attack = -1
	entry.taunt_stage = -1
	if is_instance_valid(entry.bubble):
		entry.bubble.hide()
		entry.bubble.queue_free()
	entry.bubble = null
	var source: CharacterBody3D = entry.source.get_ref()
	if not is_instance_valid(source): return
	if entry.regional: source.record.anger = 0.0
	if not provoked: return
	source.caption.text = ""
	source.caption.hide()
	source.wait = 0.0
	if entry.regional:
		source.record.wait = 0.0
		source.state = "walking the neighborhood"
	else:
		source.speech_time = 0.0
		source.reply_time = 0.0
		source.reply = ""
		source.state = "walking" if source.active else "indoors"

func reset_hostility() -> void:
	# Run synchronously at death, before health is restored at respawn. No live
	# attacker or delayed warning may follow the player into the next life.
	for key: String in fighters.keys(): finish_fighter(key)
	for entry: Dictionary in entries.values(): _clear_anger(entry)
	# Regional identities can be unloaded while their journey records survive.
	if is_instance_valid(life):
		for record: Dictionary in life.resident_records: record.anger = 0.0
	_sync_player()

func bind_source(source: CharacterBody3D) -> void:
	var key := key_for(source)
	if entries.has(key): entries[key].source = weakref(source)

func civilian_health(source: CharacterBody3D) -> float:
	var entry: Dictionary = entries.get(key_for(source),{})
	return float(entry.get("health",Combat.BASE_HEALTH))

func is_annoyed(source: CharacterBody3D) -> bool:
	return float(entries.get(key_for(source),{}).get("anger",0))>0

func answer_annoyed(source: CharacterBody3D) -> String:
	var key := key_for(source)
	var entry := _entry_for(source)
	entry.speech = 5.5
	source.caption.text = entry.line
	source.wait = 2.5
	_update_bubble(key,entry)
	return source.profile.name+": "+entry.line

func _entry_for(source: CharacterBody3D) -> Dictionary:
	var key := key_for(source)
	if not entries.has(key):
		var spawn_point: Vector3 = source.record.get("spawn",source.record.route[0]) if source.get("record") is Dictionary else source.population.points.get(source.profile.home,source.global_position)
		entries[key] = {"source":weakref(source),"regional":source.get("record") is Dictionary,"spawn":spawn_point,"anger":0.0,"health":Combat.BASE_HEALTH,"hold":0.0,"speech":0.0,"line":"","bubble":null,"respawn":0.0,"dead":false,"suspended":false,"away":0.0,"challenge":0.0,"assault":false,"last_attack":-1,"taunt_stage":-1}
	entries[key].source = weakref(source)
	return entries[key]

func _theft_gain(source: CharacterBody3D, key: String, owner: bool) -> float:
	var temperament: float = {"dismissive":70,"pragmatic":50,"indifferent":45,"curious":30,"friendly":20}.get(source.profile.attitude,45)
	return temperament+(25 if owner else 0)+absi(key.hash())%35

func _raise_anger(entry: Dictionary, gain: float) -> void:
	var before: float = entry.anger
	entry.anger = minf(enrage_threshold,before+gain)
	if before<enrage_threshold and entry.anger>=enrage_threshold: entry.challenge = .8
	entry.hold = 6

func receive_assault(source: CharacterBody3D, amount: float, origin: Vector3, attacker: Node, incoming: Dictionary = {}) -> float:
	if attacker!=actor or not can_fight() or not is_finite(amount) or amount<=0: return 0
	if not source.is_visible_in_tree() or source.virtualized or source.collision_layer==0: return 0
	var key := key_for(source)
	var entry := _entry_for(source)
	if entry.dead or entry.suspended or fighters.has(key): return 0
	var applied := minf(amount,float(entry.health))
	entry.health -= applied
	var serial := int(incoming.get("attack_serial",-1))
	if serial<0 or serial!=int(entry.last_attack):
		entry.last_attack = serial
		entry.assault = true
		_raise_anger(entry,_theft_gain(source,key,true)*assault_anger_scale)
		var ratio: float = entry.anger/enrage_threshold
		var stage := 3 if ratio>=1 else 2 if ratio>=.7 else 1 if ratio>=.34 else 0
		if stage!=entry.taunt_stage or entry.speech<3:
			entry.taunt_stage = stage
			var lines: Array = ASSAULT_LINES[stage]
			entry.line = lines[absi(key.hash()+serial+stage)%lines.size()]
			entry.speech = 5.5
	if not is_instance_valid(entry.bubble): entry.bubble = make_bubble()
	source.caption.hide()
	source.wait = 2.5
	source.state = "furious" if entry.anger>=enrage_threshold else "annoyed"
	var facing := actor.global_position-source.global_position
	if Vector2(facing.x,facing.z).length()>.05: source.visual.rotation.y = atan2(facing.x,facing.z)
	if entry.regional: source.record.anger = entry.anger
	var contact: Vector3 = incoming.get("contact",source.global_position+Vector3.UP*.95)
	actor.weapon_combat.feedback.confirm("heavy" if float(incoming.get("hit_stun_level",0))>=1.5 else "hit",contact,contact-origin,actor,source,true,int(incoming.get("hurtbox_shape",-1)))
	DamageNumber.make_room(get_tree())
	var number := DamageNumber.new()
	number.text = "%.1f" % applied
	add_child(number)
	number.global_position = source.global_position+Vector3.UP*1.5
	if entry.health<=0:
		_suspend_source(entry,source)
		entry.dead = true
		entry.respawn = respawn_delay
		_clear_anger(entry)
	_update_bubble(key,entry)
	return applied

func can_fight() -> bool:
	if is_instance_valid(actor.kyren_encounter) and (actor.kyren_encounter.active or actor.kyren_encounter.dialogue_open): return false
	if actor.health<=0: return false
	if is_instance_valid(actor.sparring_duel) and (actor.sparring_duel.active or actor.sparring_duel.dialogue_open): return false
	if is_instance_valid(actor.boss_encounter) and (actor.boss_encounter.active or actor.boss_encounter.dialogue_open): return false
	return true

func key_for(source: CharacterBody3D) -> String:
	return "region/"+str(source.record.id) if source.get("record") is Dictionary else "hub/"+str(source.profile.id)

func make_bubble() -> Label3D:
	var bubble := Label3D.new()
	bubble.font_size = 32
	bubble.pixel_size = 0.005
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.modulate = Color(1,0.48,0.27)
	bubble.outline_size = 7
	bubble.width = 430
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.hide()
	add_child(bubble)
	return bubble

func observe_theft(vehicle: CharacterBody3D, owner: CharacterBody3D = null) -> void:
	if not is_instance_valid(life): return
	var witnesses: Array[CharacterBody3D] = []
	if is_instance_valid(owner): witnesses.append(owner)
	for source: CharacterBody3D in life.people.values():
		if source!=owner and source.is_visible_in_tree(): witnesses.append(source)
	if is_instance_valid(population):
		for source: CharacterBody3D in population.active_residents: witnesses.append(source)
	witnesses.sort_custom(func(a: CharacterBody3D,b: CharacterBody3D): return a.global_position.distance_squared_to(vehicle.global_position)<b.global_position.distance_squared_to(vehicle.global_position))
	var count := 0
	for source: CharacterBody3D in witnesses:
		if count>=6: break
		if source.global_position.distance_to(vehicle.global_position)>18: continue
		var ray := PhysicsRayQueryParameters3D.create(source.global_position+Vector3.UP*1.35,vehicle.global_position+Vector3.UP,9,[source.get_rid(),vehicle.get_rid(),actor.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		react(source,source==owner,0 if source==owner else 1+count%2)
		if source==owner or count==0:
			var key := key_for(source)
			life.session.show_notice(source.profile.name+": "+entries[key].line,5.5)
		count += 1

func react(source: CharacterBody3D, owner: bool, tier: int = 0) -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree(): return
	var key := key_for(source)
	var entry := _entry_for(source)
	if entry.dead: return
	if not is_instance_valid(entry.bubble): entry.bubble = make_bubble()
	source.caption.text = ""
	entry.source = weakref(source)
	entry.tier = tier
	_raise_anger(entry,_theft_gain(source,key,owner))
	entry.speech = 5.5
	var lines: Array = OWNER_LINES if owner else WITNESS_LINES
	entry.line = lines[absi(key.hash()+int(entry.anger))%lines.size()]
	if entry.regional:
		source.record["anger"] = entry.anger
		source.wait = 2.5
	else: source.wait = 2.5

func begin_fighter(key: String) -> bool:
	if not retaliation_enabled or not can_fight() or fighters.has(key) or not entries.has(key): return false
	var entry: Dictionary = entries[key]
	var source: CharacterBody3D = entry.source.get_ref()
	if entry.dead or not is_instance_valid(source) or not source.is_visible_in_tree() or entry.anger<enrage_threshold: return false
	if source.global_position.distance_to(actor.global_position)>24: return false
	# A fast approach may precede the neighborhood's next scheduling tick.
	# Materialize safely before replacing a civilian with a combat body.
	if source.get("virtualized")==true and not source.set_virtualized(false): return false
	var at := source.global_position
	var yaw: float = source.visual.rotation.y
	_suspend_source(entry,source)
	var fighter := Fighter.new()
	fighter.identity = key
	fighter.profile = source.profile.duplicate(true)
	fighter.opponent = actor
	fighter.reactions = self
	fighter.spawn = at
	fighter.position = at
	add_child(fighter)
	fighter.weapon_combat.health = entry.health
	fighter.visual.rotation.y = yaw
	fighters[key] = fighter
	_sync_player()
	return true

func _suspend_source(entry: Dictionary, source: CharacterBody3D) -> void:
	if entry.regional:
		source.record.combat = true
		source.set_physics_process(false)
		source.hide()
		source.collision_layer = 0
		source.collision_mask = 0
	else:
		source.population.active_residents.erase(source)
		source.population.reserved_outdoors += 1
		source.deactivate()
		source.indoor_left = INF
	entry.suspended = true

func _sync_player() -> void:
	var needed := not fighters.is_empty() and can_fight()
	var protected: bool = not can_fight() and actor.health>0
	if needed:
		if not actor.is_in_group("combat_targets"): _owns_player_target = true
		actor.add_to_group("combat_targets")
		actor.set_collision_layer_value(2,true)
	elif _owns_player_target and not protected:
		actor.remove_from_group("combat_targets")
		actor.set_collision_layer_value(2,false)
		_owns_player_target = false
	if is_instance_valid(actor.world_actions) and actor.world_actions.attached() and not protected:
		actor.world_actions._layer = (actor.world_actions._layer|2) if needed else (actor.world_actions._layer&~2)

func finish_fighter(key: String, defeated: bool = false, expected: Node = null) -> void:
	if not fighters.has(key): return
	var fighter: CharacterBody3D = fighters[key]
	if expected!=null and fighter!=expected: return
	# A player death and an NPC's deferred lethal callback may share a frame.
	# Preserve the NPC's death instead of restoring a zero-HP hostile civilian.
	defeated = defeated or fighter.dead or fighter.health<=0
	var entry: Dictionary = entries[key]
	if actor.target_lock.opponent==fighter: actor.target_lock.clear()
	entry.last_position = fighter.global_position
	entry.health = fighter.health
	fighters.erase(key)
	fighter.controls.stop()
	fighter.weapon_combat.cancel()
	fighter.set_physics_process(false)
	fighter.weapon_combat.set_physics_process(false)
	fighter.remove_from_group("combat_targets")
	fighter.collision_layer = 0
	fighter.hide()
	fighter.queue_free()
	if defeated: _clear_anger(entry)
	else: entry.anger = 30.0
	entry.dead = defeated
	entry.respawn = respawn_delay if defeated else 0.0
	entry.speech = 0
	if not defeated: restore_source(entry,false)
	_sync_player()

func restore_source(entry: Dictionary, at_spawn: bool) -> bool:
	var source: CharacterBody3D = entry.source.get_ref()
	if not is_instance_valid(source): return false
	var at: Vector3 = entry.spawn if at_spawn else entry.get("last_position",entry.spawn)
	# Delay reconstitution if another body/structure occupies the spawn.
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.85
	capsule.radius = 0.28
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY,at+Vector3.UP*1.02)
	query.collision_mask = 13
	query.exclude = [source.get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	if entry.regional:
		source.record.combat = false
		source.record.anger = entry.anger
		source.record.point = at
		source.global_position = at
		source.velocity = Vector3.ZERO
		if not source.set_virtualized(false):
			source.record.combat = true
			return false
		source.wait = 2
		source.collision_layer = 4
		source.collision_mask = 13
		source.show()
		source.set_physics_process(true)
	else:
		source.population.reserved_outdoors = maxi(0,source.population.reserved_outdoors-1)
		source.indoor_left = 15
		source.activate(at)
		source.wait = 2
	entry.suspended = false
	entry.dead = false
	if at_spawn: entry.health = Combat.BASE_HEALTH
	return true

func _physics_process(delta: float) -> void:
	_sync_player()
	_clock += delta
	if _clock<0.2: return
	var elapsed := _clock
	_clock = 0
	for key: String in entries:
		var entry: Dictionary = entries[key]
		var source: CharacterBody3D = entry.source.get_ref()
		entry.speech = maxf(0,entry.speech-elapsed)
		entry.hold = maxf(0,entry.hold-elapsed)
		entry.challenge = maxf(0,entry.challenge-elapsed)
		if fighters.has(key):
			var fighter: CharacterBody3D = fighters[key]
			entry.away = entry.away+elapsed if fighter.global_position.distance_to(actor.global_position)>50 else 0.0
			if not can_fight() or entry.away>5: finish_fighter(key)
		elif entry.suspended:
			entry.respawn = maxf(0,entry.respawn-elapsed)
			if entry.respawn==0: restore_source(entry,entry.dead)
		elif entry.hold==0: entry.anger = maxf(0,entry.anger-anger_recovery*elapsed)
		elif entry.anger>=enrage_threshold and entry.challenge==0: begin_fighter(key)
		if is_instance_valid(source) and entry.regional: source.record.anger = entry.anger
		_update_bubble(key,entry)

func _update_bubble(key: String, entry: Dictionary) -> void:
	var source: Node3D = entry.source.get_ref()
	var focus: Node3D = fighters.get(key,source)
	if entry.speech==0 and entry.anger<=0 and is_instance_valid(entry.bubble):
		entry.bubble.queue_free()
		entry.bubble = null
	if not is_instance_valid(entry.bubble): return
	entry.bubble.visible = is_instance_valid(focus) and focus.is_visible_in_tree() and focus.global_position.distance_to(actor.global_position)<24
	if entry.bubble.visible:
		entry.bubble.global_position = focus.global_position+Vector3.UP*(2.9+0.65*entry.get("tier",0))
		var ratio := clampf(float(entry.anger)/enrage_threshold,0,1)
		var filled := ceili(ratio*8)
		var stage := "HOSTILE" if fighters.has(key) or ratio>=1 else "FURIOUS" if ratio>=.7 else "IRRITATED" if ratio>=.34 else "ANNOYED"
		var speech: String = entry.line+"\n" if entry.speech>0 else ""
		entry.bubble.text = speech+(stage if entry.assault else "ANGER")+" ["+"|".repeat(filled)+"-".repeat(8-filled)+"] %d%%" % int(ratio*100)
		entry.bubble.modulate = Color(1,.75,.3).lerp(Color(1,.2,.12),ratio)
		if is_instance_valid(source) and entry.speech>0: source.caption.hide()
