extends CharacterBody3D
const Visual = preload("res://scripts/character_visual.gd")
const GlassStep = preload("res://scripts/glass_step.gd")
const PhaseDodge = preload("res://scripts/phase_dodge.gd")
const CombatIntent = preload("res://scripts/combat_intent.gd")
const WeaponCombat = preload("res://scripts/weapon_combat.gd")
const TargetLock = preload("res://scripts/target_lock.gd")
const FallDamage = preload("res://scripts/fall_damage.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Unstuck = preload("res://scripts/unstuck.gd")
signal air_stepped(origin: Vector3, side: int)
@export var walk_speed := 3.5
@export var run_speed := 7.5
@export var boost_speed := 10.2
@export var jump_speed := 7.5
@export var sky_jump_lift := 9.2
@export var sky_jump_push := 3.4
@export var gravity := 22.0
## Match the normal Traveler controller's momentum handling (no Library dependency).
@export var acceleration := 9.0
@export var boost_acceleration := 20.0
@export var live_motion_retrieval := true
@export var inventory_owner_id := ""
var sparring_duel: Node
var boss_encounter: Node
var health: float:
	get: return weapon_combat.health if is_instance_valid(weapon_combat) else WeaponCombat.BASE_HEALTH
var controls: Node
var camera_rig: Node3D
var visual: Node3D
var dodge: Node
var combat: Node
var weapon_combat: Node
var target_lock: Node3D
var fall_damage: Node
var inventory: Node
var loot_authority: Node
var unstuck: Node
var world_actions: Node3D
var _death_serial := 0
var _death_processing := false
var _jump_after_dodge := false
var boost_active := false
var air_step_count := 0
var last_sky_impulse := Vector3.ZERO
var _glass_steps: Array[Node3D] = []
var spawn := Vector3(0,0.05,6)

func _ready() -> void:
	name = "Player"
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48)
	max_slides = 12
	set_collision_mask_value(3,true) # Residents occupy their own physical layer.
	set_collision_mask_value(4,true) # Physical vehicles.
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.85
	collider.shape = capsule
	collider.position.y = 0.95
	add_child(collider)
	visual = Visual.new()
	visual.live_retrieval = live_motion_retrieval
	add_child(visual)
	dodge = PhaseDodge.new()
	dodge.actor = self
	add_child(dodge)
	combat = CombatIntent.new()
	combat.name = "CombatIntent"
	add_child(combat)
	inventory = Inventory.new()
	inventory.owner_id = inventory_owner_id if not inventory_owner_id.is_empty() else "actor_"+str(get_instance_id())
	inventory.actor = self
	add_child(inventory)
	inventory.seed_starter()
	combat.loadout_resolver = inventory.weapon_slot
	if controls.has_signal("special_hold_cancelled"):
		controls.special_hold_cancelled.connect(combat.cancel_charge)
	target_lock = TargetLock.new()
	target_lock.actor = self
	add_child(target_lock)
	weapon_combat = WeaponCombat.new()
	weapon_combat.actor = self
	add_child(weapon_combat)
	inventory.equipment_changed.connect(combat.refresh_equipment)
	inventory.equipment_changed.connect(func(): visual.sync_clothing(inventory))
	fall_damage = FallDamage.new()
	fall_damage.actor = self
	add_child(fall_damage)
	dodge.started.connect(fall_damage.on_dodge_started)
	dodge.shifted.connect(func(_point: Vector3): fall_damage.rebase_after_phase())
	dodge.finished.connect(fall_damage.rebase_after_phase)
	position = spawn
	fall_damage.reset()
	unstuck = Unstuck.new()
	unstuck.actor = self
	add_child(unstuck)

