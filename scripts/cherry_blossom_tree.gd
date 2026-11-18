extends Node3D
## Static faceted branches and blossom clusters with one bounded petal pool.
const Chunk = preload("res://scripts/world_chunk.gd")
const Motes = preload("res://scripts/kyren_motes.gd")
var structure: Node3D
var blossoms: MultiMeshInstance3D
var petals: MultiMeshInstance3D

func branch(a: Vector3, b: Vector3, bottom: float, top: float) -> void:
	var points := PackedVector3Array()
	var length := a.distance_to(b)
	for ring in range(2):
		for i in range(8):
			var angle := TAU*i/8
			var radius := bottom if ring==0 else top
			points.append(Vector3(cos(angle)*radius,length*ring,sin(angle)*radius))
	var faces: Array = [[7,6,5,4,3,2,1,0],[8,9,10,11,12,13,14,15]]
	for i in range(8): faces.append([i,(i+1)%8,(i+1)%8+8,i+8])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	structure.volume(points,faces,Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),a),shape,"CherryBranch",Color(.51,.22,.12))

func flower_mesh() -> ArrayMesh:
	var source: PackedVector3Array = Motes.shape().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var vertices := PackedVector3Array()
	for i in range(5):
		var basis := Basis(Vector3.FORWARD,i*TAU/5)
		for vertex: Vector3 in source: vertices.append(basis*(vertex*.55+Vector3(0,.38,0)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _ready() -> void:
	name = "CherryBlossomTree"
	structure = Chunk.new()
	structure.name = "CherryWood"
	add_child(structure)
	branch(Vector3.ZERO,Vector3(-.15,2.7,-.25),.35,.25)
	branch(Vector3(-.15,2.7,-.25),Vector3(.25,5.5,-.45),.25,.10)
	var centers := [Vector3(0,6.6,0),Vector3(-2.7,6.0,.6),Vector3(2.6,6.3,-.3),Vector3(-.5,7.5,-1.7),Vector3(.1,5.7,2.4)]
	var sizes := [Vector3(3,1.15,2.7),Vector3(2.4,1,2.5),Vector3(2.4,1.1,2.3),Vector3(2.4,1,2.2),Vector3(2.7,1,2.4)]
	blossoms = MultiMeshInstance3D.new()
	blossoms.name = "BlossomCanopy"
	blossoms.multimesh = MultiMesh.new()
	blossoms.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	blossoms.multimesh.use_colors = true
	blossoms.multimesh.mesh = flower_mesh()
	blossoms.multimesh.instance_count = centers.size()*48
	blossoms.material_override = Motes.ink()
	blossoms.visibility_range_end = 170
	blossoms.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blossoms)
	for cluster in range(centers.size()):
		var center: Vector3 = centers[cluster]
		var size: Vector3 = sizes[cluster]
		branch(Vector3(.1,3.4,-.3),center-Vector3.UP*.4,.13,.045)
		var crown := PackedVector3Array([Vector3(0,1,0),Vector3(0,-.8,0)])
		for i in range(8): crown.append(Vector3(cos(i*TAU/8),0,sin(i*TAU/8)))
		var faces: Array = []
		for i in range(8):
			faces.append([0,2+i,2+(i+1)%8])
			faces.append([1,2+(i+1)%8,2+i])
		for i in range(crown.size()): crown[i] = crown[i]*size
		structure.convex(crown,faces,center,"CherryCrown",Color(.63,.14,.36))
		for i in range(48):
			var y := 1-2*(i+.5)/48
			var angle := i*2.399963+cluster
			var radial := sqrt(1-y*y)
			var normal := Vector3(radial*cos(angle),y,radial*sin(angle))
			var at := center+normal*size
			var orientation := Basis(Quaternion(Vector3.BACK,normal))*Basis(Vector3.BACK,angle)
			var scale_factor := .23+fmod(i*.037,.12)
			blossoms.multimesh.set_instance_transform(cluster*48+i,Transform3D(orientation.scaled(Vector3.ONE*scale_factor),at))
			blossoms.multimesh.set_instance_color(cluster*48+i,Color(1,.34+fmod(i*.13,.30),.60+fmod(i*.07,.27)))
	structure.commit()
	petals = Motes.new()
	add_child(petals)
