extends SceneTree
## Production city board and counter geometry, using real civic source lookup.
var world: Node3D
var ui: CanvasLayer
var view: Camera3D
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func reveal() -> void:
	for i in range(10):
		ui.finish_line()
		if ui._queue.is_empty(): break
		ui.advance()
	ui.finish_line()
func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await frames(4)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/communication_"+label+".png")
	print("CAPTURE ",label)
func premises(building: String,label: String) -> void:
	var buildings: Node = world.building_civilization
	check(buildings.model.records.has(building),"The actual "+label+" has an assigned city building")
	if not buildings.model.records.has(building): return
	var row: Dictionary = buildings.model.records[building]
	var base := Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
	world.player.global_position = base+Vector3(0,.12,0)
	world.player.velocity = Vector3.ZERO
	view.global_position = base+Vector3(3,2.7,4)
	view.look_at(base+Vector3(0,1.5,-2))
	await frames(3)
	check(buildings.interact() and buildings.current==building and buildings.menu.is_open,"The "+label+" opens its real local building menu")
	buildings._guild_terminal()
	ui._process(.15)
	await frames(2)
	check(ui.is_open and not buildings.menu.is_open and ui._terminal_mode() and ui._panel.is_visible_in_tree() and ui._terminal_text.is_visible_in_tree(),"The "+label+" hands its building menu to the existing institution interface")
	check(not ui._bubble.is_visible_in_tree() and not ui._voice.playing and ui.presentation_source(String(row.owner))==null,"The "+label+" presents local terminal text without fabricating a speaker or electronic voice")
	reveal()
	await frames(2)
	check(root.get_visible_rect().encloses(ui._panel.get_global_rect()),"The "+label+" institution choices stay inside the viewport")
	await shot(label.replace(" ","_")+"_terminal")
	world.player.global_position = base+Vector3(float(row.size[0])+10,.12,0)
	ui._process(.1)
	check(not ui.is_open and not ui._panel.is_visible_in_tree() and not ui._voice.playing,"Leaving the "+label+" closes its terminal text, choices, and voice channel")
func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Production local speech watchdog"); quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.world_memory_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.dungeon_enemies_enabled = false
	root.add_child(world)
	ui = world.communication
	world.player.visual.retrieval.enabled = false
	world.civilization.simulation_enabled = false
	for i in range(480):
		await frames(1)
		if world.civic_interactions.initialized: break
	check(world.civic_interactions.initialized,"The real civic authorities initialize for production speech review")
	if not world.civic_interactions.initialized: world.queue_free(); await frames(); quit(1); return
	world.civic_interactions.set_process(false)
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	world.player.set_physics_process(false)
	view = Camera3D.new()
	world.add_child(view)
	view.fov = 58
	view.current = true
	var board: Dictionary = {}
	var reception: Dictionary = {}
	for point: Dictionary in world.civilian_services.establishments.points:
		if point.get("id")=="board_security": board=point
		if point.get("id")=="reception": reception=point
	check(not board.is_empty() and not reception.is_empty(),"The actual guild board and reception retain physical interaction anchors")
	if board.is_empty() or reception.is_empty(): world.queue_free(); await frames(); quit(1); return
	world.player.global_position = board.anchor.global_position+Vector3(1.5,-1.35,0)
	world.player.velocity = Vector3.ZERO
	view.global_position = board.anchor.global_position+Vector3(5,1.9,4)
	view.look_at(board.anchor.global_position+Vector3(0,.5,0))
	await frames(4)
	check(world.civic_interactions.begin_service(board,""),"The real Security board opens its close-range conversation")
	reveal()
	await frames(3)
	check(ui.is_open and ui._bubble.is_visible_in_tree() and ui._panel.is_visible_in_tree() and not paused,"Production board instructions appear overhead while contextual choices remain live")
	check(root.get_visible_rect().encloses(ui._bubble.get_global_rect()) and root.get_visible_rect().encloses(ui._panel.get_global_rect()),"Actual board translation and all current guild choices fit the viewport")
	await shot("board_overhead")
	ui.close_conversation("fixture")
	var receptionist: Node3D
	for person: Node3D in world.civilian_services._people:
		if person.get_meta("natural_resident_id","")=="guild_receptionist": receptionist=person
	check(is_instance_valid(receptionist),"The receptionist is an actual in-world Code Form")
	if not is_instance_valid(receptionist): world.queue_free(); await frames(); quit(1); return
	var id: String = world.civilization.id_for_source(receptionist)
	world.player.global_position = reception.anchor.global_position+Vector3(0,-1.2,1.0)
	world.player.velocity = Vector3.ZERO
	# This is the normal counter approach: camera behind the customer, with the
	# keeper physically behind the counter rather than at its interaction marker.
	view.global_position = reception.anchor.global_position+Vector3(3.5,2.0,3.5)
	view.look_at(receptionist.global_position+Vector3.UP*1.7)
	await frames(4)
	check(world.civic_interactions.begin_service(reception,id),"The actual keeper remains reachable across the reception counter")
	check(ui.presentation_source(id)==receptionist,"Keeper dialogue is anchored to the actual entity rather than the counter's marker")
	reveal()
	await frames(3)
	check(ui.is_open and ui._bubble.is_visible_in_tree(),"Counter geometry does not hide an otherwise valid nearby keeper conversation")
	await shot("reception_overhead")
	ui.close_conversation("fixture")
	for i in range(120):
		if world.building_civilization._guild_premises_ready: break
		await frames(1)
	check(world.building_civilization._guild_premises_ready,"Starter guild and faction headquarters finish assigning real premises")
	await premises(String(world.quest_system.organizations.guilds.dark_box.headquarters),"Dark Box guild")
	await premises(String(world.quest_system.organizations.factions.security.headquarters),"Security faction")
	world.queue_free()
	await frames(3)
	print("PRODUCTION LOCAL COMMUNICATION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
