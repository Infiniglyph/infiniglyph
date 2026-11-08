extends SceneTree
## Check anatomical facing from the posed elbow, independently of the yaw formula.
## Also record physical motion so a visual fix can be compared with its baseline.
var failures := 0
var motion: Array = []

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func planar(value: Vector3) -> Vector3:
	return Vector3(value.x, 0, value.z)

func anatomical_forward(visual: Node3D) -> Vector3:
	var arm: Node3D = visual.joints["RightArm"]
	var elbow: Node3D = arm.get_node("Hinge")
	var upper := -arm.global_basis.y.normalized()
	var lower := -elbow.global_basis.y.normalized()
	# The elbow flexes toward the front, perpendicular to its upper arm.
	return planar(lower - upper * lower.dot(upper)).normalized()

func record(player: CharacterBody3D) -> void:
	motion.append([player.position.x, player.position.y, player.position.z,
		player.velocity.x, player.velocity.y, player.velocity.z])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await frames(30)
	var player: CharacterBody3D = world.player
	var cases := [
		["forward", [KEY_W], Vector3.FORWARD],
		["backward", [KEY_S], Vector3.BACK],
		["left", [KEY_A], Vector3.LEFT],
		["right", [KEY_D], Vector3.RIGHT],
		["forward-left", [KEY_W, KEY_A], Vector3(-1,0,-1).normalized()],
		["forward-right", [KEY_W, KEY_D], Vector3(1,0,-1).normalized()],
		["backward-left", [KEY_S, KEY_A], Vector3(-1,0,1).normalized()],
		["backward-right", [KEY_S, KEY_D], Vector3(1,0,1).normalized()]]
	for yaw in [0.0, PI/2, PI]:
		for running in [false, true]:
			for spec in cases:
				player.position = player.spawn
				player.velocity = Vector3.ZERO
				world.camera_rig.yaw = yaw
				await frames(20)
				var start := player.position
				for code in spec[1]: key(code, true)
				key(KEY_SHIFT, running)
				for tick in range(75):
					await physics_frame
					record(player)
				for code in spec[1]: key(code, false)
				key(KEY_SHIFT, false)
				var expected: Vector3 = spec[2].rotated(Vector3.UP, yaw)
				var label := "%s / yaw %.2f / run %s" % [spec[0], yaw, running]
				check(planar(player.position-start).normalized().dot(expected)>0.999, "Travel direction: " + label)
				check(anatomical_forward(player.visual).dot(expected)>0.999, "Anatomical facing: " + label)
				check(is_equal_approx(planar(player.velocity).length(), 7.5 if running else 3.5), "Speed: " + label)
				check(player.rotation.is_zero_approx(), "Collision body stays unrotated: " + label)
				check(is_equal_approx(world.camera_rig.yaw,yaw), "Camera yaw unaffected: " + label)
				# Settle without input before teleporting into the next case.
				await frames(20)
	# Headless Godot cannot capture a real mouse; feed the existing look-intent field.
	player.position = player.spawn
	player.velocity = Vector3.ZERO
	world.camera_rig.yaw = 0
	await frames(20)
	key(KEY_W,true)
	key(KEY_D,true)
	for tick in range(30):
		world.controls.mouse_look += Vector2(12,0)
		await physics_frame
		record(player)
	await frames(45)
	check(absf(world.camera_rig.yaw)>0.5,"Camera look intent rotates the camera during movement")
	check(anatomical_forward(player.visual).dot(planar(player.velocity).normalized())>0.999,"Facing follows travel after a moving camera turn")
	key(KEY_W,false)
	key(KEY_D,false)
	var baseline_path := "res://.godot/facing_momentum_baseline.json"
	if "--record-baseline" in OS.get_cmdline_user_args():
		var file := FileAccess.open(baseline_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(motion))
		file.close()
		print("Recorded ",motion.size()," physical motion samples before correction")
	elif "--compare-baseline" in OS.get_cmdline_user_args():
		check(FileAccess.file_exists(baseline_path),"Pre-fix physical motion baseline exists")
		if FileAccess.file_exists(baseline_path):
			var baseline: Array = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
			check(baseline.size()==motion.size(),"Motion sample count is unchanged")
			var max_error := 0.0
			for i in range(mini(baseline.size(),motion.size())):
				for component in range(6):
					max_error = maxf(max_error,absf(baseline[i][component]-motion[i][component]))
			check(max_error<0.0001,"Physical position/velocity traces remain unchanged")
			print("Maximum physical motion difference: ",max_error)
	world.queue_free()
	await process_frame
	print("Facing regression: 48 direction/camera/speed cases + moving camera turn; ",failures," failures")
	quit(1 if failures else 0)
