extends SceneTree
## Inspect the real garment, joints and live poses; no alternate clothing rig.
const Catalog = preload("res://scripts/item_catalog.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void:
		if not gameplay_enabled: move = Vector2.ZERO

var world: Node3D
var p: CharacterBody3D
var robe: Node3D
var controls: Node
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func fabric_points(branch: Node3D, reference: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface: MeshInstance3D in branch.find_children("*","MeshInstance3D",true,false):
		if not surface.mesh is ArrayMesh: continue
		for index in range(surface.mesh.get_surface_count()):
			var material: Material = surface.mesh.surface_get_material(index)
			if not material is StandardMaterial3D or material.albedo_color.get_luminance()>0.08: continue
			var vertices: PackedVector3Array = surface.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in vertices:
				points.append(reference.to_local(surface.to_global(point)))
	return points

func bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty(): return AABB()
	var result := AABB(points[0],Vector3.ZERO)
	for point: Vector3 in points: result = result.expand(point)
	return result

func garment_meshes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in robe.find_children("*","MeshInstance3D",true,false): result.append(mesh)
	for sleeve: Node3D in robe._external_pieces:
		for mesh: MeshInstance3D in sleeve.find_children("*","MeshInstance3D",true,false): result.append(mesh)
	return result

func attachments_safe() -> bool:
	if robe.get_parent()!=p.visual.chest or not robe.position.is_equal_approx(Vector3(0,-p.visual.REST_HIP_HEIGHT,0)): return false
	for entry: Dictionary in robe._sleeves:
		var sleeve: Node3D = entry.node
		var joint: Node3D = entry.joint
		if sleeve.get_parent()!=joint or sleeve.position.length()>0.001 or sleeve.global_position.distance_to(joint.global_position)>0.003: return false
		var shell := bounds(fabric_points(sleeve,sleeve))
		if shell.size.y<entry.length*0.8 or shell.size.y>entry.length+0.08 or shell.size.x>0.31 or shell.size.z<0.10 or shell.size.z>0.35: return false
		if entry.length<0.29 and shell.position.y< -0.275: return false
	for hand: Node3D in [p.weapon_combat.rig.left_hand,p.weapon_combat.rig.right_hand]:
		if hand.position.distance_to(Vector3(0,-0.29,0))>0.002: return false
	return true

func finite_pose() -> bool:
	var points := fabric_points(robe,p.visual)
	for sleeve: Node3D in robe._external_pieces: points.append_array(fabric_points(sleeve,p.visual))
	for point: Vector3 in points:
		if not point.is_finite() or point.length()>3.5: return false
	return not points.is_empty()

func tail_tips() -> PackedVector3Array:
	var result := PackedVector3Array()
	for tail: Node3D in robe._tails:
		var shell := bounds(fabric_points(tail,tail))
		result.append(p.visual.pelvis.to_local(tail.to_global(Vector3(shell.get_center().x,shell.position.y,shell.get_center().z))))
	return result

func shot(label: String, local_offset: Vector3) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var was_physics: bool = p.is_physics_processing()
	var was_combat: bool = p.weapon_combat.is_physics_processing()
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	# Back-mounted shields otherwise hide the very torso and sigil being reviewed.
	# This is capture-only visibility; restore every model after the still frame.
	var weapon_visibility: Dictionary = {}
	for models: Dictionary in p.weapon_combat.rig.models.values():
		for key: String in ["right","left","stowed"]:
			var model: Node3D = models[key]
			weapon_visibility[model] = model.visible
			model.visible = false
	var resident_visibility: Dictionary = {}
	for resident: Node3D in world.population.residents:
		resident_visibility[resident] = resident.visible
		resident.visible = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 38
	camera.global_position = p.visual.global_position+p.visual.global_basis*local_offset
	camera.look_at(p.visual.global_position+Vector3.UP*1.02)
	camera.current = true
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/fitted_"+label+".png")
	print("CAPTURE: fitted_",label)
	camera.queue_free()
	world.camera_rig.camera.current = true
	for model: Node3D in weapon_visibility: model.visible = weapon_visibility[model]
	for resident: Node3D in resident_visibility: resident.visible = resident_visibility[resident]
	p.set_physics_process(was_physics)
	p.weapon_combat.set_physics_process(was_combat)

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.get_slice("=",1))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	p = world.player
	p.visual.retrieval.enabled = false
	world.population.set_physics_process(false)
	controls = Intent.new()
	root.add_child(controls)
	p.controls = controls
	world.inventory_session.controls = controls
	controls.interaction_context = world.inventory_session
	world.camera_rig.controls = controls
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(8)
	var item: Resource = Catalog.create(&"eternal_scribe_robes")
	check(p.inventory.add_item(item) and world.loot.request_equip(p.inventory,&"body",item.instance_id),"The fitted robe equips through existing item ownership and Body authority")
	robe = p.visual.robe
	p.combat.sheathed = true
	p.weapon_combat.sync_rig()
	p.visual.rotation.y = PI
	await frames(15)
	var torso := bounds(fabric_points(robe._back_cloak,robe._back_cloak))
	print("FITTED TORSO: ",torso)
	check(torso.size.y>0.35 and torso.size.y<0.65 and torso.size.x<0.65,"The fitted back stops at the waist instead of forming a full-length board")
	var chest_points := PackedVector3Array()
	for point: Vector3 in fabric_points(robe,robe):
		if point.y>1.10 and point.y<1.47: chest_points.append(point)
	var chest_bounds := bounds(chest_points)
	print("FITTED CHEST: ",chest_bounds)
	check(chest_bounds.size.x<0.65 and chest_bounds.size.x>0.38 and chest_bounds.size.z>0.17,"The body has a narrow wrapped silhouette with actual front-to-back depth")
	var hood_points := PackedVector3Array()
	for point: Vector3 in fabric_points(robe,robe):
		if point.y>1.52: hood_points.append(point)
	var hood_bounds := bounds(hood_points)
	check(hood_bounds.size.x>0.3 and hood_bounds.size.x<0.63 and hood_bounds.size.z>0.17,"The narrower hood wraps around the head instead of widening the whole figure")
	check(robe._tails.size()==4,"Four split tails replace the single rigid long back panel")
	var tails_fitted := true
	for tail: Node3D in robe._tails:
		var shape := bounds(fabric_points(tail,tail))
		tails_fitted = tails_fitted and shape.size.x<0.51 and shape.size.y>0.50 and shape.size.y<0.98
		var hip_point: Vector3 = p.visual.pelvis.to_local(tail.global_position)
		tails_fitted = tails_fitted and absf(hip_point.y)<0.10 and absf(hip_point.x)<0.4
	check(tails_fitted,"Each separate tail hangs from the hips with a narrow, leg-length hem")
	check(attachments_safe() and finite_pose(),"Fitted sleeves articulate at both arm links and leave wrists and weapon grips anchored")
	check(robe._glyph_nodes.size()==12 and robe.has_back_sigil() and robe.get_front_inscription_count()==6,"Twelve living inscriptions and the geometric back sigil survive the adaptation")
	check(robe.get_trail_speck_count()==12 and robe.get_trail_symbol_count()==9,"Movement effects retain fixed speck and symbol pools")
	var meshes: Array[MeshInstance3D] = garment_meshes()
	var face_vertices := 0
	for surface: MeshInstance3D in meshes:
		if surface.mesh is ArrayMesh:
			for index in range(surface.mesh.get_surface_count()): face_vertices += surface.mesh.surface_get_array_len(index)
	print("GARMENT BUDGET: ",meshes.size()," mesh instances; ",face_vertices," ArrayMesh vertices")
	check(meshes.size()<160 and face_vertices<15000,"The complete fitted outfit remains a bounded cosmetic geometry budget")
	var no_collision := robe.find_children("*","CollisionObject3D",true,false).is_empty()
	for sleeve: Node3D in robe._external_pieces: no_collision = no_collision and sleeve.find_children("*","CollisionObject3D",true,false).is_empty()
	check(no_collision,"Garment volume introduces no collider or movement obstruction")
	await shot("front",Vector3(0.8,1.2,4.5))
	await shot("back",Vector3(-0.9,1.2,-4.5))
	await shot("side",Vector3(4.5,1.15,0.6))
	var idle_tips := tail_tips()
	controls.move = Vector2(0,-1)
	controls.boost = true
	await frames(hz)
	var run_tips := tail_tips()
	var animated := 0
	var differing := false
	for index in range(run_tips.size()):
		if idle_tips[index].distance_to(run_tips[index])>0.08: animated += 1
		if index>0 and (run_tips[index]-idle_tips[index]).distance_to(run_tips[0]-idle_tips[0])>0.025: differing = true
	check(animated==4 and differing,"All four tails flow during running with separate motion rather than one board transform")
	check(attachments_safe() and finite_pose() and p.velocity.length()>7,"Running keeps sleeve attachments stable and preserves full ground responsiveness")
	await shot("run",Vector3(3.8,1.3,-2.0))
	controls.jump_requested = true
	await frames(3)
	controls.jump_requested = true
	await frames(3)
	check(p.air_step_count==1 and p.velocity.y>0 and attachments_safe() and finite_pose(),"A live Sky Jump keeps the fitted garment attached without restricting aerial movement")
	await shot("sky_step",Vector3(3.8,1.2,-2.0))
	controls.move = Vector2.ZERO
	controls.boost = false
	p.respawn()
	p.combat.sheathed = true
	p.weapon_combat.sync_rig()
	await frames(12)
	var actions: Node3D = world.world_actions
	var seat: Dictionary = actions.seats[0]
	p.position = seat.point+seat.forward*1.1
	p.position.y = 0.05
	p.velocity = Vector3.ZERO
	await frames(10)
	check(actions.interact() and not actions.seat.is_empty(),"The worn robe retains real bench interaction")
	await frames(hz/2)
	check(attachments_safe() and finite_pose() and absf(p.visual.joints.LeftLeg.rotation.x)>0.8,"Seated hips and bent elbows remain articulated under the fitted coat")
	await shot("seated",Vector3(3.8,1.2,2.5))
	actions.detach()
	p.position = Vector3(0,0.05,6)
	p.velocity = Vector3.ZERO
	await frames(10)
	var bike := Vehicle.new()
	bike.record = {"id":99001,"kind":"motorcycle","point":Vector3(0,0.05,9),"yaw":0.0,"traffic":false,"taken":true,"route":PackedVector3Array(),"cursor":0,"color":Color("ffc95c"),"driver":{"tint":Color.CYAN,"body_profile":&"male"}}
	world.add_child(bike)
	bike.set_physics_process(false)
	p.position = bike.position+Vector3(0,0,-2.1)
	p.velocity = Vector3.ZERO
	await frames(4)
	check(actions.board(bike),"The fitted robe can enter an actual motorcycle through the shared attachment path")
	await frames(hz/2)
	check(attachments_safe() and finite_pose() and absf(p.visual.joints.LeftArm.rotation.x)>0.9,"Mounted posture preserves articulated sleeves, attached hems and free wrists")
	await shot("motorcycle",Vector3(3.8,1.5,-2.5))
	actions.detach()
	bike.queue_free()
	p.respawn()
	await frames(8)
	var instances_before: Dictionary = {}
	for mesh: MeshInstance3D in meshes: instances_before[mesh.get_instance_id()] = true
	var glyph_generation: int = robe.get_inscription_generation_count()
	await frames(hz*6)
	var meshes_after: Array[MeshInstance3D] = garment_meshes()
	var unchanged := meshes_after.size()==meshes.size()
	for mesh: MeshInstance3D in meshes_after: unchanged = unchanged and instances_before.has(mesh.get_instance_id())
	check(unchanged and robe.get_inscription_generation_count()>glyph_generation,"Living inscription cycles reuse every garment mesh instead of growing render objects")
	var sleeves: Array = robe._external_pieces.duplicate()
	check(world.loot.request_unequip(p.inventory,&"body") and not robe.is_processing(),"Removing fitted clothing still stops its processing")
	var hidden := not robe.visible
	for sleeve: Node3D in sleeves: hidden = hidden and not sleeve.visible
	check(hidden,"Removing the outfit also hides all articulated sleeve pieces")
	world.queue_free()
	controls.queue_free()
	await frames()
	print("Fitted robes verification: %d checks, %d failures at %d Hz" % [checks,failures,hz])
	quit(1 if failures else 0)
