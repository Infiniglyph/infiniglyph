extends Node3D
## Eight rigid mounts share two GPU surfaces, rather than one mesh pair per
## sleeve/greave. Native skinning also preserves the reconstruction shader.
const Database=preload("res://scripts/equipment_database.gd")
const Geometry=preload("res://scripts/equipment_geometry.gd")
const SHADER=preload("res://scripts/resident_attire.gdshader")
const MOUNTS:={"body":[0],"head":[1],"hands":[2,3],"legs":[4,5,6,7]}
static var cache: Dictionary={}
static var material: ShaderMaterial
var signature:=""
var skeleton: Skeleton3D
var figure: MeshInstance3D

func sync(store: Node) -> void:
	var next:=""
	for slot: StringName in [&"body",&"head",&"hands",&"legs"]:
		var item: Resource=store.equipped_item(slot)
		next+=(String(item.item_type_id) if item!=null else "-")+"/"
	if signature==next: return
	signature=next
	if not is_instance_valid(skeleton):
		skeleton=Skeleton3D.new(); skeleton.name="ClothingSkeleton"; add_child(skeleton)
		var skin:=Skin.new()
		for i in range(8):
			skeleton.add_bone("mount_"+str(i)); skeleton.set_bone_rest(i,Transform3D.IDENTITY); skin.add_bind(i,Transform3D.IDENTITY)
		figure=MeshInstance3D.new(); figure.name="BatchedClothing"; add_child(figure)
		figure.skeleton=figure.get_path_to(skeleton); figure.skin=skin
		figure.custom_aabb=AABB(Vector3(-1,-.2,-1.5),Vector3(2,2.8,3))
		figure.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material==null:
		material=ShaderMaterial.new(); material.shader=SHADER
	if not cache.has(next):
		var batches: Array[Dictionary]=[]
		for layer in range(2): batches.append({"points":PackedVector3Array(),"colors":PackedColorArray(),"bones":PackedInt32Array(),"weights":PackedFloat32Array()})
		for slot: String in MOUNTS:
			var item: Resource=store.equipped_item(StringName(slot))
			if item==null: continue
			var entry:=Database.get_item(item.item_type_id)
			if entry.is_empty(): continue
			var model:=Geometry.model(entry.geometry)
			for layer in range(2):
				var source: MeshInstance3D=model.get_child(layer)
				if source.mesh.get_surface_count()==0: continue
				var points: PackedVector3Array=source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var tint:=Color(entry.geometry.tint) if layer==1 else Color(entry.geometry.get("tailoring",{}).get("fabric","0b111b"))
				for bone: int in MOUNTS[slot]:
					for point: Vector3 in points:
						batches[layer].points.append(point); batches[layer].colors.append(tint)
						batches[layer].bones.append_array(PackedInt32Array([bone,0,0,0]))
						batches[layer].weights.append_array(PackedFloat32Array([1,0,0,0]))
			model.free()
		var mesh:=ArrayMesh.new()
		for layer in range(2):
			if batches[layer].points.is_empty(): continue
			var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=batches[layer].points; arrays[Mesh.ARRAY_COLOR]=batches[layer].colors
			arrays[Mesh.ARRAY_BONES]=batches[layer].bones; arrays[Mesh.ARRAY_WEIGHTS]=batches[layer].weights
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES if layer==0 else Mesh.PRIMITIVE_LINES,arrays)
			mesh.surface_set_material(mesh.get_surface_count()-1,material)
		if cache.size()>=64: cache.erase(cache.keys()[0])
		cache[next]=mesh
	figure.mesh=cache[next]

func at(slot: String,index: int,point: Vector3,end: Vector3=Vector3.INF) -> void:
	if not is_instance_valid(skeleton): return
	var mounts: Array=MOUNTS.get(slot,[])
	if index>=mounts.size(): return
	var basis:=Basis.IDENTITY if not end.is_finite() or point.distance_squared_to(end)<.000001 else Basis(Quaternion(Vector3.DOWN,(end-point).normalized()))
	skeleton.set_bone_pose(int(mounts[index]),Transform3D(basis,point))
