extends SceneTree
## Native Compatibility review; all artwork is the actual gameplay brush/IK/trail.
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Brush = preload("res://scripts/paintbrush_presentation.gd")
const Patterns = preload("res://scripts/paintbrush_patterns.gd")
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
	p.combat.poll(controls)
func shot(label: String, from: Vector3, focus: Vector3) -> void:
	view.global_position = from
	view.look_at(focus)
	await frames(4) # Let new native meshes, camera and material variants reach the renderer.
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/paintbrush_"+label+".png")
	print("CAPTURE ",label)
func equip_color(color: String) -> void:
	controls.reset_combat_input()
	p.weapon_combat.cancel()
	var item: Resource = Catalog.create(StringName("paintbrush_"+color))
	p.inventory.add_item(item)
	p.inventory.assign(&"down",item.instance_id)
	p.combat.selected_slot = &"down"
	p.combat.sheathed = false
	p.weapon_combat.sync_rig()
func step(velocity: Vector3, airborne: bool = false) -> void:
	p.velocity = velocity
	p.position += velocity/60
	p.visual.animate(1.0/60,velocity,not airborne)
	p.weapon_combat._physics_process(1.0/60)
	var paint: Node = p.weapon_combat.paint_trace
	if is_instance_valid(paint): paint._physics_process(1.0/60)

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
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
	controls.special_hold_cancelled.connect(p.combat.cancel_charge)
	world.camera_rig.yaw = 0
	world.camera_rig.pitch = 0
	await frames(12)
	for resident: Node in world.population.get_children():
		resident.set_physics_process(false)
		resident.set_process(false)
		if resident is Node3D: resident.hide()
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	view = Camera3D.new()
	view.fov = 55
	world.add_child(view)
	view.current = true
	if "--ready-only" in OS.get_cmdline_user_args():
		equip_color("violet")
		p.position = Vector3(0,.02,10)
		p.visual.rotation.y = 0
		for i in range(24): step(Vector3.ZERO)
		await shot("ready",p.global_position+Vector3(-3.2,1.8,2.7),p.global_position+Vector3(0,1.15,0))
		quit()
		return
	var examples := [["cyan",KEY_Q,false,"squares"],["mint",KEY_R,false,"triangles"],["violet",KEY_Q,true,"crosses"],["ember",KEY_R,true,"aerial_circles"]]
	for spec: Array in examples if not "--palette-only" in OS.get_cmdline_user_args() else []:
		equip_color(spec[0])
		p.position = Vector3(0,.02,10)
		for i in range(24): step(Vector3.ZERO)
		if spec[2]: key(KEY_V)
		key(spec[1])
		for i in range(105): step(Vector3(1.65,.75 if spec[3]=="aerial_circles" else 0,0),spec[3]=="aerial_circles")
		key(spec[1],false)
		if spec[2]: key(KEY_V,false)
		var paint: Node = p.weapon_combat.paint_trace
		paint.redraw()
		paint.set_physics_process(false)
		await shot(spec[3],p.global_position+Vector3(2.8,1.85,-4.0),p.global_position+Vector3(-.8,1.2,0))
		print("PAINT BUDGET: ",paint.sections.size()," sections / ",paint.last_contact_microseconds," us last contact pass")
		paint.clear()
	# Actual native batch readback, plus all eight brush models and pigments.
	p.visual.hide()
	equip_color("violet")
	var palette := ["cyan","violet","gold","mint","pink","blue","silver","ember"]
	var trace: Node = p.weapon_combat.ensure_paint_trace()
	for i in range(palette.size()):
		var color := Color(Database.get_item(StringName("paintbrush_"+palette[i])).geometry.tint)
		var brush := Brush.model(color)
		world.add_child(brush)
		brush.position = Vector3((i-3.5)*.8,.95,5)
		for child: Node in brush.get_children():
			if child is VisualInstance3D: child.layers = 2
		trace.tint = color
		trace.append_section(Patterns.mark(&"square",brush.position+Vector3.UP*.8,Basis.IDENTITY,.21))
	trace.redraw()
	trace.set_physics_process(false)
	trace.layers = 2
	view.cull_mask = 2 # Review pigment without city geometry occluding the swatches.
	var matches := true
	for i in range(palette.size()):
		var expected := Color(Database.get_item(StringName("paintbrush_"+palette[i])).geometry.tint)
		var actual: Color = trace.multimesh.get_instance_color(i*4)
		matches = matches and actual.to_html(false)==expected.to_html(false)
		print("NATIVE PAINT COLOR ",palette[i]," expected=",expected.to_html(false)," actual=",actual.to_html(false))
	await shot("palette",Vector3(0,2.0,-2.8),Vector3(0,1.3,5))
	print("PAINTBRUSH NATIVE: color batch match=",matches)
	quit(0 if matches else 1)
