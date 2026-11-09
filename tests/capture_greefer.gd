extends SceneTree
var world: Node3D
var camera: Camera3D

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/greefer_"+label+".png")
	print("CAPTURE: ",label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.visual.retrieval.enabled = false
	var boss: CharacterBody3D = world.greefer
	boss.think_enabled = false
	for child: Node in world.get_children():
		if child is CanvasLayer: child.hide()
	camera = Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.fov = 60
	camera.position = boss.position+Vector3(4.8,2.6,7.5)
	camera.look_at(boss.position+Vector3.UP*1.8)
	await frames(5)
	await shot("model_rest")
	boss.flight_mode = true
	await frames(40)
	camera.position = boss.position+Vector3(5.8,3.4,9.8)
	camera.look_at(boss.position+Vector3.UP*1.7)
	await shot("model_flight")
	world.boss_encounter.show()
	world.player.set_physics_process(false)
	world.player.position = Vector3(0,0.05,-16.4)
	boss.position = Vector3(0,0.045,-20)
	boss.flight_mode = false
	world.boss_encounter.start(true)
	boss.weapon_combat._begin(preload("res://scripts/greefer_moves.gd").move(&"sweep"))
	camera.position = boss.position+Vector3(4.0,3.1,7.0)
	camera.look_at(boss.position+Vector3(0,1.7,0.6))
	await frames(30)
	await shot("combat")
	world.queue_free()
	await process_frame
	print("Greefer native review complete")
	quit()
