extends SceneTree
const Model=preload("res://scripts/universal_quests.gd")
const Runtime=preload("res://scripts/quest_system.gd")
var checks:=0
var failures:=0
var model: RefCounted
var identities: Dictionary={"human":{"active":true,"kind":"player"},"worker":{"active":true,"kind":"code_form"},"merchant":{"active":true,"kind":"code_form"},"contact":{"active":true,"kind":"code_form"},"boss":{"active":true,"kind":"boss"}}
var balances: Dictionary={"faction:security":1000,"faction:commerce":1000,"faction:exploration":1000,"faction:underworld":1000,"resident:merchant":100,"human":0,"worker":0}
var escrow: Dictionary={}
var committed: Dictionary={}
var authorized_needs: Dictionary={}
var outcomes: Array=[]
var reject_pay:=false
var reject_refund:=false

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func configure(target: RefCounted) -> void:
	target.configure({"identity":func(id: String): return identities.get(id,{}),"authorize":authorize,"finance":finance,"outcome":func(row: Dictionary): outcomes.append(row)})
func authorize(operation: String,payload: Dictionary) -> bool:
	match operation:
		"introduce": return payload.contact_id=="contact"
		"publish": return payload.source=="faction:"+String(model.templates[payload.template_id].faction) or payload.source=="resident:"+payload.issuer
		"delegate": return authorized_needs.has(payload.terms.get("need_id","")) and payload.source=="resident:"+payload.issuer
		"event": return committed.get(payload.event_id,{})==payload
		"fail": return payload.reason=="verified loss"
	return false
func finance(request: Dictionary) -> bool:
	var id: String=request.quest_id
	match request.operation:
		"reserve":
			if escrow.has(id) or balances.get(request.source,0)<request.amount: return false
			balances[request.source]-=request.amount
			escrow[id]={"source":request.source,"amount":request.amount,"status":"open"}
			return true
		"pay":
			if reject_pay or not escrow.has(id) or not identities.get(request.beneficiary,{}).get("active",false): return false
			if escrow[id].status=="paid": return true
			if escrow[id].status!="open": return false
			balances[request.beneficiary]=balances.get(request.beneficiary,0)+escrow[id].amount
			escrow[id].status="paid"
			return true
		"refund":
			if reject_refund or not escrow.has(id): return false
			if escrow[id].status=="refunded": return true
			if escrow[id].status!="open": return false
			balances[escrow[id].source]+=escrow[id].amount; escrow[id].status="refunded"
			return true
	return false
func event(kind: String,actor: String,target: String,extra: Dictionary={}) -> Dictionary:
	var result: Dictionary={"event_id":"receipt_"+str(committed.size()),"event_type":kind,"actor_id":actor,"target_id":target,"timestamp":model.world_seconds}
	result.merge(extra,true); committed[result.event_id]=result.duplicate(true)
	return result
func create(template: String,terms: Dictionary={}) -> String:
	var faction: String=model.templates[template].faction
	return model.create_contract(template,"faction/"+faction,"faction:"+faction,terms,model.world_seconds)
