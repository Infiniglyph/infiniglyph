extends "res://tests/equation_tracing.gd"
## Real input/IK and the shared live hurt-shape resolver at each supported rate.
const Database = preload("res://scripts/equipment_database.gd")
const BrushMoves = preload("res://scripts/paintbrush_moves.gd")
const Pattern = preload("res://scripts/paintbrush_patterns.gd")
const ItemType = preload("res://scripts/inventory_item_type.gd")
const COLORS := ["cyan","violet","gold","mint","pink","blue","silver","ember"]

func frames(count: int = 2, animate: bool = false) -> void:
	for i in range(count):
		if animate:
			# This fixture advances the weapon manually. Advance its trail clock
			# once too, rather than mixing manual samples with render-dependent
			# physics catch-up. The movement/reflection cases below use live physics.
			p.visual.animate(1.0/hz,p.velocity,p.is_on_floor())
			w._physics_process(1.0/hz)
			if is_instance_valid(w.paint_trace):
				w.paint_trace.set_physics_process(false)
				w.paint_trace._physics_process(1.0/hz)
				w.paint_trace.set_physics_process(false)
		await physics_frame
		await process_frame

func equip_brush(color: String = "violet") -> Node3D:
	w.cancel()
	controls.reset_combat_input()
	var item: Resource = Catalog.create(StringName("paintbrush_"+color))
	p.inventory.add_item(item)
	p.inventory.assign(&"down",item.instance_id)
	p.combat.selected_slot = &"down"
	p.combat.sheathed = false
	w.sync_rig()
	return w.rig.models[StringName("paintbrush_"+color)].right

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	scene = Node3D.new()
	root.add_child(scene)
	view = Camera3D.new()
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
	var brush: Node3D
	for color: String in COLORS:
		brush = equip_brush(color)
		var id := StringName("paintbrush_"+color)
		var entry: Dictionary = Database.get_item(id)
		check(Database.valid(entry) and ItemType.label(Catalog.get_definition(id))=="Paintbrush" and w.loadout(&"down").id==&"paintbrush","Registered/equippable Paintbrush edition: "+color)
		trace = w.ensure_paint_trace()
		trace.append_section(PackedVector3Array([Vector3(60,2,COLORS.find(color)),Vector3(61,2,COLORS.find(color))]))
		check(trace.section_color(trace.sections[-1]).is_equal_approx(Color(entry.geometry.tint)),"New paint matches brush pigment: "+color)
	var retained_colors := true
	trace.redraw()
	for i in range(COLORS.size()):
		var pigment := Color(Database.get_item(StringName("paintbrush_"+COLORS[i])).geometry.tint)
		retained_colors = retained_colors and trace.section_color(trace.sections[i]).is_equal_approx(pigment)
		if DisplayServer.get_name()!="headless": retained_colors = retained_colors and trace.multimesh.get_instance_color(i).to_html(false)==pigment.to_html(false)
	check(retained_colors,"Old paint retains its pigment through color switches (batch readback verified in native rendering)")
	check(not trace.mathematical and trace.get_child_count()==0 and trace._ink.emission_operator==BaseMaterial3D.EMISSION_OP_MULTIPLY,"Paint uses one smooth batch with pigment-preserving emission and no equation decoration")
	check(w.paintbrush_settings!=w.equation_trace_settings and is_equal_approx(w.paintbrush_settings.damage,30) and is_equal_approx(w.equation_trace_settings.damage,30),"Brush tuning is independent of Manuscript tuning and starts at balanced 30 damage")
	var saved: Dictionary = p.inventory.serialize()
	check(p.inventory.restore(saved) and p.inventory.equipped_item(&"down").item_type_id==&"paintbrush_ember","Existing inventory persistence restores the exact equipped brush color")
	await frames(hz/2,true)
	brush = w.rig.models[&"paintbrush_ember"].right
	check(brush.get_parent()==w.rig.left_hand and brush.get_node("BrushTip").global_position.distance_to(w.rig.left_hand.to_global(BrushMoves.TIP))<.001,"Physical brush and tip attach to anatomical right hand")
	check(w.rig.models[&"paintbrush_ember"].left.get_child_count()==0 and not w.rig.models.has(&"eturnull_manuscript"),"Empty offhand contains no book or floating quill")
	check(w.rig.left_hand.global_basis.y.normalized().dot(Vector3.UP)>.999 and w.rig.right_hand.global_position.y<w.rig.left_hand.global_position.y-.1,"Ready brush stays upright with its empty supporting hand lowered")
	check(w.body.phase_label=="paintbrush-ready" and p.visual.chest.global_basis.y.dot(p.visual.global_basis.z)>.06,"Forward-leaning martial ready stance is distinct from the Scribe rear-foot stance")
	trace.clear()
	rt(1)
	await frames(hz/4,true)
	check(trace.action==&"" and trace.sections.is_empty() and w.active_move.is_empty(),"RT alone never generates paint or an attack")
	rt(0)
	var target := Target.new()
	target.health = 100000
	target.max_health = 100000
	target.counterattacks = false
	scene.add_child(target)
	target.position = Vector3(40,0,40)
	target.set_physics_process(false)
	var slopes: Array[float] = []
	for button: JoyButton in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:
		w.cancel()
		trace.clear()
		pad(button)
		pad(button,false)
		await frames(ceili(hz*.40),true)
		check(trace.sections.size()>2 and w.active_move.is_empty() and trace.light.is_empty(),"Bumper creates a short persistent stroke with quick recovery: "+str(button))
		if trace.sections.is_empty(): quit(1); return
		var a: Vector3 = trace.sections[0].points[0]
		var b: Vector3 = trace.sections[-1].points[-1]
		var direction: Vector3 = Moves.writing_basis(w.trace_aim_direction()).inverse()*(b-a)
		slopes.append(direction.x*direction.y)
		check(a.distance_to(b)>.25 and a.distance_to(b)<1.5 and trace.sections.all(func(s: Dictionary): return s.points.size()==2 and is_equal_approx(s.damage,30)),"Light attack writes actual brush-tip segments at configured damage and close range")
		trace.set_physics_process(false)
		# Keep the sentry's separate solid pedestal below the incoming line of
		# sight. The stroke meets the upper capsule rather than its floor plinth.
		target.position = a-Vector3.UP*1.35
		await frames()
		var before: float = target.total_damage
		trace.resolve_contacts()
		check(is_equal_approx(target.total_damage-before,30),"A real target takes 30 from the suspended light stroke")
		trace.resolve_contacts()
		check(is_equal_approx(target.total_damage-before,30),"Overlapping light-stroke segments share the half-second victim cooldown")
		target.position = Vector3(40,0,40)
	check(slopes[0]*slopes[1]<0,"LB and RB paint genuinely opposing diagonal strokes")
	for index in range(4):
		w.cancel()
		trace.clear()
		var modified := index>=2
		var button: JoyButton = JOY_BUTTON_X if index%2==0 else JOY_BUTTON_Y
		if modified: rt(1)
		pad(button)
		pad(button,false)
		if modified: rt(0)
		check(trace.sections.size()==1 and trace.sections[0].points.size()==[8,6,4,32][index] and trace.sections[0].bounds.size.length()<.25,"Tiny tap draws the actual small "+BrushMoves.ART_NAMES[index])
		check(p.combat.charge_action==&"" and p.combat.trace_action==&"" and w.active_move.is_empty(),"A paint tap never turns into a charge/release attack")
		trace.clear()
		if modified: rt(1)
		pad(button)
		await frames(hz/2,true)
		var count: int = trace.sections.size()
		check(count>minf(hz,1.0/trace.settings.sampling_interval)/5 and p.combat.trace_action!=&"" and p.combat.charge_action==&"","Holding continuously paints "+BrushMoves.ART_NAMES[index])
		var old_point: Vector3 = trace.sections[0].points[0]
		for i in range(hz/3):
			p.position += Vector3(.035,.01,-.03)
			await frames(1,true)
		check(trace.sections.size()>count and trace.sections[0].points[0]==old_point,"New paint follows 3D travel while older shapes stay fixed")
		check(trace.nib_position().distance_to(trace._last)<.08 and brush.get_node("BrushTip").global_position.distance_to(trace.nib_position())<.001,"Visible nib, solved right hand and recorded stroke agree")
		check(trace.sections.slice(1).all(func(s: Dictionary): return s.points.size()==2),"Held paint has continuous strokes and no mathematical symbols")
		pad(button,false)
		if modified: rt(0)
		count = trace.sections.size()
		await frames(hz/8,true)
		check(trace.action==&"" and trace.sections.size()==count,"Release immediately stops new paint and preserves the existing trail")
		trace.set_physics_process(false)
		var point: Vector3 = trace.sections[-1].points[-1]
		target.position = point-Vector3.UP*1.35
		await frames()
		var before: float = target.total_damage
		trace.resolve_contacts()
		check(is_equal_approx(target.total_damage-before,30),"Released geometry remains hazardous: "+BrushMoves.ART_NAMES[index])
		target.position = Vector3(40,0,40)
	# The real controller remains unrestricted during an unmodified triangle.
	trace.clear()
	p.position = Vector3(0,.02,10)
	p.velocity = Vector3.ZERO
	p.set_physics_process(true)
	w.set_physics_process(true)
	await frames(hz/4)
	key(KEY_R)
	controls.move = Vector2.UP
	controls.boost = true
	await frames(hz/5)
	key(KEY_SPACE)
	await frames(hz/5)
	key(KEY_SPACE,false)
	var altitude: float = p.position.y
	key(KEY_SPACE)
	await frames(hz/5)
	key(KEY_SPACE,false)
	check(p.last_sky_impulse.y>0 and p.position.y>altitude and p.combat.trace_action==&"special_y" and not controls.special_modified(),"Unmodified triangle tracing stays active through jump and Sky Jump")
	check(p.boost_active and p.position.z<8 and trace.sections.any(func(s: Dictionary): return s.bounds.get_center().y>2),"Sprint momentum produces aerial paint without movement restrictions")
	controls.request_dodge()
	await frames(2)
	check(p.combat.trace_action==&"" and trace.action==&"" and not trace.sections.is_empty(),"Dodge cancels drawing while existing paint expires naturally")
	key(KEY_R,false)
	controls.move = Vector2.ZERO
	controls.boost = false
	p.set_physics_process(false)
	w.set_physics_process(false)
	p.dodge.cancel()
	w.clear_stagger()
	trace.clear()
	p.position = Vector3(0,.02,-3)
	p.velocity = Vector3.ZERO
	var defender := make_player(Vector3(0,.02,0))
	defender.add_to_group("combat_targets")
	await frames(3)
	defender.set_physics_process(false)
	defender.combat.blocking = true
	defender.weapon_combat.parry_remaining = .18
	var center: Vector3 = defender.combat_point()+Vector3(0,0,-.2)
	trace.append_section(PackedVector3Array([center-Vector3.RIGHT*.4,center+Vector3.RIGHT*.4]))
	var born: float = trace.sections[0].born
	var hp: float = defender.health
	trace.resolve_contacts()
	check(defender.weapon_combat.last_parried and defender.health==hp and w.forced_state==&"parried" and is_equal_approx(w.stagger_remaining,1),"A shared timed parry negates paint and applies the existing one-second attacker stun")
	check(trace.sections[0].reflected and trace.sections[0].owner.get_ref()==defender and trace.sections[0].velocity.z<0 and trace.sections[0].born==born,"Intercepted paint changes allegiance and moves in defender facing without refreshing lifetime")
	check(trace.section_color(trace.sections[0]).is_equal_approx(Color(Database.get_item(&"paintbrush_ember").geometry.tint)),"Reflected paint keeps the originating brush pigment")
	w.clear_stagger()
	p.combat.blocking = true
	p.camera_rig.yaw = PI
	w.parry_remaining = .18
	trace.set_physics_process(true)
	var author_hp: float = p.health
	await frames(hz/2)
	check(p.health<author_hp and not w.last_parried and defender.health==hp,"Redirected paint can hit its author, cannot be parried again, and leaves its defender safe")
	p.combat.blocking = false
	defender.combat.blocking = false
	defender.position = Vector3(40,0,-40)
	trace.clear()
	p.camera_rig.yaw = 0
	key(KEY_F)
	var own_hp: float = p.health
	w.receive_hit(30,p.combat_point()+Vector3.FORWARD*2,defender,{"damage":30,"parryable":true,"action":&"attack_right"})
	check(w.last_parried and p.health==own_hp,"The equipped brush uses the normal defensive parry")
	w.parry_remaining = 0
	w.receive_hit(30,p.combat_point()+Vector3.FORWARD*2,defender,{"damage":30,"parryable":true,"action":&"attack_right"})
	check(w.last_blocked and own_hp-p.health>0 and own_hp-p.health<30,"The brush's 60-percent block power uses the existing guard system")
	key(KEY_F,false)
	trace.clear()
	trace.append_section(PackedVector3Array([Vector3(5,3,0),Vector3(6,3,0)]))
	trace.time += float(trace.settings.lifetime)-float(trace.settings.fade_duration)*.5
	trace.redraw()
	check(trace.section_opacity(trace.sections[0])>.4 and trace.section_opacity(trace.sections[0])<.6,"Paint visibly fades near the end of its configured lifetime")
	trace._physics_process(1)
	check(trace.sections.is_empty() and trace.multimesh.visible_instance_count==0 and not trace.is_physics_processing(),"Expired paint removes both visuals and hazards")
	for i in range(1200): trace.append_section(PackedVector3Array([Vector3(i*.01,4,0),Vector3(i*.01+.01,4,0)]))
	trace.redraw()
	check(trace.sections.size()<=trace.settings.maximum_sections and trace.multimesh.visible_instance_count<=trace.settings.maximum_strokes and trace.get_child_count()==0,"Extended painting obeys bounded geometry without per-stroke nodes")
	trace.clear()
	key(KEY_Q)
	key(KEY_V)
	check(p.combat.trace_action==&"special_x","Pressing RT/V mid-square keeps the shape selected on the original press")
	controls.set_gameplay_enabled(false)
	check(p.combat.trace_action==&"" and trace.action==&"","Menus/focus cancel drawing without pausing the simulation")
	controls.set_gameplay_enabled(true)
	key(KEY_Q)
	p.combat.sheathed = true
	p.combat.sheathed_changed.emit(true)
	check(trace.action==&"" and not brush.visible and w.rig.models[&"paintbrush_ember"].stowed.visible,"Sheathing hides the held brush and uses its normal back mount")
	key(KEY_Q,false)
	p.combat.sheathed = false
	w.sync_rig()
	key(KEY_Q)
	key(KEY_RIGHT)
	key(KEY_RIGHT,false)
	check(trace.action==&"" and w.rig.selected==&"right","Weapon switching cancels paint and equips the other weapon normally")
	w.reset()
	check(trace.sections.is_empty(),"Death/respawn reset clears residual paint and reflected ownership")
	check(is_equal_approx(preload("res://scripts/vehicle_light_wave.gd").DAMAGE,750) and is_equal_approx(w.equation_trace_settings.damage,30),"Vehicle trail and Manuscript balance remain unchanged")
	print("PAINTBRUSH: ",checks," checks, ",failures," failures at ",hz," Hz")
	scene.queue_free()
	await frames(2)
	quit(1 if failures else 0)
