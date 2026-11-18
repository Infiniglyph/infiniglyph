extends "res://tests/equation_tracing.gd"
## Audit shipped definitions, then use real bumper input and the live combat
## clock to verify the next action survives buffering and starts in recovery.
const Database = preload("res://scripts/equipment_database.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Flow = preload("res://scripts/reference_weapon_flow.gd")
const Source = preload("res://scripts/equipment_moves.gd")
var starts: Array[Dictionary] = []
var finished: Array[Dictionary] = []

func step() -> void:
	p.visual.animate(1.0/hz,p.velocity,p.is_on_floor())
	w._physics_process(1.0/hz)
	await physics_frame
	await process_frame

func own(entry: Dictionary) -> void:
	w.cancel()
	controls.reset_combat_input()
	var item: Resource = Catalog.create(StringName(entry.id))
	p.inventory.add_item(item)
	p.inventory.assign(&"right",item.instance_id)
	p.combat.selected_slot = &"right"
	p.combat.sheathed = false
	w.sync_rig()

func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	var representatives := {}
	var count := 0
	var timing := true
	var identity := true
	var faster := 0
	for entry: Dictionary in Database.all():
		if not entry.has("motion_set") or not Flow.TEMPO.has(entry.family): continue
		var raw: Dictionary = Source.move(entry,&"attack_right",0,false)
		var move: Dictionary = Library.move(StringName(entry.id),&"attack_right")
		var art: Dictionary = Library.charged_move(StringName(entry.id),&"special_x",1)
		count += 1
		if move.duration<raw.duration-.01: faster += 1
		timing = timing and move.duration<=Flow.TEMPO[entry.family].x+.071 and move.hits[0]>=move.windup and move.hits[-1]<move.chain_open and move.chain_open<=move.duration and art.chain_open>art.hits[-1] and art.chain_open<=art.duration
		identity = identity and move.clip_id==raw.clip_id and move.damage==raw.damage and move.reach==raw.reach and move.motion==raw.motion and move.hits.size()==raw.hits.size() and is_equal_approx(move.hits[0]/move.duration,raw.hits[0]/raw.duration)
		if not representatives.has(entry.motion_set.cut): representatives[entry.motion_set.cut] = entry
	check(count>1600 and faster>1500 and timing,"All reference weapon families have compact valid timing, including charged pulses; "+str(faster)+" slow definitions accelerated")
	check(identity,"Tempo preserves each weapon's clip, complete gesture, damage, reach and pulse count")
	for slot: StringName in Library.LOADOUTS:
		var move: Dictionary = Library.move(slot,&"attack_right")
		check(not move.has("reference_flow") and move.duration=={&"down":.52,&"left":.50,&"right":.43,&"up":.34}[slot],"The basic "+String(slot)+" weapon retains its existing handling")
	check(not Library.move(&"eturnull_manuscript",&"attack_right").has("reference_flow") and not Library.move(&"paintbrush_violet",&"attack_right").has("reference_flow"),"Scribe and Paintbrush retain their existing timing and presentation")
	var smooth := {"duration":1.0,"hits":[.4],"motion_contact":.4,"retargeted":true,"reference_flow":true,"flow_right":Vector3.ZERO,"flow_left":Vector3.ZERO,"flow_right_rotation":Vector3.ZERO,"flow_left_rotation":Vector3.ZERO,"motion":[]}
	for value in [0.0,1.0,1.4,2.0]:
		var frame := {"t":smooth.motion.size()/3.0}
		for key: String in ["right","left","right_rotation","left_rotation","hip","chest"]: frame[key] = [value,value*2,value*3]
		smooth.motion.append(frame)
	var velocity_ok := true
	for key_time in [1.0/3,2.0/3]:
		var at: Vector3 = preload("res://scripts/weapon_motion.gd").sample(smooth,key_time).right
		var before: Vector3 = preload("res://scripts/weapon_motion.gd").sample(smooth,key_time-.0001).right
		var after: Vector3 = preload("res://scripts/weapon_motion.gd").sample(smooth,key_time+.0001).right
		velocity_ok = velocity_ok and ((at-before)-(after-at)).length()/.0001<.03
	check(velocity_ok,"Reference playback crosses sampled keys without a velocity corner or lost authored turns")
	scene = Node3D.new()
	root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(100,2,100)
	floor_body.position.y = -1
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	p = make_player(Vector3(0,.02,0))
	controls = p.controls
	w = p.weapon_combat
	await frames(hz/3)
	p.set_physics_process(false)
	var physical_start := p.global_transform
	var velocity_start := p.velocity
	w.attack_started.connect(func(move: Dictionary): starts.append(move.duplicate(true)))
	w.attack_finished.connect(func(move: Dictionary,_hits: int): finished.append(move.duplicate(true)))
	for cut: String in representatives:
		own(representatives[cut])
		starts.clear()
		finished.clear()
		pad(JOY_BUTTON_RIGHT_SHOULDER)
		pad(JOY_BUTTON_RIGHT_SHOULDER,false)
		var first: Dictionary = w.active_move.duplicate(true)
		await step()
		pad(JOY_BUTTON_LEFT_SHOULDER)
		pad(JOY_BUTTON_LEFT_SHOULDER,false)
		var age := 1.0/hz
		while starts.size()<2 and age<float(first.duration)+.12:
			await step()
			age += 1.0/hz
		check(starts.size()==2 and finished.size()==1 and age<=float(first.chain_open)+3.0/hz and age<float(first.duration)+1.0/hz and starts[-1].combo_index==1,"Early bumper input survives and chains during "+cut+" follow-through (%.3f s)" % age)
		check(w.rig.right_hand.global_transform.is_finite() and w.rig.left_hand.global_transform.is_finite() and w._flow_blend_remaining>0,"The "+cut+" combo hands off the presented grip smoothly")
		w.cancel()
		p.inventory.take_item(p.inventory.equipped_item(&"right").instance_id,1)
	# Staff continuation must remain visible after its contact, and return to
	# the exact authored endpoints rather than adding permanent grip drift.
	var staff: Dictionary = Library.move(StringName(representatives.conduit.id),&"attack_right")
	var raw_staff := staff.duplicate(true)
	raw_staff.reference_flow = false
	var t := float(staff.hits[0])+(float(staff.duration)-float(staff.hits[0]))*.30
	var motion = preload("res://scripts/weapon_motion.gd")
	check(motion.sample(staff,t).right.distance_to(motion.sample(raw_staff,t).right)>.025 and motion.sample(staff,staff.duration).right.distance_to(motion.sample(raw_staff,staff.duration).right)<.001,"Staff follow-through continues beyond contact and settles without changing the final grip")
	check(p.global_transform==physical_start and p.velocity==velocity_start,"Weapon flow leaves the physical transform and carried movement unchanged")
	scene.queue_free()
	await frames()
	print("REFERENCE WEAPON FLOW: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
