extends RefCounted
## Authored roles, equipment and drops. No new player class gates or shield slots.
const TYPES := {
	"crocodile":{"name":"Crocodile Warden","hp":620,"speed":2.2,"weapon":"sobek_warden_khopesh","tier":2,"scale":1.55,"guard":true,"drops":["sobek_warden_khopesh","crocodile_cuirass","floodguard_tassets","sobek_emblem"]},
	"drowned":{"name":"Drowned Skeleton","hp":110,"speed":3.0,"weapon":"tomb_blade","tier":1,"drops":["tomb_blade","mummified_wraps"]},
	"riverbound":{"name":"Riverbound Skeleton","hp":135,"speed":2.8,"weapon":"sentinel_spear","tier":1,"drops":["sentinel_spear","burial_sash"]},
	"scorpion":{"name":"Tomb Scorpion","hp":75,"speed":4.8,"weapon":"tomb_blade","tier":1,"beast":true,"venom":true,"drops":["venom_fang","bone_shards"]},
	"ibis":{"name":"Ibis Scribe","hp":260,"speed":3.2,"weapon":"scribes_grimoire","tier":2,"drops":["scribes_grimoire","thothic_scepter","ibis_scribe_robes","glyphweaver_sash","thoths_quill"]},
	"acolyte":{"name":"Scribe Acolyte","hp":140,"speed":3.0,"weapon":"thothic_scepter","tier":1,"drops":["thothic_scepter","ibis_scribe_robes"]},
	"construct":{"name":"Glyph Construct","hp":160,"speed":2.6,"weapon":"tomb_blade","tier":1,"beast":true,"drops":["thoths_quill","bone_shards"]},
	"skeletal_scribe":{"name":"Skeletal Scribe","hp":120,"speed":2.6,"weapon":"scribes_grimoire","tier":1,"drops":["scribes_grimoire","linen_bindings"]},
	"tomb_walker":{"name":"Tomb Walker","hp":80,"speed":4.1,"weapon":"tomb_blade","tier":1,"drops":["mummified_wraps","bone_shards"]},
	"tomb_fighter":{"name":"Tomb Fighter","hp":130,"speed":3.7,"weapon":"tomb_blade","tier":1,"drops":["tomb_blade","burial_sash"]},
	"burial_guard":{"name":"Burial Guard","hp":210,"speed":2.8,"weapon":"warden_khopesh","tier":2,"guard":true,"drops":["warden_khopesh","mummified_wraps","tomb_charm"]},
	"skeletal_mummy":{"name":"Skeletal Mummy","hp":155,"speed":3.0,"weapon":"sentinel_spear","tier":1,"drops":["sentinel_spear","burial_sash"]},
	"cursed_warden":{"name":"Cursed Warden","hp":330,"speed":3.8,"weapon":"warden_khopesh","tier":3,"reassemble":true,"drops":["tomb_charm","mummified_wraps","burial_sash"]},
	"renu":{"name":"Renu / The Huntress","hp":1050,"speed":5.4,"weapon":"sekhmet_blades","tier":3,"scale":1.25,"champion":true,"drops":["sekhmet_blades","lioness_champion_armor"]},
	"tefet":{"name":"Tefet / The Dancer","hp":950,"speed":6.0,"weapon":"sekhmet_blades","tier":3,"scale":1.25,"champion":true,"drops":["sekhmet_blades","champion_tassets"]},
	"sakhra":{"name":"Sakhra / The Warden","hp":1250,"speed":3.8,"weapon":"champions_spear","tier":3,"scale":1.3,"champion":true,"guard":true,"drops":["champions_spear","lioness_champion_armor","champion_tassets"]},
	"charmer":{"name":"Undead Snake Charmer","hp":310,"speed":3.3,"weapon":"charmers_whip","tier":3,"drops":["charmers_whip","serpent_cultist_hood","cultist_wraps","viperbinding_sash","serpent_idol"]},
	"asp":{"name":"Asp Viper","hp":50,"speed":4.8,"weapon":"tomb_blade","tier":1,"beast":true,"venom":true,"drops":["venom_fang"]},
	"cobra":{"name":"Cobra Sentinel","hp":150,"speed":2.8,"weapon":"tomb_blade","tier":2,"beast":true,"venom":true,"guard":true,"drops":["venom_fang","serpent_idol"]},
	"horned_viper":{"name":"Horned Viper","hp":85,"speed":5.5,"weapon":"tomb_blade","tier":1,"beast":true,"venom":true,"drops":["venom_fang"]},
	"burial_serpent":{"name":"Burial Serpent","hp":290,"speed":3.2,"weapon":"tomb_blade","tier":2,"scale":1.6,"beast":true,"venom":true,"drops":["venom_fang","viperbinding_sash"]},
	"charm_obelisk":{"name":"Charm Obelisk","hp":180,"speed":0.0,"weapon":"tomb_blade","tier":2,"beast":true,"drops":["serpent_idol"]}
}
static func get_type(kind: String) -> Dictionary: return TYPES.get(kind,{})
static func entries(floor_id: StringName) -> Array:
	var kinds: Array=[]
	match floor_id:
		&"B1": kinds=["jackal","skeleton","skeleton","jackal","skeleton","skeleton"]
		&"B3": kinds=["crocodile","drowned","riverbound","scorpion","drowned","crocodile","riverbound","scorpion","crocodile","drowned"]
		&"B4": kinds=["ibis","acolyte","construct","skeletal_scribe","jackal","ibis","construct","acolyte","falcon","skeletal_scribe"]
		&"B5": kinds=["tomb_walker","tomb_fighter","burial_guard","skeletal_mummy","tomb_walker","cursed_warden","tomb_fighter","tomb_walker","burial_guard","skeletal_mummy","tomb_walker","tomb_fighter","tomb_walker","cursed_warden","tomb_fighter","tomb_walker"]
		&"B6": return [["b6_renu","renu",-12,-48,true],["b6_tefet","tefet",12,-48,true],["b6_sakhra","sakhra",0,-64,true]]
		&"B7": kinds=["charmer","asp","cobra","horned_viper","asp","charmer","burial_serpent","cobra","horned_viper","charm_obelisk","asp","burial_serpent","horned_viper","asp","cobra","charm_obelisk"]
		_:
			if String(floor_id).begins_with("U"):
				var n:=int(String(floor_id).trim_prefix("U"))
				kinds=["jackal"] if n==8 else ["falcon","skeleton","jackal"] if n in [3,6] else ["jackal","skeleton","skeleton"]
	var result: Array=[]
	for i in range(kinds.size()):
		var x: float=[-22,12,24,-10,0,-34,32,-24,18,0,-40,40,-15,15,-28,28][i]
		var z: float=[-48,-38,-58,-58,-76,-76,-80,-96,-103,-113,-40,-45,-120,-125,-138,-145][i]
		if String(floor_id).begins_with("U"):
			var n:=int(String(floor_id).trim_prefix("U"))
			var width:=minf(22,64.0*(1-(8.0*n+3)/82.0)*.55)
			x=[-1.0,1.0,0.0][i]*width*.65
			z=-28+[-.65,-.4,.4][i]*width
		result.append([String(floor_id).to_lower()+"_"+str(i+1),kinds[i],x,z,kinds[i] in ["cursed_warden","charmer"]])
	return result
