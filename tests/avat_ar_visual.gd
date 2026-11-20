extends SceneTree
## Isolated procedural-merchant verification. Native --capture also produces
## reviewable front, hood and reverse views without loading the city or saves.
const Merchant = preload("res://scripts/avat_ar_visual.gd")
const Lines = preload("res://scripts/robe_lines.gd")
var checks := 0
var failures := 0
var world: Node3D
var merchant: Node3D
var camera: Camera3D

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else: failures += 1; push_error("FAIL: "+label)

func descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(descendants(child))
	return result

func frames(count: int) -> void:
	for i in range(count): await process_frame

func capture(label: String, from: Vector3, focus: Vector3) -> void:
	camera.position = from
	camera.look_at(focus)
	await frames(30)
	await RenderingServer.frame_post_draw
	var path := "res://captures/avat_ar_"+label+".png"
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ",path)

func run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("02030a")
	world.add_child(environment)
	merchant = Merchant.new()
	world.add_child(merchant)
	merchant.set_process(false)
	var all := descendants(merchant)
	var meshes: Array[MeshInstance3D] = []
	var labels := 0
	var collisions := 0
	var vertices := 0
	for child in all:
		if child is MeshInstance3D:
			meshes.append(child)
			if child.mesh is ArrayMesh:
				for surface in range(child.mesh.get_surface_count()): vertices += child.mesh.surface_get_array_len(surface)
		if child is Label3D: labels += 1
		if child is CollisionObject3D or child is Skeleton3D: collisions += 1
	print("MERCHANT BUDGET: ",meshes.size()," static mesh nodes / ",vertices," vertices / ",all.size()," total nodes")
	check(meshes.size()<=70 and vertices<16000,"Original layered hood, robes and brush have bounded modest geometry")
	check(labels==0 and collisions==0,"The unique merchant needs no digit text nodes, imported rig or combat physics")
	check(merchant.find_child("FlowingBinaryBody",true,false)!=null and merchant.find_child("BinaryBeneathHood",true,false)!=null,"Binary is part of the hood and single continuous apparition body")
	check(merchant.find_child("MulticolorMerchantPaintbrush",true,false)!=null and merchant.find_child("InfinityBrooch",true,false)!=null,"Multicolor brush and non-revealing infinity ornament are present")
	var atlas: Texture2D = Merchant.binary_atlas()
	check(atlas==Merchant.binary_atlas() and atlas.get_width()==128 and atlas.get_height()==256,"A single reusable original pixel atlas serves every binary surface")
	var white := 0
	var atlas_image := atlas.get_image()
	for y in range(256):
		for x in range(128):
			if atlas_image.get_pixel(x,y).r>.5: white += 1
	check(white>3000 and white<9000,"Dense legible digit strokes retain dark space inside the body")
	check(merchant._binary_materials.size()==2,"Two scrolling surfaces replace hundreds of individual text objects")
	var original_meshes: Array = []
	for mesh in meshes: original_meshes.append(mesh.mesh)
	var initial_hover: float = merchant._hover.position.y
	var initial_arm: Vector3 = merchant._arms[0].rotation
	merchant.welcome()
	for i in range(60): merchant.animate(1.0/60.0)
	check(not is_equal_approx(merchant._hover.position.y,initial_hover) and merchant._hover.position.y>=.01 and merchant._hover.position.y<=.101,"Idle hovering is gentle and stays clear of the floor")
	check(merchant._arms[0].rotation.distance_to(initial_arm)>.05,"Greeting animates the brush-bearing arm")
	check(is_equal_approx(float(merchant._binary_materials[0].get_shader_parameter("flow_time")),1.0),"Body digits continuously scroll through a lightweight shader")
	var unchanged := true
	for i in range(meshes.size()): unchanged = unchanged and meshes[i].mesh==original_meshes[i]
	check(unchanged and descendants(merchant).size()==all.size(),"Animation reuses every mesh and allocates no new scene nodes")
	for expression: StringName in Merchant.EXPRESSIONS:
		merchant.set_expression(expression)
		var visible_faces := 0
		for face: MeshInstance3D in merchant._faces.values():
			if face.visible: visible_faces += 1
		check(visible_faces==1 and merchant._faces[expression].visible,"Expression "+String(expression)+" selects one readable static face")
	merchant.set_expression(&"unknown")
	check(merchant.expression==&"welcoming","Unknown expressions safely fall back to the merchant's welcome")
	merchant.target_position = Vector3(4,0,2)
	var before: float = merchant.rotation.y
	merchant.animate(.1)
	check(merchant.rotation.y>before and merchant.rotation.y<atan2(4.0,2.0),"Facing a nearby customer eases smoothly rather than snapping")
	merchant.target_position = Vector3(100,0,0)
	before = merchant.rotation.y
	merchant.animate(.1)
	check(is_equal_approx(merchant.rotation.y,before),"Distant customers do not spin the counter merchant")
	world.rotation.y = .7
	merchant.rotation.y = 0
	merchant.target_position = world.to_global(Vector3(0,0,3))
	merchant.animate(.1)
	check(is_zero_approx(merchant.rotation.y),"Customer facing respects the shop parent's rotation")
	world.rotation.y = 0
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.content_scale_size = Vector2i(1280,720)
		root.size = Vector2i(1280,720)
		world.add_child(Lines.grid(10,10,1.0,Color("16404e")))
		camera = Camera3D.new()
		camera.fov = 39
		world.add_child(camera)
		camera.current = true
		merchant.rotation = Vector3.ZERO
		merchant.target_position = Vector3(INF,INF,INF)
		merchant.set_expression(&"welcoming")
		await capture("front",Vector3(2.4,1.8,5.4),Vector3(0,1.42,0))
		await capture("hood",Vector3(.65,2.12,2.0),Vector3(0,2.15,0))
		await capture("reverse",Vector3(-2.6,1.75,-4.5),Vector3(0,1.42,0))
		merchant.set_expression(&"excited")
		await capture("excited",Vector3(0,1.70,5.0),Vector3(0,1.42,0))
	world.free()
	print("Avat Ar visual verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
