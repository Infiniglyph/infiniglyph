extends RefCounted
## One timeline coordinates the serpent and Pharaoh; all impacts use shared rules.
const Library = preload("res://scripts/weapon_library.gd")
const PHASE_ONE := ["lunge","spit","sweep","judgment","command"]
const PHASE_TWO := ["coil","storm","grasp","annihilation","bite","inherited"]
const NAMES := {"lunge":"Serpent Lunge","spit":"Venom Spit","sweep":"Serpent Sweep","judgment":"Radiant Judgment","command":"Pharaoh's Command","coil":"Cataclysmic Coil","storm":"Venom Storm","grasp":"Serpent Grasp","annihilation":"Radiant Annihilation","bite":"Judgment Bite","inherited":"Inherited Pharaoh's Command"}

static func move(style: String) -> Dictionary:
	var data: Array = {
		"lunge":[2.55,.85,125,14,80,"thrust",[1.08]],
		"spit":[2.45,.95,65,34,100,"beam",[1.05]],
		"sweep":[2.9,1.0,105,15,250,"sweep",[1.3]],
		"judgment":[2.4,.85,90,45,100,"beam",[1.0]],
		"command":[3.5,1.2,95,35,100,"cross",[1.40,1.78]],
		"coil":[3.3,1.15,150,24,360,"slam",[1.5]],
		"storm":[3.5,1.1,60,40,150,"rain",[1.35]],
		"grasp":[2.8,1.0,120,17,90,"thrust",[1.2]],
		"annihilation":[3.15,1.05,130,20,250,"sweep",[1.4]],
		"bite":[2.6,.7,160,16,85,"thrust",[.94]],
		"inherited":[3.9,1.1,105,35,140,"cross",[1.35,1.88,2.22]]
	}.get(style,[])
	if data.is_empty(): return {}
	var result: Dictionary=Library.spec(NAMES[style],data[0],data[1],data[2],data[3],data[4],data[5],data[6])
	result.lorai_style=style
	result.action="special_y"
	result.hit_stun_level=2.0
	result.hit_stagger=.30
	result.contact_before=.10
	result.contact_after=.17
	return result

static func window(move: Dictionary, pulse: int) -> Vector2:
	return Vector2(float(move.hits[pulse])-.10,float(move.hits[pulse])+.17)
