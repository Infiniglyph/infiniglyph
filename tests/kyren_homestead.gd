extends SceneTree
## Real site placement, walkable house, doubled resident and bounded wind effects.
const Regions = preload("res://scripts/world_regions.gd")
const Home = preload("res://scripts/kyren_homestead.gd")
const Resident = preload("res://scripts/resident_visual.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void: pass
var checks := 0
var failures := 0
var hz := 60
var world: Node3D
var home: Node3D
var actor: CharacterBody3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

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

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/kyren_"+label+".png")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	await frames(10)
	home = world.wider_world.kyren_home
	var kyren: CharacterBody3D = home.kyren
	check(home!=null and Regions.grid_at(home.global_position)==Vector2i(3,47),"Kyren's home occupies screenshot grid LAT 047N / LON 003E")
	check(Regions.grid_at(kyren.global_position)==Vector2i(3,47) and home.tree.global_position.distance_to(kyren.global_position)<2,"Kyren rests under his cherry tree in the same requested cell")
	check(kyren.name=="Kyren" and kyren.state==&"resting" and not kyren.is_in_group("combat_targets") and not is_instance_valid(kyren.encounter),"The homestead can retain a peaceful resting Kyren when encounters are disabled")
	var visual: Node3D = kyren.rest_visual
	var stored: Node3D=kyren.weapon_combat.rig.models[&"kyren_katana"].stowed
	check(stored.get_parent()==visual.sword_anchor and stored.is_visible_in_tree() and not kyren.weapon_combat.rig.models[&"kyren_katana"].right.is_visible_in_tree(),"The actual equipped katana is visibly sheathed beside the resting left hip")
	check(stored.find_child("KyrenSaya",true,false)!=null,"The resting sword has a physical crimson saya around its blade")
	var bottom:=INF
	for mesh: MeshInstance3D in stored.find_children("*","MeshInstance3D",true,false):
		var bounds:=mesh.get_aabb()
		for corner in range(8): bottom=minf(bottom,(mesh.global_transform*bounds.get_endpoint(corner)).y)
	check(bottom>kyren.global_position.y+.05 and stored.global_position.distance_to(kyren.global_position)<1.4,"The seated sword stays at his waist with its tip clear of the ground")
	check(visual.stature==2 and visual.scale==Vector3.ONE*2 and visual.tint==visual.GOLD and visual.rods.mesh==Resident.rod_mesh,"Kyren is the ordinary resident body at exactly twice its size, in gold")
	# Dummy/headless rendering does not retain MultiMesh transform/color buffers.
	if DisplayServer.get_name()!="headless":
		check(is_equal_approx(visual.joints.get_instance_transform(0).basis.get_scale().x*visual.scale.x,.256),"The gold head is twice an ordinary NPC's diameter")
	check(visual.hat.get_parent()==visual.head_anchor and visual.embers.multimesh.instance_count==36 and visual.hat.find_child("CrownMathematics",true,false)==null,"The crimson conical straw hat follows his head and sheds embers without mathematical glyphs")
	check(home.tree.blossoms.multimesh.instance_count==240 and home.tree.petals.multimesh.instance_count==96,"A pink five-petal blossom canopy has a fixed 96-petal falling pool")
	var floor_hits := 0
	for offset: Vector3 in [Vector3(-10,0,-10),Vector3(10,0,-10),Vector3(10,0,10),Vector3(-10,0,10)]:
		var at: Vector3 = home.global_position+offset
		var hit := ray(at+Vector3.UP*2,at-Vector3.UP*2)
		if not hit.is_empty() and absf(hit.position.y-Regions.height_at(at.x,at.z))<.01: floor_hits += 1
	check(floor_hits==4,"The gently leveled clearing is backed by matching terrain collision")
	check(is_equal_approx(Regions.height_at(0,-752),Regions.base_height(0,-752)),"The existing country road retains its terrain height outside the clearing")
	var roof_point: Vector3 = home.to_global(Home.HOUSE_CENTER)
	var roof := ray(roof_point+Vector3.UP*9,roof_point)
	check(not roof.is_empty() and roof.position.y>home.global_position.y+6,"The basic house has a real solid pitched roof")
	var door: Vector3 = home.to_global(home.doorway)
	check(ray(door+Vector3(0,1,1.8),door+Vector3(0,1,-2.0)).is_empty(),"The front doorway is an actual open entrance")
	var wall := ray(door+Vector3(3,1,1.8),door+Vector3(3,1,-2))
	check(not wall.is_empty(),"Physical front walls remain solid on either side of the door")
	var controls := Intent.new()
	root.add_child(controls)
	actor.controls = controls
	world.camera_rig.controls = controls
	world.camera_rig.yaw = 0
	actor.global_position = door+Vector3(0,.08,3.6)
	actor.velocity = Vector3.ZERO
	await frames(hz/3)
	controls.move = Vector2.UP
	await frames(hz*2)
	controls.move = Vector2.ZERO
	check(actor.global_position.z<door.z-1 and actor.global_position.y>home.global_position.y+.15,"The real player can walk up the porch and through the house entrance")
	actor.set_physics_process(false)
	var scarf: Node3D = kyren.scarf
	var stable_length := true
	var bounded := true
	var quadrants: Dictionary = {}
	var before_nodes := home.find_children("*","",true,false).size()
	for i in range(1200):
		scarf.advance(.05)
		var length := 0.0
		for j in range(scarf.SEGMENTS): length += scarf.points[j].distance_to(scarf.points[j+1])
		stable_length = stable_length and absf(length-3)<.001
		bounded = bounded and scarf.points[-1].distance_to(scarf.points[0])<=3.001
		var toward: Vector3 = scarf.points[-1]-scarf.points[0]
		quadrants[Vector2i(int(toward.x>=0),int(toward.z>=0))] = true
	check(stable_length and bounded,"Sixty seconds of scarf motion preserve exactly three metres of cloth without stretching")
	check(quadrants.size()==4,"The red scarf continuously trails through every horizontal wind quadrant")
	check(scarf.to_global(scarf.points[0]).distance_to(visual.scarf_anchor.global_position)<.001,"The flowing scarf remains attached to the doubled resident's neck")
	var petals: Node3D = home.tree.petals
	petals.elapsed = 0
	petals.advance(0)
	var old_petal: Transform3D = petals.multimesh.get_instance_transform(0)
	petals.advance(.5)
	var new_petal: Transform3D = petals.multimesh.get_instance_transform(0)
	if DisplayServer.get_name()!="headless":
		check(new_petal.origin.y<old_petal.origin.y and Vector2(new_petal.origin.x,new_petal.origin.z)!=Vector2(old_petal.origin.x,old_petal.origin.z),"Cherry petals visibly fall and drift sideways in the wind")
	visual.embers.elapsed = 0
	visual.embers.advance(0)
	var old_ember: Transform3D = visual.embers.multimesh.get_instance_transform(0)
	visual.embers.advance(.3)
	if DisplayServer.get_name()!="headless":
		check(visual.embers.multimesh.get_instance_transform(0).origin.y<old_ember.origin.y and visual.embers.multimesh.get_instance_color(0).a>0,"Fiery hat particles fall from the brim with a live fade cycle")
	check(home.find_children("*","",true,false).size()==before_nodes and scarf.cloth.instance_count==24 and scarf.trim.instance_count==48,"Effects reuse their existing mesh pools rather than spawning new nodes")
	# Native review: a normal player beside Kyren establishes his larger proportions.
	actor.global_position = kyren.global_position+Vector3(-2.2,.05,1.2)
	actor.combat.sheathed = true
	actor.weapon_combat.sync_rig()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.far = 1800
	camera.fov = 62
	camera.current = true
	camera.position = home.global_position+Vector3(17,12,23)
	camera.look_at(home.global_position+Vector3(0,3,0))
	await capture("home")
	camera.position = kyren.global_position+Vector3(4,3,5)
	camera.look_at(kyren.global_position+Vector3.UP*1.6)
	await capture("resting")
	for i in range(hz):
		visual.animate(1.0/hz,0,false)
		scarf.advance(1.0/hz)
		petals.advance(1.0/hz)
		visual.embers.advance(1.0/hz)
	await capture("wind")
	check(kyren.state==&"resting" and not paused,"Kyren remains peacefully resting while all decorative motion runs in the live world")
	world.queue_free()
	await process_frame
	print("KYREN HOMESTEAD: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
