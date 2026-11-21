extends RefCounted
## A bounded detour through an existing shell's real door. Regional journeys and
## their physical/virtual walkers still own every metre of movement.
const MAX_DISTANCE:=64.0
const MAX_PATH_LENGTH:=190.0
var world: Node3D
var _capsule:=CapsuleShape3D.new()
func _init() -> void:
	_capsule.height=1.85; _capsule.radius=.29

func _clean_path(points: Array[Vector3]) -> PackedVector3Array:
	var result:=PackedVector3Array()
	for point: Vector3 in points:
		if result.is_empty() or result[-1].distance_to(point)>.08: result.append(point)
	return result

func _walkable(points: PackedVector3Array) -> bool:
	if points.size()<2 or not is_instance_valid(world) or not world.is_inside_tree(): return false
	var space:=world.get_world_3d().direct_space_state
	var length:=0.0
	for i in range(points.size()-1):
		var a: Vector3=points[i]; var b: Vector3=points[i+1]
		var distance:=a.distance_to(b)
		length+=distance
		if length>MAX_PATH_LENGTH or absf(a.y-b.y)>.25: return false
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=_capsule; query.collision_mask=1; query.margin=.005
		# Resting CharacterBody feet can settle a few centimetres below the
		# ideal route height. Do not mistake floor contact for a blocked path.
		query.transform=Transform3D(Basis.IDENTITY,a+Vector3.UP*.99)
		if not space.intersect_shape(query,1).is_empty(): return false
		query.motion=b-a
		var sweep:=space.cast_motion(query)
		if sweep.size()<2 or sweep[0]<.999: return false
		for step in range(ceili(distance/2.0)+1):
			var at:=a.lerp(b,minf(1,step*2.0/maxf(distance,.01)))
			var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.45,at-Vector3.UP*.35,1))
			if floor_hit.is_empty() or floor_hit.normal.y<.8 or absf(float(floor_hit.position.y)-at.y)>.18: return false
	return true

func _route_distance(route: PackedVector3Array,point: Vector3) -> float:
	var best:=INF
	for i in range(route.size()):
		best=minf(best,point.distance_to(Geometry3D.get_closest_point_to_segment(point,route[i],route[(i+1)%route.size()])))
	return best

