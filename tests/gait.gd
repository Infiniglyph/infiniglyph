extends SceneTree
## Feed fractional stick intent through the real player physics, without replacing
## a connected hardware device. Rendering is optional: pass -- --capture.
class StickIntent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	func sample() -> void: pass
	func consume_jump() -> bool: return false

var failures := 0
var world: Node3D
var stick: StickIntent
var camera: Camera3D

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func set_stick(deflection: float) -> void:
	stick.move = world.controls.filtered(Vector2(0,-deflection))
	stick.sprint = stick.move.length()>0.72

func knee_angle(id: String) -> float:
	var leg: Node3D = world.player.visual.joints[id]
	var knee: Node3D = leg.get_node("Hinge")
	return (-leg.global_basis.y).angle_to(-knee.global_basis.y)

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if camera == null:
		camera = Camera3D.new()
		camera.fov = 48
		root.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute("res://captures")
	camera.global_position = world.player.global_position+Vector3(2.6,1.2,2.6)
	camera.look_at(world.player.global_position+Vector3(0,0.9,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/gait_"+label+".png")

func measure(deflection: float, label: String) -> Dictionary:
	set_stick(0)
	world.player.position = world.player.spawn
	world.player.velocity = Vector3.ZERO
	await frames(90)
	set_stick(deflection)
	await frames(60)
	var visual: Node3D = world.player.visual
	var previous_phase: float = visual.phase
	var turns := 0.0
	var double_support := 0
	var max_sole := -100.0
	var min_sole := 100.0
	var elbow := 0.0
	var hip_height := 0.0
	for i in range(180):
		await physics_frame
		turns += angle_difference(previous_phase,visual.phase)
		previous_phase = visual.phase
		if visual._feet.LeftLeg.planted and visual._feet.RightLeg.planted: double_support += 1
		for id in ["LeftLeg","RightLeg"]:
			var knee: Node3D = visual.joints[id].get_node("Hinge")
			var sole: Vector3 = knee.global_transform*Vector3(0,-0.45,0)
			min_sole = minf(min_sole,sole.y)
			max_sole = maxf(max_sole,sole.y)
		elbow += absf(visual.joints.RightArm.get_node("Hinge").rotation.x)
		hip_height += visual.pelvis.position.y
		if i == 85: await shot(label)
	var speed: float = Vector2(world.player.velocity.x,world.player.velocity.z).length()
	var expected: float = world.controls.filtered(Vector2(0,-deflection)).length()*(7.5 if stick.sprint else 3.5)
	check(is_equal_approx(speed,expected),"Existing analog movement speed preserved: "+label)
	check(min_sole > -0.025,"Feet stay above the flat ground: "+label)
	var result := {"cadence":turns/(3*TAU),"double_support":double_support,"lift":max_sole,"elbow":elbow/180,"height":hip_height/180}
	print(label,": ",result)
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	stick = StickIntent.new()
	world.add_child(stick)
	world.player.controls = stick
	world.player.visual.retrieval.enabled = false  # Deterministic visual metrics.
	await frames(120)
	var worst_idle := maxf(knee_angle("LeftLeg"),knee_angle("RightLeg"))
	print("Initial idle knee flexion: ",rad_to_deg(worst_idle)," degrees")
	check(worst_idle < deg_to_rad(15),"Idle knees have a small relaxed bend rather than a crouch")
	check(worst_idle > deg_to_rad(2),"Idle legs do not lock or hyperextend")
	await shot("idle")
	var slow := await measure(0.28,"slow_walk")
	var walk := await measure(0.58,"walk")
	var run := await measure(0.90,"run")
	check(slow.cadence<walk.cadence and walk.cadence<run.cadence,"Walking step rate scales with low analog speed")
	check(slow.double_support>0 and walk.double_support>0 and run.double_support==0,"Walking has double support; running has shorter contacts")
	check(slow.lift<0.09 and walk.lift<0.12 and run.lift>walk.lift+0.04,"Walking keeps feet lower than the running recovery")
	check(walk.elbow<run.elbow-0.2 and walk.height>run.height+0.025,"Walking uses relaxed arms and a more upright stance")
	# Cross the existing controller walk/run boundary, then stop at an arbitrary phase.
	set_stick(0.70)
	await frames(60)
	var previous: Vector3 = world.player.visual.chest.rotation
	var largest_change := 0.0
	set_stick(0.82)
	for i in range(40):
		await physics_frame
		var current: Vector3 = world.player.visual.chest.rotation
		largest_change = maxf(largest_change,current.distance_to(previous))
		previous = current
	check(largest_change<0.08,"Walking blends into running without a torso snap")
	set_stick(0)
	await frames(180)
	var visual: Node3D = world.player.visual
	check(maxf(knee_angle("LeftLeg"),knee_angle("RightLeg"))<deg_to_rad(15),"Stopping returns both knees to the relaxed idle stance")
	check(absf(visual.pelvis.position.x)<0.002,"Idle recenters weight after either support foot")
	await shot("idle_after_run")
	world.queue_free()
	if camera != null: camera.queue_free()
	await process_frame
	print("Idle/walk verification: ",failures," failures")
	quit(1 if failures else 0)
