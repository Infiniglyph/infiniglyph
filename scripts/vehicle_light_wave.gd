extends MeshInstance3D
## A bounded world-space light wall. Swept contacts prevent fast targets from
## crossing between physics samples; one cooldown per victim across all panels.
const Persistence = preload("res://scripts/persistent_trail.gd")
const LIFETIME := 4.0
const HEIGHT := 1.2
const DAMAGE := 750.0
const MAX_SEGMENTS := 128
const CONTACT_INTERVAL := .5
var vehicle: CharacterBody3D
var owner_actor: WeakRef
var _owner_identity := ""
var enabled := false
var segments: Array[Dictionary] = []
var _last := Vector3.ZERO
var _vehicle_at := Vector3.ZERO
var _has_last := false
var _targets: Array[Node3D] = []
var _previous: Dictionary = {}
var _hit_until: Dictionary = {}
var _draw_clock := 0.0
var _ink: StandardMaterial3D
var _edge: StandardMaterial3D
var trail_color := Color.WHITE

func _ready() -> void:
	name="VehicleLightWave"
	top_level=true
	global_transform=Transform3D.IDENTITY
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh=ImmediateMesh.new()
	visible=false
	# Use the vehicle's wire color, retaining its hue and saturation at full value.
	trail_color=vehicle.record.color
	trail_color.v=1.0
	trail_color.a=1.0
	_ink=StandardMaterial3D.new()
	_ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_ink.cull_mode=BaseMaterial3D.CULL_DISABLED
	_ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_ink.vertex_color_use_as_albedo=true
	_edge=_ink.duplicate()
	set_physics_process(false)

func set_enabled(value: bool) -> void:
	enabled=value
	_has_last=false
	if value:
		var driver: Node=vehicle.driving_actor()
		var identity:=_identity(driver)
		if owner_actor!=null and (owner_actor.get_ref()!=driver or identity!=_owner_identity): _clear_owned_trail()
		owner_actor=weakref(driver)
		_owner_identity=identity
		_vehicle_at=vehicle.global_position
	set_physics_process(value or not segments.is_empty())

func _identity(driver: Node) -> String:
	if not is_instance_valid(driver): return ""
	var native:=String(driver.get_meta("code_form_id",""))
	return "native:"+native if not native.is_empty() else "actor:"+str(driver.get_instance_id())

func _clear_owned_trail() -> void:
	segments.clear(); _previous.clear(); _hit_until.clear(); _targets.clear()
	_has_last=false; _draw_clock=0

func now() -> float: return float(Engine.get_physics_frames())/Engine.physics_ticks_per_second

