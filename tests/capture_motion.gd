extends SceneTree
var scene: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func shot(label: String) -> void:
	camera.global_position = scene.player.global_position+Vector3(2.4,1.25,2.8)
	camera.look_at(scene.player.global_position+Vector3(0,0.85,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/motion_"+label+".png")

func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	camera = Camera3D.new()
	camera.fov = 48
	root.add_child(camera)
	camera.current = true
	DirAccess.make_dir_recursive_absolute("res://captures")
	await frames(45)
	await shot("idle")
	key(KEY_W,true)
	await frames(9)
	await shot("launch")
	key(KEY_SHIFT,true)
	await frames(40)
	await shot("run")
	key(KEY_D,true)
	await frames(8)
	await shot("turn")
	key(KEY_W,false)
	key(KEY_D,false)
	key(KEY_SHIFT,false)
	await frames(8)
	await shot("brake")
	await frames(80)
	scene.controls.jump_requested = true
	await frames(13)
	await shot("jump")
	while not scene.player.is_on_floor(): await physics_frame
	await frames(5)
	await shot("landing")
	scene.queue_free()
	camera.queue_free()
	await process_frame
	quit()
