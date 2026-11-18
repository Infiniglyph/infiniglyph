extends "res://tests/defensive_interactions.gd"
## Fit real outlined weapons/boots, then exchange hits through the shared resolver.
const Database = preload("res://scripts/equipment_database.gd")
const Garment = preload("res://scripts/equipment_garment.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Preview = preload("res://scripts/equipment_preview.gd")

func lowest_mesh(node: Node3D) -> float:
	var lowest := INF
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		for corner in range(8):
			lowest = minf(lowest,(mesh.global_transform*mesh.get_aabb().get_endpoint(corner)).y)
	return lowest

func capture_fit(label: String, offset: Vector3) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = p.position+offset
	camera.look_at(p.position+Vector3.UP*1.2)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/equipment_fit_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current = true

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	p = world.player
	npc = world.sparring_partner
	a = p.weapon_combat
	b = npc.weapon_combat
	controls = world.controls
	input = Shared.Intent.new()
	input.source = controls
	root.add_child(input)
	p.controls = input
	world.camera_rig.controls = input
	p.visual.retrieval.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await seconds(.3)
	await reset_pair()
	world.sparring_duel.start()
	npc.controls.stop()
	var examples: Dictionary = {}
	for entry: Dictionary in Database.all():
		if entry.category=="weapons": examples[entry.motion_set.cut if entry.has("motion_set") else entry.family] = StringName(entry.id)
	var keys: Array = [&"down",&"left",&"right",&"up"]+examples.values()
	for id: StringName in keys:
		var no_stun := true
		for action: StringName in [&"attack_left",&"attack_right"]:
			for combo in range(4):
				for air: bool in [false,true]:
					var move := Library.move(id,action,combo,air)
					no_stun = no_stun and not move.is_empty() and move.action==String(action) and move.hit_stun_level==0 and move.hit_stagger==0 and float(move.damage)>0
		check(no_stun,"All grounded/aerial bumper combo stages deal damage without stun: "+String(id))
	# Repeated clean lights cannot cancel an attack, charge or buffered action on
	# either participant, even if a custom dictionary supplies huge stun values.
	for defender: Node in [p,npc]:
		await reset_pair()
		var attacker: Node = npc if defender==p else p
		var wc: Node = defender.weapon_combat
		wc._begin(Library.move(&"right",&"special_y"))
		wc.elapsed = .12
		wc._queued = {"action":&"attack_right","slot":&"right","charge":0.0}
		defender.combat.charge_action = &"special_x"
		for i in range(24):
			var hit := Library.move(&"kyren_katana",&"attack_right" if i%2==0 else &"attack_left")
			hit.hit_stun_level = 999.0
			hit.hit_stagger = 10.0
			defender.receive_combat_hit(1,attacker.combat_point(),attacker,hit)
		check(wc.health==976 and not wc.is_staggered() and wc.can_act(),"Repeated RB/LB contacts leave control available: "+defender.name)
		check(not wc.active_move.is_empty() and wc.elapsed==.12 and not wc._queued.is_empty() and defender.combat.charge_action==&"special_x","Light hits preserve offense, charge and buffering: "+defender.name)
		wc.cancel()
		check(defender.dodge.start(Vector3.RIGHT),"Defender can dodge immediately out of light pressure: "+defender.name)
		defender.dodge.cancel()
		await reset_pair()
		guard(defender,true)
		attacker.weapon_combat._begin(Library.move(&"down",&"attack_right"))
		var applied: float = defender.receive_combat_hit(24,attacker.combat_point(),attacker,attacker.weapon_combat.active_move)
		check(applied==0 and defender.weapon_combat.last_parried and is_equal_approx(attacker.weapon_combat.stagger_remaining,1.0),"Light attacks remain parryable with the one-second attacker stun: "+defender.name)
		await reset_pair()
		var art := Library.move(&"right",&"special_rt_y")
		defender.receive_combat_hit(art.damage,attacker.combat_point(),attacker,art)
		check(defender.weapon_combat.forced_state==&"hit","Weapon arts retain normal fortitude-based stun: "+defender.name)
	await reset_pair()
	p.set_physics_process(false)
	a.set_physics_process(false)
	p.position = Vector3(0,0,8)
	p.visual.clear_combat_pose()
	p.visual.transform = Transform3D.IDENTITY
	p.visual.pelvis.position = Vector3(0,p.visual.REST_HIP_HEIGHT,0)
	p.visual.pelvis.quaternion = Quaternion.IDENTITY
	p.visual.chest.quaternion = Quaternion.IDENTITY
	var greatswords := 0
	var raised := true
	var held_unchanged := true
	var example: Dictionary
	for entry: Dictionary in Database.all():
		if entry.family!="greatsword": continue
		greatswords += 1
		a.rig.equip_item(StringName(entry.id),true)
		var model: Dictionary = a.rig.models[StringName(entry.id)]
		raised = raised and lowest_mesh(model.stowed)>=.399
		held_unchanged = held_unchanged and model.right.position.is_zero_approx() and model.right.scale.is_equal_approx(Vector3.ONE) and model.stowed_blades[0].scale.is_equal_approx(Vector3.ONE)
		example = entry
		await process_frame
	check(greatswords>=222 and raised,"All %d sheathed greatswords clear the floor by at least 40 cm at rest" % greatswords)
	check(held_unchanged,"Back-mount fitting preserves held grips and full blade dimensions")
	p.visual.pelvis.position.y -= .34
	check(lowest_mesh(a.rig.models[StringName(example.id)].stowed)>.05,"The longest stowed blade still clears the floor in a deep resting crouch")
	p.visual.pelvis.position.y += .34
	await capture_fit("greatsword",Vector3(-2.6,1.8,-3.4))
	var legs := 0
	var covered := true
	var restored := true
	var enclosed := true
	var leg_entry: Dictionary
	for entry: Dictionary in Database.all():
		if entry.family!="legs" or not entry.geometry.has("tailoring"): continue
		legs += 1
		leg_entry = entry
		var garment := Garment.new()
		p.visual.add_child(garment)
		garment.configure(p.visual,entry)
		covered = covered and not p.visual.foot_meshes.LeftLeg.visible and not p.visual.foot_meshes.RightLeg.visible
		for side: String in ["Left","Right"]:
			var boot: Node3D = garment.external.filter(func(n: Node3D): return n.name==side+"ArticulatedGreave1")[0]
			var mesh: MeshInstance3D = boot.get_node("ContouredLegPlate")
			var bounds := mesh.get_aabb()
			enclosed = enclosed and absf(bounds.position.y+.494)<.001
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var sole_triangles := 0
			for i in range(0,vertices.size(),3):
				if absf(vertices[i].y+.494)<.001 and absf(vertices[i+1].y+.494)<.001 and absf(vertices[i+2].y+.494)<.001: sole_triangles += 1
			enclosed = enclosed and sole_triangles==16
		garment.free()
		restored = restored and p.visual.foot_meshes.LeftLeg.visible and p.visual.foot_meshes.RightLeg.visible
		await process_frame
	var expected_legs: int=Database.all().filter(func(entry: Dictionary): return entry.family=="legs" and entry.geometry.has("tailoring")).size()
	check(legs==expected_legs and legs>=90 and covered,"All %d leg cosmetics hide both base foot meshes" % legs)
	check(enclosed,"Every boot reaches below the ankle and has a closed sixteen-triangle sole")
	check(restored,"Removing each leg cosmetic restores both bare feet")
	var owned: Resource = Catalog.create(StringName(leg_entry.id))
	p.inventory.add_item(owned)
	world.loot.request_equip(p.inventory,&"legs",owned.instance_id)
	p.visual.sync_clothing(p.inventory)
	check(not p.visual.foot_meshes.LeftLeg.visible,"Normal inventory equip applies the same foot coverage")
	await capture_fit("boots",Vector3(2.2,.6,3.2))
	world.loot.request_unequip(p.inventory,&"legs")
	p.visual.sync_clothing(p.inventory)
	check(p.visual.foot_meshes.LeftLeg.visible and p.visual.foot_meshes.RightLeg.visible,"Normal inventory unequip immediately restores feet")
	var preview := Preview.model(leg_entry)
	world.add_child(preview)
	await process_frame
	var figure: Node3D = preview.get_child(0)
	check(not figure.foot_meshes.LeftLeg.visible and not figure.foot_meshes.RightLeg.visible,"Equipment preview uses the same covered feet and boots")
	preview.queue_free()
	var custom_count:=0
	var custom_fit:=true
	for entry: Dictionary in Database.all():
		if entry.family!="legs" or entry.geometry.has("tailoring"): continue
		custom_count+=1
		var copy: Resource=Catalog.create(StringName(entry.id))
		p.inventory.add_item(copy)
		p.inventory.assign(&"legs",copy.instance_id)
		p.visual.sync_clothing(p.inventory)
		await process_frame # Inspect committed batches after source panels retire.
		custom_fit=custom_fit and not p.visual.foot_meshes.LeftLeg.visible and not p.visual.foot_meshes.RightLeg.visible
		var piece: Node3D=p.visual.equipment_cosmetics.pieces[&"legs"][0]
		var boots:=0
		for anchor: Node3D in piece.external:
			if not anchor.name.ends_with("SkyguardGreave"): continue
			boots+=1
			var edges: Dictionary={}
			for mesh: MeshInstance3D in anchor.find_children("*","MeshInstance3D",true,false):
				if not mesh.mesh is ArrayMesh or mesh.mesh.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES: continue
				custom_fit=custom_fit and mesh.get_aabb().position.y<=-.49
				var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				for i in range(0,vertices.size(),3):
					for side in range(3):
						var u:=str(vertices[i+side].snapped(Vector3.ONE*.00001))
						var v:=str(vertices[i+(side+1)%3].snapped(Vector3.ONE*.00001))
						var key:=u+":"+v if u<v else v+":"+u
						edges[key]=int(edges.get(key,0))+1
			for uses: int in edges.values(): custom_fit=custom_fit and uses>=2 and uses%2==0
			custom_fit=custom_fit and not edges.is_empty()
		custom_fit=custom_fit and boots==2
		p.inventory.unequip(&"legs")
		p.visual.sync_clothing(p.inventory)
		custom_fit=custom_fit and p.visual.foot_meshes.LeftLeg.visible and p.visual.foot_meshes.RightLeg.visible
		await process_frame
	check(custom_count>=6 and custom_fit,"All %d custom temple/royal leg sets hide feet and build closed greaves below the ankle" % custom_count)
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Equipment fit / light hits: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
