extends SceneTree
## Traverse route junctions with the real controller and audit exposed guard edges.
class Intent extends Node:
	var move := Vector2.ZERO
	var look := Vector2.ZERO
	var mouse_look := Vector2.ZERO
	var sprint := false
	var boost := false
	func sample() -> void: pass
	func consume_jump() -> bool: return false
	func consume_dodge() -> bool: return false
	func is_blocking() -> bool: return false
	func update_combat_hold(_delta: float) -> void: pass
	func consume_combat_requests() -> Array[Dictionary]: return []
	func consume_lock_requests() -> Array[Vector2]: return []
	func reset_combat_input() -> void: pass

var world: Node3D
var city: Node3D
var actor: CharacterBody3D
var input: Intent
var space: PhysicsDirectSpaceState3D
var excluded: Array[RID] = []
var capsule: CapsuleShape3D
var checks := 0
var failures := 0
var hz := 60
var floor_samples := 0
var capsule_samples := 0
var guard_samples := 0
var boundary_samples := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func floor_at(point: Vector3) -> Dictionary:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.32,point-Vector3.UP*0.32,1,excluded))
	if not hit.is_empty(): return hit
	# Adjacent convex sectors share an exact edge. Physics ray precision at
	# that edge must not report a gap that the full player capsule traverses.
	for offset: Vector3 in [Vector3(0.005,0,0),Vector3(-0.005,0,0),Vector3(0,0,0.005),Vector3(0,0,-0.005)]:
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(point+offset+Vector3.UP*0.32,point+offset-Vector3.UP*0.32,1,excluded))
		if not hit.is_empty(): return hit
	return {}

func capsule_query(point: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*0.95)
	query.collision_mask = 1
	query.exclude = excluded
	query.margin = 0.002
	return query

func dense_path(path: PackedVector3Array, label: String, lanes: bool = true) -> void:
	var missing_floor := 0
	var blocked_body := 0
	var blocked_sweeps := 0
	for i in range(path.size()-1):
		var a := path[i]
		var b := path[i+1]
		var direction := b-a
		var side := Vector3(-direction.z,0,direction.x).normalized()
		var offsets: Array = [-0.65,0.0,0.65] if lanes else [0.0]
		for offset: float in offsets:
			var previous: Vector3
			var have_previous := false
			var samples := maxi(1,ceili(a.distance_to(b)/0.30))
			for n in range(samples+1):
				var point := a.lerp(b,float(n)/samples)+side*offset
				var floor_hit := floor_at(point)
				floor_samples += 1
				if floor_hit.is_empty() or floor_hit.normal.y<0.9 or absf(floor_hit.position.y-point.y)>0.20:
					missing_floor += 1
					if missing_floor<=3: print(label," missing route support at ",point," hit ",floor_hit)
					have_previous = false
					continue
				point.y = floor_hit.position.y+0.012
				var query := capsule_query(point)
				capsule_samples += 1
				if not space.intersect_shape(query,1).is_empty():
					blocked_body += 1
					if blocked_body<=3: print(label," blocked capsule at ",point)
				if have_previous:
					query = capsule_query(previous)
					query.motion = point-previous
					var sweep := space.cast_motion(query)
					if sweep[0]<0.999:
						blocked_sweeps += 1
						if blocked_sweeps<=3: print(label," blocked forward sweep ",previous," -> ",point)
					query = capsule_query(point)
					query.motion = previous-point
					sweep = space.cast_motion(query)
					if sweep[0]<0.999:
						blocked_sweeps += 1
						if blocked_sweeps<=3: print(label," blocked reverse sweep ",point," -> ",previous)
				previous = point
				have_previous = true
	check(missing_floor == 0,label+" has continuous floor across the walking width")
	check(blocked_body == 0 and blocked_sweeps == 0,label+" passes torso/head capsules and sweeps in both directions")

func surface_height(point: Vector3, surface: Dictionary) -> float:
	var points: PackedVector3Array = surface.points
	if points.size()<3: return INF
	var polygon := PackedVector2Array()
	for vertex: Vector3 in points: polygon.append(Vector2(vertex.x,vertex.z))
	if not Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),polygon): return INF
	var normal := (points[1]-points[0]).cross(points[2]-points[0])
	if absf(normal.y)<0.00001: return INF
	return points[0].y-(normal.x*(point.x-points[0].x)+normal.z*(point.z-points[0].z))/normal.y

func span_distance(point: Vector3, span: Dictionary) -> float:
	var a: Vector3 = span.a
	var b: Vector3 = span.b
	var edge := Vector2(b.x-a.x,b.z-a.z)
	var t := clampf(Vector2(point.x-a.x,point.z-a.z).dot(edge)/maxf(0.00001,edge.length_squared()),0,1)
	var closest := a.lerp(b,t)
	if absf(closest.y-point.y)>0.20: return INF
	return Vector2(point.x-closest.x,point.z-closest.z).length()

