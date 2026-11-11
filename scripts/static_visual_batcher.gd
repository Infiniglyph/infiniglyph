extends Node3D
## Build once. Original structural meshes remain as hidden inspection sources;
## every collider and light stays in place. No runtime visibility streaming.
var source_count := 0
var batch_count := 0
var groups: Dictionary = {}

func build(district: Node3D) -> void:
	name = "StaticVisualBatches"
	for block: Node3D in district.find_children("*","Node3D",true,false):
		if not block.has_meta("structural_block"): continue
		for child: Node in block.get_children():
			if child is MeshInstance3D and child.visible: collect(child)
	for group: Dictionary in groups.values():
		if group.sources.size()<2: continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.vertices
		if not group.normals.is_empty(): arrays[Mesh.ARRAY_NORMAL] = group.normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(group.primitive,arrays)
		mesh.surface_set_material(0,group.material)
		var instance := MeshInstance3D.new()
		instance.name = "StaticCell"
		instance.mesh = mesh
		instance.position = group.origin
		instance.cast_shadow = group.shadow
		add_child(instance)
		for source: MeshInstance3D in group.sources: source.hide()
		source_count += group.sources.size()
		batch_count += 1
	groups.clear()

func collect(source: MeshInstance3D) -> void:
	if source.mesh.get_surface_count()!=1: return
	if not source.mesh is BoxMesh and not source.mesh is ImmediateMesh: return
	var primitive: int = Mesh.PRIMITIVE_TRIANGLES if source.mesh is BoxMesh else Mesh.PRIMITIVE_LINES
	var material := source.get_active_material(0)
	if not material is StandardMaterial3D or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED: return
	var at := source.global_position
	var cell := Vector3i(floori(at.x/16),floori(at.y/16),floori(at.z/16))
	var key := str(cell)+"/"+str(material.get_instance_id())+"/"+str(primitive)+"/"+str(source.cast_shadow)
	if not groups.has(key):
		groups[key] = {"origin":Vector3(cell)*16,"vertices":PackedVector3Array(),"normals":PackedVector3Array(),
			"material":material,"primitive":primitive,"shadow":source.cast_shadow,"sources":[]}
	var group: Dictionary = groups[key]
	var arrays := source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var transform := source.global_transform
	var normal_basis := transform.basis.inverse().transposed()
	for i in range(vertices.size() if indices.is_empty() else indices.size()):
		var index := i if indices.is_empty() else indices[i]
		group.vertices.append(transform*vertices[index]-group.origin)
		if not normals.is_empty(): group.normals.append((normal_basis*normals[index]).normalized())
	group.sources.append(source)
