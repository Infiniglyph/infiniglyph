extends SceneTree
## Physical entrances, furnishing contracts and a full-height walking capsule.
const Regions = preload("res://scripts/world_regions.gd")
const Buildings = preload("res://scripts/civilian_establishments.gd")
const Room = preload("res://scripts/private_room_interior.gd")
class Walker extends CharacterBody3D:
	var direction := Vector3.ZERO
	func _ready() -> void:
		floor_snap_length = .35
		floor_max_angle = deg_to_rad(48)
		var collider := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = .27
		shape.height = 1.85
		collider.shape = shape
		collider.position.y = .95
		add_child(collider)
	func _physics_process(delta: float) -> void:
		velocity.x = direction.x*3.5
		velocity.z = direction.z*3.5
		if not is_on_floor(): velocity.y -= 22*delta
		else: velocity.y = 0
		move_and_slide()
var scene: Node3D
var regions: Node3D
var buildings: Node3D
var room: Node3D
var actor: Walker
var checks := 0
var failures := 0
var hz := 60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func settle(at: Vector3) -> void:
	actor.global_position = at+Vector3.UP*.07
	actor.velocity = Vector3.ZERO
	actor.direction = Vector3.ZERO
	await frames(ceili(.4*hz))

func walk_to(at: Vector3) -> bool:
	for i in range(hz*12):
		var offset := at-actor.global_position
		offset.y = 0
		if offset.length()<.16:
			actor.direction = Vector3.ZERO
			await frames(ceili(.15*hz))
			return actor.is_on_floor() and absf(actor.global_position.y-at.y)<.25
		actor.direction = offset.normalized()
		await frames(1)
	actor.direction = Vector3.ZERO
	print("WALK BLOCKED: ",actor.global_position," -> ",at)
	return false

func supported_clear(at: Vector3) -> bool:
	var space := scene.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.5,at-Vector3.UP*.8,1,[actor.get_rid()]))
	if hit.is_empty() or absf(hit.position.y-at.y)>.15: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = actor.get_child(0).shape
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY,hit.position+Vector3.UP*1.0)
	return space.intersect_shape(query,1).is_empty()

