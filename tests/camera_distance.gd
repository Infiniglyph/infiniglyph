extends SceneTree
## Exercise the live Settings slider, its persisted preference and real spring arm.
const CameraRig = preload("res://scripts/camera.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
const Target = preload("res://scripts/practice_target.gd")
var world: Node3D
var actor: CharacterBody3D
var menu: CanvasLayer
var rig: Node3D
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func tap(button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await ticks(1)
	event = InputEventJoypadButton.new()
	event.button_index = button
	Input.parse_input_event(event)
	await ticks(1)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func shot() -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await ticks(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/camera_distance_settings.png")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	menu = world.start_menu
	rig = actor.camera_rig
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await ticks(12)
	check(is_equal_approx(rig.get_follow_distance(),4.2) and is_equal_approx(rig.arm.spring_length,4.2),"A new player starts closer at 4.2 m")
	await tap(JOY_BUTTON_START)
	await tap(JOY_BUTTON_DPAD_DOWN)
	await tap(JOY_BUTTON_A)
	check(menu.is_open and menu.settings_open and not paused,"Controller opens live Settings without pausing")
	# The new slider is reachable in the same controller navigation list.
	for i in range(3): await tap(JOY_BUTTON_DPAD_DOWN)
	check(menu._distance.has_focus(),"Controller navigation reaches the camera distance slider")
	var before: float = rig.get_follow_distance()
	await tap(JOY_BUTTON_DPAD_LEFT)
	check(is_equal_approx(rig.get_follow_distance(),before-0.1) and is_equal_approx(rig.arm.spring_length,before-0.1),"Controller left adjusts the real spring arm immediately")
	await tap(JOY_BUTTON_DPAD_RIGHT)
	check(is_equal_approx(rig.get_follow_distance(),before),"Controller right zooms back out")
	menu._distance.value = 6.1
	check(is_equal_approx(rig.arm.spring_length,6.1),"Mouse slider changes apply without closing Settings")
	var before_y: float = actor.position.y
	actor.position.y += 3
	await ticks(ceili(0.3*hz))
	check(not paused and actor.position.y<before_y+2.8,"Gravity continues while changing camera distance")
	var path := "user://tests/camera_distance.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	check(menu.save_settings(path),"Camera distance saves in the existing settings configuration")
	var config := ConfigFile.new()
	config.load(path)
	check(config.get_value("meta","version",0)==1 and is_equal_approx(config.get_value("camera","distance",0),6.1),"Settings retain version 1 and store the on-foot distance")
	menu._distance.value = 2.4
	check(menu.load_settings(path) and is_equal_approx(rig.get_follow_distance(),6.1),"Saved distance restores the actual camera")
	# A pre-slider version-1 save needs no migration and gets the closer default.
	config.erase_section_key("camera","distance")
	config.set_value("camera","fov",81)
	config.save(path)
	check(menu.load_settings(path) and is_equal_approx(rig.get_follow_distance(),CameraRig.DEFAULT_FOLLOW_DISTANCE) and rig.camera.fov==81,"Legacy settings load the closer default while preserving other preferences")
	config.set_value("camera","distance",1000.0)
	config.save(path)
	check(menu.load_settings(path) and is_equal_approx(rig.arm.spring_length,CameraRig.MAX_FOLLOW_DISTANCE),"Out-of-range saved distance clamps at the far limit")
	config.set_value("camera","distance",-1000.0)
	config.save(path)
	check(menu.load_settings(path) and is_equal_approx(rig.arm.spring_length,CameraRig.MIN_FOLLOW_DISTANCE),"Out-of-range saved distance clamps at the near limit")
	config.set_value("camera","distance","invalid")
	config.save(path)
	check(menu.load_settings(path) and is_equal_approx(rig.arm.spring_length,CameraRig.MIN_FOLLOW_DISTANCE),"Malformed distance cannot replace the valid camera preference")
	var prior: float = rig.get_follow_distance()
	rig.set_follow_distance(NAN)
	rig.set_follow_distance(INF)
	check(is_equal_approx(rig.get_follow_distance(),prior),"Non-finite distance requests are ignored")
	menu._distance.value = 4.2
	menu._distance.grab_focus()
	await shot()
	check(menu._distance.get_global_rect().intersects(root.get_visible_rect()),"Camera distance control remains visible in the scrolling settings layout")
	if "--settings-only" in OS.get_cmdline_user_args():
		world.queue_free()
		await process_frame
		print("Camera settings verification: ",checks," checks, ",failures," failures @",hz," Hz")
		quit(1 if failures else 0)
		return
	menu.close_menu()
	actor.set_physics_process(false)
	actor.target_lock.clear()
	# Isolate the camera from district architecture at a fixed aerial anchor.
	actor.global_position = Vector3(1000,1000,1000)
	actor.velocity = Vector3.ZERO
	rig.yaw = 0
	rig.pitch = 0
	rig.reset_follow()
	rig.set_follow_distance(6.1)
	await ticks(4)
	check(absf(rig.arm.get_hit_length()-6.1)<0.05,"Clear space allows the requested camera distance")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8,8,0.3)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = actor.global_position+Vector3(0,1.35,2.5)
	await ticks(5)
	check(rig.arm.get_hit_length()<2.5 and rig.get_follow_distance()==6.1,"Spring arm retracts at a wall without changing the saved preference")
	menu.open_menu()
	menu.show_settings()
	menu._distance.value = 9
	await ticks(3)
	check(rig.arm.get_hit_length()<2.5 and rig.get_follow_distance()==9,"Zooming out behind an obstruction keeps collision protection")
	menu.close_menu()
	wall.queue_free()
	await ticks(5)
	check(absf(rig.arm.get_hit_length()-9)<0.05,"The requested distance returns when the obstruction clears")
	# Use the real boarding/detaching route, including its camera exclusions.
	var vehicle := Vehicle.new()
	vehicle.life = world.district_life
	vehicle.record = {"id":9999,"kind":"car","point":actor.global_position,"yaw":0.3,"traffic":false,"taken":true,"color":Color.CYAN,"driver":{"tint":Color.CYAN,"body_profile":&"male"}}
	world.add_child(vehicle)
	vehicle.set_physics_process(false)
	actor.global_position = vehicle.global_position+Vector3.RIGHT*2
	rig.set_follow_distance(3.7)
	check(world.world_actions.board(vehicle),"The real boarding route accepts a parked car")
	check(is_equal_approx(rig.arm.spring_length,3.7*CameraRig.VEHICLE_DISTANCE_SCALE) and is_equal_approx(rig.get_follow_distance(),3.7),"Boarding adds vehicle clearance while retaining the user's preference")
	var vehicle_yaw: float = vehicle.rotation.y
	var camera_yaw: float = rig.yaw
	world.controls.look = Vector2.RIGHT
	await ticks(ceili(0.15*hz))
	world.controls.look = Vector2.ZERO
	check(absf(angle_difference(rig.yaw,camera_yaw))>0.2 and is_equal_approx(vehicle.rotation.y,vehicle_yaw),"Mounted free-look still rotates independently of the vehicle")
	menu.open_menu()
	menu.show_settings()
	menu._distance.value = 5.3
	check(is_equal_approx(rig.arm.spring_length,5.3*CameraRig.VEHICLE_DISTANCE_SCALE),"The same distance slider works while driving")
	check(menu.save_settings(path),"Mounted Settings save successfully")
	config.load(path)
	check(is_equal_approx(config.get_value("camera","distance",0),5.3),"Mounted saves contain the preference rather than the vehicle-scaled length")
	menu.close_menu()
	world.world_actions.detach()
	check(is_equal_approx(rig.arm.spring_length,5.3) and is_equal_approx(rig.get_follow_distance(),5.3),"Dismount restores the selected on-foot distance")
	rig.reset_follow()
	check(is_equal_approx(rig.arm.spring_length,5.3),"Blink/reset-follow keeps the selected distance")
	vehicle.queue_free()
	await ticks(2)
	# The closest preference must still clear a truck's long cargo body.
	var truck := Vehicle.new()
	truck.life = world.district_life
	truck.record = {"id":10000,"kind":"truck","point":actor.global_position+Vector3(10,0,0),"yaw":0.0,"traffic":false,"taken":true,"color":Color.CYAN,"driver":{"tint":Color.CYAN,"body_profile":&"male"}}
	world.add_child(truck)
	truck.set_physics_process(false)
	menu._distance.value = CameraRig.MIN_FOLLOW_DISTANCE
	for entry in range(2):
		actor.global_position = truck.global_position+Vector3.RIGHT*2
		check(world.world_actions.board(truck),"Board/reboard a truck with the nearest camera preference, entry "+str(entry))
		rig.pitch = 0
		rig.reset_follow()
		await ticks(5)
		var camera_local: Vector3 = truck.to_local(rig.camera.global_position)
		check(camera_local.z < -truck.dimensions.z*0.5-0.2 and is_equal_approx(rig.get_follow_distance(),2.4),"Actual near camera remains behind truck cargo without replacing the saved preference, entry "+str(entry))
		world.world_actions.detach()
		check(is_equal_approx(rig.arm.spring_length,2.4) and is_equal_approx(menu._distance.value,2.4),"Leaving a truck restores the near on-foot distance and slider, entry "+str(entry))
	check(menu.save_settings(path),"Truck clearance does not prevent settings persistence")
	config.load(path)
	check(is_equal_approx(config.get_value("camera","distance",0),2.4),"Truck clearance leaves the saved near preference unchanged")
	truck.queue_free()
	var opponent := Target.new()
	opponent.actor = actor
	opponent.health = 100000
	opponent.max_health = 100000
	world.add_child(opponent)
	opponent.global_position = actor.global_position+Vector3(4,0,-6)
	actor.target_lock.select(opponent)
	rig.set_follow_distance(2.4)
	await ticks(ceili(0.7*hz))
	var offset: Vector3 = opponent.combat_point()-(actor.global_position+Vector3.UP*1.35)
	check(actor.target_lock.is_locked() and absf(angle_difference(rig.yaw,atan2(-offset.x,-offset.z)))<0.02,"Close camera preserves target-facing lock-on orbit")
	actor.target_lock.clear()
	world.queue_free()
	await process_frame
	print("Camera distance verification: ",checks," checks, ",failures," failures @",hz," Hz")
	quit(1 if failures else 0)
