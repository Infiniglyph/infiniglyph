extends SceneTree
## Real vehicle bodies on curbs, slopes and unsupported edges.
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
class Actions extends Node:
	func anchor() -> void: pass
class Driver extends CharacterBody3D:
	var controls: Node
	var world_actions: Node
class Life extends Node3D:
	var actor: CharacterBody3D
	func pose_interval(_point: Vector3) -> float: return INF

var scene: Life
var fixtures: Node3D
var driver: Driver
var vehicle: CharacterBody3D
var hz := 60
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func box(at: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = at
	fixtures.add_child(body)
	return body

func reset(kind: String, at: Vector3 = Vector3.ZERO, yaw: float = 0) -> void:
	if is_instance_valid(vehicle): vehicle.queue_free()
	if is_instance_valid(fixtures): fixtures.queue_free()
	await frames(2)
	fixtures = Node3D.new()
	scene.add_child(fixtures)
	box(Vector3(0,-1,0),Vector3(128,2,128))
	vehicle = Vehicle.new()
	vehicle.life = scene
	vehicle.record = {"id":0,"kind":kind,"point":at+Vector3.UP*0.12,"yaw":yaw,"traffic":false,"taken":false,"color":Color.CYAN,"driver":{"tint":Color.CYAN,"body_profile":&"male"}}
	scene.add_child(vehicle)
	vehicle.player_driver = driver
	driver.controls.move = Vector2.ZERO
	await frames(ceili(hz*0.25))

func drive(seconds: float, input: Vector2 = Vector2(0,-0.4)) -> Dictionary:
	driver.controls.move = input
	var low := vehicle.position.y
	var high := low
	var air := 0
	var up := 0.0
	for index in range(ceili(seconds*hz)):
		await frames(1)
		low = minf(low,vehicle.position.y)
		high = maxf(high,vehicle.position.y)
		up = maxf(up,vehicle.velocity.y)
		if not vehicle.is_on_floor(): air += 1
	return {"low":low,"high":high,"air":air,"up":up}

func ramp() -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	# A 30-degree physical hill, with a continuous plateau at its crest.
	var rise := 15*tan(deg_to_rad(30))
	shape.points = PackedVector3Array([
		Vector3(-6,-1,5),Vector3(6,-1,5),Vector3(-6,-1,20),Vector3(6,-1,20),
		Vector3(-6,0,5),Vector3(6,0,5),Vector3(-6,rise,20),Vector3(6,rise,20)])
	collision.shape = shape
	body.add_child(collision)
	fixtures.add_child(body)
	box(Vector3(0,rise*0.5,45),Vector3(12,rise,50))

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	scene = Life.new()
	root.add_child(scene)
	driver = Driver.new()
	driver.controls = load("res://scripts/player_input.gd").new()
	driver.world_actions = Actions.new()
	driver.add_child(driver.controls)
	driver.add_child(driver.world_actions)
	scene.add_child(driver)
	scene.actor = driver
	for kind: String in ["car","motorcycle","truck"]:
		for height: float in [0.05,0.2,0.32]:
			await reset(kind)
			box(Vector3(0,height*0.5,17.5),Vector3(3.4,height,25))
			var journey := await drive(3.0)
			check(vehicle.position.z>12 and vehicle.position.y>height-0.08,kind+" enters a "+str(height)+" m raised parking slab")
			check(journey.high<height+0.02 and vehicle.signed_speed>vehicle.top_speed*0.39,kind+" curb ascent preserves throttle without a launch")
			print("CURB: ",kind," height=",height," position=",vehicle.position," speed=",vehicle.signed_speed)
		await reset(kind,Vector3.ZERO,PI*0.25)
		box(Vector3(0,0.1,17.5),Vector3(64,0.2,25))
		await drive(3)
		check(vehicle.position.z>9 and vehicle.position.y>0.12,kind+" climbs a curb approached diagonally")
		await reset(kind)
		box(Vector3(0,0.1,32.5),Vector3(8,0.2,55))
		vehicle.signed_speed = vehicle.top_speed
		await drive(1,Vector2.UP)
		check(vehicle.position.z>10 and vehicle.signed_speed>vehicle.top_speed*0.95,kind+" climbs a curb at full driving speed")
		await reset(kind,Vector3(0,0,23),PI)
		box(Vector3(0,0.1,11),Vector3(3.4,0.2,12))
		await drive(3,Vector2.DOWN)
		check(vehicle.position.z>29,"Reverse remains vehicle-relative")
		# Back into the slab from its far end.
		await reset(kind,Vector3(0,0,23))
		box(Vector3(0,0.1,11),Vector3(3.4,0.2,12))
		await drive(3,Vector2.DOWN)
		check(vehicle.position.z<14 and vehicle.position.y>0.12,kind+" reverses over a curb")
		await reset(kind)
		box(Vector3(0,0.2,11),Vector3(8,0.4,12))
		await drive(3)
		check(vehicle.position.z<5 and vehicle.position.y<0.05,kind+" cannot step up a wall above the curb limit")
		await reset(kind)
		box(Vector3(0,0.1,11),Vector3(8,0.2,12))
		# Tunnel admits the body on the flat but not after a curb-height lift.
		box(Vector3(0,vehicle.dimensions.y+0.11+0.5,4),Vector3(10,1,15))
		await drive(3)
		check(vehicle.position.z<5 and vehicle.position.y<0.05,kind+" refuses a curb with insufficient overhead clearance")
		await reset(kind)
		box(Vector3(0,0.025,17.5),Vector3(8,0.05,25))
		box(Vector3(0,vehicle.dimensions.y+0.11+0.5,15),Vector3(10,1,30))
		await drive(3)
		check(vehicle.position.z>12 and vehicle.position.y> -0.03,kind+" uses only the available lift under a low ceiling when the curb fits")
		print("LOW ROOF: ",kind," position=",vehicle.position)
		await reset(kind)
		box(Vector3(0,0.1,11),Vector3(8,0.2,12),4)
		await drive(3)
		check(vehicle.position.z<5 and vehicle.position.y<0.05,kind+" never steps onto a resident-layer obstacle")
		await reset(kind)
		box(Vector3(0,0.1,11),Vector3(8,0.2,12),8)
		await drive(3)
		check(vehicle.position.z<5 and vehicle.position.y<0.05,kind+" never steps onto another vehicle")
		await reset(kind,Vector3(0,4,0))
		box(Vector3(0,0.1,11),Vector3(8,0.2,12))
		vehicle.set_physics_process(false)
		vehicle.position = Vector3(0,0.04,5-vehicle.dimensions.z*0.5-0.02)
		vehicle.signed_speed = 6
		vehicle.velocity.y = -0.5
		driver.controls.move = Vector2.UP
		vehicle._physics_process(1.0/hz)
		check(vehicle.position.y<=0.041,kind+" airborne side contact cannot trigger a curb lift")
		await reset(kind)
		box(Vector3(0,0.16,32.5),Vector3(8,0.32,55))
		vehicle.player_driver = null
		vehicle.has_driver = true
		vehicle.record.route = PackedVector3Array([Vector3(0,0,60)])
		vehicle.record.cursor = 0
		await drive(4)
		check(vehicle.position.z>14 and vehicle.position.y>0.24 and vehicle.signed_speed>4,kind+" autonomous traffic also clears curbs without braking for the slab")
		await reset(kind)
		ramp()
		var climb := await drive(5,Vector2(0,-0.6))
		check(vehicle.position.z>21 and climb.high>8.4,kind+" climbs a continuous 30-degree hill")
		check(climb.high<8.8 and vehicle.position.is_finite(),kind+" hill ascent stays bounded to the physical surface")
		print("HILL: ",kind," position=",vehicle.position," range=",climb)
		# Keep the same body, drive back down the hill and onto the flat.
		vehicle.rotation.y = PI
		vehicle.signed_speed = 0
		await drive(6,Vector2(0,-0.6))
		check(vehicle.position.z<3 and vehicle.position.y<0.05,kind+" descends the hill back to street level")
		await reset(kind,Vector3(0,3,0))
		box(Vector3(0,1.5,0),Vector3(8,3,8))
		var drop := await drive(3,Vector2(0,-0.6))
		check(drop.air>0 and vehicle.position.z>10 and vehicle.position.y<0.05,kind+" leaves an unsupported edge and falls naturally")
	print("VEHICLE TERRAIN: ",checks," checks, ",failures," failures at ",hz," Hz")
	scene.queue_free()
	await frames(2)
	quit(1 if failures else 0)
