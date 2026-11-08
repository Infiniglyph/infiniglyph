extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in range(45): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/plaza.png")
	scene.queue_free()
	await process_frame
	quit()
