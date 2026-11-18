extends SceneTree
## Actual controller edges, countryside triangles and the complete Scribe outfit.
const Player = preload("res://scripts/player.gd")
const CameraRig = preload("res://scripts/camera.gd")
const Regions = preload("res://scripts/world_regions.gd")
const Chunk = preload("res://scripts/world_chunk.gd")
const Neon = preload("res://scripts/neon.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var scene: Node3D
var actor: CharacterBody3D
var controls: Intent
var camera: Node3D
var presentation: Node3D
var hat: Node3D
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
	for i in range(count):
		await physics_frame
		await process_frame

func tap() -> void:
	for held: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_B
		event.pressed = held
		controls._unhandled_input(event)

func finish() -> void:
	for i in range(ceili(actor.dodge.DURATION*hz)+1):
		if not actor.dodge.active: return
		actor.dodge.advance(1.0/hz)

func place(point: Vector2) -> void:
	actor.dodge.cancel()
	actor.position = Vector3(point.x,Regions.height_at(point.x,point.y)+.7,point.y)
	actor.velocity = Vector3.ZERO
	controls.move = Vector2.ZERO
	actor.set_physics_process(true)
	await frames(hz/2)
	actor.set_physics_process(false)

func capture(label: String, view: Camera3D) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	view.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/dodge_terrain_"+label+".png")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	Neon.block(scene,Vector3(0,-1,0),Vector3(60,2,60))
	var chunk := Chunk.new()
	chunk.position = Vector3(640,0,640)
	scene.add_child(chunk)
	var builder := Regions.new()
	builder.build_terrain(chunk)
	chunk.commit()
	builder.free()
	controls = Intent.new()
	scene.add_child(controls)
	actor = Player.new()
	actor.live_motion_retrieval = false
	actor.controls = controls
	camera = CameraRig.new()
	actor.camera_rig = camera
	scene.add_child(actor)
	camera.target = actor
	camera.controls = controls
	scene.add_child(camera)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for assignment: Array in [[&"eternal_scribe_robes",&"body"],[&"eturnull_hat",&"head"],[&"eturnull_manuscript",&"down"]]:
		var item: Resource = Catalog.create(assignment[0])
		check(actor.inventory.add_item(item) and actor.inventory.assign(assignment[1],item.instance_id),"Own and equip "+String(assignment[0]))
	actor.combat.selected_slot = &"down"
	actor.combat.sheathed = false
	actor.weapon_combat.sync_rig()
	await frames(3)
	presentation = actor.weapon_combat.rig.models[&"eturnull_manuscript"].right
	hat = actor.visual.find_child("EturnullHat",true,false)
	actor.set_physics_process(false)
	actor.weapon_combat.set_physics_process(false)
	presentation.set_process(false)
	hat.set_process(false)
	actor.visual.robe.set_process(false)
	actor.position = Vector3(0,10,0)
	actor.velocity = Vector3.ZERO
	for i in range(hz): presentation._process(1.0/hz)
	check(actor.dodge.start(Vector3.RIGHT),"Begin an airborne phase with the full Scribe outfit")
	var peak_scale := 0.0
	var fade_error := 0.0
	while actor.dodge.active:
		actor.dodge.advance(1.0/hz)
		# Multiple render frames per physics tick reproduce idle quill updates
		# during the fully compressed part of a phase, including slow simulation.
		for subframe in range(8):
			presentation._process(1.0/(hz*8))
			hat.advance(1.0/(hz*8))
			var basis: Basis = presentation.quill.global_basis
			peak_scale = maxf(peak_scale,maxf(basis.x.length(),maxf(basis.y.length(),basis.z.length())))
			if actor.dodge.active:
				fade_error = maxf(fade_error,absf(actor.dodge._fade_material.albedo_color.a-actor.dodge.phase_opacity()))
	print("PHASE VISUAL: peak quill scale=",peak_scale," fade error=",fade_error)
	check(peak_scale<1.5,"The quill never stretches into a beam during departure, absence or arrival")
	check(fade_error<.0001,"Hat glyph animation cannot override the shared phase fade or reveal the absent character")
	check(presentation.ink.multimesh.visible_instance_count==0 and actor.visual.scale.is_equal_approx(Vector3.ONE),"Phase exit leaves no active equation and restores the body")
	for point: Vector2 in [Vector2(760,744),Vector2(824,792),Vector2(872,856),Vector2(748,876),Vector2(767.7,767.7),Vector2(831.7,815.7)]:
		for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			await place(point)
			var grounded: bool = actor.is_on_floor()
			controls.move = direction
			tap()
			var origin: Vector3 = actor.position
			actor._physics_process(1.0/hz)
			var accepted: bool = actor.dodge.active
			finish()
			var travel: Vector3 = actor.position-origin
			var horizontal := Vector2(travel.x,travel.z).length()
			var ground := Regions.height_at(actor.position.x,actor.position.z)
			print("HILL: ",point," direction=",direction," grounded=",grounded," accepted=",accepted," travel=",travel," ground gap=",actor.position.y-ground)
			check(grounded and accepted and horizontal>3.15 and actor.position.y>=ground-.03 and actor.position.y<ground+.35,"B traverses walkable countryside at %s toward %s without entering the hill" % [point,direction])
	await place(Vector2(800,792))
	controls.move = Vector2.RIGHT
	actor.velocity = Vector3(10.2,.8,0)
	var chain_origin: Vector3 = actor.position
	for press in range(8):
		tap()
		actor._physics_process(1.0/hz)
	finish()
	check(actor.position.x-chain_origin.x>50.5 and actor.velocity.is_equal_approx(Vector3(10.2,.8,0)),"Rapid B chains follow multiple terrain triangles at full sprint range while retaining uphill momentum")
	# A solid wall on that same ground still truncates both the initial plan
	# and a plan rechecked after the departure animation.
	for late: bool in [false,true]:
		await place(Vector2(824,792))
		controls.move = Vector2.RIGHT
		var origin: Vector3 = actor.position
		var wall: Node3D
		if not late: wall = Neon.block(scene,origin+Vector3(2,1,0),Vector3(.1,4,8))
		await frames(1)
		tap()
		actor._physics_process(1.0/hz)
		if late: wall = Neon.block(scene,origin+Vector3(2,1,0),Vector3(.1,4,8))
		await frames(1)
		finish()
		check(actor.position.x>origin.x+.35 and actor.position.x<origin.x+1.7,"Countryside phase stops before a "+("late-arriving" if late else "standing")+" wall")
		wall.queue_free()
		await frames(1)
	await place(Vector2(824,792))
	controls.move = Vector2.RIGHT
	var ceiling_origin: Vector3 = actor.position
	var ceiling := Neon.block(scene,ceiling_origin+Vector3(3,1.7,0),Vector3(3,.2,2))
	await frames(1)
	tap()
	actor._physics_process(1.0/hz)
	finish()
	check(actor.position.x<ceiling_origin.x+1.3,"Slope-following capsule sweeps still stop before low overhangs")
	ceiling.queue_free()
	await frames(1)
	if "--capture" in OS.get_cmdline_user_args():
		await place(Vector2(824,792))
		controls.move = Vector2.RIGHT
		actor.visual.animate(1.0/hz,Vector3.ZERO,true)
		actor.weapon_combat.apply_pose(1.0/hz)
		presentation._process(.5)
		hat.advance(0)
		actor.visual.robe._process(1.0/hz)
		var view := Camera3D.new()
		scene.add_child(view)
		view.fov = 45
		view.global_position = actor.position+Vector3(5,2.5,6)
		view.look_at(actor.position+Vector3(1.6,1,0))
		await capture("before",view)
		tap()
		actor._physics_process(1.0/hz)
		await capture("departure",view)
		while actor.dodge.active and not actor.dodge.has_shifted:
			actor.dodge.advance(1.0/hz)
			presentation._process(1.0/hz)
			hat.advance(1.0/hz)
		await capture("absent",view)
		while actor.dodge.active and actor.dodge.phase_opacity()<.5:
			actor.dodge.advance(1.0/hz)
			presentation._process(1.0/hz)
			hat.advance(1.0/hz)
		await capture("arrival",view)
		finish()
		presentation._process(1.0/hz)
		hat.advance(1.0/hz)
		actor.visual.robe._process(1.0/hz)
		await capture("after",view)
	scene.queue_free()
	await process_frame
	print("Terrain dodge verification: %d checks, %d failures at %d Hz" % [checks,failures,hz])
	quit(1 if failures else 0)
