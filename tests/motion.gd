extends SceneTree
const Spring = preload("res://scripts/pose_spring.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func wait_profile(retrieval: Node, profile: String) -> bool:
	var deadline := Time.get_ticks_msec()+2500
	while Time.get_ticks_msec() < deadline:
		if retrieval.status == "TED-RAG live" and not retrieval.last_decision.is_empty():
			if retrieval.last_decision.profiles[0].id == profile: return true
		# Give the real background process time even with --fixed-fps.
		OS.delay_msec(10)
		await process_frame
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await frames(30)
	var player: CharacterBody3D = world.player
	var visual: Node3D = player.visual
	key(KEY_W,true)
	await frames(12)
	check(visual.pelvis.rotation.x+visual.chest.rotation.x>0.025,"Acceleration pitches the body toward travel")
	check(player.velocity.z < -1.3,"Pose anticipation permits immediate Library-rate acceleration")
	await frames(30)
	key(KEY_SHIFT,true)
	var min_sole := 10.0
	var max_sole := -10.0
	var previous_pose: Vector3 = visual.chest.rotation
	var max_pose_step := 0.0
	for i in range(60):
		await physics_frame
		max_pose_step = maxf(max_pose_step,visual.chest.rotation.distance_to(previous_pose))
		previous_pose = visual.chest.rotation
		for id in ["LeftLeg","RightLeg"]:
			var leg: Node3D = visual.joints[id]
			var knee: Node3D = leg.get_node("Hinge")
			var sole: Vector3 = knee.global_transform*Vector3(0,-0.45,0)
			min_sole = minf(min_sole,sole.y)
			max_sole = maxf(max_sole,sole.y)
	check(min_sole > -0.02 and max_sole > 0.08,"Gait supports feet above ground and lifts the swing foot")
	check(max_pose_step < 0.08,"Walk-to-run torso blending stays continuous")
	key(KEY_D,true)
	var twist := 0.0
	var bank := 0.0
	for i in range(18):
		await physics_frame
		twist = maxf(twist,absf(visual.chest.rotation.y))
		bank = maxf(bank,absf(visual.pelvis.rotation.z))
	check(twist > 0.025 and bank > 0.025,"Turning adds torso yaw lead and lateral weight lean")
	key(KEY_W,false)
	key(KEY_D,false)
	key(KEY_SHIFT,false)
	var brake_pitch := 10.0
	for i in range(30):
		await physics_frame
		brake_pitch = minf(brake_pitch,visual.pelvis.rotation.x+visual.chest.rotation.x)
	check(brake_pitch < -0.015,"Braking counters forward body weight")
	await frames(90)
	check(visual.pelvis.rotation.length()<0.01 and visual.chest.rotation.length()<0.01,"Body settles smoothly after stopping")
	world.controls.jump_requested = true
	await frames(12)
	check(not player.is_on_floor(),"Jump remains responsive with procedural poses")
	var compression := 0.0
	for i in range(90):
		await physics_frame
		compression = maxf(compression,visual.REST_HIP_HEIGHT-visual.pelvis.position.y)
	check(player.is_on_floor() and compression > 0.025,"Landing absorbs impact through hip compression")
	# Compare spring integration across frame rates.
	var coarse := Spring.new()
	var fine := Spring.new()
	for i in range(30): coarse.step(Vector3(0.2,0.1,-0.1),12,1.0/30)
	for i in range(120): fine.step(Vector3(0.2,0.1,-0.1),12,1.0/120)
	check(coarse.value.distance_to(fine.value)<0.00001,"Pose spring is consistent at 30 and 120 Hz")
	# Exercise the real persistent Python worker, not a mocked response.
	player.set_physics_process(false)
	var retrieval: Node = visual.retrieval
	retrieval.context = {"speed":0.2,"grounded":true}
	check(await wait_profile(retrieval,"walk"),"Live TED-RAG selects walking support at low speed")
	retrieval.context = {"speed":0.65,"turn":1.0,"grounded":true}
	check(await wait_profile(retrieval,"corner"),"Live TED-RAG retrieves a corner constraint from turn context")
	var turn_gain: float = retrieval.parameters.yaw_gain
	check(turn_gain>1.1 and retrieval.last_decision.has("constraint"),"TED-RAG weighted constraints change bounded pose parameters")
	retrieval.context = {"speed":0.4,"grounded":true,"landing":1.0}
	check(await wait_profile(retrieval,"land"),"Live TED-RAG updates its decision for landing context")
	check(retrieval.parameters.settle_gain>1.15,"Landing retrieval increases settling strength")
	for i in range(60): visual.animate(1.0/60,Vector3.ZERO,true)
	check(visual.gains.settle_gain>1.1,"Retrieved settings reach the live animation blend")
	var bad := {"schema":1,"engine":"TED-RAG/context_builder","parameters":retrieval.parameters.duplicate()}
	bad.parameters.pitch_gain = 200
	check(not retrieval.accept_response(bad),"Out-of-range retrieval cannot drive a pose")
	var helper_pid: int = retrieval.process_id
	var worker_pid: int = int(retrieval.last_decision.get("worker_pid",-1))
	if helper_pid > 0: OS.kill(helper_pid)
	for i in range(10):
		OS.delay_msec(10)
		await process_frame
	check(retrieval.status.begins_with("local fallback") and is_equal_approx(retrieval.parameters.yaw_gain,1.0),"Helper failure falls back without blocking the game")
	player.set_physics_process(true)
	key(KEY_W,true)
	await frames(30)
	key(KEY_W,false)
	check(player.velocity.length()>3,"Movement continues after retrieval is unavailable")
	world.queue_free()
	await process_frame
	check(helper_pid<=0 or not OS.is_process_running(helper_pid),"Motion helper is not left running")
	check(worker_pid<=0 or not OS.is_process_running(worker_pid),"Child Python interpreter is not left running")
	print("Motion verification: ",failures," failures")
	quit(1 if failures else 0)