func audit_guards() -> void:
	var uncovered := 0
	var absent_rail := 0
	var surfaces: Array = city.walk_surfaces
	var spans: Array = city.guard_spans
	for surface: Dictionary in surfaces:
		if surface.get("portal",false): continue
		var points: PackedVector3Array = surface.points
		var center := Vector3.ZERO
		for point: Vector3 in points: center += point
		center /= float(points.size())
		for i in range(points.size()):
			var a := points[i]
			var b := points[(i+1)%points.size()]
			var edge := b-a
			var outward := Vector3(-edge.z,0,edge.x).normalized()
			if outward.dot((a+b)*0.5-center)<0: outward = -outward
			var count := maxi(1,ceili(edge.length()/0.45))
			for n in range(count):
				var point := a.lerp(b,(n+0.5)/count)
				var probe := point+outward*0.16
				var exposed := true
				for other: Dictionary in surfaces:
					var neighbor_height := surface_height(probe,other)
					if is_finite(neighbor_height) and absf(neighbor_height-point.y)<0.22:
						exposed = false
						break
				if not exposed: continue
				boundary_samples += 1
				var covered := false
				for span: Dictionary in spans:
					if span_distance(point,span)<0.23:
						covered = true
						break
				if not covered:
					uncovered += 1
					if uncovered<=8: print("Unprotected ",surface.tag," boundary at ",point)
	for span: Dictionary in spans:
		var a: Vector3 = span.a
		var b: Vector3 = span.b
		var edge := b-a
		var normal := Vector3(-edge.z,0,edge.x).normalized()
		var count := maxi(1,ceili(edge.length()/0.45))
		for n in range(count):
			var at := a.lerp(b,(n+0.5)/count)+Vector3.UP
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at-normal*0.25,at+normal*0.25,1,excluded))
			guard_samples += 1
			if hit.is_empty():
				absent_rail += 1
				if absent_rail<=5: print("Missing physical handrail at ",at)
	check(boundary_samples>100 and uncovered == 0,"All sampled exposed deck/landing/lookout boundaries have guards")
	check(guard_samples>100 and absent_rail == 0,"Every declared guard span has real rail collision at 0.45m spacing")

func walk_path(path: PackedVector3Array, label: String) -> void:
	input.move = Vector2.ZERO
	actor.respawn()
	actor.target_lock.clear()
	actor.position = path[0]+Vector3.UP*0.10
	actor.velocity = Vector3.ZERO
	world.camera_rig.yaw = 0
	await frames(ceili(0.35*hz))
	var complete := actor.is_on_floor()
	for i in range(1,path.size()):
		if not complete: break
		var target := path[i]
		var budget := ceili((Vector2(target.x-actor.position.x,target.z-actor.position.z).length()/actor.walk_speed+2.5)*hz)
		var reached := false
		for tick in range(budget):
			var delta := Vector2(target.x-actor.position.x,target.z-actor.position.z)
			if delta.length()<0.18:
				reached = true
				break
			input.move = delta.normalized()*minf(1.0,delta.length()/0.55)
			await frames(1)
			if actor.position.y<minf(path[i-1].y,target.y)-0.55: break
		if not reached:
			print(label," stopped at ",actor.position," while walking toward ",target)
			complete = false
	input.move = Vector2.ZERO
	await frames(ceili(0.20*hz))
	check(complete and actor.is_on_floor(),label+" is traversable with normal walking and no jump")

func north_loop() -> PackedVector3Array:
	var path := PackedVector3Array([Vector3(-11,12.26,-45),Vector3(-11,12.26,-46.5),Vector3(-11,16.26,-55.5),Vector3(-11,16.26,-64)])
	# North half of the promenade links both streets without crossing the monument.
	for i in range(1,25):
		var angle := -PI*0.5-i*PI/24
		path.append(Vector3(sin(angle)*11,16.26,-64+cos(angle)*11))
	path.append(Vector3(11,16.26,-45))
	return path

func arc_path(side: int) -> PackedVector3Array:
	var height := 12.26 if side<0 else 16.26
	var center := Vector3(side*36,height,-28 if side<0 else -30)
	var path := PackedVector3Array()
	# The landing overlaps the curve near its 55-degree entry.
	path.append(Vector3(side*15,height,-13.1 if side<0 else -15.1))
	for i in range(11,17):
		var angle := i*PI*0.5/16*(1 if side<0 else -1)
		path.append(center+Vector3(sin(angle)*25,0,cos(angle)*25))
	path.append(Vector3(side*11,height,-42))
	path.append(Vector3(side*11,height,-48 if side>0 else -46))
	return path

