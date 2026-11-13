extends SceneTree
## Real player capsule, attachment cleanup and coasting vehicles at any speed.
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void:
		if not gameplay_enabled: move = Vector2.ZERO
class Life extends Node3D:
	var actor: CharacterBody3D
	func pose_interval(_point: Vector3) -> float: return INF
class Observer extends Node:
	signal finished
	func _process(_delta: float) -> void: finished.emit()

var world: Node3D
var p: CharacterBody3D
var actions: Node3D
var controls: Intent
var life: Life
var observer: Observer
var vehicle: CharacterBody3D
var barriers: Array[Node3D] = []
var home := Vector3(1700,20,1700)
var hz := 60
var checks := 0
var failures := 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await observer.finished

func box(at: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	body.position = at
	return body

func clear_player() -> bool:
	var query: PhysicsShapeQueryParameters3D = p.unstuck.query_at(p.global_position)
	query.collision_mask = 13
	return p.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func prepare(kind: String,yaw: float = 0) -> bool:
	if actions.attached(): actions.detach()
	if is_instance_valid(vehicle): vehicle.queue_free()
	for barrier: Node3D in barriers: barrier.queue_free()
	barriers.clear()
	controls.move = Vector2.ZERO
	await frames(2)
	vehicle = Vehicle.new()
	vehicle.record = {"id":99123,"kind":kind,"point":home+Vector3.UP*.12,"yaw":yaw,"traffic":false,"taken":true,"color":Color.CYAN,"driver":{"tint":Color.CYAN,"body_profile":&"male"}}
	vehicle.life = life
	life.add_child(vehicle)
	p.position = vehicle.to_global(Vector3(2,.1,0))
	p.velocity = Vector3.ZERO
	await frames(ceili(hz*.2))
	var boarded: bool = actions.board(vehicle)
	vehicle.set_physics_process(false)
	return boarded

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	observer = Observer.new()
	observer.process_priority = 10000
	root.add_child(observer)
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
	world.inventory_session.world_actions = actions
	controls.interaction_context = world.inventory_session
	world.camera_rig.controls = controls
	life = Life.new()
	life.actor = p
	world.add_child(life)
	box(home-Vector3.UP,Vector3(128,2,128))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(3)
	var layer: int = p.collision_layer
	var mask: int = p.collision_mask
	var capsule: Shape3D = p.get_child(0).shape
	var pace := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	for kind: String in ["car","truck","motorcycle"]:
		for speed_index in range(4):
			var yaw: float = [0,PI*.5,-PI*.75,PI][speed_index]
			check(await prepare(kind,yaw),kind+" boards for exit speed case "+str(speed_index))
			var speed: float = [0,3,vehicle.top_speed,-6][speed_index]
			vehicle.signed_speed = speed
			vehicle.velocity = vehicle.global_basis.z*speed
			actions.apply_pose()
			var carried: Vector3 = vehicle.velocity
			var before: Vector3 = vehicle.global_position
			check(actions.leave() and not actions.attached() and vehicle.player_driver==null and clear_player(),kind+" exits into clear capsule space at speed "+str(speed))
			check(p.velocity.is_equal_approx(carried) and is_equal_approx(vehicle.signed_speed,speed),kind+" preserves player and vehicle momentum on exit")
			check(p.collision_layer==layer and p.collision_mask==mask and actions._attachment_pose.is_empty() and not p.camera_rig._vehicle_mode and is_equal_approx(p.camera_rig.arm.spring_length,p.camera_rig.get_follow_distance()),kind+" restores collision, camera and mounted pose state")
			controls.move = Vector2.ZERO
			vehicle.set_physics_process(true)
			await frames(2)
			if absf(speed)>2:
				var expected_speed := maxf(0,absf(speed)-16.0*2/hz)
				check((vehicle.global_position-before).dot(carried.normalized())>0.02 and absf(vehicle.signed_speed)>0 and absf(absf(vehicle.signed_speed)-expected_speed)<.05,kind+" keeps coasting with its existing time-based braking after the driver leaves")
			check(p.controls.gameplay_enabled and not paused,kind+" leaves controls and world simulation active")
		check(await prepare(kind,PI*.5),kind+" boards for an obstructed door")
		barriers.append(box(vehicle.to_global(Vector3(1.9,1.5,vehicle.seat_z)),Vector3(3,3,.65)))
		await frames(2)
		vehicle.signed_speed = vehicle.top_speed
		vehicle.velocity = vehicle.global_basis.z*vehicle.signed_speed
		var right: Vector3 = vehicle.global_basis.x
		var origin: Vector3 = vehicle.global_position
		check(actions.leave() and (p.global_position-origin).dot(right)<-1.4 and clear_player(),kind+" selects the opposite door when the first door is blocked")
		check(await prepare(kind),kind+" boards before becoming airborne")
		vehicle.position += Vector3.UP*12
		vehicle.velocity = vehicle.global_basis.z*vehicle.top_speed+Vector3.UP*4
		vehicle.signed_speed = vehicle.top_speed
		# Refresh CharacterBody contact state after leaving the ground.
		vehicle.move_and_slide()
		actions.anchor()
		var airborne_origin: Vector3 = vehicle.global_position
		var airborne_velocity: Vector3 = vehicle.velocity
		check(not vehicle.is_on_floor() and actions.leave() and absf(p.global_position.y-airborne_origin.y)<.25 and clear_player(),kind+" exits airborne beside the cabin without snapping to the floor")
		check(p.velocity.is_equal_approx(airborne_velocity),kind+" inherits upward and forward airborne momentum")
		controls.move = Vector2.UP
		await frames(2)
		check(p.velocity.y>0 and not p.is_on_floor() and p.controls.gameplay_enabled,kind+" resumes normal air steering after ejection")
	check(await prepare("car"),"Car boards before the fully blocked exit case")
	for entry: Vector3 in [Vector3(1.45,2,0),Vector3(-1.45,2,0),Vector3(0,2,2.8),Vector3(0,2,-2.8)]:
		var side := absf(entry.x)>0
		barriers.append(box(vehicle.global_position+entry,Vector3(.3,4,8) if side else Vector3(4,4,.3)))
	await frames(2)
	vehicle.signed_speed = vehicle.top_speed
	vehicle.velocity = vehicle.global_basis.z*vehicle.top_speed
	check(not actions.leave() and actions.attached() and vehicle.player_driver==p,"Solid walls block every swept exit instead of permitting noclip at speed")
	for barrier: Node3D in barriers: barrier.queue_free()
	barriers.clear()
	await frames(2)
	check(actions.leave(),"Clearing the physical exit immediately permits the same moving exit")
	var repeated := true
	for index in range(6):
		repeated = (await prepare("motorcycle",index*.4)) and repeated
		actions.apply_pose()
		vehicle.signed_speed = vehicle.top_speed
		vehicle.velocity = vehicle.global_basis.z*vehicle.top_speed
		repeated = actions.leave() and actions._attachment_pose.is_empty() and repeated
	check(repeated,"Repeated board and high-speed dismount cycles restore the attachment pose")
	check(p.get_child(0).shape==capsule and Vector3(p.walk_speed,p.run_speed,p.boost_speed)==pace and p.health==1000,"Exiting changes no capsule, movement tuning or health")
	if is_instance_valid(vehicle): vehicle.queue_free()
	world.queue_free()
	await process_frame
	print("MOVING VEHICLE EXIT: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