func _physics_process(delta: float) -> void:
	var time:=now()
	if Persistence.expire(segments,time,LIFETIME): _draw_clock=0
	if enabled and (not is_instance_valid(vehicle.driving_actor()) or vehicle.health<=0): enabled=false
	if enabled and _identity(vehicle.driving_actor())!=_owner_identity:
		# Reassigning a physical vehicle never transfers its old damaging panels
		# to a new player or the next native inhabitant of a driver census slot.
		_clear_owned_trail()
		enabled=false; vehicle.wave_enabled=false
	if enabled:
		var point: Vector3=vehicle.to_global(Vector3(0,.08,-vehicle.dimensions.z*.5-.25))
		if vehicle.global_position.distance_to(_vehicle_at)>maxf(12,vehicle.velocity.length()*delta*4):
			segments.clear()
			_draw_clock=0
			_has_last=false
		_vehicle_at=vehicle.global_position
		if _has_last and _last.distance_to(point)>=.75:
			Persistence.append(segments,{"a":_last,"b":point,"born":time},MAX_SEGMENTS)
			_draw_clock=0
			_last=point
		elif not _has_last:
			_last=point
			_has_last=true
	# Refresh the small live roster every tick: a newly streamed fast vehicle
	# must not have a grace period in which it can pass through the wall.
	_targets.clear()
	var found: Dictionary={}
	for group: StringName in [&"vehicle_wave_targets",&"combat_targets"]:
		for target: Node in get_tree().get_nodes_in_group(group):
			if target is Node3D and not found.has(target.get_instance_id()):
				_targets.append(target)
				found[target.get_instance_id()]=true
	for id in _previous.keys():
		if not found.has(id):
			_previous.erase(id)
			_hit_until.erase(id)
	var wall_bounds:=Rect2()
	for index in range(segments.size()):
		var segment: Dictionary=segments[index]
		var a:=Vector2(segment.a.x,segment.a.z)
		if index==0: wall_bounds=Rect2(a,Vector2.ZERO)
		wall_bounds=wall_bounds.expand(a).expand(Vector2(segment.b.x,segment.b.z))
	var owner: Node=owner_actor.get_ref() if owner_actor!=null else null
	if is_instance_valid(owner):
		for target in _targets:
			if not is_instance_valid(target) or target==vehicle or target==owner or target.is_queued_for_deletion(): continue
			var driver_id:=String(owner.get_meta("code_form_id",""))
			var target_id:=String(target.get_meta("code_form_id",target.get("code_form_id") if target.get("code_form_id")!=null else ""))
			if not driver_id.is_empty() and driver_id==target_id: continue
			var id:=target.get_instance_id()
			if target.get_world_3d()!=get_world_3d() or not target.is_visible_in_tree():
				_previous.erase(id)
				continue
			var at:=target.global_transform
			var before: Transform3D=_previous.get(id,at)
			_previous[id]=at
			if float(_hit_until.get(id,0))>time: continue
			var extent: Vector3=target.dimensions if target.get("dimensions") is Vector3 else Vector3(.60,1.85,.60)
			var swept_bounds:=Rect2(Vector2(before.origin.x,before.origin.z),Vector2.ZERO).expand(Vector2(at.origin.x,at.origin.z)).grow(Vector2(extent.x,extent.z).length()*.5+.05)
			if segments.is_empty() or not wall_bounds.grow(.01).intersects(swept_bounds,true): continue
			var polygon:=PackedVector2Array()
			for transform: Transform3D in [before,at]:
				for x: float in [-1,1]:
					for z: float in [-1,1]:
						var corner:=transform*Vector3(x*(extent.x*.5+.04),0,z*(extent.z*.5+.04))
						polygon.append(Vector2(corner.x,corner.z))
			polygon=Geometry2D.convex_hull(polygon)
			var bounds:=Rect2(polygon[0],Vector2.ZERO)
			for corner in polygon: bounds=bounds.expand(corner)
			for segment in segments:
				var low: float=minf(segment.a.y,segment.b.y)
				var high: float=maxf(segment.a.y,segment.b.y)+HEIGHT
				if minf(before.origin.y,at.origin.y)>high or maxf(before.origin.y,at.origin.y)+extent.y<low: continue
				var a:=Vector2(segment.a.x,segment.a.z)
				var b:=Vector2(segment.b.x,segment.b.z)
				if not bounds.intersects(Rect2(a,Vector2.ZERO).expand(b).grow(.01),true): continue
				var touches:=Geometry2D.is_point_in_polygon(a,polygon) or Geometry2D.is_point_in_polygon(b,polygon)
				for edge in range(polygon.size()-1):
					if touches: break
					touches=Geometry2D.segment_intersects_segment(a,b,polygon[edge],polygon[edge+1])!=null
				if not touches: continue
				_hit_until[id]=time+CONTACT_INTERVAL
				var contact: Vector3=Geometry3D.get_closest_point_to_segment(target.global_position,segment.a,segment.b)+Vector3.UP*.8
				if target.has_method("receive_combat_hit"):
					target.receive_combat_hit(DAMAGE,contact,owner,{"action":&"vehicle_wave","vehicle_wave":true,"damage":DAMAGE,"parryable":false,"hit_stun_level":0.0,"attack_serial":get_instance_id()+int(time/CONTACT_INTERVAL),"contact":contact})
				break
	_draw_clock-=delta
	if _draw_clock<=0:
		_draw_clock=.05
		draw_wave(time)
	if not enabled and segments.is_empty():
		mesh.clear_surfaces()
		visible=false
		_previous.clear()
		_hit_until.clear()
		set_physics_process(false)

func draw_wave(time: float) -> void:
	mesh.clear_surfaces()
	visible=not segments.is_empty()
	if segments.is_empty(): return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,_ink)
	for segment in segments:
		var opacity := Persistence.opacity(segment.born,time,LIFETIME,.6)
		mesh.surface_set_color(Color(trail_color,.58*opacity))
		for point: Vector3 in [segment.a,segment.b,segment.b+Vector3.UP*HEIGHT,segment.a,segment.b+Vector3.UP*HEIGHT,segment.a+Vector3.UP*HEIGHT]: mesh.surface_add_vertex(point)
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,_edge)
	for segment in segments:
		var opacity := Persistence.opacity(segment.born,time,LIFETIME,.6)
		mesh.surface_set_color(Color(trail_color,opacity))
		for height: float in [0,HEIGHT*.5,HEIGHT]:
			mesh.surface_add_vertex(segment.a+Vector3.UP*height)
			mesh.surface_add_vertex(segment.b+Vector3.UP*height)
	mesh.surface_end()
