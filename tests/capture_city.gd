extends SceneTree
## Render actual orange illumination, including an identical lights-off baseline.
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func shot(label: String) -> Image:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png("res://captures/city_"+label+".png")
	return result

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.player.visual.live_retrieval = false
	for i in range(45): await physics_frame
	world.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute("res://captures")
	await shot("plaza")
	var camera := Camera3D.new()
	camera.fov = 64
	root.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(1,9,-15)
	camera.look_at(Vector3(-10.5,2.3,-24))
	var lit := await shot("streetlight")
	for fixture in get_nodes_in_group("street_lights"): fixture.light.visible = false
	var unlit := await shot("lights_off")
	var warm_pixels := 0
	var max_gain := 0.0
	for y in range(lit.get_height()):
		for x in range(lit.get_width()):
			var difference: Color = lit.get_pixel(x,y)-unlit.get_pixel(x,y)
			max_gain = maxf(max_gain,difference.r)
			if difference.r > 0.015 and difference.r > difference.g*1.4: warm_pixels += 1
	var passed := warm_pixels > 1000 and max_gain > 0.1
	print("CITY RENDER: ","PASS" if passed else "FAIL", "; ",warm_pixels," orange-lit pixels; maximum red gain ",max_gain)
	for fixture in get_nodes_in_group("street_lights"): fixture.light.visible = true
	camera.global_position = Vector3(82,68,116)
	camera.look_at(Vector3(30,20,94))
	await shot("skyline")
	world.queue_free()
	camera.queue_free()
	await process_frame
	quit(0 if passed else 1)
