extends RefCounted
## Deduplication and compact structured continuity. Actions remain callbacks.
const Message = preload("res://scripts/intent_message.gd")
const Intents = preload("res://scripts/universal_intent.gd")
const MAX_SEEN := 512
const MAX_FACTS := 256
var channel_id := "uic_"+str(Time.get_unix_time_from_system()).replace(".","")+"_"+str(Time.get_ticks_usec())
var serial := 0
var seen: Array[String] = []
var facts: Array[Dictionary] = []
var recent: Array[Dictionary] = []
var busy := false

func make_message(speaker: String,listener: String,intent: String,subject: String = "",parameters: Dictionary = {},emotion: String = "neutral",conversation: String = "",timestamp: float = 0.0,event_id: String = "") -> Dictionary:
	serial += 1
	var id:=channel_id+"/"+str(serial)
	return Message.validate({"message_id":id,"event_id":id if event_id.is_empty() else event_id,"speaker_id":speaker,"listener_id":listener,"intent":intent,"subject_id":subject,"parameters":parameters,"emotion":emotion,"conversation_id":conversation if not conversation.is_empty() else channel_id+"/conversation/"+str(serial),"world_timestamp":timestamp})

func receive(input: Dictionary,handler: Callable = Callable()) -> Dictionary:
	var message:=Message.validate(input)
	if message.is_empty(): return {"accepted":false,"reason":"invalid"}
	if busy: return {"accepted":false,"reason":"busy"}
	var key: String="m/"+message.message_id
	var event: String="e/"+message.event_id
	if seen.has(key) or seen.has(event): return {"accepted":false,"reason":"duplicate","duplicate":true}
	# Mark before an authority callback, including rejected requests. Replays
	# cannot retry a side effect by changing presentation or reentering signals.
	seen.append(key); seen.append(event)
	while seen.size()>MAX_SEEN: seen.pop_front()
	busy=true
	var outcome: Variant=handler.call(message.duplicate(true)) if handler.is_valid() else {"accepted":true}
	if not outcome is Dictionary: outcome={"accepted":bool(outcome)}
	var result: Dictionary=outcome.duplicate(true)
	result.accepted=bool(result.get("accepted",true))
	if result.accepted:
		for fact: Variant in result.get("facts",[]):
			if fact is Dictionary and fact.size()<=8 and Message.values(fact):
				facts.append({"event_id":message.event_id,"speaker_id":message.speaker_id,"listener_id":message.listener_id,"intent":message.intent,"subject_id":message.subject_id,"parameters":Message.canonical_values(fact),"world_timestamp":message.world_timestamp})
				while facts.size()>MAX_FACTS: facts.pop_front()
	recent.append(message.duplicate(true))
	while recent.size()>24: recent.pop_front()
	busy=false
	result.message=message
	return result

func select_autonomous(speaker: Dictionary,listener: Dictionary,context: Dictionary = {},turn: int = 0) -> Dictionary:
	var options:=Intents.clean_nodes(context.get("nodes",Intents.nodes(context)))
	var highest: float=-INF
	var selected: Dictionary={}
	for node: Dictionary in options:
		if not node.enabled: continue
		var intent: String=node.intent
		var motives: Dictionary=speaker.get("motivations",{})
		var score:=.25+float(posmod((String(speaker.get("id",""))+intent+str(turn)).hash(),100))/100.0
		if intent in ["request_trade","offer_trade","browse_goods"]: score+=float(motives.get("wealth",.5))
		if intent in ["ask_work","offer_work","offer_help"]: score+=float(motives.get("security",.5))
		if intent in ["ask_rumor","share_rumor","request_info"]: score+=float(motives.get("knowledge",.5))
		if intent=="greet": score+=float(motives.get("social",.5))
		if intent in ["threaten","hostility"] and float(speaker.get("relationships",{}).get(String(listener.get("id","")),0))>=0: score*=.15
		if intent=="share_rumor" and not node.parameters.has("fact_id"): continue
		if score>highest: highest=score; selected=node
	return selected

func serialize() -> Dictionary: return {"version":1,"namespace":channel_id,"serial":serial,"seen":seen.duplicate(),"facts":facts.duplicate(true),"recent":recent.duplicate(true)}

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=6 or input.get("version")!=1 or not Message.text(input.get("namespace"),80): return {}
	if not (input.get("serial") is float or input.get("serial") is int) or not is_finite(float(input.serial)) or input.serial<0 or input.serial>1e12 or floorf(input.serial)!=input.serial: return {}
	if not input.get("seen") is Array or input.seen.size()>MAX_SEEN or not input.get("facts") is Array or input.facts.size()>MAX_FACTS or not input.get("recent") is Array or input.recent.size()>24: return {}
	var unique: Dictionary={}
	for key: Variant in input.seen:
		if not Message.text(key,100) or unique.has(key): return {}
		unique[key]=true
	for fact: Variant in input.facts:
		if not fact is Dictionary or fact.size()!=7 or not Message.values(fact): return {}
		for key: String in ["event_id","speaker_id","listener_id","intent","subject_id"]:
			if not Message.text(fact.get(key),128,true): return {}
		if not fact.get("parameters") is Dictionary or not Intents.exists(fact.intent) or not (fact.get("world_timestamp") is float or fact.get("world_timestamp") is int) or not is_finite(float(fact.world_timestamp)) or fact.world_timestamp<0: return {}
	for message: Variant in input.recent:
		if Message.validate(message).is_empty(): return {}
	var result: Dictionary=input.duplicate(true)
	result.serial=int(result.serial)
	for fact: Dictionary in result.facts:
		fact.parameters=Message.canonical_values(fact.parameters)
		fact.world_timestamp=float(fact.world_timestamp)
	for i in range(result.recent.size()): result.recent[i]=Message.validate(result.recent[i])
	return result

func restore(input: Variant) -> bool:
	var decoded:=validate(input)
	if decoded.is_empty(): return false
	channel_id=decoded["namespace"]; serial=decoded.serial
	seen.assign(decoded.seen); facts.assign(decoded.facts); recent.assign(decoded.recent)
	return true
