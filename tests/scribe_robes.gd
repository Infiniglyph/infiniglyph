extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Model = preload("res://scripts/inventory.gd")
var world: Node3D
var p: CharacterBody3D
var session: Node
var checks := 0
var failures := 0
var hz := 60

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

func shot(label: String, offset: Vector3) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 46
	camera.position = p.position+offset
	camera.look_at(p.position+Vector3.UP)
	camera.current = true
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/scribe_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current = true

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.get_slice("=",1))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	root.add_child(world)
	p = world.player
	p.visual.retrieval.enabled = false
	session = world.inventory_session
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(10)
	var inventory: Node = p.inventory
	var weapons_before: Dictionary = inventory.equipment.duplicate()
	var speed_before := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	var capsule: Shape3D = p.get_child(0).shape
	check(not is_instance_valid(p.visual.robe),"Unequipped players do not construct or process garment geometry")
	var shop: CanvasLayer = session.shop
	p.position = shop.anchor()+Vector3(0,0.1,3.2)
	p.velocity = Vector3.ZERO
	await frames(10)
	session.interact()
	check(shop.is_open and shop.offer(&"eternal_scribe_robes").price==0,"The bipyramid exchange offers the Eternal Scribe Robes for free")
	check(shop.buy(&"eternal_scribe_robes") and inventory.count_type(&"eternal_scribe_robes")==1,"Buying robes creates one owned clothing item")
	await shot("shop",Vector3(3,2,5))
	shop.close_menu()
	var iid := ""
	for item: Resource in inventory.items.values():
		if item.item_type_id==&"eternal_scribe_robes": iid = item.instance_id
	check(not inventory.assign(&"up",iid) and not inventory.assign(&"body",inventory.equipment[&"up"]),"Clothing cannot replace a weapon direction, and weapons cannot occupy Body")
	world.loot.host_enabled = false
	check(not world.loot.request_equip(inventory,&"body",iid),"Clients cannot bypass the existing equipment authority")
	world.loot.host_enabled = true
	var ui: CanvasLayer = session.ui
	ui.open_menu()
	ui.select_item(iid)
	ui.activate_selection()
	check(ui._modal_buttons[0].text=="WEAR IN BODY","Inventory exposes an explicit clothing wear action")
	ui.activate_selection()
	var robe: Node3D = p.visual.robe
	check(inventory.equipment.get(&"body")==iid and is_instance_valid(robe) and robe.is_equipped(),"The inventory action equips the visible robe on the existing figure")
	check(inventory.equipment.size()==5 and inventory.equipment[&"up"]==weapons_before[&"up"] and p.combat.resolve_slot(&"up")==&"up","Clothing coexists with all four existing weapon assignments")
	check(speed_before==Vector3(p.walk_speed,p.run_speed,p.boost_speed) and capsule==p.get_child(0).shape,"Clothing does not change speed, responsiveness or collision")
	check(robe.has_back_sigil() and robe.get_front_inscription_count()==6 and robe.get_trail_speck_count()==12 and robe.get_trail_symbol_count()==9,"The source back sigil, six front inscriptions and bounded trails are preserved")
	check(robe.get_external_piece_count()==4 and robe._external_pieces[1].get_parent()==p.visual.joints.LeftArm.get_node("Hinge"),"Both sleeves articulate with the existing shoulder and elbow joints")
	check(robe.global_basis.z.dot(p.visual.global_basis.z)<-0.99,"The Library's -Z garment is correctly fitted to the +Z character")
	var collision_free := robe.find_children("*","CollisionObject3D",true,false).is_empty()
	check(collision_free,"The robe introduces no extra collision or gameplay body")
	check(inventory.eligible_equipped().has(iid),"Equipped clothing follows the existing transferable-gear death/drop rules")
	ui.select_tab(1)
	ui._select_row(4)
	check(ui.equipment_buttons.size()==11 and ui.selected_iid==iid and ui._meta_label.text.contains("COSMETICS"),"The Equipment tab exposes the Body slot with the worn robe")
	await shot("inventory",Vector3(3,2,5))
	ui.close_menu()
	p.position = Vector3(0,0.15,6)
	p.velocity = Vector3.ZERO
	p.visual.rotation.y = PI
	await frames(15)
	await shot("front",Vector3(2,1.3,-4))
	await shot("back",Vector3(-1.2,1.3,4))
	world.controls._request(&"weapon",&"right")
	p.combat.poll(world.controls)
	world.controls._request(&"action",&"special_y")
	p.combat.poll(world.controls)
	await frames(maxi(2,hz/4))
	var w: Node = p.weapon_combat
	check(robe.is_equipped() and not w.active_move.is_empty() and w.rig.left_hand.global_position.distance_to(w.rig.right_hand.to_global(Vector3(0,-0.17,0)))<0.012,"A worn robe preserves the two-handed katana grip during a special")
	world.controls.jump_requested = true
	await frames(2)
	check(p.velocity.y>0 and robe.is_equipped(),"Jump stays available during combat with the robe equipped")
	world.controls.jump_requested = true
	await frames(2)
	check(p.air_step_count==1 and p.velocity.y>7,"Unlimited Sky Jump remains free while robed")
	p.respawn()
	await frames(10)
	var generation: int = robe.get_inscription_generation_count()
	await frames(hz)
	check(robe.get_inscription_generation_count()>generation and not paused,"Living inscriptions continue while the world runs")
	# Exercise the phase cache across a would-be inscription replacement.
	robe._elapsed = 4.79
	check(p.dodge.start(Vector3.RIGHT),"Dodge remains available with clothing equipped")
	var meshes: Array = robe.find_children("*","MeshInstance3D",true,false)
	var first: Node = meshes[0]
	await frames(maxi(1,hz/10))
	check(is_instance_valid(first) and not world.loot.request_equip(inventory,&"body",iid),"A live phase keeps its cached garment meshes stable and rejects outfit replacement")
	await frames(hz)
	var restored := true
	for mesh: GeometryInstance3D in robe.find_children("*","GeometryInstance3D",true,false):
		restored = restored and mesh.material_override==null
	check(not p.dodge.active and p.visual.scale.is_equal_approx(Vector3.ONE) and restored,"The complete outfit restores after the dodge fade")
	check(session.save_checkpoint("user://tests/scribe-robes.json",true),"Worn clothing saves through the existing inventory checkpoint")
	check(world.loot.request_unequip(inventory,&"body") and not robe.visible and not robe.is_processing(),"Unequip hides the entire garment and stops cloth processing")
	var sleeves_hidden := true
	for sleeve: Node3D in robe._external_pieces: sleeves_hidden = sleeves_hidden and not sleeve.visible
	check(sleeves_hidden,"Unequipping also hides external sleeves")
	check(session.load_checkpoint("user://tests/scribe-robes.json") and robe.is_equipped(),"Reload restores the owned garment and equipped appearance")
	var prior: Dictionary = inventory.serialize()
	var old_save := prior.duplicate(true)
	old_save.equipment.erase("body")
	var restored_old := Model.new()
	check(restored_old.restore(old_save) and not restored_old.equipment.has(&"body"),"Existing version-one saves without clothing still restore")
	restored_old.free()
	p.respawn()
	await frames(5)
	check(robe.is_equipped() and inventory.equipped_item(&"body").instance_id==iid,"Ordinary respawn preserves the owned outfit")
	p.position = Vector3(0,0.15,6)
	p.velocity = Vector3.ZERO
	await frames(8)
	var dropped: bool = world.loot.request_drop(inventory,iid,1,p.position+Vector3.RIGHT*1.5)
	check(dropped and not robe.is_equipped() and inventory.equipped_item(&"body")==null,"Dropping worn clothing removes its appearance without duplicating ownership")
	var pickup: Node3D
	for candidate: Node3D in world.loot.pickups.values():
		if candidate.item_instance.instance_id==iid: pickup = candidate
	check(is_instance_valid(pickup) and world.loot.request_pickup(inventory,pickup),"Dropped clothing can be collected through the normal loot pipeline")
	check(world.loot.request_equip(inventory,&"body",iid) and robe.is_equipped() and p.visual.find_children("EternalScribeRobe","Node3D",true,false).size()==1,"Re-equipping reuses one robe and its bounded geometry")
	world.queue_free()
	await frames()
	print("Scribe robes verification: %d checks, %d failures at %d Hz" % [checks,failures,hz])
	quit(1 if failures else 0)
