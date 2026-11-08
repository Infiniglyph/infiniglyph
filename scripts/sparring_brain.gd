extends "res://scripts/player_input.gd"
## Uses the same input contract as a player. No direct root motion or damage.
const Library = preload("res://scripts/weapon_library.gd")
const ACTIONS := [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
const SLOTS := [&"down",&"left",&"right",&"up"]
var actor: CharacterBody3D
var opponent: CharacterBody3D
var active := false
var decision := 0.3
var cursor := 0
var defense_cooldown := 0.0
var guard_time := 0.0
var sky_cooldown := 0.0
var charge_remaining := 0.0
var charging_button: StringName = &""
var circle := 1.0
var decisions := 0
var threat_time := 0.0

func _ready() -> void: pass # AI must never capture the mouse or listen to a pad.
func _unhandled_input(_event: InputEvent) -> void: pass

func stop() -> void:
	active = false
	reset_combat_input()
	move = Vector2.ZERO
	look = Vector2.ZERO
	sprint = false
	boost = false
	jump_requested = false
	dodge_requested = false
	guard_time = 0
	charge_remaining = 0
	charging_button = &""
	threat_time = 0

func start() -> void:
	stop()
	active = true
	decision = 0.45
	defense_cooldown = 0.4
	sky_cooldown = 0

func sample() -> void:
	move = Vector2.ZERO
	boost = false
	sprint = false
	_keyboard_block = false
	if not active or not is_instance_valid(opponent): return
	if actor.weapon_combat.is_staggered(): return
	var delta := get_physics_process_delta_time()
	var toward := opponent.global_position-actor.global_position
	var distance := Vector2(toward.x,toward.z).length()
	actor.camera_rig.yaw = atan2(-toward.x,-toward.z)
	if not actor.target_lock.is_locked() and distance<actor.target_lock.RANGE: actor.target_lock.select(opponent)
	decision = maxf(0,decision-delta)
	defense_cooldown = maxf(0,defense_cooldown-delta)
	sky_cooldown = maxf(0,sky_cooldown-delta)
	guard_time = maxf(0,guard_time-delta)
	_keyboard_block = guard_time>0
	# Read telegraphed windup at discrete reaction intervals, never force a parry.
	var incoming: Dictionary = opponent.weapon_combat.active_move
	var threat: bool = not incoming.is_empty() and defense_cooldown == 0 and distance<float(incoming.reach)+0.5 and opponent.weapon_combat.elapsed<float(incoming.hits[0])
	threat_time = threat_time+delta if threat else 0.0
	if threat and threat_time>=0.1:
		defense_cooldown = 0.9
		if decisions%3 == 1:
			move = Vector2(circle,0.35).normalized()
			dodge_requested = true
			circle *= -1
		else:
			guard_time = maxf(0.34,float(incoming.hits[0])-opponent.weapon_combat.elapsed+0.12)
			_keyboard_block = true
		return
	if actor.dodge.active: return
	if charge_remaining>0:
		charge_remaining = maxf(0,charge_remaining-delta)
		move = Vector2(circle*0.18,0)
		if charge_remaining == 0:
			_special(charging_button,-1,false)
			charging_button = &""
		return
	if _keyboard_block: return
	# Pursue elevated opponents using the same repeatable jump/sky-step impulse.
	var blocked := distance>2 and actor.test_move(actor.global_transform,toward.normalized()*0.6)
	if sky_cooldown == 0 and (toward.y>1.2 or blocked) and (actor.is_on_floor() or actor.velocity.y<2):
		jump_requested = true
		sky_cooldown = 0.4
	var slot: StringName = SLOTS[(cursor/6)%SLOTS.size()]
	var action: StringName = ACTIONS[cursor%ACTIONS.size()]
	var spec := Library.move(slot,action)
	var comfortable := maxf(1.2,float(spec.reach)*0.72)
	if distance>comfortable:
		move = Vector2(circle*0.12,-1).normalized()
		sprint = distance>4
		boost = distance>8
	elif distance<1.1: move = Vector2(circle*0.45,0.6).limit_length()
	else: move = Vector2(circle*0.32,0)
	if not actor.weapon_combat.active_move.is_empty() or decision>0: return
	if distance>float(spec.reach)*0.95 or absf(toward.y)>1.7: return
	var ray := PhysicsRayQueryParameters3D.create(actor.combat_point(),opponent.combat_point(),1,[actor.get_rid(),opponent.get_rid()])
	if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return
	choose_attack(slot,action)

func choose_attack(slot: StringName, action: StringName) -> void:
	if actor.combat.selected_slot != slot: _request(&"weapon",slot)
	decisions += 1
	if String(action).begins_with("special_") and decisions%3 == 0:
		_keyboard_modifier = String(action).contains("rt_")
		charging_button = &"x" if String(action).ends_with("x") else &"y"
		_special(charging_button)
		_keyboard_modifier = false
		charge_remaining = 1.2
	else: _request(&"action",action)
	decision = float(Library.move(slot,action).duration)+0.35
	cursor = (cursor+1)%24
	if cursor%4 == 0: circle *= -1

func on_forced_reaction() -> void:
	# Discard obsolete intentions; the shared combat controller owns recovery.
	reset_combat_input()
	charge_remaining = 0
	charging_button = &""
	guard_time = 0
	threat_time = 0
	decision = 0
	jump_requested = false
	dodge_requested = false
