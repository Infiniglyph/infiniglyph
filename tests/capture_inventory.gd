extends SceneTree
## Capture the real city/session menu at its supported 1280x720 viewport.
const Catalog = preload("res://scripts/item_catalog.gd")
var world: Node3D
var ui: CanvasLayer

func _initialize() -> void: call_deferred("run")

func shot(label: String) -> void:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/inventory_"+label+".png")
	print("INVENTORY CAPTURE ",label," footer bottom ",ui._help.global_position.y+ui._help.size.y)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in range(12):
		await physics_frame
		await process_frame
	var inventory: Node = world.player.inventory
	for entry in [[&"light_shard",12],[&"signal_tonic",3],[&"civic_key",1],[&"cyan_mantle",1],[&"echo_fragment",2]]: inventory.add_item(Catalog.create(entry[0],entry[1]))
	ui = world.inventory_session.ui
	ui.open_menu()
	DirAccess.make_dir_recursive_absolute("res://captures")
	var katana := ""
	var shards := ""
	for iid in inventory.items:
		if inventory.items[iid].item_type_id==&"katana": katana = String(iid)
		if inventory.items[iid].item_type_id==&"light_shard": shards = String(iid)
	ui.select_item(katana)
	ui.set_status("Inspect your weapons, assign quick-select directions, or drop an owned item into the city.")
	await shot("weapons")
	ui.select_tab(1)
	await shot("equipment")
	ui.select_item(shards)
	ui.activate_selection()
	ui.activate_selection()
	ui._adjust_quantity(2)
	await shot("drop_quantity")
	ui._close_modal()
	ui.select_category(1)
	await shot("cosmetics")
	for i in range(12): inventory.add_item(Catalog.create(&"katana"))
	ui.select_category(0)
	await shot("paged_collection")
	ui.close_menu()
	world.queue_free()
	await process_frame
	print("Inventory native captures complete")
	quit()
