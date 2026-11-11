extends Node3D
## Observed theft -> personal anger -> existing combat, never a global crime AI.
const Fighter = preload("res://scripts/resident_fighter.gd")
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
@export_range(0,4,1) var max_fighters := 3
var _owns_player_target := false
var _clock := 0.0

func _ready() -> void:
	name = "TheftReactions"
	life.reactions = self

func can_fight() -> bool:
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
	if not entries.has(key):
		var spawn_point: Vector3 = source.record.get("spawn",source.record.route[0]) if source.get("record") is Dictionary else source.population.points.get(source.profile.home,source.global_position)
		entries[key] = {"source":weakref(source),"regional":source.get("record") is Dictionary,"spawn":spawn_point,"anger":0.0,"hold":0.0,"speech":0.0,"line":"","bubble":null,"respawn":0.0,"dead":false,"suspended":false,"away":0.0}
	var entry: Dictionary = entries[key]
	if entry.dead: return
	if not is_instance_valid(entry.bubble): entry.bubble = make_bubble()
	source.caption.text = ""
	entry.source = weakref(source)
	entry.tier = tier
	var temperament: float = {"dismissive":70,"pragmatic":50,"indifferent":45,"curious":30,"friendly":20}.get(source.profile.attitude,45)
	entry.anger = minf(enrage_threshold,entry.anger+temperament+(25 if owner else 0)+absi(key.hash())%35)
	entry.hold = 6
	entry.speech = 5.5
	var lines: Array = OWNER_LINES if owner else WITNESS_LINES
	entry.line = lines[absi(key.hash()+int(entry.anger))%lines.size()]
	if entry.regional:
		source.record["anger"] = entry.anger
		source.wait = 2.5
	else: source.wait = 2.5

func begin_fighter(key: String) -> bool:
	if not can_fight() or fighters.size()>=max_fighters or fighters.has(key) or not entries.has(key): return false
	var entry: Dictionary = entries[key]
	var source: CharacterBody3D = entry.source.get_ref()
	if entry.dead or not is_instance_valid(source) or not source.is_visible_in_tree() or entry.anger<enrage_threshold: return false
	if source.global_position.distance_to(actor.global_position)>24: return false
	# A fast approach may precede the neighborhood's next scheduling tick.
	# Materialize safely before replacing a civilian with a combat body.
	if source.get("virtualized")==true and not source.set_virtualized(false): return false
	var at := source.global_position
	var yaw: float = source.visual.rotation.y
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
		source.indoor_left = INF # The lobby scheduler must not duplicate a fighter.
	entry.suspended = true
	var fighter := Fighter.new()
	fighter.identity = key
	fighter.profile = source.profile.duplicate(true)
	fighter.opponent = actor
	fighter.reactions = self
	fighter.spawn = at
	fighter.position = at
	add_child(fighter)
	fighter.visual.rotation.y = yaw
	fighters[key] = fighter
	_sync_player()
	return true

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

func finish_fighter(key: String, defeated: bool = false) -> void:
	if not fighters.has(key): return
	var fighter: CharacterBody3D = fighters[key]
	var entry: Dictionary = entries[key]
	if actor.target_lock.opponent==fighter: actor.target_lock.clear()
	entry.last_position = fighter.global_position
	fighters.erase(key)
	fighter.controls.stop()
	fighter.weapon_combat.cancel()
	fighter.set_physics_process(false)
	fighter.weapon_combat.set_physics_process(false)
	fighter.remove_from_group("combat_targets")
	fighter.collision_layer = 0
	fighter.hide()
	fighter.queue_free()
	entry.anger = 0.0 if defeated else 30.0
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
		if fighters.has(key):
			var fighter: CharacterBody3D = fighters[key]
			entry.away = entry.away+elapsed if fighter.global_position.distance_to(actor.global_position)>50 else 0.0
			if not can_fight() or entry.away>5: finish_fighter(key)
		elif entry.suspended:
			entry.respawn = maxf(0,entry.respawn-elapsed)
			if entry.respawn==0: restore_source(entry,entry.dead)
		elif entry.hold==0: entry.anger = maxf(0,entry.anger-anger_recovery*elapsed)
		elif entry.anger>=enrage_threshold and entry.speech<4.7: begin_fighter(key)
		var focus: Node3D = fighters.get(key,source)
		if entry.speech==0 and is_instance_valid(entry.bubble):
			entry.bubble.queue_free()
			entry.bubble = null
		if not is_instance_valid(entry.bubble): continue
		entry.bubble.visible = is_instance_valid(focus) and focus.global_position.distance_to(actor.global_position)<24
		if entry.bubble.visible:
			entry.bubble.global_position = focus.global_position+Vector3.UP*(2.9+0.65*entry.get("tier",0))
			entry.bubble.text = entry.line+"\nANGER %d%%" % int(entry.anger/enrage_threshold*100)
