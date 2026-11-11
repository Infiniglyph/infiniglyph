extends RefCounted


static func make_material(color: Color, energy: float = 2.4) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


static func segments(points: PackedVector3Array, color: Color, energy: float = 2.4) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, make_material(color, energy))
	for point in points:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func polyline(points: PackedVector3Array, color: Color, closed: bool = false) -> MeshInstance3D:
	var line_points := PackedVector3Array()
	if points.size() < 2:
		return segments(line_points, color)
	for index in range(points.size() - 1):
		line_points.append(points[index])
		line_points.append(points[index + 1])
	if closed:
		line_points.append(points[points.size() - 1])
		line_points.append(points[0])
	return segments(line_points, color)


static func box(size: Vector3, color: Color) -> MeshInstance3D:
	var half := size * 0.5
	var corners := [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z),
		Vector3(-half.x, half.y, half.z),
	]
	var edge_indices := [
		0, 1, 1, 2, 2, 3, 3, 0,
		4, 5, 5, 6, 6, 7, 7, 4,
		0, 4, 1, 5, 2, 6, 3, 7,
	]
	var points := PackedVector3Array()
	for index in edge_indices:
		points.append(corners[index])
	return segments(points, color)


static func grid(width: float, depth: float, spacing: float, color: Color) -> MeshInstance3D:
	var points := PackedVector3Array()
	var half_width := width * 0.5
	var half_depth := depth * 0.5
	var x := -half_width
	while x <= half_width + 0.001:
		points.append(Vector3(x, 0.01, -half_depth))
		points.append(Vector3(x, 0.01, half_depth))
		x += spacing
	var z := -half_depth
	while z <= half_depth + 0.001:
		points.append(Vector3(-half_width, 0.01, z))
		points.append(Vector3(half_width, 0.01, z))
		z += spacing
	return segments(points, color, 1.2)


static func circle(radius: float, segments_count: int, color: Color, center: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var points := PackedVector3Array()
	for index in range(segments_count):
		var first_angle := TAU * float(index) / float(segments_count)
		var second_angle := TAU * float(index + 1) / float(segments_count)
		points.append(center + Vector3(cos(first_angle) * radius, sin(first_angle) * radius, 0.0))
		points.append(center + Vector3(cos(second_angle) * radius, sin(second_angle) * radius, 0.0))
	return segments(points, color)
