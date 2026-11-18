extends SceneTree
const Database = preload("res://scripts/equipment_database.gd")
const Garment = preload("res://scripts/equipment_garment.gd")
const Visual = preload("res://scripts/character_visual.gd")
const Variants = preload("res://scripts/garment_variants.gd")
var checks:=0
var failures:=0
var scene: Node3D

func check(ok: bool, message: String) -> void:
	checks+=1
	if ok: print("PASS: ",message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _initialize() -> void: call_deferred("run")

func mannequin(point: Vector3) -> Node3D:
	var actor:=CharacterBody3D.new()
	actor.position=point
	scene.add_child(actor)
	var figure:=Visual.new()
	figure.live_retrieval=false
	actor.add_child(figure)
	return figure

func signature(garment: Node3D) -> String:
	var hash_value:=HashingContext.new()
	hash_value.start(HashingContext.HASH_SHA256)
	for node: Node3D in garment.external:
		for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var arrays:=mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				hash_value.update(vertices.to_byte_array())
	return hash_value.finish().hex_encode()

func run() -> void:
	scene=Node3D.new()
	root.add_child(scene)
	var figure:=mannequin(Vector3.ZERO)
	var samples: Dictionary={"hands":{},"legs":{},"body":{},"head":{}}
	for family: String in ["hands","legs","body","head"]:
		var signatures: Dictionary={}
		var count:=0
		var max_vertices:=0
		var palettes: Dictionary={}
		for entry: Dictionary in Database.all():
			if entry.family!=family or not entry.geometry.has("tailoring"): continue
			# Explicit color editions share one cut; test that cut once here.
			var palette: String=entry.geometry.get("palette_group","")
			if not palette.is_empty():
				if palettes.has(palette): continue
				palettes[palette]=true
			var garment:=Garment.new()
			figure.add_child(garment)
			garment.configure(figure,entry)
			garment.set_process(false)
			var fingerprint:=signature(garment)
			if signatures.has(fingerprint): print("DUPLICATE GEOMETRY ",entry.id," and ",signatures[fingerprint])
			signatures[fingerprint]=entry.id
			count+=1
			var vertices:=0
			for node: Node3D in garment.external:
				for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
					for index in range(mesh.mesh.get_surface_count()): vertices+=mesh.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX].size()
			max_vertices=maxi(max_vertices,vertices)
			var style: int=garment.profile.design
			if not samples[family].has(style): samples[family][style]=entry
			garment.free()
		check(count>70 and signatures.size()==count,"Every "+family+" item has distinct rendered geometry: "+str(count)+" designs")
		check(samples[family].size()==8 and max_vertices<22000,"Eight silhouette families and bounded geometry for "+family+" (peak "+str(max_vertices)+" vertices)")
	check(figure.foot_meshes.LeftLeg.visible and figure.foot_meshes.RightLeg.visible,"Switching off leg cosmetics restores both original feet")
	figure.get_parent().queue_free()
	await frames()
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1600,1000)
		for i in range(8):
			var display:=mannequin(Vector3((i%4-1.5)*2.6,0,(i/4)*4.6))
			for family: String in ["hands","legs"]:
				var garment:=Garment.new()
				display.add_child(garment)
				garment.configure(display,samples[family][i])
				garment.set_process(false)
			var label:=Label3D.new()
			label.text=["Lapped plate","Flared / lamellar","Wrapped cloth","Spiral / lattice","Winged","Fluted","Articulated","Faceted"][i]
			label.position=display.get_parent().position+Vector3(0,2.25,0)
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size=28
			label.pixel_size=.006
			scene.add_child(label)
		var camera:=Camera3D.new()
		scene.add_child(camera)
		camera.position=Vector3(0,8,14)
		camera.look_at(Vector3(0,1,2.3))
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=7.5
		camera.current=true
		await frames(4)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/garment_variety.png")
	scene.queue_free()
	print("Garment variety: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
