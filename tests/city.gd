extends SceneTree
## Audit the original Neon.block volumes and fixture heads. The batched additions
## receive their own full-volume/face/route audit in tests/metropolis.gd.
const Neon = preload("res://scripts/neon.gd")
var failures := 0
var world: Node3D

func check(condition: bool, description: String) -> void:
	if condition: print("PASS: ",description)
	else:
		push_error("FAIL: "+description)
		failures += 1

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.player.visual.live_retrieval = false
	await frames(30)
	var district: Node3D = world.get_node("CentralDistrict")
	var surfaces: Array[MeshInstance3D] = []
	var bodies: Array[RID] = [world.player.get_rid()]
	var roofs: Array[MeshInstance3D] = []
	var buildings: Array = get_nodes_in_group("city_buildings")
	for node: Node in district.find_children("*","MeshInstance3D",true,false):
		if node.mesh is BoxMesh:
			surfaces.append(node)
			var body: StaticBody3D = node.get_parent().get_node_or_null("Collision")
			if body != null: bodies.append(body.get_rid())
			var size: Vector3 = node.mesh.size
			var in_building := false
			for building: Node3D in buildings:
				if building.is_ancestor_of(node): in_building = true
			if not in_building and size.y >= 3.0 and size.x >= 8.0: roofs.append(node)
	for building: Node3D in buildings: roofs.append(building.roof)
	# Isolate a structural face from adjacent chunks and the new gate leaves as
	# well as other hub boxes. Shared seams can legitimately touch two bodies.
	for body: CollisionObject3D in world.find_children("*","CollisionObject3D",true,false):
		if not bodies.has(body.get_rid()): bodies.append(body.get_rid())
	check(surfaces.size() == 200+buildings.size()*8,"Hub structures include split road-opening walls, twelve perimeter towers and every physical lobby box")
	var missing := 0
	var bad_faces := 0
	var space := world.get_world_3d().direct_space_state
	for surface in surfaces:
		var body: StaticBody3D = surface.get_parent().get_node_or_null("Collision")
		if body == null:
			missing += 1
			continue
		var shape: CollisionShape3D = body.get_child(0)
		if shape.disabled or not shape.shape is BoxShape3D or shape.shape.size != surface.mesh.size or shape.global_transform != surface.global_transform or body.collision_layer & 1 == 0:
			missing += 1
			continue
		var excluded: Array[RID] = bodies.duplicate()
		excluded.erase(body.get_rid())
		# Isolate each body's six faces, including undersides and narrow lamp parts.
		for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
			for sign_value in [-1,1]:
				var normal: Vector3 = axis*sign_value
				var face: Vector3 = normal*surface.mesh.size*0.5
				var query := PhysicsRayQueryParameters3D.create(surface.to_global(face+normal*0.1),surface.to_global(face-normal*0.1),1,excluded)
				var hit := space.intersect_ray(query)
				if hit.is_empty() or hit.collider != body or hit.position.distance_to(surface.to_global(face)) > 0.003 or hit.normal.dot(surface.global_basis*normal) < 0.99:
					bad_faces += 1
	check(missing == 0,"Every structural mesh has a matching enabled full-volume collider")
	check(bad_faces == 0,"All %d structural faces block physics rays, including rooftops" % (surfaces.size()*6))
	check(roofs.size() == 34,"All 22 city buildings and 12 perimeter towers remain around the two outward avenues")
	var landings := 0
	var corner_hits := 0
	for roof in roofs:
		var size: Vector3 = roof.mesh.size
		var top: Vector3 = roof.to_global(Vector3(0,size.y*0.5,0))
		for x in [-0.45,0.45]:
			for z in [-0.45,0.45]:
				var corner: Vector3 = top+Vector3(x*size.x,0,z*size.z)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(corner+Vector3.UP,corner+Vector3.DOWN,1,[world.player.get_rid()]))
				if not hit.is_empty() and hit.normal.y > 0.99 and absf(hit.position.y-top.y) < 0.003: corner_hits += 1
		world.player.global_position = top+Vector3.UP
		world.player.velocity = Vector3.ZERO
		await frames(50)
		if world.player.is_on_floor() and absf(world.player.global_position.y-top.y) < 0.05: landings += 1
	check(corner_hits == 136,"All four corners of all 34 hub roofs provide solid support")
	check(landings == 34,"The real player lands and stays grounded on every city and skyline roof")
	var fixtures := get_nodes_in_group("street_lights")
	# Inspect every fixture's full-quality shadow capability; normal play budgets
	# the nearest casters without removing any orange light or physical post.
	world.graphics.shadow_budget = 16
	world.graphics.apply_quality()
	var valid_lights := 0
	var lamp_landings := 0
	for fixture in fixtures:
		var light: SpotLight3D = fixture.light
		var orange_edges := 0
		for surface: MeshInstance3D in fixture.find_children("*","MeshInstance3D",true,false):
			if surface.mesh is ImmediateMesh and surface.mesh.surface_get_material(0).emission == Neon.ORANGE: orange_edges += 1
		if light.light_color == Neon.ORANGE and light.light_energy > 0 and light.shadow_enabled and (-light.global_basis.z).dot(Vector3.DOWN) > 0.99 and orange_edges == 5:
			valid_lights += 1
		var top: Vector3 = fixture.to_global(Vector3(0,5.76,-2))
		world.player.global_position = top+Vector3.UP
		world.player.velocity = Vector3.ZERO
		await frames(50)
		if world.player.is_on_floor() and absf(world.player.global_position.y-top.y) < 0.05: lamp_landings += 1
	check(fixtures.size() == 16 and valid_lights == 16,"All 16 orange fixtures emit downward orange light with shadows")
	check(lamp_landings == 16,"Every streetlight head physically supports the player")
	var foundation_hits := 0
	for x in [-106,0,106]:
		for z in [-106,0,106]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,2,z),Vector3(x,-1,z),1,[world.player.get_rid()]))
			if not hit.is_empty() and absf(hit.position.y) < 0.003: foundation_hits += 1
	check(foundation_hits == 9,"The extended foundation supports the skyline and outer district")
	# Count conservative light AABB intersections, which determine mesh light lists.
	var max_lights := 0
	for surface in surfaces:
		var bounds: AABB = surface.global_transform*surface.get_aabb()
		var count := 0
		for fixture in fixtures:
			var light: SpotLight3D = fixture.light
			if bounds.intersects(light.global_transform*light.get_aabb()): count += 1
		max_lights = maxi(count,max_lights)
	check(max_lights <= 8,"Every surface stays within Compatibility's eight-spotlight limit (max %d)" % max_lights)
	check(Neon.dark.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL,"Opaque world surfaces receive real lighting")
	world.queue_free()
	await process_frame
	print("CITY RESULT: ",failures," failures; ",surfaces.size()," solids, ",landings," roof landings, ",lamp_landings," lamp landings")
	quit(1 if failures else 0)
