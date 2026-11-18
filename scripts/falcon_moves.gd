extends RefCounted
## Readable aerial techniques built on the existing parryable strike pipeline.
const Library = preload("res://scripts/weapon_library.gd")

static func move(kind: String, action: StringName) -> Dictionary:
	var result: Dictionary=Library.move(&"horuswing_blades",action).duplicate(true)
	if kind=="archer":
		result.merge({"name":"Skeletal Archer / Drawn Sun","arrow":true,"duration":1.55,"windup":.45,"hits":[.82],"damage":22.0,"reach":18.0,"arc":18.0,"profile":"thrust","retargeted":false,"motion_contact":.53,"motion":bow_motion(),"hit_stun_level":0.0,"hit_stagger":0.0},true)
		return result
	var combo: bool=action==&"attack_left"
	var wing: bool=action==&"special_x"
	var dive: bool=action==&"special_y"
	result.merge({"name":"Wing Slash" if wing else "Sunfall Dive" if dive else "Air Step Combo" if combo else "Talon Crossing","duration":1.50 if dive else 1.2 if combo else 1.15 if wing else .78,"windup":.45 if dive else .30 if wing else .17,"hits":[.78,1.0] if dive else [.29,.53,.77] if combo else [.48] if wing else [.28],"damage":25.0 if dive else 36.0 if wing else 16.0 if combo else 23.0,"reach":2.8 if dive else 3.5 if wing else 2.1,"arc":220.0 if wing else 135.0,"profile":"slam" if dive else "cross" if wing else "sweep","hit_stun_level":1.1 if dive else .8 if wing else 0.0,"hit_stagger":.18 if dive or wing else 0.0},true)
	if kind=="winged_skeleton": result.damage*=.65
	if wing: result.profile="feather"
	if dive:
		result.dive=true
		result.dash={"start":.48,"end":1.0,"speed":8.0}
		result.retargeted=false
		result.motion_contact=.52
		result.motion=dive_motion()
	return result

static func dive_motion() -> Array:
	var keys: Array=[]
	for i in range(5):
		keys.append({"t":[0,.28,.52,.76,1][i],"right":[.32,[1.10,1.65,.91,1.0,1.1][i],[.12,.08,.56,.35,.15][i]],"left":[-.32,[1.10,1.65,.91,1.0,1.1][i],[.12,.08,.56,.35,.15][i]],"right_rotation":[[1.1,-.5,2.6,1.4,1.1][i],0,-.3],"left_rotation":[[1.1,-.5,2.6,1.4,1.1][i],0,.3],"hip":[[0,-.15,.35,.18,0][i],0,0],"chest":[[0,-.2,.25,.15,0][i],0,0]})
	return keys

static func bow_motion() -> Array:
	var keys: Array=[]
	for i in range(4):
		keys.append({"t":[0,.25,.53,1][i],"right":[.15,1.36,[.25,.50,.50,.25][i]],"left":[-.15,1.36,[.25,-.08,.38,.25][i]],"right_rotation":[0,0,0],"left_rotation":[0,0,0],"hip":[0,-.22,0],"chest":[0,.18,0]})
	return keys
