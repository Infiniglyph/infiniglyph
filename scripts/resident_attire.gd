extends Node3D
## Fitted catalog garments share two GPU surfaces, rather than a mesh pair per
## sleeve/greave. Native skinning also preserves the reconstruction shader.
const Database=preload("res://scripts/equipment_database.gd")
const Geometry=preload("res://scripts/equipment_geometry.gd")
const Pattern=preload("res://scripts/resident_garment_pattern.gd")
const SHADER=preload("res://scripts/resident_attire.gdshader")
const MOUNTS:={"body":[0],"head":[1],"hands":[2,3],"legs":[4,5,6,7],"arms":[8,9],"hips":[10]}
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
		for i in range(11):
			skeleton.add_bone("mount_"+str(i)); skeleton.set_bone_rest(i,Transform3D.IDENTITY); skin.add_bind(i,Transform3D.IDENTITY)
		figure=MeshInstance3D.new(); figure.name="BatchedClothing"; add_child(figure)
		figure.skeleton=figure.get_path_to(skeleton); figure.skin=skin
		figure.custom_aabb=AABB(Vector3(-1,-.2,-1.5),Vector3(2,2.8,3))
		figure.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material==null:
		material=ShaderMaterial.new(); material.shader=SHADER
	if not cache.has(next):
		var batches:=Pattern.empty_batches()
		for slot: StringName in [&"body",&"head",&"hands",&"legs"]:
			var item: Resource=store.equipped_item(StringName(slot))
			if item==null: continue
			var entry:=Database.get_item(item.item_type_id)
			if entry.is_empty(): continue
			var pattern:=Pattern.for_item(entry)
			for layer in range(2):
				for field: String in batches[layer]: batches[layer][field].append_array(pattern[layer][field])
		var mesh:=ArrayMesh.new()
		for layer in range(2):
			if batches[layer].points.is_empty(): continue
			var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=batches[layer].points; arrays[Mesh.ARRAY_COLOR]=batches[layer].colors
			arrays[Mesh.ARRAY_BONES]=batches[layer].bones; arrays[Mesh.ARRAY_WEIGHTS]=batches[layer].weights
			arrays[Mesh.ARRAY_TEX_UV]=batches[layer].energy
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
	if end.is_finite() and slot in ["hands","arms","legs"]:
		basis=basis*Basis.from_scale(Vector3(1,point.distance_to(end)/(.29 if slot=="hands" else .30 if slot=="arms" else .45),1))
	skeleton.set_bone_pose(int(mounts[index]),Transform3D(basis,point))

func torso(hip: Vector3,shoulder_line: Vector3,hem_pitch: float=0) -> void:
	if not is_instance_valid(skeleton): return
	var basis:=Basis(Quaternion(Vector3.UP,(shoulder_line-hip).normalized()))
	for bone: int in [0,1]: skeleton.set_bone_pose(bone,Transform3D(basis,hip))
	skeleton.set_bone_pose(10,Transform3D(Basis(Vector3.RIGHT,hem_pitch),hip))
