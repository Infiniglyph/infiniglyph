extends RefCounted
## Canonical, bounded value messages. Subtitle strings never drive authority.
const Intents = preload("res://scripts/universal_intent.gd")
const FIELDS := ["message_id","event_id","speaker_id","listener_id","intent","subject_id","parameters","emotion","conversation_id","world_timestamp"]

static func text(value: Variant,limit: int = 96,empty: bool = false) -> bool:
	if not value is String or value.length()>limit or not empty and value.is_empty(): return false
	for i in range(value.length()):
		if value.unicode_at(i)<32 or value.unicode_at(i)==127: return false
	return true

static func values(value: Variant,depth: int = 0) -> bool:
	if depth>5: return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_INT: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING: return value.length()<=512
		TYPE_ARRAY:
			if value.size()>24: return false
			for child: Variant in value:
				if not values(child,depth+1): return false
			return true
		TYPE_DICTIONARY:
			if value.size()>24: return false
			for key: Variant in value:
				if not text(key,64) or not values(value[key],depth+1): return false
			return true
	return false

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=FIELDS.size(): return {}
	for key: String in FIELDS:
		if not input.has(key): return {}
	for key: String in ["message_id","event_id","speaker_id","listener_id","conversation_id"]:
		if not text(input[key]): return {}
	if input.speaker_id==input.listener_id or not text(input.subject_id,128,true): return {}
	if not text(input.intent,40) or not Intents.exists(input.intent) or not text(input.emotion,24) or not input.emotion in Intents.EMOTIONS: return {}
	if not input.parameters is Dictionary or not values(input.parameters): return {}
	if not (input.world_timestamp is float or input.world_timestamp is int) or not is_finite(float(input.world_timestamp)) or input.world_timestamp<0 or input.world_timestamp>1e15: return {}
	var price: Variant=null
	for key: String in ["price","offered_price","asking_price"]:
		if not input.parameters.has(key): continue
		var amount: Variant=input.parameters[key]
		if not (amount is int or amount is float) or not is_finite(float(amount)) or amount<0 or amount>1000000000 or float(amount)!=floorf(float(amount)): return {}
		if price!=null and price!=amount: return {}
		price=amount
	if Intents.DEFINITIONS[input.intent].get("priced",false) and (price==null or input.subject_id.is_empty() and not input.parameters.has("item") and not input.parameters.has("item_name")): return {}
	var result: Dictionary=input.duplicate(true)
	result.parameters=canonical_values(input.parameters)
	result.world_timestamp=float(input.world_timestamp)
	return result

static func canonical_values(value: Variant) -> Variant:
	if value is float and value==floorf(value) and absf(value)<=1e12: return int(value)
	if value is Array:
		var array: Array=[]
		for child: Variant in value: array.append(canonical_values(child))
		return array
	if value is Dictionary:
		var result: Dictionary={}
		for key: String in value: result[key]=canonical_values(value[key])
		return result
	return value
