extends SceneTree
## Reproduce a valid outer-city death drop while its world is still constructing.
const Store = preload("res://scripts/inventory_store.gd")
const Session = preload("res://scripts/inventory_session.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Instance = preload("res://scripts/item_instance.gd")
var world: Node3D
var checks := 0
var failures := 0
var hz := 60
var checkpoint: Dictionary
var path := ""
var scenario := "valid"
var source_text := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.get_slice("=",1))
	Engine.physics_ticks_per_second = hz
	node_added.connect(observe)
	call_deferred("run")

func observe(node: Node) -> void:
	if node.get_script()!=Session: return
	node.ready.connect(func():
		# Script tools normally isolate fresh inventories. Deliberately start the
		# production load path at this exact lifecycle point, before outer terrain.
		node.save_path = path
		node.persistence_enabled = true
		check(not is_instance_valid(node.get_parent().wider_world),"The "+scenario+" checkpoint starts before outer-world construction")
		node._begin_initial_checkpoint_load()
		check(node._checkpoint_pending and not node.controls.gameplay_enabled and not node.can_talk(),"Startup gates local actions while keeping the scene tree running")
		check(not node.save_checkpoint() and FileAccess.get_file_as_string(path)==source_text,"A pending load cannot autosave starter data over its source")
	)

func create_world() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	world.population.set_physics_process(false)
	for i in range(20):
		await frames()
		if not world.inventory_session._checkpoint_pending: break
	check(not world.inventory_session._checkpoint_pending and not paused,"Startup settles after the world and physics are ready without pausing")

func run() -> void:
	var owned := Inventory.new()
	owned.owner_id = "local"
	var sword: Resource = Catalog.create(&"sword_shield")
	var robes: Resource = Catalog.create(&"eternal_scribe_robes")
	owned.add_item(sword)
	owned.add_item(robes)
	owned.add_item(Catalog.create(&"health_glyph",10))
	owned.assign(&"down",sword.instance_id)
	owned.assign(&"body",robes.instance_id)
	owned.starter_glyphs_granted = true
	var lost: Resource = Catalog.create(&"katana")
	var drop := {"pickup_id":Instance.new_id(),"item":lost.to_dict(),"position":[-1.719,0.0,-466.81],"death_owner_id":"local"}
	checkpoint = Store.encode(owned,[drop],[],"singleplayer")
	owned.free()
	path = "user://tests/startup-"+Instance.new_id()+".json"
	check(Store.store(path,checkpoint)==OK,"A valid owned checkpoint contains clothing, glyphs and an outer-city lost weapon")
	source_text = FileAccess.get_file_as_string(path)
	await create_world()
	var session: Node = world.inventory_session
	var inventory: Node = world.player.inventory
	check(session._checkpoint_usable and session.persistence_enabled and not session.notice.text.contains("autosave stopped"),"Valid outer-city drops no longer disable inventory persistence at startup")
	check(inventory.items.size()==3 and inventory.equipped_item(&"body").instance_id==robes.instance_id and inventory.count_type(&"health_glyph")==10,"Owned identities, Body equipment and glyph quantities restore without starter duplication")
	check(world.loot.pickups.size()==1 and world.loot.pickups.has(drop.pickup_id),"The lost katana restores exactly once at its saved outer-city position")
	var restored: Node3D = world.loot.pickups.get(drop.pickup_id)
	check(is_instance_valid(restored) and restored.item_instance.instance_id==lost.instance_id and restored.position.distance_to(Vector3(-1.719,0,-466.81))<0.002 and world.loot.markers.markers.size()==1,"The unclaimed weapon retains its identity, location and death marker")
	check(world.controls.gameplay_enabled and world.player.visual.robe.is_equipped(),"Gameplay resumes with the restored wearable after startup")
	check(session.save_checkpoint("",true) and Store.load_snapshot(path).inventory.items.size()==3,"Normal checkpoint saves work again after the deferred load")
	var file_before := FileAccess.get_file_as_string(path)
	var before_inventory: String = JSON.stringify(inventory.serialize())
	check(session.load_checkpoint(path) and JSON.stringify(inventory.serialize())==before_inventory and world.loot.pickups.size()==1,"Reloading the recovered checkpoint cannot duplicate or grant items")
	check(FileAccess.get_file_as_string(path)==file_before,"Loading does not repair or overwrite a source file")
	session.persistence_enabled = false
	world.queue_free()
	await frames()
	# A genuinely corrupt source still retains the original failure safeguards.
	scenario = "corrupt"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string("invalid checkpoint")
	file.close()
	source_text = "invalid checkpoint"
	await create_world()
	session = world.inventory_session
	check(not session._checkpoint_usable and not session.persistence_enabled and world.player.inventory.items.is_empty(),"Corrupt data still fails closed without reminting starter equipment or glyphs")
	check(FileAccess.get_file_as_string(path)==source_text and session.notice.text.contains("autosave stopped"),"An invalid source is preserved and the loading failure remains visible")
	check(world.controls.gameplay_enabled and not paused,"A rejected checkpoint does not freeze the world or local controls")
	world.queue_free()
	await frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Inventory startup verification: %d checks, %d failures at %d Hz" % [checks,failures,hz])
	quit(1 if failures else 0)
