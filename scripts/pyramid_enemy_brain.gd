extends "res://scripts/player_input.gd"
## Reads visible attacks after a reaction delay. Uses normal locomotion and the
## shared input/guard/parry pipeline; never applies damage directly.
var actor: CharacterBody3D
var decision := .8
var guard_time := 0.0
var defense_cooldown := 0.0
var threat_time := 0.0
var decisions := 0
var active := false
var aggro := false
var _path_clock := 0.0
var _waypoint := Vector3.ZERO

func _ready() -> void: pass
func _unhandled_input(_event: InputEvent) -> void: pass

func reset() -> void:
	reset_combat_input()
	move = Vector2.ZERO
	_keyboard_block = false
	aggro = false
	guard_time = 0
	threat_time = 0
	decision = .8

func on_forced_reaction() -> void:
	reset_combat_input()
	guard_time = 0
	threat_time = 0
	decision = .5

func sample() -> void:
	move = Vector2.ZERO
	sprint = false
	boost = false
	_keyboard_block = false
	if not active or actor.dead or not actor.encounter.can_fight(): return
	var opponent: CharacterBody3D = actor.opponent
	var delta := get_physics_process_delta_time()
	var toward := opponent.global_position-actor.global_position
	var distance := Vector2(toward.x,toward.z).length()
	var sight: bool = actor.encounter.line_of_sight(actor,opponent)
	if distance<15 and sight: aggro = true
	if actor.global_position.distance_to(actor.spawn)>28 or absf(toward.y)>5: aggro = false
	var destination: Vector3 = opponent.global_position if aggro else actor.spawn
	if actor.weapon_combat.is_staggered(): return
	decision = maxf(0,decision-delta)
	defense_cooldown = maxf(0,defense_cooldown-delta)
	guard_time = maxf(0,guard_time-delta)
	if aggro:
		actor.camera_rig.yaw = atan2(-toward.x,-toward.z)
		if not actor.target_lock.is_locked(): actor.target_lock.select(opponent)
	else:
		actor.target_lock.clear()
	_path_clock -= delta
	if _path_clock<=0:
		_waypoint = actor.encounter.next_waypoint(actor.global_position,destination)
		_path_clock = .3
	var course := _waypoint-actor.global_position
	if not aggro or distance>1.85 or not sight:
		if course.length()>.35:
			actor.camera_rig.yaw = atan2(-course.x,-course.z)
			move = Vector2(0,-1)
		return
	var incoming: Dictionary = opponent.weapon_combat.active_move
	var threat: bool = actor.enemy_kind=="jackal" and defense_cooldown<=0 and not incoming.is_empty() and opponent.weapon_combat.elapsed<float(incoming.hits[0])
	threat_time = threat_time+delta if threat else 0.0
	if threat_time>.22:
		defense_cooldown = 1.35
		if decisions%3!=2: guard_time = .32
	_keyboard_block = guard_time>0
	if _keyboard_block or not actor.weapon_combat.active_move.is_empty() or decision>0 or not actor.encounter.reserve_attack(actor): return
	var action: StringName = &"attack_right" if decisions%2==0 else &"attack_left"
	_request(&"action",action)
	decisions += 1
	decision = 1.05 if actor.enemy_kind=="jackal" else 1.25
