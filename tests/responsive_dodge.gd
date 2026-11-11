extends SceneTree
## Exercise fresh input edges through the real controller, including phase chains.
const Player = preload("res://scripts/player.gd")
const CameraRig = preload("res://scripts/camera.gd")
const Neon = preload("res://scripts/neon.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void:
		if not gameplay_enabled: move = Vector2.ZERO
var scene: Node3D
var actor: CharacterBody3D
var controls: Intent
var camera: Node3D
var hz := 60
var checks := 0
var failures := 0
var starts := 0
var shifts := 0
var ends := 0
var distances: Array[float] = []

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

func pad(held: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_B
	event.pressed = held
	controls._unhandled_input(event)

func key(held: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = held
	event.echo = echo
	controls._unhandled_input(event)

func tap(use_keyboard: bool = false) -> void:
	if use_keyboard:
		key(true)
		key(false)
	else:
		pad(true)
		pad(false)

func finish() -> void:
	for i in range(hz):
		if not actor.dodge.active: return
		await frames(1)
	check(false,"The final requested phase completes within one second")

func reset(carried: Vector3 = Vector3.ZERO) -> void:
	controls.set_gameplay_enabled(true)
	actor.respawn()
	actor.position = Vector3(0,20,0)
	controls.move = Vector2.RIGHT
	camera.yaw = 0
	await frames(1)
	actor.velocity = carried
	starts = 0
	shifts = 0
	ends = 0
	distances.clear()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	Neon.block(scene,Vector3(0,-1,0),Vector3(2000,2,2000))
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
	actor.dodge.started.connect(func(_origin: Vector3, _destination: Vector3): starts += 1)
	actor.dodge.shifted.connect(func(destination: Vector3):
		shifts += 1
		distances.append(destination.distance_to(actor.dodge.origin)))
	actor.dodge.finished.connect(func(): ends += 1)
	await frames(2)
	# Every phase interval is accepted, including before the old shift point and
	# directly after completion. Repeat with both controller and keyboard edges.
	for keyboard: bool in [false,true]:
		for interval: float in [0.0,0.05,0.12,0.18,0.27,0.34,0.35,0.61,0.70]:
			await reset()
			tap(keyboard)
			await frames(1)
			await frames(maxi(0,ceili(interval*hz)-1))
			tap(keyboard)
			await frames(1)
			check(starts==2 and actor.dodge.active and actor.dodge.elapsed<=1.0/hz+0.00001 and not actor.dodge.is_invulnerable(),"%s accepts a fresh press at %.2fs with immediate visible departure" % ["E" if keyboard else "B",interval])
			await finish()
			check(shifts==2 and distances.size()==2 and distances[0]>=3.19 and distances[1]>=3.19 and ends==2,"Both %.2fs presses produce useful swept travel without starving a pre-shift dodge" % interval)
	await reset()
	tap()
	tap(true)
	tap()
	await frames(1)
	check(starts==3 and shifts==2 and actor.dodge.active,"Three fresh edges in one physics sample each start a dodge and settle earlier travel")
	await finish()
	check(shifts==3 and actor.position.x>=9.59,"A same-frame input burst loses no displacement")
	await reset()
	pad(true)
	pad(true)
	key(true)
	key(true,true)
	key(true)
	await frames(1)
	check(starts==2,"Held buttons, key echo and duplicate pressed events do not create extra dodges")
	await finish()
	await frames(hz)
	check(starts==2 and not actor.dodge.active,"Holding B or E never auto-repeats after a phase completes")
	pad(false)
	key(false)
	# Repeated recaching must retain original materials, not cache the fade ink.
	for slot: StringName in [&"down",&"left",&"right",&"up"]:
		await reset(Vector3(8,-3,2))
		controls._request(&"weapon",slot)
		actor.combat.poll(controls)
		var geometries: Array[Node] = actor.visual.find_children("*","GeometryInstance3D",true,false)
		var materials: Array[Material] = []
		for geometry: GeometryInstance3D in geometries: materials.append(geometry.material_override)
		for press in range(12):
			tap(press%2==1)
			await frames(1)
		await finish()
		var restored := true
		for i in range(geometries.size()): restored = restored and geometries[i].material_override==materials[i]
		check(starts==12 and shifts==12 and restored and actor.visual.scale.is_equal_approx(Vector3.ONE),"Rapid %s chains restore all body and weapon materials" % slot)
		check(actor.velocity.is_equal_approx(Vector3(8,-3,2)) and actor.dodge.requested_distance>5.7,"Repeated %s dodges retain original momentum and momentum-based range" % slot)
	# Include the actual fitted outfit and articulated sleeves in rapid recaches.
	# The inscription cycle is poised to update, exercising stable mesh identities.
	await reset()
	var clothing: Resource = Catalog.create(&"eternal_scribe_robes")
	check(actor.inventory.add_item(clothing) and actor.inventory.assign(&"body",clothing.instance_id),"An owned robe equips through the existing Body assignment")
	await frames(2)
	var robe: Node3D = actor.visual.robe
	var dressed_geometry: Array[Node] = actor.visual.find_children("*","GeometryInstance3D",true,false)
	var dressed_materials: Array[Material] = []
	var dressed_ids: Array[int] = []
	for geometry: GeometryInstance3D in dressed_geometry:
		dressed_materials.append(geometry.material_override)
		dressed_ids.append(geometry.get_instance_id())
	var garment_nodes: int = robe.find_children("*","Node",true,false).size()
	for sleeve: Node3D in robe._external_pieces: garment_nodes += sleeve.find_children("*","Node",true,false).size()
	robe._elapsed = 4.79
	starts = 0
	shifts = 0
	ends = 0
	actor.velocity = Vector3.ZERO
	for press in range(12):
		tap(press%2==1)
		await frames(1)
		if press%3==0: await frames(maxi(1,ceili(0.12*hz)-1))
	var stable := true
	var faded := true
	for i in range(dressed_geometry.size()):
		stable = stable and is_instance_valid(dressed_geometry[i]) and dressed_geometry[i].get_instance_id()==dressed_ids[i]
		faded = faded and dressed_geometry[i].material_override==actor.dodge._fade_material
	check(starts==12 and stable and faded,"Rapid robed phases keep torso, tails, glyphs and all four sleeve meshes in the shared phase cache")
	await finish()
	var clothing_restored := true
	for i in range(dressed_geometry.size()):
		clothing_restored = clothing_restored and dressed_geometry[i].material_override==dressed_materials[i]
	var nodes_after: int = robe.find_children("*","Node",true,false).size()
	for sleeve: Node3D in robe._external_pieces: nodes_after += sleeve.find_children("*","Node",true,false).size()
	check(shifts==12 and ends==12 and clothing_restored and nodes_after==garment_nodes and actor.visual.scale.is_equal_approx(Vector3.ONE),"Every rapid robed phase restores original sleeve/body overrides without accumulating nodes or fade materials")
	await frames(2)
	var all_geometry: Array[Node] = actor.visual.find_children("*","GeometryInstance3D",true,false)
	var no_leak := all_geometry.size()==dressed_geometry.size()
	for geometry: GeometryInstance3D in all_geometry: no_leak = no_leak and geometry.material_override!=actor.dodge._fade_material
	check(no_leak and robe.is_equipped(),"Resuming fitted cloth and inscription updates after rapid phases leaves no cached fade behind")
	# Collision is authoritative even when repeated input accelerates a commit.
	await reset()
	var wall := Neon.block(scene,Vector3(5,20,0),Vector3(0.1,8,20))
	await frames(1)
	actor.velocity = Vector3.ZERO
	for press in range(8): tap()
	await frames(1)
	await finish()
	check(actor.position.x>4.0 and actor.position.x<4.59 and not actor.get_child(0).disabled,"Burst chaining stops the full capsule before a thin wall")
	check(not actor.dodge.is_invulnerable() and actor.visual.scale.is_equal_approx(Vector3.ONE),"An obstructed chain leaves no phase immunity or fade behind")
	wall.queue_free()
	await frames(1)
	await reset()
	tap()
	await frames(1)
	var late_wall := Neon.block(scene,Vector3(2,20,0),Vector3(0.1,8,20))
	await frames(1)
	tap(true)
	await frames(1)
	await finish()
	check(actor.position.x>0.35 and actor.position.x<1.59,"A new blocker is re-swept when a fresh press commits an early shift")
	late_wall.queue_free()
	await frames(1)
	# Only the fully absent interval grants phase immunity, on every new phase.
	await reset()
	tap()
	await frames(1)
	while not actor.dodge.is_invulnerable(): await frames(1)
	check(actor.dodge.phase_opacity()==0 and actor.dodge._fade_material.albedo_color.a==0,"The original fully hidden interval remains invulnerable")
	tap(true)
	await frames(1)
	check(actor.dodge.phase_opacity()>0 and not actor.dodge.is_invulnerable(),"A fresh press ends old immunity and starts a visibly vulnerable departure")
	await finish()
	check(not actor.dodge.is_invulnerable(),"The last chained phase ends immunity normally")
	# Invalid gameplay states discard requests rather than replaying them later.
	await reset()
	actor.weapon_combat.stagger_remaining = 0.5
	tap()
	tap(true)
	await frames(1)
	check(starts==0 and not actor.dodge.active,"Forced stagger still rejects dodge input")
	actor.weapon_combat.clear_stagger()
	await frames(2)
	check(starts==0,"Rejected stagger presses do not fire on recovery")
	actor.weapon_combat.health = 0
	check(not actor.dodge.start(Vector3.RIGHT),"A defeated actor cannot directly start a phase")
	await reset()
	tap()
	tap(true)
	controls.set_gameplay_enabled(false)
	tap()
	tap(true)
	await frames(1)
	controls.set_gameplay_enabled(true)
	await frames(1)
	check(starts==0,"Opening and closing live UI clears pending presses and blocks UI edges")
	for cancellation: String in ["focus","disconnect","respawn"]:
		await reset()
		tap()
		tap(true)
		if cancellation=="focus": controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif cancellation=="disconnect": controls._on_joy_connection_changed(0,false)
		else: actor.respawn()
		await frames(1)
		check(starts==0,"%s clears every buffered dodge edge" % cancellation)
	await reset()
	controls.set_right_trigger(0)
	controls.set_right_trigger(0.9)
	tap()
	await frames(1)
	check(starts==0 and controls.consume_heal(),"RT+B remains a Health Glyph request without a dodge")
	controls.set_right_trigger(0)
	tap()
	await frames(1)
	check(starts==1 and not controls.consume_heal(),"B alone immediately dodges after releasing RT")
	actor.respawn()
	await frames(hz)
	check(not actor.dodge.active and not actor.dodge.is_invulnerable() and get_nodes_in_group("phase_traces").is_empty(),"Reset clears the final phase and all temporary traces expire")
	scene.queue_free()
	await process_frame
	print("Responsive dodge verification: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
