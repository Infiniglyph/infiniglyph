extends Node3D
## Immutable spatial batches. Visuals and collision have the same local origin;
## engine frustum culling never unloads a fast Sky Jump's landing surface.
const Neon = preload("res://scripts/neon.gd")
static var boxes: Dictionary = {}
static var dark: StandardMaterial3D
static var wire: StandardMaterial3D
var body := StaticBody3D.new()
var triangles := PackedVector3Array()
var normals := PackedVector3Array()
var edges := PackedVector3Array()
var colors := PackedColorArray()
var volumes: Array[Dictionary] = []
var terrain_shape: CollisionShape3D
var mesh_instance: MeshInstance3D

func _init() -> void:
	body.name = "SolidWorld"
	add_child(body)
	if dark == null:
		Neon.prepare()
		dark = Neon.dark.duplicate()
		dark.cull_mode = BaseMaterial3D.CULL_DISABLED
		wire = StandardMaterial3D.new()
		wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wire.vertex_color_use_as_albedo = true

func line(a: Vector3, b: Vector3, color: Color) -> void:
	edges.append_array([a-position,b-position])
	colors.append_array([color,color])

func triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	triangles.append_array([a-position,b-position,c-position])
	normals.append_array([normal,normal,normal])

func volume(vertices: PackedVector3Array, faces: Array, transform: Transform3D, shape: Shape3D, kind: String, color: Color) -> void:
	var seen: Dictionary = {}
	for face: Array in faces:
		var normal: Vector3 = transform.basis*((vertices[face[1]]-vertices[face[0]]).cross(vertices[face[2]]-vertices[face[0]])).normalized()
		for i in range(1,face.size()-1):
			triangle(transform*vertices[face[0]]-normal*0.002,transform*vertices[face[i]]-normal*0.002,transform*vertices[face[i+1]]-normal*0.002,normal)
		for i in range(face.size()):
			var a: int = face[i]
			var b: int = face[(i+1)%face.size()]
			var pair := Vector2i(mini(a,b),maxi(a,b))
			if not seen.has(pair):
				line(transform*vertices[a],transform*vertices[b],color)
				seen[pair] = true
	var collider := CollisionShape3D.new()
	collider.name = kind
	collider.shape = shape
	body.add_child(collider)
	collider.transform = Transform3D(transform.basis,transform.origin-position)
	volumes.append({"kind":kind,"collider":collider,"transform":transform,"vertices":vertices,"faces":faces})

func box(at: Vector3, size: Vector3, kind: String, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var vertices := PackedVector3Array()
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]: vertices.append(Vector3(x,y,z)*size*0.5)
	if not boxes.has(size):
		var shape := BoxShape3D.new()
		shape.size = size
		boxes[size] = shape
	volume(vertices,[[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]],Transform3D(basis,at),boxes[size],kind,color)

func convex(vertices: PackedVector3Array, faces: Array, at: Vector3, kind: String, color: Color) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	volume(vertices,faces,Transform3D(Basis.IDENTITY,at),shape,kind,color)

func terrain(faces: PackedVector3Array) -> void:
	if faces.is_empty(): return
	if position == Vector3(-128,0,-128):
		# Four narrow physical rim bodies leave the original district completely
		# out of the expansion broad phase. A single doughnut-shaped mesh would
		# overlap every hub NPC's queries despite its empty center.
		var strips := [PackedVector3Array(),PackedVector3Array(),PackedVector3Array(),PackedVector3Array()]
		for i in range(0,faces.size(),3):
			var center: Vector3 = (faces[i]+faces[i+1]+faces[i+2])/3+position
			var index := 0 if center.x< -112 else (1 if center.x>112 else (2 if center.z< -112 else 3))
			strips[index].append_array([faces[i],faces[i+1],faces[i+2]])
		for i in range(strips.size()):
			var rim := StaticBody3D.new()
			rim.name = "HubTerrainRim_%d" % i
			add_child(rim)
			terrain_on(strips[i],rim)
		return
	terrain_on(faces,body)

func terrain_on(faces: PackedVector3Array, owner_body: StaticBody3D) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	terrain_shape = CollisionShape3D.new()
	terrain_shape.name = "Terrain"
	terrain_shape.shape = shape
	owner_body.add_child(terrain_shape)

func commit() -> void:
	var mesh := ArrayMesh.new()
	if not triangles.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = triangles
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,dark)
	if not edges.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = edges
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
		mesh.surface_set_material(mesh.get_surface_count()-1,wire)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "WorldBatch"
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	# Source geometry is not rebuilt or held as a second render-memory cache.
	triangles.clear()
	normals.clear()
	edges.clear()
	colors.clear()
