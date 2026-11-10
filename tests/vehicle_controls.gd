extends SceneTree
const Player = preload("res://scripts/player.gd")
const CameraRig = preload("res://scripts/camera.gd")
const Actions = preload("res://scripts/world_actions.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void:
		if not gameplay_enabled: move = Vector2.ZERO
class Life extends Node3D:
	var actor: CharacterBody3D
	var wider_world: Node3D
	var vehicles: Dictionary = {}
class Session extends Node:
	var world_actions: Node3D
	func show_notice(_text: String) -> void: pass
var scene: Life
var actor: CharacterBody3D
var camera: Node3D
var controls: Intent
var actions: Node3D
var vehicle: CharacterBody3D
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func reset_drive(yaw: float) -> void:
	if actions.attached(): actions.detach()
	controls.move = Vector2.ZERO
	controls.look = Vector2.ZERO
	vehicle.position = Vector3(0,0.1,0)
	vehicle.rotation.y = yaw
	vehicle.velocity = Vector3.ZERO
	vehicle.signed_speed = 0
	actor.global_position = vehicle.global_position+vehicle.global_basis.x*2
	actor.velocity = Vector3.ZERO
	await frames(4)
	check(actions.board(vehicle),"Board "+vehicle.kind+" at heading "+str(yaw))
	check(absf(wrapf(camera.yaw-yaw-PI,-PI,PI))<0.001,"Boarding starts the camera behind the +Z vehicle")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	scene = Life.new()
	root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(512,2,512)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -1
	scene.add_child(floor_body)
	controls = Intent.new()
	scene.add_child(controls)
	actor = Player.new()
	actor.live_motion_retrieval = false
	actor.controls = controls
	camera = CameraRig.new()
	actor.camera_rig = camera
	scene.add_child(actor)
	scene.actor = actor
	camera.target = actor
	camera.controls = controls
	scene.add_child(camera)
	var session := Session.new()
	scene.add_child(session)
	actions = Actions.new()
	actions.actor = actor
	actions.session = session
	scene.add_child(actions)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(4)
	for kind: String in ["car","motorcycle","truck"]:
		vehicle = Vehicle.new()
		vehicle.life = scene
		vehicle.record = {"id":0,"kind":kind,"point":Vector3.ZERO,"yaw":0.0,"traffic":false,"taken":false,"color":Color.CYAN,"driver":{"tint":Color.CYAN,"body_profile":&"male"}}
		scene.add_child(vehicle)
		for yaw: float in [0.0,PI*0.5,PI,-PI*0.5]:
			await reset_drive(yaw)
			var forward: Vector3 = vehicle.global_basis.z
			var right: Vector3 = -vehicle.global_basis.x
			var before := vehicle.global_position
			controls.move = Vector2.UP
			await frames(hz)
			check((vehicle.global_position-before).dot(forward)>2 and vehicle.signed_speed>5,"Stick up drives toward the nose at any world heading")
			var travel_heading := vehicle.rotation.y
			controls.look = Vector2(1,0.2)
			var camera_before: float = camera.yaw
			await frames(hz)
			controls.look = Vector2.ZERO
			check(absf(wrapf(camera.yaw-camera_before,-PI,PI))>1 and absf(wrapf(vehicle.rotation.y-travel_heading,-PI,PI))<0.001,"Free look orbits without changing vehicle heading")
			controls.move = Vector2(0.7,-0.7)
			before = vehicle.global_position
			await frames(hz)
			check(wrapf(vehicle.rotation.y-travel_heading,-PI,PI)< -0.1 and (vehicle.global_position-before).dot(right)>0.2,"Stick right turns toward the vehicle's physical right from every camera view")
			controls.move = Vector2.ZERO
			await frames(hz*2)
			check(absf(vehicle.signed_speed)<0.1,"Releasing the stick slows the vehicle to rest")
		await reset_drive(0)
		controls.move = Vector2(0,-0.4)
		await frames(hz*2)
		check(vehicle.signed_speed>0 and vehicle.signed_speed<vehicle.top_speed*0.45,"Partial stick retains analog speed control")
		controls.move = Vector2.DOWN
		await frames(hz*2)
		check(vehicle.signed_speed< -4,"Stick back brakes then reverses")
		var reverse_yaw := vehicle.rotation.y
		controls.move = Vector2(0.6,0.8)
		await frames(hz)
		check(wrapf(vehicle.rotation.y-reverse_yaw,-PI,PI)>0.1,"Steering reverses naturally while backing up")
		controls.set_gameplay_enabled(false)
		await frames(hz)
		check(absf(vehicle.signed_speed)<0.1 and not paused,"Opening a menu brakes local input while world time continues")
		controls.set_gameplay_enabled(true)
		actions.detach()
		vehicle.queue_free()
		await frames(2)
	print("VEHICLE CONTROLS: ",checks," checks, ",failures," failures at ",hz," Hz")
	scene.queue_free()
	await frames(2)
	quit(1 if failures else 0)
