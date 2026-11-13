extends SceneTree
## Audit real reference bends and the presented player torso, without strikes.
const Body = preload("res://scripts/combat_body.gd")
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
	var candidates := 0
	var backward := 0
	var corrected := true
	for file: String in DirAccess.get_files_at("res://data/equipment/motions"):
		if not file.ends_with(".json") or file=="manifest.json": continue
		var clips: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/motions/"+file))
		for clip: Dictionary in clips.values():
			var closest: Dictionary = clip.motion[0]
			for frame: Dictionary in clip.motion:
				if absf(float(frame.t)-float(clip.contact))<absf(float(closest.t)-float(clip.contact)): closest=frame
			var hip := Vector3(closest.hip[0],closest.hip[1],closest.hip[2])
			var chest := Vector3(closest.chest[0],closest.chest[1],closest.chest[2])
			if (Basis.from_euler(hip)*Basis.from_euler(chest)).y.z<-.02: backward += 1
			var pose := Body.forward_attack_pose(hip,chest,1)
			var up: Vector3 = (Basis.from_euler(pose.hip)*Basis.from_euler(pose.chest)).y
			corrected = corrected and up.z>.05 and up.y>0 and pose.hip.y==hip.y and pose.hip.z==hip.z
			candidates += 1
	check(candidates>500 and backward>300,"The audit reproduces the widespread backward bend in the source contact poses")
	check(corrected,"Every source contact leans forward while preserving authored hip yaw and bank")
	var rest_hip := Vector3(.20,.80,-.06)
	var rest_chest := Vector3(.10,-.30,.08)
	var released := Body.forward_attack_pose(rest_hip,rest_chest,0)
	check(released.hip.is_equal_approx(rest_hip) and Basis.from_euler(released.chest).is_equal_approx(Basis.from_euler(rest_chest)),"Zero attack weight preserves locomotion lean at entry and recovery")
	var almost_released := Body.forward_attack_pose(rest_hip,rest_chest,.001)
	check(Quaternion.from_euler(almost_released.hip).angle_to(Quaternion.from_euler(rest_hip))<.003 and Quaternion.from_euler(almost_released.chest).angle_to(Quaternion.from_euler(rest_chest))<.003,"Forward support blends continuously with the existing attack envelope")
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
	var position := p.global_transform
	var pace := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	var capsule: Shape3D = p.get_child(0).shape
	var ids: Array[StringName] = [&"fractured_moon",&"event_horizon",&"last_argument"]
	for family: String in ["dagger","greatsword","hammer","scythe"]:
		for entry: Dictionary in Database.all():
			if entry.family==family: ids.append(StringName(entry.id)); break
	for id: StringName in ids:
		var item: Resource = Catalog.create(id)
		p.inventory.add_item(item)
		world.loot.request_equip(p.inventory,&"right",item.instance_id)
		p.combat.selected_slot = &"right"
		p.combat.sheathed = false
		w.sync_rig()
		var supported := true
		var metrics := []
		for heading: float in [0,PI*.5,PI]:
			for speed: float in [0,3.5,-3.5]:
				w.cancel()
				p.visual.rotation.y = heading
				w._facing = Vector3.BACK.rotated(Vector3.UP,heading)
				p.velocity = Vector3(0,0,speed).rotated(Vector3.UP,heading)
				w.active_move = w.move_for(&"right",&"attack_right")
				w.body.begin(w._facing)
				for frame in range(ceili(hz*.45)):
					p.visual.animate(1.0/hz,p.velocity,true)
					w.elapsed = float(w.active_move.hits[0])
					w.apply_pose(1.0/hz)
				var up: Vector3 = p.visual.global_basis.inverse()*p.visual.chest.global_basis.y
				supported = supported and up.z>.025 and up.y>0
				metrics.append(snappedf(up.z,.001))
		check(supported,String(id)+" presents a forward torso at impact when still, advancing, backpedaling and facing different headings: "+str(metrics))
		w.cancel()
		p.visual.clear_combat_pose()
		p.inventory.take_item(item.instance_id,1)
	p.velocity = Vector3.ZERO
	check(p.global_transform==position and Vector3(p.walk_speed,p.run_speed,p.boost_speed)==pace and p.get_child(0).shape==capsule,"The visual lean correction preserves the controller, movement tuning and collision capsule")
	world.queue_free()
	await process_frame
	print("FORWARD WEAPON LEAN: ",checks," checks, ",failures," failures at ",hz," Hz; ",candidates," reference contacts")
	quit(1 if failures else 0)