func _physics_process(delta: float) -> void:
	weapon_combat.advance_stagger(delta)
	fall_damage.advance(delta)
	controls.sample()
	if is_instance_valid(world_actions) and world_actions.step(delta): return
	combat.advance_charge(delta)
	target_lock.update(delta,controls)
	if controls.has_method("update_combat_hold"): controls.update_combat_hold(delta)
	combat.poll(controls)
	var jump: bool = controls.consume_jump()
	var dodge_requests := 0
	if controls.has_method("consume_dodge_requests"): dodge_requests = controls.consume_dodge_requests()
	elif controls.has_method("consume_dodge"): dodge_requests = int(controls.consume_dodge())
	var staggered: bool = weapon_combat.is_staggered()
	if staggered:
		jump = false
		dodge_requests = 0
		_jump_after_dodge = false
	var move_input: Vector2 = Vector2.ZERO if staggered else controls.move
	var intent := Vector3(move_input.x,0,move_input.y).rotated(Vector3.UP,camera_rig.yaw)
	if target_lock.is_locked(): intent = target_lock.movement(move_input)
	var idle_forward: Vector3 = target_lock.facing() if target_lock.is_locked() else Vector3.FORWARD.rotated(Vector3.UP,camera_rig.yaw)
	var dodge_direction := intent if not intent.is_zero_approx() else idle_forward
	# Consume every fresh press before advancing an existing phase. The dodge
	# owns immediate chaining, rather than losing requests in an active return.
	for _request in range(dodge_requests): dodge.start(dodge_direction)
	if dodge.active:
		_jump_after_dodge = _jump_after_dodge or jump
		dodge.advance(delta)
		face_locked_target()
		return
	var grounded := is_on_floor()
	if grounded: air_step_count = 0
	jump = jump or _jump_after_dodge
	_jump_after_dodge = false
	var speed := run_speed if controls.sprint else walk_speed
	boost_active = not staggered and controls.boost and not move_input.is_zero_approx()
	if boost_active: speed = boost_speed
	# Preserve the established ground pacing. Air steering inherits carried speed,
	# so sky-jump momentum above the ordinary pace is not pulled back to a cap.
	var rate := boost_acceleration if controls.boost else acceleration
	var target := intent*speed
	var horizontal_velocity := Vector3(velocity.x,0,velocity.z)
	if staggered: target = horizontal_velocity # Input pauses; existing momentum carries.
	var reversal := 0.0
	if not intent.is_zero_approx() and horizontal_velocity.length() > 0.1:
		reversal = maxf(0,-horizontal_velocity.normalized().dot(intent.normalized()))
	if not grounded and not intent.is_zero_approx():
		target = intent.normalized()*maxf(horizontal_velocity.length(),target.length())
	velocity.x = move_toward(velocity.x,target.x,rate*delta)
	velocity.z = move_toward(velocity.z,target.z,rate*delta)
	if not grounded: velocity.y -= gravity*delta
	if jump:
		if not grounded:
			var side := -1 if air_step_count % 2 == 0 else 1
			air_step_count += 1
			last_sky_impulse = Vector3.UP*sky_jump_lift+intent*sky_jump_push
			velocity += last_sky_impulse
			_spawn_glass_step(side,last_sky_impulse)
		else: velocity.y = jump_speed
	# Step up only when grounded, obstructed, and a clear raised sweep exists.
	# A downward sweep confirms support: no automatic ascent into open space.
	var motion := Vector3(velocity.x,0,velocity.z)*delta
	if is_on_floor() and velocity.y <= 0 and motion.length() > 0.001 and test_move(global_transform,motion):
		var raised := global_transform.translated(Vector3.UP*0.29)
		var landing := KinematicCollision3D.new()
		if not test_move(global_transform,Vector3.UP*0.29) and not test_move(raised,motion):
			# Probe over the tread, beyond the capsule's rounded leading edge.
			raised.origin += motion.normalized()*0.28
			if test_move(raised,Vector3.DOWN*0.31,landing) and landing.get_normal().y > 0.7:
				global_position.y += 0.29-landing.get_travel().length()
	fall_damage.prepare(grounded)
	var preimpact_velocity := velocity
	move_and_slide()
	fall_damage.finish(preimpact_velocity)
	var horizontal := Vector2(velocity.x,velocity.z).length()
	if target_lock.is_locked(): face_locked_target()
	elif horizontal > 0.1 and not weapon_combat.visual_frozen():
		# This procedural rig faces +Z: elbows bend forward, knees backward.
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(velocity.x,velocity.z),1-exp(-16*delta))
	visual.animate(delta,velocity,is_on_floor(),boost_active,{"boost":float(controls.boost),"repetition":clampf(air_step_count/6.0,0,1),"reversal":reversal})
	unstuck.remember_safe(delta)
	if position.y < -12: respawn()

