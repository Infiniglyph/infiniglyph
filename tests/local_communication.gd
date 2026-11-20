extends SceneTree
## Physical presentation boundaries, independent of distant semantic AI work.
const UIC = preload("res://scripts/universal_communication.gd")
const Visual = preload("res://scripts/resident_visual.gd")
const Lines = preload("res://scripts/robe_lines.gd")
class Entity:
	extends CharacterBody3D
	var health := 100.0
	var virtualized := false
class CameraFrame:
	extends Node3D
	var camera: Camera3D
class World:
	extends Node3D
	var player: CharacterBody3D
	var camera_rig: Node3D
	var civilization: Node
var sources: Dictionary = {}
var world: Node3D
var ui: CanvasLayer
var checks := 0
var failures := 0
var semantic_calls := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func identity(id: String) -> Dictionary:
	return {"id":id,"name":"Traveler" if id=="player" else "Nera" if id=="near" else "Distant Resident","kind":"player" if id=="player" else "code_form","active":true,"personality":"friendly"}
func entity(id: String,at: Vector3,tint: Color) -> CharacterBody3D:
	var actor := Entity.new()
	world.add_child(actor)
	actor.position = at
	var figure := Visual.new()
	figure.tint = tint
	actor.add_child(figure)
	sources[id] = actor
	return actor
func speak(id: String,listener: String = "player",parameters: Dictionary = {}) -> Dictionary:
	return ui.send(id,listener,"greet",parameters,{},true)
func outcomes(message: Dictionary) -> Dictionary:
	semantic_calls += 1
	if message.speaker_id=="player" and message.intent=="ask_work":
		return {"accepted":true,"reply":{"intent":"inform","parameters":{"detail":"The eastern gate needs a patient scout."}}}
	return {"accepted":true}
