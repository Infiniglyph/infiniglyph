extends MultiMeshInstance3D
## Fixed instance pools for falling cherry petals and the hat's warm embers.
@export_enum("petal","ember") var kind := "petal"
var count := 96
var elapsed := 0.0
var phase_source: Node
var _pending := 0.0
static var petal_mesh: ArrayMesh
static var ember_mesh: ArrayMesh

static func wind(time: float) -> Vector3:
	var angle := time*.19+sin(time*.31)*1.7
	return Vector3(cos(angle),.12+sin(time*.73)*.12,sin(angle)).normalized()

static func ink() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func shape(ember: bool = false) -> ArrayMesh:
	if ember and ember_mesh!=null: return ember_mesh
	if not ember and petal_mesh!=null: return petal_mesh
	var outline := PackedVector3Array([Vector3(0,.65,0),Vector3(.35,.15,.05),Vector3(.22,-.35,0),Vector3(0,-.5,.04),Vector3(-.22,-.35,0),Vector3(-.35,.15,.05)])
	if ember: outline = PackedVector3Array([Vector3(.08,.9,0),Vector3(.32,-.1,0),Vector3(0,-.48,0),Vector3(-.28,-.1,0)])
	var vertices := PackedVector3Array()
	for i in range(outline.size()): vertices.append_array([Vector3.ZERO,outline[i],outline[(i+1)%outline.size()]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if ember: ember_mesh = mesh
	else: petal_mesh = mesh
	return mesh

func _ready() -> void:
	name = "FallingEmbers" if kind=="ember" else "FallingPetals"
	count = 36 if kind=="ember" else count
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = shape(kind=="ember")
	multimesh.instance_count = count
	material_override = ink()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = 150
	visibility_range_end_margin = 20
	# Fixed bounds include the full drifting trajectories, not only spawn points.
	custom_aabb = AABB(Vector3(-1.4,-1.2,-1.4),Vector3(2.8,1.8,2.8)) if kind=="ember" else AABB(Vector3(-7,-.2,-7),Vector3(14,9,14))
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
	var ember := kind=="ember"
	for i in range(count):
		var life := (1.4+fmod(i*.37,1.1)) if ember else (6.0+fmod(i*.53,2.5))
		var phase := elapsed/life+float(i)/count
		var t := fposmod(phase,1)
		var cycle := floorf(phase)
		var angle := i*2.399963+cycle*.71
		var radius := .58 if ember else sqrt(fposmod(i*.618034+cycle*.13,1))*4.3
		var at := Vector3(cos(angle)*radius,.102,sin(angle)*radius)
		var drift := wind(elapsed)*sin(t*PI)*(.20 if ember else 1.5)
		if ember:
			at.y -= t*.95
			at += Vector3(sin(elapsed*4+i)*.025,0,cos(elapsed*3+i)*.025)
		else:
			at.y = 6.2+fposmod(i*.71,1.4)-t*7.7
			at += Vector3(sin(elapsed*1.4+i)*.23,sin(elapsed*1.9+i)*.08,cos(elapsed*1.2+i)*.22)
		at += drift
		var size := (.032+fmod(i*.019,.024)) if ember else (.11+fmod(i*.037,.09))
		var rotation := Vector3(elapsed*(1.3 if ember else 1.9)+i,angle,elapsed*.8+i)
		var basis := Basis.from_euler(rotation)*Basis.from_scale(Vector3(size,size*(1.6 if ember else 1),size))
		multimesh.set_instance_transform(i,Transform3D(basis,at))
		var color := Color(1,.20+.55*(1-t),.025) if ember else Color(1,.38+fmod(i*.13,.30),.62+fmod(i*.07,.24))
		color.a = smoothstep(0,.08,t)*(1-smoothstep(.72,1,t))
		multimesh.set_instance_color(i,color)
