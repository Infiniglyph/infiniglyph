extends SceneTree
## Real garment geometry and skeleton; no inventory saves or locomotion changes.
const Database = preload("res://scripts/equipment_database.gd")
const Visual = preload("res://scripts/character_visual.gd")
const Garment = preload("res://scripts/equipment_garment.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
const MountedPose = preload("res://scripts/mounted_rider_pose.gd")
class Actions extends Node:
	var vehicle: CharacterBody3D
class Actor extends CharacterBody3D:
	var world_actions: Actions
class Ride extends CharacterBody3D:
	var kind := "motorcycle"
var checks := 0
var failures := 0
var hz := 60
var actor: Actor
var figure: Node3D
var cloth: Node3D
var plate: Node3D
var capture := false
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func tick(seconds: float) -> void:
	for frame in range(int(ceil(seconds*hz))):
		cloth._process(1.0/hz)
		plate._process(1.0/hz)
func make_garment(entry: Dictionary,flexible: bool) -> Node3D:
	var definition := entry.duplicate(true)
	definition.geometry.tailoring.cut = "cloth" if flexible else "plate"
	definition.geometry.tailoring.hem = .78
	definition.geometry.tailoring.cape = .96 if flexible else 0.0
	definition.geometry.tailoring.tabard = .68 if flexible else 0.0
	definition.geometry.tailoring.ragged = flexible
	var garment := Garment.new()
	figure.add_child(garment)
	garment.configure(figure,definition)
	garment.set_process(false)
	garment._process(0)
	return garment
func mesh_nodes(garment: Node3D) -> Array[Node]:
	var result: Array[Node] = garment.find_children("*","MeshInstance3D",true,false)
	for external: Node3D in garment.external:
		if external.get_parent()!=garment: result.append_array(external.find_children("*","MeshInstance3D",true,false))
	return result
func seam_error(garment: Node3D) -> float:
	var result := 0.0
	for tail: Node3D in garment.tails:
		var origin: Node3D = figure.chest if tail.get_meta("cape") else figure.pelvis
		var seam: Vector3 = tail.get_meta("seam")
		var offset := Vector3(0,.43,0) if tail.get_meta("cape") else Vector3.ZERO
		if actor.world_actions.vehicle!=null: offset += Vector3(0,.065,0)
		result=maxf(result,tail.global_position.distance_to(origin.to_global(seam+offset)))
	return result
func cloth_vertices(garment: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for tail: Node3D in garment.tails:
		for mesh: MeshInstance3D in tail.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var points: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for point: Vector3 in points: result.append(figure.pelvis.to_local(mesh.to_global(point)))
	return result
func real_vehicle(kind: String) -> CharacterBody3D:
	var vehicle := Vehicle.new()
	vehicle.record={"id":999,"point":Vector3.ZERO,"kind":kind,"color":Color("b395ff"),"yaw":0.0,"traffic":false,"taken":true,"driver":{"tint":Color.CYAN,"body_profile":"male"}}
	vehicle.set_physics_process(false)
	root.add_child(vehicle)
	vehicle.set_physics_process(false)
	return vehicle
func rider_pose(vehicle: CharacterBody3D) -> void:
	actor.world_actions.vehicle=vehicle
	var contacts: Dictionary=vehicle.rider_anchors()
	actor.rotation=Vector3.ZERO
	actor.position=vehicle.to_global(contacts.hip)-Vector3.UP*figure.REST_HIP_HEIGHT
	figure.pelvis.rotation=Vector3.ZERO
	figure.chest.rotation=Vector3(float(contacts.chest_pitch),0,0)
	for side: String in ["Left","Right"]:
		var key:=side.to_lower()
		MountedPose.solve_limb(figure.joints[side+"Leg"],vehicle.to_global(contacts[key+"_foot"]),contacts.knee_pole,.45,.45)
		var elbow: Vector3=contacts.elbow_pole
		elbow.x=-.35 if side=="Left" else .35
		MountedPose.solve_limb(figure.joints[side+"Arm"],vehicle.to_global(contacts[key+"_hand"]),elbow,.30,.29)
	cloth._process(1.0/hz)
func image_pose(camera: Camera3D,label: String,point: Vector3,target: Vector3) -> void:
	camera.position=point
	camera.look_at(target)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/equipment_cloth_"+label+".png")
	print("CLOTH CAPTURE: ",label)
func legs_clear_of_cloth() -> bool:
	for tail: Node3D in cloth.tails:
		for mesh: MeshInstance3D in tail.find_children("*","MeshInstance3D",true,false):
			if not mesh.mesh is ArrayMesh: continue
			var points: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for side: String in ["Left","Right"]:
				var joint: Node3D=figure.joints[side+"Leg"]
				var knee: Node3D=joint.get_node("Hinge")
				for segment: Array in [[joint.global_position,knee.global_position],[knee.global_position,knee.to_global(Vector3(0,-.45,0))]]:
					for i in range(0,points.size(),3):
						var hit: Variant=Geometry3D.segment_intersects_triangle(segment[0],segment[1],mesh.to_global(points[i]),mesh.to_global(points[i+1]),mesh.to_global(points[i+2]))
						if hit!=null and hit.distance_to(segment[0])>.001 and hit.distance_to(segment[1])>.001: return false
	return true
func capture_suite(rest: Dictionary) -> void:
	plate.free()
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.current=true
	camera.fov=42
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute("res://captures")
	actor.rotation=Vector3.ZERO
	actor.position=Vector3.ZERO
	for key: String in rest: figure.joints[key].transform=rest[key]
	figure.chest.rotation=Vector3(.13,0,0)
	figure.joints.RightLeg.rotation.x=-.65
	figure.joints.RightLeg.get_node("Hinge").rotation.x=.24
	figure.joints.LeftLeg.rotation.x=.45
	figure.joints.LeftLeg.get_node("Hinge").rotation.x=.68
	figure.joints.RightArm.rotation.x=.45
	figure.joints.LeftArm.rotation.x=-.45
	actor.velocity=Vector3(0,0,9)
	for frame in range(hz): cloth._process(1.0/hz)
	await image_pose(camera,"walk",Vector3(3.4,1.55,3.8),Vector3(0,1.0,0))
	var vehicle:=real_vehicle("motorcycle")
	actor.velocity=Vector3.ZERO
	rider_pose(vehicle)
	await image_pose(camera,"motorcycle",Vector3(3.6,1.85,-3.6),Vector3(0,1.0,-.1))
	var minimum_y:=INF
	for point: Vector3 in cloth_vertices(cloth): minimum_y=minf(minimum_y,figure.pelvis.to_global(point).y)
	check(minimum_y>.76,"Actual sport-bike rider pose keeps every cloth vertex above the rear wheel")
	check(legs_clear_of_cloth(),"Folded bike cloth does not intersect either thigh or shin")
	var cape_trails := true
	for tail: Node3D in cloth.tails:
		if not tail.get_meta("cape"): continue
		var direction: Vector3 = (figure.pelvis.global_basis.inverse()*(tail.global_basis*Vector3.DOWN)).normalized()
		cape_trails=cape_trails and direction.z<-.95 and absf(direction.y)<.20
	check(cape_trails,"Shoulder capes trail horizontally on a leaned rider instead of becoming upright flags")
	vehicle.free()
	vehicle=real_vehicle("car")
	rider_pose(vehicle)
	await image_pose(camera,"car",Vector3(5.0,2.3,-4.8),Vector3(0,.95,0))
	vehicle.free()
	actor.world_actions.vehicle=null
	actor.position=Vector3.ZERO
	figure.chest.rotation=Vector3.ZERO
	for key: String in rest: figure.joints[key].transform=rest[key]
	for frame in range(hz*2): cloth._process(1.0/hz)
	await image_pose(camera,"dismount",Vector3(3.4,1.55,3.8),Vector3(0,1.0,0))
	camera.free()
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
		if arg=="--capture": capture=true
	actor=Actor.new()
	actor.world_actions=Actions.new()
	actor.add_child(actor.world_actions)
	figure=Visual.new()
	figure.live_retrieval=false
	actor.add_child(figure)
	root.add_child(actor)
	var entry: Dictionary
	for item: Dictionary in Database.all():
		if item.family=="body":
			entry=item
			break
	cloth=make_garment(entry,true)
	plate=make_garment(entry,false)
	var meshes_before := mesh_nodes(cloth)
	var vertex_count := 0
	for mesh: MeshInstance3D in meshes_before:
		for surface in range(mesh.mesh.get_surface_count()): vertex_count+=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
	var joints_before: Dictionary = {}
	for key: String in figure.joints: joints_before[key]=figure.joints[key].transform
	check(cloth.tails.size()==11 and plate.tails.size()==6,"Cloth uses split hems, a cape and tabards; plate keeps six firm articulated tassets")
	var front: Node3D = cloth.tails[0]
	var back: Node3D = cloth.tails[2]
	figure.joints.RightLeg.rotation.x=-.65
	tick(.45)
	check(float(front.get_meta("cloth_angles").x)<-.45 and absf(float(back.get_meta("cloth_angles").x))<.03,"Forward thigh swing carries its front hem clear while the rear hem stays supported")
	figure.joints.RightLeg.rotation.x=.65
	tick(.45)
	check(float(back.get_meta("cloth_angles").x)>.40 and absf(float(front.get_meta("cloth_angles").x))<.03,"Backward thigh swing carries its rear hem without pulling the front panel backward")
	check(seam_error(cloth)<.00001,"Leg articulation and panel bends keep every sewn hip and shoulder seam pinned")
	figure.joints.RightLeg.rotation=Vector3.ZERO
	actor.velocity=Vector3(0,0,12)
	tick(.8)
	var cloth_pitch: float=front.get_meta("cloth_angles").x
	var plate_pitch: float=plate.tails[0].get_meta("cloth_angles").x
	check(cloth_pitch>.10 and cloth_pitch>plate_pitch*4,"Flexible fabric trails behind motion while plate remains firm")
	check(front.get_meta("bend") is Node3D and front.get_meta("bend_angles").length()>.10 and not plate.tails[0].has_meta("bend"),"Free cloth hems flex at a second seam instead of moving as one rigid panel")
	actor.velocity=Vector3(0,0,-12)
	tick(.8)
	check(front.get_meta("cloth_angles").x<-.10 and front.get_meta("bend_angles").x<-.10,"Backpedaling trails cloth toward character-front, opposing actual travel")
	actor.velocity=Vector3(12,0,0)
	tick(.8)
	check(front.get_meta("cloth_angles").z<-.08 and front.get_meta("bend_angles").z<-.04,"Strafing trails both cloth bands away from lateral travel")
	actor.velocity=Vector3(0,0,12)
	tick(.8)
	# Apply the same short turn/acceleration over real time at each rate,
	# rather than a one-frame yaw teleport whose angular impulse varies by Hz.
	for frame in range(int(ceil(.15*hz))):
		actor.rotation.y+=2.5/hz
		actor.velocity=Vector3(0,0,12).lerp(Vector3(8,0,8),clampf((frame+1)/(.15*hz),0,1))
		tick(1.0/hz)
	check(absf(float(front.get_meta("cloth_angles").y))>.005 and cloth._inertia.length()>.02,"Turning and acceleration add a bounded delayed cloth response")
	actor.velocity=Vector3.ZERO
	tick(3)
	check(cloth._flow<.0001 and cloth._inertia.length()<.0001 and front.get_meta("cloth_angles").length()<.001 and front.get_meta("bend_angles").length()<.001,"Cloth movement settles fully after stopping without permanent tilt")
	var ride := Ride.new()
	root.add_child(ride)
	actor.world_actions.vehicle=ride
	tick(1.0/hz)
	var lowest := INF
	var furthest_back := 0.0
	for point: Vector3 in cloth_vertices(cloth):
		lowest=minf(lowest,point.y)
		furthest_back=minf(furthest_back,point.z)
	check(lowest>-.18 and furthest_back<-.6 and seam_error(cloth)<.00001,"Stationary bike hems fold behind the saddle above the wheel, around their own seams")
	ride.kind="car"
	tick(1.0/hz)
	var hidden := true
	for tail: Node3D in cloth.tails: hidden=hidden and not tail.visible
	check(hidden,"An enclosed car tucks away long hems and capes")
	ride.kind="truck"
	tick(1.0/hz)
	for tail: Node3D in cloth.tails: hidden=hidden and not tail.visible
	check(hidden,"An enclosed truck uses the same mounted cloth treatment")
	actor.world_actions.vehicle=null
	tick(1.0/hz)
	var restored := true
	for tail: Node3D in cloth.tails: restored=restored and tail.visible and tail.get_meta("cloth_angles").length()<.01
	check(restored and seam_error(cloth)<.00001,"Dismount immediately restores foot-bound clothing with no lingering bike fold")
	for cycle in range(80):
		figure.joints.LeftLeg.rotation.x=sin(cycle*.3)*.7
		figure.joints.RightLeg.rotation.x=-sin(cycle*.3)*.7
		actor.rotation.y=cycle*.07
		actor.velocity=Vector3(sin(cycle*.07),0,cos(cycle*.07))*10
		tick(1.0/hz)
	check(seam_error(cloth)<.00001 and mesh_nodes(cloth)==meshes_before,"Repeated gait and turns preserve attachment positions and reuse every mesh")
	var skeleton_unchanged := true
	for key: String in joints_before:
		if key in ["LeftLeg","RightLeg"]: continue
		skeleton_unchanged=skeleton_unchanged and figure.joints[key].transform.is_equal_approx(joints_before[key])
	check(skeleton_unchanged and figure.joints.LeftLeg.position.is_equal_approx(joints_before.LeftLeg.origin) and figure.joints.RightLeg.position.is_equal_approx(joints_before.RightLeg.origin),"Clothing only updates its own transforms and leaves skeleton joint origins intact")
	# The store mannequin deliberately has no world_actions property.
	var mannequin := CharacterBody3D.new()
	var preview := Visual.new()
	preview.live_retrieval=false
	mannequin.add_child(preview)
	root.add_child(mannequin)
	var preview_garment := Garment.new()
	preview.add_child(preview_garment)
	preview_garment.configure(preview,entry)
	preview_garment.set_process(false)
	preview_garment._process(0)
	check(preview_garment.global_position.is_finite() and preview_garment._flow==0,"The store mannequin fits safely without gameplay or mount state")
	mannequin.visible=false
	if capture: await capture_suite(joints_before)
	actor.free()
	mannequin.free()
	ride.free()
	print("EQUIPMENT CLOTH RESOURCES: ",meshes_before.size()," fixed meshes, ",vertex_count," vertices for the 11-panel cloth stress outfit")
	print("EQUIPMENT CLOTH FLOW: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
