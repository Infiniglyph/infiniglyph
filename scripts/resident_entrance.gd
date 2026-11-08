extends Node3D
## A real recessed lobby. The screen conceals indoor streaming transitions.
const Neon = preload("res://scripts/neon.gd")
var entrance_id: StringName
var roof: MeshInstance3D
var lease: WeakRef
var exits := 0
var entries := 0

func build(size: Vector3) -> void:
	add_to_group("resident_entrances")
	var width := size.x
	var low := minf(2.8,size.y-0.2)
	var bay := 5.2
	var depth := 4.2
	var cap := Neon.block(self,Vector3(0,(size.y+low)*0.5,-width*0.5),Vector3(width,size.y-low,width))
	roof = cap.get_node("Surface")
	for side: int in [-1,1]:
		Neon.block(self,Vector3(side*(width+bay)*0.25,low*0.5,-width*0.5),Vector3((width-bay)*0.5,low,width))
	Neon.block(self,Vector3(0,low*0.5,-(width+depth)*0.5),Vector3(bay,low,width-depth))
	Neon.block(self,Vector3(0,0.06,-depth*0.5),Vector3(bay,0.12,depth))
	for side: int in [-1,1]:
		Neon.block(self,Vector3(side*1.9,1.175,-0.09),Vector3(1.4,2.35,0.18))
	Neon.block(self,Vector3(0,(low+2.35)*0.5,-0.09),Vector3(bay,low-2.35,0.18))
	Neon.block(self,Vector3(0,1.37,-1.9),Vector3(1.6,2.5,0.16))
	batch_surfaces()

func batch_surfaces() -> void:
	# Keep each box/collider available for audits, but draw a lobby in two batches.
	var faces := PackedVector3Array()
	var edges := PackedVector3Array()
	var normals := PackedVector3Array()
	for visual: MeshInstance3D in find_children("*","MeshInstance3D",true,false):
		var arrays: Array = visual.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if visual.mesh is BoxMesh:
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for index: int in indices:
				faces.append(to_local(visual.to_global(vertices[index])))
				normals.append(source_normals[index])
		else:
			for vertex: Vector3 in vertices: edges.append(to_local(visual.to_global(vertex)))
		visual.hide()
	for spec: Array in [[faces,Mesh.PRIMITIVE_TRIANGLES,Neon.dark],[edges,Mesh.PRIMITIVE_LINES,Neon.edge]]:
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(spec[1],spec[2])
		for i in range(spec[0].size()):
			if spec[1]==Mesh.PRIMITIVE_TRIANGLES: mesh.surface_set_normal(normals[i])
			mesh.surface_add_vertex(spec[0][i])
		mesh.surface_end()
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)

func outside() -> Vector3:
	return to_global(Vector3(0,0.045,1.6))

func concealed() -> Vector3:
	return to_global(Vector3(0,0.165,-3.15))

func passage(inward: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point: Vector3 in [Vector3(0,0.045,1.6),Vector3(0,0.165,-0.65),Vector3(1.6,0.165,-0.9),Vector3(1.6,0.165,-3.15),Vector3(0,0.165,-3.15)]:
		result.append(to_global(point))
	if not inward: result.reverse()
	return result

func available(resident: Node = null) -> bool:
	return lease==null or not is_instance_valid(lease.get_ref()) or lease.get_ref()==resident

func claim(resident: Node) -> bool:
	if not available(resident): return false
	lease = weakref(resident)
	return true

func release(resident: Node) -> void:
	if lease!=null and lease.get_ref()==resident: lease = null
