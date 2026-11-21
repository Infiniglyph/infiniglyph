extends "res://tests/equation_tracing.gd"
const Database=preload("res://scripts/equipment_database.gd")
const Library=preload("res://scripts/weapon_library.gd")
const Brush=preload("res://scripts/paintbrush_moves.gd")
const Temple=preload("res://scripts/dungeon_glyphs.gd")
const WandEffect=preload("res://scripts/wand_effect.gd")
const Filters=preload("res://scripts/equipment_filters.gd")

func wear(id: StringName) -> Node3D:
	w.cancel(); p.combat.blocking=false; p.combat.sheathed=false
	var item: Resource=Catalog.create(id); p.inventory.add_item(item); p.inventory.assign(&"down",item.instance_id)
	p.combat.selected_slot=&"down"; w.sync_rig()
	return w.rig.models[id].right

func pose(count: int=1) -> void:
	for i in range(count):
		p.visual.animate(1.0/hz,Vector3.ZERO,p.is_on_floor())
		w._physics_process(1.0/hz)
	if is_instance_valid(w.rig.caster_guard): w.rig.caster_guard._process(0)

func review(label: String,focus: Vector3=Vector3(0,1.15,0),offset: Vector3=Vector3(-2.7,1.7,3.2)) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	view.make_current()
	view.projection=Camera3D.PROJECTION_ORTHOGONAL if label=="hieroglyphs" else Camera3D.PROJECTION_PERSPECTIVE
	if label=="hieroglyphs": view.size=8.4
	view.global_position=p.position+offset; view.look_at(p.position+focus)
	await process_frame; await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/caster_"+label+".png")

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Caster visuals watchdog"); quit(2))
	scene=Node3D.new(); root.add_child(scene)
	var floor_body:=StaticBody3D.new(); var collision:=CollisionShape3D.new(); var box:=BoxShape3D.new()
	box.size=Vector3(60,1,60); collision.shape=box; floor_body.add_child(collision); floor_body.position.y=-.5; scene.add_child(floor_body)
	view=Camera3D.new(); view.fov=42; scene.add_child(view); view.current=true
	p=make_player(Vector3(0,.02,0)); w=p.weapon_combat; p.camera_rig.yaw=PI
	await frames(20); p.set_physics_process(false); p.velocity=Vector3.ZERO
	var controller:=p.global_transform
	wear(&"dark_box_arc_wand"); pose(60)
	var shoulder: Node3D=p.visual.joints.LeftArm
	var elbow: Node3D=shoulder.get_node("Hinge")
	var upper: Vector3=(elbow.global_position-shoulder.global_position).normalized()
	var forearm: Vector3=(w.rig.left_hand.global_position-elbow.global_position).normalized()
	var angle:=rad_to_deg(asin(clampf(forearm.y,-1,1)))
	check(upper.dot(Vector3.DOWN)>.98 and absf(angle-45)<3,"Wand carry has a hanging upper right arm and a forearm rising at 45 degrees")
	var right_foot: Vector3=p.visual.to_local(p.visual.joints.LeftLeg.get_node("Hinge").to_global(Vector3(0,-.45,0)))
	var left_foot: Vector3=p.visual.to_local(p.visual.joints.RightLeg.get_node("Hinge").to_global(Vector3(0,-.45,0)))
	check(right_foot.z>left_foot.z+.25 and p.visual.chest.global_basis.z.dot(p.visual.global_basis.x)<-.15,"The wand stance turns right, with the anatomical right foot forward and left foot back")
	check(w.rig.right_hand.global_position.y<w.rig.left_hand.global_position.y-.2,"The empty rear hand hangs down beside the body")
	var rear_elbow: Node3D=p.visual.joints.RightArm.get_node("Hinge")
	check((w.rig.right_hand.global_position-rear_elbow.global_position).normalized().dot(Vector3.DOWN)>.98,"The rear forearm hangs relaxed instead of resting on the hip")
	await review("wand_ready")
	p.combat.blocking=true; w._on_block(true); pose(30)
	var ward: Node3D=w.rig.caster_guard
	check(ward.visible and (ward.global_position-p.combat_point()).dot(w.aim_direction())>.6,"Blocking with a wand displays its magic circle in front of the caster")
	check(ward.find_children("*","CollisionObject3D",true,false).is_empty() and w.total_hits==0,"The ward is cosmetic and introduces no extra hitboxes or damage pulses")
	await review("wand_block")
	p.combat.blocking=false; pose()
	check(not ward.visible,"Releasing block removes the wand circle immediately")
	p.combat.blocking=true; p.combat.sheathed=true; w.sync_rig(); pose()
	check(not ward.visible,"Sheathing suppresses the magic circle even if block is held")
	wear(&"paintbrush_ember"); p.combat.blocking=true; w._on_block(true)
	var start:=Vector3.ZERO; var span:=0.0; var error:=0.0
	for i in range(150):
		pose()
		var tip: Vector3=w.rig.left_hand.to_global(Brush.TIP)
		if i==0: start=tip
		span=maxf(span,tip.distance_to(start))
		var desired: Vector3=Brush.guard_frame(p,w.aim_direction())*Brush.guard_pen(w.guard_visual_time)
		error=maxf(error,tip.distance_to(desired))
	check(span>.3 and error<.09,"Paintbrush blocking visibly draws concentric circles with the actual right arm and held nib")
	check(ward.visible and ward._surfaces.size()==1 and ward._surfaces[0].mesh.surface_get_material(0).albedo_color.is_equal_approx(Color(Database.get_item(&"paintbrush_ember").geometry.tint)),"The painter's concentric guard keeps the equipped pigment")
	check((ward.global_transform*Brush.guard_pen(w.guard_visual_time)).distance_to(w.rig.left_hand.to_global(Brush.TIP))<.001,"The guard drawing stays attached to the solved brush tip")
	await review("paint_block")
	p.transition_locked=true; ward._process(0)
	check(not ward.visible,"Instance transitions hide the cosmetic block drawing")
	p.transition_locked=false; p.combat.blocking=false
	for id: StringName in [&"thothic_scepter",&"ahkmets_scepter"]:
		var model:=wear(id); var entry:=Database.get_item(id)
		var casts:=true
		for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			var move:=Library.move(id,action)
			casts=casts and move.get("weapon_family")=="wand" and move.get("wand_attack") in ["flick","slither","volley","ground","wheel"]
		check(casts and entry.combat_kind=="wand" and Filters.matches(Catalog.get_definition(id),Filters.WEAPON_NAMES.find("WANDS")),String(id)+" uses all wand casts and the WANDS inventory filter")
		check(model.name=="ArcWand" and model.has_node("TempleFocusEmblem"),String(id)+" keeps a bounded temple-themed wand focus")
		var owned: Resource=p.inventory.equipped_item(&"down"); var identity: String=owned.instance_id
		check(p.inventory.restore(JSON.parse_string(JSON.stringify(p.inventory.serialize()))) and p.inventory.equipped_item(&"down").instance_id==identity,"Existing "+String(id)+" identities survive the equipment conversion and reload")
		var before:=scene.get_children().filter(func(node): return node is WandEffect).size()
		w.sync_rig(); w._begin(Library.move(id,&"attack_right")); pose(ceili(hz*.22))
		check(scene.get_children().filter(func(node): return node is WandEffect).size()==before+1,String(id)+" actually releases its wand laser through shared combat")
	var grimoire:=wear(&"scribes_grimoire"); grimoire.stow_amount=0; pose(30)
	var symbols:=true; var bounded:=true
	for sequences: Array in Database.get_item(&"scribes_grimoire").moves.values():
		for move: Dictionary in sequences:
			symbols=symbols and move.get("writing_system")=="hieroglyphic" and not move.has("equation") and not move.get("inscription",[]).is_empty()
			bounded=bounded and Moves.strokes(move).size()/2<=grimoire.STROKE_LIMIT and move.reach==7.0
	check(symbols and bounded,"Every Egyptian Scribe move uses bounded hieroglyph geometry instead of mathematical expressions")
	check(grimoire.leaves[0].get_child(2).mesh==Temple.mesh(0) and grimoire.turning_page.get_child(2).mesh==Temple.mesh(1),"The temple codex pages display real ankh and eye meshes")
	var move:=Library.move(&"scribes_grimoire",&"special_x")
	grimoire.write(move,float(move.hits[0]),Vector3.BACK)
	check(grimoire.active_points==Moves.strokes(move) and grimoire.ink.multimesh.visible_instance_count>0,"Visible Egyptian calligraphy uses the same strokes as hit detection")
	grimoire.set_process(false)
	await review("hieroglyphs",Vector3(0,1,3.5),Vector3(7,5,12))
	wear(&"eturnull_manuscript")
	var original:=Library.move(&"eturnull_manuscript",&"special_x")
	check(original.has("equation") and not original.has("writing_system") and not w.rig.caster_guard.visible,"Eturnull retains mathematical writing and other weapons do not inherit the ward")
	check(p.global_transform==controller and p.velocity.is_zero_approx(),"All new stance and block visuals leave controller position, rotation and momentum alone")
	scene.queue_free(); await process_frame
	print("CASTER VISUALS: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
