extends RefCounted
## Weighted authored translations. Missing knowledge/amounts never get invented.
const Message = preload("res://scripts/intent_message.gd")
var phrases: Array = []
var rng := RandomNumberGenerator.new()
var _tokens := RegEx.new()

func _init() -> void:
	rng.randomize()
	_tokens.compile("\\{([a-z_]+)\\}")
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/communication_phrases.json"))
	if data is Dictionary and data.get("phrases") is Array: phrases=data.phrases

func translate(message: Dictionary,profile: Dictionary,context: Dictionary = {}) -> Dictionary:
	if Message.validate(message).is_empty(): return {"text":"","phrase_id":""}
	var values: Dictionary={"speaker_name":String(context.get("speaker_name",message.speaker_id)),"listener_name":String(context.get("listener_name",message.listener_id))}
	for key: String in ["item","item_name","price","offered_price","asking_price","guild","location","information"]:
		if message.parameters.has(key): values[key]=str(message.parameters[key])
	for key: String in ["price","offered_price","asking_price"]:
		if message.parameters.has(key): values.price=str(int(message.parameters[key]))
	if values.has("item_name"): values.item=values.item_name
	elif not values.has("item") and not message.subject_id.is_empty(): values.item=String(message.subject_id).replace("_"," ")
	# Knowledge-bearing wording must have a semantic source reference. It is the
	# authority adapter's job to validate that fact against the speaker's memory.
	if not message.parameters.has("fact_id"): values.erase("information")
	elif not values.has("information") and message.parameters.get("detail") is String:
		values.information=String(message.parameters.detail)
	var candidates: Array[Dictionary]=[]
	var total:=0.0
	for phrase: Dictionary in phrases:
		if phrase.get("intent")!=message.intent: continue
		if values.has("information") and String(phrase.get("id","")).ends_with("_unknown"): continue
		if phrase.has("special") and phrase.special!=profile.get("special",""): continue
		var compatible:=true
		for token: RegExMatch in _tokens.search_all(String(phrase.template)):
			if not values.has(token.get_string(1)): compatible=false; break
		if not compatible: continue
		var weight:=float(phrase.get("weight",1.0))
		if phrase.get("tone")==profile.get("tone"): weight*=2.0
		if phrase.get("tone")==message.emotion: weight*=1.7
		if profile.get("personality","") in phrase.get("personality_tags",[]): weight*=1.8
		for tag: String in phrase.get("context_tags",[]):
			if context.get(tag,false) or tag in context.get("tags",[]): weight*=1.5
		weight*=1.0+minf(.5,float(profile.get("habits",{}).get(phrase.id,0))*.025)
		if not profile.get("context",[]).is_empty() and profile.context[-1].intent==message.intent: weight*=.75
		if phrase.has("special"): weight*=2.5
		total+=weight
		candidates.append({"phrase":phrase,"weight":weight})
	if candidates.is_empty(): return {"text":_with_details("["+String(message.intent).replace("_"," ")+"]",message),"phrase_id":""}
	var pick:=rng.randf()*total
	var selected: Dictionary=candidates[-1].phrase
	for candidate: Dictionary in candidates:
		pick-=float(candidate.weight)
		if pick<=0: selected=candidate.phrase; break
	var output:=String(selected.template)
	for token: RegExMatch in _tokens.search_all(String(selected.template)):
		output=output.replace(token.get_string(),String(values[token.get_string(1)]))
	return {"text":_with_details(output,message),"phrase_id":String(selected.id)}

func _display_value(value: Variant,limit: int = 128) -> String:
	if not (value is String or value is StringName or value is int or value is float): return ""
	var text:=str(value).strip_edges()
	return text if text.length()<=limit else text.left(limit-1)+"…"

func _with_details(wording: String,message: Dictionary) -> String:
	# Wording is only presentation. Preserve the actual adapter's instructions and
	# amounts even when a personality's selected introductory phrase is brief.
	var params: Dictionary=message.parameters
	var pieces: Array[String]=[wording.left(800)]
	for key: String in ["detail","reason"]:
		if key=="detail" and message.intent in ["share_rumor","share_info"] and not params.has("fact_id"): continue
		var value:=_display_value(params.get(key,""),384 if key=="detail" else 192)
		if not value.is_empty() and not value in wording: pieces.append(value)
	var names: Dictionary={"name":"Name","role":"Role","goal":"Goal","faction":"Faction","treasury":"Treasury","reward":"Reward","quest_id":"Quest","status":"Status"}
	for key: String in names:
		# The opening greeting retains the speaker's authored personality. An
		# unrelated current AI goal must not become its greeting or an instruction.
		if key=="goal" and message.intent=="greet": continue
		if not params.has(key): continue
		var value:=_display_value(params[key])
		if not value.is_empty(): pieces.append(String(names[key])+": "+value)
	return "\n".join(pieces)
