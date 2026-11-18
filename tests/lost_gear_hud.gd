extends SceneTree
## Real death, persistent guidance, recovery and checkpoint restoration.
const Regions = preload("res://scripts/world_regions.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
var world: Node3D
var actor: CharacterBody3D
var session: Node
var loot: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

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

func shot(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/lost_gear_"+label+".png")

func entries() -> Array:
	return loot.markers.for_owner(actor.inventory.owner_id)

func shows(point: Vector3) -> bool:
	return session.loss_hint.visible and session.loss_hint.text.contains(Regions.grid_label(Regions.grid_at(point)))

func collect(pickup: Node3D) -> bool:
	actor.global_position = pickup.global_position+Vector3(1,0,0)
	await frames()
	return loot.request_pickup(actor.inventory,pickup)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	session = world.inventory_session
	loot = world.loot
	await frames(10)
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	actor.set_physics_process(false)
	check(not session.loss_hint.visible and session.loss_hint.text.is_empty(),"No lost-item overlay appears without an unclaimed death loss")
	loot.death_drop_probability = 1
	actor.global_position = Vector3(0,.05,40)
	actor.weapon_combat.health = 0
	actor.on_combat_defeat()
	await frames(15)
	check(actor.health==1000 and actor.global_position==actor.spawn and entries().size()==1,"A real lethal defeat drops gear and respawns the player normally")
	if entries().is_empty():
		world.queue_free()
		quit(1)
		return
	var first: Node3D = loot.pickups[entries()[0].pickup_id]
	check(shows(first.global_position) and session.loss_hint.text.contains("34 m") and session.loss_hint.text.contains("ALT 0 m") and session.loss_hint.text.contains("1 unclaimed"),"Respawn immediately locates the actual lost pickup with distance, grid and altitude")
	session._process(6.1)
	check(session.notice.text.is_empty() and shows(first.global_position),"Lost-item coordinates survive expiration of the six-second notice")
	session.show_notice("Collected test fragment")
	session._refresh_losses()
	check(session.notice.text=="Collected test fragment" and shows(first.global_position),"Transient collection/save notices cannot replace persistent recovery guidance")
	actor.global_position = Vector3(0,.05,20)
	await frames(15)
	check(session.loss_hint.text.contains("20 m"),"Distance refreshes as the player moves toward lost gear")
	actor.global_position = Vector3(0,.05,-20)
	actor.weapon_combat.health = 0
	actor.on_combat_defeat()
	await frames(15)
	check(entries().size()==2 and session.loss_hint.text.contains("2 unclaimed") and shows(Vector3(0,0,-20)),"Repeated deaths retain both losses and guide the player to the newest one")
	actor.global_position = Vector3(0,.05,30)
	await frames(15)
	check(shows(Vector3(0,0,-20)) and session.loss_hint.text.contains("50 m"),"The newest outstanding loss stays selected when an older loss is closer")
	for resolution: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await frames()
		var label: Label = session.loss_hint
		var rect := label.get_global_rect()
		var text_width := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
		check(root.get_visible_rect().encloses(rect) and text_width<=rect.size.x and rect.end.y<session.notice.get_global_rect().position.y,"Lost-item location fits above short notices at "+str(resolution))
		await shot(str(resolution.x))
	root.size = Vector2i(1280,720)
	session.set_process(false)
	session.resident_dialogue.text = "RESIDENT\nA conversation remains readable above the recovery guidance."
	session.resident_dialogue.show()
	session._refresh_losses()
	check(session.loss_hint.get_global_rect().end.y<=session.resident_dialogue.get_global_rect().position.y,"Recovery guidance moves above an active resident dialogue panel")
	await shot("dialogue")
	session.resident_dialogue.hide()
	session._refresh_losses()
	session.set_process(true)
	var checkpoint := "user://tests/lost_gear_hud.json"
	check(session.save_checkpoint(checkpoint,true),"A checkpoint saves actual unclaimed losses")
	check(await collect(first),"The first lost item can be recovered through the real pickup transaction")
	check(entries().size()==1 and session.loss_hint.text.contains("1 unclaimed") and shows(entries()[0].world_position),"Recovering one item immediately retargets the remaining loss")
	var remaining: Node3D = loot.pickups[entries()[0].pickup_id]
	check(await collect(remaining),"The second lost item can be recovered normally")
	check(not session.loss_hint.visible and session.loss_hint.text.is_empty(),"Recovering the last item removes the persistent overlay")
	await frames() # Let collected pickups leave the physics space before reload.
	check(session.load_checkpoint(checkpoint),"A saved checkpoint restores owned gear and death drops together")
	await frames()
	check(entries().size()==2 and session.loss_hint.visible and session.loss_hint.text.contains("2 unclaimed"),"Reloading restores persistent locations without requiring another death")
	for entry: Dictionary in entries(): loot.pickups[entry.pickup_id].queue_free()
	await frames()
	check(not session.loss_hint.visible and session.loss_hint.text.is_empty(),"Legitimate removal of unclaimed pickups clears the location overlay")
	var foreign := Pickup.new()
	foreign.item_instance = Catalog.create(&"katana")
	foreign.death_owner_id = "other-player"
	loot.add_child(foreign)
	foreign.global_position = Vector3(0,0,-4)
	check(loot.register_pickup(foreign) and not session.loss_hint.visible,"Other players' lost items never appear in the local recovery readout")
	foreign.queue_free()
	await frames()
	check(session.loss_hint.mouse_filter==Control.MOUSE_FILTER_IGNORE and not paused,"Recovery guidance captures no gameplay input and never pauses simulation")
	world.queue_free()
	await process_frame
	print("Lost gear HUD verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
