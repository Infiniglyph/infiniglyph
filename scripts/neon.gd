extends RefCounted
## Opaque physical surfaces and a separate, batched edge presentation.
const CYAN := Color(0.04, 0.78, 0.94)
## Orange identifies fixtures that actually emit light into the world.
const ORANGE := Color(1.0, 0.28, 0.035)
static var dark: StandardMaterial3D
static var edge: StandardMaterial3D
static var body: StandardMaterial3D
static var boxes: Dictionary = {}
static var inks: Dictionary = {}

## Only for immutable world/vehicle inks. Effects keep material() so fading
## one impact or phase trace can never mutate another object's material.
static func shared_material(color: Color) -> StandardMaterial3D:
	if not inks.has(color): inks[color] = material(color)
	return inks[color]

static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	return m

static func prepare() -> void:
	if dark != null: return
	# Keep emissive edges, but let opaque surfaces receive the street lighting.
	dark = StandardMaterial3D.new()
	dark.albedo_color = Color(0.055, 0.065, 0.08)
	dark.roughness = 1.0
	dark.emission_enabled = true
	dark.emission = Color(0.003, 0.007, 0.011)
	edge = material(CYAN * 0.65)
	body = material(Color(0.15, 1.0, 1.0))

static func lines(points: PackedVector3Array, mat: Material = null) -> MeshInstance3D:
	prepare()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, edge if mat == null else mat)
	for p in points: mesh.surface_add_vertex(p)
	mesh.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual

static func block(parent: Node3D, center: Vector3, size: Vector3, edge_material: Material = null, surface_material: Material = null) -> Node3D:
	prepare()
	var root := Node3D.new()
	root.name = "SolidBlock"
	root.set_meta("structural_block",true)
	parent.add_child(root)
	root.position = center
	var solid := MeshInstance3D.new()
	solid.name = "Surface"
	if not boxes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = dark
		boxes[size] = mesh
	solid.mesh = boxes[size]
	solid.material_override = surface_material
	root.add_child(solid)
	var h := size * 0.5 + Vector3.ONE * 0.002
	var corners: Array[Vector3] = []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]: corners.append(Vector3(x, y, z) * h)
	var points := PackedVector3Array()
	for i in range(8):
		for bit in [1, 2, 4]:
			var j: int = i ^ bit
			if i < j: points.append_array([corners[i], corners[j]])
	root.add_child(lines(points, edge_material))
	# Every structural box is solid, including roofs and distant skyline towers.
	# Decorative lines and short-lived effects use lines(), never hollow blocks.
	var physics := StaticBody3D.new()
	physics.name = "Collision"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	physics.add_child(shape)
	root.add_child(physics)
	return root
