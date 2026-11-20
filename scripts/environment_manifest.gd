extends RefCounted
## Bounded GPU cell/height assembly; never touches actors, collision or topology.
const SHADER = preload("res://scripts/environment_manifest.gdshader")
var pieces: Array[Dictionary] = []
var labels: Array[Dictionary] = []
var effects: Array[ShaderMaterial] = []

func capture(root: Node3D, anchor: Vector3, cell_size: Vector3=Vector3(2.6,1.25,2.6), height_range: float=18.0) -> void:
	restore()
	var palette: Dictionary={}
	for mesh: GeometryInstance3D in root.find_children("*","GeometryInstance3D",true,false):
		if not mesh.is_visible_in_tree(): continue
		if mesh is Label3D:
			labels.append({"node":mesh,"visible":mesh.visible})
			mesh.hide()
			continue
		if not mesh is MeshInstance3D and not mesh is MultiMeshInstance3D: continue
		var original: Material=mesh.material_override
		var source: Material=original
		var shape: Mesh=mesh.mesh if mesh is MeshInstance3D else mesh.multimesh.mesh if mesh.multimesh!=null else null
		if source==null and shape!=null and shape.get_surface_count()>0: source=shape.surface_get_material(0)
		var tint: Color=source.albedo_color if source is StandardMaterial3D else Color(.04,.7,.85)
		var material: ShaderMaterial=palette.get(tint)
		if material==null:
			material=ShaderMaterial.new()
			material.shader=SHADER
			material.set_shader_parameter("anchor",anchor)
			material.set_shader_parameter("tint",tint)
			material.set_shader_parameter("cell_size",cell_size)
			material.set_shader_parameter("height_range",height_range)
			palette[tint]=material
			effects.append(material)
		pieces.append({"node":mesh,"original":original})
		mesh.material_override=material

func advance(progress: float) -> void:
	for material in effects: material.set_shader_parameter("progress",clampf(progress,0,1))

func restore() -> void:
	for piece in pieces:
		if is_instance_valid(piece.node): piece.node.material_override=piece.original
	for label in labels:
		if is_instance_valid(label.node): label.node.visible=label.visible
	pieces.clear()
	labels.clear()
	effects.clear()
