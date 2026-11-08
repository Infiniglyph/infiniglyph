extends SceneTree
const Neon = preload("res://scripts/neon.gd")
class Intent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	var dodge := false
	func sample() -> void: pass
	func consume_jump() -> bool:
		var value := jump
		jump = false
		return value
	func consume_dodge() -> bool:
		var value := dodge
		dodge = false
		return value

var world: Node3D
var p: CharacterBody3D
var input: Intent
var camera: Camera3D
var failures := 0

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func tick() -> void:
	await physics_frame
	await process_frame

func frames(count: int) -> void:
	for i in range(count): await tick()

func place(at: Vector3, motion: Vector3 = Vector3.ZERO) -> void:
	input.move = Vector2.ZERO
	input.jump = false
	input.dodge = false
	input.boost = false
	p.respawn()
	p.position = at
	await tick()
	p.velocity = motion

func start(move: Vector2 = Vector2.ZERO) -> void:
	input.move = move
	input.dodge = true
	await tick()

func finish() -> void:
	for i in range(60):
		if not p.dodge.active: return
		await tick()
	check(false,"Dodge finishes within one second")

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if camera == null:
		camera = Camera3D.new()
		camera.fov = 56
		root.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute("res://captures")
	var aim: Vector3 = (p.dodge.origin+p.dodge.destination)*0.5+Vector3.UP*0.8
	camera.global_position = aim+Vector3(6,3,7)
	camera.look_at(aim)
	p.set_physics_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/dodge_"+label+".png")
	p.set_physics_process(true)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	input = Intent.new()
	world.add_child(input)
	p.controls = input
	p.visual.retrieval.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(30)
	# Real event routing; neither keyboard repeat nor button release retriggers it.
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_B
	button.pressed = true
	world.controls._unhandled_input(button)
	check(world.controls.consume_dodge() and not world.controls.consume_dodge(),"Controller B produces one dodge request")
	button.pressed = false
	world.controls._unhandled_input(button)
	check(not world.controls.consume_dodge(),"Releasing B does not dodge")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	world.controls._unhandled_input(key)
	check(world.controls.consume_dodge(),"Keyboard E routes to the same dodge")
	key.echo = true
	world.controls._unhandled_input(key)
	check(not world.controls.consume_dodge(),"Holding E does not repeat the dodge")
	# Quantify the requested sky-step tuning in the actual physics, not a formula.
	check(is_equal_approx(p.sky_jump_push,3.4),"Sky-step forward boost is 15 percent lower")
	for hz in [30,60,120]:
		Engine.physics_ticks_per_second = hz
		await place(Vector3(0,80,0))
		var initial_y := p.position.y
		var highest := initial_y
		input.jump = true
		for i in range(hz):
			await tick()
			highest = maxf(highest,p.position.y)
			if p.velocity.y <= 0: break
		var rise := highest-initial_y
		check(absf(rise-1.85)<0.12,"Neutral sky-step rises about one character height at %d Hz (%.3f m)" % [hz,rise])
	Engine.physics_ticks_per_second = 60
	check(p.walk_speed == 3.5 and p.run_speed == 7.5 and p.boost_speed == 10.2,"Walking, running and sprint pacing remain unchanged")
	await place(Vector3(0,0,6))
	world.camera_rig.yaw = 0
	await start()
	check(p.dodge.active and not p.dodge.has_shifted,"Dodge starts its dematerialization before shifting")
	await frames(2)
	await shot("departure")
	while not p.dodge.has_shifted and p.dodge.active: await tick()
	check(absf(p.position.distance_to(p.dodge.origin)-3.2)<0.01,"Standing dodge shifts 3.2 meters camera-forward")
	check(p.dodge.elapsed >= 0.34*0.43 and p.dodge.elapsed < 0.34*0.43+1.0/60+0.001,"Blink commits at the Library's shift point")
	check(p.collision_layer == 1 and p.scale == Vector3.ONE and not p.get_child(0).disabled and is_equal_approx(p.get_child(0).shape.height,1.85),"Dodge keeps the capsule collision enabled and upright")
	check(world.camera_rig.global_position.distance_to(p.position+Vector3.UP*1.35)<0.1,"Camera follows the blink without a yaw or pitch inversion")
	await shot("shift")
	await frames(5)
	await shot("arrival")
	await finish()
	check(p.visual.scale.is_equal_approx(Vector3.ONE) and p.dodge.elapsed == 0.34,"Visual rematerializes at the end of the 0.34 second phase")
	var restored_materials := true
	for geometry in p.visual.find_children("*","GeometryInstance3D",true,false):
		restored_materials = restored_materials and geometry.material_override == null
	check(restored_materials and p.visual.position.is_zero_approx() and Neon.body.albedo_color.a == 1,"Phase exit restores original body materials and visual position")
	await shot("complete")
	await start(Vector2.RIGHT)
	check(not p.dodge.active,"Cooldown blocks an immediate second dodge")
	await frames(40)
	check(not p.dodge.active and p.dodge.cooldown == 0,"Holding the button cannot dodge again after the cooldown")
	var directions := 0
	for yaw in [0.0,PI*0.5,PI,PI*1.5]:
		for move in [Vector2.ZERO,Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized()]:
			await place(Vector3(0,0,0))
			world.camera_rig.yaw = yaw
			await start(move)
			var expected := Vector3(move.x,0,move.y).rotated(Vector3.UP,yaw) if not move.is_zero_approx() else Vector3.FORWARD.rotated(Vector3.UP,yaw)
			await finish()
			var travel: Vector3 = p.position-p.dodge.origin
			if travel.normalized().dot(expected)>0.999 and absf(travel.length()-3.2)<0.01: directions += 1
	check(directions == 24,"Camera-relative cardinal, diagonal and neutral dodges work across four camera yaws")
	for speed in [0.0,5.1,10.2,40.0]:
		await place(Vector3(0,10,0),Vector3(speed,-3,0))
		world.camera_rig.yaw = 0
		await start(Vector2.RIGHT)
		var expected_distance := 3.2+3.2*minf(speed/10.2,1)
		await finish()
		check(absf(p.position.distance_to(p.dodge.origin)-expected_distance)<0.01,"Dodge range follows actual carried speed %.1f m/s" % speed)
		check(p.velocity.distance_to(Vector3(speed,-3,0))<0.001,"Dodge returns carried horizontal/vertical momentum %.1f m/s" % speed)
	# New blockers, thin posts, diagonal contacts and low overhangs all stop a blink.
	var cases := [
		[Vector3(2,1,0),Vector3(0.1,3,12),Vector2.RIGHT,1.6,"thin wall"],
		[Vector3(1.5,1,0),Vector3(0.16,2,0.16),Vector2.RIGHT,1.07,"narrow post"],
		[Vector3(2,1,0),Vector3(0.1,3,12),Vector2(1,-1).normalized(),1.63,"diagonal wall"],
		[Vector3(3,1.7,0),Vector3(3,0.2,2),Vector2.RIGHT,1.15,"low overhang"]]
	for spec in cases:
		await place(Vector3.ZERO,Vector3(10.2,0,0))
		world.camera_rig.yaw = 0
		var obstacle := Neon.block(world,spec[0],spec[1])
		await tick()
		await start(spec[2])
		await finish()
		check(p.dodge.has_shifted and p.position.x < float(spec[3]) and p.position.x > 0.35,"Full capsule sweep stops before a "+spec[4])
		obstacle.queue_free()
		await tick()
	await place(Vector3.ZERO)
	var close_wall := Neon.block(world,Vector3(0.55,1,0),Vector3(0.1,3,12))
	await tick()
	await start(Vector2.RIGHT)
	check(not p.dodge.active and p.dodge.cooldown == 0,"An obstructed dodge with less than 0.35m clearance is rejected")
	close_wall.queue_free()
	await tick()
	await place(Vector3.ZERO)
	await start(Vector2.RIGHT)
	var late_wall := Neon.block(world,Vector3(2,1,0),Vector3(0.1,3,12))
	await finish()
	check(p.position.x > 0.35 and p.position.x < 1.6,"A blocker added during dematerialization stops the committing blink")
	late_wall.queue_free()
	await tick()
	# Jump requests during the brief phase are retained, and remain additive in air.
	await place(Vector3(0,20,0),Vector3(0,-6,0))
	await start(Vector2.RIGHT)
	input.jump = true
	await tick()
	await finish()
	await tick()
	check(p.air_step_count == 1 and absf(p.velocity.y-(-6-p.gravity/60+p.sky_jump_lift))<0.01,"A jump pressed during the phase fires once on exit with additive lift")
	await place(Vector3(0,40,0))
	await frames(15)
	var peak_y: float = p.visual._fall_peak_y
	await start(Vector2.RIGHT)
	await finish()
	await tick()
	check(absf(p.visual._fall_peak_y-peak_y)<0.01,"Air dodging preserves the current drop-height history")
	await place(Vector3(29,16.12,24),Vector3(10.2,0,0))
	await start(Vector2.RIGHT)
	await finish()
	var roof_y := p.position.y
	await frames(6)
	check(not p.is_on_floor() and p.position.y < roof_y-0.01,"Dodging off a rooftop resumes falling normally")
	await place(Vector3.ZERO)
	await start(Vector2.RIGHT)
	p.respawn()
	check(not p.dodge.active and p.dodge.cooldown == 0 and p.visual.scale == Vector3.ONE,"Respawn cancels a phase and restores the full visual")
	await frames(40)
	check(get_nodes_in_group("phase_traces").is_empty(),"Phase traces expire without leaving geometry behind")
	world.queue_free()
	if camera != null: camera.queue_free()
	await process_frame
	print("Dodge/sky-step verification: ",failures," failures")
	quit(1 if failures else 0)
