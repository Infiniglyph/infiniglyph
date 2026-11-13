extends RefCounted
## Shared fitted fabric construction for the Scribe robe and equipment.
const Lines = preload("res://scripts/robe_lines.gd")
var faces := PackedVector3Array()
var seams := PackedVector3Array()
var inlays := PackedVector3Array()

static func surface(label: String, vertices: PackedVector3Array, color: Color) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color.lightened(.025)
	material.emission_energy_multiplier = .55
	mesh.surface_set_material(0,material)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,trim: bool = false) -> void:
	faces.append_array([a,b,c,a,c,d])
	if trim: seams.append_array([a,b,b,c,c,d,d,a])

func line(points: Array, accent: bool = false) -> void:
	for i in range(1,points.size()):
		if accent: inlays.append_array([points[i-1],points[i]])
		else: seams.append_array([points[i-1],points[i]])

func point(row: Vector3, angle: float, center: Vector3 = Vector3.ZERO) -> Vector3:
	return center+Vector3(sin(angle)*row.x,row.y,cos(angle)*row.z)

func loft(rows: Array, gap: float = 0.0, center: Vector3 = Vector3.ZERO, ribs: int = 4) -> void:
	const COUNT := 16
	for j in range(rows.size()-1):
		for i in range(COUNT):
			var a := lerpf(gap,TAU-gap,i/float(COUNT))
			var b := lerpf(gap,TAU-gap,(i+1)/float(COUNT))
			quad(point(rows[j],a,center),point(rows[j],b,center),point(rows[j+1],b,center),point(rows[j+1],a,center))
	for row: Vector3 in [rows[0],rows[-1]]:
		for i in range(COUNT): seams.append_array([point(row,lerpf(gap,TAU-gap,i/float(COUNT)),center),point(row,lerpf(gap,TAU-gap,(i+1)/float(COUNT)),center)])
	for i in range(ribs+1):
		var path: Array = []
		for row: Vector3 in rows: path.append(point(row,lerpf(gap,TAU-gap,i/float(maxi(1,ribs))),center))
		line(path,i%2==0)

func finish(parent: Node3D, label: String, fabric: Color, trim: Color, accent: Color) -> void:
	if not faces.is_empty(): parent.add_child(surface(label,faces,fabric))
	if not seams.is_empty(): parent.add_child(Lines.segments(seams,trim,1.3))
	if not inlays.is_empty(): parent.add_child(Lines.segments(inlays,accent,1.5))
