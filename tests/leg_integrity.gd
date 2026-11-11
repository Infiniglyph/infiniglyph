extends SceneTree
## Check rendered rods against their hinges, including interrupted visual poses.
const Library = preload("res://scripts/weapon_library.gd")
class Intent extends Node:
	var move := Vector2.ZERO
	var look := Vector2.ZERO
	var mouse_look := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	var dodge := false
	var guard := false
	func sample() -> void: pass
	func consume_jump() -> bool:
		var value := jump
		jump = false
		return value
	func consume_dodge() -> bool:
		var value := dodge
		dodge = false
		return value
	func is_blocking() -> bool: return guard
	func update_combat_hold(_delta: float) -> void: pass
	func consume_combat_requests() -> Array[Dictionary]: return []
	func consume_lock_requests() -> Array[Vector2]: return []
	func reset_combat_input() -> void: pass

var world: Node3D
var actor: CharacterBody3D
var input: Intent
var checks := 0
var failures := 0
var hz := 60
var samples := 0
var separation := 0.0
var length_error := 0.0
var basis_error := 0.0
var local_hinge_error := 0.0
var hip_anchor_error := 0.0
var bad_transform := false
var reported := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func rod_at(joint: Node3D) -> MeshInstance3D:
	for child: Node in joint.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh: return child
	return null

func inspect_pose(label: String) -> void:
	var visual: Node3D = actor.visual
	for id: String in ["LeftLeg","RightLeg"]:
		var hip: Node3D = visual.joints[id]
		var knee: Node3D = hip.get_node("Hinge")
		var thigh := rod_at(hip)
		var shin := rod_at(knee)
		var thigh_length: float = thigh.mesh.height
		var shin_length: float = shin.mesh.height
		var thigh_top: Vector3 = visual.to_local(thigh.to_global(Vector3.UP*thigh_length*0.5))
		var thigh_bottom: Vector3 = visual.to_local(thigh.to_global(Vector3.DOWN*thigh_length*0.5))
		var knee_position := visual.to_local(knee.global_position)
		var shin_top: Vector3 = visual.to_local(shin.to_global(Vector3.UP*shin_length*0.5))
		var shin_bottom: Vector3 = visual.to_local(shin.to_global(Vector3.DOWN*shin_length*0.5))
		var gap := maxf(thigh_bottom.distance_to(knee_position),shin_top.distance_to(knee_position))
		separation = maxf(separation,gap)
		length_error = maxf(length_error,maxf(absf(thigh_top.distance_to(thigh_bottom)-thigh_length),absf(shin_top.distance_to(shin_bottom)-shin_length)))
		local_hinge_error = maxf(local_hinge_error,knee.position.distance_to(Vector3(0,-thigh_length,0)))
		hip_anchor_error = maxf(hip_anchor_error,hip.position.distance_to(Vector3(-0.125 if id == "LeftLeg" else 0.125,0,0)))
		for joint: Node3D in [hip,knee]:
			bad_transform = bad_transform or not joint.transform.is_finite() or not joint.global_transform.is_finite()
			var basis: Basis = joint.basis
			basis_error = maxf(basis_error,maxf(absf(basis.x.length()-1),maxf(absf(basis.y.length()-1),absf(basis.z.length()-1))))
			basis_error = maxf(basis_error,maxf(absf(basis.x.dot(basis.y)),maxf(absf(basis.x.dot(basis.z)),absf(basis.y.dot(basis.z)))))
		if not reported and (gap>0.001 or length_error>0.001 or local_hinge_error>0.001 or basis_error>0.001 or bad_transform):
			reported = true
			print("Limb integrity failure during ",label," ",id," gap ",gap," hinge ",knee.position," hip basis ",hip.basis," knee basis ",knee.basis," visual scale ",visual.scale)
		samples += 1

func begin_case() -> void:
	separation = 0
	length_error = 0
	basis_error = 0
	local_hinge_error = 0
	hip_anchor_error = 0
	bad_transform = false
	reported = false

func end_case(label: String) -> void:
	check(not bad_transform and separation<0.0002 and local_hinge_error<0.0002 and hip_anchor_error<0.0002,label+" keeps every thigh, knee and shin connected (gap %.6f)" % separation)
	check(length_error<0.0003 and basis_error<0.0003,label+" preserves both 0.45m segments without scale/shear (length %.6f, basis %.6f)" % [length_error,basis_error])

func frames(count: int, label: String = "live animation") -> void:
	for i in range(count):
		await physics_frame
		await process_frame
		inspect_pose(label)

func seconds(duration: float, label: String = "live animation") -> void:
	await frames(ceili(duration*hz),label)

