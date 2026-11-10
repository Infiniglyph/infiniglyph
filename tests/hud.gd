extends SceneTree
## Layout/render review against the real player combat state.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/hud_"+label+".png")
	print("CAPTURE: ",label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var actor: CharacterBody3D = world.player
	actor.visual.retrieval.enabled = false
	await frames(4)
	var hud: Control = world.find_child("CombatHUD",true,false)
	check(hud.get_child_count() == 2 and hud.health_bar is ProgressBar and hud.exhaustion_bar is ProgressBar,"Permanent player HUD contains only two bars")
	check(hud.health_bar.value == 1000 and hud.exhaustion_bar.value == 0,"Fresh player shows full HP and empty accumulated exhaustion")
	var old_text := false
	for label: Label in world.find_children("*","Label",true,false):
		if label.text.contains("WEAPON SLOTS") or label.text.contains("WASD move") or label.text.contains("PHASE 003") or label.text.contains("Momentum increases"): old_text = true
	check(not old_text,"Title, debug panel and control sheet are absent from the live scene")
	for resolution: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await frames(3)
		var hp: Rect2 = hud.health_bar.get_global_rect()
		var strain: Rect2 = hud.exhaustion_bar.get_global_rect()
		check(root.get_visible_rect().encloses(hp) and root.get_visible_rect().encloses(strain),"Both bars fit viewport "+str(resolution))
		check(hp.position.x == 24 and hp.position.y == 24 and strain.position.y>hp.end.y and strain.size.y<hp.size.y,"HP remains top left with thinner exhaustion directly below at "+str(resolution))
		await shot(str(resolution.x)+"_full")
	root.size = Vector2i(1280,720)
	actor.set_physics_process(false)
	actor.weapon_combat.health = 542
	actor.weapon_combat.psi_meter = 48
	actor.weapon_combat._psi_delay = 10
	actor.weapon_combat.changed.emit()
	await frames(3)
	check(hud.health_bar.value == 542 and hud.exhaustion_bar.value == 48,"Partial bars reflect actual damage and accumulated strain")
	await shot("partial")
	actor.weapon_combat._psi_delay = 0
	await frames(30)
	# process_frame resumes before Control._process; permit one 60 Hz recovery
	# step when observing between callbacks rather than after drawing.
	check(hud.exhaustion_bar.value<48 and absf(hud.exhaustion_bar.value-actor.weapon_combat.psi_meter)<0.3,"Existing exhaustion recovery empties the display continuously")
	actor.respawn()
	await frames(2)
	check(hud.health_bar.value == 1000 and hud.exhaustion_bar.value == 0,"Respawn restores both displayed combat resources")
	world.start_menu.open_menu()
	await frames(2)
	check(world.start_menu.is_open and not paused,"System menu still overlays a live world")
	world.start_menu.close_menu()
	world.inventory_session.ui.open_menu()
	await frames(2)
	check(world.inventory_session.ui.is_open and not paused,"Inventory still overlays a live world")
	world.inventory_session.ui.close_menu()
	world.queue_free()
	await process_frame
	print("HUD verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
