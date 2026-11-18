extends RefCounted
## Kyren metadata shares the existing encounter journal and owner/backup policy.
const Journal = preload("res://scripts/encounter_progress.gd")
static func fresh() -> Dictionary:
	var data := Journal.fresh()
	data.kyren = {"challenges":0,"consecutive_defeats":0,"three_defeats_seen":false,"salt":10.0,"lingering_floor":10.0,"pattern":""}
	return data

static func valid(data: Variant) -> bool:
	if not Journal.valid(data) or not data.get("kyren") is Dictionary: return false
	var extra: Dictionary = data.kyren
	for key in ["challenges","consecutive_defeats"]:
		var number: Variant = extra.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number<0 or number>1000000 or floorf(number)!=number: return false
	for key in ["salt","lingering_floor"]:
		var number: Variant = extra.get(key)
		if not (number is int or number is float) or not is_finite(float(number)) or number<0 or number>100: return false
	return extra.get("three_defeats_seen") is bool and extra.get("pattern") in ["","parry","sky","repeat","art"]