func equip(slot: StringName) -> void:
	world.controls._request(&"weapon",slot)
	actor.combat.poll(world.controls)

func attack(action: StringName) -> void:
	world.controls._request(&"action",action)
	actor.combat.poll(world.controls)

func reset() -> void:
	input.move = Vector2.ZERO
	input.sprint = false
	input.boost = false
	input.jump = false
	input.dodge = false
	input.guard = false
	actor.respawn()
	actor.position = Vector3(0,0.05,6)
	actor.visual.rotation.y = PI
	world.camera_rig.yaw = 0
	await seconds(0.4)

func shot() -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 44
	camera.position = actor.position+Vector3(-1.5,1.2,-3.5)
	camera.look_at(actor.position+Vector3.UP*0.9)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/leg_integrity_katana_idle.png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	input = Intent.new()
	root.add_child(input)
	actor.controls = input
	world.camera_rig.controls = input
	begin_case()
	await reset()
	equip(&"right")
	await seconds(1.5,"drawn katana idle")
	end_case("Drawn katana idle")
	begin_case()
	for slot: StringName in Library.LOADOUTS:
		equip(slot)
		for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			attack(action)
			await seconds(float(Library.move(slot,action).duration)+0.25,"combat "+String(slot)+" "+String(action))
	await seconds(1.0,"combat recovery")
	end_case("All weapon attacks and recovery")
	begin_case()
	for cycle in range(6):
		equip(&"right")
		attack(&"special_rt_x")
		await seconds(0.1,"pre-dodge combat")
		actor.dodge.start(Vector3.RIGHT if cycle%2 == 0 else Vector3.LEFT)
		await seconds(0.14,"vanishing dodge")
		if cycle%2 == 0:
			actor.weapon_combat.cancel()
			inspect_pose("cancel while flattened")
			actor.dodge.cancel()
		await seconds(0.6,"materialize and recover")
	end_case("Repeated combat/dodge interruptions")
	begin_case()
	actor.dodge.present(0)
	for id: String in ["LeftLeg","RightLeg"]:
		var knee: Node3D = actor.visual.joints[id].get_node("Hinge")
		actor.visual.combat_leg(id,knee.to_global(Vector3.DOWN*0.45),actor.visual.global_basis.z.normalized())
	inspect_pose("IK while teleport presentation is flattened")
	actor.dodge.present(1)
	actor.visual.clear_combat_pose()
	inspect_pose("restore after flattened IK")
	await seconds(0.2)
	end_case("IK under teleport flattening")
	begin_case()
	await reset()
	equip(&"right")
	actor.position = Vector3(0,0.05,-29)
	await seconds(0.3)
	var targets := get_nodes_in_group("combat_targets")
	actor.target_lock.select(targets[0])
	check(actor.target_lock.is_locked(),"The strafe/backpedal test uses a real living lock target")
	for direction: Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		input.move = direction
		await seconds(0.4,"locked strafing and backpedaling")
	input.move = Vector2.ZERO
	actor.target_lock.clear()
	await seconds(0.4,"lock release")
	end_case("Lock-on locomotion and release")
	begin_case()
	await reset()
	equip(&"right")
	for direction: Vector2 in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
		input.move = direction
		input.sprint = true
		await seconds(0.6,"running direction changes")
	input.move = Vector2.ZERO
	input.sprint = false
	input.jump = true
	await seconds(0.25,"jump ascent")
	input.jump = true
	await seconds(1.0,"sky step and falling cradle")
	await seconds(1.2,"landing and idle recovery")
	end_case("Locomotion, air steps and landing")
	begin_case()
	await reset()
	equip(&"right")
	input.guard = true
	await seconds(0.25,"guard")
	input.guard = false
	actor.weapon_combat.stagger(actor.position+Vector3.FORWARD)
	await seconds(1.3,"forced recoil and recovery")
	end_case("Guard and forced recoil recovery")
	begin_case()
	await reset()
	equip(&"right")
	actor.set_physics_process(false)
	actor.weapon_combat.set_physics_process(false)
	actor.position = Vector3(11,16.235,-45)
	actor.visual._initialized = false
	# Long idle at an elevated world-space junction reproduces accumulated
	# transform error that a short animation capture cannot reveal.
	for frame in range(600*hz):
		actor.visual.animate(1.0/hz,Vector3.ZERO,true)
		actor.weapon_combat.apply_pose(1.0/hz)
		if frame%60 == 0: inspect_pose("long elevated katana idle")
	end_case("Ten-minute elevated katana idle soak")
	await shot()
	print("Leg integrity audit: ",samples," limb samples at ",hz," Hz")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Leg integrity verification: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
