extends SceneTree
## Exercise the real leg geometry and drop/landing physics. Optional -- --capture.
class Intent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	func sample() -> void: pass
	func consume_jump() -> bool:
		var requested := jump
		jump = false
		return requested

var failures := 0
var world: Node3D
var p: CharacterBody3D
var input: Intent
var camera: Camera3D

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func tick() -> void:
	await physics_frame
	await process_frame

func knee_flex(id: String) -> float:
	var leg: Node3D = p.visual.joints[id]
	return (-leg.global_basis.y).angle_to(-leg.get_node("Hinge").global_basis.y)

func cradled() -> bool:
	for id in ["LeftLeg","RightLeg"]:
		var knee: Node3D = p.visual.joints[id].get_node("Hinge")
		var knee_local: Vector3 = p.visual.to_local(knee.global_position)
		var ankle: Vector3 = p.visual.to_local(knee.to_global(Vector3(0,-0.45,0)))
		if knee_local.z < 0.30 or ankle.z < 0.25 or ankle.y < 0.35 or ankle.y > 0.62: return false
	return true

func shot(label: String, side: bool = false) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if camera == null:
		camera = Camera3D.new()
		camera.fov = 44
		root.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute("res://captures")
	var processing := p.is_physics_processing()
	p.set_physics_process(false)
	camera.global_position = p.global_position+p.visual.global_basis*Vector3(3.0,1.0,0.0 if side else 1.7)
	camera.look_at(p.global_position+Vector3(0,0.85,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/fall_"+label+".png")
	p.set_physics_process(processing)

func drop(height: float, label: String, base: Vector3 = Vector3(0,0,6)) -> Dictionary:
	p.position = base+Vector3.UP*height
	p.velocity = Vector3.ZERO
	p.visual._initialized = false
	p.set_physics_process(true)
	var peak := 0.0
	var bend := 0.0
	var land_frame := -1
	var min_sole := 1000.0
	var settled := false
	var falling_shot := false
	for i in range(360):
		await tick()
		if not p.is_on_floor():
			if label == "high" and p.velocity.y < -14 and not falling_shot:
				await shot("moving_fall_high",true)
				falling_shot = true
			continue
		if land_frame < 0: land_frame = i
		var compression: float = p.visual.REST_HIP_HEIGHT-p.visual.pelvis.position.y
		if compression > peak:
			peak = compression
			bend = knee_flex("LeftLeg")
		for id in ["LeftLeg","RightLeg"]:
			var knee: Node3D = p.visual.joints[id].get_node("Hinge")
			min_sole = minf(min_sole,knee.to_global(Vector3(0,-0.45,0)).y-base.y)
		if i == land_frame+8: await shot("landing_"+label,true)
		if i >= land_frame+120:
			settled = absf(compression) < 0.005 and knee_flex("LeftLeg") < deg_to_rad(15)
			break
	check(land_frame >= 0 and settled,"Drop %s lands and returns to the relaxed idle stance" % label)
	check(min_sole >= -0.005,"Landing %s keeps both feet above the surface" % label)
	check(absf(p.visual.last_landing_height-height) < 0.12,"Landing %s measures descent relative to its landing surface" % label)
	var result := {"compression":peak,"bend":rad_to_deg(bend),"height":p.visual.last_landing_height,"speed":p.visual.last_landing_speed}
	print("DROP ",label,": ",result)
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	input = Intent.new()
	world.add_child(input)
	p.controls = input
	p.visual.retrieval.enabled = false
	for i in range(30): await tick()
	p.set_physics_process(false)
	p.position = Vector3(0,10,6)
	var pose_cases := 0
	for yaw in [0.0,PI*0.5,PI,PI*1.5]:
		for speed in [0.0,7.5,10.2]:
			p.visual.rotation.y = yaw
			p.visual._initialized = false
			for i in range(60): p.visual.animate(1.0/60,Vector3(0,-12,speed).rotated(Vector3.UP,yaw),false)
			if cradled(): pose_cases += 1
	check(pose_cases == 12,"Both legs cradle forward at rest/run/sprint across all four facing directions")
	p.visual.rotation.y = 0
	for i in range(60): p.visual.animate(1.0/60,Vector3(0,-12,0),false)
	await shot("cradle_side",true)
	await shot("cradle")
	# A continuous ascent/apex/descent changes the feet smoothly into the cradle.
	p.visual._initialized = false
	for i in range(60): p.visual.animate(1.0/60,Vector3(0,5,0),false)
	var max_step := 0.0
	var previous: Vector3 = p.visual._ankles.LeftLeg
	for i in range(45):
		p.visual.animate(1.0/60,Vector3(0,-i*0.3,0),false)
		var ankle: Vector3 = p.visual._ankles.LeftLeg
		max_step = maxf(max_step,ankle.distance_to(previous))
		previous = ankle
	check(max_step < 0.06 and cradled(),"Apex-to-fall transition tucks forward smoothly without a pose snap")
	# Actual world motion must not drag the air pose behind/above the character.
	p.set_physics_process(true)
	var moving_cases := 0
	for yaw in [0.0,PI*0.5,PI,PI*1.5]:
		for speed in [0.0,10.2,40.0]:
			p.position = Vector3(0,120,6)
			p.velocity = Vector3(0,-12,speed).rotated(Vector3.UP,yaw)
			p.visual.rotation.y = yaw
			p.visual._initialized = false
			for i in range(32): await tick()
			if cradled(): moving_cases += 1
	check(moving_cases == 12,"Real descending motion at 0/10.2/40 m/s preserves the forward cradle across all four facings")
	# Compare drop heights from the same stationary stance, after carried run sway
	# and gait compression have settled out of the preceding momentum cases.
	p.respawn()
	for i in range(120): await tick()
	p.visual.rotation.y = 0
	var small := await drop(0.5,"small")
	var medium := await drop(4.0,"medium")
	var high := await drop(16.0,"high")
	check(medium.compression > small.compression+0.04 and high.compression > medium.compression+0.04,"Higher drops produce progressively deeper landing compression")
	check(medium.bend > small.bend+10 and high.bend > medium.bend+10,"Knee bend increases with the drop height")
	check(high.compression < 0.43 and high.bend < 135,"Large-drop compression stays within a supported crouch")
	await drop(4.0,"rooftop",Vector3(23,3.12,-24))
	# A heavy landing never locks the next jump, and a fresh ascent sheds its crouch.
	p.position = Vector3(0,16,6)
	p.velocity = Vector3.ZERO
	p.visual._initialized = false
	await tick()
	for i in range(180):
		await tick()
		if p.is_on_floor(): break
	input.jump = true
	await tick()
	check(not p.is_on_floor() and p.velocity.y > 7,"Jump responds on the first tick after a heavy landing")
	for i in range(12): await tick()
	check(p.visual._landing < 0.001,"A renewed ascent releases the landing compression")
	# Preserve propulsion/contralateral drive, then recover forward during descent.
	p.position = Vector3(0,40,6)
	p.velocity = Vector3(0,-25,0)
	await tick()
	input.jump = true
	await tick()
	check(p.air_step_count == 1 and is_equal_approx(p.last_sky_impulse.y,p.sky_jump_lift),"A sky step during a fall applies its configured impulse")
	for i in range(32): await tick()
	check(p.velocity.y < 0 and cradled(),"After a falling sky-step kick both legs recover into the forward cradle")
	p.respawn()
	await tick()
	check(p.visual.last_landing_height < 0.1 and p.visual._landing < 0.001,"Respawn clears stale fall height and impact compression")
	world.queue_free()
	if camera != null: camera.queue_free()
	await process_frame
	print("Fall/landing verification: ",failures," failures")
	quit(1 if failures else 0)
