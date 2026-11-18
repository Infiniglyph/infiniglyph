extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Data = preload("res://scripts/respawn_glyph_data.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var service: Node
var controls: Intent
var checks:=0
var failures:=0
var hz:=60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks+=1
	if ok: print("PASS: ",title)
	else:
		failures+=1
		push_error("FAIL: "+title)

func frames(count: int=2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func place(point: Vector3) -> void:
	p.global_position=point
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	p.visual.rebase_after_phase()
	await frames(10)

func glyph(id: StringName) -> Resource:
	var item: Resource=Catalog.create(id)
	p.inventory.add_item(item)
	if item.quantity>0: return item
	for owned: Resource in p.inventory.items.values():
		if owned.item_type_id==id: return owned
	return null

func die() -> void:
	p.receive_hit(5000,p.combat_point()+Vector3.BACK)

func button(code: JoyButton) -> void:
	var event:=InputEventJoypadButton.new()
	event.button_index=code
	event.pressed=true
	service._input(event)

func run() -> void:
	create_timer(55).timeout.connect(func():push_error("RESPAWN TEST WATCHDOG");quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	p=world.player
	service=world.respawn_glyphs
	controls=Intent.new()
	root.add_child(controls)
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	p.visual.retrieval.enabled=false
	await place(Vector3(0,.05,8))
	check(Catalog.get_definition(&"respawn_glyph")!=null and Catalog.get_definition(&"home_respawn_glyph")!=null,"Both placeable glyph definitions exist")
	var home:=glyph(&"home_respawn_glyph")
	check(world.loot.request_respawn_glyph(p.inventory,home.instance_id),"Home glyph places through the ownership authority")
	var home_point:=Data.point(p.inventory.respawn_points.home)
	check(p.inventory.count_type(&"home_respawn_glyph")==0 and service.markers.size()==1,"Placement consumes one item and creates one reusable owned marker")
	await place(Vector3(3,.05,8))
	var temporary:=glyph(&"respawn_glyph")
	check(world.loot.request_respawn_glyph(p.inventory,temporary.instance_id),"Personal glyph places independently of home")
	check(service.markers.size()==2 and p.inventory.respawn_points.size()==2,"One active marker of each kind is retained")
	await place(Vector3(-3,.05,8))
	temporary=glyph(&"respawn_glyph")
	check(world.loot.request_respawn_glyph(p.inventory,temporary.instance_id),"Placing another personal glyph replaces its previous destination")
	await frames(2)
	var personal_point:=Data.point(p.inventory.respawn_points.respawn)
	check(service.markers.size()==2 and Data.point(p.inventory.respawn_points.home)==home_point,"Replacement preserves home and leaves exactly two markers")
	var unused:=glyph(&"respawn_glyph")
	p.global_position.y+=3
	p.set_physics_process(false)
	await frames(2)
	check(not world.loot.request_respawn_glyph(p.inventory,unused.instance_id) and p.inventory.get_item(unused.instance_id)!=null,"Unsupported placement is rejected without consuming an item")
	p.set_physics_process(true)
	await place(Vector3(0,.05,10))
	die()
	check(service.waiting and p.health==0 and p.transition_locked and not controls.gameplay_enabled and not paused,"Death opens a choice, locks local actions and keeps the world live")
	check(service._keys==["respawn","home","default"],"Personal, home and default destinations are offered")
	if "--capture" in OS.get_cmdline_user_args():
		await frames(2)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/respawn_choice.png")
	button(JOY_BUTTON_DPAD_DOWN)
	button(JOY_BUTTON_A)
	check(not service.waiting and p.health==p.weapon_combat.max_health and p.global_position.distance_to(home_point)<.1 and controls.gameplay_enabled,"Controller navigation reconstructs at Home")
	await frames(3)
	die()
	var confirm:=InputEventKey.new()
	confirm.keycode=KEY_ENTER
	confirm.pressed=true
	service._input(confirm)
	check(p.global_position.distance_to(personal_point)<.1 and p.inventory.respawn_points.size()==2,"Keyboard confirmation chooses the personal glyph; both points remain reusable")
	var travel: Node=world.dungeon_travel
	travel._set_location(travel.pyramid_id)
	await place(Vector3(0,.05,-8))
	temporary=glyph(&"respawn_glyph")
	check(world.loot.request_respawn_glyph(p.inventory,temporary.instance_id),"A personal glyph can bind a clear dungeon floor")
	var dungeon_point:=Data.point(p.inventory.respawn_points.respawn)
	check(service.markers.respawn.get_world_3d()==travel.interior.get_world_3d(),"Dungeon marker belongs to its own World3D")
	die()
	service.choose("home")
	check(not travel.inside() and p.global_position.distance_to(home_point)<.1 and p.get_world_3d()==travel.outside_root.get_world_3d(),"Choosing Home reconstructs correctly across the instance boundary")
	await frames(3)
	die()
	service.choose("respawn")
	check(travel.inside() and p.global_position.distance_to(dungeon_point)<.1 and p.get_world_3d()==travel.interior.get_world_3d(),"Choosing the personal glyph returns to its saved dungeon floor")
	var checkpoint: String="res://.godot/respawn-glyphs-checkpoint-"+str(hz)+".json"
	check(world.inventory_session.save_checkpoint(checkpoint,true),"Placed glyph ownership and destination save through the existing checkpoint")
	p.inventory.respawn_points.clear()
	p.inventory.changed.emit()
	check(world.inventory_session.load_checkpoint(checkpoint) and p.inventory.respawn_points.size()==2,"Checkpoint restores both reusable destinations")
	await frames(2)
	check(service.markers.size()==2 and service.markers.respawn.get_world_3d()==travel.interior.get_world_3d(),"Loaded markers rebuild once in their correct worlds")
	var saved: Dictionary=p.inventory.serialize()
	var corrupt: Dictionary=saved.duplicate(true)
	corrupt.respawn_points.home.position[0]=NAN
	check(not p.inventory.restore(corrupt) and p.inventory.serialize()==saved,"Nonfinite anchors are rejected atomically")
	corrupt=saved.duplicate(true)
	corrupt.respawn_points.home.location="pyramid/somebody_else"
	check(not p.inventory.restore(corrupt),"A foreign player's instance cannot be installed as an owned respawn destination")
	await frames(2)
	die()
	service.choose("default")
	check(p.global_position.distance_to(travel.interior.spawn_anchor.global_position)<.1 and p.inventory.respawn_points.size()==2,"Default spawn remains selectable without deleting either glyph")
	var legacy: Dictionary=saved.duplicate(true)
	legacy.erase("respawn_points")
	check(p.inventory.restore(legacy) and p.inventory.respawn_points.is_empty(),"Older checkpoints without placed glyphs remain compatible")
	await frames(3)
	die()
	check(not service.waiting and p.health>0,"Without glyphs, the established immediate default respawn is preserved")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	print("RESPAWN GLYPHS ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
