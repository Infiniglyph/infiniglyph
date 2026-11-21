extends SceneTree
## Native renderer review using the real player, item, rig and combat poses.
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Wand = preload("res://scripts/wand_presentation.gd")
var world: Node3D
var p: CharacterBody3D
var w: Node
var view: Camera3D
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func shot(label: String, from: Vector3, focus: Vector3) -> void:
	if "--no-capture" in OS.get_cmdline_user_args(): return
	view.global_position = from
	view.look_at(focus)
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/wand_"+label+".png")
	print("CAPTURE ",label)
func pose(delta: float, elapsed: float) -> void:
	p.visual.animate(delta,Vector3.ZERO,true)
	w.elapsed = elapsed
	w.apply_pose(delta)
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute("res://captures")
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	world.civilization_enabled = false
	root.add_child(world)
	p = world.player
	w = p.weapon_combat
	p.visual.retrieval.enabled = false
	await frames(12)
	for child: Node in world.get_children():
		if child is Node3D and child!=p: child.hide()
		if child is CanvasLayer: child.hide()
		if child!=p:
			child.set_physics_process(false)
			child.set_process(false)
	for resident: Node in world.population.get_children():
		resident.set_physics_process(false)
		resident.set_process(false)
	p.set_physics_process(false)
	w.set_physics_process(false)
	p.position = Vector3(0,.02,10)
	p.velocity = Vector3.ZERO
	p.visual.rotation.y = 0
	w._facing = Vector3.BACK
	view = Camera3D.new()
	view.fov = 42
	world.add_child(view)
	view.current = true
	var item: Resource = Catalog.create(&"dark_box_arc_wand")
	p.inventory.add_item(item)
	p.inventory.assign(&"up",item.instance_id)
	p.combat.selected_slot = &"up"
	p.combat.sheathed = false
	w.sync_rig()
	for i in range(30): pose(1.0/60,0)
	var model: Node3D = w.rig.models[&"dark_box_arc_wand"].right
	check(model.get_parent()==w.rig.left_hand,"Wand occupies the real anatomical right hand with a free offhand")
	var emitter: Node3D = model.get_node("WandEmitter")
	check(emitter.global_position.y>1.15 and emitter.global_position.distance_to(p.global_position)<2.0,"Dueling carry keeps its emitter ahead and above the waist")
	await shot("ready",p.position+Vector3(-2.8,1.65,3.0),p.position+Vector3(0,1.03,0))
	var controller := p.global_transform
	var anchor: Vector3 = w.rig.left_hand.position
	for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
		w.cancel()
		w.active_move = Library.move(&"dark_box_arc_wand",action)
		w.body.begin(Vector3.BACK)
		var finite := true
		for i in range(ceili(float(w.active_move.duration)*120)+1):
			var elapsed := minf(i/120.0,float(w.active_move.duration))
			pose(1.0/120,elapsed)
			for limb: String in ["RightArm","LeftArm","LeftLeg","RightLeg"]:
				finite = finite and p.visual.joints[limb].global_transform.is_finite() and p.visual.joints[limb].get_node("Hinge").global_transform.is_finite()
		check(finite and w.rig.left_hand.position.distance_to(anchor)<.00001,"Actual "+String(action)+" IK remains finite and retains its wrist attachment")
		# Capture the authored release pose after a fresh visual warmup.
		w.body.release(true)
		var release: float = w.active_move.hits[0]
		for i in range(ceili(release*120)+1): pose(1.0/120,minf(i/120.0,release))
		await shot(String(action),p.position+Vector3(-2.8,1.65,3.0),p.position+Vector3(0,1.03,0))
	check(p.global_transform==controller and p.velocity.is_zero_approx(),"Casting gestures never move or rotate the physical controller")
	w.cancel()
	p.combat.sheathed = true
	w.sync_rig()
	for i in range(30): pose(1.0/60,0)
	var back: Node3D = w.rig.models[&"dark_box_arc_wand"].stowed_blades[0]
	check(back.get_node("WandEmitter").global_position.y>1.1,"Stowed wand remains high on the back and clears the legs")
	await shot("stowed",p.position+Vector3(2.7,1.6,-3),p.position+Vector3(0,1.05,0))
	p.hide()
	var colors := Database.all().filter(func(entry: Dictionary): return entry.family=="wand" and entry.id not in ["thothic_scepter","ahkmets_scepter"])
	check(colors.size()==8,"Exactly eight colored wand variants share the presentation")
	for i in range(colors.size()):
		var entry: Dictionary = colors[i]
		var display := Wand.model(Color(entry.geometry.tint))
		world.add_child(display)
		display.position = Vector3((i-3.5)*.26,.1,7)
		for child: Node in display.get_children():
			if child is VisualInstance3D: child.layers=2
	view.cull_mask = 2
	await shot("palette",Vector3(0,.38,9.35),Vector3(0,.38,7))
	world.queue_free()
	await process_frame
	print("WAND NATIVE RIG: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
