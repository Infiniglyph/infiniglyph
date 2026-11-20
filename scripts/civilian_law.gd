extends Node
## Evidence and wanted cases. Criminality never decides economic XP validity.
const Instance=preload("res://scripts/item_instance.gd")
const MAX_CASES:=256
const MAX_SEEN:=2048
const CRIMES:={"assault":1,"theft":2,"stolen_trade":2,"threat":1,"criminal_contract":1}
signal case_recorded(record: Dictionary)
signal changed
var world: Node3D
var identity_provider: Callable
var cases: Dictionary={}
var sequence:=0
var seen: Dictionary={}
var _busy:=false

func transaction_active() -> bool: return _busy

func _now() -> float:
	return float(world.civilization.world_seconds) if is_instance_valid(world) and is_instance_valid(world.civilization) else 0.0

func _known(id: String) -> bool:
	if not identity_provider.is_valid(): return false
	var record: Variant=identity_provider.call(id)
	return record is Dictionary and record.get("kind") in ["player","code_form"] and record.get("active",false)

func record_crime(event: Dictionary) -> Dictionary:
	if _busy or sequence>=1000000000 or not Instance.valid_text(event.get("event_id"),false,128) or seen.has(event.event_id) or event.get("kind") not in CRIMES: return {}
	var offender:=String(event.get("offender",""))
	var victim:=String(event.get("victim",""))
	if not _known(offender) or (not victim.is_empty() and not _known(victim)) or not event.get("witnesses") is Array: return {}
	var witnesses: Array[String]=[]
	for id: Variant in event.witnesses:
		if not id is String or id==offender or not _known(id): continue
		if id not in witnesses: witnesses.append(id)
	if witnesses.is_empty() or witnesses.size()>16: return {}
	for key: String in ["asset_id","transaction_id"]:
		if not Instance.valid_text(event.get(key,""),true,128): return {}
	_busy=true
	sequence+=1
	var id:="case_"+str(sequence)
	var entry:={"id":id,"event_id":String(event.event_id),"offender":offender,"victim":victim,"kind":String(event.kind),"witnesses":witnesses,"asset_id":String(event.get("asset_id","")),"transaction_id":String(event.get("transaction_id","")),"timestamp":_now(),"status":"open","investigator":"","resolved_at":0.0}
	if cases.size()>=MAX_CASES:
		var removable:=""
		for previous: String in cases:
			if cases[previous].status=="resolved": removable=previous; break
		if removable.is_empty(): sequence-=1; _busy=false; return {}
		cases.erase(removable)
	cases[id]=entry
	seen[String(event.event_id)]=sequence
	if seen.size()>MAX_SEEN: seen.erase(seen.keys()[0])
	case_recorded.emit(entry.duplicate(true))
	changed.emit()
	_busy=false
	return entry.duplicate(true)

func wanted_level(id: String) -> int:
	var total:=0
	for entry: Dictionary in cases.values():
		if entry.offender==id and entry.status!="resolved": total+=int(CRIMES[entry.kind])
	return mini(5,total)

func open_cases() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for entry: Dictionary in cases.values():
		if entry.status!="resolved": result.append(entry.duplicate(true))
	return result

func known_cases(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for entry: Dictionary in open_cases():
		if id==entry.victim or id in entry.witnesses or id==entry.investigator: result.append(entry)
	return result

func investigate(case_id: String,investigator: String) -> bool:
	if _busy or not _known(investigator) or not cases.has(case_id) or cases[case_id].status=="resolved": return false
	if cases[case_id].offender==investigator: return false
	if cases[case_id].status=="investigating":
		if cases[case_id].investigator==investigator: return true
		if _known(String(cases[case_id].investigator)): return false
	_busy=true
	cases[case_id].status="investigating"
	cases[case_id].investigator=investigator
	changed.emit()
	_busy=false
	return true

func resolve(case_id: String,investigator: String) -> bool:
	if _busy or not cases.has(case_id) or cases[case_id].status!="investigating" or cases[case_id].investigator!=investigator or not _known(investigator): return false
	_busy=true
	cases[case_id].status="resolved"
	cases[case_id].resolved_at=_now()
	changed.emit()
	_busy=false
	return true

func serialize() -> Dictionary:
	return {"version":1,"sequence":sequence,"cases":cases.duplicate(true),"seen":seen.duplicate()}

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=4 or input.get("version")!=1 or not Instance.whole_number(input.get("sequence"),0,1000000000) or not input.get("cases") is Dictionary or input.cases.size()>MAX_CASES or not input.get("seen") is Dictionary or input.seen.size()>MAX_SEEN: return {}
	for id: Variant in input.cases:
		var entry: Variant=input.cases[id]
		if not Instance.valid_text(id,false,128) or not entry is Dictionary or entry.size()!=12 or entry.get("id")!=id or entry.get("kind") not in CRIMES or entry.get("status") not in ["open","investigating","resolved"]: return {}
		if not id.begins_with("case_") or not id.trim_prefix("case_").is_valid_int() or int(id.trim_prefix("case_"))<1 or int(id.trim_prefix("case_"))>int(input.sequence): return {}
		for key: String in ["offender","event_id"]:
			if not Instance.valid_text(entry.get(key),false,128): return {}
		for key: String in ["victim","asset_id","transaction_id","investigator"]:
			if not Instance.valid_text(entry.get(key),true,128): return {}
		for key: String in ["timestamp","resolved_at"]:
			if not (entry.get(key) is int or entry.get(key) is float) or not is_finite(float(entry[key])) or entry[key]<0 or entry[key]>1e15: return {}
		if not entry.get("witnesses") is Array or entry.witnesses.is_empty() or entry.witnesses.size()>16: return {}
		var witnesses: Dictionary={}
		for witness: Variant in entry.witnesses:
			if not Instance.valid_text(witness,false,128) or witnesses.has(witness) or witness==entry.offender: return {}
			witnesses[witness]=true
		if entry.status=="open" and not entry.investigator.is_empty(): return {}
		if entry.status!="open" and (entry.investigator.is_empty() or entry.investigator==entry.offender): return {}
		if entry.status!="resolved" and entry.resolved_at!=0 or entry.status=="resolved" and entry.resolved_at<entry.timestamp: return {}
	for key: Variant in input.seen:
		if not Instance.valid_text(key,false,128) or not Instance.whole_number(input.seen[key],1,int(input.sequence)): return {}
	return input.duplicate(true)

func restore(input: Variant) -> bool:
	if _busy: return false
	if input==null:
		_busy=true
		cases.clear(); seen.clear(); sequence=0
		changed.emit()
		_busy=false
		return true
	var clean:=validate(input)
	if clean.is_empty(): return false
	_busy=true
	cases=clean.cases
	seen=clean.seen
	sequence=int(clean.sequence)
	changed.emit()
	_busy=false
	return true
