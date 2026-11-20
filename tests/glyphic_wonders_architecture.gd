extends SceneTree
## Real standing capsule paths, cold collision support and bounded hall geometry.
const Exterior=preload("res://scripts/glyphic_wonders_exterior.gd")
const Hall=preload("res://scripts/glyphic_wonders_hall.gd")
const Regions=preload("res://scripts/world_regions.gd")
const Chunk=preload("res://scripts/world_chunk.gd")
class Walker extends CharacterBody3D:
	var direction:=Vector3.ZERO
	func _ready() -> void:
		floor_snap_length=.35
		var collision:=CollisionShape3D.new()
		var capsule:=CapsuleShape3D.new()
		capsule.radius=.28; capsule.height=1.85
		collision.shape=capsule
		collision.position.y=.95
		add_child(collision)
	func _physics_process(delta: float) -> void:
		velocity.x=direction.x*9
		velocity.z=direction.z*9
		if not is_on_floor(): velocity.y-=22*delta
		elif velocity.y<0: velocity.y=0
		move_and_slide()
var scene: Node3D
var exterior: Node3D
var hall: Node3D
var support: StaticBody3D
var actor: Walker
var checks:=0
var failures:=0

func _initialize() -> void:
	Engine.physics_ticks_per_second=60
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)

func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame

func settle(at: Vector3) -> void:
	actor.global_position=at+Vector3.UP*.03
	actor.velocity=Vector3.ZERO; actor.direction=Vector3.ZERO
	await frames(25)

func walk_to(point: Vector3) -> bool:
	for i in range(1200):
		var delta:=point-actor.global_position
		delta.y=0
		if delta.length()<.2:
			actor.direction=Vector3.ZERO
			await frames(3)
			return actor.is_on_floor() and absf(actor.global_position.y-point.y)<.2
		actor.direction=delta.normalized()
		await frames(1)
	actor.direction=Vector3.ZERO
	return false

func floor_height(at: Vector3) -> float:
	var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.3,at-Vector3.UP*.8,1,[actor.get_rid()])
	var hit:=scene.get_world_3d().direct_space_state.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else -INF

func clear(at: Vector3) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=actor.get_child(0).shape
	query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.95)
	query.collision_mask=1; query.exclude=[actor.get_rid()]
	return scene.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func captures() -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	DisplayServer.window_set_size(Vector2i(1280,800))
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.003,.005,.014)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.15,.2,.3)
	environment.environment.ambient_light_energy=.5
	scene.add_child(environment)
	var camera:=Camera3D.new()
	camera.fov=75; camera.far=450
	scene.add_child(camera); camera.current=true
	for spec: Array in [["exterior",exterior,Vector3(16,10,22),Vector3(0,3.8,0)],["hall",hall,Vector3(30,7,61),Vector3(-1,15,-26)]]:
		camera.global_position=spec[1].to_global(spec[2])
		camera.look_at(spec[1].to_global(spec[3]))
		await process_frame; await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/glyphic_wonders_"+spec[0]+".png")
		print("WONDERS CAPTURE: ",spec[0])

