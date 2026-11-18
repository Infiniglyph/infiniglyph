extends Node3D
## Shared crimson straw hat and fixed ember pool for Kyren and player copies.
const Lines = preload("res://scripts/robe_lines.gd")
const Motes = preload("res://scripts/kyren_motes.gd")
var embers: MultiMeshInstance3D

func _ready() -> void:
	name="CrimsonStrawHat"
	position.y=-.09
	var cone := CylinderMesh.new()
	cone.top_radius = .015
	cone.bottom_radius = .58
	cone.height = .24
	cone.radial_segments = 48
	var fabric := Lines.make_material(Color(.11,.009,.012),0)
	fabric.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material = fabric
	var surface := MeshInstance3D.new()
	surface.mesh = cone
	surface.position.y = .22
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	var weave := PackedVector3Array()
	for ring in range(1,9):
		var radius := .58*ring/8.0
		var y := .344-radius/.58*.24
		for j in range(48):
			for k in [j,j+1]: weave.append(Vector3(cos(k*TAU/48)*radius,y,sin(k*TAU/48)*radius))
	for j in range(48):
		var angle := j*TAU/48
		weave.append_array([Vector3(cos(angle)*.02,.344,sin(angle)*.02),Vector3(cos(angle)*.58,.104,sin(angle)*.58)])
	add_child(Lines.segments(weave,Color(.67,.075,.045),.6))
	embers = Motes.new()
	embers.kind = "ember"
	add_child(embers)
