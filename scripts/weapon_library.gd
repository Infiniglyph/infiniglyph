extends RefCounted
## Authored prototype moves: timing and damage are tuning data, not animation assets.
const LOADOUTS := {
	&"down":{"id":&"sword_shield","name":"Longsword + Shield","short":"Sword + Shield","color":Color(0.45,0.85,1),"guard":0.85},
	&"left":{"id":&"spear","name":"Spear","short":"Spear","color":Color(0.35,1,0.75),"guard":0.60},
	&"right":{"id":&"katana","name":"Katana","short":"Katana","color":Color(0.8,0.6,1),"guard":0.70},
	&"up":{"id":&"twin_blades","name":"Twin Blades","short":"Twin Blades","color":Color(1,0.35,0.8),"guard":0.55}}

static func loadout(slot: StringName) -> Dictionary:
	return LOADOUTS.get(slot,LOADOUTS[&"down"])

static func move(slot: StringName, action: StringName) -> Dictionary:
	var weapon: StringName = loadout(slot).id
	var right := action == &"attack_right"
	if action in [&"attack_left",&"attack_right"]:
		match weapon:
			&"sword_shield": return spec("Royal Cleave" if right else "Shield Knuckle",0.52,0.18,24 if right else 16,2.0 if right else 1.35,100,"sweep" if right else "thrust",[0.22],1 if right else -1)
			&"spear": return spec("Lance Thrust" if right else "Reverse Haft",0.50,0.16,23 if right else 18,3.0 if right else 2.1,38 if right else 130,"thrust" if right else "sweep",[0.21],1 if right else -1)
			&"katana": return spec("Drawing Cut" if right else "Returning Edge",0.43,0.13,22,2.1,100,"sweep",[0.17],1 if right else -1)
			_: return spec("Right Rake" if right else "Left Rake",0.34,0.10,16,1.65,100,"sweep",[0.14],1 if right else -1)
	var index := [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"].find(action)
	if index < 0: return {}
	var moves: Array
	match weapon:
		&"sword_shield": moves = [
			spec("Citadel Wheel",0.85,0.22,36,2.8,300,"orbit",[0.34]),
			spec("Glyphbreaker",0.95,0.38,48,3.0,170,"slam",[0.48]),
			spec("Aegis Bloom",0.90,0.18,38,3.2,360,"aegis",[0.30]),
			spec("Sky Bastion",1.0,0.22,29,3.7,110,"pillar",[0.34,0.58])]
		&"spear": moves = [
			spec("Helix Lance",0.95,0.18,16,4.6,38,"spiral",[0.26,0.43,0.60]),
			spec("Orbit Reaper",0.90,0.22,38,3.7,360,"orbit",[0.36]),
			spec("Prism Skewer",1.0,0.34,58,7.0,24,"beam",[0.46]),
			spec("Constellation Rain",1.15,0.28,18,5.5,110,"rain",[0.40,0.60,0.80])]
		&"katana": moves = [
			spec("Neon Crescent",0.68,0.16,34,4.8,70,"crescent",[0.25]),
			spec("Crossed Horizon",0.88,0.18,25,3.6,100,"cross",[0.28,0.48]),
			spec("Afterimage Waltz",1.0,0.16,19,3.6,200,"waltz",[0.25,0.44,0.63]),
			spec("Zero-Line Sever",1.1,0.48,72,7.0,22,"beam",[0.58])]
		_: moves = [
			spec("Binary Cyclone",0.90,0.16,15,2.7,360,"orbit",[0.24,0.42,0.60]),
			spec("Mirror Fang",0.80,0.16,26,2.6,110,"cross",[0.26,0.46]),
			spec("Shatterstep Lattice",1.0,0.18,13,3.9,140,"lattice",[0.25,0.40,0.55,0.70]),
			spec("Twin Comets",0.95,0.22,34,6.3,50,"comets",[0.34,0.55])]
	return moves[index]

static func spec(title: String, duration: float, windup: float, damage: float, reach: float, arc: float, profile: String, hits: Array, side: int = 1) -> Dictionary:
	return {"name":title,"duration":duration,"windup":windup,"damage":damage,"reach":reach,"arc":arc,"profile":profile,"hits":hits,"side":side,"parryable":true,"hit_stun_level":clampf(damage*0.05,0.65,3.6),"hit_stagger":clampf(0.12+damage*0.005,0.2,0.48)}

static func charged_move(slot: StringName, action: StringName, strength: float) -> Dictionary:
	var result := move(slot,action).duplicate(true)
	if result.is_empty() or strength<=0 or not String(action).begins_with("special_"): return result
	var power := clampf(strength,0,1)
	result.name = "Extended "+String(result.name)
	result.damage = float(result.damage)*(1+0.65*power)
	result.reach = float(result.reach)*(1+0.3*power)
	result.duration = float(result.duration)*(1+0.35*power)
	var hits: Array = []
	var first := float(result.hits[0])
	for time: float in result.hits: hits.append(0.1+(time-first)*(1+0.35*power))
	hits.append(float(hits[-1])+0.18+0.08*power)
	result.hits = hits
	result.windup = 0.06
	result.duration = maxf(float(result.duration),float(hits[-1])+0.28)
	result.hit_stun_level = float(result.hit_stun_level)*(1+0.45*power)
	result.hit_stagger = minf(0.65,float(result.hit_stagger)*(1+0.3*power))
	result.charge = power
	return result
