extends "res://scripts/pyramid_enemy_brain.gd"
## Roles react to visible positions and committed attacks, never buffered input.
var memory:=0.0
var last_seen:=Vector3.ZERO
var mode:="rest"

func reset() -> void:
	super.reset()
	memory=0
	mode="rest"

func sample() -> void:
	move=Vector2.ZERO
	sprint=false
	boost=false
	_keyboard_block=false
	if not active or actor.dead or actor.reassemble_time>0 or not actor.encounter.can_fight() or not actor.encounter.same_floor(actor,actor.opponent): return
	var dt:=get_physics_process_delta_time()
	var target: CharacterBody3D=actor.opponent
	var toward:=target.global_position-actor.global_position
	var distance:=Vector2(toward.x,toward.z).length()
	var sight: bool=actor.encounter.line_of_sight(actor,target)
	decision=maxf(0,decision-dt)
	defense_cooldown=maxf(0,defense_cooldown-dt)
	guard_time=maxf(0,guard_time-dt)
	memory=maxf(0,memory-dt)
	if sight and distance<32:
		aggro=true
		last_seen=target.global_position
		memory=6
	if memory<=0 or actor.global_position.distance_to(actor.spawn)>60: aggro=false
	if actor.weapon_combat.is_staggered(): return
	if aggro:
		actor.camera_rig.yaw=atan2(-toward.x,-toward.z)
		if sight and not actor.target_lock.is_locked(): actor.target_lock.select(target)
	else: actor.target_lock.clear()
	var destination: Vector3=last_seen if aggro else actor.spawn
	var caster: bool=actor.enemy_kind in ["ibis","acolyte","skeletal_scribe","charmer","cobra","charm_obelisk"]
	var reach:=11.0 if caster else 3.0 if actor.enemy_kind in ["crocodile","sakhra","skeletal_mummy","riverbound"] else 1.7
	mode="pressure" if aggro else "return"
	if aggro and caster and sight and distance<5 and actor.enemy_kind!="charm_obelisk": move=Vector2(0,.65)
	elif not aggro or not sight or distance>reach:
		var waypoint: Vector3=actor.encounter.next_waypoint(actor.global_position,destination,actor.floor_id)
		var course:=waypoint-actor.global_position
		if Vector2(course.x,course.z).length()>.4 and actor.enemy_kind!="charm_obelisk":
			actor.camera_rig.yaw=atan2(-course.x,-course.z)
			move=Vector2(0,-1)
	if not aggro or not sight: return
	if actor.traits.get("champion",false):
		if not actor.encounter.champion_turn(actor):
			move=Vector2(.8 if actor.enemy_kind=="tefet" else -.8,0)
			mode="flank"
			return
		sprint=true
	var incoming: Dictionary=target.weapon_combat.active_move
	var threat: bool=actor.traits.get("guard",false) and sight and distance<4 and defense_cooldown<=0 and not incoming.is_empty()
	threat_time=threat_time+dt if threat else 0.0
	if threat_time>.23:
		guard_time=.38
		defense_cooldown=1.9
	_keyboard_block=guard_time>0
	if _keyboard_block or decision>0 or not actor.weapon_combat.active_move.is_empty() or not actor.encounter.reserve_attack(actor): return
	var action: StringName=&"attack_right"
	var kind: String=actor.enemy_kind
	if caster:
		if distance>17 or absf(toward.y)>8: return
		if kind in ["ibis","acolyte","skeletal_scribe"]: action=[&"attack_right",&"special_x",&"special_rt_x",&"special_y",&"special_rt_y"][decisions%5]
		elif kind in ["charmer","charm_obelisk"]: action=[&"special_x",&"special_rt_x",&"special_y",&"attack_right"][decisions%4] if kind=="charmer" else &"special_x"
		else: action=&"special_x" if distance>3 else &"attack_right"
	elif kind=="renu" and distance<9:
		action=&"special_rt_y" if actor.encounter.convergence_ready(actor) else &"attack_right"
	elif distance>reach+.9 or absf(toward.y)>2.2: return
	elif kind=="crocodile": action=[&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"][decisions%5]
	elif kind=="cursed_warden": action=&"special_x" if decisions%4==3 else &"attack_right"
	elif actor.traits.get("champion",false) and actor.encounter.convergence_ready(actor): action=&"special_rt_y"
	else: action=&"attack_right" if decisions%2==0 else &"attack_left"
	_request(&"action",action)
	decisions+=1
	decision=2.6 if caster else 2.0 if kind=="crocodile" else 1.5 if actor.traits.get("champion",false) else 1.05
