extends Node3D
## Shared sentinel clothing and player-size loot copies on the existing rig.
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Neon = preload("res://scripts/neon.gd")
const Surface = preload("res://scripts/garment_surface.gd")
var figure: Node3D
var external: Array[Node3D]=[]
var covered_feet: Array[MeshInstance3D]=[]

func panel(parent: Node3D, outline: Array, at: Vector3, depth: float=.025) -> Node3D:
	var mesh:=Geometry.model({"family":"sword","outline":outline,"depth":depth,"tint":"ffd170"})
	parent.add_child(mesh)
	mesh.position=at
	return mesh

func anchor(parent: Node3D, label: String) -> Node3D:
	var result:=Node3D.new()
	result.name=label
	parent.add_child(result)
	external.append(result)
	return result

func configure(visual: Node3D, kind: String) -> void:
	figure=visual
	figure.add_child(self)
	name=kind.to_pascal_case()
	match kind:
		"falcon_mantle": mantle()
		"falcon_tassets": tassets()
		"falcon_seal": seal()
	for root: Node3D in external: batch_panels(root)

func batch_panels(root: Node3D) -> void:
	var faces:=PackedVector3Array()
	var edges:=PackedVector3Array()
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if not mesh.mesh is ArrayMesh: continue # Keep cyan ImmediateMesh inlays.
		var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var transform_to_root:=root.global_transform.affine_inverse()*mesh.global_transform
		for point: Vector3 in vertices:
			if mesh.mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_TRIANGLES: faces.append(transform_to_root*point)
			else: edges.append(transform_to_root*point)
		mesh.hide()
		mesh.queue_free()
	if not faces.is_empty(): root.add_child(Surface.surface("BatchedFeatherSurfaces",faces,Color("030507")))
	if not edges.is_empty(): root.add_child(Neon.lines(edges,Neon.shared_material(Color("ffd170"))))

func mantle() -> void:
	var root:=anchor(figure.chest,"LayeredFalconMantle")
	var collar:=PackedVector3Array()
	for i in range(24):
		var a:=i*TAU/24
		var b:=(i+1)*TAU/24
		collar.append_array([Vector3(cos(a)*.28,.48,sin(a)*.18),Vector3(cos(b)*.28,.48,sin(b)*.18),Vector3(cos(a)*.18,.55,sin(a)*.12),Vector3(cos(a)*.28,.48,sin(a)*.18)])
	root.add_child(Neon.lines(collar,Neon.shared_material(Color("6cffff"))))
	for side: int in [-1,1]:
		for i in range(5):
			var feather:=panel(root,[[-.045,0],[.05,0],[.07,-.20],[0,-.37],[-.055,-.23]],Vector3(side*(.19+i*.048),.46-i*.018,0))
			feather.rotation.z=side*(.24+i*.16)
	for i in range(11):
		var x: float=(i-5)*.051
		panel(root,[[-.04,0],[.045,0],[.06,-.55],[0,-.82-absf(x)*.5],[-.05,-.62]],Vector3(x,.42,-.18-absf(x)*.12))
	var notation:=PackedVector3Array()
	for i in range(5):
		var y:=.32-i*.14
		notation.append_array([Vector3(-.04,y,-.214),Vector3(.04,y,-.214),Vector3(0,y+.04,-.214),Vector3(0,y-.07,-.214)])
	root.add_child(Neon.lines(notation,Neon.shared_material(Color("6cffff"))))

func tassets() -> void:
	var root:=anchor(figure.pelvis,"SkyguardTassets")
	for side: int in [-1,1]:
		for i in range(3):
			var cloth:=panel(root,[[-.075,.04],[.075,.04],[.095,-.37],[.025,-.61],[-.085,-.45]],Vector3(side*(.075+i*.071),-.02,.16-i*.038))
			cloth.rotation.z=side*(i*.15)
	var script:=PackedVector3Array()
	for i in range(4):
		var y: float=-.10-i*.10
		script.append_array([Vector3(-.025,y,.192),Vector3(.025,y,.192),Vector3(0,y+.035,.192),Vector3(0,y-.035,.192)])
	root.add_child(Neon.lines(script,Neon.shared_material(Color("6cffff"))))
	for side: String in ["Left","Right"]:
		var boot:=anchor(figure.joints[side+"Leg"].get_node("Hinge"),side+"SkyguardGreave")
		panel(boot,[[-.07,-.10],[.07,-.10],[.09,-.43],[.06,-.49],[-.07,-.49]],Vector3(0,0,.02),.16)
		panel(boot,[[-.075,0],[.075,0],[.09,-.085],[-.09,-.085]],Vector3(0,-.42,.07),.29)
		var foot: MeshInstance3D=figure.foot_meshes.get(side+"Leg")
		if is_instance_valid(foot):
			covered_feet.append(foot)
			foot.hide()

func seal() -> void:
	var root:=anchor(figure.joints.RightArm.get_node("Hinge"),"EyeOfHorusSeal")
	root.position=Vector3(0,-.22,.06)
	var lines:=PackedVector3Array([Vector3(-.10,0,0),Vector3(0,.045,0),Vector3(0,.045,0),Vector3(.10,0,0),Vector3(.10,0,0),Vector3(0,-.04,0),Vector3(0,-.04,0),Vector3(-.10,0,0),Vector3(.02,-.04,0),Vector3(.055,-.12,0),Vector3(.055,-.12,0),Vector3(-.015,-.13,0)])
	for i in range(12):
		lines.append_array([Vector3(cos(i*TAU/12)*.023,sin(i*TAU/12)*.023,0),Vector3(cos((i+1)*TAU/12)*.023,sin((i+1)*TAU/12)*.023,0)])
	root.add_child(Neon.lines(lines,Neon.shared_material(Color("6cffff"))))

func _exit_tree() -> void:
	for foot in covered_feet:
		if is_instance_valid(foot): foot.show()
	for node in external:
		if is_instance_valid(node): node.queue_free()
