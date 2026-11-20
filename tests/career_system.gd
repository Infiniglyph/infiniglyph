extends SceneTree
const Careers=preload("res://scripts/career_registry.gd")
const Runtime=preload("res://scripts/career_system.gd")
const Quests=preload("res://scripts/universal_quests.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
var checks:=0
var failures:=0
var people: Dictionary={"worker":{"kind":"code_form","active":true,"level":8,"experience":44,"expires_at":123456,"motivations":{"wealth":.9,"risk":.8}},"owner":{"kind":"code_form","active":true},"other":{"kind":"code_form","active":true},"player":{"kind":"player","active":true},"avat_ar":{"kind":"unique","active":true},"boss":{"kind":"boss","active":true}}
var premises: Dictionary={"shop/one":"owner","workshop/one":"owner"}
var orgs: Dictionary={"guilds":{"dark_box":{"leader":"worker","status":"active","headquarters":""}},"factions":{"security":{"leader":"other"}}}
var actions: Array=[]
var committed: Dictionary={}
var selection_context: Dictionary={}
var quests: RefCounted
var economy: Node
var model: RefCounted
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func callbacks(target: RefCounted) -> void:
	target.configure({"identity":func(id: String): return people.get(id,{}),"authorize":authorize,"quest":quest,"perform":perform,"premises":func(id: String,reference: String,_kinds: Array): return premises.get(reference)==id or id=="worker" and reference=="shop/one","organizations":func(): return orgs,"context":func(_id: String): return selection_context})
func authorize(operation: String,payload: Dictionary) -> bool:
	match operation:
		"hire": return payload.employer=="owner"
		"business": return premises.get(payload.workplace)==payload.owner
		"service_event": return committed.get(payload.event_id,{})==payload
		"register_career": return payload.id=="courtyard_keeper"
	return false
func quest(operation: String,payload: Dictionary) -> Dictionary:
	if operation=="inspect":
		var row: Dictionary=quests.instances.get(payload.quest_id,{})
		return {"row":row.duplicate(true),"funded":economy.contracts.get(payload.quest_id,{}).get("status")=="reserved"}
	return {}
func perform(actor: String,capability: String,employment: Dictionary) -> Dictionary:
	actions.append({"actor":actor,"capability":capability,"employment":employment.id})
	return {"performed":true,"capability":capability}
func finance(row: Dictionary) -> bool:
	match row.operation:
		"reserve": return economy.reserve_contract(row.quest_id,row.source,int(row.amount))
		"pay": return economy.settle_contract(row.quest_id,row.beneficiary,row.service,row.legality)
		"refund": return economy.refund_contract(row.quest_id)
	return false
func run() -> void:
	economy=Economy.new(); root.add_child(economy); economy.configure("human",["worker","owner","other"]); economy.bless_cycle(0,["worker","owner","other"])
	quests=Quests.new()
	quests.configure({"identity":func(id: String): return people.get(id,{}),"authorize":func(operation: String,row: Dictionary): return operation in ["publish","event"] and (operation!="event" or committed.get(row.event_id,{})==row),"finance":finance})
	model=Careers.new(); callbacks(model)
	var sectors: Dictionary={}
	for row: Dictionary in model.definitions.values(): sectors[row.sector]=true
	check(model.definitions.size()==74 and sectors.size()==8,"All seventy-four stable careers cover eight sectors")
	check(model.definitions.cartographer.name=="Cartographer" and model.definitions.guild_leader.qualifications==["actual_leadership"],"Career definitions retain descriptive metadata and office qualification")
	check(model.select_career("player","merchant").is_empty() and model.select_career("avat_ar","merchant").is_empty() and model.select_career("boss","thief").is_empty(),"Players, Avat Ar and bosses cannot enter ordinary employment")
	var person_before: Dictionary=people.worker.duplicate(true)
	var funds_before: Dictionary=economy.serialize()
	var merchant: String=model.select_career("worker","merchant")
	var courier: String=model.select_career("worker","courier")
	check(not merchant.is_empty() and not courier.is_empty() and model.set_primary("worker",courier) and model.records_for("worker",false).size()==2,"A Code Form can hold multiple jobs and choose its primary occupation")
	check(economy.serialize()==funds_before and people.worker==person_before and quests.memberships.is_empty(),"Career titles generate no coins, XP, lifespan reset or guild authority")
	check(model.end_employment("worker",merchant) and model.records_for("worker",false).size()==1 and model.records_for("worker").size()==2,"Career changes retain compact employment history")
	check(model.select_career("worker","guild_leader").is_empty() and model.select_career("worker","faction_leader").is_empty(),"Leadership careers cannot self-appoint organizational authority")
	model.synchronize_positions("worker")
	var offices: Array=model.records_for("worker",false).filter(func(row: Dictionary): return row.status=="office")
	check(offices.size()==1 and offices[0].career=="guild_leader" and offices[0].role_ref=="dark_box","Actual guild leadership creates a corresponding occupational office")
	orgs.guilds.dark_box.leader="other"; model.synchronize_positions("worker"); model.synchronize_positions("other")
	check(model.records_for("worker",false).filter(func(row: Dictionary): return row.status=="office").is_empty() and model.records_for("other",false).size()==2,"Succession ends the old office while independent guild/faction leadership can coexist")
	check(model.hire("owner","worker","courier","shop/one","fictional").is_empty(),"A job cannot promise unreserved compensation")
	var job: String=quests.create_contract("personal_delivery","owner","resident:owner",{"item_type":"electron_meal","recipient_id":"owner","reward":12},0)
	quests.accept(job,"worker",0)
	var business: String=model.register_business("owner","Corner Supply","shop/one","shop")
	check(not business.is_empty() and model.register_business("worker","Fake Shop","workshop/one","workshop").is_empty(),"Businesses require actual owned or authorized functional premises")
	var employed: String=model.hire("owner","worker","courier","shop/one",job,business)
	check(not employed.is_empty() and model.employments[employed].compensation.amount==12 and model.businesses[business].employees==[employed],"A business hires against a real funded shared-quest contract")
	check(model.hire("owner","other","courier","shop/one",job).is_empty(),"One assignment cannot be reused to fund another employee")
	var before_wait: int=economy.balance("resident:worker")
	model.npc_step("worker",1000)
	check(economy.balance("resident:worker")==before_wait and quests.instances[job].status=="active","Waiting or performing a title callback cannot complete or pay the assignment")
	var delivery: Dictionary={"event_id":"delivered_meal","actor_id":"worker","event_type":"delivery","item_type":"electron_meal","recipient_id":"owner","target_id":"","timestamp":0}
	committed[delivery.event_id]=delivery; quests.consume_event(delivery)
	check(quests.instances[job].status=="completed" and economy.balance("resident:worker")==before_wait+12,"Only an authorized matching actual-event proof settles compensation")
	model.reconcile_contracts(1200)
	check(model.employments[employed].status=="ended" and economy.balance("resident:worker")==before_wait+12,"A completed assignment ends employment without another wage payment")
	var second: String=quests.create_contract("personal_delivery","owner","resident:owner",{"item_type":"electron_meal","recipient_id":"owner","reward":8},1200)
	quests.accept(second,"worker",1200)
	var second_job: String=model.hire("owner","worker","courier","shop/one",second,business)
	check(not second_job.is_empty(),"A second real funded assignment prepares the stale job regression")
	var resumed_jobs:=Careers.new(); callbacks(resumed_jobs)
	check(resumed_jobs.restore(model.serialize()),"A live employment rebuilds its active contract index on restore")
	quests.cancel(second,"owner")
	# Simulate the quest board compacting terminal history before this worker's
	# next scheduled AI turn; there must be no active dangling employment.
	quests.instances.erase(second)
	resumed_jobs.reconcile_contracts(1250)
	check(resumed_jobs.employments[second_job].status=="ended" and resumed_jobs.businesses[business].employees.is_empty(),"Cancelled/pruned contracts end jobs and business assignments without an NPC turn")
	var end_time: float=resumed_jobs.employments[second_job].ended_at
	resumed_jobs.reconcile_contracts(1300)
	check(resumed_jobs.employments[second_job].ended_at==end_time and not Careers.validate(resumed_jobs.serialize()).is_empty(),"Contract cleanup is idempotent and remains strictly saveable")
	model.reconcile_contracts(1250)
	for n in range(Careers.BASE_ROLES.size()):
		var key: String=model.select_career("owner",Careers.BASE_ROLES[n])
		if not key.is_empty(): model.set_primary("owner",key); model.npc_step("owner",1400+n*130.0)
	var seen: Dictionary={}
	for action: Dictionary in actions: seen[action.capability]=true
	check(seen.size()==8,"The eight career templates dispatch only their reusable bounded action capabilities")
	var calls:=actions.size(); model.npc_step("owner",2311)
	check(actions.size()==calls,"Existing AI scheduling observes the action cooldown")
	var service: Dictionary={"event_id":"service_a","actor_id":"worker","service":"courtyard_care"}
	check(not model.observe_service(service),"Unverified uncategorized work cannot invent a profession")
	committed[service.event_id]=service
	check(model.observe_service(service) and not model.observe_service(service) and model.candidates.courtyard_care.count==1,"Meaningful uncategorized services are recorded once with persistent replay protection")
	var known: Dictionary={"event_id":"known_patrol","actor_id":"worker","service":"patrol"}; committed[known.event_id]=known
	check(model.observe_service(known) and model.candidates.size()==1,"Existing service aliases do not masquerade as newly emerging professions")
	var custom: Dictionary=model.definitions.guild_clerk.duplicate(true); custom.id="courtyard_keeper"; custom.name="Courtyard Keeper"
	check(model.register_definition(custom) and model.definitions.has("courtyard_keeper"),"Extensible career definitions reuse supported existing capabilities")
	var invalid: Dictionary=custom.duplicate(true); invalid.id="arbitrary_code"; invalid.capabilities=["execute_script"]
	check(not model.register_definition(invalid),"New career metadata cannot introduce arbitrary executable actions")
	var restored:=Careers.new(); callbacks(restored)
	check(restored.restore(JSON.parse_string(JSON.stringify(model.serialize()))) and restored.businesses[business].owner=="owner" and restored.definitions.has("courtyard_keeper"),"Careers, funded employment, business ownership and extensions round-trip through strict JSON")
	check(not restored.observe_service(service),"Semantic replay protection survives save/load")
	var corrupt: Dictionary=model.serialize(); corrupt.workers.worker.primary="unknown"
	check(not restored.restore(corrupt),"Malformed employment links reject without changing live records")
	model.retire("owner")
	check(model.businesses[business].status=="closed" and model.records_for("owner",false).is_empty() and model.records_for("owner").size()==1,"Lifetime retirement closes businesses and compacts historical jobs without inheritance")
	check(people.worker==person_before,"Progression and identity remain owned by the original Code Form registry")
	people.worker.motivations={"wealth":0.0,"knowledge":1.0,"duty":0.0,"social":0.0,"risk":0.0}
	model.npc_step("worker",90000)
	var primary: Dictionary=model.employments[model.workers.worker.primary]
	check(model.definitions[primary.career].sector in ["exploration","knowledge"] and primary.status=="self_employed","Periodic self-employment reevaluation responds to changed motives while retaining job history")
	var invalid_pay: Dictionary=model.serialize(); invalid_pay.employments[primary.id].compensation.type="contract"
	check(Careers.validate(invalid_pay).is_empty(),"Self-employed titles cannot be relabeled as funded paid contracts")
	var reachable:=0
	for career: String in model.definitions:
		if model.definitions[career].employment_type=="office" or career=="courtyard_keeper": continue
		people.worker.motivations={"wealth":.5,"knowledge":.5,"security":.1 if model.definitions[career].sector=="underworld" else .5,"social":.5,"mastery":.5,"loyalty":.5,"novelty":.5,"survival":.5}
		selection_context={"occupation":career}
		if model._choose("worker")==career: reachable+=1
	check(reachable==72,"Every nonoffice founding career can be selected from actual occupational context, beyond the eight shared action templates")
	var runtime:=Runtime.new(); runtime.setup({}); root.add_child(runtime)
	check(not runtime.is_processing() or not runtime.has_method("_process"),"The career runtime adds no per-frame profession simulation")
	runtime.free(); economy.free()
	print("Career system: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
