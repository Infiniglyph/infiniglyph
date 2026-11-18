extends "res://scripts/pyramid_enemy_brain.gd"
## Pursues observed positions and uses the player's collision-tested Sky Jumps.
var jump_cooldown := 0.0
var memory := 0.0
var last_seen := Vector3.ZERO
var mode := "rest"
var sky_steps := 0

func reset() -> void:
	super.reset()
	jump_cooldown=0
	memory=0
	mode="rest"
	jump_requested=false

func sample() -> void:
	move=Vector2.ZERO
	sprint=false
	boost=false
	_keyboard_block=false
	if not active or actor.dead or not actor.encounter.can_fight() or not actor.encounter.same_floor(actor,actor.opponent): return
	var delta:=get_physics_process_delta_time()
	var target: CharacterBody3D=actor.opponent
	var toward:=target.global_position-actor.global_position
	var distance:=Vector2(toward.x,toward.z).length()
	var sight: bool=actor.encounter.line_of_sight(actor,target)
	decision=maxf(0,decision-delta)
	defense_cooldown=maxf(0,defense_cooldown-delta)
	guard_time=maxf(0,guard_time-delta)
	jump_cooldown=maxf(0,jump_cooldown-delta)
	memory=maxf(0,memory-delta)
	if sight and distance<27:
		aggro=true
		last_seen=target.global_position
		memory=5
	if memory==0 or actor.global_position.distance_to(actor.spawn)>52: aggro=false
	if actor.weapon_combat.is_staggered(): return
	if aggro:
		actor.camera_rig.yaw=atan2(-toward.x,-toward.z)
		if not actor.target_lock.is_locked() and sight: actor.target_lock.select(target)
		if not sight: actor.target_lock.clear()
	else: actor.target_lock.clear()
	var destination: Vector3=last_seen if aggro else actor.spawn
	var waypoint: Vector3=actor.encounter.next_waypoint(actor.global_position,destination,actor.floor_id)
	var course:=waypoint-actor.global_position
	if actor.enemy_kind=="archer":
		mode="draw" if aggro and sight else "search"
		if aggro and sight and distance<6:
			move=Vector2(0,1)
		elif not aggro or not sight or distance>16:
			if Vector2(course.x,course.z).length()>.4:
				actor.camera_rig.yaw=atan2(-course.x,-course.z)
				move=Vector2(0,-1)
		if aggro and sight and distance>=5 and distance<19 and decision<=0 and actor.weapon_combat.active_move.is_empty() and actor.encounter.reserve_attack(actor):
			_request(&"action",&"special_x")
			decision=2.0
			decisions+=1
		return
	mode="aerial approach" if aggro else "return"
	sprint=aggro
	if (not aggro or distance>2.0 or not sight) and Vector2(course.x,course.z).length()>.4:
		actor.camera_rig.yaw=atan2(-course.x,-course.z)
		move=Vector2(0,-1)
	if aggro and sight:
		var desired:=clampf(target.global_position.y+2.8,actor.floor_y+3,actor.ceiling_y-3)
		var roof_clear: bool=actor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.combat_point(),actor.combat_point()+Vector3.UP*2.4,1,[actor.get_rid(),target.get_rid()])).is_empty()
		if jump_cooldown<=0 and roof_clear and actor.global_position.y<desired-1.1 and actor.velocity.y<2 and not actor.weapon_combat.active_move.get("dive",false):
			jump_requested=true
			# A quick second air step arrests a descent before resuming the normal
			# climbing cadence; every impulse still passes through Player physics.
			jump_cooldown=.10 if actor.velocity.y < -3.5 else .22
			if not actor.is_on_floor(): sky_steps+=1
	var incoming: Dictionary=target.weapon_combat.active_move
	var threat: bool=actor.enemy_kind=="falcon" and sight and distance<3.5 and defense_cooldown<=0 and not incoming.is_empty() and target.weapon_combat.elapsed<float(incoming.hits[0])
	threat_time=threat_time+delta if threat else 0.0
	if threat_time>.22:
		guard_time=.30
		defense_cooldown=1.5
	_keyboard_block=guard_time>0
	if not aggro or not sight or _keyboard_block or decision>0 or not actor.weapon_combat.active_move.is_empty() or not actor.encounter.reserve_attack(actor): return
	var height: float=actor.global_position.y-target.global_position.y
	var action: StringName
	if actor.enemy_kind=="falcon" and height>2.0 and height<9 and distance<7 and (target.global_position.y>actor.floor_y+1 or decisions%3==0):
		action=&"special_y"
		mode="dive"
	elif absf(height)<1.7 and distance<3.1:
		action=&"special_x" if actor.enemy_kind=="falcon" and decisions%3==2 else &"attack_left" if decisions%2==1 else &"attack_right"
		mode="wing slash" if action==&"special_x" else "air step combo"
	else: return
	_request(&"action",action)
	decision=1.5 if action==&"special_y" else .95
	decisions+=1
