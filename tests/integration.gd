extends SceneTree
var failures := 0
var world: Node3D

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ",description)
	else:
		push_error("FAIL: "+description)
		failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await frames(30)
	var p: CharacterBody3D = world.player
	check(p.is_on_floor(),"Player settles on plaza collision")
	check(world.camera_rig.camera.current,"Third-person camera is active")
	check(p.visual.joints.size()==4,"Four articulated limb chains exist")
	var start := p.position
	key(KEY_W,true)
	await frames(60)
	key(KEY_W,false)
	check(p.position.z < start.z-2,"Keyboard walks forward across plaza")
	var walk_travel := start.z-p.position.z
	await frames(20)
	var walking_z := p.position.z
	key(KEY_W,true)
	key(KEY_SHIFT,true)
	await frames(60)
	key(KEY_W,false)
	key(KEY_SHIFT,false)
	check(walking_z-p.position.z > walk_travel*1.4,"Running moves faster than walking with Library acceleration")
	await frames(20)
	var floor_y := p.position.y
	world.controls.jump_requested = true
	await frames(14)
	check(p.position.y > floor_y+0.6,"Jump rises above ground")
	await frames(90)
	check(p.is_on_floor(),"Jump lands on floor")
	# Walk against the south face of a tower.
	p.position = Vector3(-23,0.2,-14)
	p.velocity = Vector3.ZERO
	key(KEY_W,true)
	await frames(120)
	key(KEY_W,false)
	check(p.position.z > -17.9,"Building collision blocks forward motion")
	# Walk up the entire 12-step flight to the low roof.
	p.position = Vector3(23,0.2,-8)
	p.velocity = Vector3.ZERO
	await frames(20)
	key(KEY_W,true)
	await frames(210)
	key(KEY_W,false)
	check(p.position.y > 3 and p.position.z < -18,"Stairs reach the accessible rooftop")
	key(KEY_W,true)
	await frames(320)
	key(KEY_W,false)
	check(p.position.y > 4.5 and p.position.z < -37,"Rooftop connects to the higher terrace")
	# Camera sweep must shorten near solid buildings, excluding its player.
	p.position = Vector3(-23,0.2,-14)
	p.velocity = Vector3.ZERO
	world.camera_rig.yaw = PI
	world.camera_rig.reset_follow()
	await frames(30)
	check(world.camera_rig.arm.get_hit_length() < 5.5,"Spring arm retracts against building collision")
	check(world.camera_rig.global_position.distance_to(p.global_position+Vector3(0,1.35,0))<0.1,"Camera follows the player")
	# Test controller events without requiring connected hardware.
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	world.controls._unhandled_input(button)
	check(world.controls.consume_jump(),"Controller A routes to jump intent")
	check(world.controls.filtered(Vector2(0.05,0.05)) == Vector2.ZERO,"Analog deadzone filters stick drift")
	world.queue_free()
	await process_frame
	print("RESULT: ",failures," failures")
	quit(1 if failures else 0)
