extends Node3D
const Neon = preload("res://scripts/neon.gd")
const Entrance = preload("res://scripts/resident_entrance.gd")
var roof: MeshInstance3D
var entrance: Node3D

func build(size: Vector3, front: Vector3 = Vector3.ZERO, id: StringName = &"") -> void:
	add_to_group("city_buildings")
	if front.is_zero_approx():
		roof = Neon.block(self,Vector3(0,size.y*0.5,0),size).get_node("Surface")
	else:
		entrance = Entrance.new()
		entrance.entrance_id = id
		add_child(entrance)
		entrance.position = front*size.x*0.5
		entrance.rotation.y = atan2(front.x,front.z)
		entrance.build(size)
		roof = entrance.roof
	# Floor bands and vertical facade seams describe the mass behind the light.
	var points := PackedVector3Array()
	var h := size * 0.5 + Vector3(0.006, 0, 0.006)
	for level in range(3, int(size.y), 3):
		var y := float(level)
		points.append_array([Vector3(-h.x,y,-h.z),Vector3(h.x,y,-h.z),Vector3(h.x,y,-h.z),Vector3(h.x,y,h.z),Vector3(h.x,y,h.z),Vector3(-h.x,y,h.z),Vector3(-h.x,y,h.z),Vector3(-h.x,y,-h.z)])
	for seam in range(-int(h.x)+3,int(h.x),3):
		for side in [-1,1]:
			var bottom := 0.0 if front.is_zero_approx() else minf(2.8,size.y-0.2)
			points.append_array([Vector3(seam,bottom,side*h.z),Vector3(seam,size.y,side*h.z),Vector3(side*h.x,bottom,seam),Vector3(side*h.x,size.y,seam)])
	if not points.is_empty(): add_child(Neon.lines(points,Neon.material(Color(0.02,0.65,0.78))))
