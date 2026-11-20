extends RefCounted
## One release per gesture; projectile motion and contacts live in WandEffect.
const Motion = preload("res://scripts/wand_motion.gd")
const ACTIONS := [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
const CASTS := ["flick","flick","slither","volley","ground","wheel"]
const TITLES := ["Backhand Laser Flick","Forehand Laser Flick","Slither Shot","Laser Volley","Ground Cast","Laser Wheel"]
const DURATIONS := [.34,.34,.52,.55,.62,.60]
const RELEASES := [.13,.13,.21,.22,.26,.25]
const DAMAGE := [22.0,22.0,30.0,18.0,36.0,34.0]
const REACH := [4.0,4.0,12.0,14.0,9.0,12.0]

static func move(item: Dictionary, action: StringName, aerial: bool = false) -> Dictionary:
	var index := ACTIONS.find(action)
	if index<0: return {}
	var profile := "wand_"+String(CASTS[index])
	var side := -1 if index==0 else 1
	var duration: float = DURATIONS[index]
	var hits := [float(RELEASES[index])]
	return {"name":TITLES[index],"action":String(action),"item_id":item.id,"weapon_family":"wand","wand_attack":CASTS[index],"duration":duration,"windup":hits[0]-.035,"hits":hits,"damage":DAMAGE[index],"reach":REACH[index],"arc":75.0,"profile":profile,"side":side,"parryable":true,"hit_stun_level":0.0 if index<2 else 1.1,"hit_stagger":0.0 if index<2 else .22,"aerial":aerial,"motion":Motion.authored(profile,duration,hits,side),"chain_open":hits[0]+.11,"body_profile":[.10,.40,.18,.20,.10]}
