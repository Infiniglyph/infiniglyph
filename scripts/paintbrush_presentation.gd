extends RefCounted
## An original code-native brush, with its nib .45 m above the physical grip.
const Lines = preload("res://scripts/robe_lines.gd")
const Moves = preload("res://scripts/paintbrush_moves.gd")

static func model(tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Paintbrush"
	var shaft := MeshInstance3D.new()
	var solid := CylinderMesh.new()
	solid.top_radius = .023
	solid.bottom_radius = .015
	solid.height = .48
	solid.radial_segments = 8
	solid.material = Lines.make_material(Color("09131d"),0)
	shaft.mesh = solid
	shaft.position.y = -.02
	root.add_child(shaft)
	var edges := PackedVector3Array()
	for i in range(8):
		var angle := i*TAU/8
		edges.append_array([Vector3(cos(angle)*.023,.22,sin(angle)*.023),Vector3(cos(angle)*.015,-.26,sin(angle)*.015)])
	root.add_child(Lines.segments(edges,tint,1.3))
	for y: float in [-.18,.10,.22]:
		var band := Lines.circle(.032,12,tint)
		band.rotation.x = PI*.5
		band.position.y = y
		root.add_child(band)
	# Bristles flare from the ferrule into a curved, tapered calligraphy tip.
	var bristles := PackedVector3Array()
	var surface := ImmediateMesh.new()
	surface.surface_begin(Mesh.PRIMITIVE_TRIANGLES,Lines.make_material(tint*.32,.6))
	for i in range(10):
		var angle := i*TAU/10
		var next := (i+1)*TAU/10
		var a := Vector3(cos(angle)*.031,.22,sin(angle)*.031)
		var b := Vector3(cos(angle)*.069,.32,sin(angle)*.048)
		var c := Vector3(cos(next)*.069,.32,sin(next)*.048)
		bristles.append_array([a,b,b,Moves.TIP])
		for point: Vector3 in [a,b,c,b,Moves.TIP,c]: surface.surface_add_vertex(point)
	surface.surface_end()
	var filling := MeshInstance3D.new()
	filling.mesh = surface
	root.add_child(filling)
	root.add_child(Lines.segments(bristles,tint,1.5))
	var tip := Node3D.new()
	tip.name = "BrushTip"
	tip.position = Moves.TIP
	root.add_child(tip)
	return root
