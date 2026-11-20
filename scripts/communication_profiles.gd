extends RefCounted
## Recognizable deterministic voices, with a bounded memory of phrasing habits.
const Message = preload("res://scripts/intent_message.gd")
const MAX_PROFILES := 2048
const TRAITS := ["verbosity","formality","humor","confidence","sarcasm","friendliness","expressiveness"]
var records: Dictionary = {}

func profile(id: String,identity: Dictionary = {}) -> Dictionary:
	if records.has(id): return records[id]
	if not Message.text(id): return {}
	if records.size()>=MAX_PROFILES: records.erase(records.keys()[0])
	var traits: Dictionary={}
	for key: String in TRAITS: traits[key]=.15+float(posmod((id+key).hash(),71))/100.0
	var personality:=String(identity.get("personality","curious"))
	if personality=="friendly": traits.friendliness=.9; traits.humor=.7
	elif personality=="pragmatic": traits.formality=.8; traits.verbosity=.3
	elif personality=="dismissive": traits.sarcasm=.8; traits.friendliness=.2
	var special: bool=String(identity.get("kind",""))=="unique" and (String(identity.get("special",""))=="avat_ar" or id.contains("avat_ar"))
	if special: traits.friendliness=.98; traits.humor=.95; traits.expressiveness=.98
	var voice: Dictionary={"pitch":190.0+float(posmod(id.hash(),350)),"jitter":.05+float(posmod((id+"j").hash(),20))/100.0,"timbre":float(posmod((id+"t").hash(),80))/100.0,"speed":27.0+float(posmod((id+"s").hash(),20)),"rhythm":.75+float(posmod((id+"r").hash(),40))/100.0}
	if special: voice.pitch=510.0; voice.speed=39.0; voice.jitter=.21; voice.timbre=.3
	var row: Dictionary={"id":id,"personality":personality,"tone":"cheerful" if special else "friendly" if traits.friendliness>.65 else "formal" if traits.formality>.65 else "plain","special":"avat_ar" if special else "","traits":traits,"voice":voice,"habits":{},"context":[]}
	records[id]=row
	return row

func remember_phrase(id: String,phrase: String,message: Dictionary) -> void:
	var row:=profile(id)
	if row.is_empty(): return
	if not phrase.is_empty():
		if not row.habits.has(phrase) and row.habits.size()>=8: row.habits.erase(row.habits.keys()[0])
		row.habits[phrase]=mini(64,int(row.habits.get(phrase,0))+1)
	row.context.append({"intent":message.intent,"listener_id":message.listener_id,"subject_id":message.subject_id})
	while row.context.size()>8: row.context.pop_front()

func serialize() -> Dictionary: return {"version":1,"records":records.duplicate(true)}

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=2 or input.get("version")!=1 or not input.get("records") is Dictionary or input.records.size()>MAX_PROFILES: return {}
	var result: Dictionary={}
	for id: Variant in input.records:
		var row: Variant=input.records[id]
		if not Message.text(id) or not row is Dictionary or row.size()!=8 or row.get("id")!=id: return {}
		for key: String in ["personality","tone","special"]:
			if not Message.text(row.get(key),40,true): return {}
		if not row.get("traits") is Dictionary or row.traits.size()!=TRAITS.size() or not row.get("voice") is Dictionary or row.voice.size()!=5: return {}
		for key: String in TRAITS:
			if not _number(row.traits.get(key),0,1): return {}
		for spec: Array in [["pitch",100,900],["jitter",0,.5],["timbre",0,1],["speed",10,80],["rhythm",.4,2]]:
			if not _number(row.voice.get(spec[0]),spec[1],spec[2]): return {}
		if not row.get("habits") is Dictionary or row.habits.size()>8 or not row.get("context") is Array or row.context.size()>8: return {}
		for phrase: Variant in row.habits:
			if not Message.text(phrase,80) or not _number(row.habits[phrase],1,64) or float(row.habits[phrase])!=floorf(row.habits[phrase]): return {}
		for recent: Variant in row.context:
			if not recent is Dictionary or recent.size()!=3: return {}
			for key: String in ["intent","listener_id","subject_id"]:
				if not Message.text(recent.get(key),128,true): return {}
		result[id]=row.duplicate(true)
		for phrase: String in result[id].habits: result[id].habits[phrase]=int(result[id].habits[phrase])
	return {"version":1,"records":result}

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high

func restore(input: Variant) -> bool:
	var decoded:=validate(input)
	if decoded.is_empty(): return false
	records=decoded.records
	return true
