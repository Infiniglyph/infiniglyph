extends RefCounted
## Shared host-authoritative obligations. Bodies, inventories, law and XP stay
## with their existing authorities; only committed world events advance work.
const Item=preload("res://scripts/item_instance.gd")
const MAX_INSTANCES:=1024
const MAX_OPEN:=256
const MAX_MEMBERS:=4096
const MAX_EVENTS:=64
const BLOOM_BYTES:=32768
const KINDS:=["delivery","discovery","service","recovery"]
const TERMINAL:=["completed","cancelled","failed","expired"]
var factions: Dictionary={}
var templates: Dictionary={}
var instances: Dictionary={}
var memberships: Dictionary={}
var introductions: Dictionary={}
var world_seconds:=0.0
var next_id:=1
var last_error:=""
var revision:=0
var _callbacks: Dictionary={}
var _busy:=false
var _event_bloom:=PackedByteArray()
var _event_index: Dictionary={}

func _init() -> void:
	var f: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/factions.json"))
	var q: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest_templates.json"))
	if f is Dictionary:
		for row: Dictionary in f.get("factions",[]): factions[row.id]=row
	if q is Dictionary:
		for row: Dictionary in q.get("templates",[]): templates[row.id]=row
	_event_bloom.resize(BLOOM_BYTES)
	_event_bloom.fill(0)

func configure(callbacks: Dictionary) -> void: _callbacks=callbacks

func _identity(id: String) -> bool:
	if not _callbacks.get("identity",Callable()).is_valid(): return false
	var row: Variant=_callbacks.identity.call(id)
	return row is Dictionary and row.get("active",false)==true and row.get("kind","") in ["player","code_form"]

func _authorized(operation: String,payload: Dictionary) -> bool:
	return _callbacks.get("authorize",Callable()).is_valid() and _callbacks.authorize.call(operation,payload)==true

func _finance(operation: String,row: Dictionary) -> bool:
	if not _callbacks.get("finance",Callable()).is_valid(): return false
	return _callbacks.finance.call({"operation":operation,"quest_id":row.id,"source":row.source,"beneficiary":row.participant,"amount":row.reward,"service":row.kind,"legality":row.legality})==true

func _outcome(row: Dictionary) -> void:
	if _callbacks.get("outcome",Callable()).is_valid():
		_callbacks.outcome.call({"quest_id":row.id,"status":row.status,"issuer":row.issuer,"participant":row.participant,"kind":row.kind,"legality":row.legality,"reward":row.reward})

func is_member(id: String,faction: String) -> bool: return faction in memberships.get(id,[])

func join(id: String,faction: String) -> bool:
	if _busy or not _identity(id) or not factions.has(faction): return false
	if not factions[faction].public and not introductions.has(id): return false
	if is_member(id,faction): return true
	if not memberships.has(id):
		if memberships.size()>=MAX_MEMBERS: return false
		memberships[id]=[]
	memberships[id].append(faction)
	revision+=1
	return true

func introduce(id: String,contact_id: String) -> bool:
	if _busy or not _identity(id) or not _identity(contact_id) or introductions.size()>=MAX_MEMBERS: return false
	if not _authorized("introduce",{"participant":id,"contact_id":contact_id}): return false
	introductions[id]=contact_id
	revision+=1
	return true

func available(id: String,faction: String="",public_only: bool=false) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for row: Dictionary in instances.values():
		if row.status!="available" or (not faction.is_empty() and row.faction!=faction): continue
		if not row.faction.is_empty() and not factions[row.faction].public:
			if public_only or not introductions.has(id): continue
		if not row.eligible.is_empty() and not id in row.eligible: continue
		result.append(row.duplicate(true))
	return result

func for_participant(id: String,include_history: bool=true) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for row: Dictionary in instances.values():
		if row.participant==id and (include_history or not row.status in TERMINAL): result.append(row.duplicate(true))
	return result

