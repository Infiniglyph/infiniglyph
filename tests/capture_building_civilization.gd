extends SceneTree
## Native production review. --capture-page selects one first readback to avoid
## this Intel/ANGLE driver's cached-font omissions after repeated UI captures.
const Catalog=preload("res://scripts/item_catalog.gd")
var world: Node3D
var properties: Node
var camera: Camera3D
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func place(at: Vector3) -> void:
	world.player.global_position=at; world.player.velocity=Vector3.ZERO
	world.player.fall_damage.reset(); world.player.visual.rebase_after_phase()
	world.controls.set_gameplay_enabled(true)
	await frames(5)
func selected(page: String) -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-page="): return argument.get_slice("=",1)==page
	return true
func shoot(page: String,from: Vector3,focus: Vector3,menu: CanvasLayer=null) -> void:
	if not selected(page): return
	camera.global_position=from; camera.look_at(focus); camera.make_current()
	world.camera_rig.camera.global_transform=camera.global_transform
	for i in range(30): await process_frame; await RenderingServer.frame_post_draw
	# Flush a complete settled native frame before the first readback. This is
	# fixture-only: normal menus retain their ordinary live rendering behavior.
	RenderingServer.force_draw(false)
	if RenderingServer.has_method("force_sync"): RenderingServer.call("force_sync")
	if menu!=null:
		var fits:=true
		for control: Control in menu._screen.find_children("*","Control",true,false):
			if control.is_visible_in_tree() and (control is Label or control is Button):
				fits=fits and root.get_visible_rect().encloses(control.get_global_rect())
		check(fits,"Actual "+page+" controls and text stay inside the native viewport")
	check(root.get_texture().get_image().save_png("res://.godot/civic-building-"+page+".png")==OK,"Native "+page+" capture saves")
func run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Building native capture watchdog"); quit(2))
	root.size=Vector2i(1280,720); root.content_scale_size=Vector2i(1280,720)
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false; world.world_memory_enabled=false
	world.district_life_enabled=false; world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false; world.neon_glow_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	world.civilization.simulation_enabled=false
	world.player.visual.retrieval.enabled=false; world.sparring_partner.visual.retrieval.enabled=false
	for i in range(400):
		await frames(1)
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	properties=world.building_civilization
	check(properties.ready_for_use and properties._guild_premises_ready,"Production shell and institution authorities finish initialization")
	world.civic_interactions.set_process(false)
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	world.camera_rig.set_process(false); world.camera_rig.set_physics_process(false)
	for layer: CanvasLayer in world.find_children("*","CanvasLayer",true,false):
		if layer!=properties.menu and layer!=world.career_menu.menu: layer.hide()
	var hud: Node=world.find_child("CombatHUD",true,false)
	if hud is CanvasItem: hud.hide()
	world.player.visual.hide()
	camera=Camera3D.new(); camera.far=1800; camera.fov=70; world.add_child(camera)
	var descriptor: Dictionary={}
	for row: Dictionary in properties.descriptors.values():
		if row.manual_review or row.region!="city" or not properties.model.records[row.id].owner.is_empty() or row.size.x<18: continue
		descriptor=row; break
	check(not descriptor.is_empty(),"A real vacant city shell supplies the review room")
	if descriptor.is_empty(): world.queue_free(); await frames(); quit(1); return
	var base: Vector3=descriptor.point
	await place(base+Vector3(0,.04,0))
	properties._process(1)
	properties.current=String(descriptor.id)
	# Prepare authoritative contents before constructing the first native page;
	# repeated page replacement triggers this driver's font-atlas readback issue.
	properties.model.claim(String(descriptor.id),"player",float(world.civilization.world_seconds))
	properties.model.set_use(String(descriptor.id),"player","workshop",float(world.civilization.world_seconds))
	var specs: Array=[{ "type":&"basic_bed","at":[-4.0,0.0,-4.0] },{ "type":&"single_chair","at":[4.0,0.0,4.0] },{ "type":&"crafting_station","at":[-4.0,0.0,4.0] }]
	for spec: Dictionary in specs:
		var item: Resource=Catalog.create(spec.type)
		world.player.inventory.add_item(item)
		check(properties.install(String(descriptor.id),"player",world.player.inventory,item.instance_id,spec.at,0),"Actual owned "+String(spec.type)+" installs for native review")
	properties._process(1)
	check(properties.interact(),"An actually occupied hollow building opens its renovation authority")
	await shoot("renovation",base+Vector3(0,2.4,7),base+Vector3(-1,1,-3),properties.menu)
	properties.menu.close_menu()
	await shoot("interior",base+Vector3(0,2.5,7),base+Vector3(-2,1.1,-3))
	var guild: Dictionary=world.quest_system.organizations.guild("dark_box")
	var hq: Dictionary=properties.descriptors[String(guild.headquarters)]
	var front: float=float(hq.size.z)*.5
	await place(hq.exit)
	await shoot("guild",hq.point+Vector3(0,4.7,front+13),hq.point+Vector3(0,3.2,front))
	var native: String=guild.leader
	world.careers.model.synchronize_positions(native)
	var native_position: Vector3=world.civic_interactions.position_for(native)
	check(native_position.is_finite(),"The native guild leader retains a real physical inspection position")
	if native_position.is_finite():
		await place(native_position+Vector3(0,.2,1.5))
		check(world.career_menu.open(native),"The actual nearby native exposes read-only career inspection")
		await shoot("career",native_position+Vector3(0,2.5,6),native_position+Vector3(0,1,0),world.career_menu.menu)
		world.career_menu.close_menu()
	print("Building native review: ",checks," checks, ",failures," failures")
	world.queue_free(); await frames(3); quit(1 if failures else 0)
