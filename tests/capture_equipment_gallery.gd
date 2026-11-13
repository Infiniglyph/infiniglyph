extends SceneTree
## Standalone visual QA of the actual runtime meshes, without loading the city.
const Database = preload("res://scripts/equipment_database.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	camera.position = Vector3(0,0,12)
	camera.current = true
	var families := ["dagger","sword","greatsword","katana","axe","hammer","spear","halberd","scythe","bow","crossbow","staff","shield","head","body","hands","legs","ring"]
	for index in range(families.size()):
		var item: Dictionary = {}
		for entry: Dictionary in Database.all():
			if entry.family==families[index] and (entry.geometry.has("outline") or families[index] in ["bow","crossbow","head","body","hands","legs","ring"]):
				item=entry
				break
		if item.is_empty(): continue
		var model := Geometry.model(item.geometry)
		stage.add_child(model)
		var bounds: AABB = model.get_child(0).mesh.get_aabb()
		var scale_value := 2.15/maxf(.01,maxf(bounds.size.x,bounds.size.y))
		model.scale = Vector3.ONE*scale_value
		model.rotation.y = .4
		var at := Vector3((index%6-2.5)*3.1,(1-index/6)*3.3,0)
		model.position = at-model.basis*bounds.get_center()
		var label := Label3D.new()
		label.text = String(families[index]).to_upper()+"\n"+String(item.name).left(26)
		label.font_size = 24
		label.pixel_size = .007
		label.position = at+Vector3(0,-1.45,.1)
		stage.add_child(label)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/equipment_gallery.png")
	print("CAPTURE: equipment_gallery")
	quit()