func _prune() -> void:
	if instances.size()<MAX_INSTANCES: return
	for id: String in instances.keys():
		if instances[id].status in TERMINAL:
			instances.erase(id)
			if instances.size()<MAX_INSTANCES: return

func create_contract(template_id: String,issuer: String,source: String,terms: Dictionary,now: float) -> String:
	last_error=""
	if _busy or not templates.has(template_id) or not _finite(now) or now<world_seconds or not _text(source): return ""
	var definition: Dictionary=templates[template_id]
	if not (_identity(issuer) or issuer=="faction/"+String(definition.faction)): return ""
	if _identity(issuer) and not String(definition.faction).is_empty() and not is_member(issuer,definition.faction): return ""
	if not _authorized("publish",{"template_id":template_id,"issuer":issuer,"source":source,"terms":terms}): return ""
	if not _valid_terms(terms,definition.kind): return ""
	var open:=0
	for row: Dictionary in instances.values():
		if not row.status in TERMINAL: open+=1
	if open>=MAX_OPEN: last_error="The bounded contract board is full."; return ""
	_prune()
	if instances.size()>=MAX_INSTANCES: return ""
	var need: String=terms.get("need_id","")
	if not need.is_empty():
		for prior: Dictionary in instances.values():
			if prior.issuer==issuer and prior.need_id==need: return ""
	var reward: int=int(terms.get("reward",definition.reward))
	var ttl: float=float(terms.get("ttl",definition.ttl))
	var objective: Dictionary={"target_id":String(terms.get("target_id","")),"item_type":String(terms.get("item_type","")),"recipient_id":String(terms.get("recipient_id","")),"service":String(terms.get("service","")),"count":int(terms.get("count",1)),"progress":0}
	var id: String="quest_"+str(next_id)
	var row: Dictionary={"id":id,"template":template_id,"title":definition.title,"kind":definition.kind,"faction":definition.faction,"issuer":issuer,"source":source,"reward":reward,"legality":definition.legality,"eligible":terms.get("eligible",[]).duplicate(),"participant":"","status":"available","closing_as":"","created_at":now,"accepted_at":0.0,"expires_at":now+ttl,"completed_at":0.0,"objective":objective,"events":[],"need_id":need}
	_busy=true
	var funded:=_finance("reserve",row)
	if funded:
		instances[id]=row; next_id+=1; world_seconds=now
		revision+=1
	_busy=false
	if not funded: last_error="The issuer cannot fund this contract."
	return id if funded else ""

func request_work(issuer: String,template_id: String,source: String,terms: Dictionary,now: float) -> String:
	if not _identity(issuer) or not _text(terms.get("need_id","")) or not _authorized("delegate",{"issuer":issuer,"template_id":template_id,"source":source,"terms":terms}): return ""
	return create_contract(template_id,issuer,source,terms,now)

func accept(quest_id: String,id: String,now: float) -> bool:
	if _busy or not _identity(id) or not instances.has(quest_id) or not _finite(now) or now<world_seconds: return false
	var row: Dictionary=instances[quest_id]
	if row.status!="available" or now>=row.expires_at or row.issuer==id: return false
	if row.kind=="delivery" and row.objective.recipient_id==id: return false
	if not row.faction.is_empty() and not is_member(id,row.faction): return false
	if not row.eligible.is_empty() and not id in row.eligible: return false
	var count:=0
	for prior: Dictionary in instances.values():
		if prior.participant==id and prior.status in ["active","ready"]: count+=1
	if count>=3: return false
	row.status="active"; row.participant=id; row.accepted_at=now; world_seconds=now
	revision+=1
	_reindex()
	return true

func _reindex() -> void:
	_event_index.clear()
	for row: Dictionary in instances.values():
		if row.status!="active": continue
		if not _event_index.has(row.kind): _event_index[row.kind]=[]
		_event_index[row.kind].append(row.id)

func _bits(id: String) -> Array[int]:
	return [posmod(id.hash(),BLOOM_BYTES*8),posmod(("event/"+id).hash(),BLOOM_BYTES*8),posmod((id+"/quest").hash(),BLOOM_BYTES*8)]