func face_locked_target() -> void:
	if target_lock.is_locked() and not weapon_combat.visual_frozen():
		var facing: Vector3 = target_lock.facing()
		visual.rotation.y = atan2(facing.x,facing.z)

func respawn() -> void:
	if is_instance_valid(world_actions) and world_actions.attached(): world_actions.detach()
	if is_instance_valid(sparring_duel) and sparring_duel.active: sparring_duel.finish(false)
	dodge.cancel()
	target_lock.clear()
	if controls.has_method("reset_combat_input"): controls.reset_combat_input()
	combat.reset()
	weapon_combat.reset()
	_jump_after_dodge = false
	global_position = spawn
	velocity = Vector3.ZERO
	controls.boost = false
	boost_active = false
	air_step_count = 0
	last_sky_impulse = Vector3.ZERO
	fall_damage.reset()
	if is_instance_valid(unstuck): unstuck.reset_history()
	if controls.has_method("consume_dodge"): controls.consume_dodge()
	for step in _glass_steps:
		if is_instance_valid(step): step.queue_free()
	_glass_steps.clear()
	camera_rig.reset_follow()

func combat_point() -> Vector3:
	return global_position+Vector3.UP*0.95

func body_impact_point(hurtbox_contact: Vector3) -> Vector3:
	# The movement/hurt capsule is wider than this light being's visible spine.
	# Project its registered contact onto the body, never onto a weapon/grip.
	var hips: Vector3 = visual.pelvis.global_position
	var shoulders: Vector3 = visual.chest.to_global(Vector3(0,0.56,0))
	var spine := shoulders-hips
	var along := clampf((hurtbox_contact-hips).dot(spine)/maxf(0.0001,spine.length_squared()),0,1)
	var center := hips+spine*along
	var outward := hurtbox_contact-center
	return center+(outward.normalized()*0.045 if not outward.is_zero_approx() else Vector3.ZERO)

func receive_hit(amount: float, source: Vector3, attacker: Node = null, incoming: Dictionary = {}) -> float:
	if amount>0 and is_instance_valid(boss_encounter) and boss_encounter.active and attacker == boss_encounter.boss:
		boss_encounter.register_contact()
	return weapon_combat.receive_hit(amount,source,attacker,incoming)

func receive_combat_hit(amount: float, source: Vector3, attacker: Node, incoming: Dictionary = {}) -> float:
	return receive_hit(amount,source,attacker,incoming)

func on_parried(source: Vector3) -> void:
	weapon_combat.stagger(source)

func can_attack_target(target: Node) -> bool:
	if is_instance_valid(boss_encounter) and boss_encounter.active: return target == boss_encounter.boss
	return not is_instance_valid(sparring_duel) or not sparring_duel.active or target == sparring_duel.partner

func on_combat_defeat() -> void:
	if _death_processing or weapon_combat.health>0: return
	_death_processing = true
	if is_instance_valid(boss_encounter) and boss_encounter.active:
		boss_encounter.player_defeated()
	elif is_instance_valid(sparring_duel) and sparring_duel.active:
		sparring_duel.finish(false)
	else:
		_death_serial += 1
		if is_instance_valid(loot_authority): loot_authority.resolve_death(inventory,str(get_instance_id())+":"+str(_death_serial),global_position)
		respawn()
	_death_processing = false

func _spawn_glass_step(side: int, impulse: Vector3) -> void:
	var origin: Vector3 = global_position+Vector3.UP*0.55-impulse.normalized()*0.525+visual.global_basis.x*side*0.125
	var remaining: Array[Node3D] = []
	for step in _glass_steps:
		if is_instance_valid(step) and not step.is_queued_for_deletion(): remaining.append(step)
	_glass_steps = remaining
	while _glass_steps.size() >= 12: _glass_steps.pop_front().queue_free()
	var glass := GlassStep.new()
	glass.impulse = impulse
	get_parent().add_child(glass)
	glass.global_position = origin
	glass.global_basis = Basis(Quaternion(Vector3.UP,impulse.normalized())).scaled(Vector3.ONE*sqrt(glass.response_strength))
	_glass_steps.append(glass)
	visual.trigger_air_step(side,impulse,air_step_count)
	air_stepped.emit(origin,side)