func run() -> void:
	model=Model.new(); configure(model)
	check(model.factions.size()==4 and model.templates.size()==9,"Faction resources and separate reusable quest templates load")
	check(not model.join("boss","security") and not model.join("unknown","commerce"),"Only registered players and living civilian Code Forms can join")
	var q:=create("exploration_discovery",{"target_id":"city/market"})
	check(not q.is_empty() and balances["faction:exploration"]==990 and escrow[q].status=="open","Publishing reserves a finite reward from its actual treasury")
	check(model.available("human","exploration",true).size()==1 and not model.accept(q,"human",0),"Public boards are readable before membership while acceptance checks membership")
	check(model.join("human","exploration") and model.join("human","security") and model.is_member("human","exploration") and model.is_member("human","security"),"A participant retains simultaneous independent public memberships")
	check(model.accept(q,"human",0) and not model.accept(q,"worker",0),"Exactly one eligible participant owns an accepted assignment")
	check(model.consume_event({"event_id":"forged","event_type":"discovery","actor_id":"human","target_id":"city/market","timestamp":0}).is_empty(),"Unverified UI/dialogue declarations never advance a quest")
	var receipt:=event("discovery","human","city/market")
	check(model.consume_event(receipt)==[q] and model.instances[q].status=="completed" and balances.human==10,"A real discovery completes and pays the player through the same engine")
	check(model.consume_event(receipt).is_empty() and balances.human==10 and outcomes.size()==1,"A repeated committed event cannot progress or pay twice")
	check(outcomes[0].participant=="human" and not outcomes[0].has("xp"),"Quest outcomes never grant player Code Form XP")
	var private_job:=create("underworld_delivery",{"item_type":"light_shard","recipient_id":"merchant"})
	check(not model.join("human","underworld") and model.available("human","underworld",true).is_empty() and model.available("human","underworld").is_empty(),"Private contracts stay off public boards and inaccessible without introduction")
	check(not model.introduce("human","merchant") and model.introduce("human","contact") and model.join("human","underworld"),"A verified friendly contact grants persistent private faction access")
	check(model.available("human","underworld").size()==1 and model.available("human","underworld",true).is_empty() and model.accept(private_job,"human",0),"Private members can accept genuine criminal work without publishing it publicly")
	model.consume_event(event("delivery","human","",{"item_type":"wrong","recipient_id":"merchant"}))
	check(model.instances[private_job].status=="active","Delivery objectives require the actual requested goods and recipient")
	model.consume_event(event("delivery","human","",{"item_type":"light_shard","recipient_id":"merchant"}))
	check(model.instances[private_job].status=="completed" and outcomes.back().legality=="illegal" and balances.human==24,"Criminal completion pays real coins and keeps legality separate from rewards")
	check(model.join("worker","commerce"),"A civilian uses the identical persistent membership authority")
	var service:=create("commerce_service",{"target_id":"tavern","service":"supply_work","count":2})
	check(model.accept(service,"worker",0),"A civilian accepts the same shared contract instance type")
	model.consume_event(event("service","worker","tavern",{"service":"supply_work"}))
	check(model.instances[service].objective.progress==1 and model.instances[service].status=="active","Counted objectives advance only from matching committed work")
	reject_pay=true
	model.consume_event(event("service","worker","tavern",{"service":"supply_work"}))
	check(model.instances[service].status=="ready" and balances.worker==0,"Failed settlement retains a funded ready obligation without fake completion")
	var saved: Dictionary=model.serialize()
	var restored:=Model.new(); configure(restored)
	check(not Model.validate(saved).is_empty() and restored.restore(JSON.parse_string(JSON.stringify(saved))),"Active membership, events and funded completion survive strict JSON round trip")
	model=restored
	reject_pay=false; model.advance_to(1)
	check(model.instances[service].status=="completed" and balances.worker==8,"A reloaded pending settlement retries exactly once")
	model.advance_to(2)
	check(balances.worker==8,"Clock catch-up cannot duplicate a completed reward")
	var old_replay:=receipt.duplicate(true)
	check(model.consume_event(old_replay).is_empty(),"Stable event deduplication survives save/load and history changes")
	var before: Dictionary=model.serialize()
	var corrupt:=before.duplicate(true); corrupt.instances[service].objective.progress=900
	check(not model.restore(corrupt) and model.serialize()==before,"Malformed objective state fails atomically without disturbing live work")
	var expire:=create("commerce_delivery",{"item_type":"light_shard","recipient_id":"merchant","ttl":2})
	var treasury_before: int=balances["faction:commerce"]
	model.advance_to(5)
	check(model.instances[expire].status=="expired" and balances["faction:commerce"]==treasury_before+10,"Offline expiration refunds the reserved issuer funds")
	model.advance_to(6)
	check(balances["faction:commerce"]==treasury_before+10,"Repeated offline catch-up cannot repeat a refund")
	var cancelled:=create("security_recovery",{"item_type":"katana","target_id":"lost/123"})
	check(not model.cancel(cancelled,"worker") and model.cancel(cancelled,"faction/security"),"Only the issuer or assigned worker may cancel work")
	var failed:=create("security_recovery",{"item_type":"katana","target_id":"lost/456"})
	check(not model.fail(failed,"just dialogue") and model.fail(failed,"verified loss"),"Failure requires a host-verified condition and refunds escrow")
	var retirement:=create("commerce_service",{"target_id":"guild","service":"work"})
	model.accept(retirement,"worker",6); identities.worker.active=false; model.retire("worker")
	check(model.instances[retirement].status=="failed" and not model.memberships.has("worker") and not model.accept(retirement,"worker",6),"Retired identities fail/refund work and pass no membership or job to replacements")
	var need_terms: Dictionary={"need_id":"supplies/day1","item_type":"light_shard","recipient_id":"merchant"}
	check(model.request_work("merchant","personal_delivery","resident:merchant",need_terms,6).is_empty(),"A fabricated autonomous need cannot create a delegated reward")
	authorized_needs[need_terms.need_id]=true
	var delegated: String=model.request_work("merchant","personal_delivery","resident:merchant",need_terms,6)
	check(not delegated.is_empty() and balances["resident:merchant"]==94 and model.request_work("merchant","personal_delivery","resident:merchant",need_terms,6).is_empty(),"A verified Code Form need funds one generic delegated obligation from its own wallet")
	check(model.accept(delegated,"human",6),"Personal favors share the engine without unrelated faction restrictions")
	model.consume_event(event("delivery","human","",{"item_type":"light_shard","recipient_id":"merchant"}))
	check(model.instances[delegated].status=="completed" and balances.human==30,"The same real delivery event system resolves delegated work and pays once")
	var empty_treasury: int=balances["faction:security"]; balances["faction:security"]=0
	check(create("security_service",{"target_id":"street","service":"patrol"}).is_empty(),"A depleted faction cannot create unfunded reward promises")
	balances["faction:security"]=empty_treasury
	var retry_refund:=create("security_service",{"target_id":"city/watch","service":"patrol"})
	reject_refund=true
	check(not model.cancel(retry_refund,"faction/security") and model.instances[retry_refund].status=="closing" and model.obligations().has(retry_refund),"A rejected refund keeps its durable escrow obligation instead of losing coins")
	var pending:=Model.new(); configure(pending)
	check(pending.restore(JSON.parse_string(JSON.stringify(model.serialize()))),"A pending cancellation survives strict persistence")
	model=pending; reject_refund=false; model.advance_to(7)
	check(model.instances[retry_refund].status=="cancelled" and escrow[retry_refund].status=="refunded","Reloaded cancellation retries the refund and closes once")
	var combined_a:=create("exploration_discovery",{"target_id":"city/docks"})
	var combined_b:=create("exploration_discovery",{"target_id":"city/docks"})
	check(model.accept(combined_a,"human",7) and model.accept(combined_b,"human",7),"Independent contracts may request the same real observation")
	var combined_event:=event("discovery","human","city/docks")
	check(model.consume_event(combined_event).size()==2 and model.instances[combined_a].status=="completed" and model.instances[combined_b].status=="completed","One genuine event independently validates each applicable funded contract")
	var timed:=create("security_service",{"target_id":"street","service":"patrol","ttl":1})
	model.join("human","security"); model.accept(timed,"human",7)
	model.advance_to(9)
	check(model.consume_event(event("service","human","street",{"service":"patrol"})).is_empty() and model.instances[timed].status=="expired","A late real event cannot resurrect expired work or collect its refunded reward")
	var strict: Dictionary=model.serialize()
	var malformed: Dictionary=strict.duplicate(true); malformed.memberships.human.append("invented")
	check(Model.validate(malformed).is_empty(),"Persistence rejects unknown faction memberships")
	malformed=strict.duplicate(true); malformed.introductions.clear()
	check(Model.validate(malformed).is_empty(),"Private memberships require their persisted introduction provenance")
	malformed=strict.duplicate(true); malformed.instances[combined_a].events.clear()
	check(Model.validate(malformed).is_empty(),"Completed objective progress requires retained event references")
	var runtime:=Runtime.new(); root.add_child(runtime); runtime.model=model
	check(runtime.board("underworld","human").is_empty() and not runtime.board("security","human").is_empty(),"The runtime exposes public board context without leaking private contracts")
	check(not paused and model.obligations().is_empty(),"Settled work leaves no outstanding obligations and never pauses simulation")
	runtime.free()
	print("Universal quests: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
