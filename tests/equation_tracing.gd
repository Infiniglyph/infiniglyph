extends SceneTree
## Real input, held quill/IK, arbitrary camera pitch, persistent stroke contacts,
## single reflection, movement and bounded resource lifecycle at 30/60/120 Hz.
const Player = preload("res://scripts/player.gd")
const CameraRig = preload("res://scripts/camera.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Target = preload("res://scripts/practice_target.gd")
const Moves = preload("res://scripts/scribe_moves.gd")
const Persistence = preload("res://scripts/persistent_trail.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void: pass
var hz := 60
var checks := 0
var failures := 0
var scene: Node3D
var p: CharacterBody3D
var w: Node
var controls: Node
var presentation: Node3D
var trace: MultiMeshInstance3D
var view: Camera3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2, animate: bool = false) -> void:
	for i in range(count):
		if animate:
			p.visual.animate(1.0/hz,p.velocity,p.is_on_floor())
			w._physics_process(1.0/hz)
		await physics_frame
		await process_frame

func make_player(at: Vector3) -> CharacterBody3D:
	var input := Intent.new()
	scene.add_child(input)
	var actor := Player.new()
	actor.live_motion_retrieval = false
	actor.controls = input
	actor.spawn = at
	var camera := CameraRig.new()
	actor.camera_rig = camera
	scene.add_child(actor)
	camera.target = actor
	camera.controls = input
	scene.add_child(camera)
	camera.set_physics_process(false)
	actor.weapon_combat.max_health = 10000
	actor.weapon_combat.health = 10000
	actor.weapon_combat.set_physics_process(false)
	return actor

func key(code: Key, held: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = held
	controls._combat_input(event)
	p.combat.poll(controls)

func pad(button: JoyButton, held: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = held
	controls._combat_input(event)
	p.combat.poll(controls)

func rt(value: float) -> void:
	controls.set_right_trigger(value)
	p.combat.poll(controls)

func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	view.global_position = p.global_position+Vector3(2.4,1.9,-3.5)
	view.look_at(p.global_position+Vector3.UP*1.05)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/equation_"+label+".png")

func equip_manuscript() -> void:
	var item: Resource = Catalog.create(&"eturnull_manuscript")
	p.inventory.add_item(item)
	p.inventory.assign(&"down",item.instance_id)
	p.combat.selected_slot = &"down"
	p.combat.sheathed = false
	w.sync_rig()
	presentation = w.rig.models[&"eturnull_manuscript"].right

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	view = Camera3D.new()
	view.fov = 55
	scene.add_child(view)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(256,2,256)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -1
	scene.add_child(floor_body)
	p = make_player(Vector3(0,.02,0))
	controls = p.controls
	w = p.weapon_combat
	await frames(hz/3)
	p.set_physics_process(false)
	equip_manuscript()
	view.current = true
	await frames(hz/2,true)
	check(presentation.book.global_position.distance_to(w.rig.right_hand.global_position)<.16,"Open Manuscript stays attached to anatomical left hand")
	check(presentation.quill.visible and presentation.quill.global_position.distance_to(w.rig.left_hand.global_position)>.6,"Existing free quill hover remains independent of right hand")
	key(KEY_V)
	await frames(hz/3,true)
	check(w.is_writing_stance() and not is_instance_valid(w.equation_trace),"RT/V alone enters writing stance without a trail or attack")
	check(presentation.quill.global_position.distance_to(w.rig.left_hand.global_position-Vector3.UP*.16)<.002,"RT/V brings actual quill nib into free hand")
	check(presentation.quill.global_basis.y.normalized().dot(Vector3.UP)>.999,"Held quill is upright")
	await capture("writing_stance")
	key(KEY_V,false)
	await frames(hz/3,true)
	check(not w.is_writing_stance() and presentation.quill.global_position.distance_to(w.rig.left_hand.global_position)>.6,"Releasing modifier returns normal floating quill without sheathing")
	# Camera-directed ordinary equations share the same full 3D frame for ink
	# and collision; no changes to non-Scribe aim or the player's capsule.
	var target := Target.new()
	target.health = 100000
	target.max_health = 100000
	scene.add_child(target)
	target.set_physics_process(false)
	var camera_aims := true
	p.position.y = 5
	for pitch: float in [-.65,0,.6]:
		p.camera_rig.pitch = pitch
		p.camera_rig.yaw = .65
		var direction: Vector3 = -Basis.from_euler(Vector3(pitch,.65,0)).z
		w.cancel()
		w._on_action(&"attack_right",&"down")
		w.elapsed = float(w.active_move.hits[0])
		target.global_position = p.combat_point()+direction*4.5-Vector3.UP*.95
		await frames()
		var before: float = target.total_damage
		w.strike(0)
		camera_aims = camera_aims and w._facing.dot(direction)>.999 and presentation.active_transform.basis.z.normalized().dot(direction)>.999 and target.total_damage>before
	check(camera_aims,"Upward, horizontal and downward camera aim rotate visible ordinary equations AND real hits")
	w.cancel()
	p.position.y = .02
	target.position = Vector3(40,0,40)
	p.camera_rig.pitch = 0
	p.camera_rig.yaw = 0
	key(KEY_V)
	key(KEY_Q)
	trace = w.equation_trace
	key(KEY_Q,false)
	check(trace.sections.size()==1 and trace.sections[0].bounds.size.length()<.23,"Tiny X tap writes a tiny real X immediately")
	check(p.combat.charge_action==&"" and p.combat.trace_action==&"" and w.active_move.is_empty(),"Trace tap never dispatches a charged/release attack")
	trace.clear()
	key(KEY_R)
	key(KEY_R,false)
	check(trace.sections.size()==1 and trace.sections[0].points.size()==16 and trace.sections[0].bounds.size.length()<.23,"Tiny Y tap writes an eight-edge circular mark")
	trace.clear()
	key(KEY_Q)
	await frames(hz,true)
	var x_count: int = trace.sections.size()
	check(x_count>hz/3 and p.combat.trace_action==&"special_rt_x" and p.combat.charge_action==&"","Held X continuously records multiple patterns rather than charging once")
	var old_point: Vector3 = trace.sections[0].points[0]
	for i in range(hz/2):
		p.position += Vector3(.02,.012,-.035)
		p.velocity = Vector3(.02,.012,-.035)*hz
		await frames(1,true)
	check(trace.sections.size()>x_count and trace.sections[0].points[0]==old_point,"Moving and rising changes new writing while old equations stay fixed in world space")
	check(presentation.quill.global_position.distance_to(w.rig.left_hand.global_position-Vector3.UP*.16)<.002,"Conducting hand and visible quill stay physically aligned while tracing")
	await capture("x_path")
	key(KEY_Q,false)
	var stopped: int = trace.sections.size()
	await frames(hz/5,true)
	check(trace.sections.size()==stopped,"Releasing X immediately stops sampling and leaves existing sections alive")
	key(KEY_V,false)
	trace.clear()
	key(KEY_V)
	key(KEY_R)
	await frames(hz/3,true)
	var first_circle: Vector3 = trace.sections[0].bounds.get_center()
	for i in range(hz/2):
		p.position.z -= .04
		p.position.y += .02
		await frames(1,true)
	var last_circle: Vector3 = trace.sections[-1].bounds.get_center()
	check(trace.sections.size()>20 and last_circle.distance_to(first_circle)>1,"Held Y draws a growing three-dimensional helical trail along travel")
	await capture("circle_path")
	key(KEY_SPACE)
	check(controls.consume_jump() and not controls.consume_shield(),"V+Space jumps while actively tracing")
	key(KEY_SPACE,false)
	key(KEY_R,false)
	key(KEY_SPACE)
	check(controls.consume_shield() and not controls.consume_jump(),"V+Space retains Shield Glyph use outside tracing")
	key(KEY_SPACE,false)
	key(KEY_V,false)
	trace.clear()
	rt(1)
	pad(JOY_BUTTON_X)
	pad(JOY_BUTTON_A)
	check(controls.consume_jump() and not controls.consume_shield(),"Controller RT+X+A jumps while tracing")
	pad(JOY_BUTTON_A,false)
	pad(JOY_BUTTON_X,false)
	pad(JOY_BUTTON_A)
	check(controls.consume_shield() and not controls.consume_jump(),"Controller RT+A remains Shield Glyph use outside tracing")
	pad(JOY_BUTTON_A,false)
	pad(JOY_BUTTON_Y)
	rt(0)
	check(p.combat.trace_action==&"" and trace.action==&"","Releasing RT stops active Y without waiting for Y release")
	rt(1)
	pad(JOY_BUTTON_A)
	check(controls.consume_shield() and not controls.consume_jump(),"A cancelled, still-held face button cannot steal the Shield Glyph shortcut")
	pad(JOY_BUTTON_A,false)
	rt(0)
	pad(JOY_BUTTON_Y,false)
	trace.clear()
	p.position = Vector3(0,.02,10)
	p.velocity = Vector3.ZERO
	p.set_physics_process(true)
	w.set_physics_process(true)
	await frames(hz/4)
	key(KEY_V)
	key(KEY_Q)
	controls.move = Vector2.UP
	controls.boost = true
	var moved_from: Vector3 = p.global_position
	await frames(hz/4)
	key(KEY_SPACE)
	await frames(hz/5)
	key(KEY_SPACE,false)
	var jump_height: float = p.position.y
	key(KEY_SPACE)
	await frames(hz/5)
	key(KEY_SPACE,false)
	check(p.last_sky_impulse.y>0 and p.position.y>jump_height and p.combat.trace_action==&"special_rt_x","Real Sky Jump adds lift while the X trace remains active")
	check(p.global_position.distance_to(moved_from)>2 and p.boost_active and not trace.sections.is_empty(),"Real sprint/boost movement stays unrestricted during writing")
	var airborne_trail := false
	for section: Dictionary in trace.sections: airborne_trail = airborne_trail or section.bounds.get_center().y>2
	check(airborne_trail,"Actual airborne movement leaves world-space equations above the ground")
	controls.request_dodge()
	await frames(2)
	check(p.combat.trace_action==&"" and trace.action==&"","Real dodge immediately cancels active tracing")
	controls.move = Vector2.ZERO
	controls.boost = false
	key(KEY_Q,false)
	key(KEY_V,false)
	p.set_physics_process(false)
	w.set_physics_process(false)
	p.dodge.cancel()
	w.clear_stagger()
	# Lifetime, actual glyph contacts, gaps, fast crossings, defenses/reflection.
	trace.clear()
	p.position = Vector3(0,.02,-3)
	p.velocity = Vector3.ZERO
	target.position = Vector3(0,.02,0)
	await frames()
	var center: Vector3 = target.combat_point()
	trace.append_section(PackedVector3Array([center+Vector3(-.5,0,0),center+Vector3(.5,0,0)]))
	trace.set_physics_process(true)
	var damage_before: float = target.total_damage
	await frames(2)
	check(is_equal_approx(target.total_damage-damage_before,750),"Persistent equations apply vehicle-trail damage through actual stroke contact")
	await frames(hz/2+2)
	check(target.total_damage-damage_before>=1500,"Surviving sections remain hazardous on the shared half-second cooldown")
	trace.clear()
	trace.append_section(PackedVector3Array([center+Vector3(-1,0,0),center+Vector3(-.6,0,0),center+Vector3(.6,0,0),center+Vector3(1,0,0)]))
	trace.resolve_contacts()
	var gap_before: float = target.total_damage
	trace.resolve_contacts()
	check(target.total_damage==gap_before,"Empty space between mathematical strokes is a genuine safe gap")
	target.position.x = -2
	trace.resolve_contacts()
	target.position.x = 2
	trace.resolve_contacts()
	check(target.total_damage>gap_before,"Swept hurt shapes catch a fast target crossing between simulation samples")
	trace.clear()
	target.position = Vector3(40,0,40)
	var defender := make_player(Vector3(0,.02,0))
	defender.add_to_group("combat_targets")
	await frames(3)
	defender.set_physics_process(false)
	defender.camera_rig.yaw = 0
	defender.combat.blocking = true
	defender.weapon_combat.parry_remaining = 0
	center = defender.combat_point()+Vector3(0,0,-.2)
	trace.append_section(PackedVector3Array([center+Vector3(-.4,0,0),center+Vector3(.4,0,0)]))
	var guard_hp: float = defender.health
	trace.resolve_contacts()
	check(defender.weapon_combat.last_blocked and guard_hp-defender.health>0 and guard_hp-defender.health<750,"Ordinary guard mitigates persistent ink through existing weapon block power")
	trace.clear()
	defender.combat.blocking = false
	defender.dodge.start(Vector3.RIGHT)
	defender.dodge.elapsed = defender.dodge.DURATION*.5
	trace.append_section(PackedVector3Array([center+Vector3(-.4,0,0),center+Vector3(.4,0,0)]))
	var dodge_hp: float = defender.health
	trace.resolve_contacts()
	check(defender.weapon_combat.last_evaded and defender.health==dodge_hp,"Normal dodge invulnerability avoids persistent ink")
	defender.dodge.cancel()
	trace.clear()
	defender.combat.blocking = true
	defender.weapon_combat.parry_remaining = .18
	center = defender.combat_point()+Vector3(0,0,-.2)
	trace.append_section(PackedVector3Array([center+Vector3(-.4,0,0),center+Vector3(.4,0,0)]))
	trace.append_section(PackedVector3Array([center+Vector3(-.4,.1,0),center+Vector3(.4,.1,0)]))
	var hp: float = defender.health
	trace.resolve_contacts()
	check(defender.weapon_combat.last_parried and defender.health==hp,"Existing timed parry prevents all incoming equation damage")
	check(w.forced_state==&"parried" and is_equal_approx(w.stagger_remaining,1),"Successful trail parry preserves the shared one-second attacker stun")
	check(trace.reflected_count==2 and trace.sections.all(func(s: Dictionary): return s.reflected and s.owner.get_ref()==defender and s.velocity.z<0),"Intercepted neighbouring sections leave a real opening and fly in defender facing direction")
	w.clear_stagger()
	p.combat.blocking = true
	p.camera_rig.yaw = PI
	w.parry_remaining = .18
	trace.set_physics_process(true)
	var author_hp: float = p.health
	await frames(hz/2)
	check(p.health<author_hp and not w.last_parried,"Redirected equations can hit their author and cannot be parried a second time")
	check(defender.health==hp,"Original defender remains safe through the reflected section")
	p.combat.blocking = false
	defender.combat.blocking = false
	defender.position = Vector3(40,0,-40)
	trace.clear()
	center = p.combat_point()
	trace.append_section(PackedVector3Array([center-Vector3.RIGHT*.4,center+Vector3.RIGHT*.4]))
	var immune_hp: float = p.health
	trace.resolve_contacts()
	check(p.health==immune_hp,"Unreflected ink excludes its author")
	trace.clear()
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4,4,.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	scene.add_child(wall)
	wall.position = Vector3(0,1,-1.5)
	target.position = Vector3(0,.02,0)
	await frames()
	center = target.combat_point()
	trace.append_section(PackedVector3Array([center-Vector3.RIGHT*.4,center+Vector3.RIGHT*.4]))
	var wall_hp: float = target.total_damage
	trace.resolve_contacts()
	check(target.total_damage==wall_hp,"Opaque architecture blocks a trace through the shared world collision layers")
	wall.queue_free()
	target.position = Vector3(40,0,40)
	trace.clear()
	trace.append_section(PackedVector3Array([Vector3(10,2,0),Vector3(11,2,0)]))
	trace.set_physics_process(true)
	trace.time += float(trace.settings.lifetime)-float(trace.settings.fade_duration)*.5
	trace.redraw()
	var alpha: float = trace.section_opacity(trace.sections[0])
	check(alpha>.35 and alpha<.65 and trace.multimesh.visible_instance_count==1,"Visible stroke alpha fades during the end of its lifetime")
	await frames(hz)
	check(trace.sections.is_empty() and trace.multimesh.visible_instance_count==0 and not trace.is_physics_processing(),"Expired geometry AND collision retire without permanent nodes")
	for i in range(1200): trace.append_section(PackedVector3Array([Vector3(i*.01,4,0),Vector3(i*.01+.01,4,0)]))
	trace.redraw()
	check(trace.sections.size()<=trace.settings.maximum_sections and trace.multimesh.visible_instance_count<=trace.settings.maximum_strokes and trace.get_child_count()==0,"Sustained writing obeys section/stroke limits without per-glyph scene or physics nodes")
	check(is_equal_approx(Persistence.opacity(1,4,4,.6),1) and is_equal_approx(Persistence.opacity(1,4.7,4,.6),.5),"Vehicle and equations share unchanged bounded storage/fade rules")
	trace.clear()
	key(KEY_V)
	key(KEY_Q)
	key(KEY_DOWN)
	p.combat.sheathed = true
	p.combat.sheathed_changed.emit(true)
	await frames(hz,true)
	check(p.combat.trace_action==&"" and trace.action==&"" and not presentation.quill.visible,"Sheathing cancels tracing and returns quill inside closed hip book")
	key(KEY_Q,false)
	key(KEY_DOWN,false)
	key(KEY_V,false)
	p.combat.sheathed = false
	w.sync_rig()
	key(KEY_V)
	key(KEY_R)
	controls.set_gameplay_enabled(false)
	check(p.combat.trace_action==&"" and trace.action==&"","Menu/focus input reset cancels tracing without pausing world time")
	w.reset()
	check(trace.sections.is_empty(),"Death/respawn reset removes old hazards and reflected ownership")
	controls.set_gameplay_enabled(true)
	p.combat.sheathed = false
	key(KEY_V)
	key(KEY_Q)
	key(KEY_Q,false)
	key(KEY_V,false)
	key(KEY_RIGHT)
	key(KEY_RIGHT,false)
	key(KEY_V)
	key(KEY_Q)
	check(p.combat.charge_action==&"special_rt_x" and p.combat.trace_action==&"","Other weapons retain their modified charge/release arts")
	key(KEY_Q,false)
	check(not w.active_move.is_empty() and not w.active_move.get("weapon_family","")=="scribe","Other weapons still execute their original modified art on release")
	key(KEY_V,false)
	print("EQUATION TRACING: ",checks," checks, ",failures," failures at ",hz," Hz")
	scene.queue_free()
	await frames(2)
	quit(1 if failures else 0)
