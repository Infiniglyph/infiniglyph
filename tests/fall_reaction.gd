extends SceneTree
## Exercise reversible landing overlays against the real skeleton and weapons.
const Reaction = preload("res://scripts/fall_reaction.gd")
const Library = preload("res://scripts/weapon_library.gd")
var world: Node3D
var actor: CharacterBody3D
var reaction: RefCounted
var checks := 0
var failures := 0
var hz := 60
var camera: Camera3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func baseline() -> void:
	actor.visual.clear_combat_pose()
	actor.visual.animate(1.0/hz,actor.velocity,true)
	actor.weapon_combat.apply_pose(1.0/hz)

func limb_end(id: String, length: float) -> Vector3:
	return actor.visual.joints[id].get_node("Hinge").to_global(Vector3(0,-length,0))

func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if camera == null:
		camera = Camera3D.new()
		camera.fov = 44
		root.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute("res://captures")
	camera.position = actor.global_position+actor.visual.global_basis*Vector3(2.5,1.2,2.2)
	camera.look_at(actor.global_position+Vector3.UP*0.75)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/fall_reaction_"+label+".png")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	await frames(30)
	actor.position = Vector3(0,0.1,6)
	actor.velocity = Vector3.ZERO
	await frames(30)
	actor.set_physics_process(false)
	actor.weapon_combat.set_physics_process(false)
	actor.combat.sheathed = true
	actor.weapon_combat.rig.equip(&"down",true)
	reaction = Reaction.new()
	reaction.actor = actor
	var root_transform := actor.transform
	var structural: Dictionary = {}
	for id in ["LeftArm","RightArm","LeftLeg","RightLeg"]:
		structural[id] = [actor.visual.joints[id].position,actor.visual.joints[id].get_node("Hinge").position]
	var minima: Dictionary = {}
	for fall_kind: StringName in [&"minor",&"heavy",&"severe",&"critical"]:
		for moving in [false,true]:
			actor.velocity = Vector3(0,0,7.5 if moving else 0)
			baseline()
			reaction.begin(fall_kind,20 if fall_kind==&"minor" else (35 if fall_kind==&"heavy" else 55))
			var starting_duration: float = reaction.duration
			var min_hip := 10.0
			var min_foot := 10.0
			var min_head := 10.0
			var rigid := true
			var finite := true
			var steps := 0
			var saved := false
			var recovery_saved := false
			while reaction.active() and steps<hz*3:
				baseline()
				reaction.advance(1.0/hz)
				reaction.apply(1.0/hz)
				steps += 1
				min_hip = minf(min_hip,actor.visual.pelvis.position.y)
				var head: Vector3 = actor.visual.chest.to_global(Vector3(0,0.78,0))
				min_head = minf(min_head,head.y-actor.global_position.y-0.135)
				for id: String in structural:
					var joint: Node3D = actor.visual.joints[id]
					rigid = rigid and joint.position.is_equal_approx(structural[id][0]) and joint.get_node("Hinge").position.is_equal_approx(structural[id][1])
					finite = finite and joint.transform.is_finite() and joint.scale.is_equal_approx(Vector3.ONE)
				for id in ["LeftLeg","RightLeg"]:
					min_foot = minf(min_foot,limb_end(id,0.45).y-actor.global_position.y)
				if not saved and reaction.remaining<starting_duration*0.68 and reaction.active():
					await shot(String(fall_kind)+("_moving" if moving else "_standing"))
					saved = true
				if not recovery_saved and reaction.remaining<starting_duration*0.25 and reaction.active() and fall_kind==&"severe":
					await shot("severe_recovery"+("_moving" if moving else "_standing"))
					recovery_saved = true
			var title := String(fall_kind)+(" moving" if moving else " stationary")
			check(not reaction.active() and absf(float(steps)/hz-starting_duration)<=1.1/hz,title+" recovers on its deterministic timer")
			check(rigid and finite,title+" preserves rigid limb offsets and finite unit-scale transforms")
			check(min_foot>-0.012 and min_head>0.12,title+" keeps feet and head above the landing surface")
			check(actor.transform==root_transform and actor.velocity==Vector3(0,0,7.5 if moving else 0),title+" never alters collision root or momentum")
			minima[title] = min_hip
	check(minima["heavy stationary"]<minima["minor stationary"]-0.04 and minima["severe stationary"]<minima["heavy stationary"]-0.04,"Height tiers produce distinct crouch, heavy brace and low knockdown")
	# Lower tiers preserve ongoing attack articulation and their local arm pose.
	actor.velocity = Vector3.ZERO
	for fall_kind: StringName in [&"minor",&"heavy"]:
		actor.combat.sheathed = false
		actor.weapon_combat.active_move = Library.move(&"down",&"special_x")
		actor.weapon_combat.elapsed = 0.29
		baseline()
		var move_before: Dictionary = actor.weapon_combat.active_move.duplicate(true)
		var arm_before: Quaternion = actor.visual.joints.RightArm.quaternion
		var chest_before: Quaternion = actor.visual.chest.quaternion
		reaction.begin(fall_kind,30)
		reaction.advance(0.18)
		reaction.apply(1.0/hz)
		check(actor.weapon_combat.active_move==move_before and actor.visual.joints.RightArm.quaternion.is_equal_approx(arm_before) and actor.visual.chest.quaternion.is_equal_approx(chest_before),String(fall_kind)+" retains the active attack and authored upper-body pose")
		reaction.cancel()
	actor.weapon_combat.cancel()
	actor.combat.selected_slot = &"right"
	actor.combat.sheathed = false
	actor.weapon_combat.rig.equip(&"right",false)
	for i in range(hz): baseline()
	reaction.begin(&"severe",55)
	reaction.advance(0.30)
	reaction.apply(1.0/hz)
	var rig = actor.weapon_combat.rig
	check(rig.left_hand.global_position.distance_to(rig.right_hand.to_global(Vector3(0,-0.17,0)))<0.01,"Landing weight transfer keeps both katana hands on the same hilt")
	actor.visual.clear_combat_pose()
	var clean_position: Vector3 = actor.visual.pelvis.position
	var clean_rotation: Quaternion = actor.visual.pelvis.quaternion
	reaction.cancel()
	check(actor.visual.pelvis.position.is_equal_approx(clean_position) and actor.visual.pelvis.quaternion.is_equal_approx(clean_rotation),"Late cancel does not restore stale landing transforms over a freshly cleared pose")
	baseline()
	var rest: Vector3 = actor.visual.pelvis.position
	reaction.begin(&"heavy",35)
	reaction.advance(0.2)
	reaction.apply(1.0/hz)
	reaction.cancel()
	check(actor.visual.pelvis.position.is_equal_approx(rest),"Immediate cancel removes its own landing overlay")
	reaction.begin(&"not_a_landing",100)
	check(not reaction.active(),"Unknown landing kind leaves the visual reaction inactive")
	for state: StringName in [&"parried",&"exhausted"]:
		actor.weapon_combat.enter_forced(state,1.0,actor.global_position+Vector3.FORWARD)
		reaction.begin(&"heavy",35)
		reaction.advance(0.2)
		reaction.apply(1.0/hz)
		check(not reaction.active(),"Landing overlay yields to the higher-priority "+String(state)+" reaction")
		actor.weapon_combat.clear_stagger()
	world.queue_free()
	await process_frame
	print("Fall reaction verification: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