func promenade_circle() -> PackedVector3Array:
	var path := PackedVector3Array()
	for i in range(49):
		var angle := -PI*0.5-i*TAU/48
		path.append(Vector3(sin(angle)*11,16.26,-64+cos(angle)*11))
	return path

func stair_top_path(side: int) -> PackedVector3Array:
	var steps := 48 if side<0 else 64
	var start_z := 12.5 if side<0 else 15.3
	var tread := 0.5 if side<0 else 0.45
	var floor_y := 12.26 if side<0 else 16.26
	# Approach from the flat foot as during play, then maintain normal walking
	# momentum up the flight before checking the final treads and portal.
	var path := PackedVector3Array([Vector3(side*15,0.12,start_z+0.8)])
	for step in range(steps-5,steps):
		path.append(Vector3(side*15,0.12+(step+1)*0.25,start_z-(step+0.5)*tread))
	path.append(Vector3(side*15,floor_y,-13.1 if side<0 else -15.1))
	var center := Vector3(side*36,floor_y,-28 if side<0 else -30)
	for i in range(11,14):
		var angle := i*PI*0.5/16*(1 if side<0 else -1)
		path.append(center+Vector3(sin(angle)*25,0,cos(angle)*25))
	return path

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	actor = world.player
	actor.visual.retrieval.enabled = false
	city = world.get_node("CentralDistrict/Metropolis")
	input = Intent.new()
	root.add_child(input)
	actor.controls = input
	world.camera_rig.controls = input
	await frames(15)
	space = world.get_world_3d().direct_space_state
	excluded = [actor.get_rid(),world.sparring_partner.get_rid()]
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.85
	check(city.walk_surfaces.size()>50 and city.guard_spans.size()>20,"Walkable surfaces and exposed boundary guards are registered")
	var crossing := PackedVector3Array([Vector3(-11,12.26,-45),Vector3(-9.5,12.26,-45),Vector3(9.5,16.26,-45),Vector3(11,16.26,-45)])
	dense_path(crossing,"The sloped cross-city bridge and both open T-junctions")
	for side in [-1,1]:
		var path := arc_path(side)
		dense_path(path,("West" if side<0 else "East")+" stair landing, curve and straight")
		await walk_path(path,("West" if side<0 else "East")+" landing-to-straight route")
		path.reverse()
		await walk_path(path,("West" if side<0 else "East")+" straight-to-landing route")
		var stairs := stair_top_path(side)
		await walk_path(stairs,("West" if side<0 else "East")+" stair approach and full flight through the landing portal")
		stairs.reverse()
		await walk_path(stairs,("West" if side<0 else "East")+" landing portal back onto the staircase")
	var loop := north_loop()
	dense_path(loop,"The rising west route and complete north promenade")
	await walk_path(loop,"West ramp to east avenue through north promenade")
	loop.reverse()
	await walk_path(loop,"East avenue through north promenade to west ramp")
	var promenade := promenade_circle()
	dense_path(promenade,"The complete circular civic promenade")
	await walk_path(promenade,"Clockwise circuit of the civic promenade")
	promenade.reverse()
	await walk_path(promenade,"Counterclockwise circuit of the civic promenade")
	await walk_path(crossing,"West-to-east crossing")
	crossing.reverse()
	await walk_path(crossing,"East-to-west crossing")
	for side in [-1,1]:
		var floor_y := 12.26 if side<0 else 16.26
		var center_z := -3.0 if side<0 else -5.0
		var center := Vector3(side*35,floor_y,center_z)
		# Enter through the overlapped floor area, clear of the exposed inside corner.
		var start := Vector3(side*35,floor_y,center_z-2)
		dense_path(PackedVector3Array([start,center,center+Vector3.FORWARD*-1]),("West" if side<0 else "East")+" finished southern lookout",false)
		var arc_center := Vector3(side*36,floor_y,-28 if side<0 else -30)
		var path := PackedVector3Array([center,start])
		for i in range(1,6):
			var angle := i*PI*0.5/16*(1 if side<0 else -1)
			path.append(arc_center+Vector3(sin(angle)*25,0,cos(angle)*25))
		await walk_path(path,("West" if side<0 else "East")+" lookout joins its curved skyway")
	audit_guards()
	input.move = Vector2.ZERO
	actor.respawn()
	print("Skyway route audit: ",floor_samples," floor samples, ",capsule_samples," body capsules, ",boundary_samples," exposed-edge samples, ",guard_samples," physical rail probes")
	world.queue_free()
	input.queue_free()
	await process_frame
	print("Skyway route verification: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
