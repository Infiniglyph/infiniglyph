extends Node
## Timed weapon moves and coordinated whole-body visual poses. Locomotion
## velocity and the collision capsule remain owned by the player controller.
const Library = preload("res://scripts/weapon_library.gd")
const Rig = preload("res://scripts/weapon_rig.gd")
const Effect = preload("res://scripts/combat_effect.gd")
const Trail = preload("res://scripts/blade_trail.gd")
const Body = preload("res://scripts/combat_body.gd")
const Rules = preload("res://scripts/combat_rules.gd")
const Feedback = preload("res://scripts/impact_feedback.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
const PARRY_WINDOW := 0.18
const PARRY_FEEDBACK_TIME := 0.60
const BASE_HEALTH := 1000.0
const RECOIL_RECOVERY := 0.12
## 50% extra damage at the established 10.2 m/s sprint. No aerial speed cap.
@export var momentum_damage_gain := 0.5/10.2
@export var rules: Resource = Rules.new()
signal changed
signal hit_landed(target: Node, amount: float, move_name: String)
signal parried(source: Vector3)
var actor: CharacterBody3D
var rig: Node3D
var trail: MeshInstance3D
var body := Body.new()
var max_health := BASE_HEALTH
var health := BASE_HEALTH
var stagger_remaining := 0.0
var forced_state := &""
var forced_duration := 0.0
var psi_meter := 0.0
var _psi_delay := 0.0
var hitstop_remaining := 0.0
var _freeze_armed := false
var feedback: Node3D
var last_outcome := &"invalid"
var _reaction_duration := 0.0
var _reaction_scale := 1.0
var _kneel_remaining := 0.0
var _kneel_duration := 0.0
var _pulse_targets: Dictionary = {}
var recoil_remaining := 0.0
var _recoil_away := Vector3.FORWARD
var _last_stagger_tick := -1
var active_move: Dictionary = {}
var elapsed := 0.0
var status := "Ready"
var last_damage := 0.0
var last_blocked := false
var last_parried := false
var last_evaded := false
var parry_remaining := 0.0
var parry_feedback := 0.0
var total_parries := 0
var total_hits := 0
var last_strike_speed := 0.0
var last_strike_multiplier := 1.0
var last_hit_amount := 0.0
var impact_feedback := 0.0
var _facing := Vector3.FORWARD
var _queued: Dictionary = {}
var _queue_time := 0.0
var _pose_weight := 0.0
var _right_rotation := Vector3.ZERO
var _left_rotation := Vector3.ZERO
var _hud_time := 0.0
var _katana_anchor := Vector3.ZERO
var _katana_gripping := false
var _full_charge_shown := false
var _combo_cursor := 0
var _combo_remaining := 0.0
var _combo_item: StringName = &""

func _ready() -> void:
	name = "WeaponCombat"
	actor.combat.permission = can_act
	feedback = Feedback.obtain(actor)
	_build_presentation()
	actor.combat.action_requested.connect(_on_action)
	actor.combat.charge_started.connect(_on_charge_started)
	actor.combat.weapon_slot_selected.connect(_on_weapon)
	actor.combat.sheathed_changed.connect(_on_sheathed)
	actor.combat.block_changed.connect(_on_block)
	actor.dodge.started.connect(func(_a: Vector3, _b: Vector3): cancel())
	sync_rig()

func _build_presentation() -> void:
	# Creature combatants can supply their own rig/weight transfer while keeping
	# the same timed hits, defenses, exhaustion, feedback and forced states.
	body.actor = actor
	rig = Rig.new()
	rig.visual = actor.visual
	actor.visual.add_child(rig)
	trail = Trail.new()
	actor.add_child(trail)
	trail.top_level = true
	trail.global_transform = Transform3D.IDENTITY

func loadout(slot: StringName) -> Dictionary:
	var resolved: StringName = actor.combat.resolve_slot(slot)
	if resolved == &"": return {"id":&"unarmed","name":"Empty","short":"Empty","color":Color(0.35,0.55,0.6),"guard":0.0}
	return Library.loadout(equipment_key(slot))

func equipment_key(slot: StringName) -> StringName:
	var inventory: Node = actor.get("inventory")
	if is_instance_valid(inventory):
		var item: Resource = inventory.equipped_item(slot)
		if item!=null and item.owner_id==inventory.owner_id and Equipment.is_weapon(item.item_type_id): return item.item_type_id
	return actor.combat.resolve_slot(slot)

func combo_for(key: StringName,action: StringName) -> int:
	return _combo_cursor if action in [&"attack_left",&"attack_right"] and key==_combo_item and _combo_remaining>0 else 0

func move_for(slot: StringName, action: StringName) -> Dictionary:
	var resolved: StringName = actor.combat.resolve_slot(slot)
	var key := equipment_key(slot)
	return Library.move(key,action,combo_for(key,action),not actor.is_on_floor()) if resolved != &"" else {}

func charged_move(slot: StringName, action: StringName, strength: float) -> Dictionary:
	var resolved: StringName = actor.combat.resolve_slot(slot)
	var key := equipment_key(slot)
	return Library.charged_move(key,action,strength,combo_for(key,action),not actor.is_on_floor()) if resolved != &"" else {}

func sync_rig() -> void:
	var key := equipment_key(actor.combat.selected_slot)
	if Equipment.is_weapon(key): rig.equip_item(key,actor.combat.sheathed)
	else: rig.equip(actor.combat.resolve_slot(actor.combat.selected_slot),actor.combat.sheathed)

func aim_direction() -> Vector3:
	if actor.target_lock.is_locked(): return actor.target_lock.facing()
	return Vector3.FORWARD.rotated(Vector3.UP,actor.camera_rig.yaw)

func damage_multiplier(speed: float) -> float:
	return 1.0+maxf(0,speed)*maxf(0,momentum_damage_gain)

func is_staggered() -> bool:
	return stagger_remaining>0.000001

func can_act() -> bool:
	return health>0 and not is_staggered()

func stagger(source: Vector3) -> void:
	enter_forced(&"parried",rules.parry_stagger,source)

func enter_forced(state: StringName, duration: float, source: Vector3) -> void:
	if health<=0: return
	var priorities := {&"":0,&"hit":1,&"fallen":2,&"exhausted":2,&"parried":3}
	if is_staggered() and int(priorities[forced_state])>int(priorities[state]): return
	cancel()
	body.release(true)
	if actor.dodge.active: actor.velocity = actor.dodge._saved_velocity
	actor.dodge.cancel()
	actor.combat.cancel_charge()
	actor.combat.blocking = false
	parry_remaining = 0
	forced_state = state
	forced_duration = maxf(0.01,duration)
	stagger_remaining = forced_duration
	_reaction_scale = 1.0 if state == &"parried" else 0.65
	_reaction_duration = forced_duration+RECOIL_RECOVERY
	recoil_remaining = _reaction_duration
	if state == &"exhausted":
		_kneel_duration = forced_duration+0.22
		_kneel_remaining = _kneel_duration
	elif state == &"parried":
		_kneel_remaining = 0
	_last_stagger_tick = Engine.get_physics_frames()
	var away := actor.global_position-source
	away.y = 0
	_recoil_away = actor.visual.global_basis.inverse()*away.normalized() if not away.is_zero_approx() else Vector3.FORWARD
	status = forced_label()
	if actor.controls.has_method("on_forced_reaction"): actor.controls.on_forced_reaction()
	changed.emit()

func forced_label() -> String:
	return {&"parried":"Parried - open",&"exhausted":"Exhausted - vulnerable",&"hit":"Hit stagger",&"fallen":"Hard landing"}.get(forced_state,"Ready")

func clear_stagger() -> void:
	stagger_remaining = 0
	recoil_remaining = 0
	forced_state = &""
	_kneel_remaining = 0
	hitstop_remaining = 0
	_freeze_armed = false
	actor.visual.clear_combat_pose()
	status = "Guard" if actor.combat.blocking else ("Sheathed" if actor.combat.sheathed else "Ready")
	changed.emit()

func recoil_amount() -> float:
	if recoil_remaining<=0: return 0
	var age := _reaction_duration-recoil_remaining
	var settle := minf(0.28,_reaction_duration*0.4)
	return _reaction_scale*lerpf(0.65,1.0,smoothstep(0,0.035,age))*(1-smoothstep(_reaction_duration-settle,_reaction_duration,age))

func freeze_visuals(duration: float) -> void:
	hitstop_remaining = maxf(hitstop_remaining,maxf(0,duration))
	_freeze_armed = false # Present the confirmed reaction once before holding it.

func visual_frozen() -> bool:
	return _freeze_armed and hitstop_remaining>0.000001 and not actor.dodge.active

func effective_fortitude() -> float:
	if is_staggered(): return 0
	var slot: StringName = actor.combat.resolve_slot(actor.combat.selected_slot)
	var base: float = rules.base_fortitude+{&"down":0.25,&"left":0.1,&"right":0.0,&"up":-0.1}.get(slot,0.0)
	if actor.combat.blocking: base += 0.2
	if not active_move.is_empty():
		var driving := elapsed>=float(active_move.windup)*0.65 and elapsed<float(active_move.hits[-1])+0.12
		base += ({&"down":0.75,&"left":0.55,&"right":0.45,&"up":0.25}.get(slot,0.25) if driving else 0.1)
		if active_move.profile in ["slam","aegis","beam","pillar"] and driving: base += 0.4
		base += float(active_move.get("charge",0))*0.35
	return maxf(0,base)

func get_block_exhaustion(incoming: Dictionary) -> float:
	return clampf(10+float(incoming.get("damage",16))*0.4,14,40)*(0.6+guard_strength()*0.4)

func _add_exhaustion(amount: float, source: Vector3) -> bool:
	if amount<=0 or health<=0 or is_staggered(): return false
	psi_meter = minf(rules.max_psi,psi_meter+amount)
	_psi_delay = rules.psi_recovery_delay
	if psi_meter>=rules.max_psi:
		enter_forced(&"exhausted",rules.exhausted_duration,source)
		return true
	changed.emit()
	return false

func on_guard_contact(amount: float, source: Vector3) -> bool:
	if health<=0 or is_staggered(): return false
	# Additive arm/body recoil; preserve the current move and its hit schedule.
	_reaction_scale = 0.28
	_reaction_duration = 0.16
	recoil_remaining = 0.16
	_recoil_away = actor.visual.global_basis.inverse()*(actor.global_position-source).normalized()
	return _add_exhaustion(amount,source)

func _on_action(action: StringName, slot: StringName) -> void:
	if is_staggered(): return
	if actor.combat.sheathed:
		return
	if actor.combat.blocking: return
	var strength: float = actor.combat.released_charge
	actor.combat.cancel_charge()
	var move := charged_move(slot,action,strength)
	if move.is_empty(): return
	if actor.dodge.active or not active_move.is_empty():
		_queued = {"action":action,"slot":slot,"charge":strength}
		_queue_time = 0.4
		return
	_begin(move)

func _on_charge_started(_action: StringName, _slot: StringName) -> void:
	_queued.clear()
	_queue_time = 0
	_full_charge_shown = false
	if actor.combat.blocking or is_staggered():
		actor.combat.cancel_charge()
		return
	if active_move.is_empty() and not actor.dodge.active:
		_facing = aim_direction()
		body.begin(_facing)
	changed.emit()

func _begin(move: Dictionary) -> void:
	if is_staggered(): return
	active_move = move
	if move.has("combo_next"):
		_combo_cursor = int(move.combo_next)
		_combo_item = StringName(move.item_id)
		_combo_remaining = float(move.duration)+0.65
	_pulse_targets.clear()
	elapsed = 0
	_facing = aim_direction()
	body.begin(_facing)
	status = move.name
	changed.emit()

func cancel() -> void:
	_combo_cursor = 0
	_combo_remaining = 0
	actor.combat.cancel_charge()
	active_move = {}
	_queued.clear()
	actor.visual.clear_combat_pose()
	body.release(actor.dodge.active)
	if actor.dodge.active and parry_remaining>0:
		parry_remaining = 0
		changed.emit()
	if is_instance_valid(trail): trail.samples.clear()

func _on_weapon(slot: StringName) -> void:
	cancel()
	sync_rig()
	status = forced_label() if is_staggered() else "Ready · "+loadout(slot).name
	changed.emit()

func _on_sheathed(stowed: bool) -> void:
	cancel()
	sync_rig()
	status = forced_label() if is_staggered() else ("Sheathed" if stowed else "Ready")
	changed.emit()

func _on_block(held: bool) -> void:
	if held:
		cancel()
		_facing = aim_direction()
	parry_remaining = PARRY_WINDOW if held and actor.combat.fresh_block and not actor.dodge.active and not is_staggered() else 0.0
	status = forced_label() if is_staggered() else ("Guard" if held else "Ready")
	changed.emit()

func reset() -> void:
	cancel()
	clear_stagger()
	health = max_health
	psi_meter = 0
	_psi_delay = 0
	last_outcome = &"invalid"
	last_damage = 0
	last_blocked = false
	last_parried = false
	last_evaded = false
	parry_remaining = 0
	parry_feedback = 0
	impact_feedback = 0
	last_strike_speed = 0
	last_strike_multiplier = 1
	last_hit_amount = 0
	_pose_weight = 0
	_katana_gripping = false
	body.release(true)
	trail.samples.clear()
	sync_rig()
	status = "Sheathed" if actor.combat.sheathed else "Ready"
	changed.emit()

func guard_strength() -> float:
	return 0.25 if actor.combat.sheathed else float(loadout(actor.combat.selected_slot).guard)

func receive_hit(amount: float, source: Vector3, attacker: Node = null, incoming: Dictionary = {}) -> float:
	last_parried = false
	last_blocked = false
	last_evaded = false
	last_damage = 0
	last_outcome = &"invalid"
	if amount<=0 or health<=0: return 0
	if actor.dodge.is_invulnerable():
		last_evaded = true
		last_outcome = &"evaded"
		return 0
	var attack := incoming
	if attack.is_empty() and is_instance_valid(attacker) and attacker.get("weapon_combat") != null:
		attack = attacker.weapon_combat.active_move
	var toward := source-actor.global_position
	toward.y = 0
	var direction: Vector3 = (actor.combat_point()-source).normalized()
	var point: Vector3 = incoming.get("contact",actor.combat_point()-direction*0.27)
	var bloom: bool = not active_move.is_empty() and active_move.profile == "aegis" and elapsed < 0.65
	var facing := aim_direction() if actor.combat.blocking else _facing
	var frontal := toward.normalized().dot(facing)>cos(deg_to_rad(70))
	var guarding: bool = actor.combat.blocking and can_act()
	# Exactly one outcome, with no exhaustion/fortitude evaluation on a parry.
	if guarding and frontal and parry_remaining>0 and not actor.dodge.active and bool(attack.get("parryable",true)):
		last_parried = true
		last_outcome = &"parry"
		parry_remaining = 0
		parry_feedback = PARRY_FEEDBACK_TIME
		total_parries += 1
		if is_instance_valid(attacker) and attacker != actor and attacker.has_method("on_parried"):
			attacker.on_parried(actor.combat_point())
		feedback.confirm("parry",point,direction,attacker,actor,false,int(incoming.get("hurtbox_shape",-1)))
		parried.emit(source)
		changed.emit()
		return 0
	var basic_guard := guarding and frontal
	last_blocked = bloom or basic_guard
	var reduction := (0.95 if bloom else guard_strength()) if last_blocked else 0.0
	var vulnerability: float = rules.exhausted_damage_multiplier if forced_state == &"exhausted" else 1.0
	last_damage = maxf(0,amount)*(1-reduction)*vulnerability
	var applied := last_damage
	health = maxf(0,health-last_damage)
	var outcome := "block" if last_blocked else "hit"
	last_outcome = &"block" if last_blocked else &"hyper_armor"
	if last_blocked:
		# Resolve strain once per confirmed hit, before either meter can clamp or
		# exhaust its owner. Automatic Aegis mitigation keeps its existing rules.
		var strain := get_block_exhaustion(attack)
		if is_instance_valid(attacker) and attacker.get("weapon_combat") != null:
			if attacker.weapon_combat.on_guard_contact(strain,actor.combat_point()): outcome = "exhaustion"
		if basic_guard and _add_exhaustion(strain*maxf(0,rules.defender_exhaustion_multiplier),source):
			outcome = "exhaustion"
	elif health>0:
		var strength := float(attack.get("hit_stun_level",0))
		if strength>=effective_fortitude() and strength>0:
			enter_forced(&"hit",float(attack.get("hit_stagger",0.25)),source)
			last_outcome = &"stagger"
			outcome = "heavy" if strength>=1.5 else "hit"
		elif not is_staggered():
			_reaction_scale = 0.12
			_reaction_duration = 0.13
			recoil_remaining = _reaction_duration
			_recoil_away = actor.visual.global_basis.inverse()*direction
		if strength>=1.5: outcome = "heavy"
	feedback.confirm(outcome,point,direction,attacker,actor,applied>0,int(incoming.get("hurtbox_shape",-1)))
	if applied>0: parry_feedback = 0
	changed.emit()
	if health<=0: actor.on_combat_defeat()
	return applied

func receive_environment_damage(amount: float) -> float:
	# Gravity has no attacker, guard arc, parry, momentum multiplier or iframe.
	# Keep it separate from weapon resolution and its fortitude/exhaustion rules.
	if amount<=0 or health<=0: return 0
	var applied := minf(health,amount)
	health -= applied
	last_damage = applied
	last_outcome = &"fall"
	last_parried = false
	last_blocked = false
	last_evaded = false
	parry_feedback = 0
	# Landing motion keeps playing; weapon hitstop must not hold a fresh jump
	# in its previous crouch. Sparks, sound and camera feedback still play.
	feedback.confirm("hit" if applied<=50 else "heavy",actor.combat_point(),Vector3.DOWN,null,actor,true,-1,false)
	changed.emit()
	if health<=0: actor.on_combat_defeat()
	return applied

func advance_stagger(delta: float) -> void:
	# The actor advances this before sampling controls. The component also calls
	# it for isolated/test actors; one physics-frame stamp prevents double ticks.
	var tick := Engine.get_physics_frames()
	if tick == _last_stagger_tick: return
	_last_stagger_tick = tick
	var was_staggered := is_staggered()
	stagger_remaining = maxf(0,stagger_remaining-delta)
	hitstop_remaining = maxf(0,hitstop_remaining-delta)
	_kneel_remaining = maxf(0,_kneel_remaining-delta)
	_psi_delay = maxf(0,_psi_delay-delta)
	if not was_staggered and _psi_delay<=0 and active_move.is_empty() and actor.combat.charge_action == &"" and not actor.dodge.active and not actor.boost_active:
		psi_meter = maxf(0,psi_meter-rules.psi_recovery*delta)
	recoil_remaining = maxf(0,recoil_remaining-delta)
	if was_staggered and not is_staggered():
		# Reset the threshold even if a higher priority parry replaced exhaustion.
		if psi_meter>=rules.max_psi: psi_meter = rules.max_psi*rules.recovered_psi_fraction
		forced_state = &""
		_psi_delay = rules.psi_recovery_delay
		status = "Guard" if actor.combat.blocking else ("Sheathed" if actor.combat.sheathed else "Ready")
		changed.emit()

func _physics_process(delta: float) -> void:
	_combo_remaining = maxf(0,_combo_remaining-delta)
	advance_stagger(delta)
	var world_actions: Node = actor.get("world_actions")
	if is_instance_valid(world_actions) and world_actions.attached():
		world_actions.apply_pose()
		return
	impact_feedback = maxf(0,impact_feedback-delta)
	if actor.target_lock.is_locked(): _facing = actor.target_lock.facing()
	var was_ready := parry_remaining>0
	var had_feedback := parry_feedback>0
	parry_remaining = maxf(0,parry_remaining-delta)
	parry_feedback = maxf(0,parry_feedback-delta)
	if (was_ready and parry_remaining==0) or (had_feedback and parry_feedback==0): changed.emit()
	_queue_time = maxf(0,_queue_time-delta)
	if _queue_time == 0: _queued.clear()
	if actor.dodge.active:
		_pose_weight = 0
		trail.update(delta,[],loadout(actor.combat.selected_slot).color)
		return
	if not is_staggered() and active_move.is_empty() and not _queued.is_empty() and not actor.combat.blocking and not actor.combat.sheathed:
		var request := _queued.duplicate()
		_queued.clear()
		actor.combat.released_charge = float(request.get("charge",0))
		_on_action(request.action,request.slot)
		actor.combat.released_charge = 0
	if not active_move.is_empty():
		var previous := elapsed
		elapsed += delta
		advance_strikes(previous)
		if not active_move.is_empty() and elapsed >= float(active_move.duration):
			active_move = {}
			status = "Ready"
			changed.emit()
	if actor.combat.charge_action != &"" and active_move.is_empty() and not actor.combat.blocking:
		var charging := move_for(actor.combat.charge_slot,actor.combat.charge_action)
		active_move = charging
		var saved_time := elapsed
		elapsed = float(charging.windup)*0.55*smoothstep(0,0.25,actor.combat.charge_elapsed)
		apply_pose(delta)
		active_move = {}
		elapsed = saved_time
		status = "Charge %d%% - release" % int(actor.combat.charge_elapsed/actor.combat.CHARGE_FULL*100)
		if actor.combat.charge_elapsed>=actor.combat.CHARGE_FULL and not _full_charge_shown:
			_full_charge_shown = true
			emit_effect("parry",0.7,0,loadout(actor.combat.charge_slot).color,actor.combat_point(),aim_direction(),0.3)
	else:
		if status.begins_with("Charge "): status = "Ready"
		apply_pose(delta)
	if actor.get("fall_damage") != null: actor.fall_damage.apply_pose(delta)
	_freeze_armed = hitstop_remaining>0
	var tracing: bool = not active_move.is_empty() and elapsed >= float(active_move.windup)*0.65 and elapsed < float(active_move.duration)*0.86
	if not visual_frozen(): trail.update(delta,rig.blade_segments() if tracing else [],loadout(actor.combat.selected_slot).color)
	_hud_time -= delta
	if _hud_time <= 0:
		_hud_time = 0.1
		changed.emit()

func advance_strikes(previous: float) -> void:
	for pulse in range(active_move.hits.size()):
		var hit_time: float = active_move.hits[pulse]
		if previous < hit_time and elapsed >= hit_time: strike(pulse)
		if active_move.is_empty(): break # A duel may finish inside a hit callback.

func strike(pulse: int = -1) -> void:
	if active_move.is_empty() or is_staggered(): return
	var move := active_move.duplicate(true)
	if actor.target_lock.is_locked(): _facing = actor.target_lock.facing()
	var origin := actor.global_position+Vector3.UP*0.95
	var volume := SphereShape3D.new()
	volume.radius = float(move.reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = volume
	query.transform = Transform3D(Basis.IDENTITY,origin)
	query.collision_mask = 2
	query.exclude = [actor.get_rid()]
	var space := actor.get_world_3d().direct_space_state
	var candidates: Array = space.intersect_shape(query,32)
	resolve_strike(move,pulse,origin,candidates)
	emit_effect(move.profile,float(move.reach),float(move.arc),loadout(actor.combat.selected_slot).color,origin,_facing)
	changed.emit()

func resolve_strike(move: Dictionary, pulse: int, origin: Vector3, candidates: Array, use_arc: bool = true) -> void:
	# Shared resolution for weapon volumes and articulated creature contacts.
	# Sample actual impact velocity; keep guard/parry/exhaustion in receive_hit.
	var impact_speed := actor.velocity.length()
	var multiplier := damage_multiplier(impact_speed)
	var damage := float(move.damage)*multiplier
	var space := actor.get_world_3d().direct_space_state
	var excluded: Array[RID] = [actor.get_rid()]
	for candidate: Dictionary in candidates: excluded.append(candidate.rid)
	var visited: Dictionary = _pulse_targets.get(pulse,{}) if pulse>=0 else {}
	if pulse>=0: _pulse_targets[pulse] = visited
	for candidate: Dictionary in candidates:
		var target: Node3D = candidate.collider
		if visited.has(target) or not target.has_method("receive_hit"): continue
		if not actor.can_attack_target(target): continue
		var point: Vector3 = target.combat_point() if target.has_method("combat_point") else target.global_position+Vector3.UP*0.9
		var toward := point-origin
		if use_arc and absf(toward.y)>1.9: continue
		var planar := Vector3(toward.x,0,toward.z)
		if use_arc and float(move.arc)<359 and planar.normalized().dot(_facing)<cos(deg_to_rad(float(move.arc)*0.5)): continue
		# Hurt volumes are separate from terrain. Opaque world geometry must stop
		# every strike, including radial pulses and long-range glyph cuts.
		var obstruction := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,point,9,excluded)) # Architecture and physical vehicles.
		if not obstruction.is_empty(): continue
		visited[target] = true
		# Carry attacker identity for real parry recoil. Legacy targets keep their
		# existing two-argument hit contract; never infer the attacker from a lock.
		var contact := move.duplicate()
		contact.hurtbox_shape = int(candidate.shape)
		var surface := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,point,2,[actor.get_rid()]))
		contact.contact = candidate.get("contact",surface.position if not surface.is_empty() and surface.collider == target else point-toward.normalized()*0.27)
		var applied: float = target.receive_combat_hit(damage,origin,actor,contact) if target.has_method("receive_combat_hit") else target.receive_hit(damage,origin)
		if not target.has_method("receive_combat_hit") and applied>0:
			feedback.confirm("heavy" if float(move.get("hit_stun_level",0))>=1.5 else "hit",contact.contact,toward,actor,target,true,int(candidate.shape))
		if applied<=0 and active_move.is_empty(): break # A parry cancels this entire pulse.
		if applied <= 0: continue
		total_hits += 1
		last_strike_speed = impact_speed
		last_strike_multiplier = multiplier
		last_hit_amount = applied
		impact_feedback = 2.0
		hit_landed.emit(target,applied,move.name)
		if active_move.is_empty(): break

