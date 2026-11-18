extends SceneTree
## Monument scale, exact site, real collision and preserved neighbouring routes.
const Pyramid = preload("res://scripts/pyramid_exterior.gd")
const Regions = preload("res://scripts/world_regions.gd")
const KyrenHome = preload("res://scripts/kyren_homestead.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var pyramid: Node3D
var player: CharacterBody3D
var controls: Intent
var checks := 0
var failures := 0
var hz := 60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,[player.get_rid()]))

func capture(label: String, offset: Vector3, target: Vector3) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.far=1800
	camera.fov=62
	camera.global_position=pyramid.global_position+offset
	camera.look_at(pyramid.global_position+target)
	camera.current=true
	await frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/pyramid_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current=true

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.district_life_enabled=false
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	pyramid=world.wider_world.pyramid
	player=world.player
	player.visual.retrieval.enabled=false
	controls=Intent.new()
	root.add_child(controls)
	player.controls=controls
	world.camera_rig.controls=controls
	world.camera_rig.yaw=0
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await frames(4)
	check(Regions.grid_at(pyramid.global_position)==Vector2i(-5,47),"Pyramid is centred at screenshot grid LAT 047N / LON 005W")
	check(pyramid.global_position.x==-80 and pyramid.global_position.z==-752,"The monument uses the centre of the requested 16-metre grid cell")
	var mass: Dictionary=pyramid.structure.volumes.filter(func(v: Dictionary): return v.kind=="PyramidMass")[0]
	var bounds:=AABB(mass.vertices[0],Vector3.ZERO)
	for vertex: Vector3 in mass.vertices: bounds=bounds.expand(vertex)
	check(bounds.size.is_equal_approx(Vector3(128,82,128)),"The solid pyramid has a life-size 128-metre square base and 82-metre height")
	check(mass.collider.shape is ConvexPolygonShape3D and mass.vertices.size()==5,"Four sloping faces and the base share one convex solid collider")
	check(pyramid.structure.mesh_instance.mesh.get_surface_count()==2 and pyramid.structure.volumes.size()<=12 and pyramid.masonry_segments>2000,"Masonry and entrance geometry use two static mesh surfaces and bounded collision")
	var faces_solid:=true
	for outward: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD]:
		var y: float=32+Pyramid.FLOOR_HEIGHT
		var hit:=ray(pyramid.to_global(outward*80+Vector3.UP*y),pyramid.to_global(Vector3.UP*y))
		faces_solid=faces_solid and not hit.is_empty()
		if not hit.is_empty(): faces_solid=faces_solid and absf(Vector2(pyramid.to_local(hit.position).x,pyramid.to_local(hit.position).z).length()-Pyramid.HALF_BASE*(1-32.0/Pyramid.HEIGHT))<.04
	check(faces_solid,"All four visible sloping faces stop real physics rays at the matching surface")
	var apex:=ray(pyramid.to_global(Vector3(0,100,0)),pyramid.to_global(Vector3(0,70,0)))
	check(not apex.is_empty() and absf(apex.position.y-pyramid.global_position.y-Pyramid.HEIGHT-Pyramid.FLOOR_HEIGHT)<.04,"The apex is physically solid at the full rendered height")
	var pad_clear:=true
	for x: float in [-64,0,64]:
		for z: float in [-64,0,64]:
			pad_clear=pad_clear and absf(Regions.height_at(Pyramid.CENTER.x+x,Pyramid.CENTER.z+z)-pyramid.global_position.y)<.001
	check(pad_clear,"The full pyramid footprint is levelled into matching terrain collision")
	var outside:=Vector3(-256,0,-752)
	check(is_equal_approx(Regions.height_at(outside.x,outside.z),Regions.base_height(outside.x,outside.z)),"Terrain beyond the site retains its original hillside")
	var no_props:=true
	for building: Dictionary in world.wider_world.buildings:
		if absf(building.point.x-Pyramid.CENTER.x)<Pyramid.HALF_BASE+building.size.x*.5 and absf(building.point.z-Pyramid.CENTER.z)<Pyramid.HALF_BASE+building.size.z*.5: no_props=false
	check(no_props,"Procedural houses and farms cannot be buried inside the pyramid footprint")
	var capsule:=CapsuleShape3D.new()
	capsule.height=1.85
	capsule.radius=.27
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.collision_mask=1
	query.exclude=[player.get_rid()]
	var road_clear:=true
	for z in range(-832,-671,8):
		var y:=Regions.surface_at(0,z)
		query.transform=Transform3D(Basis.IDENTITY,Vector3(0,y+1.0,z))
		road_clear=road_clear and world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	check(road_clear,"The country road remains passable alongside the whole monument")
	check(is_equal_approx(Regions.height_at(0,-752),Regions.base_height(0,-752)) and is_equal_approx(Regions.surface_at(0,-864),.15),"The main road's elevation and existing ravine bridge remain unchanged")
	var home: Node3D=world.wider_world.kyren_home
	check(home.global_position.x==48 and home.kyren.state==&"resting" and Regions.grid_at(home.global_position)==Vector2i(3,47) and is_equal_approx(Regions.height_at(48,-752),Regions.base_height(48,-752)),"Kyren's home, tree clearing and resting behaviour remain at their original site")
	check(pyramid.entrance_anchor.position==Pyramid.ENTRANCE and pyramid.arrival_anchor.position==Pyramid.ARRIVAL,"Named exterior entrance/arrival anchors are ready for a future separate dungeon instance")
	var door:=ray(pyramid.to_global(Vector3(70,3.5,0)),pyramid.to_global(Vector3(60,3.5,0)))
	check(not door.is_empty() and absf(pyramid.to_local(door.position).x-64.34)<.02,"The recessed doorway has a physical sealed door rather than a hole into the pyramid solid")
	query.transform=Transform3D(Basis.IDENTITY,pyramid.to_global(Vector3(67.5,1.08,0)))
	check(world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"The entrance vestibule provides actual human-scale clearance")
	player.global_position=pyramid.to_global(Vector3(76,.15,0))
	player.velocity=Vector3.ZERO
	player.fall_damage.reset()
	await frames(hz/3)
	controls.move=Vector2.LEFT
	await frames(hz*4)
	controls.move=Vector2.ZERO
	var at: Vector3=pyramid.to_local(player.global_position)
	check(at.x>64.5 and at.x<65.2 and player.is_on_floor(),"The real player walks up the shallow approach and into the vestibule, stopping at the door")
	await capture("entrance",Vector3(92,10,20),Vector3(64,3,0))
	controls.move=Vector2.RIGHT
	await frames(hz*4)
	controls.move=Vector2.ZERO
	check(pyramid.to_local(player.global_position).x>77 and player.global_position.y>-.1,"Walking back out joins the existing country ground without a gap")
	controls.jump_requested=true
	await frames(8)
	controls.jump_requested=true
	await frames(2)
	check(player.air_step_count>0 and player.velocity.y>0,"Normal jumping and Sky Jump remain unrestricted beside the monument")
	controls.move=Vector2.ZERO
	player.global_position=pyramid.to_global(Vector3(70,.15,20))
	player.velocity=Vector3.ZERO
	player.fall_damage.reset()
	await frames(hz/3)
	check(player.dodge.start(Vector3.LEFT),"Existing phase dodge is available at the pyramid")
	await frames(hz/2)
	check(pyramid.to_local(player.global_position).x>=63.8,"Phase travel respects the pyramid's solid exterior instead of entering the sealed mass")
	player.global_position=pyramid.to_global(Pyramid.ARRIVAL)
	player.velocity=Vector3.ZERO
	await capture("exterior",Vector3(190,105,170),Vector3(0,32,0))
	check(not paused and pyramid.get_process_delta_time()>=0,"The monument and live world require no paused scene or dungeon transition")
	world.queue_free()
	controls.queue_free()
	await process_frame
	print("Pyramid exterior: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
