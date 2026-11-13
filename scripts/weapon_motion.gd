extends RefCounted
## Interpolate authored normalized joint/hip curves on the existing rig.
static func vector(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

static func rig_hand(point: Vector3) -> Vector3:
	# The archived reference hand curves use -Z forward; our figure uses +Z.
	# Keep the lateral/vertical gesture, with a small rear shoulder load rather
	# than an arm-length reach behind the back on extreme source windups.
	var hand := Vector3(point.x,point.y,-point.z)
	if hand.z<-.04: hand.z = -.04-.04*(1-exp((hand.z+.04)/.04))
	return hand

static func sample(move: Dictionary, elapsed: float) -> Dictionary:
	var frames: Array = move.get("motion",[])
	if frames.size()<2: return {}
	var t := clampf(elapsed/maxf(0.01,float(move.duration)),0,1)
	if move.get("retargeted",false) and move.hits.size()>1:
		# Repeat the source drive for each existing legitimate pulse, including
		# the charged release's extra strike. Do not invent additional damage.
		var contact := float(move.get("motion_contact",float(move.hits[0])/float(move.duration)))
		for index in range(move.hits.size()):
			var hit := float(move.hits[index])
			var start := (float(move.hits[index-1])+hit)*.5 if index>0 else 0.0
			var finish := (hit+float(move.hits[index+1]))*.5 if index<move.hits.size()-1 else float(move.duration)
			if elapsed<=finish:
				t = contact*clampf((elapsed-start)/maxf(.001,hit-start),0,1) if elapsed<=hit else contact+(1-contact)*clampf((elapsed-hit)/maxf(.001,finish-hit),0,1)
				break
	elif move.has("motion_contact"):
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
	var weight := clampf((t-float(a.t))/maxf(.00001,float(b.t)-float(a.t)),0,1) if move.get("retargeted",false) else smoothstep(float(a.t),float(b.t),t)
	var result: Dictionary = {}
	for key: String in ["right","left","right_rotation","left_rotation","hip","chest"]:
		result[key] = vector(a[key]).lerp(vector(b[key]),weight)
	for key: String in ["hip_offset","left_foot","right_foot"]:
		if a.has(key) and b.has(key): result[key] = vector(a[key]).lerp(vector(b[key]),weight)
	if move.get("retargeted",false) and move.hits.size()>1 and t>.88:
		for key: String in result:
			if frames[0].has(key): result[key] = result[key].lerp(vector(frames[0][key]),smoothstep(.88,1,t))
	if move.get("retargeted",false):
		for hand: String in ["right","left"]:
			result[hand] = rig_hand(result[hand])
			# Reflect the grip frame as well as its path. Conjugating by the Z
			# reflection preserves a proper rotation and the blade's cutting side.
			var grip: Vector3 = result[hand+"_rotation"]
			result[hand+"_rotation"] = Vector3(-grip.x,-grip.y,grip.z)
	return result