func spawn_effect(origin: Vector3) -> void:
	emit_effect(active_move.profile,float(active_move.reach),float(active_move.arc),loadout(actor.combat.selected_slot).color,origin,_facing)

func emit_effect(profile: String, radius: float, arc: float, color: Color, origin: Vector3, facing: Vector3, lifetime: float = 0.42) -> void:
	var effects := get_tree().get_nodes_in_group("weapon_effects")
	while effects.size() >= 24:
		var oldest: Node = effects.pop_front()
		oldest.remove_from_group("weapon_effects")
		oldest.queue_free()
	var effect := Effect.new()
	effect.profile = profile
	effect.radius = radius
	effect.arc = arc
	effect.color = color
	effect.lifetime = lifetime
	actor.get_parent().add_child(effect)
	effect.global_position = origin
	effect.global_basis = Basis(Vector3.UP,atan2(facing.x,facing.z))

func solve_arm(id: String, target_local: Vector3, weight: float) -> void:
	var arm: Node3D = actor.visual.joints[id]
	var hinge: Node3D = arm.get_node("Hinge")
	var target: Vector3 = actor.visual.to_global(target_local)
	var offset := target-arm.global_position
	var distance := clampf(offset.length(),0.05,0.586)
	var direction := offset.normalized()
	target = arm.global_position+direction*distance
	var side := -1.0 if id == "LeftArm" else 1.0
	var pole: Vector3 = actor.visual.global_basis*Vector3(side,-0.3,-0.1)
	pole = (pole-direction*pole.dot(direction)).normalized()
	var along := (0.30*0.30-0.29*0.29+distance*distance)/(2*distance)
	var upper := direction*along+pole*sqrt(maxf(0,0.30*0.30-along*along))
	var up := -upper.normalized()
	var right := up.cross(pole).normalized()
	var desired := Basis(right,up,right.cross(up)).orthonormalized()
	var local: Basis = arm.get_parent().global_basis.inverse()*desired
	actor.visual.combat_rotation(arm,local.get_rotation_quaternion(),weight)
	var lower_up := (hinge.global_position-target).normalized()
	right = lower_up.cross(pole).normalized()
	desired = Basis(right,lower_up,right.cross(lower_up)).orthonormalized()
	local = arm.global_basis.inverse()*desired
	actor.visual.combat_rotation(hinge,local.get_rotation_quaternion(),weight)

