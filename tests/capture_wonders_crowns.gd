extends SceneTree
func _initialize(): call_deferred("run")
func run():
	create_timer(30).timeout.connect(func(): quit(2))
	var scene:=Node3D.new(); root.add_child(scene)
	var hall:=preload("res://scripts/glyphic_wonders_hall.gd").new(); scene.add_child(hall)
	var crown: MultiMeshInstance3D=hall.get_node("RotatingColumnCrowns")
	print("CROWN ",crown.multimesh.visible_instance_count," ",crown.multimesh.get_instance_transform(9)," vertices=",crown.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	var camera:=Camera3D.new(); scene.add_child(camera); camera.position=Vector3(27,38,60); camera.look_at(Vector3(37,39,48)); camera.current=true; camera.fov=60
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/wonders_column_close.png")
	var before:=root.get_texture().get_image().get_data()
	await create_timer(.6).timeout; await RenderingServer.frame_post_draw
	var rotated: bool=root.get_texture().get_image().get_data()!=before
	print("CROWN ROTATION visible pixels change with a stationary camera: ",rotated)
	if not rotated: quit(1); return
	camera.position=Vector3(0,31,64); camera.look_at(Vector3(0,35,-20)); camera.fov=75
	for i in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/wonders_columns_hall.png")
	scene.queue_free(); await process_frame; quit()
