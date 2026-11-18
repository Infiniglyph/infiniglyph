extends Node3D
## A continuous three-metre ribbon, posed with two reusable mesh batches.
const Motes = preload("res://scripts/kyren_motes.gd")
const Neon = preload("res://scripts/neon.gd")
const LENGTH := 3.0
const SEGMENTS := 24
const FOLLOW_RESPONSE := 7.0
const RED := Color(.27,.008,.016)
var anchor: Node3D
var phase_source: Node
var motion_source: CharacterBody3D
var cloth: MultiMesh
var trim: MultiMesh
var points := PackedVector3Array()
var elapsed := 0.0
var _pending := 0.0
var _flow_yaw := 0.0
var _flow_pitch := 0.0
var _flow_ready := false

static func collar() -> MeshInstance3D:
	var wrap := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius=.075
	torus.outer_radius=.16
	torus.rings=20
	torus.ring_segments=6
	wrap.mesh=torus
	wrap.material_override=Neon.shared_material(RED)
	return wrap

func _batch(mesh: Mesh, count: int, color: Color) -> MultiMesh:
	var instance := MultiMeshInstance3D.new()
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.mesh = mesh
	data.instance_count = count
	instance.multimesh = data
	instance.material_override = Neon.shared_material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-3.4,-1,-3.4),Vector3(6.8,5.2,6.8))
	instance.visibility_range_end = 150
	add_child(instance)
	return data

func _ready() -> void:
	name = "WindScarf"
	var ribbon := BoxMesh.new()
	ribbon.size = Vector3.ONE
	cloth = _batch(ribbon,SEGMENTS,RED)
	var seam := CylinderMesh.new()
	seam.top_radius = 1
	seam.bottom_radius = 1
	seam.height = 1
	seam.radial_segments = 4
	trim = _batch(seam,SEGMENTS*2,Color(.78,.06,.055))
	points.resize(SEGMENTS+1)
	advance(0)

func _process(delta: float) -> void:
	visible = not (is_instance_valid(phase_source) and phase_source.active)
	if not visible:
		elapsed += delta
		return
	_pending += delta
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera) and camera.global_position.distance_squared_to(global_position)>22500:
		elapsed += _pending
		_pending = 0
		return
	if _pending<1.0/30: return
	advance(_pending)
	_pending = 0

func advance(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(anchor): return
	var start := to_local(anchor.global_position)
	var motion := Vector3.ZERO
	if is_instance_valid(motion_source):
		motion = motion_source.velocity
		var actions: Node = motion_source.get("world_actions")
		var vehicle: CharacterBody3D = actions.vehicle if is_instance_valid(actions) else null
		if is_instance_valid(vehicle): motion = vehicle.velocity
	var speed := motion.length()
	var influence := clampf((speed-.10)/(speed+.35),0,.98)
	var desired := Motes.wind(elapsed)*(1-influence)
	if speed>.10: desired -= motion/speed*influence
	if desired.length_squared()<.000001: desired = -motion.normalized()
	desired = desired.normalized()
	var yaw := atan2(desired.x,desired.z)
	var pitch := asin(clampf(desired.y,-1,1))
	if not _flow_ready:
		_flow_yaw = yaw
		_flow_pitch = pitch
		_flow_ready = true
	else:
		# Angle smoothing also handles full reversals without collapsing the
		# ribbon or snapping its direction through a zero-length vector.
		var blend := 1-exp(-FOLLOW_RESPONSE*delta)
		_flow_yaw = lerp_angle(_flow_yaw,yaw,blend)
		_flow_pitch = lerpf(_flow_pitch,pitch,blend)
	var world_direction := Vector3(sin(_flow_yaw)*cos(_flow_pitch),sin(_flow_pitch),cos(_flow_yaw)*cos(_flow_pitch))
	# Velocity/wind are world-space; the wearable copy inherits chest turns
	# and leans, so convert the flow into the ribbon's own frame only here.
	var inverse := global_basis.inverse()
	var direction := (inverse*world_direction).normalized()
	var side := (inverse*Vector3(-cos(_flow_yaw),0,sin(_flow_yaw))).normalized()
	var up := (inverse*Vector3.UP).normalized()
	points[0] = start
	for i in range(SEGMENTS):
		var t := float(i)/SEGMENTS
		var wave := sin(elapsed*3.4-t*TAU*1.25)*.27*t
		var lift := .12+sin(elapsed*2.1-t*TAU)*.28*t
		var tangent := (direction+side*wave+up*lift).normalized()
		points[i+1] = points[i]+tangent*(LENGTH/SEGMENTS)
		var twist := sin(elapsed*2-t*4)*.35
		var across := side.rotated(tangent,twist)
		var normal := tangent.cross(across).normalized()
		var width := lerpf(.27,.19,t)
		cloth.set_instance_transform(i,Transform3D(Basis(across*width,tangent*(LENGTH/SEGMENTS+.006),normal*.014),(points[i]+points[i+1])*.5))
		for edge in range(2):
			var offset := across*width*(.5 if edge==0 else -.5)
			var basis := Basis(Quaternion(Vector3.UP,tangent))*Basis.from_scale(Vector3(.007,LENGTH/SEGMENTS+.008,.007))
			trim.set_instance_transform(i*2+edge,Transform3D(basis,(points[i]+points[i+1])*.5+offset))