func _seen(id: String) -> bool:
	for bit: int in _bits(id):
		if (_event_bloom[bit>>3] & (1<<(bit%8)))==0: return false
	return true

func _mark(id: String) -> void:
	for bit: int in _bits(id): _event_bloom[bit>>3]|=1<<(bit%8)

func consume_event(event: Dictionary) -> Array[String]:
	var changed: Array[String]=[]
	if _busy or not _valid_event(event) or _seen(event.event_id): return changed
	# Verification is separate from the input event: no caller can complete a
	# delivery by asking a dialogue/UI endpoint to emit an uncommitted receipt.
	if not _authorized("event",event): return changed
	if float(event.timestamp)>world_seconds: advance_to(float(event.timestamp))
	for id: String in _event_index.get(event.event_type,[]).duplicate():
		var row: Dictionary=instances[id]
		if not _issuer_live(row.issuer): _close(row,"failed"); continue
		if event.actor_id!=row.participant or event.timestamp<row.accepted_at or event.timestamp>=row.expires_at or not _identity(row.participant): continue
		var objective: Dictionary=row.objective
		var matches:=true
		for key: String in ["target_id","item_type","recipient_id","service"]:
			if not String(objective[key]).is_empty() and objective[key]!=event.get(key,""): matches=false
		if not matches: continue
		# Save the replay guard before any settlement callback can notify listeners.
		if changed.is_empty(): _mark(event.event_id)
		objective.progress=mini(objective.count,int(objective.progress)+int(event.get("quantity",1)))
		row.events.append(String(event.event_id)); changed.append(id)
		revision+=1
		if objective.progress>=objective.count:
			row.status="ready"
			_finish(row)
	_reindex()
	return changed

func _finish(row: Dictionary) -> bool:
	if row.status!="ready": return false
	_busy=true
	var paid:=_finance("pay",row)
	if paid:
		row.status="completed"; row.completed_at=world_seconds
		revision+=1
		_outcome(row)
	_busy=false
	return paid

func _close(row: Dictionary,status: String) -> bool:
	if row.status in TERMINAL: return false
	_busy=true
	var refunded:=_finance("refund",row)
	row.status=status if refunded else "closing"
	row.closing_as="" if refunded else status
	revision+=1
	if refunded: row.completed_at=world_seconds; _outcome(row)
	_busy=false
	_reindex()
	return refunded

func cancel(id: String,actor: String) -> bool:
	if _busy or not instances.has(id): return false
	var row: Dictionary=instances[id]
	return _close(row,"cancelled") if actor in [row.issuer,row.participant] else false

func fail(id: String,reason: String="") -> bool:
	if _busy or not instances.has(id) or not _authorized("fail",{"quest_id":id,"reason":reason}): return false
	return _close(instances[id],"failed")

func advance_to(now: float) -> bool:
	if _busy or not _finite(now) or now<world_seconds: return false
	world_seconds=now
	for row: Dictionary in instances.values():
		if row.status in TERMINAL: continue
		if not _issuer_live(row.issuer) or (not String(row.participant).is_empty() and not _identity(row.participant)): _close(row,"failed")
		elif row.status=="closing": _close(row,row.closing_as)
		elif row.status in ["active","available"] and now>=row.expires_at: _close(row,"expired")
		elif row.status=="ready": _finish(row)
	return true

func retire(id: String) -> void:
	if _busy: return
	memberships.erase(id); introductions.erase(id)
	revision+=1
	for row: Dictionary in instances.values():
		if not row.status in TERMINAL and id in [row.issuer,row.participant]: _close(row,"failed")

func obligations() -> Dictionary:
	var result: Dictionary={}
	for row: Dictionary in instances.values():
		if not row.status in TERMINAL: result[row.id]={"source":row.source,"amount":row.reward}
	return result

func transaction_active() -> bool: return _busy

