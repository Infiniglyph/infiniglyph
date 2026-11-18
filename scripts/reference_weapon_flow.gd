extends RefCounted
## Fast gameplay timing over the existing reference gestures. Visual recovery
## can continue after a buffered input becomes available; no new damage pulses.
const TEMPO := {
	"dagger":Vector2(.34,.80),"fist":Vector2(.34,.85),"twin_blades":Vector2(.34,.90),
	"sword":Vector2(.50,.90),"katana":Vector2(.43,.90),"curved_sword":Vector2(.43,.85),
	"greatsword":Vector2(.62,1.05),"axe":Vector2(.58,.98),"hammer":Vector2(.65,1.08),
	"spear":Vector2(.50,.98),"halberd":Vector2(.56,1.00),"scythe":Vector2(.56,.98),
	"whip":Vector2(.52,.95),"staff":Vector2(.46,.90),"chime":Vector2(.46,.90)}

static func apply(move: Dictionary, item: Dictionary) -> void:
	if not move.get("retargeted",false) or not TEMPO.has(item.get("family","")): return
	var basic: bool = move.action in ["attack_left","attack_right"]
	var target: float = TEMPO[item.family].x if basic else TEMPO[item.family].y
	var old := float(move.duration)
	# Preserve fast authored attacks and small per-item tempo differences.
	var duration := old if old<=target else target+.07*(1-exp(-(old-target)/.35))
	var scale := duration/old
	move.duration = duration
	move.windup = float(move.windup)*scale
	var hits: Array = []
	for hit: float in move.hits: hits.append(hit*scale)
	move.hits = hits
	if move.has("dash"):
		move.dash.start = float(move.dash.start)*scale
		move.dash.end = float(move.dash.end)*scale
	move.reference_flow = true
	move.motion_contact = move.get("motion_contact",float(hits[0])/duration)
	var frames: Array = move.motion
	var contact := 1
	while contact<frames.size()-1 and float(frames[contact].t)<float(move.motion_contact): contact += 1
	var before: Dictionary = frames[maxi(0,contact-2)]
	var at: Dictionary = frames[contact]
	var extension := .10 if item.family in ["staff","chime"] else .055
	for hand: String in ["right","left"]:
		var direction := vector(at[hand])-vector(before[hand])
		if direction.length()<.008 and item.family in ["staff","chime"]:
			direction = Vector3(-float(move.side),-.35,-.5)
		move["flow_"+hand] = direction.normalized()*extension
		var turn := vector(at[hand+"_rotation"])-vector(before[hand+"_rotation"])
		move["flow_"+hand+"_rotation"] = turn.limit_length(.24)
	finish_timing(move)

static func vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

static func finish_timing(move: Dictionary) -> void:
	if not move.get("reference_flow",false): return
	# Every scheduled pulse must finish before an input can take over. Preserve
	# the full named draw/sheath technique rather than cutting its close short.
	move.chain_open = float(move.duration) if move.get("auto_sheathe",false) else minf(float(move.duration),maxf(float(move.hits[-1])+.10,float(move.duration)*.72))
