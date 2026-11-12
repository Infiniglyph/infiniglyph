extends SceneTree
## Scene/collision audit and optional native render review of the night details.
const Windows = preload("res://scripts/window_lights.gd")
const Stars = preload("res://scripts/starfield.gd")
var checks := 0
var failures := 0
var world: Node3D
var camera: Camera3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func _initialize() -> void: call_deferred("run")

func shot(label: String, at: Vector3, target: Vector3) -> Image:
	camera.position = at
	camera.look_at(target)
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://captures/night_"+label+".png")
	print("CAPTURE: night_",label)
	return image

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	world.controls.set_gameplay_enabled(false)
	world.greefer.think_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame
	await process_frame
	var windows: Node3D = world.get_node("WindowLights")
	check(windows.building_count==world.wider_world.buildings.size()+44,"Lit-window layouts cover the hub, skyline, urban blocks and homes")
	check(windows.pane_count>2000 and windows.batch_count<windows.pane_count/15,"Thousands of selected panes share small spatial batches")
	check(windows.find_children("*","Light3D",true,false).is_empty() and windows.find_children("*","CollisionShape3D",true,false).is_empty(),"Interior glow adds no realtime lights or collision obstacles")
	check(not windows.is_processing() and not windows.is_physics_processing() and windows.cells.is_empty(),"Window geometry is immutable and releases its build buffers")
	var bad_batches := 0
	var probes := 0
	var supported := 0
	var state := world.get_world_3d().direct_space_state
	for batch: MeshInstance3D in windows.get_children():
		if batch.mesh.get_surface_count()!=1 or batch.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: bad_batches += 1
		var material: StandardMaterial3D = batch.mesh.surface_get_material(0)
		if material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED: bad_batches += 1
		var points: PackedVector3Array = batch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for index in range(0,points.size(),6*23):
			var center := batch.to_global((points[index]+points[index+2])*0.5)
			var normal := (points[index+1]-points[index]).cross(points[index+2]-points[index]).normalized()
			var hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(center+normal*0.15,center-normal*0.15,1))
			# Two-sided panes can have either winding; probe the reverse as well.
			if hit.is_empty(): hit = state.intersect_ray(PhysicsRayQueryParameters3D.create(center-normal*0.15,center+normal*0.15,1))
			probes += 1
			if not hit.is_empty(): supported += 1
	check(bad_batches==0,"Window batches are opaque, single-surface and shadow-free")
	check(probes>200 and supported==probes,"Every sampled window is flush against a physical building (%d probes)" % probes)
	var sample := Windows.new()
	sample.facade_windows(Vector3(23,0.12,-24),Vector3(12,18,12),3)
	var copy := Windows.new()
	seed(18079)
	var expected := randi()
	seed(18079)
	copy.facade_windows(Vector3(23,0.12,-24),Vector3(12,18,12),3)
	check(randi()==expected and var_to_bytes(sample.cells)==var_to_bytes(copy.cells),"Fixed occupancy neither rerolls windows nor consumes gameplay random numbers")
	sample.free()
	copy.free()
	var environment: Environment = world.get_world_3d().environment
	check(environment.background_mode==Environment.BG_SKY and environment.sky.sky_material is PanoramaSkyMaterial,"Sparse stars use a single static sky panorama")
	check(environment.ambient_light_source==Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(environment.ambient_light_energy,0.4) and environment.reflected_light_source==Environment.REFLECTION_SOURCE_DISABLED,"Stars preserve the existing ambient light without new environment reflections")
	print("NIGHT DETAILS: ",windows.pane_count," panes in ",windows.batch_count," batches across ",windows.building_count," buildings; ",Stars.STAR_COUNT," sky specks")
	if "--capture" in OS.get_cmdline_user_args(): await render_review(windows)
	world.queue_free()
	await process_frame
	print("Night details verification: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)

func render_review(windows: Node3D) -> void:
	DirAccess.make_dir_recursive_absolute("res://captures")
	# Freeze only this review fixture to compare identical pixels.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	camera = Camera3D.new()
	camera.fov = 68
	camera.far = 1800
	root.add_child(camera)
	camera.current = true
	var at := Vector3(0,3,10)
	var target := Vector3(0,13,-55)
	var lit := await shot("hub",at,target)
	windows.hide()
	var dark := await shot("hub_windows_off",at,target)
	windows.show()
	var warm_pixels := 0
	for y in range(lit.get_height()):
		for x in range(lit.get_width()):
			var gain := lit.get_pixel(x,y)-dark.get_pixel(x,y)
			if gain.r>0.10 and gain.r>gain.g*1.4: warm_pixels += 1
	check(warm_pixels>150,"Native render shows visible warm window light (%d pixels)" % warm_pixels)
	await shot("urban",Vector3(0,4,-210),Vector3(0,18,-360))
	for home: Dictionary in world.wider_world.buildings:
		if home.region=="home" and home.point.z< -500 and absf(home.point.x)<200:
			await shot("suburbs",home.point+Vector3(10,5.5,20),home.point+Vector3.UP*2.8)
			break
	var sky := await shot("sky",Vector3(0,500,0),Vector3(0,1000,-600))
	var moved := await shot("sky_translated",Vector3(850,600,-850),Vector3(850,1100,-1450))
	var star_pixels := 0
	var changed := 0
	# Avoid HUD corners: the comparison must inspect the actual sky.
	for y in range(100,sky.get_height()-100):
		for x in range(100,sky.get_width()-100):
			var color := sky.get_pixel(x,y)
			if color.r>0.12 and color.g>0.12 and color.b>0.12: star_pixels += 1
			if color!=moved.get_pixel(x,y): changed += 1
	check(star_pixels>50 and star_pixels<4000,"Sky specks are visible while most of the void stays black (%d pixels)" % star_pixels)
	check(changed==0,"Camera translation introduces no starfield parallax or reroll")
	await shot("sky_rotated",Vector3(850,600,-850),Vector3(1450,1100,-850))
	camera.queue_free()