func run() -> void:
	scene=Node3D.new(); root.add_child(scene)
	exterior=Exterior.new(); scene.add_child(exterior)
	var sidewalk:=Chunk.new(); scene.add_child(sidewalk)
	sidewalk.box(exterior.to_global(Vector3(-6,-.12,0)),Vector3(2,.24,60),"ExistingSidewalk",Color.CYAN)
	sidewalk.commit()
	hall=Hall.new(); hall.position=Vector3(400,0,0); scene.add_child(hall)
	support=Hall.create_support(); support.position=hall.position+Vector3(0,0,500); scene.add_child(support)
	actor=Walker.new(); scene.add_child(actor)
	await frames(3)
	check(Regions.grid_at(exterior.global_position)==Vector2i(-7,38),"Small storefront occupies LAT038N LON007W")
	check(Exterior.reserves_plot(Vector3(-96,0,-608)) and not Exterior.reserves_plot(Vector3(-32,0,-608)),"Only the relevant generated scenery lot is reserved before construction")
	check(Hall.SIZE.x>Exterior.SIZE.x*8 and Hall.SIZE.z>Exterior.SIZE.z*10 and Hall.SIZE.y>Exterior.SIZE.y*7,"The instanced hall is dramatically larger than its modest storefront")
	var title:=false
	for label: Label3D in exterior.find_children("*","Label3D",true,false): title=title or label.text=="GLYPHIC WONDERS"
	check(title and exterior.entrance_anchor.position.z>Exterior.SIZE.z*.5 and clear(exterior.arrival_anchor.global_position),"Oversized named sign and obvious south-facing door have an unobstructed outside arrival")
	await settle(exterior.arrival_anchor.global_position)
	check(await walk_to(exterior.to_global(Vector3(0,Exterior.GROUND+.05,2))),"A full standing capsule walks through the open storefront door")
	check(await walk_to(exterior.arrival_anchor.global_position),"The same entrance returns smoothly to the storefront frontage")
	await settle(exterior.to_global(Vector3(-6,.05,-22)))
	check(await walk_to(exterior.to_global(Vector3(-6,.05,22))),"The original west-side civilian sidewalk remains clear along the entire storefront lot")
	check(hall.pedestals.size()==12 and hall.counter_points.size()==3,"Twelve spaced display surfaces and three permanent counter service anchors are exposed")
	var separated:=true
	for i in range(hall.pedestals.size()):
		for j in range(i): separated=separated and hall.pedestals[i].position.distance_to(hall.pedestals[j].position)>=15
	check(separated,"Merchandise displays retain at least15meters of separation and a broad central aisle")
	await settle(hall.spawn_anchor.global_position)
	check(await walk_to(hall.to_global(Vector3(0,Hall.FLOOR+.05,-28))),"The entire monumental central walkway is physically traversable")
	var accessible:=true
	for marker: Marker3D in hall.counter_points:
		var point:=hall.to_global(Vector3(marker.position.x,Hall.FLOOR+.05,marker.position.z))
		accessible=accessible and clear(point) and marker.global_position.distance_to(hall.merchant_anchor.global_position)<5
	check(accessible and clear(hall.merchant_anchor.global_position+Vector3.UP*.05),"Every counter interaction is within5meters of the merchant with standing space on both sides")
	var visible_shapes: Array=hall.structure.body.get_children()
	var dormant_shapes: Array=support.get_children()
	var parity:=visible_shapes.size()==dormant_shapes.size()
	for i in range(visible_shapes.size()): parity=parity and visible_shapes[i].transform==dormant_shapes[i].transform and visible_shapes[i].shape==dormant_shapes[i].shape
	check(parity and dormant_shapes.size()==Hall.collision_layout().size(),"Rendered and collision-only interiors share every floor, column, counter and pedestal surface exactly")
	check(support.find_children("*","GeometryInstance3D",true,false).is_empty(),"Dormant support allocates no meshes, labels, item models or lights")
	var tops:=true
	for marker: Marker3D in hall.pedestals:
		tops=tops and absf(floor_height(marker.global_position)-Hall.PEDESTAL_TOP)<.01 and absf(floor_height(marker.global_position+Vector3(0,0,500))-Hall.PEDESTAL_TOP)<.01
	check(tops,"All twelve merchandise tops support dropped objects in both loaded and dormant collision layouts")
	var saved:=hall.to_global(Vector3(20,Hall.PEDESTAL_TOP+.05,24))
	check(hall.resolve_saved_position({"position":[saved.x,saved.y,saved.z]},actor).distance_to(saved)<.01,"A pedestal-supported checkpoint preserves its exact furniture elevation")
	var column:=hall.to_global(Vector3(37,.17,24))
	check(hall.resolve_saved_position({"position":[column.x,column.y,column.z]},actor)==hall.spawn_anchor.global_position and hall.resolve_saved_position({"position":[INF,0,0]},actor)==hall.spawn_anchor.global_position,"Obstructed or nonfinite saved positions fall back to the safe arrival")
	var aerial:=hall.to_global(Vector3(0,20,10))
	check(hall.resolve_saved_position({"position":[aerial.x,aerial.y,aerial.z]},actor)==aerial,"Clear aerial positions remain legal for unrestricted Sky Jump movement")
	hall.structure.body.collision_layer=0
	support.position=hall.position
	await frames(2)
	check(hall.resolve_saved_position({"position":[saved.x,saved.y,saved.z]},actor).distance_to(saved)<.01 and absf(floor_height(saved)-Hall.PEDESTAL_TOP)<.01,"Cold support survives the exact loaded-to-dormant handoff without losing a pedestal checkpoint")
	var names_clear:=true
	for node: Node in hall.find_children("*","Node",true,false): names_clear=names_clear and not "metatron" in String(node.name).to_lower()
	check(names_clear and hall.ornament_motifs==[&"open_arches",&"rings",&"infinity"],"Ornament contracts contain only non-revealing arches, rings and infinity calligraphy")
	check(hall.find_children("*","MeshInstance3D",true,false).size()==1 and hall.structure.mesh_instance.mesh.get_surface_count()==2 and exterior.structure.mesh_instance.mesh.get_surface_count()==2,"Both architectural environments each use one immutable two-surface batch")
	check(not paused,"Architecture and movement checks keep the world simulation running")
	await captures()
	scene.free()
	print("Glyphic Wonders architecture: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
