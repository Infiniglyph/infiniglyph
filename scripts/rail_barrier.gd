extends RefCounted
## One continuous, bevel-ended collision panel behind an open visual railing.
## No post/midrail gaps for a moving capsule to enter or step up into.
static func geometry(a: Vector3, b: Vector3, height: float, width: float) -> Dictionary:
	var along:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
	var side:=Vector3(-along.z,0,along.x)*width*.5
	var cap:=along*width*.25
	var outline: Array[Vector3]=[a-cap-side*.5,a-side,b-side,b+cap-side*.5,
		b+cap+side*.5,b+side,a+side,a-cap+side*.5]
	var vertices:=PackedVector3Array()
	for lift: float in [-.03,height]:
		for point in outline: vertices.append(point+Vector3.UP*lift)
	var faces: Array=[[7,6,5,4,3,2,1,0],[8,9,10,11,12,13,14,15]]
	for i in range(8): faces.append([i,(i+1)%8,(i+1)%8+8,i+8])
	var shape:=ConvexPolygonShape3D.new()
	shape.points=vertices
	return {"vertices":vertices,"faces":faces,"shape":shape}
