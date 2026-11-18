extends "res://tests/whip_discs.gd"
const Motion = preload("res://scripts/weapon_motion.gd")

func shot(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	q.visual.hide()
	camera.position=Vector3(.7,1.9,-4.0) if label.ends_with("stow") else Vector3(2.8,2.5,4.2)
	camera.look_at(Vector3(0,1.15,0))
	camera.current=true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/"+label+".png")
	q.visual.show()

func pose_at(time: float=0) -> void:
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	for i in range(24):
		p.visual.animate(1.0/60,Vector3.ZERO,true)
		p.weapon_combat.elapsed=time
		p.weapon_combat.apply_pose(1.0/60)

func run() -> void:
	create_timer(50).timeout.connect(func():push_error("DISC REFINEMENT WATCHDOG");quit(2))
	arena=Node3D.new()
	root.add_child(arena)
	camera=Camera3D.new()
	arena.add_child(camera)
	var floor:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(60,1,60)
	shape.shape=box
	floor.add_child(shape)
	floor.position.y=-.5
	arena.add_child(floor)
	p=fighter(Vector3(0,.02,0))
	q=fighter(Vector3(0,.02,5))
	await frames(5)
	for id: StringName in [&"vector_disc",&"twin_vector_discs"]:
		equip(id)
		pose_at()
		var rig: Node3D=p.weapon_combat.rig
		check(rig.right_hand.global_basis.y.dot(Vector3.UP)<-.9,"Disc ready carry points down: "+String(id))
		check(absf(rig.right_hand.global_basis.z.dot(p.visual.chest.global_basis.x))>.9,"Disc face turns sideways to clear the body")
		await shot("disc_refined_"+String(id)+"_ready")
		if id==&"twin_vector_discs":
			check(rig.left_hand.global_basis.y.dot(Vector3.UP)<-.9,"Offhand disc also points down")
			check(absf(rig.left_hand.global_basis.z.dot(p.visual.chest.global_basis.x))>.9,"Offhand disc also turns sideways")
		p.combat.sheathed=true
		p.weapon_combat.sync_rig()
		var blades: Array=rig.models[id].stowed_blades
		var centered:=true
		for blade: Node3D in blades:
			var center: Vector3=p.visual.chest.to_local(blade.to_global(Vector3(0,.18,0)))
			centered=centered and center.y>.28 and center.y<.39
		check(centered,"Stowed discs sit higher on the back")
		if id==&"vector_disc": check(absf(blades[0].position.x)<.001,"Single stowed disc is centered")
		await shot("disc_refined_"+String(id)+"_stow")
	if "--poses-only" in OS.get_cmdline_user_args():
		for action: StringName in [&"special_rt_x",&"special_rt_y"]:
			equip(&"vector_disc")
			p.weapon_combat._on_action(action,&"down")
			pose_at(.48)
			await shot("disc_"+String(action)+"_gym")
		print("DISC NATIVE POSES: six captures")
		quit()
		return
	# Measure the actual returning centerline, not a decorative effect.
	equip(&"vector_disc")
	p.set_physics_process(true)
	p.weapon_combat.set_physics_process(true)
	cast()
	var bend:=0.0
	var returned:=false
	for tick in range(ceili(hz*1.5)):
		for disc in p.weapon_combat.flying_discs:
			if not is_instance_valid(disc): continue
			if disc.returning:
				returned=true
				var a: Vector3=disc._return_start
				var b: Vector3=disc.hand.global_position
				var chord:=b-a
				var t:=clampf((disc.global_position-a).dot(chord)/maxf(.001,chord.length_squared()),0,1)
				bend=maxf(bend,disc.global_position.distance_to(a.lerp(b,t)))
		await frames(1)
	check(returned and bend>1.3,"Disc follows a broad circular return arc")
	check(p.weapon_combat.rig.models[&"vector_disc"].right.visible,"Curved return catches and restores the held disc")
	for action: StringName in [&"special_rt_x",&"special_rt_y"]:
		equip(&"vector_disc")
		var move:=Library.move(&"vector_disc",action)
		var charged:=Library.charged_move(&"vector_disc",action,1)
		check(move.disc_gym and move.disc_flight>=2 and charged.hits==[.48] and charged.reach==7,"RT arts retain gymnastic release timing when charged")
		var a:=Motion.sample(move,float(move.hits[0]))
		var b:=Motion.sample(move,float(move.duration)*.8)
		check(a.has("left_leg") and a.left_leg.distance_to(a.right_leg)>.5 and a.hip.distance_to(b.hip)>1,"RT art has full-body rotation and scissoring leg motion")
		p.weapon_combat._on_action(action,&"down")
		pose_at(float(move.hits[0]))
		await shot("disc_"+String(action)+"_gym")
		pose_at(float(move.duration))
		p.weapon_combat.cancel()
		p.visual.animate(1.0/60,Vector3.ZERO,true)
		p.weapon_combat.apply_pose(1.0/60)
		check(p.weapon_combat.body.hips.value.length()<.4,"Completed flip recovers without unwinding a full revolution")
		p.set_physics_process(true)
		p.weapon_combat.set_physics_process(true)
		q.weapon_combat.reset()
		p.weapon_combat._on_action(action,&"down")
		var lateral:=0.0
		var altitude:=0.0
		for tick in range(ceili(hz*1.75)):
			for disc in p.weapon_combat.flying_discs:
				if not is_instance_valid(disc) or disc.returning: continue
				var line: Vector3=disc.global_position-disc._start-disc.direction*disc.travelled
				lateral=maxf(lateral,absf(line.x))
				altitude=maxf(altitude,absf(line.y))
			await frames(1)
		check(lateral>.5 or altitude>.5,"RT art launches on an angled curved path")
		check(q.health<q.weapon_combat.max_health,"Angled RT throw converges on the locked target")
	# Body flips must remain visual: running displacement is still identical.
	var displacements: Array[Vector3]=[]
	for attack: bool in [false,true]:
		equip(&"vector_disc")
		p.target_lock.clear()
		p.controls.move=Vector2(1,0)
		p.controls.sprint=true
		if attack: p.weapon_combat._on_action(&"special_rt_x",&"down")
		await frames(hz)
		displacements.append(p.global_position)
		p.controls.move=Vector2.ZERO
		p.controls.sprint=false
	check(displacements[0].distance_to(displacements[1])<.05,"Gymnastic throws preserve normal running acceleration and displacement")
	arena.queue_free()
	await frames(2)
	print("DISC REFINEMENT ",hz," HZ: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
