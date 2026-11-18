extends SceneTree
const Database = preload("res://scripts/equipment_database.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Preview = preload("res://scripts/equipment_preview.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
var world: Node3D
var actor: CharacterBody3D
var checks:=0
var failures:=0
var entries: Array[Dictionary]=[]

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)
func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func signature(garment: Node3D) -> String:
	var hash_value:=HashingContext.new()
	hash_value.start(HashingContext.HASH_SHA256)
	for piece: Node3D in garment.external:
		for mesh: MeshInstance3D in piece.find_children("*","MeshInstance3D",true,false):
			if not mesh.mesh is ArrayMesh: continue
			var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			hash_value.update(vertices.to_byte_array())
	return hash_value.finish().hex_encode()

func shot(label: String, offset: Vector3) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.global_position=actor.global_position+offset
	camera.look_at(actor.global_position+Vector3.UP*.8)
	camera.current=true
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/void_soul_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current=true

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.wider_world_enabled=false
	world.district_life_enabled=false
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	actor=world.player
	actor.visual.retrieval.enabled=false
	await frames(12)
	actor.set_physics_process(false)
	actor.combat.sheathed=true
	actor.weapon_combat.sync_rig()
	for entry: Dictionary in Database.all():
		if entry.geometry.get("palette_group")=="void_soul_greaves": entries.append(entry)
	check(entries.size()==8,"Eight original Void Soul Greaves editions cover the equipment palette")
	var colors: Dictionary={}
	var cuts: Dictionary={}
	var valid:=true
	var fitted:=true
	var bounded:=true
	var stats_before:=Vector3(actor.walk_speed,actor.run_speed,actor.boost_speed)
	var collider: Shape3D=actor.get_child(0).shape
	var cyan_iid: String
	for entry in entries:
		valid=valid and Database.valid(entry) and entry.slot=="legs" and entry.name.begins_with("Void Soul Greaves - ") and entry.description.contains("gift from the void to a weary traveler") and entry.effects.is_empty()
		colors[entry.geometry.tint]=true
		var item: Resource=Catalog.create(StringName(entry.id))
		check(item!=null and actor.inventory.add_item(item) and world.loot.request_equip(actor.inventory,&"legs",item.instance_id),"Equip the owned "+String(entry.name)+" through normal authority")
		check(not world.inventory_session.shop.offer(StringName(entry.id)).is_empty(),"The Tower Exchange / Archive offers "+String(entry.name))
		await frames()
		var garment: Node3D=actor.visual.equipment_cosmetics.pieces[&"legs"][0]
		cuts[signature(garment)]=true
		fitted=fitted and garment.tails.size()==6 and not actor.visual.foot_meshes.LeftLeg.visible and not actor.visual.foot_meshes.RightLeg.visible
		fitted=fitted and garment.external.filter(func(piece: Node3D): return piece.get_parent()==actor.visual.pelvis).size()==1
		var nodes_before: int=garment.find_children("*","",true,false).size()
		var meshes_before: int=garment.external.size()
		for velocity: Vector3 in [Vector3.ZERO,Vector3(0,0,10),Vector3(10,0,0),Vector3(-10,6,-4),Vector3(0,-12,0)]:
			actor.velocity=velocity
			for step in range(30): garment._process(1.0/60)
			for tail: Node3D in garment.tails:
				bounded=bounded and tail.global_position.is_finite() and tail.global_position.distance_to(actor.visual.pelvis.global_position)<.5 and tail.basis.get_scale().y<=1.001
		bounded=bounded and garment.external.size()==meshes_before and garment.find_children("*","",true,false).size()==nodes_before
		if entry.id=="void_soul_greaves_cyan": cyan_iid=item.instance_id
	check(valid and colors.size()==8,"Each edition has original traveler lore, its own color, and the Legs slot")
	check(cuts.size()==1,"Color editions share the same authored cloth and scale geometry")
	check(fitted,"Every edition fits the pelvis, has six articulated cloth panels, and hides both base feet")
	check(bounded,"Running, strafing and aerial motion keep seams attached with fixed geometry")
	check(stats_before==Vector3(actor.walk_speed,actor.run_speed,actor.boost_speed) and collider==actor.get_child(0).shape,"Greaves preserve movement speeds, collision and combat values")
	world.loot.request_equip(actor.inventory,&"legs",cyan_iid)
	await frames()
	var worn: Node3D=actor.visual.equipment_cosmetics.pieces[&"legs"][0]
	var mount:=Vehicle.new()
	var mount_ok:=true
	for kind: String in ["car","truck","motorcycle"]:
		mount.kind=kind
		mount.velocity=Vector3(0,0,25)
		world.world_actions.vehicle=mount
		for step in range(30): worn._process(1.0/60)
		for tail: Node3D in worn.tails:
			mount_ok=mount_ok and tail.visible==(kind=="motorcycle")
			if kind=="motorcycle": mount_ok=mount_ok and absf(tail.get_meta("cloth_angles").x-1.55)<.15
	world.world_actions.vehicle=null
	mount.free()
	actor.velocity=Vector3.ZERO
	worn._process(0)
	check(mount_ok,"Cloth folds behind a motorcycle saddle and hides safely inside cars and trucks")
	check(world.inventory_session.save_checkpoint("user://tests/void_soul_greaves.json",true),"All eight owned color editions save through the existing checkpoint")
	actor.inventory.unequip(&"legs")
	await frames()
	check(actor.visual.foot_meshes.LeftLeg.visible and actor.visual.foot_meshes.RightLeg.visible,"Unequipping restores both original feet and removes the waistcloth")
	check(world.inventory_session.load_checkpoint("user://tests/void_soul_greaves.json") and actor.inventory.equipped_item(&"legs").item_type_id==&"void_soul_greaves_cyan","Loading restores the exact equipped color")
	await frames()
	await shot("front",Vector3(1.6,1.4,3))
	await shot("back",Vector3(-1.6,1.3,-3))
	# Exercise the exact store mannequin builder for every edition.
	var gallery:=SubViewport.new()
	gallery.own_world_3d=true
	gallery.size=Vector2i(1600,1000)
	gallery.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(gallery)
	var preview_ok:=true
	for i in range(entries.size()):
		var model:=Preview.model(entries[i])
		gallery.add_child(model)
		model.position=Vector3((i%4-1.5)*2.2,0,-(i/4)*3.7)
		preview_ok=preview_ok and model.find_children("VoidSoulLappedScales","MeshInstance3D",true,false).size()==4
		var label:=Label3D.new()
		label.text=String(entries[i].name).trim_prefix("Void Soul Greaves - ")
		label.position=model.position+Vector3(0,2.08,0)
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate=Color(entries[i].geometry.tint)
		label.font_size=28
		gallery.add_child(label)
	check(preview_ok,"Every Equipment Archive preview uses the same layered scale and cloth renderer")
	if "--capture" in OS.get_cmdline_user_args():
		var camera:=Camera3D.new()
		gallery.add_child(camera)
		camera.position=Vector3(0,5.5,10)
		camera.look_at(Vector3(0,.9,-1.7))
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=6.8
		camera.current=true
		await frames(4)
		await RenderingServer.frame_post_draw
		gallery.get_texture().get_image().save_png("res://captures/void_soul_colors.png")
	gallery.queue_free()
	world.queue_free()
	await process_frame
	print("VOID SOUL GREAVES: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
