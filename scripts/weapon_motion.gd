extends RefCounted
## Interpolate authored normalized joint/hip curves on the existing rig.
static func vector(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

static func sample(move: Dictionary, elapsed: float) -> Dictionary:
	var frames: Array = move.get("motion",[])
	if frames.size()<2: return {}
	var t := clampf(elapsed/maxf(0.01,float(move.duration)),0,1)
	if move.has("motion_contact"):
		var first := float(move.hits[0])
		var contact := float(move.motion_contact)
		t = elapsed/maxf(.01,first)*contact if elapsed<=first else contact+(1-contact)*clampf((elapsed-first)/maxf(.01,float(move.duration)-first),0,1)
	var a: Dictionary = frames[0]
	var b: Dictionary = frames[-1]
	for index in range(1,frames.size()):
		if t<=float(frames[index].t):
			a = frames[index-1]
			b = frames[index]
			break
	var weight := smoothstep(float(a.t),float(b.t),t)
	var result: Dictionary = {}
	for key: String in ["right","left","right_rotation","left_rotation","hip","chest"]:
		result[key] = vector(a[key]).lerp(vector(b[key]),weight)
	return result
