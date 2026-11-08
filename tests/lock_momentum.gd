extends SceneTree
## Real target selection, movement, camera, timed impacts and collision queries.
const Target = preload("res://scripts/practice_target.gd")
const Library = preload("res://scripts/weapon_library.gd")
class Intent extends Node:
	var source: Node
	var move := Vector2.ZERO
	var look := Vector2.ZERO
	var mouse_look := Vector2.ZERO
	var sprint := false
	var boost := false
	func sample() -> void: pass
	func consume_jump() -> bool: return source.consume_jump()
	func consume_dodge() -> bool: return source.consume_dodge()
	func is_blocking() -> bool: return source.is_blocking()
	func update_combat_hold(delta: float) -> void: source.update_combat_hold(delta)
	func consume_combat_requests() -> Array[Dictionary]: return source.consume_combat_requests()
	func consume_lock_requests() -> Array[Vector2]: return source.consume_lock_requests()
	func reset_combat_input() -> void: source.reset_combat_input()
var failures := 0
var checks := 0
var hz := 60
var world: Node3D
var p: CharacterBody3D
var w: Node
var lock_on: Node3D
var controls: Node
var input: Intent
var center: StaticBody3D
var targets: Array[Node3D] = []
var device := 0
var hit_speeds: Array[float] = []
var hit_amounts: Array[float] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func seconds(time: float) -> void:
	await frames(ceili(time*hz))

