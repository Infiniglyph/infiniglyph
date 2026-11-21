extends SceneTree
const Wardrobe=preload("res://scripts/code_form_wardrobe.gd")
const Visual=preload("res://scripts/resident_visual.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Preview=preload("res://scripts/equipment_preview.gd")
const Pattern=preload("res://scripts/resident_garment_pattern.gd")
const Garment=preload("res://scripts/equipment_garment.gd")
var checks:=0
var failures:=0
var stage: Node3D
var camera: Camera3D
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func capture(label: String):
	if "--capture" not in OS.get_cmdline_user_args(): return
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/resident_"+label+".png")
func count_vertices(node: Node3D) -> Vector2i:
	var total:=Vector2i.ZERO
	if node is MeshInstance3D and node.mesh!=null:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var count: int=arrays[Mesh.ARRAY_VERTEX].size()
			if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(surface)==Mesh.PRIMITIVE_TRIANGLES: total.x+=count
			else: total.y+=count
	for child in node.get_children():
		if child is Node3D: total+=count_vertices(child)
	return total
func label(text: String,at: Vector3):
	var sign:=Label3D.new(); sign.text=text; sign.font_size=36; sign.pixel_size=.005; sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED; stage.add_child(sign); sign.position=at
func run():
	create_timer(60).timeout.connect(func(): quit(2))
	stage=Node3D.new(); root.add_child(stage)
	camera=Camera3D.new(); stage.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=4.8; camera.position=Vector3(1.8,2.5,7); camera.look_at(Vector3(0,1,0)); camera.current=true
	var threshold:=Wardrobe.Equipment.get_item(&"eq_a_13ef1868")
	var showroom:=Preview.model(threshold); stage.add_child(showroom); showroom.position.x=-1.1
	await process_frame
	var mannequin: Node3D=showroom.get_child(0)
	var garment: Node3D=mannequin.get_children().filter(func(child): return child is Garment)[0]
	garment.set_process(false)
	var vertices:=Vector2i.ZERO
	for source: Node3D in garment.external: vertices+=count_vertices(source)
	var pattern:=Pattern.for_item(threshold)
	check(Vector2i(pattern[0].points.size(),pattern[1].points.size())==vertices,"Threshold native geometry retains every triangle and seam from the actual Tower garment")
	var hem:=AABB(); var first:=true; var sleeves:=0
	for i in range(pattern[0].points.size()):
		var bone: int=pattern[0].bones[i*4]
		if bone==10:
			if first: hem=AABB(pattern[0].points[i],Vector3.ZERO); first=false
			else: hem=hem.expand(pattern[0].points[i])
		if bone in [8,9,2,3]: sleeves+=1
	check(hem.position.y<-.85 and hem.size.x>.6 and sleeves>1000,"Threshold keeps the ankle-length split panels, flare, and all four articulated sleeves")
	var accented:=false
	for color: Color in pattern[1].colors: accented=accented or color.r>color.g*1.1
	check(pattern[1].colors.size()>100 and accented,"The fitted seams retain their distinct catalog accent colors")
	var resident:=Visual.new(); stage.add_child(resident); resident.position.x=1.1
	var store:=Inventory.new(); store.owner_id="resident:garment-review"; stage.add_child(store)
	var owned: Resource=Wardrobe.Catalog.create(&"eq_a_13ef1868"); store.add_item(owned); store.assign(&"body",owned.instance_id); resident.sync_clothing(store)
	check(resident.attire.figure.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==vertices.x,"An owned Threshold vestment uses the fitted pattern rather than a generic shell")
	label("TOWER PREVIEW",Vector3(-1.1,2.3,0)); label("RESIDENT",Vector3(1.1,2.3,0))
	await capture("threshold_comparison")
	for child in stage.get_children():
		if child!=camera: child.queue_free()
	await process_frame
	var figures: Array[Node3D]=[]
	var bodies: Array=Wardrobe.BODY_STARTERS.duplicate(); bodies.append(StringName(Wardrobe.UNIFORM.body))
	for i in range(bodies.size()):
		var person:=Visual.new(); stage.add_child(person); person.position.x=(i-2)*2.2; figures.append(person)
		var inventory:=Inventory.new(); inventory.owner_id="resident:garment-pool/"+str(i); stage.add_child(inventory)
		Wardrobe.issue(inventory,{"attire_issued":false,"uniform_issued":false},i==4)
		var body: Resource=Wardrobe.Catalog.create(bodies[i]); inventory.add_item(body); inventory.assign(&"body",body.instance_id)
		person.sync_clothing(inventory)
		var mesh: Mesh=person.attire.figure.mesh
		check(mesh.get_surface_count()==2 and person.attire.get_child_count()==2 and person.attire.skeleton.get_bone_count()==11,"Full outfit retains two surfaces, eleven mounts and no per-resident cloth nodes: "+str(bodies[i]))
		var builds:=Pattern.builds
		var twin:=Visual.new(); stage.add_child(twin); twin.sync_clothing(inventory)
		check(twin.attire.figure.mesh==mesh and Pattern.builds==builds,"Identical fitted outfits reuse cached geometry without rebuilding: "+str(bodies[i]))
		twin.free()
		person.animate(.4,1.4,true)
		check(person.attire.skeleton.get_bone_pose(8).origin.distance_to(person.attire.skeleton.get_bone_pose(2).origin)>.25,"Sleeves and gauntlets follow separate shoulder and elbow contacts")
		label(["LATTICE","PARALLAX","THRESHOLD","HEARTH","DARK BOX"][i],Vector3((i-2)*2.2,2.4,0))
	camera.size=11.5; camera.position=Vector3(.8,3.4,11); camera.look_at(Vector3(0,1.15,0))
	await capture("civic_collection")
	var hidden:=Visual.new()
	check(Pattern.cache.size()<=Pattern.LIMIT and hidden.get_child_count()==0,"Pattern memory is bounded and no full garment rig is added to hidden residents")
	hidden.free()
	for person in figures:
		person.sitting=true; person.animate(.2,0,false)
		check(person.attire.skeleton.get_bone_pose(10).basis.y.z<-.6,"Seated hems fold over the lap while the torso retains its fitted silhouette")
	await capture("seated_collection")
	stage.queue_free(); await process_frame
	print("RESIDENT GARMENTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
