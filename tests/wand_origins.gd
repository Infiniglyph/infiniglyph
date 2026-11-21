extends "res://tests/equation_tracing.gd"
const Library=preload("res://scripts/weapon_library.gd")
const Laser=preload("res://scripts/wand_effect.gd")
var released: Array[Node3D]=[]

func review(action: StringName,cast: Node3D) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	cast.set_physics_process(false); cast._physics_process(.02)
	view.make_current(); view.fov=44
	view.position=p.position+Vector3(-2.8,1.9,3.5); view.look_at(p.position+Vector3(0,1.1,.5))
	await process_frame; await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/wand_origin_"+String(action)+".png")

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	scene=Node3D.new(); root.add_child(scene)
	var floor_body:=StaticBody3D.new(); var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new()
	box.size=Vector3(10000,1,10000); shape.shape=box; floor_body.add_child(shape); floor_body.position.y=-.5; scene.add_child(floor_body)
	view=Camera3D.new(); scene.add_child(view)
	p=make_player(Vector3(0,.02,0)); w=p.weapon_combat; p.camera_rig.yaw=PI
	await frames(10); p.set_physics_process(false); p.velocity=Vector3.ZERO
	p.combat.sheathed=false
	scene.child_entered_tree.connect(func(node):
		if node is Laser: released.append(node))
	for id: StringName in [&"dark_box_arc_wand",&"arc_wand_ember",&"thothic_scepter",&"ahkmets_scepter"]:
		var owned: Resource=Catalog.create(id); p.inventory.add_item(owned); p.inventory.assign(&"down",owned.instance_id); p.combat.selected_slot=&"down"; w.sync_rig()
		for yaw: float in [0,1.3,PI]:
			p.position=Vector3(1600+50*yaw,.02,-1200); p.visual.rotation.y=yaw
			for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
				w.cancel(); w._begin(Library.move(id,action)); released.clear()
				for i in range(ceili(hz*.4)):
					# The real actor restores its locomotion pose before WeaponCombat.
					p.visual.animate(1.0/hz,Vector3.ZERO,true); w._physics_process(1.0/hz)
					if not released.is_empty(): break
				var emitter: Node3D=w.rig.models[id].right.get_node("WandEmitter")
				check(released.size()==1 and released[0]._origin.distance_to(emitter.global_position)<.002,String(id)+" "+String(action)+" releases from the visible tip after solving the casting pose at yaw "+str(yaw))
				if action==&"special_rt_x" and released.size()==1:
					var arrays: Array=released[0]._mesh.surface_get_arrays(1)
					var nearest:=INF
					for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: nearest=minf(nearest,vertex.distance_to(emitter.global_position))
					check(nearest<.025,"Ground Cast's visible laser starts at the wand before reaching its floor pattern")
				if id==&"dark_box_arc_wand" and yaw==0 and released.size()==1: await review(action,released[0])
				for cast in released: cast.expire()
				await process_frame
	scene.queue_free(); await process_frame
	print("WAND ORIGINS: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
