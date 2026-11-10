extends Node3D
## Visible solid road gate. Existing Greefer completion is the only unlock flag.
const Neon = preload("res://scripts/neon.gd")
var encounter: Node
var opened := false
var opening := 0.0
var leaves: Array[Node3D] = []
var sign: Label3D

func _ready() -> void:
	name = "OutwardRoadGate"
	for side in [-1,1]:
		Neon.block(self,Vector3(side*11.4,3.5,0),Vector3(0.7,7,0.9))
		var leaf := Node3D.new()
		add_child(leaf)
		leaf.position.x = side*5.3
		Neon.block(leaf,Vector3(0,2.2,0),Vector3(10.5,4.4,0.35))
		var engraving := PackedVector3Array()
		for x in range(-4,5): engraving.append_array([Vector3(x,0.1,-0.19),Vector3(x,4.3,-0.19)])
		leaf.add_child(Neon.lines(engraving))
		leaves.append(leaf)
	Neon.block(self,Vector3(0,7.3,0),Vector3(23.5,0.7,0.9))
	sign = Label3D.new()
	sign.position = Vector3(0,7.3,0.48)
	sign.font_size = 40
	sign.pixel_size = 0.012
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign)
	if is_instance_valid(encounter): encounter.progression_changed.connect(refresh)
	refresh()
	opening = 1.0 if opened else 0.0
	place_leaves()

func refresh() -> void:
	opened = not is_instance_valid(encounter) or encounter.can_progress()
	sign.text = "OUTER CITY  /  OPEN" if opened else "OUTER CITY  /  CONFRONT GREEFER"

func place_leaves() -> void:
	for i in range(2):
		leaves[i].position.x = (-1 if i == 0 else 1)*lerpf(5.3,17.0,smoothstep(0,1,opening))

func _physics_process(delta: float) -> void:
	var desired := 1.0 if opened else 0.0
	if is_equal_approx(opening,desired): return
	opening = move_toward(opening,desired,delta*0.55)
	place_leaves()