func key(code: Key, held: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = held
	event.echo = echo
	controls._unhandled_input(event)

func tap(code: Key) -> void:
	key(code)
	key(code,false)

func pad(held: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = JOY_BUTTON_RIGHT_STICK
	event.pressed = held
	controls._unhandled_input(event)

func target(at: Vector3) -> StaticBody3D:
	var result := Target.new()
	result.actor = p
	result.health = 100000
	result.max_health = 100000
	world.add_child(result)
	result.global_position = at
	targets.append(result)
	return result

func reset_player() -> void:
	p.set_physics_process(true)
	w.set_physics_process(true)
	p.respawn()
	p.position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	input.move = Vector2.ZERO
	input.look = Vector2.ZERO
	input.mouse_look = Vector2.ZERO
	input.sprint = false
	input.boost = false
	world.camera_rig.yaw = 0
	world.camera_rig.pitch = -0.22
	world.camera_rig.reset_follow()
	await seconds(0.5)

func wall(at: Vector3, size: Vector3 = Vector3(2,4,0.3)) -> StaticBody3D:
	var result := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	result.add_child(shape)
	world.add_child(result)
	result.position = at
	return result

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/lock_"+label+".png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	w = p.weapon_combat
	lock_on = p.target_lock
	controls = world.controls
	p.visual.retrieval.enabled = false
	input = Intent.new()
	input.source = controls
	root.add_child(input)
	p.controls = input
	world.camera_rig.controls = input
	var pads := Input.get_connected_joypads()
	if not pads.is_empty(): device = pads[0]
	for original in get_nodes_in_group("combat_targets"): original.queue_free()
	await reset_player()
	p.set_physics_process(false)
	pad()
	pad()
	check(controls.consume_lock_requests() == [Vector2.ZERO],"R3 duplicate/held events emit one lock toggle")
	pad(false)
	pad()
	pad(false)
	check(controls.consume_lock_requests() == [Vector2.ZERO],"A released R3 can toggle again")
	key(KEY_TAB)
	key(KEY_TAB,true,true)
	key(KEY_TAB)
	check(controls.consume_lock_requests() == [Vector2.ZERO],"Tab ignores keyboard repeat/duplicate presses")
	key(KEY_TAB,false)
	for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		controls.sample_target_flick(Vector2.ZERO,device)
		controls.sample_target_flick(direction*0.5,device)
		check(controls.consume_lock_requests().is_empty(),"Soft stick deflection does not switch: "+str(direction))
		controls.sample_target_flick(direction,device)
		controls.sample_target_flick(direction,device)
		controls.sample_target_flick(-direction,device)
		check(controls.consume_lock_requests() == [direction],"One dominant-axis request until neutral: "+str(direction))
	controls.sample_target_flick(Vector2.ZERO,device)
	controls.sample_target_flick(Vector2(0.4,-0.9),device)
	check(controls.consume_lock_requests() == [Vector2.UP],"Diagonal flick chooses its dominant screen direction")
	for code: Key in [KEY_I,KEY_J,KEY_K,KEY_L]: tap(code)
	check(controls.consume_lock_requests() == [Vector2.UP,Vector2.LEFT,Vector2.DOWN,Vector2.RIGHT],"I/J/K/L provide the four keyboard target directions")
	pad()
	controls._on_joy_connection_changed(device,false)
	check(controls.consume_lock_requests().is_empty(),"Disconnect cancels pending controller lock commands")
	tap(KEY_TAB)
	controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(controls.consume_lock_requests().is_empty(),"Focus loss clears pending lock commands")
	p.set_physics_process(true)
	tap(KEY_TAB)
	await frames(2)
	check(not lock_on.is_locked(),"R3/Tab with no targets is safe")
	center = target(Vector3(0,0,-8))
	await frames(3)
	pad()
	pad(false)
	await frames(3)
	check(lock_on.opponent == center and lock_on.marker.visible,"R3 acquires a visible living target and displays brackets")
	await seconds(0.6)
	check(p.visual.global_basis.z.dot(Vector3.FORWARD)>0.999,"Idle character faces the locked enemy")
	var left := target(Vector3(-4,0,-8))
	var right := target(Vector3(4,0,-8))
	var upper := target(Vector3(0,4,-8))
	# Offset the nearer target enough to avoid physically occluding the center.
	var lower := target(Vector3(0.4,0,-3.2))
	await frames(3)
	for spec in [[Vector2.LEFT,left],[Vector2.RIGHT,right],[Vector2.UP,upper],[Vector2.DOWN,lower]]:
		lock_on.select(center)
		await seconds(0.5)
		controls.sample_target_flick(Vector2.ZERO,device)
		controls.sample_target_flick(spec[0],device)
		await frames(1)
		check(lock_on.opponent == spec[1],"Screen-direction flick selects the corresponding target: "+str(spec[0]))
	lock_on.select(right)
	lock_on.switch_target(Vector2.RIGHT)
	check(lock_on.opponent == right,"Flick toward empty space retains the current target")
	for other in [left,right,upper,lower]: other.queue_free()
	await frames(2)
	# Test actual target-relative acceleration, signed travel and facing while moving.
	for mode in [0,1,2]:
		for direction: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2(1,1).normalized(),Vector2(-1,-1).normalized()]:
			await reset_player()
			lock_on.select(center)
			input.move = direction
			input.sprint = mode == 1
			input.boost = mode == 2
			var worst_facing := 1.0
			var worst_alignment := 1.0
			for tick in range(ceili(hz*0.9)):
				await frames(1)
				worst_facing = minf(worst_facing,p.visual.global_basis.z.dot(lock_on.facing()))
				if tick>hz*0.5:
					var expected: Vector3 = lock_on.movement(direction)
					worst_alignment = minf(worst_alignment,Vector3(p.velocity.x,0,p.velocity.z).normalized().dot(expected.normalized()))
			var expected_speed := 3.5 if mode == 0 else (7.5 if mode == 1 else 10.2)
			check(worst_facing>0.999 and worst_alignment>0.97,"Facing held during strafe/backpedal/diagonal, mode %d %s" % [mode,str(direction)])
			check(absf(Vector2(p.velocity.x,p.velocity.z).length()-expected_speed)<0.3 and p.rotation.is_zero_approx(),"Existing speed and unrotated capsule, mode %d %s" % [mode,str(direction)])
	await reset_player()
	lock_on.select(center)
	input.look = Vector2(1,1)
	input.mouse_look = Vector2(200,100)
	await seconds(0.5)
	check(absf(angle_difference(world.camera_rig.yaw,0))<0.02,"Locked camera tracks target instead of consuming look as orbit")
	input.look = Vector2.ZERO
	center.position = Vector3(4,0,-6)
	await seconds(0.6)
	var offset: Vector3 = center.position-p.position
	check(p.visual.global_basis.z.dot(lock_on.facing())>0.999,"Facing tracks a moving opponent without movement input")
	check(absf(angle_difference(world.camera_rig.yaw,atan2(-offset.x,-offset.z)))<0.02,"Camera smoothly follows a moving locked target")
	var projected: Vector2 = world.camera_rig.camera.unproject_position(center.combat_point())
	check(root.get_visible_rect().has_point(projected),"Tracked opponent stays in the camera frame")
	key(KEY_F)
	await frames(2)
	check(w.receive_hit(10,p.position+lock_on.facing()*2+Vector3.UP) == 0 and w.last_parried,"Timed block faces the locked target")
	key(KEY_F,false)
	controls._request(&"action",&"attack_right")
	await frames(3)
	check(w._facing.dot(lock_on.facing())>0.999 and p.visual.global_basis.z.dot(lock_on.facing())>0.999,"Attack hit cone and character use target facing")
	w.cancel()
	controls.jump_requested = true
	await seconds(0.15)
	check(not p.is_on_floor() and p.position.y>0.4 and p.visual.global_basis.z.dot(lock_on.facing())>0.999,"Locked jump retains facing and normal lift")
	controls.jump_requested = true
	await frames(2)
	check(p.air_step_count == 1 and p.velocity.y>8 and lock_on.is_locked(),"Unlimited sky steps retain propulsion while locked")
	input.move = Vector2.LEFT
	controls.dodge_requested = true
	await seconds(0.17)
	check(p.dodge.active and p.dodge.is_invulnerable() and p.visual.global_basis.z.dot(lock_on.facing())>0.999,"Target-relative dodge retains locked facing and hidden invulnerability")
	await seconds(0.3)
	check(not p.dodge.active and lock_on.is_locked(),"Lock persists through phase arrival")
	await reset_player()
	center.position = Vector3(0,0,-8)
	lock_on.select(center)
	await seconds(0.5)
	var target_screen: Vector2 = world.camera_rig.camera.unproject_position(center.combat_point())
	var player_screen: Vector2 = world.camera_rig.camera.unproject_position(p.position+Vector3.UP)
	check(absf(target_screen.x-player_screen.x)>35,"Shoulder camera separates player and enemy silhouettes")
	await shot("tracked")
	var rear_wall := wall(Vector3(0,1.5,3))
	await seconds(0.2)
	check(world.camera_rig.arm.get_hit_length()<3.5,"Locked shoulder camera still retracts against solid walls")
	rear_wall.queue_free()
	await frames(2)
	var side_wall := wall(Vector3(0.8,1.5,0),Vector3(0.3,4,5))
	await seconds(0.5)
	check(world.camera_rig.position.x<0.5,"Shoulder anchor sweeps against adjacent walls instead of entering them")
	side_wall.queue_free()
	await frames(2)
	tap(KEY_TAB)
	await frames(2)
	check(not lock_on.is_locked() and not lock_on.marker.visible,"Tab unlocks and removes the indicator")
	var yaw_before: float = world.camera_rig.yaw
	input.look = Vector2.RIGHT
	await seconds(0.25)
	check(absf(angle_difference(yaw_before,world.camera_rig.yaw))>0.4,"Free right-stick camera control resumes after unlock")
	input.look = Vector2.ZERO
	await reset_player()
	center.hide()
	lock_on.toggle()
	check(not lock_on.is_locked(),"Hidden opponents cannot be acquired")
	center.show()
	center.position.z = 8
	lock_on.toggle()
	check(not lock_on.is_locked(),"Off-screen opponents behind the camera cannot be acquired")
	center.position.z = -34
	lock_on.toggle()
	check(not lock_on.is_locked(),"Distant opponents cannot be acquired")
	center.position.z = -8
	var barrier := wall(Vector3(0,1.5,-4))
	await frames(2)
	lock_on.toggle()
	check(not lock_on.is_locked(),"Solid structures prevent lock acquisition through walls")
	barrier.queue_free()
	await frames(3)
	lock_on.select(center)
	barrier = wall(Vector3(0,1.5,-4))
	await seconds(0.15)
	check(lock_on.is_locked() and not lock_on.marker.visible,"Brief obstruction hides brackets and preserves lock during grace")
	barrier.queue_free()
	await seconds(0.1)
	check(lock_on.is_locked() and lock_on.marker.visible,"Brief obstruction clears without losing the target")
	barrier = wall(Vector3(0,1.5,-4))
	await seconds(0.45)
	check(not lock_on.is_locked(),"Sustained terrain obstruction releases lock")
	barrier.queue_free()
	await frames(2)
	lock_on.select(center)
	center.health = 0
	await frames(2)
	check(not lock_on.is_locked(),"Defeated/rebooting targets release lock")
	center.health = center.max_health
	lock_on.select(center)
	center.position.z = -34
	await frames(2)
	check(not lock_on.is_locked(),"Targets beyond the lock range release lock")
	center.position.z = -8
	lock_on.select(center)
	lock_on._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not lock_on.is_locked(),"Focus loss releases the current lock")
	lock_on.select(center)
	p.respawn()
	check(not lock_on.is_locked(),"Respawn clears lock")
	await reset_player()
	var disposable := target(Vector3(0,0,-6))
	lock_on.select(disposable)
	disposable.queue_free()
	await frames(3)
	check(not lock_on.is_locked(),"Freed opponents cannot leave a dangling lock")
	# Every pulse samples actual current velocity, without moving the actor for a hit.
	await reset_player()
	p.set_physics_process(false)
	w.set_physics_process(false)
	center.position = Vector3(0,0,-1.6)
	await frames(2)
	w.active_move = Library.move(&"down",&"attack_right")
	w._facing = Vector3.FORWARD
	var base: float = w.active_move.damage
	for velocity: Vector3 in [Vector3.ZERO,Vector3(0,0,-3.5),Vector3(0,0,-7.5),Vector3(0,0,-10.2),Vector3(0,12,0),Vector3(30,-40,0)]:
		p.velocity = velocity
		var before: float = center.total_damage
		w.strike()
		var expected: float = base*(1+velocity.length()*0.5/10.2)
		check(absf(center.total_damage-before-expected)<0.001,"Damage follows actual full impact velocity: "+str(velocity))
		check(is_equal_approx(w.last_strike_speed,velocity.length()) and is_equal_approx(w.last_hit_amount,expected),"Impact HUD records applied damage and physical speed: "+str(velocity))
	check(is_equal_approx(w.damage_multiplier(10.2),1.5) and w.damage_multiplier(100)>w.damage_multiplier(50),"Sprint adds 50% damage and accumulated sky momentum keeps scaling")
	var last_speed: float = w.last_strike_speed
	var last_amount: float = w.last_hit_amount
	center.position.z = -20
	await frames(2)
	p.velocity = Vector3.ZERO
	w.strike()
	check(w.last_strike_speed == last_speed and w.last_hit_amount == last_amount,"A missed swing preserves the last successful impact feedback")
	center.position.z = -1.6
	await frames(2)
	# Timed hit path: change velocity after windup, then again before the next pulse.
	w.cancel()
	w.active_move = Library.move(&"left",&"special_x")
	w.elapsed = 0
	w._facing = Vector3.FORWARD
	var spec: Dictionary = w.active_move
	w.hit_landed.connect(func(_t: Node, amount: float, _name: String):
		hit_speeds.append(w.last_strike_speed)
		hit_amounts.append(amount))
	p.velocity = Vector3(0,0,-50)
	w._physics_process(float(spec.hits[0])-0.01)
	check(hit_speeds.is_empty(),"High speed during windup causes no early damage")
	p.velocity = Vector3.ZERO
	w._physics_process(0.02)
	p.velocity = Vector3.UP*12
	w._physics_process(float(spec.hits[1])-float(spec.hits[0]))
	p.velocity = Vector3(0,0,-10.2)
	w._physics_process(float(spec.hits[2])-float(spec.hits[1]))
	check(hit_speeds.size() == 3 and is_equal_approx(hit_speeds[0],0) and is_equal_approx(hit_speeds[1],12) and is_equal_approx(hit_speeds[2],10.2),"Multihit skill resamples changed speed at all three contact times")
	check(is_equal_approx(hit_amounts[0],float(spec.damage)) and is_equal_approx(hit_amounts[2],float(spec.damage)*1.5),"Windup speed never gets cached as the impact bonus")
	check(not get_nodes_in_group("damage_numbers").is_empty(),"Actual damage creates visible impact numbers")
	await shot("impact")
	for i in range(32): center.receive_hit(1,p.position)
	check(get_nodes_in_group("damage_numbers").size()<=24,"Floating impact numbers stay bounded during multihits")
	await seconds(1)
	check(get_nodes_in_group("damage_numbers").is_empty(),"Impact numbers expire cleanly")
	w.cancel()
	p.velocity = Vector3.ZERO
	center.position.z = -8
	p.dodge.cooldown = 0
	check(p.dodge.start(Vector3.FORWARD),"Phase dodge still accepts a normal direction")
	p.dodge.advance(0.17)
	check(p.dodge.is_invulnerable() and p.velocity.is_zero_approx(),"Teleport displacement grants no fake impact velocity and keeps its invulnerability")
	p.dodge.cancel()
	# One live sprint/contact verifies post-movement velocity in the real pipeline.
	await reset_player()
	center.position = Vector3(0,0,-8)
	p.position = Vector3(0,0,-4)
	lock_on.select(center)
	await seconds(0.25)
	input.move = Vector2.UP
	input.boost = true
	p.velocity = Vector3.FORWARD*10.2
	controls._request(&"weapon",&"down")
	controls._request(&"action",&"attack_right")
	var before_hits: int = center.hit_count
	await seconds(0.24)
	check(center.hit_count == before_hits+1 and is_equal_approx(w.last_strike_speed,10.2) and is_equal_approx(w.last_hit_amount,36),"Real sprint strike lands for 36 instead of the standing 24 damage")
	await shot("sprint_impact")
	input.move = Vector2.ZERO
	await seconds(0.7)
	var hud: Control = world.find_child("CombatHUD",true,false)
	check(root.get_visible_rect().encloses(hud.lock_status.get_global_rect()) and root.get_visible_rect().encloses(hud.impact.get_global_rect()),"Lock and impact HUD labels fit the viewport")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Lock/momentum regression @",hz," Hz: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
