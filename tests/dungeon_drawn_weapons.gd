extends SceneTree
## Real doorway inputs and complete skeleton samples during both travel phases.
const Catalog = preload("res://scripts/item_catalog.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var controls: Intent
var travel: Node
var checks := 0
var failures := 0
var hz := 60
var monitoring := false
var stats: Dictionary = {}
var capture_view: Camera3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	Engine.max_physics_steps_per_frame = 1
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
		if monitoring and travel.busy: sample_pose()

func orthogonal(basis: Basis) -> bool:
	return basis.is_finite() and absf(basis.determinant()-1)<0.003 and absf(basis.x.dot(basis.y))<0.003 and absf(basis.z.dot(basis.y))<0.003 and absf(basis.x.dot(basis.z))<0.003

func sample_pose() -> void:
	var v: Node3D = p.visual
	stats.frames += 1
	stats.phases[int(travel._phase)] = true
	stats.root_up = minf(stats.root_up,v.global_basis.y.normalized().dot(Vector3.UP))
	stats.hip_up = minf(stats.hip_up,v.pelvis.global_basis.y.normalized().dot(Vector3.UP))
	stats.chest_up = minf(stats.chest_up,v.chest.global_basis.y.normalized().dot(Vector3.UP))
	stats.hip_min = minf(stats.hip_min,v.pelvis.global_position.y-p.global_position.y)
	stats.head_min = minf(stats.head_min,v.chest.to_global(Vector3(0,.78,0)).y-p.global_position.y)
	stats.hip_drift = maxf(stats.hip_drift,v.pelvis.position.distance_to(stats.hip_start))
	stats.orthogonal = stats.orthogonal and orthogonal(v.global_basis) and orthogonal(v.pelvis.global_basis) and orthogonal(v.chest.global_basis)
	for id: String in v.joints:
		var limb: Node3D = v.joints[id]
		stats.orthogonal = stats.orthogonal and orthogonal(limb.global_basis)
		stats.limb_max = maxf(stats.limb_max,limb.get_node("Hinge").global_position.distance_to(p.global_position))
	stats.safe = stats.safe and p.visible and p.transition_locked and not controls.gameplay_enabled and is_equal_approx(p.health,740)

func key_g() -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_G
		event.keycode = KEY_G
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func rt(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	Input.parse_input_event(event)
	await frames(1)

func place(point: Vector3) -> void:
	p.global_position = point
	p.velocity = Vector3.ZERO
	p.fall_damage.reset()
	p.visual.rebase_after_phase()
	await frames(ceili(.65*hz))

func transition(input: String, label: String) -> void:
	var was_inside: bool = travel.inside()
	var inventory: Dictionary = p.inventory.serialize()
	var character_id := p.get_instance_id()
	var visual_id: int = p.visual.get_instance_id()
	var pitch: float = world.camera_rig.pitch
	var serial: int = p.weapon_combat.attack_serial
	var stowed: bool = p.combat.sheathed
	var kind: StringName = p.weapon_combat.loadout(p.combat.selected_slot).id
	stats = {"frames":0,"phases":{},"root_up":1.0,"hip_up":1.0,"chest_up":1.0,"hip_min":INF,"head_min":INF,"hip_drift":0.0,"hip_start":p.visual.pelvis.position,"orthogonal":true,"limb_max":0.0,"safe":true}
	monitoring = true
	if input=="g": await key_g()
	else:
		await rt(0)
		await rt(1)
		check(not travel.busy,label+": bare RT waits for release")
		await rt(0)
	# process_frame resumes before InventorySession._process consumes the fresh
	# interaction request. Let the normal consumer run before inspecting travel.
	await frames(2)
	check(travel.busy,label+": doorway input starts exactly one transition")
	var captured: Dictionary = {}
	for i in range(hz*4):
		if not travel.busy: break
		await frames(1)
		if is_instance_valid(capture_view) and not stowed and label.ends_with("entry") and travel.busy and travel._phase==0 and float(travel._clock)>.25 and not captured.has(travel._phase):
			captured[travel._phase] = true
			await shot(label+"_phase_"+str(travel._phase))
	monitoring = false
	await frames(ceili(.3*hz))
	print("DRAWN TRAVEL ",label," @",hz,"Hz: ",JSON.stringify(stats))
	check(not travel.busy and travel.inside()!=was_inside and stats.phases.size()==2,label+": both deconstruction and reconstruction complete")
	check(stats.safe and not p.transition_locked and controls.gameplay_enabled,label+": visibility, health and input protection survive the transition")
	check(stats.orthogonal and stats.root_up>.999,label+": global visual and skeleton bases remain finite and orthonormal")
	# Releasing the supported ready stance may restore roughly 14 cm of hip
	# offset once. Repeated overlays previously accumulated almost four metres.
	check(stats.hip_up>.85 and stats.chest_up>.80 and stats.hip_drift<.20,label+": ready overlays never accumulate pelvis drift or torso rotation")
	check(stats.hip_min>.73 and stats.head_min>1.35 and stats.limb_max<1.9,label+": head, pelvis and limbs remain supported above the floor")
	var support := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p.global_position+Vector3.UP*.3,p.global_position-Vector3.UP*.4,1,[p.get_rid()]))
	check(p.is_on_floor() and not support.is_empty() and p.health==740,label+": the same healthy player lands on real destination support")
	check(p.get_instance_id()==character_id and p.visual.get_instance_id()==visual_id and p.inventory.serialize()==inventory and is_equal_approx(world.camera_rig.pitch,pitch),label+": actor, visual, inventory and camera elevation are preserved")
	check(p.weapon_combat.attack_serial==serial and p.weapon_combat.active_move.is_empty() and controls._combat_requests.is_empty(),label+": reset inputs cannot create an automatic attack")
	var ready: String = "scribe-ready" if kind==&"scribe" else "paintbrush-ready"
	check(p.combat.sheathed==stowed and p.combat.selected_slot==&"down" and (stowed or p.weapon_combat.body.phase_label==ready),label+": the same drawn or sheathed state resumes its normal stance")

