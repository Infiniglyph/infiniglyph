extends SceneTree
const Neon = preload("res://scripts/neon.gd")
class Intent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	func sample() -> void: pass
	func consume_jump() -> bool:
		var requested := jump
		jump = false
		return requested

var world: Node3D
var input: Intent
var failures := 0
var steps: Array = []
var camera: Camera3D

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if camera == null:
		camera = Camera3D.new()
		camera.fov = 50
		root.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute("res://captures")
	var aim: Vector3 = world.player.global_position+Vector3(0,0.65,0)
	if label.begins_with("glass") and not steps.is_empty():
		aim = (aim+steps.back().origin)*0.5
		var distance: float = maxf(4.5,world.player.global_position.distance_to(steps.back().origin)*1.4+3.5)
		camera.global_position = aim+Vector3(2.8,2.0,3.0).normalized()*distance
	else: camera.global_position = world.player.global_position+Vector3(2.4,1.1,2.6)
	camera.look_at(aim)
	# Freeze the test subject for this review frame as uncapped speed increases.
	var processing: bool = world.player.is_physics_processing()
	world.player.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/traversal_"+label+".png")
	world.player.set_physics_process(processing)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	input = Intent.new()
	world.add_child(input)
	var p: CharacterBody3D = world.player
	p.controls = input
	p.visual.retrieval.enabled = false
	p.air_stepped.connect(func(origin: Vector3, side: int): steps.append({"origin":origin,"side":side}))
	await frames(30)
	# Exercise actual event routing and stick-neutral cancellation independently.
	var controller: Node = world.controls
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_LEFT_STICK
	button.pressed = true
	controller._unhandled_input(button)
	check(controller.boost,"L3 click enables fast running")
	controller._unhandled_input(button)
	check(not controller.boost,"A second L3 click disables fast running")
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_CTRL
	ctrl.pressed = true
	controller._unhandled_input(ctrl)
	check(controller.boost,"Ctrl enables the same fast-run mode")
	ctrl.echo = true
	controller._unhandled_input(ctrl)
	check(controller.boost,"Keyboard repeat does not toggle fast run repeatedly")
	controller._boost_had_movement = true
	controller.sample()
	check(not controller.boost,"Releasing movement cancels fast run")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	controller._unhandled_input(space)
	check(controller.consume_jump() and not controller.consume_jump(),"One press produces one jump request")
	space.echo = true
	controller._unhandled_input(space)
	check(not controller.consume_jump(),"Holding Space does not auto-repeat sky steps")
	input.move = Vector2(0,-1)
	await frames(3)
	var before := -p.velocity.z
	await frames(1)
	check(absf(-p.velocity.z-before-9.0/60)<0.0001,"Normal acceleration matches the Library's 9 m/s²")
	input.boost = true
	before = -p.velocity.z
	await frames(1)
	check(absf(-p.velocity.z-before-20.0/60)<0.0001,"Fast-run acceleration matches the Library's 20 m/s²")
	await frames(90)
	check(absf(-p.velocity.z-10.2)<0.001,"Fast run reaches the Library sprint speed of 10.2 m/s")
	check(p.visual.pelvis.rotation.x+p.visual.chest.rotation.x>deg_to_rad(40),"Fast run has an exaggerated forward lean")
	check(p.rotation.is_zero_approx() and absf(world.camera_rig.pitch+0.22)<0.001,"Fast-run lean leaves collision body and camera upright")
	await shot("fast_run")
	# Measure uncapped impulses beyond the north edge: the newly solid tower and
	# skyways must obstruct flight through the city, not alter this free-air check.
	p.global_position = Vector3(0,0.05,-106)
	input.jump = true
	await frames(3)
	check(not p.is_on_floor() and steps.is_empty(),"Ground jump launches without an airborne glass tile")
	var start_height := p.position.y
	var carry_correct := true
	var lift_correct := true
	for i in range(20):
		var speed_before: float = -p.velocity.z
		var vertical_before: float = p.velocity.y
		input.jump = true
		await frames(2)
		carry_correct = carry_correct and absf(-p.velocity.z-speed_before-p.sky_jump_push)<0.01
		lift_correct = lift_correct and absf(p.velocity.y-vertical_before-p.sky_jump_lift+2*p.gravity/60)<0.01
		if i == 0:
			await shot("glass_contact")
			var glass: Node3D = p._glass_steps.back()
			var origin := glass.global_position
			await frames(4)
			check(glass.global_position.is_equal_approx(origin),"Glass foothold stays at the takeoff point")
			check(glass.find_children("*","CollisionObject3D",true,false).is_empty(),"Glass is visual and cannot obstruct movement or camera")
			await shot("glass_step")
		else:
			await frames(4)
			if i == 1: await shot("glass_right")
		await frames(4)
	check(steps.size()==20 and p.air_step_count==20,"Twenty consecutive air jumps succeed without a jump allowance")
	check(p.position.y>start_height+15,"Repeated sky steps continue gaining altitude")
	check(carry_correct and lift_correct,"Sky steps add directional momentum to existing horizontal and vertical velocity")
	var alternating := true
	for i in range(1,steps.size()): alternating = alternating and steps[i].side != steps[i-1].side
	check(alternating,"Sky steps alternate the stamping foot")
	input.move = Vector2.ZERO
	input.boost = false
	before = -p.velocity.z
	await frames(1)
	check(absf(before+p.velocity.z-9.0/60)<0.0001 and p.velocity.z<0,"Airborne release coasts and brakes at the Library rate")
	for i in range(30):
		input.jump = true
		await frames(1)
	await frames(2)
	check(p.air_step_count>=50,"Rapid sky steps remain unlimited")
	check(get_nodes_in_group("digital_glass_steps").size()<=12,"Rapid input bounds the number of live glass effects")
	await frames(60)
	check(get_nodes_in_group("digital_glass_steps").is_empty(),"Glass shards expire without accumulating")
	# A real low ceiling must still block the player's capsule.
	p.respawn()
	await frames(30)
	var ceiling: Node3D = Neon.block(world,Vector3(0,4,6),Vector3(6,0.25,6))
	p.position.y = 1.8
	p.velocity = Vector3.ZERO
	await frames(3)
	for i in range(15):
		input.jump = true
		await frames(3)
	check(p.position.y<2.05,"Unlimited jumping respects solid ceilings")
	ceiling.queue_free()
	p.respawn()
	await frames(45)
	check(p.is_on_floor() and p.air_step_count==0,"Landing/respawn resets pose bookkeeping and returns to idle")
	input.move = Vector2(1,-1).normalized()
	input.boost = true
	world.camera_rig.yaw = PI*0.5
	await frames(90)
	var travel := Vector3(p.velocity.x,0,p.velocity.z)
	var expected := Vector3(1,0,-1).normalized().rotated(Vector3.UP,PI*0.5)
	check(absf(travel.length()-10.2)<0.001,"Diagonal fast running has the same top speed")
	check(travel.normalized().dot(expected)>0.999,"Fast running remains camera-relative after camera rotation")
	check(p.visual.global_basis.z.dot(travel.normalized())>0.999,"Fast-run facing stays aligned with travel")
	world.queue_free()
	if camera != null: camera.queue_free()
	await process_frame
	print("Traversal verification: ",failures," failures")
	quit(1 if failures else 0)
