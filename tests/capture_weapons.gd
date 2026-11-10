extends SceneTree
## Deterministic review poses; real execution is covered by weapons.gd.
const Library = preload("res://scripts/weapon_library.gd")
var world: Node3D
var p: CharacterBody3D
var w: Node
var camera: Camera3D
var failures := 0
var captures := 0

func _initialize() -> void:
	call_deferred("run")

func pose(time: float = 0.0) -> void:
	for i in range(18):
		p.visual.animate(1.0/60,Vector3.ZERO,true)
		w.elapsed = time
		w.apply_pose(1.0/60)
		w.trail.update(1.0/60,w.rig.blade_segments() if not w.active_move.is_empty() else [],Library.loadout(p.combat.selected_slot).color)

func shot(label: String, distance: float = 4.4, view: Vector3 = Vector3(0.68,0.36,1)) -> void:
	camera.global_position = p.global_position+view.normalized()*distance+Vector3.UP*1.1
	camera.look_at(p.global_position+Vector3.UP*1.1)
	await process_frame
	await RenderingServer.frame_post_draw
	var hud: Control = world.find_child("CombatHUD",true,false)
	for item: Control in [hud.health_bar,hud.exhaustion_bar]:
		if not root.get_visible_rect().encloses(item.get_global_rect()):
			push_error("Player bar leaves viewport: "+item.name)
			failures += 1
	root.get_texture().get_image().save_png("res://captures/weapon_"+label+".png")
	captures += 1

func equip(slot: StringName) -> void:
	world.controls._request(&"weapon",slot)
	p.combat.poll(world.controls)
	w.reset()

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	w = p.weapon_combat
	p.visual.retrieval.enabled = false
	for i in range(12): await physics_frame
	p.set_physics_process(false)
	w.set_physics_process(false)
	world.camera_rig.set_physics_process(false)
	world.camera_rig.set_process(false)
	p.position = Vector3.ZERO
	p.visual.rotation.y = 0
	p.visual.rebase_after_phase()
	camera = Camera3D.new()
	camera.fov = 50
	root.add_child(camera)
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute("res://captures")
	for slot: StringName in Library.LOADOUTS:
		equip(slot)
		pose()
		await shot(String(slot)+"_ready")
		if slot==&"right": await shot("right_ready_side",4.4,p.visual.global_basis*Vector3(1.5,0.25,0))
		p.combat.blocking = true
		pose()
		await shot(String(slot)+"_guard")
		p.combat.blocking = false
		for action: StringName in [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			w._on_action(action,slot)
			pose(float(w.active_move.hits[0])+0.035)
			w.status = w.active_move.name
			w.strike()
			w.changed.emit()
			await shot(String(slot)+"_"+String(action),maxf(5.5,float(w.active_move.reach)*1.75))
			w.cancel()
			for effect in get_nodes_in_group("weapon_effects"): effect.queue_free()
			w.trail.samples.clear()
		world.controls._request(&"sheathe",&"")
		p.combat.poll(world.controls)
		pose()
		await shot(String(slot)+"_sheathed")
		if slot==&"right": await shot("right_sheathed_left",4.4,p.visual.global_basis*Vector3(-1.5,0.25,-0.5))
	world.queue_free()
	camera.queue_free()
	await process_frame
	print("Weapon render review: ",captures," frames, ",failures," failures")
	quit(1 if failures else 0)
