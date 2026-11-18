extends RefCounted
const Library = preload("res://scripts/weapon_library.gd")
const Types = preload("res://scripts/pyramid_bestiary.gd")

static func move(kind: String, action: StringName) -> Dictionary:
	var data:=Types.get_type(kind)
	var result: Dictionary=Library.move(StringName(data.weapon),action).duplicate(true)
	result.action=action
	result.erase("weapon_family") # Enemy volumes below share the combat resolver.
	result.merge({"damage":23.0,"duration":1.05,"windup":.25,"hits":[.46],"reach":2.2,"arc":120.0,"hit_stun_level":0.0,"hit_stagger":0.0,"profile":"sweep"},true)
	var special: bool=action not in [&"attack_right",&"attack_left"]
	match kind:
		"crocodile":
			result.merge({"name":"Heavy Cleave","duration":1.75,"windup":.60,"hits":[.95],"damage":58.0,"reach":3.6,"arc":160.0},true)
			if action==&"special_x": result.merge({"name":"Shield Slam","duration":1.55,"hits":[.80],"reach":2.5,"damage":42.0,"dash":{"start":.48,"end":.78,"speed":5.0},"toss":true,"profile":"thrust"},true)
			elif action==&"special_y": result.merge({"name":"Grab and Toss","duration":1.8,"hits":[.90],"reach":2.1,"damage":65.0,"toss":true,"profile":"cross"},true)
			elif action==&"special_rt_x": result.merge({"name":"Tail Sweep","duration":1.9,"hits":[1.05],"reach":4.0,"arc":300.0,"damage":44.0},true)
			elif action==&"special_rt_y": result.merge({"name":"Flood Surge","duration":2.3,"hits":[.75],"field":"flood","field_radius":4.8,"field_delay":.65,"damage":48.0,"profile":"slam"},true)
		"ibis","acolyte","skeletal_scribe":
			result.merge({"name":"Glyph Volley","glyph_volley":true,"duration":1.65,"windup":.45,"hits":[.78],"reach":16.0,"damage":17.0,"profile":"thrust","motion":conduct()},true)
			if action==&"special_x": result.merge({"name":"Glyph Field","glyph_volley":false,"field":"glyph","field_radius":3.4,"field_delay":.8,"duration":1.7,"damage":13.0},true)
			elif action==&"special_y": result.merge({"name":"Hieroglyph Bind","glyph_volley":false,"field":"bind","field_radius":2.3,"field_delay":.9,"duration":1.9,"damage":16.0},true)
			elif action==&"special_rt_x": result.merge({"name":"Barrier Tablet","glyph_volley":false,"ritual":"ward","duration":1.8},true)
			elif action==&"special_rt_y": result.merge({"name":"Scribe's Chant","glyph_volley":false,"ritual":"chant","duration":2.0},true)
		"construct": result.merge({"name":"Crystal Orbit","profile":"orbit","reach":2.7,"arc":300.0,"damage":21.0},true)
		"renu":
			result.merge({"name":"Pounce Lunge","duration":1.55,"windup":.36,"hits":[.72],"reach":2.8,"damage":40.0,"dash":{"start":.40,"end":.68,"speed":12.0},"profile":"cross"},true)
		"tefet": result.merge({"name":"Blade Dance","duration":1.7,"windup":.32,"hits":[.55,.84,1.15],"reach":2.7,"arc":200.0,"damage":22.0,"profile":"waltz"},true)
		"sakhra": result.merge({"name":"Warden's Wide Sweep","duration":1.65,"windup":.55,"hits":[.90],"reach":4.0,"arc":210.0,"damage":48.0,"profile":"sweep"},true)
		"charmer","charm_obelisk":
			result.merge({"name":"Whip Crack","duration":1.5,"windup":.35,"hits":[.68],"reach":5.2,"damage":28.0,"arc":100.0,"weapon_family":"whip"},true)
			if action==&"special_x": result.merge({"name":"Serpent Summon","ritual":"summon","duration":2.0},true)
			elif action==&"special_y": result.merge({"name":"Venom Cloud","field":"venom","field_radius":3.8,"field_delay":.9,"duration":2.0,"damage":9.0},true)
			elif action==&"special_rt_x": result.merge({"name":"Coordinated Assault","ritual":"chant","duration":1.8},true)
		"asp","cobra","horned_viper","burial_serpent","scorpion":
			result.merge({"name":"Venom Bite","duration":1.0,"windup":.28,"hits":[.48,.70] if kind=="horned_viper" else [.48],"reach":2.0 if kind!="burial_serpent" else 3.1,"damage":12.0 if kind=="asp" else 24.0,"profile":"thrust"},true)
			if kind=="cobra" and special: result.merge({"name":"Venom Spit","glyph_volley":true,"venom_projectile":true,"reach":12.0,"damage":18.0,"duration":1.8,"hits":[.8]},true)
		"tomb_walker": result.merge({"name":"Grave Grasp","damage":14.0,"drain":true,"profile":"cross"},true)
		"skeletal_mummy","riverbound": result.merge({"name":"Burial Spear","reach":3.4,"arc":55.0,"profile":"thrust"},true)
		"cursed_warden":
			result.merge({"name":"Cursed Cleave","reach":3.2,"arc":180.0,"damage":33.0},true)
			if special: result.merge({"name":"Burial Command","ritual":"chant","duration":1.8},true)
	if data.get("champion",false) and action==&"special_rt_y":
		result.merge({"name":"Lioness Convergence","duration":2.0,"windup":.6,"hits":[.8],"field":"sand","field_radius":4.5,"field_delay":.85,"damage":35.0,"profile":"slam"},true)
	if special:
		result.hit_stun_level=1.2
		result.hit_stagger=.22
	return result

static func conduct() -> Array:
	var keys: Array=[]
	for i in range(5):
		keys.append({"t":[0,.25,.48,.72,1][i],"right":[[.32,.52,.15,-.25,.32][i],[1.05,1.65,1.5,1.05,1.05][i],[.2,.25,.6,.4,.2][i]],"left":[-.32,1.26,.35],"right_rotation":[[0,-.5,1.4,2.0,0][i],0,0],"left_rotation":[.55,0,0],"hip":[0,[0,-.2,.3,.1,0][i],0],"chest":[0,[0,.3,-.3,-.1,0][i],0]})
	return keys
