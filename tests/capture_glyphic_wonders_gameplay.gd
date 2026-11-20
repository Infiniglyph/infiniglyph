extends SceneTree
## Native review of the production exterior, instance, merchandise and service
## pages. Uses isolated user data and real interaction eligibility/owned coins.
const Catalog = preload("res://scripts/item_catalog.gd")
const Entry = preload("res://scripts/equipment_entry.gd")
var world: Node3D
var shop: Node
var actor: CharacterBody3D
var camera: Camera3D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else: failures += 1; push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count): await physics_frame; await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await frames(2)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await frames(2)

func shoot(label: String,from: Vector3,focus: Vector3,fov: float = 64.0) -> void:
	camera.position = from
	camera.look_at(focus)
	camera.fov = fov
	camera.make_current()
	# Keep the existing non-rendering outdoor visibility camera pointed at the
	# same scene; the actual capture camera remains a direct child of World.
	world.camera_rig.camera.global_transform = camera.global_transform
	for i in range(30): await process_frame; await RenderingServer.frame_post_draw
	if shop.menu.is_open:
		var labels_fit := true
		for control: Control in shop.menu._screen.find_children("*","Control",true,false):
			if (control is Label or control is Button) and control.is_visible_in_tree() and not control.text.is_empty():
				labels_fit = labels_fit and root.get_visible_rect().encloses(control.get_global_rect())
				print("PAGE TEXT ",label," ",control.text.replace("\n"," | ")," rect=",control.get_global_rect())
		check(labels_fit,"The "+label+" menu text and buttons fit the native viewport")
	if "--capture" not in OS.get_cmdline_user_args(): return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-page=") and argument.get_slice("=",1)!=label: return
	var path := "res://captures/glyphic_wonders_gameplay_"+label+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"The actual "+label+" scene saves as a native render")
	print("CAPTURE ",ProjectSettings.globalize_path(path))

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Wonders gameplay capture watchdog"); quit(2))
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.content_scale_size = Vector2i(1280,720)
	root.size = Vector2i(1280,720)
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.world_memory_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.dungeon_enemies_enabled = false
	world.death_drop_probability = 0
	root.add_child(world)
	shop = world.glyphic_wonders
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	for i in range(240):
		await frames(1)
		if world.civilization.ready_for_simulation and world.dungeon_travel.ready_for_travel: break
	check(world.civilization.ready_for_simulation and world.dungeon_travel.ready_for_travel,"The actual world, shop and civilian clock finish their normal construction")
	world.civilization.simulation_enabled = false
	world.start_menu.close_menu()
	world.camera_rig.set_physics_process(false)
	world.camera_rig.set_process(false)
	for layer: CanvasLayer in world.find_children("*","CanvasLayer",true,false):
		if layer==world.graphics._glow or layer==shop.menu: continue
		layer.visible = false
	var hud: Node = world.find_child("CombatHUD",true,false)
	if hud is CanvasItem: hud.hide()
	actor.visual.hide()
	camera = Camera3D.new()
	camera.far = 1800
	world.add_child(camera)
	camera.make_current()
	var exterior: Node3D = world.wider_world.glyphic_wonders
	actor.global_position = exterior.arrival_anchor.global_position+Vector3(0,0,12)
	actor.velocity = Vector3.ZERO
	world.controls.set_gameplay_enabled(true)
	await frames(20)
	await shoot("storefront",Vector3(-86,8.5,-570),Vector3(-112,3.1,-608),56)
	check(world.dungeon_travel.restore_location(world.dungeon_travel.wonders_id),"The production shop instance activates through DungeonTravel")
	await frames(30)
	check(shop.displays.size()==12 and shop.hall.pedestals.size()==12,"All twelve current stock models populate the real spacious hall")
	print("DISPLAYED STOCK ",JSON.stringify(shop.stock.rotating_ids()))
	await shoot("hall",Vector3(0,12,62),Vector3(0,19,-28),73)
	actor.global_position = Vector3(0,.17,-30)
	actor.velocity = Vector3.ZERO
	await frames(30)
	await shoot("merchant",Vector3(1.8,3.2,-26),Vector3(0,2.9,-35),53)
	await shoot("merchant_hood",Vector3(1.1,2.5,-32.0),Vector3(0,2.12,-36.1),42)
	# Funded fixture transfer is an ordinary conserved ledger operation, never
	# free inventory or edits to balances. No persistent user save is touched.
	var economy: Node = world.civilian_services.economy
	check(economy.transfer(economy.guild_account,economy.player_account,80,"Native shop review funds"),"The inspection fixture has real accounted coins")
	var display_point: Dictionary = {}
	for point: Dictionary in shop._points:
		if point.kind=="display": display_point=point; break
	check(not display_point.is_empty(),"A current physical display exposes the production inspect interaction")
	# A counter-only review also makes it the first service page, isolating
	# native cached-font readback artifacts from earlier page replacement.
	var counter_only := "--capture-page=counter" in OS.get_cmdline_user_args()
	if not display_point.is_empty() and not counter_only:
		actor.global_position = display_point.anchor.global_position+Vector3(0,-1.1,3.5)
		actor.velocity = Vector3.ZERO
		actor.visual.rebase_after_phase()
		world.controls.set_gameplay_enabled(true)
		await frames(30)
		await key(KEY_G)
		var entry := Entry.for_id(StringName(display_point.type_id))
		check(shop.menu.is_open and shop.menu._title.text==entry.name and shop.menu._body.text.contains(String(entry.description)),"Keyboard G opens the actual pedestal's shared item description")
		var price: int = shop.stock.offer(StringName(display_point.type_id)).price
		check(shop.menu._body.text.contains("Price: %d Glyph Coins" % price),"Pedestal inspection shows its real authoritative retail price")
		await shoot("inspection",actor.global_position+Vector3(-3,2.7,5),display_point.anchor.global_position+Vector3.UP,58)
		shop.menu.close_menu()
	actor.global_position = Vector3(0,.17,-29.5)
	actor.velocity = Vector3.ZERO
	actor.visual.rebase_after_phase()
	world.controls.set_gameplay_enabled(true)
	await frames(30)
	await key(KEY_G)
	check(shop.menu.is_open and shop.menu._title.text.contains("Avat Ar") and shop.menu._choices.size()==7,"The actual counter menu offers permanent glyphs and merchant conversation")
	await shoot("counter",Vector3(1.8,3.2,-26),Vector3(0,2.9,-35),53)
	shop.menu.close_menu()
	world.queue_free()
	await process_frame
	print("Wonders native gameplay review: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
