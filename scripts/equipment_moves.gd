extends RefCounted
## Named item recipes over sampled reference motion. Bounded lazy banks/cache;
## the existing strike resolver remains authoritative for damage and defense.
const BANK_LIMIT := 4
const CACHE_LIMIT := 24
static var banks: Dictionary = {}
static var moves: Dictionary = {}

static func bank(cut: String) -> Dictionary:
	if not banks.has(cut):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/motions/"+cut+".json"))
		if not parsed is Dictionary: return {}
		if banks.size()>=BANK_LIMIT: banks.erase(banks.keys()[0])
		banks[cut] = parsed
	return banks[cut]

static func move(item: Dictionary, action: StringName, combo: int, aerial: bool) -> Dictionary:
	var recipe: Dictionary = item.motion_set
	var basic := action in [&"attack_left",&"attack_right"]
	var index := posmod(combo,3) if basic else [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"].find(action)
	if index<0: return {}
	var key := String(item.id)+":"+String(action)+":"+str(index)+":"+str(aerial)
	if moves.has(key): return moves[key].duplicate(true)
	var clip_key: String = recipe.basic[index+(0 if action==&"attack_right" else 3)] if basic else recipe.arts[index]
	var clip: Dictionary = bank(recipe.cut).get(clip_key,{})
	if clip.is_empty(): return {}
	var cut: String = recipe.cut
	var heavy := cut in ["maul","greatblade","cleaver"]
	var point := cut in ["lance","rapier","conduit"]
	var profile := "thrust" if point else ("slam" if cut=="maul" else "sweep")
	if not basic: profile = ("beam" if index==3 else "spiral") if point else ("slam" if heavy else "cross" if cut=="paired" else "crescent")
	var duration := clampf(float(clip.duration),.40,1.85 if basic else 2.4)*float(recipe.tempo)
	var contact := clampf(float(clip.contact),.20,.74)
	var damage := (30.0 if heavy else 18.0 if cut in ["knife","knuckles","paired"] else 23.0) if basic else (38.0+index*6.0)
	var titles: Array = ["Opening","Return","Closing"] if basic else ["Gathered Arc","Rising Proof","Woven Refrain","Final Line"]
	var result := {"name":String(item.name)+" / "+String(titles[index]),"duration":duration,"windup":duration*maxf(.08,contact-.10),"damage":damage,"reach":clampf(float(item.geometry.length)+.65,.9,3.8)*(1.0 if basic else 1.35),"arc":48.0 if point else 125.0,"profile":profile,"hits":[duration*contact],"side":1 if action!=&"attack_left" else -1,"parryable":true,"hit_stun_level":1.4 if heavy else .9,"hit_stagger":.28 if heavy else .22,"item_id":String(item.id),"combo_index":index if basic else 0,"combo_next":(index+1)%3 if basic else 0,"aerial":aerial,"motion_contact":contact,"retargeted":true,"grip_mode":item.attachment.offhand,"motion":clip.motion.duplicate(true),"clip_id":clip_key,"body_profile":[.14*float(recipe.weight),.6,.27,float(recipe.stance),.14]}
	for frame: Dictionary in result.motion:
		for foot: String in ["left_foot","right_foot"]: frame[foot][0] = float(frame[foot][0])*float(recipe.stance)/.20
		for hand: String in ["right","left"]:
			frame[hand][2] = float(frame[hand][2])*float(recipe.leverage)
			frame[hand][1] = float(frame[hand][1])+float(recipe.grip)
		# Let the existing air kick/cradle carry the lower body while hands and
		# chest perform a separate compact airborne version of this sequence.
		if aerial:
			frame.hip[0] = float(frame.hip[0])*.65
			frame.chest[0] = float(frame.chest[0])*.8
			frame.hip_offset = [0,0,0]
			for hand: String in ["right","left"]: frame[hand][2] = float(frame[hand][2])*.88
	if moves.size()>=CACHE_LIMIT: moves.erase(moves.keys()[0])
	moves[key] = result
	return result.duplicate(true)
