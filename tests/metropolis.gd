extends SceneTree
## World-space checks against the actual physics world, not just mesh metadata.
var world: Node3D
var city: Node3D
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func _initialize() -> void: call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.player.visual.retrieval.enabled = false
	city = world.get_node("CentralDistrict/Metropolis")
	await frames(15)
	check(city.solids.size()>650,"The new district contains real architectural volumes, not background silhouettes")
	check(city.render_batches<city.solids.size()/4,"Static architecture is batched into spatial cells")
	check(city.tree_count == 16 and city.banner_count == 6 and city.skyline_count == 10,"Completed quarters include sixteen geometric trees, six banners and ten new skyline towers")
	var space := world.get_world_3d().direct_space_state
	var excluded: Array[RID] = [world.player.get_rid(),world.sparring_partner.get_rid()]
	var invalid := 0
	var missed_faces := 0
	var face_count := 0
	for volume: Dictionary in city.solids:
		var collider: CollisionShape3D = volume.collider
		if collider.disabled or collider.global_transform != volume.transform or collider.get_parent().collision_layer & 1 == 0:
			invalid += 1
			continue
		if collider.shape is ConvexPolygonShape3D and collider.shape.points != volume.vertices: invalid += 1
		if collider.shape is BoxShape3D:
			var expected: Vector3 = volume.vertices[-1]-volume.vertices[0]
			if not expected.is_equal_approx(collider.shape.size): invalid += 1
		for face: Array in volume.faces:
			var center := Vector3.ZERO
			for index: int in face: center += volume.vertices[index]
			center /= float(face.size())
			var normal: Vector3 = (volume.vertices[face[1]]-volume.vertices[face[0]]).cross(volume.vertices[face[2]]-volume.vertices[face[0]]).normalized()
			if normal.dot(center)<0: normal = -normal
			var transform: Transform3D = volume.transform
			var query := PhysicsRayQueryParameters3D.create(transform*(center+normal*0.07),transform*(center-normal*0.07),1,excluded)
			query.hit_from_inside = true # Internal/overlapping support joints are solid too.
			if space.intersect_ray(query).is_empty(): missed_faces += 1
			face_count += 1
	check(invalid == 0,"Every added structural volume matches enabled box/convex collision")
	check(missed_faces == 0,"All %d new structural faces block physical rays (%d missing)" % [face_count,missed_faces])
	var supported := 0
	var landings := 0
	for route: Dictionary in city.routes:
		var point: Vector3 = route.point
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.3,point-Vector3.UP*0.3,1,excluded))
		if not hit.is_empty() and hit.normal.y>0.9: supported += 1
		else: print("Unsupported route: ",route," ray ",hit)
		world.player.position = point+Vector3.UP*0.8
		world.player.velocity = Vector3.ZERO
		await frames(35)
		if world.player.is_on_floor() and absf(world.player.position.y-point.y)<0.09: landings += 1
		else: print("Failed landing: ",route," actor ",world.player.position)
	check(supported == city.routes.size(),"Both skyways, their landings and all tower ring routes provide support")
	check(landings == city.routes.size(),"The actual player lands on all %d sampled elevated routes (%d landed)" % [city.routes.size(),landings])
	# Follow the complete stairs with the real movement controller and step sweep.
	for side in [-1,1]:
		var p: CharacterBody3D = world.player
		p.respawn()
		p.position = Vector3(side*15,0.2,13.5 if side<0 else 16.3)
		p.velocity = Vector3.ZERO
		world.camera_rig.yaw = 0
		await frames(8)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_W
		event.pressed = true
		Input.parse_input_event(event)
		for tick in range(1000):
			await frames(1)
			if p.position.y>(12.10 if side<0 else 16.10): break
		event = InputEventKey.new()
		event.physical_keycode = KEY_W
		event.pressed = false
		Input.parse_input_event(event)
		await frames(1)
		check(p.position.y>11.8 if side<0 else p.position.y>15.8,"Walking climbs the full %s skyway staircase" % ("west" if side<0 else "east"))
	# Existing NPC and ground route stay at their established coordinates.
	world.player.respawn()
	world.player.position = world.sparring_partner.home+Vector3(-2,0,0)
	await frames(20)
	check(world.sparring_duel.can_talk(),"Ember remains reachable on the east sidewalk")
	var clear := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1.1,6),Vector3(0,1.1,-34),1,excluded))
	check(clear.is_empty(),"The main approach to the practice sentries stays clear at character height")
	var valid_lights := 0
	for light: OmniLight3D in city.light_sources:
		if light.light_color.r>0.9 and light.light_energy>0 and light.omni_range>0 and not light.shadow_enabled: valid_lights += 1
	check(valid_lights == city.light_sources.size(),"Architectural orange luminaires emit real local light with a bounded shadow cost")
	var spots := get_nodes_in_group("street_lights")
	var omnis: Array = city.light_sources.duplicate()
	omnis.append(world.sparring_partner.light)
	var max_spots := 0
	var max_omnis := 0
	var surfaces: Array = world.get_node("CentralDistrict").find_children("*","MeshInstance3D",true,false)
	if world.world_memory!=null: surfaces.append_array(world.world_memory.find_children("*","MeshInstance3D",true,false))
	for surface: MeshInstance3D in surfaces:
		var material: Material = surface.material_override if surface.material_override != null else surface.mesh.surface_get_material(0)
		if not material is StandardMaterial3D or material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL: continue
		var bounds: AABB = surface.global_transform*surface.get_aabb()
		var spot_count := 0
		var omni_count := 0
		for fixture: Node in spots:
			if bounds.intersects(fixture.light.global_transform*fixture.light.get_aabb()): spot_count += 1
		for light: OmniLight3D in omnis:
			if bounds.intersects(light.global_transform*light.get_aabb()): omni_count += 1
		max_spots = maxi(max_spots,spot_count)
		max_omnis = maxi(max_omnis,omni_count)
		if omni_count>8: print("Light overflow: ",surface.get_path()," bounds ",bounds," omni ",omni_count)
	check(max_spots<=8 and max_omnis<=8,"Every world batch stays within Compatibility light lists (spot %d / omni %d)" % [max_spots,max_omnis])
	print("Metropolis audit: ",city.solids.size()," solids, ",city.render_batches," batches, ",face_count," face probes, ",city.light_sources.size()," local architectural lights")
	world.queue_free()
	await process_frame
	print("Metropolis verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
