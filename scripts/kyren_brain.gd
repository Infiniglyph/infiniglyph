extends "res://scripts/sparring_brain.gd"
## Skilled input-contract AI. Reads visible actions, never the opponent's inputs.
var rng := RandomNumberGenerator.new()
var seen_serial := -1
var reaction_delay := .16
var sight := false
var _sight_clock := 0.0
var observed: Dictionary = {}
var favored := ""
var behavior := "resting"

func _ready() -> void: rng.randomize()

func observe(move: Dictionary) -> void:
	var key := String(move.get("action",move.get("name","")))
	observed[key] = int(observed.get(key,0))+1
	if favored.is_empty() or observed[key]>int(observed.get(favored,0)): favored=key

func can_see() -> bool:
	if not is_instance_valid(opponent): return false
	var ray := PhysicsRayQueryParameters3D.create(actor.combat_point(),opponent.combat_point(),9,[actor.get_rid(),opponent.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func navigate(toward: Vector3) -> void:
	var direction := Vector3(toward.x,0,toward.z).normalized()
	if direction.is_zero_approx(): return
	actor.camera_rig.yaw = atan2(-direction.x,-direction.z)
	move = Vector2(0,-1)
	if actor.test_move(actor.global_transform,direction*.7):
		var found := false
		for angle in [.65,-.65,1.2,-1.2,1.7,-1.7]:
			var alternative := direction.rotated(Vector3.UP,angle)
			if not actor.test_move(actor.global_transform,alternative*.9):
				actor.camera_rig.yaw = atan2(-alternative.x,-alternative.z)
				found = true
				break
		if not found and sky_cooldown<=0:
			jump_requested = true
			sky_cooldown = .5

func sample() -> void:
	move = Vector2.ZERO
	boost = false
	sprint = false
	_keyboard_block = false
	var delta := get_physics_process_delta_time()
	sky_cooldown = maxf(0,sky_cooldown-delta)
	if not active or not is_instance_valid(opponent): return
	if actor.weapon_combat.is_staggered():
		behavior = "recovering"
		return
	var salt: float = actor.encounter.salt.value
	var pressure := salt/100
	var toward := opponent.global_position-actor.global_position
	var distance := Vector2(toward.x,toward.z).length()
	_sight_clock -= delta
	if _sight_clock<=0:
		_sight_clock = .1
		sight = can_see()
	actor.camera_rig.yaw = atan2(-toward.x,-toward.z)
	if sight and not actor.target_lock.is_locked() and distance<actor.target_lock.RANGE: actor.target_lock.select(opponent)
	decision = maxf(0,decision-delta)
	defense_cooldown = maxf(0,defense_cooldown-delta)
	guard_time = maxf(0,guard_time-delta)
	_keyboard_block = guard_time>0
	var incoming: Dictionary = opponent.weapon_combat.active_move if sight else {}
	var threat := not incoming.is_empty() and distance<float(incoming.reach)+.65 and absf(toward.y)<3
	if threat:
		if seen_serial!=opponent.weapon_combat.attack_serial:
			seen_serial=opponent.weapon_combat.attack_serial
			threat_time = 0
			reaction_delay = rng.randf_range(.12,.23)
		threat_time += delta
	else: threat_time = 0
	if threat and threat_time>=reaction_delay and defense_cooldown==0:
		var until: float = float(incoming.hits[0])-opponent.weapon_combat.elapsed
		if until>0 and until<.22 and rng.randf()<.70:
			defense_cooldown = rng.randf_range(.65,1.1)
			if rng.randf()<.36:
				move = Vector2(circle,.3).normalized()
				dodge_requested = true
				circle *= -1
				behavior = "sidestep"
			else:
				guard_time = until+.15
				_keyboard_block = true
				behavior = "timed guard"
			return
	if actor.dodge.active or _keyboard_block: return
	if charge_remaining>0:
		charge_remaining=maxf(0,charge_remaining-delta)
		behavior="charging"
		move=Vector2(circle*.18,0)
		if charge_remaining==0:
			_special(charging_button,-1,false)
			charging_button=&""
		return
	if not sight:
		behavior="seeking"
		navigate(toward)
		return
	if sky_cooldown==0 and toward.y>1.3 and (actor.is_on_floor() or actor.velocity.y<2):
		jump_requested=true
		sky_cooldown=.45
	var comfortable := lerpf(3.4,2.5,pressure)
	# Adapt to executed, visible history; never inspect buffered player input.
	var learned: bool = pressure>=.25 and int(observed.get(favored,0))>=3
	if learned and favored.begins_with("special_"): comfortable=2.3
	elif learned and favored.begins_with("attack_") and not incoming.is_empty(): comfortable=4.6
	if distance>comfortable:
		move=Vector2(circle*.1,-1).normalized()
		sprint=distance>5
		boost=distance>10
	elif distance<1.5: move=Vector2(circle*.45,.5)
	else: move=Vector2(circle*lerpf(.4,.22,pressure),0)
	behavior="pressure" if pressure>=.5 else "measuring"
	if not actor.weapon_combat.active_move.is_empty() or decision>0: return
	if absf(toward.y)>2.8 or distance>8: return
	var action: StringName
	var roll := rng.randf()
	if distance>5: action = &"special_x" if roll<.55 else &"special_rt_y"
	elif learned and favored.begins_with("attack_") and distance>3.7: action=&"special_rt_y"
	elif roll<lerpf(.22,.42,pressure): action=[&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"][rng.randi_range(0,3)]
	else: action=&"attack_left" if rng.randf()<.32 else &"attack_right"
	var spec: Dictionary = actor.weapon_combat.move_for(&"right",action)
	if distance>float(spec.reach)+(3.0 if spec.has("dash") else -.3): return
	if String(action).begins_with("special_") and rng.randf()<.30:
		_keyboard_modifier=String(action).contains("rt_")
		charging_button=&"x" if String(action).ends_with("x") else &"y"
		_special(charging_button)
		_keyboard_modifier=false
		charge_remaining=rng.randf_range(.5,1.2)
	else: _request(&"action",action)
	decisions += 1
	decision=float(spec.duration)+rng.randf_range(.12,.48)*(1-pressure*.5)
	if decisions%3==0: circle *= -1