func apply_pose(delta: float) -> void:
	if visual_frozen(): return
	var attacking := not active_move.is_empty()
	var guarding: bool = actor.combat.blocking and not is_staggered()
	var recoil := recoil_amount()
	var idle: bool = actor.is_on_floor() and Vector2(actor.velocity.x,actor.velocity.z).length()<0.1
	var kind: StringName = loadout(actor.combat.selected_slot).id
	var katana: bool = kind == &"katana" and not actor.combat.sheathed
	if not katana: _katana_gripping = false
	var desired_weight := 1.0 if attacking or guarding or katana or recoil>0 else (0.45 if idle and not actor.combat.sheathed else 0.0)
	_pose_weight = lerpf(_pose_weight,desired_weight,1-exp(-18*delta))
	if attacking or guarding:
		var aim := aim_direction() if guarding else _facing
		actor.visual.rotation.y = lerp_angle(actor.visual.rotation.y,atan2(aim.x,aim.z),1-exp(-22*delta))
	var right := Vector3(0.28,1.03,0.20)
	var left := Vector3(-0.28,1.08,0.22)
	var right_rotation := Vector3(0.16,0,-0.12)
	var left_rotation := Vector3(0.16,0,0.12)
	if guarding:
		right = Vector3(0.22,1.30,0.32)
		left = Vector3(-0.16,1.32,0.40)
		right_rotation = Vector3(0.4,0,0.5)
		left_rotation = Vector3(0,0,-0.1)
		if kind == &"spear":
			left = Vector3(0.12,1.25,0.4)
			right_rotation.x = 1.15
		elif kind == &"twin_blades":
			left.x = -0.22
			right_rotation.z = 0.7
			left_rotation.z = -0.7
	elif attacking:
		var progress := clampf(elapsed/float(active_move.duration),0,1)
		var wind := clampf(elapsed/maxf(0.01,float(active_move.windup)),0,1)
		var cut := smoothstep(float(active_move.windup)*0.9,float(active_move.hits[0])+0.05,elapsed)
		var side := float(active_move.side)
		var profile: String = active_move.profile
		right = right.lerp(Vector3(0.4*side,1.49,0.05),wind).lerp(Vector3(-0.12*side,1.12,0.37),cut)
		left = left.lerp(Vector3(-0.28,1.23,0.20),wind)
		right_rotation = Vector3(lerpf(-0.45,1.25,cut),0,side*lerpf(-1.2,1.1,cut))
		if profile in ["thrust","spiral","beam","comets"]:
			right = Vector3(0.20,1.10,lerpf(0.08,0.53,sin(PI*progress)))
			left = Vector3(0.08,1.18,0.34)
			right_rotation = Vector3(PI*0.5,0,0)
		elif profile in ["slam","pillar","rain"]:
			right = Vector3(0.10,1.77,0.18).lerp(Vector3(0.17,0.99,0.34),cut)
			left = Vector3(-0.08,1.69,0.20).lerp(Vector3(-0.10,1.1,0.36),cut)
			right_rotation = Vector3(lerpf(-0.8,1.8,cut),0,0.1)
		elif profile in ["orbit","lattice","waltz"]:
			var turn := progress*TAU*(2 if kind == &"twin_blades" else 1)
			right = Vector3(cos(turn)*0.32,1.22+sin(turn*2)*0.12,0.28+sin(turn)*0.14)
			left = Vector3(-cos(turn)*0.30,1.22-sin(turn*2)*0.12,0.28-sin(turn)*0.14)
			right_rotation = Vector3(0.7,turn,0.9)
			left_rotation = Vector3(0.7,-turn,-0.9)
		elif profile == "cross":
			var turn := progress*TAU*1.5
			right = Vector3(cos(turn)*0.32,1.26+sin(turn)*0.20,0.32)
			left = Vector3(-cos(turn)*0.32,1.26-sin(turn)*0.20,0.32)
			right_rotation.z = sin(turn)*1.3
			left_rotation.z = -sin(turn)*1.3
		elif profile == "aegis":
			left = Vector3(-0.08,1.34,0.47)
			right = Vector3(0.3,1.37,0.28)
			left_rotation = Vector3.ZERO
		if int(active_move.side)<0 and profile == "sweep":
			left = Vector3(-0.4,1.42,0.1).lerp(Vector3(0.12,1.16,0.37),cut)
			left_rotation = Vector3(lerpf(-0.4,1.2,cut),0,lerpf(1.0,-1.0,cut))
		if kind == &"sword_shield" and int(active_move.side)<0:
			left = Vector3(-0.27,1.2,lerpf(0.20,0.53,sin(PI*progress)))
			left_rotation = Vector3.ZERO
	if katana:
		var pose := katana_pose(attacking,guarding)
		right = pose.hand
		right_rotation = pose.rotation
	if attacking and active_move.has("motion"):
		var authored := Motion.sample(active_move,elapsed)
		if not authored.is_empty():
			right = authored.right
			left = authored.left
			right_rotation = authored.right_rotation
			left_rotation = authored.left_rotation
	if recoil>0:
		right = right.lerp(Vector3(0.40,1.32,-0.08),recoil)
		left = left.lerp(Vector3(-0.36,1.22,-0.10),recoil)
		right_rotation = right_rotation.lerp(Vector3(-0.55,0.4,-0.75),recoil)
		left_rotation = left_rotation.lerp(Vector3(-0.4,-0.2,0.6),recoil)
	for axis in range(3):
		_right_rotation[axis] = lerp_angle(_right_rotation[axis],right_rotation[axis],1-exp(-22*delta))
		_left_rotation[axis] = lerp_angle(_left_rotation[axis],left_rotation[axis],1-exp(-22*delta))
	body.apply(delta,active_move,elapsed,guarding,kind,aim_direction() if guarding else _facing)
	if recoil>0: apply_recoil_body(recoil)
	if _kneel_remaining>0: apply_exhausted_body()
	if _pose_weight>0.001:
		var right_world := hand_world(right)
		if katana:
			var hand_local := Vector3(right.x,right.y-actor.visual.REST_HIP_HEIGHT,right.z)
			if not _katana_gripping:
				_katana_anchor = actor.visual.chest.to_local(rig.right_hand.global_position)
				_katana_gripping = true
			_katana_anchor = _katana_anchor.lerp(hand_local,1-exp(-30*delta))
			right_world = actor.visual.chest.to_global(_katana_anchor)
			# Both wrists share one physical hilt. Clamp the shared grip into the
			# overlap of both arm reaches before solving either chain.
			var hilt_offset: Vector3 = actor.visual.chest.global_basis*Basis.from_euler(_right_rotation)*Vector3(0,-0.17,0)
			var r_shoulder: Vector3 = actor.visual.joints.RightArm.global_position
			var l_shoulder: Vector3 = actor.visual.joints.LeftArm.global_position
			for i in range(5):
				right_world = r_shoulder+(right_world-r_shoulder).limit_length(0.575)
				var support := right_world+hilt_offset
				right_world += l_shoulder+(support-l_shoulder).limit_length(0.575)-support
		solve_arm("RightArm",actor.visual.to_local(right_world),1.0 if katana else _pose_weight)
		if not katana: solve_arm("LeftArm",actor.visual.to_local(hand_world(left)),_pose_weight)
	rig.orient(_right_rotation,_left_rotation)
	if katana:
		if not attacking and not guarding and actor.is_on_floor(): clear_katana_tip()
		solve_arm("LeftArm",actor.visual.to_local(rig.right_hand.to_global(Vector3(0,-0.17,0))),1.0)