func shot(label: String) -> void:
	for mesh: GeometryInstance3D in p.find_children("*","GeometryInstance3D",true,false): mesh.layers = 2
	capture_view.global_position = p.global_position+p.visual.global_basis*Vector3(2.5,1.9,3.5)
	capture_view.look_at(p.global_position+Vector3.UP*.95)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/dungeon_drawn_"+label.replace(" ","_")+".png")
	print("DRAWN TRAVEL CAPTURE: ",label)

func equip(id: StringName, sheathed: bool) -> void:
	p.weapon_combat.cancel()
	controls.reset_combat_input()
	var item: Resource = Catalog.create(id)
	p.inventory.add_item(item)
	check(world.loot.request_equip(p.inventory,&"down",item.instance_id),"Equip travel reference "+String(id))
	p.combat.selected_slot = &"down"
	p.combat.sheathed = sheathed
	p.weapon_combat.sync_rig()
	await frames(ceili(.45*hz))

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.dungeon_enemies_enabled = false
	world.inventory_persistence_enabled = false
	world.world_memory_enabled = false
	world.district_life_enabled = false
	world.boss_encounters_enabled = false
	world.neon_glow_enabled = false
	root.add_child(world)
	p = world.player
	travel = world.dungeon_travel
	world.controls.set_process_unhandled_input(false)
	controls = Intent.new()
	root.add_child(controls)
	controls.interaction_context = world.inventory_session
	world.controls = controls
	p.controls = controls
	world.camera_rig.controls = controls
	world.inventory_session.controls = controls
	p.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p.weapon_combat.health = 740
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		# Render the actual character in its real World3D without the entire
		# city/maze dominating a close-up regression capture on integrated GPUs.
		for mesh: GeometryInstance3D in p.find_children("*","GeometryInstance3D",true,false): mesh.layers = 2
		capture_view = Camera3D.new()
		world.add_child(capture_view)
		capture_view.cull_mask = 2
		capture_view.fov = 50
		capture_view.current = true
	await frames(10)
	var cases: Array = [[&"eturnull_manuscript",true,"g","rt"],[&"eturnull_manuscript",false,"rt","g"],[&"paintbrush_violet",false,"g","rt"]]
	if "--repro" in OS.get_cmdline_user_args(): cases = [[&"eturnull_manuscript",false,"g","rt"]]
	for entry: Array in cases:
		await equip(entry[0],entry[1])
		await place(world.wider_world.pyramid.to_global(Vector3(65.5,.15,0)))
		var label: String = String(entry[0])+(" sheathed" if entry[1] else " drawn")
		await transition(entry[2],label+" entry")
		if "--repro" in OS.get_cmdline_user_args(): break
		await place(Vector3(0,.05,1.5))
		await transition(entry[3],label+" exit")
		if not entry[1]:
			var serial: int = p.weapon_combat.attack_serial
			for pressed: bool in [true,false]:
				var button := InputEventJoypadButton.new()
				button.button_index = JOY_BUTTON_RIGHT_SHOULDER
				button.pressed = pressed
				Input.parse_input_event(button)
				await frames(1)
			check(p.weapon_combat.attack_serial==serial+1 and not p.weapon_combat.active_move.is_empty(),label+": a fresh light attack works normally after exit")
			await frames(hz)
	world.queue_free()
	controls.queue_free()
	await frames(2)
	print("Dungeon drawn weapons verification: ",checks," checks, ",failures," failures @",hz," Hz")
	quit(1 if failures else 0)
