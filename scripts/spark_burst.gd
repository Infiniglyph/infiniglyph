extends MeshInstance3D
## Short analytic spark flights: pooled geometry, no particles with physics bodies.
const MAX_SPARKS := 28
const DRAG := 2.2
var trails := ImmediateMesh.new()
var ink: StandardMaterial3D
var velocities := PackedVector3Array()
var lifetimes := PackedFloat32Array()
var delays := PackedFloat32Array()
var widths := PackedFloat32Array()
var colors := PackedColorArray()
var positions := PackedVector3Array()
var count := 0
var duration := 0.65
var age := 0.0

func _ready() -> void:
	mesh = trails
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink = StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ink.vertex_color_use_as_albedo = true
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	velocities.resize(MAX_SPARKS)
	lifetimes.resize(MAX_SPARKS)
	delays.resize(MAX_SPARKS)
	widths.resize(MAX_SPARKS)
	colors.resize(MAX_SPARKS)
	positions.resize(MAX_SPARKS)
	hide()

func ignite(normal: Vector3, primary: Color, secondary: Color, strength: float, number: int, seed_value: int) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	count = clampi(number,1,MAX_SPARKS)
	age = 0
	duration = 0
	var outward := -normal.normalized() if normal.length_squared()>0.00001 else Vector3.BACK
	var tangent := outward.cross(Vector3.UP).normalized()
	if tangent.is_zero_approx(): tangent = Vector3.RIGHT
	var up := tangent.cross(outward).normalized()
	for i in range(count):
		# Uneven cone, independent speeds and launch delays prevent a radial stamp.
		var ray := (outward*random.randf_range(0.35,1.4)+tangent*random.randf_range(-1.2,1.2)+up*random.randf_range(-0.6,1.3)).normalized()
		velocities[i] = ray*random.randf_range(3.2,8.5)*strength+Vector3.UP*random.randf_range(0.8,2.8)
		lifetimes[i] = random.randf_range(0.26,0.58)
		delays[i] = random.randf_range(0,0.035)
		widths[i] = random.randf_range(0.012,0.023)
		colors[i] = primary if i%3 != 0 else secondary
		positions[i] = Vector3.ZERO
		duration = maxf(duration,lifetimes[i]+delays[i])
	show()
	redraw(0)

func flight(index: int, time: float) -> Vector3:
	# Time-based closed form stays identical across render/physics rates.
	return velocities[index]*((1-exp(-DRAG*time))/DRAG)+Vector3.DOWN*5.5*time*time

func redraw(time: float) -> void:
	age = time
	trails.clear_surfaces()
	if age>=duration:
		hide()
		return
	var camera := get_viewport().get_camera_3d()
	var view := to_local(camera.global_position) if camera != null else Vector3(0,1,5)
	var active := false
	for i in range(count):
		var elapsed := age-delays[i]
		if elapsed<0 or elapsed>=lifetimes[i]: continue
		if not active:
			trails.surface_begin(Mesh.PRIMITIVE_TRIANGLES,ink)
			active = true
		var head := flight(i,elapsed)
		var tail := flight(i,maxf(0,elapsed-0.028))
		positions[i] = head
		var direction := head-tail
		if direction.length_squared()<0.00001: direction = velocities[i].normalized()*0.015
		var side := direction.cross(view-head).normalized()*widths[i]
		var color := colors[i]
		color.a = (1-smoothstep(0.45,1,elapsed/lifetimes[i]))*minf(1,elapsed/0.012+0.35)
		# Short tapered streaks travel with the sparks; none remain tied to origin.
		trails.surface_set_color(Color(color,0))
		trails.surface_add_vertex(tail)
		trails.surface_set_color(color)
		trails.surface_add_vertex(head+side)
		trails.surface_add_vertex(head-side)
		# Bright compact head stays readable after the streak becomes very short.
		var tip := direction.normalized()*widths[i]*1.8
		for vertex in [head+tip,head-side,head-tip,head+tip,head-tip,head+side]:
			trails.surface_add_vertex(vertex)
	if active: trails.surface_end()
