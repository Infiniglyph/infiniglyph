extends SceneTree
const Neon = preload("res://scripts/neon.gd")
class Intent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	func sample() -> void: pass
	func consume_jump() -> bool:
		var value := jump
		jump = false
		return value

var world: Node3D
var p: CharacterBody3D
var input: Intent
var failures := 0

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func tick() -> void:
	await physics_frame
	await process_frame

func place(at: Vector3, motion: Vector3 = Vector3.ZERO) -> void:
	input.move = Vector2.ZERO
	input.boost = false
	p.position = at
	p.velocity = Vector3.ZERO
	await tick()
	p.velocity = motion

func wait_profile(retrieval: Node, profile: String) -> bool:
	var deadline := Time.get_ticks_msec()+2500
	while Time.get_ticks_msec()<deadline:
		if retrieval.status=="TED-RAG live" and not retrieval.last_decision.is_empty():
			if retrieval.last_decision.profiles[0].id==profile: return true
		OS.delay_msec(10)
		await process_frame
	return false

func trajectory(hz: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	await place(Vector3(1000,5000,0))
	p.position = Vector3(1000,5000,0)
	p.velocity = Vector3(6,20,0)
	input.move = Vector2(0.5,0)
	world.camera_rig.yaw = 0
	var start := p.position
	for i in range(hz):
		if i % (hz/5) == 0: input.jump = true
		await tick()
	return {"displacement":p.position-start,"velocity":p.velocity}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	input = Intent.new()
	world.add_child(input)
	p.controls = input
	await frames(45)
	# Sprint remains analog; the existing ground controller is unchanged.
	input.move = Vector2(0,-0.5)
	input.boost = true
	await frames(90)
	check(absf(p.velocity.length()-5.1)<0.01,"Half input produces half sprint speed")
	input.move = Vector2(0,-1)
	await frames(60)
	check(absf(p.velocity.length()-10.2)<0.01,"Full input preserves the established sprint speed")
	input.move = Vector2.ZERO
	input.boost = false
	await frames(12)
	check(float(p.visual.retrieval.context.boost)>0.5 and float(p.visual.retrieval.context.acceleration)<-0.5,"Sprint braking context remains available to asynchronous retrieval")
	# Isolate posing to inspect both leg/arm pairings and continuity on re-trigger.
	p.set_physics_process(false)
	var visual: Node3D = p.visual
	for side in [-1,1]:
		var before: Vector3 = visual.chest.rotation
		visual.trigger_air_step(side,Vector3(2,7.5,-2),2)
		check(visual.chest.rotation.is_equal_approx(before),"Sky step does not reset the current torso pose: %s" % side)
		for i in range(9): visual.animate(1.0/60,Vector3(4,10,-4),false)
		var left: float = visual.joints.LeftArm.rotation.x
		var right: float = visual.joints.RightArm.rotation.x
		check(right<left-0.3 if side == -1 else left<right-0.3,"Opposite arm drives forward for the stepping leg: %s" % side)
	p.set_physics_process(true)
	await place(Vector3(0,100,0),Vector3(20,10,0))
	world.camera_rig.yaw = PI*0.5
	input.move = Vector2(0,-1)
	input.jump = true
	await tick()
	check(p.last_sky_impulse.is_equal_approx(Vector3(-p.sky_jump_push,p.sky_jump_lift,0)),"Air impulse follows camera-relative input")
	check(p.velocity.x>0 and p.velocity.x<20,"Opposing impulse first reduces carried velocity")
	check(p.velocity.y>17,"Air jump adds lift instead of replacing vertical velocity")
	var glass: Node3D = p._glass_steps.back()
	check(glass.global_basis.y.normalized().dot(p.last_sky_impulse.normalized())>0.999,"Glass surface normal follows the propulsion direction")
	var small_scale := glass.global_basis.get_scale().length()
	for i in range(5):
		input.jump = true
		await tick()
	check(p.velocity.x<0,"Repeated opposing impulses reverse midair motion")
	var previous_y := p.velocity.y
	await tick()
	check(absf(previous_y-p.velocity.y-p.gravity/60)<0.001,"Gravity continues between air jumps")
	var ordinary_push: float = p.sky_jump_push
	p.sky_jump_push = 12
	input.jump = true
	await tick()
	glass = p._glass_steps.back()
	check(glass.global_basis.get_scale().length()>small_scale,"Stronger impulses produce a stronger glass response")
	p.sky_jump_push = ordinary_push
	check(p.velocity.length()>p.boost_speed*3,"Accumulated motion exceeds grounded sprint speed without a cap")
	# Thin isolated fixtures exercise full kinematic motion sweeps at 2000 m/s.
	input.move = Vector2.ZERO
	world.camera_rig.yaw = 0
	var wall: Node3D = Neon.block(world,Vector3(1006,50,0),Vector3(0.1,100,20))
	await place(Vector3(1000,10,0),Vector3(2000,0,0))
	input.move = Vector2(1,0)
	await frames(3)
	check(p.position.x<1005.70 and absf(p.velocity.x)<1,"High-speed sweep does not tunnel through a 0.1m wall")
	wall.queue_free()
	await process_frame
	var ceiling: Node3D = Neon.block(world,Vector3(1000,20,0),Vector3(30,0.1,30))
	await place(Vector3(1000,10,0),Vector3(0,2000,0))
	await frames(3)
	check(p.position.y<18.15 and p.velocity.y<=0,"High-speed upward motion respects a thin ceiling")
	ceiling.queue_free()
	await process_frame
	var floor_body: Node3D = Neon.block(world,Vector3(1000,-0.05,0),Vector3(50,0.1,50))
	await place(Vector3(1000,100,0),Vector3(25,-2000,0))
	await frames(6)
	check(p.is_on_floor() and p.position.y>-0.04,"High-speed landing does not tunnel through a thin floor")
	check(p.velocity.x>23,"Landing retains horizontal momentum for normal ground braking")
	check(float(visual.retrieval.context.impact)>0.9,"High-speed landing supplies an impact retrieval context")
	check(world.camera_rig.global_position.distance_to(p.position+Vector3(0,1.35,0))<=2.01,"Camera keeps the player framed at extreme velocity")
	input.jump = true
	await frames(2)
	check(not p.is_on_floor() and p.velocity.y>7,"High-speed landing does not lock the next jump")
	floor_body.queue_free()
	await process_frame
	var slow := await trajectory(30)
	var fast := await trajectory(120)
	check((slow.velocity as Vector3).distance_to(fast.velocity)<0.001,"30/120 Hz physics produce matching accumulated velocity")
	check((slow.displacement as Vector3).distance_to(fast.displacement)<0.31,"30/120 Hz displacement stays within the documented Euler tolerance")
	print("30/120 Hz displacement difference over one second: ",(slow.displacement as Vector3).distance_to(fast.displacement)," m")
	check(absf(fast.velocity.x-(6+5*0.5*p.sky_jump_push))<0.001 and absf(fast.velocity.y-(20+5*p.sky_jump_lift-p.gravity))<0.001,"Jump accumulation matches impulse and gravity totals")
	Engine.physics_ticks_per_second = 60
	p.set_physics_process(false)
	var retrieval: Node = visual.retrieval
	var cases := [
		["sprint",{"speed":1,"boost":1,"grounded":true}],
		["sprint_launch",{"speed":0.65,"acceleration":1,"boost":1,"grounded":true}],
		["sprint_brake",{"speed":0.65,"acceleration":-1,"boost":1,"grounded":true}],
		["sprint_corner",{"speed":1,"turn":1,"boost":1,"grounded":true}],
		["ground_air",{"speed":0.65,"transition":1,"grounded":false}],
		["sky_push",{"speed":0.5,"propulsion":1,"grounded":false}],
		["sky_chain",{"speed":0.7,"propulsion":1,"repetition":1,"grounded":false}],
		["air_reverse",{"speed":0.7,"acceleration":-1,"reversal":1,"grounded":false}],
		["sky_reverse",{"speed":0.7,"acceleration":-1,"propulsion":1,"repetition":0.5,"reversal":1,"grounded":false}],
		["land_fast",{"speed":0.5,"landing":1,"impact":1,"grounded":true}]]
	for spec in cases:
		retrieval.context = spec[1]
		check(await wait_profile(retrieval,spec[0]),"Live TED-RAG profile: "+spec[0])
	p.set_physics_process(true)
	var live := await trajectory(60)
	var helper_pid: int = retrieval.process_id
	if helper_pid>0: OS.kill(helper_pid)
	for i in range(15):
		OS.delay_msec(10)
		await process_frame
	check(retrieval.status.begins_with("local fallback"),"TED-RAG failure falls back during aerial movement")
	retrieval.enabled = false
	var fallback := await trajectory(60)
	check((live.velocity as Vector3).distance_to(fallback.velocity)<0.001 and (live.displacement as Vector3).distance_to(fallback.displacement)<0.001,"TED-RAG enabled/disabled gives identical movement physics")
	check(float(retrieval.parameters.pitch_gain)==1.0,"Disabled retrieval restores default pose weights")
	world.queue_free()
	await process_frame
	print("Phase 002 verification: ",failures," failures")
	quit(1 if failures else 0)
