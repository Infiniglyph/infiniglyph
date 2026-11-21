extends RefCounted
## Civilian-only need debt: zero is full, one is empty. Time is analytic so
## unloaded citizens do not need a frame loop or catch-up physics.
const RED := .8
const FOOD_SECONDS := 3600.0
const WATER_SECONDS := 1800.0
const BASE_HP := 1000.0

static func advance(state: Dictionary, seconds: float) -> float:
	if not is_finite(seconds) or seconds<=0: return 0.0
	var damage:=0.0
	for spec: Array in [["hunger",FOOD_SECONDS,1.0],["thirst",WATER_SECONDS,2.0]]:
		var debt:=float(state.get(spec[0],.25))
		var red_time:=maxf(0,seconds-maxf(0,RED-debt)*float(spec[1]))
		state[spec[0]]=minf(1,debt+seconds/float(spec[1]))
		damage+=red_time*float(spec[2])
	state.vitality=maxf(0,float(state.get("vitality",BASE_HP))-damage)
	return damage

static func consume(state: Dictionary, drink: bool, healing: float=0) -> void:
	state["thirst" if drink else "hunger"]=0.0
	if not drink: state.vitality=minf(BASE_HP,float(state.get("vitality",BASE_HP))+maxf(0,healing))

static func reset(state: Dictionary) -> void:
	state.hunger=.25
	state.thirst=.25
	state.vitality=BASE_HP

static func summary(state: Dictionary) -> String:
	return "Food %d%%  /  Water %d%%%s" % [roundi((1-float(state.hunger))*100),roundi((1-float(state.get("thirst",.25)))*100),"  [RED: losing HP]" if maxf(float(state.hunger),float(state.get("thirst",0)))>=RED else ""]
