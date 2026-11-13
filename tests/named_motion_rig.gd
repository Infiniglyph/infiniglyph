extends SceneTree
## Sample the actual player skeleton through every combo/art in each motion cut.
const Database = preload("res://scripts/equipment_database.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
var checks := 0
var failures := 0
var hz := 60
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")
func run() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	var p: CharacterBody3D = world.player
	p.visual.retrieval.enabled = false
	world.population.set_physics_process(false)
	p.position = Vector3(0,.1,8)
	for i in range(20):
		await physics_frame
		await process_frame
	p.set_physics_process(false)
	var w: Node = p.weapon_combat
	w.set_physics_process(false)
	var baseline := p.global_transform
	var pace := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	var cuts: Dictionary = {}
	for entry: Dictionary in Database.all():
		if not entry.has("motion_set") or cuts.has(entry.motion_set.cut): continue
		cuts[entry.motion_set.cut] = entry
	for cut: String in cuts:
		var entry: Dictionary = cuts[cut]
		var item: Resource = Catalog.create(StringName(entry.id))
		p.inventory.add_item(item)
		world.loot.request_equip(p.inventory,&"right",item.instance_id)
		p.combat.selected_slot = &"right"
		p.combat.sheathed = false
		w.sync_rig()
		var finite := true
		var supported := true
		var grip := true
		var forward := true
		var backward_samples: Array = []
		var hand_origin: Vector3 = w.rig.right_hand.position
		for action: StringName in [&"attack_right",&"attack_left",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			for combo in range(3 if action in [&"attack_right",&"attack_left"] else 1):
				w.cancel()
				w.active_move = w.move_for(&"right",action)
				# Inspect the requested stage directly without a live hit resolver.
				w.active_move = preload("res://scripts/weapon_library.gd").move(StringName(entry.id),action,combo)
				w.body.begin(Vector3.BACK)
				for frame in range(ceili(float(w.active_move.duration)*hz)+1):
					p.visual.animate(1.0/hz,Vector3.ZERO,true)
					w.elapsed = minf(frame/float(hz),float(w.active_move.duration))
					w.apply_pose(1.0/hz)
					for contact: float in w.active_move.hits:
						if absf(w.elapsed-contact)>1.5/hz: continue
						var up: Vector3 = p.visual.global_basis.inverse()*p.visual.chest.global_basis.y
						forward = forward and up.z>.025 and up.y>0
						if up.z<=.025 or up.y<=0:
							backward_samples.append([action,combo,snappedf(w.elapsed,.001),up])
					for name: String in ["LeftArm","RightArm","LeftLeg","RightLeg"]:
						var joint: Node3D = p.visual.joints[name]
						finite = finite and joint.global_transform.is_finite() and joint.get_node("Hinge").global_transform.is_finite()
					for name: String in ["LeftLeg","RightLeg"]:
						var ankle: Vector3 = p.visual.joints[name].get_node("Hinge").to_global(Vector3(0,-.45,0))
						supported = supported and ankle.y>p.global_position.y-.055
					if w.active_move.get("grip_mode")=="support":
						var support: Vector3 = w.rig.right_hand.to_global(Vector3(0,-.17,0))
						grip = grip and w.rig.left_hand.global_position.distance_to(support)<.025
		check(finite and supported and grip,"All "+cut+" combo/art poses keep finite joints, clear soles and a reachable shared grip")
		check(forward,"The "+cut+" swings drive forward at their actual contact frames: "+str(backward_samples))
		check(w.rig.right_hand.position.distance_to(hand_origin)<.00001,"The "+cut+" grip retains its local wrist anchor throughout the sequence")
		w.cancel()
		p.visual.clear_combat_pose()
		p.inventory.take_item(item.instance_id,1)
	check(cuts.size()==15 and p.global_transform==baseline and p.velocity.is_zero_approx() and Vector3(p.walk_speed,p.run_speed,p.boost_speed)==pace,"All 15 cuts leave the controller transform, velocity and movement speeds unchanged")
	world.queue_free()
	await process_frame
	print("NAMED MOTION RIG: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
