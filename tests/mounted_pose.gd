extends SceneTree
## Exercise the real attachment, articulated rider and owned garment together.
const Catalog = preload("res://scripts/item_catalog.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
const Chunk = preload("res://scripts/world_chunk.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void:
		if not gameplay_enabled: move = Vector2.ZERO
class FrameObserver:
	extends Node
	signal finished
	func _process(_delta: float) -> void: finished.emit()

var world: Node3D
var p: CharacterBody3D
var actions: Node3D
var controls: Node
var robe: Node3D
var robe_iid := ""
var frame_observer: Node
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
	for index in range(count):
		await physics_frame
		# SceneTree.process_frame is emitted before garment _process callbacks.
		# Observe the state after their real update, as the renderer will see it.
		if is_instance_valid(frame_observer): await frame_observer.finished
		else: await process_frame

func endpoint(side: String, limb: String) -> Vector3:
	var joint: Node3D = p.visual.joints[side+limb]
	return joint.get_node("Hinge").to_global(Vector3.DOWN*(0.45 if limb=="Leg" else 0.29))

func anchor_error(vehicle: Node3D, anchors: Dictionary) -> float:
	var result := 0.0
	for side: String in ["Left","Right"]:
		for pair: Array in [["Leg","_foot"],["Arm","_hand"]]:
			var key: String = side.to_lower()+pair[1]
			result = maxf(result,vehicle.to_local(endpoint(side,pair[0])).distance_to(anchors[key]))
	return result

func limb_points(vehicle: Node3D, side: String) -> PackedVector3Array:
	var thigh: Node3D = p.visual.joints[side+"Leg"]
	return PackedVector3Array([vehicle.to_local(thigh.global_position),vehicle.to_local(thigh.get_node("Hinge").global_position),vehicle.to_local(endpoint(side,"Leg"))])

func volume_bounds(vehicle: Node3D, kind: String) -> AABB:
	for child: Node in vehicle.get_children():
		if child.get_script()!=Chunk: continue
		for volume: Dictionary in child.volumes:
			if volume.kind!=kind: continue
			var result := AABB(volume.transform*volume.vertices[0],Vector3.ZERO)
			for point: Vector3 in volume.vertices: result = result.expand(volume.transform*point)
			return result
	return AABB()

func headlights_attached(vehicle: Node3D) -> bool:
	var fairing := volume_bounds(vehicle,"HeadlightFairing")
	var frame := volume_bounds(vehicle,"Frame")
	if fairing.size.is_zero_approx() or frame.size.is_zero_approx() or not fairing.intersects(frame): return false
	var count := 0
	for lamp: SpotLight3D in vehicle.lamps:
		var attached := false
		for child: Node in vehicle.get_children():
			if not child is MeshInstance3D or not child.mesh is BoxMesh: continue
			if child.position.distance_to(lamp.position)>0.001: continue
			# The rear face of the actual lens overlaps the actual front fairing.
			var contact: Vector3 = child.position-Vector3.BACK*child.mesh.size.z*0.5
			attached = fairing.grow(0.004).has_point(contact)
		if attached: count += 1
	return count==2

func traffic_contacts(vehicle: Node3D, anchors: Dictionary) -> bool:
	var driver: Node3D = vehicle.driver_visual
	for index in range(2):
		var prefix := "left" if index==0 else "right"
		var foot: Vector3 = driver.to_global(driver.joints.get_instance_transform(4+index*3).origin)
		var hand: Vector3 = driver.to_global(driver.joints.get_instance_transform(9+index*2).origin)
		if vehicle.to_local(foot).distance_to(anchors[prefix+"_foot"])>0.002 or vehicle.to_local(hand).distance_to(anchors[prefix+"_hand"])>0.002:
			print("TRAFFIC CONTACTS: ",vehicle.kind," ",prefix," foot=",vehicle.to_local(foot)," hand=",vehicle.to_local(hand)," expected=",anchors[prefix+"_foot"],anchors[prefix+"_hand"])
			return false
	return driver.get_child_count()==2

func distant_contacts(vehicle: Node3D, anchors: Dictionary) -> float:
	var before: Transform3D = vehicle.global_transform
	var maximum := 0.0
	for origin: Vector3 in [Vector3(1048,0.05,900),Vector3(-1048,0.05,-900)]:
		for tick in range(180):
			vehicle.position = origin+Vector3(0.003*tick,0,0.002*tick)
			vehicle.rotation.y = tick*0.007
			actions.apply_pose()
			maximum = maxf(maximum,anchor_error(vehicle,anchors))
	vehicle.global_transform = before
	actions.apply_pose()
	return maximum

func fabric_triangles(branch: Node3D, reference: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface: MeshInstance3D in branch.find_children("*","MeshInstance3D",true,false):
		if not surface.is_visible_in_tree() or not surface.mesh is ArrayMesh: continue
		for index in range(surface.mesh.get_surface_count()):
			var material: Material = surface.mesh.surface_get_material(index)
			if not material is StandardMaterial3D or material.albedo_color.get_luminance()>0.08: continue
			var vertices: PackedVector3Array = surface.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
			for point: Vector3 in vertices: result.append(reference.to_local(surface.to_global(point)))
	return result

func intersects_triangle(start: Vector3, finish: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	# Segment/triangle intersection, independent of the clothing's transforms.
	var direction := finish-start
	var edge1 := b-a
	var edge2 := c-a
	var cross := direction.cross(edge2)
	var determinant := edge1.dot(cross)
	if absf(determinant)<0.000001: return false
	var inverse := 1.0/determinant
	var from_a := start-a
	var u := from_a.dot(cross)*inverse
	if u<0 or u>1: return false
	var q := from_a.cross(edge1)
	var v := direction.dot(q)*inverse
	if v<0 or u+v>1: return false
	var t := edge2.dot(q)*inverse
	return t>0.001 and t<0.999

func bike_cloth_clear(vehicle: Node3D) -> bool:
	var legs: Array[PackedVector3Array] = [limb_points(vehicle,"Left"),limb_points(vehicle,"Right")]
	var hip: Vector3 = vehicle.to_local(p.visual.pelvis.global_position)
	for tail: Node3D in robe._tails:
		if not tail.is_visible_in_tree():
			print("CLOTH: hidden bike tail ",tail.name)
			return false
		var points := fabric_triangles(tail,vehicle)
		if points.is_empty():
			print("CLOTH: empty bike fabric ",tail.name)
			return false
		var hem := Vector3.ZERO
		var hem_count := 0
		for point: Vector3 in points:
			if not point.is_finite() or point.y<0.76:
				print("CLOTH: low fabric ",tail.name," point=",point)
				return false
			if point.z<hip.z-0.20:
				hem += point
				hem_count += 1
		if hem_count<points.size()/3 or hem.z/hem_count>hip.z-0.20:
			print("CLOTH: insufficient rear flow ",tail.name," rear vertices=",hem_count,"/",points.size()," hip=",hip)
			return false
		for leg: PackedVector3Array in legs:
			for segment in range(2):
				for index in range(0,points.size(),3):
					if intersects_triangle(leg[segment],leg[segment+1],points[index],points[index+1],points[index+2]):
						print("CLOTH: leg intersection ",tail.name," leg=",leg," triangle=",points[index],points[index+1],points[index+2])
						return false
	return true

func cabin_cloth_hidden() -> bool:
	if not robe.is_equipped() or not robe._back_cloak.is_visible_in_tree(): return false
	for tail: Node3D in robe._tails:
		if tail.is_visible_in_tree() or not fabric_triangles(tail,p.visual).is_empty(): return false
	for sleeve: Node3D in robe._external_pieces:
		if not sleeve.is_visible_in_tree(): return false
	return true

func visible_tails() -> bool:
	for tail: Node3D in robe._tails:
		if not tail.is_visible_in_tree() or fabric_triangles(tail,p.visual).is_empty(): return false
	return true

func relaxed_arms() -> bool:
	for side: String in ["Left","Right"]:
		var arm: Node3D = p.visual.joints[side+"Arm"]
		var hinge: Node3D = arm.get_node("Hinge")
		var wrist: Vector3 = hinge.to_global(Vector3.DOWN*0.29)
		var drop: float = (arm.global_position-wrist).dot(p.visual.global_basis.y)
		if absf(arm.rotation.y)>0.02 or absf(hinge.rotation.y)>0.02 or absf(hinge.rotation.z)>0.02 or drop<0.45:
			print("DISMOUNT ARMS: ",side," shoulder=",arm.rotation," elbow=",hinge.rotation," wrist drop=",drop)
			return false
	return true

func shot(label: String, vehicle: Node3D, offset: Vector3, show_weapons: bool = false) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if "--weapons-only" in OS.get_cmdline_user_args() and not show_weapons: return
	var weapon_visibility: Dictionary = {}
	if not show_weapons:
		for models: Dictionary in p.weapon_combat.rig.models.values():
			for key: String in ["right","left","stowed"]:
				var model: Node3D = models[key]
				weapon_visibility[model] = model.visible
				model.visible = false
	var resident_visibility: Dictionary = {}
	for resident: Node3D in world.population.residents:
		resident_visibility[resident] = resident.visible
		resident.visible = false
	for pickup: Node3D in world.loot.pickups.values():
		resident_visibility[pickup] = pickup.visible
		pickup.visible = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 38
	camera.global_position = vehicle.to_global(offset)
	camera.look_at(vehicle.to_global(Vector3(0,1.0,0)))
	camera.current = true
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/mounted_"+label+".png")
	print("CAPTURE: mounted_",label)
	camera.queue_free()
	world.camera_rig.camera.current = true
	for model: Node3D in weapon_visibility: model.visible = weapon_visibility[model]
	for resident: Node3D in resident_visibility: resident.visible = resident_visibility[resident]

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.get_slice("=",1))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	frame_observer = FrameObserver.new()
	frame_observer.process_priority = 10000
	root.add_child(frame_observer)
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	p = world.player
	actions = world.world_actions
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
	check(p.inventory.add_item(item) and world.loot.request_equip(p.inventory,&"body",item.instance_id),"Mounted tests equip a genuinely owned robe through Body authority")
	robe = p.visual.robe
	robe_iid = item.instance_id
	var original_layer: int = p.collision_layer
	var original_mask: int = p.collision_mask
	var capsule: Shape3D = p.get_child(0).shape
	var pace := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	controls._request(&"weapon",&"right")
	p.combat.poll(controls)
	for kind: String in ["motorcycle","car","truck"]:
		var vehicle := Vehicle.new()
		vehicle.record = {"id":99011,"kind":kind,"point":Vector3(0,0.05,8),"yaw":0.0,"traffic":false,"taken":true,"route":PackedVector3Array(),"cursor":0,"color":Color("ffc95c"),"driver":{"tint":Color.CYAN,"body_profile":&"female" if kind=="truck" else &"male"}}
		world.add_child(vehicle)
		vehicle.set_physics_process(false)
		var anchors: Dictionary = vehicle.rider_anchors()
		await frames(2)
		if DisplayServer.get_name()!="headless":
			check(traffic_contacts(vehicle,anchors),"Traffic "+kind+" drivers share the same planted hand/foot contacts without extra draw batches")
		else: print("NATIVE ONLY: MultiMesh traffic contacts for ",kind," (dummy renderer returns stub transforms)")
		if kind=="motorcycle":
			var pegs := volume_bounds(vehicle,"RearSetFootPegs")
			check(absf(anchors.left_foot.y-0.045-pegs.end.y)<0.004 and anchors.left_foot.z<anchors.hip.z-0.15,"Actual rear-set peg geometry supports the rider's foot soles behind the saddle")
			check(headlights_attached(vehicle),"Both motorcycle lenses attach to a front fairing that physically joins the visible frame")
		for heading: float in [0.0,PI*0.5,-PI*0.75]:
			vehicle.position = Vector3(0,0.05,8)+Vector3(heading,0,-heading)
			vehicle.rotation.y = heading
			p.position = vehicle.to_global(Vector3(0,0,-2.0))
			p.velocity = Vector3.ZERO
			await frames(3)
			check(actions.board(vehicle),"Board "+kind+" at heading "+str(heading))
			await frames(1)
			if is_zero_approx(heading):
				check(bike_cloth_clear(vehicle) if kind=="motorcycle" else cabin_cloth_hidden(),"Mounting "+kind+" adopts its safe cloth profile on the first updated frame")
			await frames(maxi(6,hz/2))
			var error := anchor_error(vehicle,anchors)
			print("RIDER: ",kind," yaw=",heading," endpoint error=",error)
			if kind!="motorcycle" and is_zero_approx(heading):
				var hood: Node3D = robe.find_child("OpenScholarHood",true,false)
				var hood_max_y := -INF
				for point: Vector3 in fabric_triangles(hood,vehicle): hood_max_y = maxf(hood_max_y,point.y)
				var roof := volume_bounds(vehicle,"Roof")
				print("CABIN HOOD: ",kind," maximum fabric y=",hood_max_y," roof=",roof)
				check(hood_max_y<roof.position.y-0.001,"The "+kind+" hood fits beneath the solid roof instead of protruding through it")
			check(error<0.025 and vehicle.to_local(p.visual.pelvis.global_position).distance_to(anchors.hip)<0.005,"Actual hands and feet reach vehicle anchors independently of world heading")
			var feet_safe := true
			for side: String in ["Left","Right"]:
				var leg := limb_points(vehicle,side)
				feet_safe = feet_safe and leg[2].y>0.28 and leg[1].y>0.28 and leg[2].y<leg[0].y-0.12
				if kind=="motorcycle": feet_safe = feet_safe and leg[2].z<leg[0].z-0.15 and absf(leg[2].x)>0.20
				else: feet_safe = feet_safe and leg[2].z>leg[0].z+0.40 and absf(leg[2].x)<vehicle.dimensions.x*0.5-0.15 and leg[2].z<vehicle.dimensions.z*0.5-0.30
			check(feet_safe,"Both "+kind+" feet stay above the floor at rear pegs or inside the pedal well")
			if kind=="motorcycle":
				var chest_up: Vector3 = vehicle.global_basis.inverse()*(p.visual.chest.global_basis*Vector3.UP)
				check(chest_up.z>0.45 and chest_up.y>0.40,"Motorcycle rider crouches forward toward the controls in a Tron-like riding posture")
				check(bike_cloth_clear(vehicle),"All four motorcycle tails stream behind the hips above the wheels without crossing either leg")
			else: check(cabin_cloth_hidden(),"Enclosed "+kind+" stows tail fabric and glyphs while retaining jacket and sleeves")
			vehicle.velocity = vehicle.global_basis.z*14
			for moving_tick in range(maxi(4,hz/3)):
				vehicle.position += vehicle.velocity/hz
				await frames(1)
			check(anchor_error(vehicle,anchors)<0.025 and (bike_cloth_clear(vehicle) if kind=="motorcycle" else cabin_cloth_hidden()),"Travel speed preserves planted contacts and mounted cloth clearance")
			vehicle.velocity = Vector3.ZERO
			if is_zero_approx(heading):
				var distant_error := distant_contacts(vehicle,anchors)
				print("DISTANT RIDER: ",kind," 360 poses near (+/-1048,+/-900), max endpoint error=",distant_error)
				check(distant_error<0.002,"Repeated "+kind+" poses remain planted after driving to distant positive and negative world coordinates")
				await frames(2)
				if kind=="motorcycle":
					await shot("bike_side",vehicle,Vector3(4.8,1.30,-0.4))
					await shot("bike_rear",vehicle,Vector3(3.8,1.8,-3.8))
					await shot("bike_front",vehicle,Vector3(3.0,1.5,4.4))
					await shot("bike_katana",vehicle,Vector3(4.8,1.30,-0.4),true)
				else:
					await shot(kind+"_low_side",vehicle,Vector3(6.5,0.75,0.2))
					if kind=="car": await shot("car_katana",vehicle,Vector3(6.5,0.75,0.2),true)
			check(actions.leave(),"Stationary "+kind+" still provides a collision-safe exit")
			await frames(maxi(6,hz/3))
			check(not actions.attached() and p.collision_layer==original_layer and p.collision_mask==original_mask and visible_tails(),"Exiting restores physical collision and all four on-foot tails")
			check(relaxed_arms(),"Leaving "+kind+" restores relaxed shoulders and elbows without inherited IK twist")
			if kind=="motorcycle" and is_zero_approx(heading):
				await shot("bike_dismounted_front",p,Vector3(0.8,1.2,4.5),true)
				await shot("bike_dismounted_side",p,Vector3(4.5,1.2,0.5),true)
		# Clothing toggles use the same ownership/equipment route while mounted.
		p.position = vehicle.to_global(Vector3(0,0,-2.0))
		p.velocity = Vector3.ZERO
		await frames(3)
		check(actions.board(vehicle) and world.loot.request_unequip(p.inventory,&"body"),"The "+kind+" pose remains valid when the owned garment is removed")
		await frames(4)
		check(anchor_error(vehicle,anchors)<0.025 and not robe.is_equipped(),"Bare mounted limbs keep the same exact vehicle contacts")
		check(world.loot.request_equip(p.inventory,&"body",robe_iid),"The existing Body slot can equip clothing while riding "+kind)
		await frames(maxi(6,hz/2))
		check(bike_cloth_clear(vehicle) if kind=="motorcycle" else cabin_cloth_hidden(),"Reequipped clothing immediately adopts the correct mounted presentation")
		actions.detach()
		p.position = Vector3(0,0.05,3)
		vehicle.queue_free()
		await frames(4)
	# Use a real registered bench, preserving its pre-existing seated profile.
	var seat: Dictionary = actions.seats[0]
	p.position = seat.point+seat.forward*1.1
	p.position.y = 0.05
	p.velocity = Vector3.ZERO
	await frames(10)
	check(actions.interact() and not actions.seat.is_empty(),"Real bench interaction remains available after repeated vehicle changes")
	await frames(maxi(6,hz/3))
	var bench_ok := true
	for side: String in ["Left","Right"]:
		var leg: Node3D = p.visual.joints[side+"Leg"]
		bench_ok = bench_ok and absf(leg.rotation.x+1.14)<0.002 and absf(leg.get_node("Hinge").rotation.x-1.14)<0.002
	check(bench_ok and visible_tails(),"Bench sitting retains its established seated pose and unstowed robe tails")
	check(actions.leave(),"Bench standing still follows collision-safe exit handling")
	controls.move = Vector2.UP
	await frames(maxi(8,hz/2))
	check(p.velocity.length()>1 and p.get_child(0).shape==capsule and Vector3(p.walk_speed,p.run_speed,p.boost_speed)==pace and not paused,"Dismounted movement, speeds, capsule and continuously running world remain intact")
	controls.move = Vector2.ZERO
	world.queue_free()
	controls.queue_free()
	await frames()
	print("Mounted pose verification: %d checks, %d failures at %d Hz" % [checks,failures,hz])
	quit(1 if failures else 0)