func capture_views() -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	for parent: Node3D in [buildings,room]:
		for geometry: GeometryInstance3D in parent.find_children("*","GeometryInstance3D",true,false): geometry.layers = 2
	var camera := Camera3D.new()
	camera.cull_mask = 2
	camera.fov = 65
	scene.add_child(camera)
	camera.current = true
	for view: Array in [["guild_exterior",buildings.guild,Vector3(35,15,41),Vector3(0,4,0)],["guild_reception",buildings.guild,Vector3(5,2.8,14),Vector3(-8,1.8,-2)],["guild_upper_hall",buildings.guild,Vector3(14,6.5,-9),Vector3(-5,6.4,-16)],["tavern_interior",buildings.tavern,Vector3(0,2.7,11.5),Vector3(0,1.6,-4)],["private_room",room,Vector3(0,2.7,5.9),Vector3(0,1.6,-3.5)]]:
		camera.global_position = view[1].to_global(view[2])
		camera.look_at(view[1].to_global(view[3]))
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/establishments_"+view[0]+".png")
		print("ESTABLISHMENT CAPTURE: ",view[0])

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	regions = Regions.new()
	scene.add_child(regions)
	buildings = regions.establishments
	room = Room.new()
	room.position = Vector3(1400,0,0)
	scene.add_child(room)
	actor = Walker.new()
	scene.add_child(actor)
	await frames(3)
	check(Regions.grid_at(buildings.guild.global_position)==Vector2i(-2,10) and Regions.grid_at(buildings.tavern.global_position)==Vector2i(-1,14),"Businesses occupy the two requested latitude/longitude cells")
	check(Buildings.reserves_plot(Vector3(-32,0,-160)) and Buildings.reserves_plot(Vector3(-32,0,-224)) and not Buildings.reserves_plot(Vector3(32,0,-160)),"Only their two original city scenery lots are reserved")
	var overlaps := 0
	for data: Dictionary in regions.buildings:
		if data.region!="city": continue
		var original := Rect2(data.point.x-data.size.x*.5,data.point.z-data.size.z*.5,data.size.x,data.size.z)
		for footprint: Rect2 in [Rect2(-52,-177,40,34),Rect2(-24,-237,16,26)]:
			if original.intersects(footprint): overlaps += 1
	check(overlaps==0,"Replaced city blocks retain no original skyscraper visual or collision footprint")
	var ids: Dictionary = {}
	var valid := true
	for data: Dictionary in buildings.points:
		valid = valid and not ids.has(data.id) and is_instance_valid(data.anchor) and not String(data.label).is_empty()
		ids[data.id] = data.kind
	check(valid and ids.has(&"reception") and ids.has(&"board_security") and ids.has(&"board_commerce") and ids.has(&"board_exploration") and ids.has(&"bartender") and ids.has(&"room_3"),"Public services, three faction boards, private doors and furniture expose unique reusable interaction anchors")
	check(buildings.room_exit.size()==3 and buildings.room_arrivals.size()==3,"Every upstairs room entrance has an independent safe return marker")
	var all_supported := true
	for arrival: Marker3D in buildings.room_arrivals: all_supported = all_supported and supported_clear(arrival.global_position)
	check(all_supported,"All upstairs return positions have real floor support and standing capsule clearance")
	check(buildings.seats.size()==13,"Guild seating, tavern tables and bar stools expose thirteen usable seat records")
	var seats_valid := true
	for data: Dictionary in buildings.seats:
		seats_valid = seats_valid and data.occupant==null and data.world==scene.get_world_3d() and is_equal_approx(data.forward.length(),1)
	check(seats_valid,"Seat records have bounded world positions, facing and vacant ownership")
	for spec: Array in [[buildings.guild,17.0,"Guild"],[buildings.tavern,13.0,"Tavern"]]:
		var outside: Vector3 = spec[0].to_global(Vector3(0,Buildings.GROUND,spec[1]+2))
		var inside: Vector3 = spec[0].to_global(Vector3(0,Buildings.GROUND,spec[1]-3))
		await settle(outside)
		check(await walk_to(inside),spec[2]+" front entrance admits the full-size walking capsule seamlessly")
		check(await walk_to(outside),spec[2]+" can be walked out through the same open door")
	await settle(buildings.stair_route[0])
	var upstairs := true
	for at: Vector3 in buildings.stair_route.slice(1): upstairs = await walk_to(at) and upstairs
	check(upstairs and actor.global_position.y>4.6,"Ordinary walking climbs the smooth physical guild staircase into the public upper hallway")
	var downstairs := true
	var reverse: Array = buildings.stair_route.duplicate()
	reverse.reverse()
	for at: Vector3 in reverse.slice(1): downstairs = await walk_to(at) and downstairs
	check(downstairs and actor.global_position.y<.3,"The same stair flight descends smoothly without rail or ceiling snags")
	var room_ids: Dictionary = {}
	for data: Dictionary in room.points: room_ids[data.id] = data.kind
	check(room_ids.get(&"computer")==&"storage" and room_ids.has(&"bed") and room_ids.has(&"room_chair") and room_ids.has(&"room_table") and room_ids.has(&"room_exit"),"Instanced lodging furnishes a bed, chair, table, storage computer and exit")
	check(supported_clear(room.spawn_anchor.global_position),"Private-room reconstruction arrival has real support and standing clearance")
	await settle(room.spawn_anchor.global_position)
	check(await walk_to(room.to_global(Vector3(0,Room.FLOOR,-3))),"Private room preserves a clear central walking lane between its furnishings")
	var batches := 0
	var surfaces := 0
	for node: Node in [buildings.guild.get_node("GuildBatch"),buildings.tavern.get_node("TavernBatch"),room.structure]:
		batches += 1
		surfaces += node.mesh_instance.mesh.get_surface_count()
	check(batches==3 and surfaces==6,"Public buildings and lodging use three immutable two-surface geometry batches")
	check(not paused,"Physical architecture never pauses the world simulation")
	await capture_views()
	scene.queue_free()
	await frames(2)
	print("Establishment architecture: ",checks," checks, ",failures," failures @",hz," Hz")
	quit(1 if failures else 0)
