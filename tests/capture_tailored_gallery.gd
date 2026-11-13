extends SceneTree
const Database = preload("res://scripts/equipment_database.gd")
const Preview = preload("res://scripts/equipment_preview.gd")
const Lines = preload("res://scripts/robe_lines.gd")
var world: Node3D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ids: Array[StringName] = [&"eq_a_11298fc8",&"eq_a_1121eea8",&"eq_a_140d9ce8",&"eq_a_13c151a8",&"eq_a_13029588",&"eq_a_135681e8",&"eq_a_115ef7a8",&"eq_a_158b1528"]
	for i in range(ids.size()):
		var entry := Database.get_item(ids[i])
		var model := Preview.model(entry)
		world.add_child(model)
		model.position = Vector3((i%4-1.5)*1.75,(1-i/4)*2.5,0)
		model.rotation.y = .3 if i%2==0 else -.45
		var label := Label3D.new()
		model.add_child(label)
		label.text = String(entry.name).replace(" Vestment","\nVestment")
		label.font_size = 28
		label.pixel_size = .003
		label.position.y = 2.12
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.3
	camera.position = Vector3(0,2.7,10)
	camera.look_at(Vector3(0,2.2,0))
	camera.current = true
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/tailored_gallery.png")
	print("TAILORED GALLERY captured")
	world.queue_free()
	await process_frame
	quit()
