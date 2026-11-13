extends SceneTree
## Exercise the actual arm chains, shared hilt and body presentation over whole
## reference moves. No strikes or visual pose may move the physics body.
const Player = preload("res://scripts/player.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
const CUTS := ["knife","edge","rapier","cleaver","greatblade","maul","longcurve","lance","crescent","glaive","reaper","paired","knuckles","filament","conduit"]
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
class CameraRig extends Node3D:
	var yaw := 0.0
var scene: Node3D
var p: CharacterBody3D
var w: Node
var controls: Intent
var camera_rig: CameraRig
var camera: Camera3D
var hz := 60
var only_cut := ""
var checks := 0
var failures := 0
var metrics: Dictionary = {}
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
		if arg.begins_with("--only="): only_cut=arg.trim_prefix("--only=")
	Engine.physics_ticks_per_second = hz
	call_deferred("run")
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func equip(entry: Dictionary) -> Resource:
	var item: Resource = Catalog.create(StringName(entry.id))
	if not p.inventory.add_item(item): return null
	if not p.inventory.assign(&"right",item.instance_id): return null
	p.combat.selected_slot = &"right"
	p.combat.sheathed = false
	w.sync_rig()
	return item
func arm_metrics(result: Dictionary, shared: bool) -> void:
	for id: String in ["LeftArm","RightArm"]:
		var upper: Node3D = p.visual.joints[id]
		var lower: Node3D = upper.get_node("Hinge")
		var grip: Node3D = w.rig.left_hand if id=="LeftArm" else w.rig.right_hand
		result.finite = result.finite and upper.global_transform.is_finite() and lower.global_transform.is_finite() and grip.global_transform.is_finite()
		result.length_error = maxf(result.length_error,maxf(absf(upper.global_position.distance_to(lower.global_position)-.30),absf(lower.global_position.distance_to(grip.global_position)-.29)))
		var local: Vector3 = p.visual.chest.to_local(grip.global_position)
		result.min_wrist_z = minf(result.min_wrist_z,local.z)
		var elbow: Vector3 = p.visual.chest.to_local(lower.global_position)
		result.min_elbow_z = minf(result.min_elbow_z,elbow.z)
		result.max_wrist_speed = maxf(result.max_wrist_speed,grip.global_position.distance_to(result.previous[id])*hz) if result.previous.has(id) else result.max_wrist_speed
		result.previous[id] = grip.global_position
	if shared:
		var support: Vector3 = w.rig.right_hand.to_global(Vector3(0,-.17,0))
		result.hilt_error = maxf(result.hilt_error,support.distance_to(w.rig.left_hand.global_position))
func timeline(move: Dictionary,heading: float,aerial: bool) -> Dictionary:
	w.cancel()
	w.body.release(true)
	p.visual.clear_combat_pose()
	p.visual.rotation.y = heading
	w._facing = Vector3.BACK.rotated(Vector3.UP,heading)
	w._pose_weight = 1.0
	w._katana_gripping = false
	w.active_move = move
	w.body.begin(w._facing)
	var original_transform := p.global_transform
	var original_velocity := p.velocity
	var original_move := move.duplicate(true)
	var result := {"finite":true,"length_error":0.0,"hilt_error":0.0,"min_wrist_z":9.0,"min_elbow_z":9.0,"max_wrist_speed":0.0,"target_z":9.0,"previous":{},"physics":true,"heading":true,"samples":0,"timing":true,"release_wrist_step":0.0,"release_elbow_step":0.0,"release_local_wrist_step":0.0,"release_local_elbow_step":0.0,"release_min_z":9.0,"worst_release":{},"worst_elbow":{},"air_return_error":0.0}
	var steps := maxi(2,ceili(float(move.duration)*hz))
	for tick in range(steps+1):
		w.elapsed = minf(float(move.duration),tick/float(hz))
		p.visual.animate(1.0/hz,p.velocity,not aerial)
		w.apply_pose(1.0/hz)
		var pose := Motion.sample(move,w.elapsed)
		result.target_z = minf(result.target_z,minf(pose.left.z,pose.right.z))
		arm_metrics(result,move.get("grip_mode")=="support" or w.loadout(&"right").id==&"katana")
		result.physics = result.physics and p.global_transform==original_transform and p.velocity==original_velocity
		result.heading = result.heading and p.visual.global_basis.z.dot(w._facing)>.999
		result.samples += 1
	var previous_elbows := {"LeftArm":p.visual.joints.LeftArm.get_node("Hinge").global_position,"RightArm":p.visual.joints.RightArm.get_node("Hinge").global_position}
	var previous_local_elbows := {"LeftArm":p.visual.chest.to_local(previous_elbows.LeftArm),"RightArm":p.visual.chest.to_local(previous_elbows.RightArm)}
	var previous_local_wrists := {"LeftArm":p.visual.chest.to_local(w.rig.left_hand.global_position),"RightArm":p.visual.chest.to_local(w.rig.right_hand.global_position)}
	var release_trace: Array = []
	w.cancel()
	for tick in range(ceili(.55*hz)):
		p.visual.animate(1.0/hz,p.velocity,not aerial)
		var base_wrists := {"LeftArm":w.rig.left_hand.global_position,"RightArm":w.rig.right_hand.global_position}
		w.apply_pose(1.0/hz)
		for id: String in ["LeftArm","RightArm"]:
			var grip: Node3D = w.rig.left_hand if id=="LeftArm" else w.rig.right_hand
			var elbow: Vector3 = p.visual.joints[id].get_node("Hinge").global_position
			var step: float = grip.global_position.distance_to(result.previous[id])
			if step>float(result.release_wrist_step):
				result.worst_release = {"tick":tick,"time":tick/float(hz),"arm":id,"move":move.name,"clip":move.get("clip_id","authored"),"aerial":aerial,"remaining":w._arm_release_remaining,"pose_weight":w._pose_weight,"pole_weight":w._natural_pole_weight,"chest_angles":str(p.visual.chest.global_basis.get_euler()),"from":str(result.previous[id]),"to":str(grip.global_position)}
			result.release_wrist_step = maxf(result.release_wrist_step,step)
			var elbow_step: float = elbow.distance_to(previous_elbows[id])
			if elbow_step>float(result.release_elbow_step): result.worst_elbow={"tick":tick,"time":tick/float(hz),"arm":id,"move":move.name,"clip":move.get("clip_id","authored"),"aerial":aerial,"remaining":w._arm_release_remaining,"pose_weight":w._pose_weight,"pole_weight":w._natural_pole_weight,"from":str(previous_elbows[id]),"to":str(elbow),"shoulder":str(p.visual.joints[id].global_position),"wrist":str(grip.global_position),"reach_distance":grip.global_position.distance_to(p.visual.joints[id].global_position),"bend":str(w._arm_bends.get(id,Vector3.ZERO)),"reach":str(w._arm_reaches.get(id,Vector3.ZERO))}
			result.release_elbow_step = maxf(result.release_elbow_step,elbow_step)
			var local_wrist: Vector3 = p.visual.chest.to_local(grip.global_position)
			var local_elbow: Vector3 = p.visual.chest.to_local(elbow)
			result.release_local_wrist_step = maxf(result.release_local_wrist_step,local_wrist.distance_to(previous_local_wrists[id]))
			result.release_local_elbow_step = maxf(result.release_local_elbow_step,local_elbow.distance_to(previous_local_elbows[id]))
			result.release_min_z = minf(result.release_min_z,p.visual.chest.to_local(grip.global_position).z)
			result.previous[id] = grip.global_position
			previous_elbows[id] = elbow
			previous_local_wrists[id] = local_wrist
			previous_local_elbows[id] = local_elbow
			result.finite = result.finite and grip.global_transform.is_finite()
			if aerial and tick/float(hz)>.5 and w.loadout(&"right").id!=&"katana": result.air_return_error=maxf(result.air_return_error,grip.global_position.distance_to(base_wrists[id]))
		if move.get("clip_id")=="c4714e067b683" and not aerial and tick<12:
			release_trace.append({"tick":tick,"shoulder":str(p.visual.joints.RightArm.global_position),"elbow":str(p.visual.joints.RightArm.get_node("Hinge").global_position),"wrist":str(w.rig.right_hand.global_position),"chest":str(p.visual.chest.global_basis.get_euler()),"bend":str(w._arm_bends.get("RightArm",Vector3.ZERO)),"reach":str(w._arm_reaches.get("RightArm",Vector3.ZERO))})
	if not release_trace.is_empty(): FileAccess.open("res://captures/greatblade_release_trace.json",FileAccess.WRITE).store_string(JSON.stringify(release_trace,"\t"))
	result.timing = move==original_move
	return result
func prime_release(entry: Dictionary) -> void:
	w.cancel()
	w.body.release(true)
	p.combat.blocking = false
	controls._keyboard_block = false
	w._begin(Library.move(StringName(entry.id),&"attack_right",0,false))
	for tick in range(ceili(hz*.12)):
		w.elapsed = float(w.active_move.hits[0])
		p.visual.animate(1.0/hz,Vector3.ZERO,true)
		w.apply_pose(1.0/hz)
	w.cancel()
	p.visual.animate(1.0/hz,Vector3.ZERO,true)
	w.apply_pose(1.0/hz)
func interrupt_release(entry: Dictionary) -> void:
	p.position = Vector3(0,.02,0)
	p.velocity = Vector3.DOWN
	p.move_and_slide()
	p.velocity = Vector3.ZERO
	p.apply_floor_snap()
	var item: Resource = equip(entry)
	prime_release(entry)
	check(w._arm_release_remaining>0 and w.can_act(),"A completed named strike enters a visual release while combat remains immediately available")
	w._on_action(&"attack_right",&"right")
	check(not w.active_move.is_empty() and w.elapsed==0 and String(w.active_move.item_id)==String(entry.id),"A fresh attack starts on the same press during visual release, with no added recovery lock")
	p.visual.animate(1.0/hz,Vector3.ZERO,true)
	w.apply_pose(1.0/hz)
	check(w._queued.is_empty() and w.elapsed==0 and not w.active_move.is_empty(),"An immediate replacement attack has no extra queued delay from the visual release")
	prime_release(entry)
	controls._keyboard_block = true
	p.combat.poll(controls)
	p.visual.animate(1.0/hz,Vector3.ZERO,true)
	w.apply_pose(1.0/hz)
	check(p.combat.blocking and w.active_move.is_empty() and w.parry_remaining>0 and is_zero_approx(w._arm_release_remaining),"Guard and its existing timed-parry window take over immediately during arm release")
	controls._keyboard_block = false
	p.combat.poll(controls)
	p.visual.animate(1.0/hz,Vector3.ZERO,true)
	w.apply_pose(1.0/hz)
	check(is_zero_approx(w._arm_release_remaining),"Releasing guard cannot resurrect an older named-attack arm return")
	prime_release(entry)
	var dodged: bool = p.dodge.start(Vector3.RIGHT)
	check(dodged and p.dodge.active and w.active_move.is_empty() and is_zero_approx(w._arm_release_remaining),"A dodge starts immediately during visual release and discards that cached arm return")
	p.dodge.cancel()
	p.visual.animate(1.0/hz,Vector3.ZERO,true)
	w.apply_pose(1.0/hz)
	check(is_zero_approx(w._arm_release_remaining) and w.can_act(),"Finishing a dodge leaves no stale release pose or added combat delay")
	prime_release(entry)
	p.combat.sheathed = true
	w.sync_rig()
	check(is_zero_approx(w._arm_release_remaining),"Sheathing cancels the visible arm-return cache immediately")
	p.combat.sheathed = false
	w.sync_rig()
	w.cancel()
	p.inventory.take_item(item.instance_id,1)
func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	controls = Intent.new()
	scene.add_child(controls)
	camera_rig = CameraRig.new()
	scene.add_child(camera_rig)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30,.2,30)
	shape.shape = box
	floor.add_child(shape)
	scene.add_child(floor)
	floor.position.y = -.1
	p = Player.new()
	p.controls = controls
	p.camera_rig = camera_rig
	p.live_motion_retrieval = false
	p.spawn = Vector3.ZERO
	scene.add_child(p)
	w = p.weapon_combat
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(12)
	p.set_physics_process(false)
	w.set_physics_process(false)
	var movement_tuning := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	var collider: Shape3D = p.get_child(0).shape
	var representatives: Dictionary = {}
	for entry: Dictionary in Database.all():
		if entry.has("motion_set") and not representatives.has(entry.motion_set.cut): representatives[entry.motion_set.cut]=entry
	check(representatives.size()==15,"All fifteen reference handling cuts have real owned-equipment representatives")
	if "--capture-only" in OS.get_cmdline_user_args():
		await captures(representatives)
		scene.queue_free()
		await process_frame
		print("Natural weapon arms close captures completed")
		quit()
		return
	for cut: String in CUTS:
		if not only_cut.is_empty() and cut!=only_cut: continue
		var entry: Dictionary = representatives[cut]
		var item: Resource = equip(entry)
		check(item!=null,cut+" equips its actual named weapon on the character's arm rig")
		var result := {"finite":true,"length_error":0.0,"hilt_error":0.0,"min_wrist_z":9.0,"min_elbow_z":9.0,"target_z":9.0,"max_wrist_speed":0.0,"physics":true,"heading":true,"samples":0,"timing":true,"release_wrist_step":0.0,"release_elbow_step":0.0,"release_local_wrist_step":0.0,"release_local_elbow_step":0.0,"release_min_z":9.0,"worst_release":{},"worst_elbow":{},"air_return_error":0.0}
		for aerial: bool in [false,true]:
			p.position = Vector3(0,5 if aerial else .02,0)
			p.velocity = Vector3.DOWN
			p.move_and_slide()
			p.velocity = Vector3.ZERO
			if not aerial: p.apply_floor_snap()
			check(p.is_on_floor()!=aerial,cut+(" airborne" if aerial else " grounded")+" exercises the matching controller floor state")
			var moves: Array[Dictionary] = []
			for combo in range(3): moves.append(Library.move(StringName(entry.id),&"attack_right",combo,aerial))
			moves.append(Library.move(StringName(entry.id),&"special_x",0,aerial))
			moves.append(Library.move(StringName(entry.id),&"special_rt_y",0,aerial))
			moves.append(Library.charged_move(StringName(entry.id),&"special_x",1.0,0,aerial))
			for index in range(moves.size()):
				var sample := timeline(moves[index],float(index%3)*PI*.5,aerial)
				if float(sample.release_wrist_step)>float(result.release_wrist_step): result.worst_release=sample.worst_release
				if float(sample.release_elbow_step)>float(result.release_elbow_step): result.worst_elbow=sample.worst_elbow
				for key: String in ["finite","physics","heading","timing"]: result[key] = result[key] and sample[key]
				for key: String in ["length_error","hilt_error","max_wrist_speed","release_wrist_step","release_elbow_step","release_local_wrist_step","release_local_elbow_step","air_return_error"]: result[key]=maxf(result[key],sample[key])
				for key: String in ["min_wrist_z","min_elbow_z","target_z","release_min_z"]: result[key]=minf(result[key],sample[key])
				result.samples += sample.samples
		check(result.finite and result.length_error<.001,cut+" keeps finite shoulder/elbow/wrist poses and both anatomical limb lengths over complete combos and arts")
		check(result.target_z>=-.081,cut+" windup, contact and recovery hand targets stay out of the behind-back workspace")
		check(result.min_wrist_z>=-.17,cut+" actual wrists remain within one shared-grip span of the torso plane instead of folding behind the back")
		check(result.hilt_error<.007,cut+" maintains both physical wrists on the shared hilt when using a supported grip")
		check(result.physics and result.heading,cut+" poses preserve the physics transform, velocity and selected facing at three headings")
		check(result.timing,cut+" visual sampling leaves the move's hit windows, duration, damage and motion identity unchanged")
		check(result.release_min_z>=-.17,cut+" wrists remain in a natural workspace while returning to draw-ready after release")
		# Bound motion in the arm's anatomical workspace. World velocities also
		# include the preserved source torso turn; keep those as diagnostics.
		# A full 1.18 m wrist excursion in 0.16 s peaks near 11.1 m/s under a
		# smoothstep. The 16 m/s bound still rejects independent IK-plane snaps.
		check(result.release_local_wrist_step*hz<16 and result.release_local_elbow_step*hz<16,cut+" returns to ready continuously at bounded chest-relative wrist and elbow speeds")
		check(result.air_return_error<.002,cut+" fully returns arm endpoints to the existing airborne locomotion pose after the visual handoff")
		metrics[cut] = result
		print("ARM METRICS ",cut," ",JSON.stringify(result))
		w.cancel()
		p.inventory.take_item(item.instance_id,1)
	check(Vector3(p.walk_speed,p.run_speed,p.boost_speed)==movement_tuning and p.get_child(0).shape==collider and controls.gameplay_enabled,"Natural arm presentation preserves movement tuning, collision and unrestricted local controls")
	interrupt_release(representatives.greatblade)
	if "--capture" in OS.get_cmdline_user_args(): await captures(representatives)
	DirAccess.make_dir_recursive_absolute("res://captures")
	FileAccess.open("res://captures/natural_weapon_arm_metrics_"+str(hz)+".json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	scene.queue_free()
	await process_frame
	print("Natural weapon arms verification: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
func captures(representatives: Dictionary) -> void:
	p.position = Vector3(0,.02,0)
	p.velocity = Vector3.DOWN
	p.move_and_slide()
	p.velocity = Vector3.ZERO
	p.apply_floor_snap()
	if "--release-trace" in OS.get_cmdline_user_args():
		await capture_final_line(representatives.longcurve if "--longcurve-release" in OS.get_cmdline_user_args() else representatives.greatblade)
		return
	for cut: String in ["greatblade","reaper","longcurve"]:
		var entry: Dictionary = representatives[cut]
		var item: Resource = equip(entry)
		var move := Library.move(StringName(entry.id),&"attack_right",0,false)
		w.cancel()
		w.body.release(true)
		p.visual.rotation.y = 0
		w._facing = Vector3.BACK
		w.active_move = move
		w._pose_weight = 1
		w._katana_gripping = false
		w.body.begin(w._facing)
		camera.fov = 40
		camera.position = Vector3(1.9,1.65,2.5)
		camera.look_at(Vector3(0,1.05,0))
		var phases := {"windup":float(move.windup)*.60,"contact":float(move.hits[0]),"recovery":float(move.duration)*.83}
		var time := 0.0
		for phase: String in phases:
			while time<float(phases[phase]):
				time += 1.0/hz
				w.elapsed = time
				p.visual.animate(1.0/hz,Vector3.ZERO,true)
				w.apply_pose(1.0/hz)
			await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://captures")
			root.get_texture().get_image().save_png("res://captures/natural_arms_"+cut+"_"+phase+".png")
		# Finish the move before assessing its automatic draw-ready return.
		while time<float(move.duration):
			time += 1.0/hz
			w.elapsed = minf(time,float(move.duration))
			p.visual.animate(1.0/hz,Vector3.ZERO,true)
			w.apply_pose(1.0/hz)
		w.cancel()
		for tick in range(ceili(.55*hz)):
			p.visual.animate(1.0/hz,Vector3.ZERO,true)
			w.apply_pose(1.0/hz)
			if tick in [0,ceili(.16*hz),ceili(.55*hz)-1]:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://captures/natural_arms_"+cut+("_released_first" if tick==0 else "_settling" if tick==ceili(.16*hz) else "_ready")+".png")
		p.inventory.take_item(item.instance_id,1)
func capture_final_line(entry: Dictionary) -> void:
	var item: Resource = equip(entry)
	var longcurve: bool = entry.motion_set.cut=="longcurve"
	var heading := 0.0 if longcurve else PI*.5
	var prefix := "longcurve_return_" if longcurve else "final_line_release_"
	w.cancel()
	w.body.release(true)
	p.visual.rotation.y = heading
	w._facing = Vector3.BACK.rotated(Vector3.UP,heading)
	w.active_move = Library.move(StringName(entry.id),&"special_x" if longcurve else &"special_rt_y",0,false)
	w._pose_weight = 1
	w._katana_gripping = false
	w.body.begin(w._facing)
	camera.fov = 40
	camera.position = Vector3(1.9,1.65,2.5).rotated(Vector3.UP,heading)
	camera.look_at(Vector3(0,1.05,0))
	for tick in range(ceili(float(w.active_move.duration)*hz)+1):
		w.elapsed = minf(float(w.active_move.duration),tick/float(hz))
		p.visual.animate(1.0/hz,Vector3.ZERO,true)
		w.apply_pose(1.0/hz)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/"+prefix+"before.png")
	w.cancel()
	for tick in range(13 if longcurve else 7):
		p.visual.animate(1.0/hz,Vector3.ZERO,true)
		w.apply_pose(1.0/hz)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/"+prefix+str(tick)+".png")
	w.cancel()
	p.inventory.take_item(item.instance_id,1)
