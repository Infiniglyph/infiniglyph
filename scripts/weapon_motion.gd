extends RefCounted
## Interpolate authored normalized joint/hip curves on the existing rig.
const Wand = preload("res://scripts/wand_motion.gd")
static func vector(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

static func rig_hand(point: Vector3) -> Vector3:
	# The archived reference hand curves use -Z forward; our figure uses +Z.
	# Keep the lateral/vertical gesture, with a small rear shoulder load rather
	# than an arm-length reach behind the back on extreme source windups.
	var hand := Vector3(point.x,point.y,-point.z)
	if hand.z<-.04: hand.z = -.04-.04*(1-exp((hand.z+.04)/.04))
	return hand

static func tangent(previous: float, value: float, next: float, before: float, after: float) -> float:
	var a := (value-previous)/maxf(.00001,before)
	var b := (next-value)/maxf(.00001,after)
	if a*b<=0: return 0
	return signf(a)*minf(absf(2*a*b/(a+b)),3*minf(absf(a),absf(b)))

static func flowing_vector(frames: Array, index: int, key: String, weight: float) -> Vector3:
	var a: Dictionary = frames[index]
	var b: Dictionary = frames[index+1]
	var prior: Dictionary = frames[maxi(0,index-1)]
	var next: Dictionary = frames[mini(frames.size()-1,index+2)]
	var av := vector(a[key])
	var bv := vector(b[key])
	var pv := vector(prior.get(key,a[key]))
	var nv := vector(next.get(key,b[key]))
	var span := float(b.t)-float(a.t)
	var result := Vector3.ZERO
	# Monotone Hermite curves keep key poses and unwrapped authored turns,
	# with continuous velocity and no spline overshoot beyond the sampled reach.
	for axis in range(3):
		var slope := (bv[axis]-av[axis])/maxf(.00001,span)
		var start := tangent(pv[axis],av[axis],bv[axis],float(a.t)-float(prior.t),span) if index>0 else slope
		var finish := tangent(av[axis],bv[axis],nv[axis],span,float(next.t)-float(b.t)) if index+2<frames.size() else 0.0
		var u := weight
		result[axis] = (2*u*u*u-3*u*u+1)*av[axis]+(u*u*u-2*u*u+u)*span*start+(-2*u*u*u+3*u*u)*bv[axis]+(u*u*u-u*u)*span*finish
	return result

static func sample(move: Dictionary, elapsed: float) -> Dictionary:
	if move.get("weapon_family")=="wand": return Wand.sample(move,elapsed)
	var frames: Array = move.get("motion",[])
	if frames.size()<2: return {}
	var t := clampf(elapsed/maxf(0.01,float(move.duration)),0,1)
	if (move.get("retargeted",false) or move.get("scribe_gesture",false)) and move.hits.size()>1:
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
	var segment := frames.size()-2
	for index in range(1,frames.size()):
		if t<=float(frames[index].t):
			a = frames[index-1]
			b = frames[index]
			segment = index-1
			break
	var weight := clampf((t-float(a.t))/maxf(.00001,float(b.t)-float(a.t)),0,1) if move.get("retargeted",false) else smoothstep(float(a.t),float(b.t),t)
	var result: Dictionary = {}
	for key: String in ["right","left","right_rotation","left_rotation","hip","chest"]:
		result[key] = flowing_vector(frames,segment,key,weight) if move.get("reference_flow",false) else vector(a[key]).lerp(vector(b[key]),weight)
	for key: String in ["hip_offset","left_foot","right_foot","left_leg","right_leg","left_knee","right_knee"]:
		if a.has(key) and b.has(key): result[key] = vector(a[key]).lerp(vector(b[key]),weight)
	if move.get("reference_flow",false):
		var contact := float(move.motion_contact)
		var follow := clampf((t-contact)/maxf(.01,1-contact),0,1)
		var envelope := sin(PI*follow)*(1-follow)*1.4
		for hand: String in ["right","left"]:
			result[hand] += move["flow_"+hand]*envelope
			result[hand+"_rotation"] += move["flow_"+hand+"_rotation"]*envelope
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
	if move.get("auto_sheathe",false):
		var closing := smoothstep(float(move.get("sheath_start",.68)),1,elapsed/maxf(.01,float(move.duration)))
		result.right = result.right.lerp(Vector3(-.16,1.04,.12),closing)
		result.left = result.left.lerp(Vector3(-.28,1.0,.05),closing)
		result.right_rotation = result.right_rotation.lerp(Vector3(-1.97,.10,0),closing)
	return result
