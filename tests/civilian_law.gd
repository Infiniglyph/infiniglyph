extends SceneTree
const Law=preload("res://scripts/civilian_law.gd")
var checks:=0
var failures:=0
var identities: Dictionary={"player":{"kind":"player","active":true},"a":{"kind":"code_form","active":true},"b":{"kind":"code_form","active":true},"guard":{"kind":"code_form","active":true},"boss":{"kind":"boss","active":true},"monster":{"kind":"monster","active":true}}
var nested:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func crime(event_id: String,offender: String="a",witnesses: Array=["b"]) -> Dictionary:
	return {"event_id":event_id,"kind":"theft","offender":offender,"victim":"b","witnesses":witnesses,"asset_id":"real_owned_item","transaction_id":"human:commerce:1"}
func run() -> void:
	var law:=Law.new(); root.add_child(law); law.identity_provider=func(id: String): return identities.get(id,{})
	check(law.record_crime(crime("unseen","a",[])).is_empty() and law.wanted_level("a")==0,"An unobserved alleged crime creates no evidence or wanted status")
	check(law.record_crime(crime("own","a",["a","unknown","boss"])).is_empty(),"An offender, unknown identity or boss cannot supply civilian witness evidence")
	check(law.record_crime(crime("boss","boss")).is_empty() and law.record_crime(crime("monster","monster")).is_empty(),"Bosses and monsters never become civilian legal offenders")
	law.case_recorded.connect(func(_entry: Dictionary): nested=nested or not law.record_crime(crime("nested")).is_empty())
	var record: Dictionary=law.record_crime(crime("witnessed"))
	check(not record.is_empty() and law.wanted_level("a")==2 and record.asset_id=="real_owned_item" and record.transaction_id=="human:commerce:1","Actual witness evidence preserves the owned asset and transaction provenance independently")
	var sequence: int=law.sequence
	check(law.record_crime(crime("witnessed")).is_empty() and law.sequence==sequence and law.wanted_level("a")==2 and not nested,"Duplicate or reentrant crime submissions cannot compound wanted status")
	check(not law.record_crime(crime("human","player")).is_empty() and law.wanted_level("player")==2,"The same evidence rules apply to the human outsider")
	check(law.known_cases("b").size()==2 and law.known_cases("guard").is_empty(),"Case knowledge follows witnesses and victims rather than global omniscience")
	check(not law.investigate(record.id,"a") and not law.investigate(record.id,"boss") and not law.resolve(record.id,"guard"),"An offender or excluded entity cannot investigate, and an uninvestigated case cannot resolve")
	var guard_state:={"busy":true,"reentered":false}
	law.changed.connect(func():
		guard_state.busy=guard_state.busy and law._busy
		guard_state.reentered=guard_state.reentered or law.investigate(record.id,"b"))
	check(law.investigate(record.id,"guard") and not law.investigate(record.id,"b") and not law.resolve(record.id,"b") and law.resolve(record.id,"guard"),"Only the assigned known investigator can resolve an investigated case")
	check(guard_state.busy and not guard_state.reentered,"Investigation and resolution callbacks cannot reenter or replace an assigned investigator")
	check(law.wanted_level("a")==0 and law.known_cases("b").size()==1 and not law.resolve(record.id,"guard"),"Resolution clears that open evidence exactly once without deleting its history")
	identities.a.active=false
	var saved: Dictionary=law.serialize()
	var restored:=Law.new(); root.add_child(restored); restored.identity_provider=law.identity_provider
	check(restored.restore(JSON.parse_string(JSON.stringify(saved))) and restored.cases[record.id].offender=="a" and restored.cases[record.id].status=="resolved","Historical cases survive JSON reload after their original civilian retires")
	check(restored.record_crime(crime("dead")).is_empty(),"A retired historical identity cannot originate a new active crime")
	identities.a.active=true
	var handoff: Dictionary=law.record_crime(crime("handoff"))
	law.investigate(handoff.id,"guard")
	identities.guard.active=false
	check(not law.resolve(handoff.id,"guard") and law.investigate(handoff.id,"b"),"A retired investigator's real unfinished case permits an active replacement investigator")
	identities.guard.active=true
	check(not law.resolve(handoff.id,"guard") and law.resolve(handoff.id,"b"),"Reassignment transfers investigation authority without allowing the previous investigator to resolve it")
	var bad:=saved.duplicate(true); bad.cases[record.id].witnesses=["a"]
	check(Law.validate(bad).is_empty(),"Strict restore rejects self-witnessed evidence")
	bad=saved.duplicate(true); bad.cases[record.id].resolved_at=-1
	check(Law.validate(bad).is_empty(),"Strict restore rejects impossible investigation chronology")
	var bounded:=true
	for i in range(Law.MAX_SEEN+2):
		var entry: Dictionary=restored.record_crime(crime("history/"+str(i)))
		if entry.is_empty() or not restored.investigate(entry.id,"guard") or not restored.resolve(entry.id,"guard"): bounded=false; break
	check(bounded and restored.cases.size()<=Law.MAX_CASES and restored.seen.size()<=Law.MAX_SEEN,"Resolved evidence and replay working sets remain bounded across thousands of cases")
	check(not Law.validate(JSON.parse_string(JSON.stringify(restored.serialize()))).is_empty(),"A full bounded evidence history remains valid after JSON persistence")
	var full:=Law.new(); root.add_child(full); full.identity_provider=law.identity_provider
	var open_full:=true
	for i in range(Law.MAX_CASES): open_full=open_full and not full.record_crime(crime("open/"+str(i))).is_empty()
	sequence=full.sequence
	check(open_full and full.record_crime(crime("overflow")).is_empty() and full.sequence==sequence and full.cases.size()==Law.MAX_CASES,"A full open case ledger rejects overflow without losing evidence or sequence integrity")
	check(full.wanted_level("a")==5 and full.wanted_level("monster")==0,"Wanted pressure is capped and excluded combat entities remain unaffected")
	print("CIVILIAN LAW: ",checks," checks, ",failures," failures")
	full.free(); restored.free(); law.free(); quit(0 if failures==0 else 1)