func _issuer_live(id: String) -> bool:
	return factions.has(id.trim_prefix("faction/")) if id.begins_with("faction/") else _identity(id)

func serialize() -> Dictionary:
	return {"version":1,"world_seconds":world_seconds,"next_id":next_id,"memberships":memberships.duplicate(true),"introductions":introductions.duplicate(),"instances":instances.duplicate(true),"event_bloom":_event_bloom.hex_encode()}

func restore(data: Variant) -> bool:
	if _busy: return false
	if data==null:
		instances.clear(); memberships.clear(); introductions.clear(); _event_index.clear()
		world_seconds=0.0; next_id=1; _event_bloom.fill(0); revision+=1
		return true
	var decoded:=validate(data)
	if decoded.is_empty(): return false
	world_seconds=decoded.world_seconds; next_id=decoded.next_id
	memberships=decoded.memberships; introductions=decoded.introductions; instances=decoded.instances
	_event_bloom=String(decoded.event_bloom).hex_decode()
	revision+=1
	_reindex()
	return true

static func _finite(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=9e12
static func _text(value: Variant,empty: bool=false) -> bool: return Item.valid_text(value,empty,128) and not "\n" in String(value) and not "\r" in String(value)

static func _valid_terms(terms: Dictionary,kind: String) -> bool:
	for key: Variant in terms:
		if not key in ["target_id","item_type","recipient_id","service","count","eligible","reward","ttl","need_id"]: return false
	for key: String in ["target_id","item_type","recipient_id","service","need_id"]:
		if not _text(terms.get(key,""),true): return false
	if not Item.whole_number(terms.get("count",1),1,MAX_EVENTS) or not Item.whole_number(terms.get("reward",1),1,100000): return false
	if not _finite(terms.get("ttl",86400)) or float(terms.get("ttl",86400))<1 or float(terms.get("ttl",86400))>86400*365: return false
	if not terms.get("eligible",[]) is Array or terms.get("eligible",[]).size()>32: return false
	var eligible_seen: Dictionary={}
	for id: Variant in terms.get("eligible",[]):
		if not _text(id) or eligible_seen.has(id): return false
		eligible_seen[id]=true
	match kind:
		"delivery": return _text(terms.get("item_type")) and _text(terms.get("recipient_id"))
		"discovery": return _text(terms.get("target_id"))
		"service": return _text(terms.get("service")) and _text(terms.get("target_id"))
		"recovery": return _text(terms.get("item_type")) and _text(terms.get("target_id"))
	return false

static func _valid_event(event: Dictionary) -> bool:
	if not _text(event.get("event_id")) or not event.get("event_type","") in KINDS or not _text(event.get("actor_id")) or not _finite(event.get("timestamp")): return false
	if not Item.whole_number(event.get("quantity",1),1,100000): return false
	for key: String in ["target_id","item_type","recipient_id","service"]:
		if not _text(event.get(key,""),true): return false
	return true

static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size()!=7 or not Item.whole_number(data.get("version"),1,1) or not _finite(data.get("world_seconds")) or not Item.whole_number(data.get("next_id"),1,9007199254740991): return {}
	if not data.get("memberships") is Dictionary or data.memberships.size()>MAX_MEMBERS or not data.get("introductions") is Dictionary or data.introductions.size()>MAX_MEMBERS or not data.get("instances") is Dictionary or data.instances.size()>MAX_INSTANCES: return {}
	if not data.get("event_bloom") is String or data.event_bloom.length()!=BLOOM_BYTES*2 or data.event_bloom.hex_decode().hex_encode()!=data.event_bloom: return {}
	var model=load("res://scripts/universal_quests.gd").new()
	var memberships_copy: Dictionary={}
	for id: Variant in data.memberships:
		var joined: Variant=data.memberships[id]
		if not _text(id) or not joined is Array or joined.size()>model.factions.size(): return {}
		var seen: Dictionary={}
		for faction: Variant in joined:
			if not faction is String or not model.factions.has(faction) or seen.has(faction): return {}
			seen[faction]=true
		memberships_copy[String(id)]=joined.duplicate()
	for id: Variant in data.introductions:
		if not _text(id) or not _text(data.introductions[id]): return {}
	for id: String in memberships_copy:
		for faction: String in memberships_copy[id]:
			if not model.factions[faction].public and not data.introductions.has(id): return {}
	var rows: Dictionary={}
	var open:=0
	var highest:=0
	for id: Variant in data.instances:
		var row: Variant=data.instances[id]
		if not _text(id) or not String(id).begins_with("quest_") or not String(id).trim_prefix("quest_").is_valid_int() or not row is Dictionary or row.size()!=20 or row.get("id")!=id or not model.templates.has(row.get("template","")): return {}
		var serial: int=int(String(id).trim_prefix("quest_"))
		if serial<1 or String(id)!="quest_"+str(serial): return {}
		highest=maxi(highest,serial)
		var definition: Dictionary=model.templates[row.template]
		for key: String in ["title","kind","faction","legality"]:
			if row.get(key)!=definition[key]: return {}
		if not _text(row.get("issuer")) or not _text(row.get("source")) or not _text(row.get("participant"),true) or not _text(row.get("need_id"),true) or not Item.whole_number(row.get("reward"),1,100000): return {}
		if not row.get("status","") in TERMINAL+["available","active","ready","closing"]: return {}
		if row.status=="closing" and not row.get("closing_as","") in ["cancelled","failed","expired"]: return {}
		if row.status!="closing" and row.get("closing_as")!="": return {}
		if row.status=="available" and row.participant!="": return {}
		if row.status in ["active","ready","completed"] and row.participant=="": return {}
		if not String(row.participant).is_empty() and row.participant==row.issuer: return {}
		for key: String in ["created_at","accepted_at","expires_at","completed_at"]:
			if not _finite(row.get(key)): return {}
		if row.created_at>row.expires_at or row.created_at>data.world_seconds or (row.accepted_at>0 and (row.accepted_at<row.created_at or row.accepted_at>data.world_seconds)): return {}
		if row.status in ["active","ready","completed"] and (row.accepted_at<row.created_at or row.accepted_at>data.world_seconds): return {}
		if row.status in TERMINAL and (row.completed_at<row.created_at or row.completed_at>data.world_seconds): return {}
		if row.status=="expired" and row.completed_at<row.expires_at: return {}
		if not row.get("events") is Array or row.events.size()>MAX_EVENTS or not row.get("objective") is Dictionary or row.objective.size()!=6: return {}
		var seen_events: Dictionary={}
		for event: Variant in row.events:
			if not _text(event) or seen_events.has(event): return {}
			seen_events[event]=true
		var objective: Dictionary=row.objective
		var terms: Dictionary=objective.duplicate(); terms.erase("progress"); terms.reward=row.reward; terms.ttl=float(row.expires_at)-float(row.created_at); terms.eligible=row.get("eligible")
		if not _valid_terms(terms,row.kind) or not Item.whole_number(objective.get("progress"),0,int(objective.count)): return {}
		if row.status in ["ready","completed"] and objective.progress!=objective.count: return {}
		if row.status=="active" and objective.progress>=objective.count: return {}
		if objective.progress<row.events.size() or (objective.progress>0 and row.events.is_empty()): return {}
		if row.kind=="delivery" and not String(row.participant).is_empty() and objective.recipient_id==row.participant: return {}
		if row.status=="available" and (objective.progress!=0 or not row.events.is_empty()): return {}
		if not row.status in TERMINAL: open+=1
		rows[String(id)]=Item.json_copy(row)
	if open>MAX_OPEN or highest>=int(data.next_id): return {}
	return {"version":1,"world_seconds":float(data.world_seconds),"next_id":int(data.next_id),"memberships":memberships_copy,"introductions":data.introductions.duplicate(),"instances":rows,"event_bloom":data.event_bloom}