func request(record: Dictionary,descriptor: Dictionary,station_position: Vector3) -> bool:
	if not is_instance_valid(world) or record.get("combat",false) or not record.get("valid",false) or record.get("wonders_route",false): return false
	var id:=String(record.get("code_form_id",""))
	if id.is_empty() or not record.get("route") is PackedVector3Array or record.route.size()<2 or descriptor.get("manual_review",true): return false
	if not record.get("point") is Vector3 or not station_position.is_finite() or not descriptor.get("point") is Vector3: return false
	var base: Vector3=descriptor.point
	var size: Vector3=descriptor.size
	var start: Vector3=record.point
	if absf(start.y-base.y)>.3 or absf(station_position.y-base.y)>.3: return false # Ground-floor stations only.
	if absf(station_position.x-base.x)>size.x*.5-.8 or absf(station_position.z-base.z)>size.z*.5-.8: return false
	var previous: Dictionary=record.get("career_commute",{})
	if previous.get("identity")==id and previous.get("building")==descriptor.id and previous.get("station",Vector3.INF).distance_to(station_position)<.1: return true
	# A new workplace cannot interrupt another detour halfway through a wall.
	if not previous.is_empty(): return false
	var original: PackedVector3Array=record.route.duplicate()
	var original_cursor:=int(record.get("cursor",0))
	if original_cursor<0 or original_cursor>=original.size(): return false
	var y:=base.y+.04
	var door_out: Vector3=descriptor.get("exit",base+Vector3(0,.04,size.z*.5+1.1))
	var door_in: Vector3=descriptor.get("entry",base+Vector3(0,.04,size.z*.5-.9))
	if _route_distance(original,door_out)>MAX_DISTANCE or start.distance_to(door_out)>MAX_DISTANCE+size.x: return false
	var approaches: Array[Array]=[]
	approaches.append([start,door_out])
	approaches.append([start,Vector3(start.x,y,door_out.z),door_out])
	approaches.append([start,Vector3(door_out.x,y,start.z),door_out])
	for side: float in [-1.0,1.0]:
		var edge:=base.x+side*(size.x*.5+1.0)
		approaches.append([start,Vector3(edge,y,start.z),Vector3(edge,y,door_out.z),door_out])
	var exterior:=PackedVector3Array()
	for approach: Array in approaches:
		var candidate: Array[Vector3]=[]; candidate.assign(approach)
		var path:=_clean_path(candidate)
		if _walkable(path): exterior=path; break
	if exterior.is_empty(): return false
	for gap: float in [1.65,2.25]:
		for offset: Vector3 in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
			var target:=station_position+offset*gap; target.y=y
			if absf(target.x-base.x)>size.x*.5-.7 or absf(target.z-base.z)>size.z*.5-.7: continue
			var interior:=_clean_path([door_out,door_in,Vector3(base.x,y,target.z),target])
			if not _walkable(interior): continue
			var route:=exterior.duplicate()
			for i in range(1,interior.size()): route.append(interior[i])
			var outward:=route.duplicate()
			var station_index:=route.size()-1
			# The exact validated reverse is the egress route, ending at the
			# original physical point before resuming its unchanged safe loop.
			for i in range(outward.size()-2,-1,-1): route.append(outward[i])
			for offset_index in range(original.size()): route.append(original[(original_cursor+offset_index)%original.size()])
			record.career_commute={"identity":id,"building":String(descriptor.id),"station":station_position,"approach":target,"station_index":station_index,"base_route":original,"base_cursor":original_cursor}
			record.route=route; record.cursor=1; record.checked=true; record.wait=0.0
			return true
	return false

func on_arrival(record: Dictionary) -> bool:
	var marker: Dictionary=record.get("career_commute",{})
	if marker.is_empty(): return false
	# Detour waypoint ordinals are not novel exploration/discovery facts.
	var id:=String(record.get("code_form_id",""))
	var employed:=false
	if is_instance_valid(world) and is_instance_valid(world.get("careers")):
		var worker: Dictionary=world.careers.model.workers.get(id,{})
		var primary: Dictionary=world.careers.model.employments.get(String(worker.get("primary","")),{})
		employed=primary.get("workplace")==marker.building and primary.get("status","")!="ended"
	if id!=marker.identity or not employed:
		# Existing walkers cache the current route until their arrival callback
		# returns. Restore after that frame, at an actual original street node.
		# Never truncate a journey while its body is inside an old workplace.
		if not marker.get("restoring",false):
			for point: Vector3 in marker.base_route:
				if record.point.distance_to(point)<.6:
					marker.restoring=true; call_deferred("_restore_when_safe",record); break
		return true
	if record.get("combat",false): return true
	if int(record.get("cursor",-1))!=int(marker.station_index) or not record.get("point") is Vector3: return true
	if record.point.distance_to(marker.approach)>.9 or record.point.distance_to(marker.station)>3.5: return true
	if not is_instance_valid(world) or not is_instance_valid(world.get("careers")) or not is_instance_valid(world.get("civilization")): return true
	if world.civilization.autonomy._unavailable(String(marker.identity)): return true
	world.careers.npc_step(String(marker.identity),float(world.civilization.world_seconds))
	return true

func _restore_when_safe(record: Dictionary) -> void:
	if not restore_base(record) and record.get("career_commute") is Dictionary: record.career_commute.erase("restoring")

func restore_base(record: Dictionary) -> bool:
	var marker: Dictionary=record.get("career_commute",{})
	if marker.is_empty() or not marker.get("base_route") is PackedVector3Array: return false
	var route: PackedVector3Array=marker.base_route
	for index in range(route.size()):
		if record.point.distance_to(route[index])<.6:
			record.route=route; record.cursor=(index+1)%route.size(); record.erase("career_commute")
			return true
	return false