func apply_recoil_body(amount: float) -> void:
	var visual: Node3D = actor.visual
	var ankles: Dictionary = {}
	if actor.is_on_floor():
		for id in ["LeftLeg","RightLeg"]:
			ankles[id] = visual.joints[id].get_node("Hinge").to_global(Vector3(0,-0.45,0))
	# Chest opens as the weapon is knocked aside; hips sink over supported feet.
	# Only pose nodes move. The capsule, camera and carried momentum are untouched.
	visual.combat_position(visual.pelvis,visual.pelvis.position+Vector3(_recoil_away.x*0.025,-0.06,_recoil_away.z*0.035)*amount)
	visual.combat_rotation(visual.pelvis,visual.pelvis.quaternion*Quaternion.from_euler(Vector3(_recoil_away.z*0.10,0,-_recoil_away.x*0.08)*amount),1)
	visual.combat_rotation(visual.chest,visual.chest.quaternion*Quaternion.from_euler(Vector3(_recoil_away.z*0.36,0.15,-0.08)*amount),1)
	for id in ankles: visual.combat_leg(id,ankles[id],visual.global_basis.z)

func apply_exhausted_body() -> void:
	var visual: Node3D = actor.visual
	var age := _kneel_duration-_kneel_remaining
	var weight := smoothstep(0,0.22,age)*(1-smoothstep(_kneel_duration-0.3,_kneel_duration,age))
	if weight<=0: return
	# Rear knee descends, front foot braces, hips carry the weight. Pose only.
	var hips: Vector3 = visual.pelvis.position+Vector3(0,0,-0.06)*weight
	# Do not stack kneeling depth with the existing height-based landing compression.
	hips.y = lerpf(visual.pelvis.position.y,visual.REST_HIP_HEIGHT-0.44,weight)
	visual.combat_position(visual.pelvis,hips)
	visual.combat_rotation(visual.chest,Quaternion.from_euler(Vector3(0.32,0,0)),weight)
	for id in ["LeftLeg","RightLeg"]:
		var ankle: Vector3 = visual.joints[id].get_node("Hinge").to_global(Vector3(0,-0.45,0))
		var target: Vector3 = visual.to_global(Vector3(-0.17 if id == "LeftLeg" else 0.17,0.06,0.38 if id == "LeftLeg" else -0.38))
		if not actor.is_on_floor(): target.y = ankle.y-0.1
		visual.combat_leg(id,ankle.lerp(target,weight),visual.global_basis.z)

