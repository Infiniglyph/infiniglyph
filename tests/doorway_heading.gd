extends SceneTree
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var travel: Node
var controls: Intent
var checks:=0
var failures:=0
var hz:=60

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks+=1
	if ok: print("PASS: ",title)
	else:
		failures+=1
		push_error("FAIL: "+title)

func frames(count: int=2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func close_angle(a: float,b: float) -> bool: return absf(wrapf(a-b,-PI,PI))<.002

func transfer(yaw: float, heading: float, entering: bool) -> void:
	var pitch: float=world.camera_rig.pitch
	var outside: StringName=travel.OUTSIDE
	check(travel.interact(),"Door interaction begins a physical transition")
	var steady:=true
	for tick in range(hz*4):
		if not travel.busy: break
		await frames(1)
		var turn: float=-PI*.5 if entering and travel.inside() else PI*.5 if not entering and travel.active_location==outside else 0.0
		steady=steady and close_angle(world.camera_rig.yaw,yaw+turn) and close_angle(p.visual.global_rotation.y,heading+turn)
	check(steady and not travel.busy,"The doorway frame maps character and camera together during assembly")
	var turn: float=-PI*.5 if entering else PI*.5
	check(close_angle(world.camera_rig.yaw,yaw+turn) and close_angle(p.visual.global_rotation.y,heading+turn),"Facing stays relative to the entrance, rather than the old compass heading")
	check(absf(world.camera_rig.pitch-pitch)<.001 and close_angle(p.visual.global_rotation.y-world.camera_rig.yaw,heading-yaw),"Camera pitch and independent orbit offset are preserved")
	await frames(3)
	var view: Vector3=-world.camera_rig.camera.global_basis.z
	view.y=0
	view=view.normalized()
	var forward: Vector3=p.visual.global_basis.z
	check(view.dot(Vector3.FORWARD if entering else Vector3.RIGHT)>.90 and forward.dot(Vector3.FORWARD if entering else Vector3.RIGHT)>.95,"Rendered camera and character face into the corridor / away from the exit")

func run() -> void:
	create_timer(45).timeout.connect(func():quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	root.add_child(world)
	p=world.player
	travel=world.dungeon_travel
	controls=Intent.new()
	root.add_child(controls)
	controls.interaction_context=world.inventory_session
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	p.visual.retrieval.enabled=false
	p.global_position=world.wider_world.pyramid.to_global(Vector3(65.5,.15,0))
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	await frames(15)
	world.camera_rig.yaw=PI*.5+.32
	world.camera_rig.pitch=-.41
	p.visual.rotation.y=-PI*.5+.17
	world.camera_rig.reset_follow()
	await transfer(world.camera_rig.yaw,p.visual.global_rotation.y,true)
	p.global_position=Vector3(0,.05,1.5)
	p.velocity=Vector3.ZERO
	await frames(ceili(hz*.6))
	world.camera_rig.yaw=PI+.2
	p.visual.rotation.y=-.1
	world.camera_rig.reset_follow()
	await transfer(world.camera_rig.yaw,p.visual.global_rotation.y,false)
	var before: float=p.visual.global_rotation.y
	travel.restore_location(travel.pyramid_id,{"floor_id":"hub","position":[0,.05,-1],"yaw":1.1})
	check(close_angle(world.camera_rig.yaw,1.1) and close_angle(p.visual.global_rotation.y,before),"Checkpoint relocation does not apply an extra doorway rotation")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	print("DOORWAY HEADING ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
