extends SceneTree
const Shell=preload("res://scripts/building_shell.gd")
const Chunk=preload("res://scripts/world_chunk.gd")
const Neon=preload("res://scripts/neon.gd")
class Walker extends CharacterBody3D:
	var destination:=Vector3.ZERO
	var walking:=false
	func _ready() -> void:
		floor_snap_length=.35; floor_max_angle=deg_to_rad(48); max_slides=12
		collision_layer=2; collision_mask=1
		var collider:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new()
		capsule.height=1.85; capsule.radius=.27
		collider.shape=capsule; collider.position.y=.95; add_child(collider)
	func _physics_process(delta: float) -> void:
		var horizontal:=Vector3(destination.x-global_position.x,0,destination.z-global_position.z)
		var motion:=horizontal.normalized()*minf(4.2,horizontal.length()/delta) if walking else Vector3.ZERO
		velocity.x=motion.x; velocity.z=motion.z
		if not is_on_floor(): velocity.y-=22*delta
		else: velocity.y=minf(0,velocity.y)
		move_and_slide()
var world: Node3D
var shell: Node3D
var walker: Walker
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func ray(a: Vector3,b: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
func walk(target: Vector3) -> bool:
	walker.destination=target; walker.walking=true
	for i in range(ceili(walker.global_position.distance_to(target)/4.2*Engine.physics_ticks_per_second)+180):
		shell.set_nearby(true,shell.to_local(walker.global_position).y)
		await frames(1)
		if Vector2(walker.global_position.x-target.x,walker.global_position.z-target.z).length()<.06:
			walker.walking=false
			await frames(3)
			return absf(walker.global_position.y-target.y)<.18
	print("WALK STUCK ",walker.global_position," -> ",target)
	for i in range(walker.get_slide_collision_count()):
		var contact:=walker.get_slide_collision(i)
		print("COLLISION ",contact.get_collider().get_path()," normal=",contact.get_normal()," point=",contact.get_position())
	walker.walking=false
	return false
func capture(from: Vector3,focus: Vector3,path: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera:=Camera3D.new(); world.add_child(camera)
	camera.position=from; camera.look_at(focus); camera.make_current(); camera.fov=70
	for i in range(20): await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path)==OK,"Native shell capture saved "+path)
	camera.queue_free(); await frames()
func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Building shell watchdog"); quit(2))
	root.size=Vector2i(1280,720); root.content_scale_size=Vector2i(1280,720)
	world=Node3D.new(); root.add_child(world)
	Neon.block(world,Vector3(0,-.3,0),Vector3(80,.6,80))
	shell=Shell.new(); world.add_child(shell)
	shell.configure(Shell.stable_id(Vector3.ZERO),Vector3(18,14,24))
	var exterior:=Chunk.new(); shell.add_child(exterior); shell.bake_exterior(exterior,Vector3.ZERO); exterior.commit()
	check(not shell.manual_review and shell.floor_count==4 and shell.placement_layout().ceiling_height>=3,"A normal tower has four safely spaced accessible storeys")
	check(shell._loaded.is_empty() and shell.get_child_count()==1,"Distant shell construction does not instantiate interiors or furnishing roots")
	check(Shell.stable_id(Vector3(32,0,-96))==Shell.stable_id(Vector3(32,8,-96)) and Shell.stable_id(Vector3(33,0,-96))!=Shell.stable_id(Vector3(32,0,-96)),"Stable physical identity uses position/context rather than census order or terrain height")
	await frames(3)
	check(ray(Vector3(0,1,14),Vector3(0,1,10)).is_empty(),"The visible entrance is carved through the actual front-wall collider")
	check(not ray(Vector3(3,1,14),Vector3(3,1,10)).is_empty() and not ray(Vector3(0,15,0),Vector3(0,13,0)).is_empty(),"Walls and the original-height roof retain solid collision")
	shell.set_accessible(false); await frames()
	check(not ray(Vector3(0,1,14),Vector3(0,1,10)).is_empty(),"Private access closes a real opaque physical doorway")
	shell.set_accessible(true); await frames()
	check(ray(Vector3(0,1,14),Vector3(0,1,10)).is_empty(),"Authority can restore a clear exit without changing the shell")
	check(shell.ensure_local_contents_loaded(0) and shell._loaded.size()==3,"Approaching the ground floor loads only the adjacent indexed storeys")
	var saved_contents:=Node3D.new(); saved_contents.name="PersistentFixture"; shell.furniture_parent().add_child(saved_contents)
	walker=Walker.new(); world.add_child(walker); walker.position=Vector3(0,.04,14)
	await frames(5)
	check(await walk(Vector3(0,.04,9)) and await walk(Vector3(0,.04,0)),"A player-sized capsule physically enters the hollow room from the street")
	var layout: Dictionary=shell.placement_layout()
	var back: float=layout.stair_min[1]+1.5
	var front: float=layout.stair_max[1]-1.5
	var well_min: float=layout.stair_min[0]+.12
	var route: Array[Vector3]=[Vector3(0,.04,back-.65),Vector3(well_min+.8,.04,back-.65),Vector3(well_min+.8,.04,back),Vector3(well_min+.8,3.54,front),Vector3(well_min+.8,3.54,front+.65),Vector3(well_min+2.4,3.54,front+.65),Vector3(well_min+2.4,3.54,front),Vector3(well_min+2.4,7.04,back),Vector3(well_min+2.4,7.04,back-.65),Vector3(0,7.04,back-.65),Vector3(0,7.04,0)]
	var climbed:=true
	for point: Vector3 in route:
		if not await walk(point): climbed=false; break
	check(climbed and walker.position.y>6.8,"Alternating stair lanes and protected landings reach two upper floors without jumping or head collisions")
	if climbed:
		route.reverse()
		var descended:=true
		for point: Vector3 in route:
			if not await walk(point): descended=false; break
		check(descended and await walk(Vector3(0,.04,14)),"The same protected route descends and exits to the street")
	await capture(Vector3(0,2.1,15.8),Vector3(2,2.4,0),"res://.godot/building-shell-entry.png")
	await capture(Vector3(7.9,4.9,-2.7),Vector3(7.9,5.2,-8),"res://.godot/building-shell-stairs.png")
	shell.set_nearby(false)
	check(shell._loaded.is_empty() and is_instance_valid(saved_contents) and saved_contents.get_parent()==shell.furniture_parent(),"Unloading detailed floors preserves the authority-owned furnishing parent and its contents")
	var tall:=Shell.new(); world.add_child(tall); tall.configure("building/tall",Vector3(30,704,32))
	check(tall.floor_count==220 and tall.ensure_local_contents_loaded(110) and tall._loaded.size()<=5,"A 220-floor tower materializes a bounded five-storey window")
	tall.ensure_local_contents_loaded(219)
	check(tall._loaded.size()==3 and tall._loaded.has(219) and not tall._loaded.has(110),"Vertical streaming releases old floor batches while keeping the top roof approach safe")
	var small:=Shell.new(); world.add_child(small); small.configure("building/unsuitable",Vector3(4,2.5,4))
	check(small.manual_review and not small.ensure_local_contents_loaded(),"Unsafe footprints are explicitly flagged for manual review instead of generating broken rooms")
	var narrow:=Shell.new(); world.add_child(narrow); narrow.configure("building/narrow",Vector3(8,20,8))
	check(not narrow.manual_review and narrow.floor_count==1 and narrow.placement_layout().upper_manual_review,"Narrow towers offer a safe ground room while marking unsupported upper access for review")
	world.queue_free(); await frames(3)
	print("Building shell verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