func clear_katana_tip() -> void:
	# Sprint anticipation can lean the torso before speed catches up. Correct
	# carry clearance from the actual hand and blade, not from input speed.
	var axis: Vector3 = rig.right_hand.global_basis.y.normalized()
	var tip: Vector3 = rig.right_hand.to_global(Vector3(0,1.15,0))
	var floor := body.floor_contact(tip)
	var height: float = floor.point.y+0.055 if not floor.is_empty() else actor.global_position.y+0.08
	if tip.y>=height: return
	var vertical := clampf((height-rig.right_hand.global_position.y)/1.15,-0.95,0.95)
	var planar := Vector3(axis.x,0,axis.z).normalized()
	if planar.is_zero_approx(): planar = actor.visual.global_basis.z
	var raised := planar*sqrt(1-vertical*vertical)+Vector3.UP*vertical
	rig.orient_hand(rig.right_hand,Basis(Quaternion(axis,raised))*rig.right_hand.global_basis)
	var local: Basis = actor.visual.chest.global_basis.inverse()*rig.right_hand.global_basis
	var primary := local.get_euler()
	var alternate := Vector3(PI-primary.x,primary.y+PI,primary.z+PI)
	# YXZ Euler decompositions have two equivalent forms. Keep the form nearest
	# the previous grip, so crossing 90 degrees cannot introduce a wrist flip.
	for i in range(3):
		primary[i] = _right_rotation[i]+angle_difference(_right_rotation[i],primary[i])
		alternate[i] = _right_rotation[i]+angle_difference(_right_rotation[i],alternate[i])
	_right_rotation = primary if primary.distance_squared_to(_right_rotation)<alternate.distance_squared_to(_right_rotation) else alternate