func reset() -> void: ui.close_conversation("fixture")
func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Local communication watchdog"); quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	world = World.new()
	root.add_child(world)
	world.player = entity("player",Vector3.ZERO,Color("42f8ff"))
	var nearby := entity("near",Vector3(0,0,3),Color("bc9aff"))
	var distant := entity("far",Vector3(20,0,3),Color("ffb957"))
	world.camera_rig = CameraFrame.new()
	world.add_child(world.camera_rig)
	var camera := Camera3D.new()
	world.camera_rig.add_child(camera)
	world.camera_rig.camera = camera
	camera.position = Vector3(0,3,-5)
	camera.look_at(Vector3(0,1.3,3))
	camera.fov = 58
	camera.current = true
	world.add_child(Lines.grid(18,18,1,Color("073b48")))
	ui = UIC.new()
	ui.world = world
	ui.identity_provider = identity
	ui.source_provider = func(id: String) -> Node3D: return sources.get(id)
	ui.outcome_handler = outcomes
	world.add_child(ui)
	await frames(3)
	check(ui.can_present("near") and not ui.can_present("far"),"Only a visible physical speaker within six metres can be translated")
	var state: int = ui.translator.rng.state
	var count: int = ui.profiles.records.size()
	var before := semantic_calls
	var far := speak("far","near")
	check(far.accepted and semantic_calls==before+1 and not ui.ambient and not ui._bubble.is_visible_in_tree(),"Distant NPC communication still resolves meaning without local text or sound")
	check(ui.translator.rng.state==state and ui.profiles.records.size()==count,"Rejected presentation allocates no voice profile and consumes no translation randomness")
	var near := speak("near")
	ui._process(.15)
	await frames(2)
	check(near.accepted and ui.ambient and not ui.is_open and ui._bubble.visible and not ui._panel.visible,"Nearby speech appears overhead without a bottom subtitle panel or gameplay input capture")
	check(ui._bubble.is_ancestor_of(ui._subtitle) and ui._subtitle.visible_characters>0,"Progressive translation is rendered inside the speaker's overhead bubble")
	check(ui._bubble.size.y<150,"A short spoken greeting uses a compact overhead bubble")
	state = ui.translator.rng.state
	for i in range(24): speak("near")
	check(ui._queue.is_empty() and ui.translator.rng.state==state,"Nearby ambient chatter cannot build a translation backlog behind the active speaker")
	var position: Vector2 = ui._bubble.position
	nearby.position.x = .6
	ui._process(.05)
	await frames(2)
	check(ui._bubble.position.distance_to(position)>1,"The overhead bubble follows its actual moving speaker")
	if "--capture" in OS.get_cmdline_user_args():
		ui.finish_line()
		await frames(3)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		check(root.get_texture().get_image().save_png("res://captures/local_communication.png")==OK,"Native overhead speech screenshot is captured")
	nearby.position = Vector3(0,0,7)
	ui._process(.1)
	check(not ui.ambient and not ui._bubble.is_visible_in_tree() and not ui._voice.playing,"Leaving the six-metre radius cancels an in-progress line and its voice")
	nearby.position = Vector3(0,0,6)
	check(ui.can_present("near"),"The six-metre boundary remains inclusive")
	nearby.position.z = 6.01
	check(not ui.can_present("near"),"A speaker just outside six metres is excluded")
	nearby.position = Vector3(0,0,3)
	nearby.hide()
	check(not ui.can_present("near"),"Hidden or unloaded speakers cannot leak translated speech")
	nearby.show()
	nearby.virtualized = true
	check(not ui.can_present("near"),"A virtualized speaker remains a semantic participant without presentation")
	nearby.virtualized = false
	var wall := StaticBody3D.new()
	world.add_child(wall)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,5,.3)
	collider.shape = box
	wall.add_child(collider)
	wall.position = Vector3(0,2.2,1.5)
	await frames(3)
	check(not ui.can_present("near"),"An opaque wall blocks nearby translation and prevents speech through rooms")
	state = ui.translator.rng.state
	before = semantic_calls
	speak("near")
	check(semantic_calls==before+1 and not ui.ambient and ui.translator.rng.state==state,"Occluded messages keep their semantic effects without generating a translation")
	wall.free()
	await frames(2)
	var foreign_view := SubViewport.new()
	foreign_view.own_world_3d = true
	root.add_child(foreign_view)
	var foreign := Entity.new()
	foreign_view.add_child(foreign)
	foreign.position = Vector3(0,0,3)
	sources.foreign = foreign
	check(not ui.can_present("foreign"),"Identical coordinates in another world cannot produce a local speech bubble")
	reset()
	camera.look_at(Vector3(0,2,-20))
	check(not ui.can_present("near"),"Ambient translation is suppressed when its speaker is behind the camera")
	check(ui.begin("near","player"),"An intentional nearby conversation can still open while the player looks away")
	reset()
	camera.look_at(Vector3(0,1.3,3))
	check(ui.begin("near","player"),"A nearby entity still opens the contextual conversation")
	ui._process(.1)
	await frames(2)
	check(ui.is_open and ui._panel.visible and ui._bubble.visible and not paused,"Active choices remain available beneath overhead dialogue while the world runs")
	check(root.get_visible_rect().encloses(ui._panel.get_global_rect()) and root.get_visible_rect().encloses(ui._bubble.get_global_rect()),"Conversation choices and the speech bubble both fit the 1280-by-720 viewport")
	if "--capture" in OS.get_cmdline_user_args():
		ui.finish_line()
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/local_conversation.png")
	reset()
	check(not ui._bubble.is_visible_in_tree() and not ui._voice.playing,"Closing communication clears transient speech and electronic voice")
	check(ui.begin("near","player",{},[{"intent":"ask_work","label":"Ask about work"}]),"A deliberate player intention opens through the physical conversation channel")
	ui.finish_line()
	ui.select(0)
	ui.advance()
	ui._process(.05)
	await frames(2)
	check(ui._line.get("speaker_id")=="player" and ui._speaker.text=="Traveler" and ui._bubble.is_visible_in_tree(),"Selecting an intention moves the overhead bubble to the speaking player")
	var player_bubble: Vector2 = ui._bubble.position
	ui.finish_line()
	if "--capture" in OS.get_cmdline_user_args():
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/local_player_intention.png")
	ui.advance()
	ui._process(.05)
	await frames(2)
	check(ui._line.get("speaker_id")=="near" and ui._speaker.text=="Nera" and ui._subtitle.text.contains("eastern gate"),"The authoritative NPC reply follows the selected player intention")
	check(ui._bubble.position.distance_to(player_bubble)>1 and ui._queue.is_empty(),"The reply hands the single overhead bubble back to the actual NPC without overlapping channels")
	if "--capture" in OS.get_cmdline_user_args():
		ui.finish_line()
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/local_npc_reply.png")
	reset()
	foreign_view.queue_free()
	world.queue_free()
	await frames(2)
	print("LOCAL COMMUNICATION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
