extends SceneTree
## Native production-world review of the held quill and aerial writing.
const Catalog = preload("res://scripts/item_catalog.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var controls: Node
var view: Camera3D

func _initialize() -> void: call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func key(code: Key, held: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = held
	controls._combat_input(event)

func shot(label: String, offset: Vector3, focus: Vector3 = Vector3(0,1.05,0)) -> void:
	view.global_position = p.global_position+offset
	view.look_at(p.global_position+focus)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/equation_gameplay_"+label+".png")
	print("CAPTURE ",label)
	var ink: Node = p.weapon_combat.equation_trace
	if is_instance_valid(ink): print("TRACE BUDGET: ",ink.sections.size()," sections / ",ink.last_contact_microseconds," us last contact pass")

func run() -> void:
	create_timer(55).timeout.connect(func(): quit(2))
	Engine.physics_ticks_per_second = 60
	DirAccess.make_dir_recursive_absolute("res://captures")
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	p = world.player
	p.visual.retrieval.enabled = false
	controls = Intent.new()
	world.add_child(controls)
	p.controls = controls
	world.camera_rig.controls = controls
	# The input source is replaced only in this capture fixture.
	controls.special_hold_cancelled.connect(p.combat.cancel_charge)
	p.global_position = Vector3(0,.02,10)
	p.velocity = Vector3.ZERO
	for spec: Array in [[&"eturnull_manuscript",&"down"],[&"eturnull_hat",&"head"],[&"eternal_scribe_robes",&"body"]]:
		var item: Resource = Catalog.create(spec[0])
		p.inventory.add_item(item)
		p.inventory.assign(spec[1],item.instance_id)
	p.combat.selected_slot = &"down"
	p.combat.sheathed = false
	p.weapon_combat.sync_rig()
	p.visual.sync_clothing(p.inventory)
	world.camera_rig.yaw = 0
	world.camera_rig.pitch = 0
	view = Camera3D.new()
	view.fov = 55
	world.add_child(view)
	view.current = true
	await frames(30)
	# Freeze only this brief review sample at a deterministic post-recovery
	# instant. A slow native readback must not outlast the 0.65-second afterglow.
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	var presentation: Node3D=p.weapon_combat.rig.models[&"eturnull_manuscript"].right
	presentation.set_process(false)
	p.weapon_combat._on_action(&"attack_right",&"down")
	var cast: Dictionary=p.weapon_combat.active_move.duplicate()
	p.weapon_combat.elapsed=float(cast.hits[0])
	p.weapon_combat.strike(0)
	p.weapon_combat.elapsed=float(cast.duration)-.001
	p.weapon_combat._physics_process(.01)
	presentation._process(float(cast.duration)-float(cast.hits[0])+.15)
	await shot("cast_afterglow",Vector3(6,3,-4.4),Vector3(0,1,-3.5))
	print("CAST AFTERGLOW: move finished=",p.weapon_combat.active_move.is_empty()," / visible echoes=",presentation.afterglows.filter(func(e: Dictionary): return e.node.visible).size())
	if "--cast-only" in OS.get_cmdline_user_args():
		quit()
		return
	presentation.set_process(true)
	p.set_physics_process(true)
	p.weapon_combat.set_physics_process(true)
	await frames(45)
	key(KEY_V)
	await frames(25)
	await shot("ready",Vector3(1.7,1.65,-3.0))
	key(KEY_Q)
	controls.move = Vector2.LEFT
	controls.sprint = true
	await frames(70)
	controls.move = Vector2.ZERO
	await shot("x",Vector3(2.2,1.8,-4.2))
	key(KEY_Q,false)
	await frames(5)
	key(KEY_R)
	controls.move = Vector2.RIGHT
	key(KEY_SPACE)
	await frames(12)
	key(KEY_SPACE,false)
	key(KEY_SPACE)
	await frames(24)
	key(KEY_SPACE,false)
	controls.move = Vector2.ZERO
	await shot("sky_circle",Vector3(2.4,.6,-4.4))
	key(KEY_R,false)
	key(KEY_V,false)
	print("EQUATION GAMEPLAY NATIVE: four captures")
	quit()
