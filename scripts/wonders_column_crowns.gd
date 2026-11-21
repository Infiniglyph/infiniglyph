extends MultiMeshInstance3D
## Ten large, hollow polyhedral crowns rotate on the GPU in one shared batch.
func _ready() -> void:
	name="RotatingColumnCrowns"
	var points:=PackedVector3Array(); var colors:=PackedColorArray()
	var corners: Array[Vector3]=[]
	for x: float in [-.72,.72]:
		for y: float in [-.72,.72]:
			for z: float in [-.72,.72]: corners.append(Vector3(x,y,z))
	for i in range(8):
		for j in range(i+1,8):
			var difference: Vector3=corners[i]-corners[j]
			if Vector3(absf(difference.x),absf(difference.y),absf(difference.z)).length()<1.5:
				points.append_array([corners[i],corners[j]]); colors.append_array([Color("56ffff"),Color("56ffff")])
	for i in range(4):
		var a:=Vector3(cos(i*TAU/4),0,sin(i*TAU/4))*.85
		var b:=Vector3(cos((i+1)*TAU/4),0,sin((i+1)*TAU/4))*.85
		for tip: Vector3 in [Vector3.UP*1.08,Vector3.DOWN*1.08]:
			points.append_array([a,tip,a,b]); colors.append_array([Color("f692ff"),Color("f692ff"),Color("ffd278"),Color("ffd278")])
	for i in range(64):
		for j in [i,i+1]:
			var a: float=j*TAU/64
			points.append(Vector3(cos(a),sin(a)*.25,sin(a)) * 1.18); colors.append(Color("a76cff"))
	# Crossed narrow ribbons retain a physical width at column height on
	# Compatibility renderers, including hardware without bloom.
	var faces:=PackedVector3Array(); var ink:=PackedColorArray()
	for i in range(0,points.size(),2):
		var a:=points[i]; var b:=points[i+1]; var axis:=(b-a).normalized()
		var side:=axis.cross(Vector3.UP).normalized()
		if side.is_zero_approx(): side=Vector3.RIGHT
		for offset: Vector3 in [side*.009,axis.cross(side).normalized()*.009]:
			for vertex: Vector3 in [a-offset,b-offset,b+offset,a-offset,b+offset,a+offset]: faces.append(vertex); ink.append(colors[i])
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=faces; arrays[Mesh.ARRAY_COLOR]=ink
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=ShaderMaterial.new(); material.shader=preload("res://scripts/wonders_column_crowns.gdshader"); mesh.surface_set_material(0,material)
	multimesh=MultiMesh.new(); multimesh.transform_format=MultiMesh.TRANSFORM_3D; multimesh.use_custom_data=true; multimesh.use_colors=true; multimesh.mesh=mesh; multimesh.instance_count=10
	var index:=0
	for side in [-1,1]:
		for z: float in [-48,-24,0,24,48]:
			multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*3.5),Vector3(side*37,39,z)))
			multimesh.set_instance_color(index,Color.WHITE)
			multimesh.set_instance_custom_data(index,Color(index*.57,0,0,1)); index+=1
	custom_aabb=AABB(Vector3(-43,34,-54),Vector3(86,10,108))
	multimesh.custom_aabb=custom_aabb
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
