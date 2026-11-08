extends SceneTree
## Measure actual wrist/ankle endpoints while the real player animates.
const Library = preload("res://scripts/weapon_library.gd")
class Intent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	var guard := false
	func sample() -> void: pass
	func is_blocking() -> bool: return guard
	func consume_jump() -> bool:
		var value := jump
		jump = false
		return value
var failures := 0
var checks := 0
var hz := 60
var world: Node3D
var p: CharacterBody3D
var w: Node
var intent: Intent
var camera: Camera3D

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: print("PASS: ",message)
	else:
		push_error("FAIL: "+message)
		failures += 1

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func equip(slot: StringName) -> void:
	world.controls._request(&"weapon",slot)
	p.combat.poll(world.controls)

func cast(action: StringName) -> void:
	world.controls._request(&"action",action)
	p.combat.poll(world.controls)

func ankle(id: String) -> Vector3:
	return p.visual.joints[id].get_node("Hinge").to_global(Vector3(0,-0.45,0))

func grip_error() -> float:
	return w.rig.left_hand.global_position.distance_to(w.rig.right_hand.to_global(Vector3(0,-0.17,0)))

func reset(slot: StringName = &"down", at: Vector3 = Vector3.ZERO) -> void:
	p.respawn()
	p.controls = intent
	intent.move = Vector2.ZERO
	intent.sprint = false
	intent.boost = false
	intent.guard = false
	p.position = at
	p.camera_rig.yaw = 0
	p.visual.rotation.y = PI
	equip(slot)
	await frames(hz)

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if camera == null:
		camera = Camera3D.new()
		camera.fov = 48
		root.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute("res://captures")
	camera.global_position = p.position+Vector3(2.7,1.8,-3.7)
	camera.look_at(p.position+Vector3.UP*0.95)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/combat_motion_"+label+".png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	w = p.weapon_combat
	p.visual.retrieval.enabled = false
	intent = Intent.new()
	root.add_child(intent)
	p.controls = intent
	await reset(&"right")
	check(grip_error()<0.008,"Both katana wrists contact the same hilt at rest")
	var blade_local: Vector3 = p.visual.global_basis.inverse()*w.rig.right_hand.global_basis.y
	check(blade_local.z<-0.90 and blade_local.y<-0.10,"Waki-gamae points the resting katana backward and slightly down")
	var hand_local: Vector3 = p.visual.to_local(w.rig.right_hand.global_position)
	check(hand_local.x>0.12 and hand_local.y>0.95 and hand_local.y<1.16 and absf(hand_local.z)<0.18,"Waki-gamae holds both hands beside the right hip")
	check(w.rig.right_hand.to_global(Vector3(0,1.15,0)).y>0.12,"Low katana guard keeps its tip above the floor")
	var rest_pelvis: Vector3 = p.visual.pelvis.position
	check(rest_pelvis.y>0.93,"Drawn katana preserves relaxed idle legs")
	await shot("katana_ready")
	for slot: StringName in [&"down",&"right",&"up"]:
		equip(slot)
		world.controls._request(&"sheathe",&"")
		p.combat.poll(world.controls)
		await frames(hz/3)
		var downward := true
		for blade: Node3D in w.rig.models[slot].stowed_blades:
			downward = downward and blade.global_basis.y.y<-0.15 and blade.to_global(Vector3(0,1.15 if slot!=&"up" else 0.66,0)).y>0.1
		check(downward,"Sheathed sword tips angle downward and clear the floor: "+String(slot))
		if slot==&"right":
			var mount: Node3D = w.rig.models[slot].stowed
			var stowed_blade: Node3D = w.rig.models[slot].stowed_blades[0]
			var tip: Vector3 = p.visual.to_local(stowed_blade.to_global(Vector3(0,1.15,0)))
			check(mount.get_parent()==p.visual.pelvis and p.visual.to_local(mount.global_position).x<-0.20 and tip.z<-0.7,"Katana saya sits on the left hip with the tip trailing behind")
	for slot: StringName in Library.LOADOUTS:
		for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			await reset(slot)
			var spec := Library.move(slot,action)
			var title: String = spec.name
			cast(action)
			var peak_hips := 0.0
			var peak_compression := 0.0
			var peak_grip := 0.0
			var peak_contact_error := 0.0
			var peak_plant_drift := 0.0
			var lead := 0.0
			var stable_samples := 0
			var finite := true
			var previous: Dictionary = {}
			var captured: Dictionary = {}
			var capture_move := (slot==&"right" or action==&"special_y" or (slot==&"left" and action==&"attack_right"))
			for i in range(ceili(float(spec.duration)*hz)+2):
				await frames(1)
				peak_hips = maxf(peak_hips,absf(wrapf(w.body.hips.value.y,-PI,PI)))
				lead = maxf(lead,w.body.hip_drive-w.body.shoulder_drive)
				if p.visual._combat_positions.has(p.visual.pelvis):
					peak_compression = maxf(peak_compression,p.visual._combat_positions[p.visual.pelvis].y-p.visual.pelvis.position.y)
				if slot == &"right": peak_grip = maxf(peak_grip,grip_error())
				for id: String in p.visual.joints:
					var joint: Node3D = p.visual.joints[id]
					finite = finite and joint.global_transform.is_finite() and joint.get_node("Hinge").global_transform.is_finite()
				for id: String in w.body.support_feet:
					var contact: Dictionary = w.body.support_feet[id]
					if contact.planted and w.body.plant_weight>0.995:
						var actual := ankle(id)
						peak_contact_error = maxf(peak_contact_error,actual.distance_to(contact.point))
						if previous.has(id) and previous[id].point.distance_to(contact.point)<0.0001:
							peak_plant_drift = maxf(peak_plant_drift,actual.distance_to(previous[id].actual))
							stable_samples += 1
						previous[id] = {"point":contact.point,"actual":actual}
					else: previous.erase(id)
				if capture_move and not w.active_move.is_empty():
					var stage: String = w.body.phase_label
					if not captured.has(stage):
						captured[stage] = true
						await shot(String(slot)+"_"+String(action)+"_"+stage)
			check(finite and peak_compression>0.035 and peak_hips>0.13,"Whole-body loading and hip rotation: "+title)
			check(lead>0.12,"Hip drive leads the shoulder release: "+title)
			check(stable_samples>0 and peak_contact_error<0.03 and peak_plant_drift<0.018,"Support foot stays planted on real floor: "+title+" (error %.3f, drift %.3f)" % [peak_contact_error,peak_plant_drift])
			if slot==&"right": check(peak_grip<0.012,"Both hands stay on the katana through its entire move: "+title+" (%.4f m)" % peak_grip)
			check(p.position.distance_to(Vector3.ZERO)<0.04 and p.velocity.length()<0.01,"Combat choreography leaves the physical root still: "+title)
			await frames(hz)
			check(absf(p.visual.pelvis.position.y-rest_pelvis.y)<0.015 and absf(wrapf(w.body.hips.value.y,-PI,PI))<0.01,"Recovery returns to the relaxed stance without unwinding: "+title)
	# Hands remain coupled when the gait, torso lean and airborne leg pose change.
	for pace in [0.4,1.0]:
		await reset(&"right")
		intent.move = Vector2(0,-pace)
		intent.sprint = pace>0.7
		intent.boost = pace>0.7
		var max_error := 0.0
		var min_tip := INF
		var max_turn := 0.0
		var previous_blade: Quaternion = w.rig.right_hand.global_basis.get_rotation_quaternion()
		for i in range(hz):
			await frames(1)
			max_error = maxf(max_error,grip_error())
			min_tip = minf(min_tip,w.rig.right_hand.to_global(Vector3(0,1.15,0)).y)
			var blade: Quaternion = w.rig.right_hand.global_basis.get_rotation_quaternion()
			max_turn = maxf(max_turn,previous_blade.angle_to(blade))
			previous_blade = blade
		check(max_error<0.012 and min_tip>0.015 and max_turn<20.0/hz,"Fluid two-handed carry clears the floor at input "+str(pace)+" (tip %.3f m, turn %.3f rad)" % [min_tip,max_turn])
		await shot("katana_pace_"+str(pace))
	await reset(&"right")
	cast(&"special_rt_x")
	await frames(maxi(1,hz/8))
	intent.jump = true
	await frames(2)
	check(not p.is_on_floor() and w.body.plant_weight==0 and w.body.support_feet.is_empty(),"Jump immediately releases combat foot planting")
	check(grip_error()<0.012,"Katana remains two-handed during a jumping special")
	intent.jump = true
	await frames(2)
	check(p.air_step_count==1 and p.velocity.y>10,"Sky step stays responsive during full-body combat")
	await reset(&"up")
	cast(&"special_x")
	await frames(hz/4)
	intent.move = Vector2.RIGHT
	intent.sprint = true
	await frames(hz/3)
	check(p.velocity.x>2.5 and w.body.plant_weight<0.01,"Movement takes over the feet without an animation lock")
	await reset(&"right")
	cast(&"special_y")
	await frames(hz/4)
	check(p.dodge.start(Vector3.RIGHT) and w.body.plant_weight==0 and w.body.hips.value==Vector3.ZERO,"Dodge cancels the whole-body pose and all anchors")
	p.dodge.cancel()
	# A high platform edge supplies no imaginary floor to the unsupported foot.
	var platform := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1,0.3,1)
	shape.shape = box
	platform.add_child(shape)
	world.add_child(platform)
	platform.position = Vector3(0,4,0)
	await reset(&"down",Vector3(-0.42,4.17,0))
	cast(&"special_y")
	await frames(hz/2)
	var supported := true
	for contact: Dictionary in w.body.support_feet.values():
		supported = supported and contact.point.y>4.1 and absf(contact.point.x)<0.51
	check(p.is_on_floor() and w.body.support_feet.size()<2 and supported,"Combat foot planting rejects unsupported space at a roof edge")
	platform.queue_free()
	await reset(&"right")
	check(grip_error()<0.012 and w.body.support_feet.is_empty(),"Respawn discards old combat foot anchors")
	await reset(&"up")
	intent.move = Vector2.RIGHT
	await frames(hz/3)
	equip(&"right")
	var draw_error := 0.0
	for i in range(hz/4):
		await frames(1)
		draw_error = maxf(draw_error,grip_error())
	check(draw_error<0.012,"A moving quick-swap couples both katana hands immediately")
	await reset(&"right")
	intent.guard = true
	await frames(hz/2)
	p.camera_rig.yaw = PI*0.75
	await frames(hz/2)
	var left_local: Vector3 = p.visual.to_local(ankle("LeftLeg"))
	var right_local: Vector3 = p.visual.to_local(ankle("RightLeg"))
	check(left_local.x<0 and right_local.x>0 and w.body._stance_basis.z.dot(w.aim_direction())>0.95,"Turning a held guard replants the stance without crossing the legs")
	world.queue_free()
	intent.queue_free()
	if camera!=null: camera.queue_free()
	await process_frame
	print("Combat motion verification: ",checks," checks at ",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
