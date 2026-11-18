extends RefCounted
## Normalized pen paths. An X lifts between diagonals; closed polygons do not.
const SQUARE := [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
const TRIANGLE := [Vector2(0,1),Vector2(-.866,-.5),Vector2(.866,-.5)]

static func shape(action: StringName) -> StringName:
	return {&"special_x":&"square",&"special_y":&"triangle",&"special_rt_x":&"cross",&"special_rt_y":&"circle"}.get(action,&"cross")

static func pen(pattern: StringName, phase: float) -> Dictionary:
	if pattern==&"cross":
		if phase<.45: return {"point":Vector2(-1,-1).lerp(Vector2(1,1),phase/.45),"down":true,"stroke":0}
		if phase<.5: return {"point":Vector2(1,1).lerp(Vector2(-1,1),(phase-.45)/.05),"down":false,"stroke":0}
		if phase<.95: return {"point":Vector2(-1,1).lerp(Vector2(1,-1),(phase-.5)/.45),"down":true,"stroke":1}
		return {"point":Vector2(1,-1).lerp(Vector2(-1,-1),(phase-.95)/.05),"down":false,"stroke":1}
	if pattern==&"circle": return {"point":Vector2(cos(phase*TAU),sin(phase*TAU)),"down":true,"stroke":0}
	var vertices: Array = SQUARE if pattern==&"square" else TRIANGLE
	var cursor := phase*vertices.size()
	var index := mini(vertices.size()-1,floori(cursor))
	return {"point":vertices[index].lerp(vertices[(index+1)%vertices.size()],cursor-index),"down":true,"stroke":0}

static func mark(pattern: StringName, center: Vector3, frame: Basis, radius: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	if pattern==&"cross":
		for point: Vector2 in [Vector2(-1,-1),Vector2(1,1),Vector2(-1,1),Vector2(1,-1)]: points.append(center+frame*Vector3(point.x,point.y,0)*radius)
	else:
		var count := 16 if pattern==&"circle" else 4 if pattern==&"square" else 3
		for i in range(count):
			for j in [i,i+1]:
				var point: Vector2 = pen(pattern,float(j%count)/count).point
				points.append(center+frame*Vector3(point.x,point.y,0)*radius)
	return points
