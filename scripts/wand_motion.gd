extends RefCounted
## Dueling gestures authored for the figure's +Z facing and anatomical right
## (historical LeftArm). These are visual samples, never gameplay action locks.
const KEYS := ["right","left","right_rotation","left_rotation","hip","chest"]

static func _frame(t: float, hand: Vector3, grip: Vector3, hip: Vector3 = Vector3.ZERO, chest: Vector3 = Vector3.ZERO, offhand: Vector3 = Vector3(.28,1.02,.20)) -> Dictionary:
	return {"t":t,"right":[offhand.x,offhand.y,offhand.z],"left":[hand.x,hand.y,hand.z],"right_rotation":[.25,0,-.12],"left_rotation":[grip.x,grip.y,grip.z],"hip":[hip.x,hip.y,hip.z],"chest":[chest.x,chest.y,chest.z]}

static func authored(profile: String, _duration: float = .5, _hits: Array = [], side: float = 1) -> Array:
	var ready := _frame(0,Vector3(-.30,1.12,.21),Vector3(.78,-.12,.14))
	var close := _frame(1,Vector3(-.30,1.12,.21),Vector3(.78,-.12,.14))
	match profile:
		"wand_flick":
			return [ready,_frame(.22,Vector3(-.40,1.34,.16),Vector3(.35,-.35,-.48*side),Vector3(.02,-.12*side,0),Vector3(.02,-.22*side,0)),_frame(.43,Vector3(-.17,1.31,.43),Vector3(1.42,.18,.36*side),Vector3(.04,.16*side,0),Vector3(.08,.14*side,.04*side)),_frame(.73,Vector3(-.38,1.22,.36),Vector3(1.74,.23,.62*side),Vector3(.04,.20*side,0),Vector3(.08,.18*side,0)),close]
		"wand_slither":
			return [ready,_frame(.23,Vector3(-.43,1.35,.10),Vector3(.28,-.40,-.58),Vector3(.02,-.16,0),Vector3(.02,-.24,0)),_frame(.46,Vector3(-.12,1.33,.45),Vector3(1.49,.08,.13),Vector3(.06,.17,0),Vector3(.10,.24,.03)),_frame(.72,Vector3(-.29,1.28,.42),Vector3(1.48,-.32,-.46),Vector3(.04,.19,0),Vector3(.08,.14,0)),close]
		"wand_volley":
			return [ready,_frame(.22,Vector3(-.36,1.42,.12),Vector3(.30,-.15,-.32),Vector3(.02,-.16,0),Vector3(.02,-.20,0)),_frame(.43,Vector3(-.19,1.39,.46),Vector3(1.57,.05,.10),Vector3(.06,.14,0),Vector3(.10,.20,0),Vector3(.30,1.17,.28)),_frame(.68,Vector3(-.24,1.36,.39),Vector3(1.46,-.07,.24),Vector3(.04,.19,0),Vector3(.08,.18,0)),close]
		"wand_ground":
			return [ready,_frame(.24,Vector3(-.43,1.57,.12),Vector3(.10,-.40,-.70),Vector3(.02,-.22,0),Vector3(.02,-.27,-.04)),_frame(.46,Vector3(-.17,.97,.47),Vector3(2.05,.10,.15),Vector3(.13,.19,0),Vector3(.22,.27,.04),Vector3(.34,1.20,.27)),_frame(.73,Vector3(-.44,.96,.32),Vector3(2.08,-.45,-.60),Vector3(.12,.27,0),Vector3(.19,.18,0)),close]
		"wand_wheel":
			# Dip beside the hip, swing beneath the hand, then release upward.
			return [ready,_frame(.23,Vector3(-.39,.86,.02),Vector3(-.32,-.28,-.18),Vector3(.10,-.25,0),Vector3(.12,-.28,-.04)),_frame(.43,Vector3(-.23,.91,.45),Vector3(1.20,.06,.12),Vector3(.12,.13,0),Vector3(.18,.25,.03),Vector3(.34,1.18,.30)),_frame(.70,Vector3(-.15,1.48,.41),Vector3(1.90,.22,.30),Vector3(.03,.30,0),Vector3(.05,.25,.04)),close]
	return [ready,close]

static func _vector(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

static func sample(move: Dictionary, elapsed: float) -> Dictionary:
	var frames: Array = move.get("motion",[])
	if frames.size()<2: frames = authored(str(move.get("profile","wand_flick")),float(move.get("duration",.5)),move.get("hits",[]),float(move.get("side",1)))
	var duration := maxf(.01,float(move.get("duration",.5)))
	var t := clampf(elapsed/duration,0,1)
	# Align the snap with its actual damage/release time. Volley repetitions
	# remain one pointed gesture rather than flailing the whole arm per bolt.
	var hits: Array = move.get("hits",[])
	if not hits.is_empty():
		var hit := float(hits[0])
		var contact := .46 if move.get("profile") in ["wand_slither","wand_ground"] else .43
		t = contact*clampf(elapsed/maxf(.01,hit),0,1) if elapsed<=hit else contact+(1-contact)*clampf((elapsed-hit)/maxf(.01,duration-hit),0,1)
	var a: Dictionary = frames[0]
	var b: Dictionary = frames[-1]
	for i in range(1,frames.size()):
		if t<=float(frames[i].t):
			a = frames[i-1]
			b = frames[i]
			break
	var u := smoothstep(float(a.t),float(b.t),t)
	var result: Dictionary = {}
	for key: String in KEYS: result[key] = _vector(a[key]).lerp(_vector(b[key]),u)
	return result

static func pose(move: Dictionary, elapsed: float, guarding: bool = false, time: float = 0) -> Dictionary:
	if not move.is_empty(): return sample(move,elapsed)
	var result := sample({"duration":1.0,"motion":authored("ready")},0)
	if guarding:
		result.left = Vector3(-.16,1.34,.36)
		result.right = Vector3(.22,1.25,.28)
		result.left_rotation = Vector3(1.22,.10,-.75)
	else:
		result.left.y += sin(time*1.8)*.008
	return result
