extends SceneTree
const Interior = preload("res://scripts/pyramid_interior.gd")
const Floor = preload("res://scripts/pyramid_floor.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Session = preload("res://scripts/inventory_session.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var interior: Node3D
var controls: Intent
var checks := 0
var failures := 0
var hz := 60
var walk_all := true
var travelled := 0.0

func check(ok: bool, message: String) -> void:
	checks+=1
	if ok: print("PASS: ",message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
		if arg=="--geometry-only": walk_all=false
	Engine.physics_ticks_per_second=hz
	call_deferred("run")

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func place(point: Vector3) -> void:
	p.global_position=point
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	p.unstuck.reset_history()
	p.visual.rebase_after_phase()
	await frames(8)

func drive(point: Vector3) -> bool:
	var initial: Vector3=p.global_position
	var budget:=ceili((initial.distance_to(point)/2.5+8)*hz)
	for i in range(budget):
		var delta:=point-p.global_position
		var flat:=Vector2(delta.x,delta.z)
		if flat.length()<.32 and absf(delta.y)<.7:
			controls.move=Vector2.ZERO
			travelled+=initial.distance_to(p.global_position)
			return true
		controls.move=flat.normalized()*clampf(flat.length()/4,.1,1)
		controls.sprint=true
		await frames(1)
	controls.move=Vector2.ZERO
	print("WALK BLOCKED target=",point," at=",p.global_position," floor=",interior.floor_at(p.global_position))
	if p.get_slide_collision_count():
		var collision:=p.get_slide_collision(0)
		print("CONTACT ",collision.get_collider().get_path()," shape ",collision.get_collider_shape()," normal ",collision.get_normal())
	return false

func hub_path(destination: Vector2i) -> bool:
	var origin:=Vector2i(4,0)
	var distance:=INF
	for cell: Vector2i in interior.open_cells:
		var next:=Interior.cell_position(cell.x,cell.y).distance_to(p.global_position)
		if next<distance:
			distance=next
			origin=cell
	var previous: Dictionary={origin:origin}
	var queue: Array[Vector2i]=[origin]
	while not queue.is_empty():
		var cell: Vector2i=queue.pop_front()
		for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:=cell+step
			if not Interior.open_at(next.x,next.y) or previous.has(next): continue
			previous[next]=cell
			queue.append(next)
	var path: Array[Vector2i]=[destination]
	while path[-1]!=origin: path.append(previous[path[-1]])
	path.reverse()
	var last:=origin
	for cell in path:
		if cell.x!=last.x:
			# The original hub's papyrus pillars sit on horizontal cell-centre
			# lines. Walk around them within the eight-metre passage.
			if not await drive(Interior.cell_position(last.x,last.y)+Vector3(0,.05,1.4)): return false
			if not await drive(Interior.cell_position(cell.x,cell.y)+Vector3(0,.05,1.4)): return false
		if not await drive(Interior.cell_position(cell.x,cell.y)+Vector3.UP*.05): return false
		last=cell
	return true

func connect_on_floor(target: Vector3) -> bool:
	var at: Vector3=p.global_position
	var id: StringName=interior.floor_at(at)
	var approach_z:=at.z
	var depart_z:=target.z
	if id==&"U7":
		var data: Dictionary=interior.floors[id].definition
		var half: float=Floor.half_at(data.ceiling)-1.5
		# Pass the ends of the processional screens before crossing their x.
		if absf(at.x)>half*.7: approach_z=Floor.CENTER.z+half*.8
		if absf(target.x)>half*.7: depart_z=Floor.CENTER.z+half*.8
	if not await drive(Vector3(at.x,target.y,approach_z)): return false
	if not await drive(Vector3(0,target.y,approach_z)): return false
	if not await drive(Vector3(0,target.y,depart_z)): return false
	if not await drive(Vector3(target.x,target.y,depart_z)): return false
	return await drive(target)

func traverse(stair: Node3D, up: bool) -> bool:
	var route: Array=stair.route.duplicate()
	if not up: route.reverse()
	if interior.floor_at(p.global_position)==&"hub":
		if not await hub_path(Vector2i(7 if stair.center_x>0 else 1,7)): return false
		if not await drive(route[0]): return false
	elif not await connect_on_floor(route[0]): return false
	for point: Vector3 in route:
		if not await drive(point): return false
	await frames(3)
	check(interior.floor_at(p.global_position)==(stair.upper_id if up else stair.lower_id),"Walk "+String(stair.lower_id)+" ↔ "+String(stair.upper_id)+(" ascending" if up else " descending"))
	return true

func capture(label: String, point: Vector3, offset: Vector3) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await place(point)
	interior.update_visibility(point,true)
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.global_position=point+offset
	camera.look_at(point+Vector3.UP*2)
	camera.far=700
	camera.current=true
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/pyramid_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current=true

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.dungeon_enemies_enabled=false
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	p=world.player
	p.visual.retrieval.enabled=false
	controls=Intent.new()
	root.add_child(controls)
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	controls.interaction_context=world.inventory_session
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await frames(10)
	await place(world.wider_world.pyramid.to_global(Vector3(65.5,.15,0)))
	check(world.dungeon_travel.interact(),"Existing physical doorway activates the same environment transition")
	while world.dungeon_travel.busy: await frames(1)
	interior=world.dungeon_travel.interior
	world.camera_rig.yaw=0
	check(interior.floors.size()==17 and interior.stairs.size()==16,"Exactly sixteen numbered floors and one unnumbered entry hub have sixteen physical connections")
	var previous_half:=INF
	for data: Dictionary in interior.definitions:
		var node: Node3D=interior.floors[data.id]
		var width: float=Floor.half_at(data.y)
		check(width<previous_half,"Continuous pyramid narrows upwards at "+String(data.id))
		previous_half=width
		var valid:=true
		for volume: Dictionary in node.batch.volumes:
			for vertex: Vector3 in volume.vertices:
				var point: Vector3=volume.transform*vertex
				valid=valid and maxf(absf(point.x),absf(point.z-Floor.CENTER.z))<=Floor.half_at(point.y)+.02
		check(valid and node.content.get_child_count()==3,"Sloping boundary and future content sockets are valid on "+String(data.id))
		var anchor: Vector3=node.spawn_anchor.global_position
		var query:=PhysicsRayQueryParameters3D.create(anchor+Vector3.UP,anchor-Vector3.UP,1,[p.get_rid()])
		check(not interior.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"Safe supported arrival exists on "+String(data.id))
	check(interior.stairs[7].center_x<0 and interior.stairs[8].center_x>0,"Hub descent occupies the back left; ascent occupies the back right")
	for i in range(1,interior.stairs.size()):
		var incoming: Node3D=interior.stairs[i-1]
		var outgoing: Node3D=interior.stairs[i]
		if outgoing.lower_id==&"hub": continue
		check(incoming.center_x*outgoing.center_x<0 and not incoming.footprint().intersects(outgoing.footprint()),"Opposing stairwells require crossing "+String(outgoing.lower_id))
	var divider_ok:=true
	for z: float in [-53,-59,-64,-75,-84]:
		for height: float in [.15,1,4,7.5]:
			var hit:=interior.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-2,height,z),Vector3(2,height,z),1,[p.get_rid()]))
			divider_ok=divider_ok and not hit.is_empty() and hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape)).name=="RearVestibuleDivider"
	check(divider_ok,"Full-height rear divider seals the former shortcut, including the empty cell behind the labyrinth")
	check(interior.resolve_saved_position({"floor_id":"hub","position":[0,.05,-70]},p)==interior.spawn_anchor.global_position,"A legacy position inside the new divider safely restores at the hub entrance")
	var stair_bounds:=true
	for stair in interior.stairs:
		for volume: Dictionary in stair.batch.volumes:
			for vertex: Vector3 in volume.vertices:
				var point: Vector3=volume.transform*vertex
				stair_bounds=stair_bounds and maxf(absf(point.x),absf(point.z-Floor.CENTER.z))<=Floor.half_at(point.y)+.02
	check(stair_bounds,"Every stair, landing and rail fits inside the same continuous pyramid profile")
	var arena: Node3D=interior.floors[&"B8"]
	check(Floor.half_at(arena.definition.y)*2>350 and arena.definition.ceiling-arena.definition.y==32,"B8 reserves a broad 350+ m arena with 32 m of headroom")
	check(Floor.half_at(interior.floors[&"U8"].definition.y)*2<30,"U8 is the compact summit chamber")
	if walk_all:
		for i in range(8,16):
			if not await traverse(interior.stairs[i],true):
				check(false,"Continuous ground route to U8")
				finish()
				return
		for i in range(15,7,-1):
			if not await traverse(interior.stairs[i],false):
				check(false,"Return ground route from U8")
				finish()
				return
		for i in range(7,-1,-1):
			if not await traverse(interior.stairs[i],false):
				check(false,"Continuous ground route to B8")
				finish()
				return
		for i in range(8):
			if not await traverse(interior.stairs[i],true):
				check(false,"Return ground route from B8")
				finish()
				return
		check(await hub_path(Vector2i(7,7)),"The two hub stair approaches remain connected through the actual labyrinth")
		check(travelled>1000,"Real controller traversal covers both branches and returns without jumping or teleporting")
	await capture("upper_gallery",interior.floors[&"U3"].spawn_anchor.global_position,Vector3(10,5,8))
	await capture("summit",interior.floors[&"U8"].spawn_anchor.global_position,Vector3(-8,4,7))
	await capture("deep_arena",arena.spawn_anchor.global_position,Vector3(40,14,32))
	await capture("hub_divider",Vector3(3,.05,-70),Vector3(14,4,7))
	await place(interior.floors[&"B1"].spawn_anchor.global_position)
	check(p.global_position.y< -12 and p.is_on_floor(),"Basement floors are supported and do not trigger the outdoor void-respawn threshold")
	for i in range(12):
		controls.jump_requested=true
		await frames(4)
	check(p.air_step_count>=8 and p.global_position.y< -1.5,"Unlimited Sky Jump remains active while the solid floor overhead contains the player")
	controls.move=Vector2.ZERO
	var checkpoint:="user://tests/pyramid_architecture.json"
	var saved_point: Vector3=interior.floors[&"B6"].spawn_anchor.global_position+Vector3(3,0,0)
	await place(saved_point)
	check(world.inventory_session.save_checkpoint(checkpoint,true),"Deep-floor position and floor identity save through the existing checkpoint")
	var snapshot: Dictionary=Store.load_snapshot(checkpoint)
	check(snapshot.location_state.floor_id=="B6" and snapshot.location_state.position[1]< -90,"Checkpoint records the actual B6 location")
	await place(interior.spawn_anchor.global_position)
	check(world.inventory_session.load_checkpoint(checkpoint),"Saved deep-floor checkpoint reloads atomically")
	await frames(6)
	check(interior.floor_at(p.global_position)==&"B6" and p.global_position.distance_to(saved_point)<.2,"Reload restores the saved floor and supported position instead of the entry")
	var missing: Dictionary=snapshot.location_state.duplicate()
	missing.erase("floor_id")
	check(interior.resolve_saved_position(missing,p).distance_to(saved_point)<.2,"A position without a floor ID infers the correct storey")
	var invalid: Dictionary={"floor_id":"B4","position":[900000,-64,900000]}
	check(interior.resolve_saved_position(invalid,p)==interior.floors[&"B4"].spawn_anchor.global_position,"An outdated or invalid position falls back to that floor's safe anchor")
	for floor_id: StringName in [&"U8",&"B8"]:
		await place(interior.floors[floor_id].spawn_anchor.global_position)
		interior.update_visibility(p.global_position,true)
		check(interior.visible_floors.size()<=3 and interior.floors[&"hub"].visible==false,"Distant floors stay hidden at "+String(floor_id)+" while collision remains loaded")
		world.loot.death_drop_probability=1
		p.weapon_combat.receive_environment_damage(10000)
		await frames(4)
		check(world.dungeon_travel.inside() and p.global_position.distance_to(interior.spawn_anchor.global_position)<.2,"Death on "+String(floor_id)+" preserves the existing front-door respawn")
	check(world.loot.markers.for_owner("local").size()==2,"Upper and lower deaths retain both recoverable item identities")
	var losses: Array=world.loot.markers.for_owner("local")
	var newest: Node3D=world.loot.pickups[losses[-1].pickup_id]
	check(newest.get_parent()==interior.floors[&"B8"].content,"Deep drops inherit their floor's visibility without changing world identity")
	await place(newest.global_position+Vector3(0,.05,1))
	check(world.inventory_session.save_checkpoint(checkpoint+".losses",true),"Checkpoint preserves drops on two different floors")
	check(world.loot.request_pickup(p.inventory,newest),"The newest B8 loss remains physically recoverable")
	await frames(4)
	check(world.loot.markers.for_owner("local").size()==1 and world.inventory_session.loss_hint.text.contains("U8"),"Recovery guidance advances from B8 to the remaining U8 loss")
	check(world.inventory_session.load_checkpoint(checkpoint+".losses"),"A cross-floor drop checkpoint restores both item identities")
	await frames(4)
	check(world.loot.markers.for_owner("local").size()==2 and interior.floor_at(p.global_position)==&"B8","Cross-floor drops and the saved B8 position survive reload together")
	check(world.inventory_session.load_checkpoint(checkpoint),"Checkpoint still reloads after deaths on both branches")
	await frames(4)
	check(interior.floor_at(p.global_position)==&"B6","Deep-floor reload remains valid after drop creation")
	var startup:=func(node: Node):
		if node.get_script()==Session:
			node.ready.connect(func():
				node.save_path=checkpoint
				node.persistence_enabled=true
				node._begin_initial_checkpoint_load())
	world.queue_free()
	controls.queue_free()
	await frames(4)
	node_added.connect(startup)
	world=load("res://scenes/main.tscn").instantiate()
	world.dungeon_enemies_enabled=false
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	node_added.disconnect(startup)
	await frames(15)
	p=world.player
	interior=world.dungeon_travel.interior
	check(world.inventory_session._checkpoint_usable and world.dungeon_travel.inside() and interior.floor_at(p.global_position)==&"B6" and p.is_on_floor() and p.global_position.distance_to(saved_point)<.2,"Fresh game startup restores B6 and its real saved position")
	world.inventory_session.persistence_enabled=false
	finish()

func finish() -> void:
	world.queue_free()
	print("Pyramid architecture: ",checks," checks @",hz," Hz, ",failures," failures; walked ",snappedf(travelled,.1)," m; full traversal=",walk_all)
	quit(1 if failures else 0)
