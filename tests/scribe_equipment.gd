extends SceneTree
## Real player, shared resolver, procedural equipment and isolated legacy saves.
const Database = preload("res://scripts/equipment_database.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Target = preload("res://scripts/practice_target.gd")
const Hat = preload("res://scripts/eturnull_hat.gd")
const Scribe = preload("res://scripts/scribe_presentation.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void: pass
var checks := 0
var failures := 0
var hz := 60
var world: Node3D
var p: CharacterBody3D
var w: Node
var hat: Node3D
var presentation: Node3D
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")
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
func own(id: StringName,slot: StringName) -> Resource:
	var item: Resource = Catalog.create(id)
	if not p.inventory.add_item(item) or not world.loot.request_equip(p.inventory,slot,item.instance_id): return null
	return item
func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/scribe_"+label+".png")
func legacy_item(id: String,owner: String = "local") -> Dictionary:
	return {"item_type_id":id,"instance_id":Instance.new_id(),"quantity":1,"upgrade_level":0,"custom_properties":{},"owner_id":owner}
func migration_checks() -> void:
	Database.prepare()
	var removed: Dictionary = Database.retired
	var shield := ""
	var talisman := ""
	var bow := ""
	var crossbow := ""
	for id: String in removed:
		if removed[id]=="shield": shield=id
		elif removed[id]=="talisman": talisman=id
		elif removed[id]=="bow": bow=id
		elif removed[id]=="crossbow": crossbow=id
	check(removed.size()==721 and not shield.is_empty() and not talisman.is_empty() and not bow.is_empty() and not crossbow.is_empty(),"Exact historical IDs cover 693 shields, eight talismans, twelve bows and eight crossbows")
	var retained: Resource = Catalog.create(&"katana")
	retained.owner_id = "local"
	var a := legacy_item(shield)
	var b := legacy_item(talisman)
	var c := legacy_item(bow)
	var d := legacy_item(crossbow)
	var inventory := {"version":1,"owner_id":"local","items":[retained.to_dict(),a,b,c,d],"equipment":{"right":retained.instance_id,"shield":a.instance_id,"down":b.instance_id,"left":c.instance_id,"up":d.instance_id}}
	var data := {"version":1,"policy":"singleplayer_checkpoint","session_id":"singleplayer","inventory":inventory,"world_drops":[]}
	var result := Store.decode(data)
	check(not result.is_empty() and result.inventory.items.size()==1 and result.inventory.equipment.size()==1 and result.inventory.equipment.right==retained.instance_id,"Old saves remove retired ownership and assignments while retaining other gear")
	var drop := legacy_item(shield,"")
	data.world_drops = [{"pickup_id":"old-drop","position":[0,0,0],"item":drop,"death_owner_id":"local"}]
	result = Store.decode(data)
	check(not result.is_empty() and result.world_drops.is_empty() and result.markers.is_empty(),"Retired world pickups and loss markers migrate out of checkpoints")
	data.world_drops[0].item.instance_id = a.instance_id
	check(Store.decode(data).is_empty(),"Migration still rejects duplicate owned and dropped identities")
	data.world_drops = []
	data.inventory.items[1].quantity = 2
	check(Store.decode(data).is_empty(),"Invalid historical quantities still fail validation")
	check(Catalog.create(StringName(shield))==null and Catalog.create(StringName(talisman))==null and Catalog.create(StringName(bow))==null and Catalog.create(StringName(crossbow))==null,"Retired definitions cannot mint new equipment")
	var clean := true
	for entry: Dictionary in Database.all(): clean = clean and entry.family not in ["shield","talisman","bow","crossbow"]
	check(clean and &"shield" not in Inventory.EQUIPMENT_SLOTS,"Active catalog contains no cosmetic shields, talismans, bows or crossbows")
func run() -> void:
	migration_checks()
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	p = world.player
	# These legacy reach/pose fixtures place their targets on a level plane.
	# Pitched camera-directed hit coverage lives in equation_tracing.gd.
	world.camera_rig.pitch = 0
	w = p.weapon_combat
	p.visual.retrieval.enabled = false
	world.population.set_physics_process(false)
	for resident: Node in world.population.get_children():
		resident.set_physics_process(false)
		resident.set_process(false)
		if resident is Node3D: resident.hide()
	var controls := Intent.new()
	root.add_child(controls)
	p.controls = controls
	world.camera_rig.controls = controls
	p.position = Vector3(0,.05,8)
	await frames(hz/2)
	p.set_physics_process(false)
	w.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = p.position+Vector3(2.3,2.0,3.4)
	camera.look_at(p.position+Vector3.UP*1.35)
	camera.current = true
	var robe_item := own(&"eternal_scribe_robes",&"body")
	var hat_item := own(&"eturnull_hat",&"head")
	var manuscript := own(&"eturnull_manuscript",&"down")
	p.combat.selected_slot = &"down"
	p.combat.sheathed = false
	w.sync_rig()
	check(robe_item!=null and hat_item!=null and manuscript!=null,"Hat, robe and Eturnull Manuscript equip through existing loot authority")
	hat = p.visual.find_child("EturnullHat",true,false)
	check(hat!=null and hat.get_parent()==p.visual.chest and hat.position==Vector3(0,.65,0),"Hat follows the existing head anchor")
	check(hat.position.y+.102<.78 and hat.position.y+.34>.78+.135,"Brim crosses below eye level while the crown clears the actual head sphere")
	var rain_colors: Dictionary = {}
	for group: Dictionary in hat.groups:
		for ink: StandardMaterial3D in group.inks:
			rain_colors[ink.albedo_color.to_html(false)] = true
	var crown_colors: Dictionary = {}
	for ink: StandardMaterial3D in hat.crown_inks: crown_colors[ink.albedo_color.to_html(false)] = true
	check(rain_colors.size()==5 and crown_colors.size()==5,"Hat rain and crown inscriptions reuse all five silver-blue, violet, silver, gold and cyan robe colors")
	check(hat.find_children("*","CollisionObject3D",true,false).is_empty(),"Hat and mathematical rain contain no combat or physical colliders")
	check(p.visual.robe.is_equipped() and not p.visual.robe.get_node("OpenScholarHood").visible,"Hat coexists with the robe and hides only its overlapping hood")
	hat.set_process(false)
	hat.elapsed = .25
	hat.advance(0)
	var initial: Vector3 = hat.groups[0].nodes[0].position
	hat.elapsed = hat.fall_seconds+hat.formation_seconds+.15
	hat.advance(0)
	var group: Dictionary = hat.groups[0]
	var aligned := true
	for i in range(group.expression.length()):
		aligned = aligned and is_equal_approx(group.nodes[i].position.y,group.nodes[0].position.y) and is_equal_approx(group.nodes[i].position.z,group.nodes[0].position.z)
	check(aligned and group.formation==1.0 and initial.distance_to(group.nodes[0].position)>.05,"Separate falling glyphs actually gather into a coherent equation")
	check(group.ink.albedo_color.a>.6,"Completed equations remain visible during their hold")
	hat.elapsed = hat.fall_seconds+hat.formation_seconds+hat.hold_seconds+hat.fade_seconds*.8
	hat.advance(0)
	check(hat.groups[0].ink.albedo_color.a<.2,"Completed expressions fade after their hold")
	hat.elapsed = .16
	hat.advance(0)
	var seed: Vector3 = hat.crown_glyphs[0].position
	hat.elapsed = 1.6
	hat.advance(0)
	var grown: Vector3 = hat.crown_glyphs[0].position
	check(Vector2(seed.x,seed.z).length()<.06 and Vector2(grown.x,grown.z).length()>.24 and hat.crown_inks[0].albedo_color.a>.5,"Flat crown symbols emerge at the center and flow outward across the top")
	var clear_of_fabric := true
	for t: float in [.0,.4,1.2,2.4,3.19]:
		hat.elapsed = t
		hat.advance(0)
		for glyph: MeshInstance3D in hat.crown_glyphs:
			clear_of_fabric = clear_of_fabric and glyph.basis.z.normalized().dot(Vector3.UP)>.85
			var bounds := glyph.mesh.get_aabb()
			for corner in range(8):
				var point: Vector3 = glyph.transform*bounds.get_endpoint(corner)
				var radius := Vector2(point.x,point.z).length()
				var fabric_height := .34-maxf(0,radius-.015)*.24/(Hat.RADIUS-.015)
				clear_of_fabric = clear_of_fabric and radius<Hat.RADIUS and point.y>fabric_height+.003
	check(clear_of_fabric,"Crown glyph planes stay above the opaque cone and inside the brim throughout emission")
	var count: int = hat.rain.get_child_count()
	var first_crown_glyph: MeshInstance3D = hat.crown_glyphs[0]
	var meshes := Hat.glyph_meshes.size()
	for i in range(400): hat.advance(.05)
	check(count==44 and hat.rain.get_child_count()==count and hat.crown.get_child_count()==16 and hat.crown_glyphs[0]==first_crown_glyph and Hat.glyph_meshes.size()==meshes,"Long-running hat reuses 44 rain glyphs and 16 crown glyphs without new instances or meshes")
	check(Database.all().any(func(e: Dictionary): return e.family=="head" and e.geometry.get("tailoring",{}).get("crown",false)),"Existing crown cosmetics remain available")
	var snapshot := Store.encode(p.inventory)
	var restored := Inventory.new()
	check(restored.restore(snapshot.inventory) and restored.equipped_item(&"head").item_type_id==&"eturnull_hat" and restored.equipped_item(&"down").item_type_id==&"eturnull_manuscript","Save/load preserves both new equipment assignments")
	restored.free()
	presentation = w.rig.models[&"eturnull_manuscript"].right
	check(presentation is Scribe and w.loadout(&"down").id==&"scribe" and is_equal_approx(w.guard_strength(),.72),"Scribe has its own class, presentation and configured block power")
	presentation.set_process(false)
	presentation._process(.5)
	var physical_origin := p.global_position
	for i in range(hz):
		p.visual.animate(1.0/hz,Vector3.ZERO,true)
		w.apply_pose(1.0/hz)
	presentation._process(1.0/hz)
	var hand_correct := true
	for heading: float in [0.0,PI*.5,PI,-PI*.5]:
		p.visual.rotation.y = heading
		for i in range(12):
			p.visual.animate(1.0/hz,Vector3.ZERO,true)
			w.apply_pose(1.0/hz)
		presentation._process(1.0/hz)
		hand_correct = hand_correct and p.visual.to_local(presentation.book.global_position).x>.08 and p.visual.to_local(presentation.quill.global_position).x<-.08
	check(hand_correct,"Book is anatomically left and hovering quill right at four world headings")
	p.visual.rotation.y = 0
	for i in range(hz/2):
		p.visual.animate(1.0/hz,Vector3.ZERO,true)
		w.apply_pose(1.0/hz)
	presentation._process(1.0/hz)
	var front_foot: Vector3 = p.visual.to_local(p.visual.joints.LeftLeg.get_node("Hinge").to_global(Vector3(0,-.45,0)))
	var rear_foot: Vector3 = p.visual.to_local(p.visual.joints.RightLeg.get_node("Hinge").to_global(Vector3(0,-.45,0)))
	print("SCRIBE READY: front=",front_foot," rear=",rear_foot," hips=",w.body.translation.value)
	check(front_foot.z>rear_foot.z+.15 and w.body.translation.value.x>0 and w.body.translation.value.z<0,"Ready stance has the anatomical left foot behind and carries the hips over it")
	check(p.visual.chest.to_local(w.rig.left_hand.global_position).y<.05 and p.global_position.is_equal_approx(physical_origin),"Right conducting arm hangs down without moving the player capsule")
	var shoulder: Vector3 = p.visual.joints.LeftArm.global_position
	var elbow: Vector3 = p.visual.joints.LeftArm.get_node("Hinge").global_position
	var wrist: Vector3 = w.rig.left_hand.global_position
	check((elbow-shoulder).normalized().dot((wrist-elbow).normalized())>.96 and wrist.y<shoulder.y-.53,"Resting right arm has a relaxed, nearly straight elbow instead of the bent ready pose")
	for i in range(hz): presentation._process(1.0/hz)
	var hover: Vector3 = p.visual.to_local(presentation.quill.global_position)
	check(absf(hover.x+1.0)<.08 and presentation.quill.global_position.y>shoulder.y+.05 and presentation.quill.global_position.y<shoulder.y+.4,"Idle quill hovers a metre to the anatomical right and just above shoulder height")
	var trails := true
	for velocity: Vector3 in [Vector3(0,0,10),Vector3(0,0,-10),Vector3(10,0,0),Vector3(-10,0,0)]:
		p.velocity = velocity
		for i in range(hz/2): presentation._process(1.0/hz)
		trails = trails and presentation.hover_trail.dot(velocity)<-.5 and presentation.hover_trail.length()<=.301
	check(trails,"Quill trails actual forward, backward and sideways travel with a bounded offset")
	p.velocity = Vector3(30,40,-30)
	for i in range(hz/2): presentation._process(1.0/hz)
	check(presentation.hover_trail.length()<=.301 and absf(presentation.hover_trail.y)<=.101,"Fast aerial motion cannot stretch the hover trail or pull it far below the shoulder")
	p.position += Vector3(120,0,-90)
	presentation._process(1.0/hz)
	check(presentation.quill.global_position.distance_to(p.global_position+Vector3.UP*1.56)<1.5,"Owner-local following keeps the quill attached through large fast-travel displacements")
	p.position = physical_origin
	p.velocity = Vector3.ZERO
	for i in range(hz): presentation._process(1.0/hz)
	check(presentation.hover_trail.length()<.005,"Hover trail settles cleanly after stopping")
	check(Catalog.get_definition(&"eturnull_manuscript").description=="A Grimoire recovered from the creator of a world that never needed to exist.\nIts pages contain no spells, only expressions describing what already is.\nThe quill does not command reality.\nIt merely corrects the equation.","Manuscript uses the exact requested four-line lore")
	check(presentation.book.get_node("LeftLeaf").rotation.y<.4 and presentation.quill.visible,"Grimoire remains open with an independently floating quill")
	camera.position = p.position+Vector3(.25,1.65,3.2)
	camera.look_at(p.position+Vector3.UP*1.02)
	await capture("outfit")
	if "--capture" in OS.get_cmdline_user_args():
		var prior_view := camera.global_transform
		var prior_fov := camera.fov
		var prior_time: float = hat.elapsed
		camera.fov = 45
		camera.global_position = hat.to_global(Vector3(0,2.5,.015))
		camera.look_at(hat.to_global(Vector3(0,.22,0)),hat.global_basis.z)
		for i in range(2):
			hat.elapsed = .4+i
			hat.advance(0)
			await capture("hat_top_"+str(i))
		camera.global_transform = prior_view
		camera.fov = prior_fov
		hat.elapsed = prior_time
		hat.advance(0)
	var page_angle: float = presentation.turning_page.rotation.y
	presentation._process(.2)
	check(absf(presentation.turning_page.rotation.y-page_angle)>.01,"An individual page turns around its own spine")
	var target := Target.new()
	target.actor = p
	target.health = 100000
	target.max_health = 100000
	world.add_child(target)
	target.set_physics_process(false)
	var names: Dictionary = {}
	var gestures: Dictionary = {}
	var actual_gestures: Dictionary = {}
	var expected_damage := {&"attack_right":[13,16,18,17],&"attack_left":[30],&"special_x":[28],&"special_y":[24],&"special_rt_x":[23],&"special_rt_y":[25]}
	var damage_tuned := true
	var low_hand := INF
	var high_hand := -INF
	for action: StringName in [&"attack_right",&"attack_left",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
		for combo in range(4 if action==&"attack_right" else 1):
			var move := Library.move(&"eturnull_manuscript",action,combo,false)
			var aerial := Library.move(&"eturnull_manuscript",action,combo,true)
			damage_tuned = damage_tuned and is_equal_approx(move.damage,expected_damage[action][combo]) and is_equal_approx(aerial.damage,move.damage)
			var sample := Motion.sample(move,float(move.duration)*.45)
			gestures[JSON.stringify([sample.left,sample.hip,sample.chest])] = true
			if action==&"attack_right":
				var twin := Library.move(&"up",&"attack_right")
				check(is_equal_approx(move.duration,twin.duration) and is_equal_approx(move.windup,twin.windup) and is_equal_approx(move.hits[0],twin.hits[0]),"Light combo stage "+str(combo+1)+" matches actual twin-blade timing")
			names[move.name] = true
			w.cancel()
			w._begin(move)
			w._facing = Vector3.FORWARD
			w.elapsed = float(move.hits[0])*.3
			presentation._process(1.0/hz)
			var partial: int = presentation.ink.multimesh.visible_instance_count
			w.elapsed = float(move.hits[0])
			presentation._process(1.0/hz)
			check(partial>0 and partial<presentation.ink.multimesh.visible_instance_count,String(move.name)+" is written progressively by the floating tip")
			var tip: Vector3 = presentation.active_transform*presentation.active_points[presentation.ink.multimesh.visible_instance_count*2-1]
			check(presentation.quill.global_position.distance_to(tip)<.001,String(move.name)+" places the real quill tip on its newest stroke")
			target.position = p.position+Vector3.FORWARD*float(move.reach)*.68
			await frames()
			var before: float = target.total_damage
			w.strike(0)
			var dealt: float = target.total_damage-before
			w.strike(0)
			check(dealt>0 and is_equal_approx(target.total_damage-before,dealt),String(move.name)+" hits actual written geometry once per pulse")
			if action==&"attack_left":
				check(is_equal_approx(dealt,30),"Final Statement applies exactly 30 base damage through the real combat resolver")
			w.elapsed = float(move.duration)*.45
			for i in range(24):
				p.visual.animate(1.0/hz,Vector3.ZERO,true)
				w.apply_pose(1.0/hz)
			presentation._process(1.0/hz)
			var actual: Vector3 = p.visual.chest.to_local(w.rig.left_hand.global_position)
			actual_gestures[str(actual.snapped(Vector3.ONE*.02))] = true
			low_hand = minf(low_hand,actual.y)
			high_hand = maxf(high_hand,actual.y)
			if "--capture" in OS.get_cmdline_user_args():
				camera.position = p.position+Vector3(2.0,1.8,-3.2)
				camera.look_at(p.position+Vector3.UP*1.0)
				await capture("gesture_"+String(action)+"_"+str(combo))
			w.cancel()
			check(presentation.ink.multimesh.visible_instance_count==0,"Cancellation removes active writing immediately")
	check(damage_tuned,"Grounded and aerial Manuscript attacks use the reduced 30-damage balance with proportional lighter hits")
	check(names.size()==9,"Four light stages, heavy attack and four weapon arts have distinct identities")
	check(gestures.size()==9,"Nine different named-weapon source gestures produce distinct conducting hand and body poses")
	check(actual_gestures.size()>=8 and high_hand-low_hand>.20,"Actual arm IK presents distinct high, low, crossed and sweeping conducting silhouettes")
	var art := Library.charged_move(&"eturnull_manuscript",&"special_x",1)
	check(art.damage>Library.move(&"eturnull_manuscript",&"special_x").damage and art.hits.size()==2 and is_equal_approx(art.reach,9.1),"Theorem uses existing charged damage and pulses with the same extended reach as a fully charged spear")
	var ordinary := Library.move(&"eturnull_manuscript",&"attack_right")
	check(is_equal_approx(ordinary.reach,Library.move(&"left",&"special_rt_x").reach),"Scribe reach matches the spear's longest seven-metre uncharged art")
	w.cancel()
	w._begin(ordinary)
	w._facing = Vector3.FORWARD
	target.position = p.position+Vector3.FORWARD*6.9
	await frames()
	var far_before: float = target.total_damage
	w.elapsed = float(ordinary.hits[0])
	w.strike(0)
	check(target.total_damage>far_before,"The far visible equation has an actual matching seven-metre contact volume")
	w.cancel()
	w._begin(ordinary)
	w._facing = Vector3.FORWARD
	target.position = p.position+Vector3(2,0,-1)
	await frames()
	var before: float = target.total_damage
	w.elapsed = float(ordinary.hits[0])
	w.strike(0)
	check(target.total_damage==before,"Being inside generic melee reach does not hit outside the written strokes")
	w.cancel()
	target.position = p.position+Vector3.FORWARD*float(ordinary.reach)*.68
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,3,.12)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.position = p.position+Vector3(0,1,-.65)
	await frames()
	w._begin(ordinary)
	w._facing = Vector3.FORWARD
	w.elapsed = float(ordinary.hits[0])
	w.strike(0)
	check(target.total_damage==before,"Opaque architecture blocks written attacks through the shared obstruction check")
	w.cancel()
	wall.queue_free()
	await frames()
	# Shared defensive path: no special Scribe parry implementation.
	w._facing = Vector3.FORWARD
	var frontal: Vector3 = w.aim_direction()
	p.combat.blocking = true
	w.parry_remaining = w.PARRY_WINDOW
	var hp: float = w.health
	var attacker: CharacterBody3D = world.sparring_partner
	attacker.set_physics_process(false)
	w.receive_hit(40,p.position+frontal,attacker,{"parryable":true})
	check(w.last_parried and w.health==hp and is_equal_approx(attacker.weapon_combat.stagger_remaining,1.0),"Counterproof preserves zero defender damage and the shared one-second attacker stun")
	w.parry_remaining = 0
	w.receive_hit(40,p.position+frontal,null,{"parryable":true})
	check(w.last_blocked and is_equal_approx(w.last_damage,40*(1-.72)),"Geometric Ward uses the existing configured block reduction")
	p.combat.blocking = false
	w.reset()
	w.sync_rig()
	# Exercise the other side of the contract with a real guarded/parrying actor.
	var defender: CharacterBody3D = world.sparring_partner
	defender.set_physics_process(false)
	defender.weapon_combat.set_physics_process(false)
	defender.weapon_combat.reset()
	defender.combat.sheathed = false
	defender.combat.blocking = true
	defender.set_collision_layer_value(2,true)
	defender.target_lock.select(p)
	world.sparring_duel.active = true
	defender.position = p.position+Vector3.FORWARD*float(ordinary.reach)*.68
	target.position = Vector3(30,0,30)
	await frames()
	defender.weapon_combat.parry_remaining = defender.weapon_combat.PARRY_WINDOW
	w._begin(ordinary)
	w._facing = Vector3.FORWARD
	w.elapsed = float(ordinary.hits[0])
	w.strike(0)
	check(defender.weapon_combat.last_parried and defender.health==1000 and w.is_staggered(),"A real opponent can parry the written stroke and stun its Scribe attacker")
	w.reset()
	defender.weapon_combat.parry_remaining = 0
	defender.weapon_combat.health = 1000
	w._begin(ordinary)
	w._facing = Vector3.FORWARD
	w.elapsed = float(ordinary.hits[0])
	w.strike(0)
	check(defender.weapon_combat.last_blocked and defender.health<1000,"A real opponent can block the mathematical stroke using its ordinary guard")
	world.sparring_duel.active = false
	defender.return_home()
	w.reset()
	p.combat.sheathed = true
	w.sync_rig()
	presentation._process(.13)
	check(presentation.quill.visible and presentation.stow_amount>.2 and presentation.stow_amount<.5,"Sheathing first dives the quill into the still-open book")
	presentation._process(.5)
	check(not presentation.quill.visible and presentation.stow_amount==1 and presentation.book.global_position.distance_to(p.visual.pelvis.to_global(Vector3(.225,.03,-.08)))<.001,"Closed Grimoire settles against the left waist with its quill inside")
	var hip_basis: Basis = p.visual.pelvis.global_basis.orthonormalized()
	var edge_forward := true
	for i in range(2):
		var leaf: Node3D = presentation.leaves[i]
		var fore_edge: Vector3 = leaf.to_global(Vector3(-.21 if i==0 else .21,0,0))-presentation.book.global_position
		edge_forward = edge_forward and absf(leaf.global_basis.z.normalized().dot(hip_basis.x))>.98 and fore_edge.normalized().dot(hip_basis.z)>.98
	check(edge_forward,"Both closed covers face sideways against the hip and their paper fore-edges face forward")
	target.position = Vector3(30,0,30)
	await frames(hz)
	await capture("sheathed")
	if "--capture" in OS.get_cmdline_user_args():
		var previous_fov := camera.fov
		camera.fov = 45
		for view: String in ["front","left","right"]:
			var offset := Vector3(0,.15,1.65)
			if view=="left": offset = Vector3(1.15,.15,.10)
			elif view=="right": offset = Vector3(-1.15,.15,.10)
			camera.global_position = p.visual.pelvis.to_global(offset)
			camera.look_at(p.visual.pelvis.global_position)
			await capture("hip_books_"+view)
		camera.fov = previous_fov
	p.combat.sheathed = false
	w.sync_rig()
	presentation._process(.5)
	check(presentation.quill.visible and presentation.stow_amount==0 and presentation.leaves[0].rotation.y<.4,"Drawing opens the book and releases the hovering quill")
	target.position = Vector3(30,0,30)
	p.velocity = Vector3.ZERO
	var baseline := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	p.set_physics_process(true)
	w.set_physics_process(true)
	presentation.set_process(true)
	controls.boost = true
	controls.move = Vector2(0,-1)
	await frames(hz/2)
	check(p.velocity.length()>4 and Vector3(p.walk_speed,p.run_speed,p.boost_speed)==baseline,"Scribe preserves running and boost movement settings")
	if "--capture" in OS.get_cmdline_user_args():
		camera.position = p.position+Vector3(2.4,1.9,-3.6)
		camera.look_at(p.position+Vector3.UP*1.1)
		await capture("hover_moving")
	w.set_physics_process(false)
	presentation.set_process(false)
	p.position.y += 4
	p.velocity = Vector3(3,4,-8)
	p.move_and_slide()
	var air: Dictionary = w.move_for(&"down",&"attack_right")
	check(air.aerial and air.weapon_family=="scribe","Aerial movement resolves the authored Scribe attack variant")
	p.set_physics_process(false)
	# Exercise a real Sky Jump request and immediate dodge cancellation.
	p.set_physics_process(true)
	controls.move = Vector2.ZERO
	controls.boost = false
	controls.jump_requested = true
	await frames(2)
	check(p.air_step_count>0 and p.last_sky_impulse.y>0,"Equipped Scribe keeps the actual unlimited Sky Jump input path")
	p.set_physics_process(false)
	w.cancel()
	var move := Library.move(&"eturnull_manuscript",&"special_x")
	w._begin(move)
	w.elapsed = float(move.hits[0])
	for i in range(16):
		p.visual.animate(1.0/hz,Vector3.ZERO,false)
		w.apply_pose(1.0/hz)
	presentation._process(1.0/hz)
	var started: bool = p.dodge.start(Vector3.RIGHT)
	check(started and w.active_move.is_empty() and presentation.ink.multimesh.visible_instance_count==0,"Dodge immediately cancels Scribe attacks and written volumes")
	p.dodge.cancel()
	p.position = Vector3(0,.05,8)
	p.velocity = Vector3.ZERO
	p.visual.position = Vector3.ZERO
	p.visual.scale = Vector3.ONE
	camera.position = p.position+Vector3(5.5,3.0,-3.7)
	camera.look_at(p.position+Vector3(0,1.1,-3.3))
	w._begin(move)
	w._facing = Vector3.FORWARD
	w.elapsed = float(move.hits[0])
	for i in range(16):
		p.visual.animate(1.0/hz,Vector3.ZERO,true)
		w.apply_pose(1.0/hz)
	presentation._process(1.0/hz)
	hat.set_process(true)
	await capture("conducting")
	check(presentation.book.global_position.is_finite() and presentation.quill.position.length()<10,"Book and quill remain bounded while airborne and conducting")
	w.cancel()
	var old_hat: Node3D = hat
	p.inventory.unequip(&"head")
	await frames()
	check(not is_instance_valid(old_hat) and p.visual.robe.get_node("OpenScholarHood").visible,"Unequipping removes all hat effects and restores the robe hood")
	p.combat.selected_slot = &"right"
	w.sync_rig()
	presentation._process(.1)
	check(not presentation.visible and presentation.ink.multimesh.visible_instance_count==0,"Switching weapons hides the quill and clears all written geometry")
	check(is_equal_approx(Library.move(&"right",&"attack_right").damage,22) and Library.loadout(&"down").id==&"sword_shield","Existing katana and functional sword/shield loadouts are preserved")
	var browser: PanelContainer = world.inventory_session.shop.browser
	browser.set_category("weapons")
	browser.filter.select(7)
	browser.refresh()
	check(browser.ids.has(&"eturnull_manuscript") and browser.ids.all(func(id: StringName): return Database.get_item(id).family=="scribe"),"Tower Exchange exposes the Scribe family as a separate filter")
	browser.show_item(&"eturnull_manuscript")
	await frames()
	var ui: CanvasLayer = world.inventory_session.ui
	ui.selected_iid = manuscript.instance_id
	ui._inspect()
	check(ui._arts.text.contains("Hold to write / 750 damage / 3.0 s trail") and browser.details.text.contains("Hold X / Q or Y / R to trace"),"Inventory and Equipment Archive explain the Manuscript's live tracing arts")
	check(browser.model.find_child("ScribePresentation",true,false)!=null,"Equipment Archive preview uses the real Scribe rig")
	browser.set_category("armour")
	browser.show_item(&"eturnull_hat")
	await frames()
	check(browser.model.find_child("EturnullHat",true,false)!=null,"Hat preview uses its actual head attachment and equation rain")
	world.queue_free()
	await frames()
	print("SCRIBE EQUIPMENT: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
