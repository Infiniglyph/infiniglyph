extends SceneTree
## Native GPU review of the city and several instants of a real confirmed hit.
var world: Node3D
var camera: Camera3D

func _initialize() -> void: call_deferred("run")

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/metropolis_"+label+".png")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute("res://captures")
	for i in range(35): await physics_frame
	await shot("arrival")
	camera = Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 64
	camera.position = Vector3(0,2.6,4)
	camera.look_at(Vector3(0,12,-50))
	await shot("boulevard")
	camera.position = Vector3(-38,32,4)
	camera.look_at(Vector3(0,18,-49))
	await shot("skyways")
	camera.position = Vector3(28,25,-32)
	camera.look_at(Vector3(0,22,-64))
	await shot("tower")
	world.player.position = Vector3(-11,16.4,-61)
	world.player.velocity = Vector3.ZERO
	for i in range(12): await physics_frame
	camera.position = Vector3(16,25,-77)
	camera.look_at(Vector3(0,14,-62))
	await shot("north_loop")
	camera.position = Vector3(-18,19,-36)
	camera.look_at(Vector3(-8,13.5,-45))
	await shot("open_junction")
	camera.position = Vector3(77,9,47)
	camera.look_at(Vector3(68,1.8,37))
	await shot("lantern_court")
	camera.position = Vector3(0,14,64)
	camera.look_at(Vector3(0,1,76))
	await shot("south_court")
	camera.position = Vector3(0,160,24)
	camera.look_at(Vector3(0,0,0))
	await shot("district_complete")
	camera.position = Vector3(28,25,-32)
	camera.look_at(Vector3(0,22,-64))
	# Render actual scene cost on this machine, excluding initial compilation.
	for i in range(25): await process_frame
	var start := Time.get_ticks_usec()
	for i in range(90): await process_frame
	print("Native city render sample: %.1f FPS (90 frames / %.3f s), %d draw calls" % [90000000.0/(Time.get_ticks_usec()-start),(Time.get_ticks_usec()-start)/1000000.0,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	var p: CharacterBody3D = world.player
	var npc: CharacterBody3D = world.sparring_partner
	p.position = npc.home+Vector3(0,0,1.6)
	p.velocity = Vector3.ZERO
	for i in range(12): await physics_frame
	world.sparring_duel.start()
	npc.controls.stop()
	p.target_lock.select(npc)
	npc.target_lock.select(p)
	p.weapon_combat._begin(load("res://scripts/weapon_library.gd").move(&"down",&"attack_right"))
	for i in range(60):
		await physics_frame
		if p.weapon_combat.feedback.last_event.get("kind","") in ["hit","heavy"]: break
	world.process_mode = Node.PROCESS_MODE_DISABLED
	camera.position = npc.position+Vector3(-2.8,1.8,3.7)
	camera.look_at(npc.position+Vector3.UP)
	var feedback: Node = p.weapon_combat.feedback
	for burst: Dictionary in feedback.bursts:
		if burst.age<burst.duration:
			burst.age = 0.06
			burst.mesh.redraw(0.06)
	await shot("sparks_early")
	feedback._process(0.12)
	await shot("sparks_flight")
	feedback._process(0.15)
	await shot("sparks_fall")
	feedback._process(0.4)
	await shot("sparks_clear")
	world.queue_free()
	camera.queue_free()
	await process_frame
	print("Metropolis native captures complete")
	quit()
