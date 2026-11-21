extends RefCounted
## Bake the actual catalog garment once, retaining its seams and silhouette.
## Only the resulting vertex arrays survive; residents run no garment nodes or
## cloth solvers. Limb-local coordinates are shared by the native pose mounts.
const Garment=preload("res://scripts/equipment_garment.gd")
const Geometry=preload("res://scripts/equipment_geometry.gd")
const LIMIT:=64
static var cache: Dictionary={}
static var builds:=0

class PatternRig:
	extends Node3D
	var pelvis:=Node3D.new()
	var chest:=Node3D.new()
	var joints: Dictionary={}
	var foot_meshes: Dictionary={}
	var mounts: Dictionary={}
	func _init(head: bool):
		add_child(pelvis); add_child(chest)
		mounts[pelvis]=10; mounts[chest]=1 if head else 0
		for side: String in ["Left","Right"]:
			var index:=0 if side=="Left" else 1
			for limb: String in ["Arm","Leg"]:
				var joint:=Node3D.new(); var hinge:=Node3D.new(); hinge.name="Hinge"
				add_child(joint); joint.add_child(hinge); joints[side+limb]=joint
				mounts[joint]=8+index if limb=="Arm" else 4+index*2
				mounts[hinge]=2+index if limb=="Arm" else 5+index*2
				if limb=="Leg":
					var foot:=MeshInstance3D.new(); hinge.add_child(foot); foot_meshes[side+limb]=foot

static func empty_batches() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for i in range(2): result.append({"points":PackedVector3Array(),"colors":PackedColorArray(),"bones":PackedInt32Array(),"weights":PackedFloat32Array(),"energy":PackedVector2Array()})
	return result

static func for_item(entry: Dictionary) -> Array[Dictionary]:
	var key:=String(entry.id)
	if cache.has(key): return cache[key]
	var batches:=empty_batches()
	var figure:=PatternRig.new(entry.family=="head")
	if entry.geometry.has("tailoring"):
		var garment:=Garment.new(); figure.add_child(garment); garment.configure(figure,entry)
		for tail: Node3D in garment.tails:
			var cape: bool=tail.get_meta("cape")
			tail.position=tail.get_meta("seam")+Vector3(0,.43 if cape else 0,0)
			figure.mounts[tail]=0 if cape else 10
		# These mounts have a meaningful local seam transform, unlike joints.
		_collect(figure,figure.mounts,batches,0,Transform3D.IDENTITY)
	else:
		# Older simple equipment retains the same anchors as EquipmentCosmetics.
		var mounts: Array={"body":[0],"head":[1],"hands":[2,3],"legs":[4,5,6,7]}.get(String(entry.family),[])
		for mount: int in mounts:
			var model:=Geometry.model(entry.geometry)
			model.position.y=.65 if entry.family=="head" else .08 if entry.family=="body" else -.02 if entry.family=="hands" else 0
			_collect(model,{},batches,mount,Transform3D.IDENTITY)
			model.free()
	figure.free()
	if cache.size()>=LIMIT: cache.erase(cache.keys()[0])
	cache[key]=batches; builds+=1
	return batches

static func _collect(node: Node3D, mounts: Dictionary, batches: Array[Dictionary], bone: int, parent_transform: Transform3D) -> void:
	var transform_to_mount:=parent_transform*node.transform
	if mounts.has(node):
		bone=int(mounts[node])
		if not node.has_meta("seam"): transform_to_mount=Transform3D.IDENTITY
	if node is MeshInstance3D and node.mesh!=null:
		for surface in range(node.mesh.get_surface_count()):
			var primitive: int=node.mesh.surface_get_primitive_type(surface) if node.mesh is ArrayMesh else Mesh.PRIMITIVE_LINES
			if primitive not in [Mesh.PRIMITIVE_TRIANGLES,Mesh.PRIMITIVE_LINES]: continue
			var layer:=0 if primitive==Mesh.PRIMITIVE_TRIANGLES else 1
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
			var ink: Material=node.get_active_material(surface)
			var tint: Color=ink.albedo_color if ink is StandardMaterial3D else Color.WHITE
			var energy: float=ink.emission_energy_multiplier if ink is StandardMaterial3D and ink.emission_enabled else 0
			for i in range(indices.size() if not indices.is_empty() else points.size()):
				var vertex: int=indices[i] if not indices.is_empty() else i
				batches[layer].points.append(transform_to_mount*points[vertex])
				batches[layer].colors.append(tint*colors[vertex] if not colors.is_empty() and ink is StandardMaterial3D and ink.vertex_color_use_as_albedo else tint)
				batches[layer].energy.append(Vector2(energy,0))
				batches[layer].bones.append_array(PackedInt32Array([bone,0,0,0])); batches[layer].weights.append_array(PackedFloat32Array([1,0,0,0]))
	for child: Node in node.get_children():
		if child is Node3D: _collect(child,mounts,batches,bone,transform_to_mount)