func hand_world(point: Vector3) -> Vector3:
	return actor.visual.chest.global_transform*Vector3(point.x,point.y-actor.visual.REST_HIP_HEIGHT,point.z)

func katana_pose(attacking: bool, guarding: bool) -> Dictionary:
	var pace := smoothstep(0.2,10.2,Vector2(actor.velocity.x,actor.velocity.z).length())
	# Waki-gamae: two hands beside the right hip, with the blade concealed
	# behind the body. The rig's anatomical front is local +Z.
	var ready := Vector3(0.28,1.04,-0.035)
	var down := Vector3(lerpf(-1.80,-1.65,pace),0,-0.10)
	if guarding: return {"hand":Vector3(0.10,1.30,0.40),"rotation":Vector3(0.65,-0.1,0.3)}
	if not attacking: return {"hand":ready,"rotation":down}
	var duration := float(active_move.duration)
	var first := float(active_move.hits[0])
	var last := float(active_move.hits[-1])
	var side := float(active_move.side)
	var load := smoothstep(0,maxf(0.03,float(active_move.windup)*0.88),elapsed)
	var cut := smoothstep(float(active_move.windup)*0.9,first+0.035,elapsed)
	var follow := smoothstep(first+0.035,last+0.15,elapsed)
	var recover := smoothstep(maxf(last+0.1,duration*0.76),duration,elapsed)
	var hand := ready.lerp(Vector3(0.28*side,1.54,0.08),load).lerp(Vector3(0.04,1.24,0.50),cut).lerp(Vector3(-0.24*side,1.09,0.32),follow)
	var rotation := down.lerp(Vector3(-0.35,0.15*side,-0.7*side),load).lerp(Vector3(1.55,0.05,0.8*side),cut).lerp(Vector3(2.25,-0.18*side,0.5*side),follow)
	if active_move.profile == "cross":
		var returning := smoothstep(first+0.08,last+0.035,elapsed)
		hand = hand.lerp(Vector3(0.26,1.14,0.38),returning)
		rotation = rotation.lerp(Vector3(1.85,0,-0.85),returning)
	elif active_move.profile == "waltz":
		hand = ready.lerp(Vector3(0.10,1.25,0.38),load)
		rotation = down.lerp(Vector3(1.6,0,0.5),load)
	elif active_move.profile == "beam":
		hand = ready.lerp(Vector3(0.12,1.62,0.06),load).lerp(Vector3(0.04,1.23,0.51),cut).lerp(Vector3(-0.14,1.08,0.36),follow)
		rotation = down.lerp(Vector3(-0.4,0,-0.12),load).lerp(Vector3(1.6,0,0.08),cut).lerp(Vector3(2.3,0,0.16),follow)
	return {"hand":hand.lerp(ready,recover),"rotation":rotation.lerp(down,recover)}

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(actor):
		cancel()
		clear_stagger()
		parry_remaining = 0
		parry_feedback = 0

func _exit_tree() -> void:
	if is_instance_valid(trail): trail.queue_free()
