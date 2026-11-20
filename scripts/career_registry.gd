extends RefCounted
## Value-only occupational records. Titles never grant money, XP or authority.
const Item=preload("res://scripts/item_instance.gd")
const CAPABILITIES:=["exploration","enforcement","trade","delivery","production","food_preparation","theft","administration"]
const SECTORS:=["exploration","security","commerce","crafting","hospitality","knowledge","underworld","administration"]
const MAX_WORKERS:=16384
const MAX_EMPLOYMENTS:=32768
const MAX_BUSINESSES:=256
const MAX_CANDIDATES:=64
const BLOOM_BYTES:=8192
const BASE_ROLES:=["adventurer","security_officer","merchant","courier","artificer","chef","thief","guild_clerk"]
const KNOWN_SERVICES:=["patrol","survey","craft","prepare_meal","recruit","delivery","trade","investigate","supply_work","guild_work","tavern_work","cooking","cook","repair","renovation","guard","recovery","discovery","item_sale","item_transfer","contract","food","crystal_sale"]
var definitions: Dictionary={}
var custom_definitions: Dictionary={}
var workers: Dictionary={}
var employments: Dictionary={}
var businesses: Dictionary={}
var candidates: Dictionary={}
var world_seconds:=0.0
var next_id:=1
var next_business:=1
var revision:=0
var _callbacks: Dictionary={}
var _busy:=false
var _events:=PackedByteArray()
func _init() -> void:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/careers.json"))
	if data is Dictionary:
		for row: Dictionary in data.get("careers",[]):
			if _definition(row): definitions[row.id]=row
	_events.resize(BLOOM_BYTES); _events.fill(0)
func configure(callbacks: Dictionary) -> void: _callbacks=callbacks
func _call(key: String,args: Array,fallback: Variant=null) -> Variant:
	var callback: Callable=_callbacks.get(key,Callable())
	return callback.callv(args) if callback.is_valid() else fallback
func _person(id: String) -> Dictionary:
	var row: Variant=_call("identity",[id],{})
	return row if row is Dictionary and row.get("active",false) and row.get("kind","")=="code_form" and id!="avat_ar" else {}
func _authorized(operation: String,payload: Dictionary) -> bool: return _call("authorize",[operation,payload],false)==true
func _worker(id: String) -> Dictionary:
	if workers.has(id): return workers[id]
	if workers.size()>=MAX_WORKERS: return {}
	workers[id]={"primary":"","employments":[],"next_decision":0.0,"next_action":0.0}
	return workers[id]
func _positions() -> Dictionary:
	var data: Variant=_call("organizations",[],{})
	return data if data is Dictionary else {}
func _has_position(id: String,career: String,reference: String) -> bool:
	var orgs:=_positions()
	var group: Dictionary=orgs.get("guilds",{}) if career=="guild_leader" else orgs.get("factions",{})
	return group.has(reference) and group[reference].get("leader")==id and group[reference].get("status","active")=="active"
func _can_add(id: String,office: bool=false) -> bool:
	if employments.size()>=MAX_EMPLOYMENTS: return false
	var count:=0
	for row: Dictionary in records_for(id):
		if row.status!="ended" and (office or row.status!="office"): count+=1
	return count<(200 if office else 8)
func _add(id: String,career: String,employer: String,workplace: String,compensation: Dictionary,quest_id: String,status: String,business: String="",role_ref: String="") -> String:
	if not _can_add(id,status=="office"): return ""
	var worker:=_worker(id)
	if worker.is_empty(): return ""
	var key:="employment_"+str(next_id)
	employments[key]={"id":key,"employee":id,"career":career,"employer":employer,"workplace":workplace,"compensation":compensation,"quest_id":quest_id,"status":status,"started_at":world_seconds,"ended_at":0.0,"business":business,"role_ref":role_ref}
	worker.employments.append(key); next_id+=1
	if worker.primary.is_empty(): worker.primary=key
	while worker.employments.size()>24:
		var removed:=false
		for prior: String in worker.employments:
			if employments[prior].status=="ended": worker.employments.erase(prior); employments.erase(prior); removed=true; break
		if not removed: break
	revision+=1
	return key
func records_for(id: String,include_history: bool=true) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for key: String in workers.get(id,{}).get("employments",[]):
		if employments.has(key) and (include_history or employments[key].status!="ended"): result.append(employments[key].duplicate(true))
	return result
func select_career(id: String,career: String,workplace: String="") -> String:
	if _busy or _person(id).is_empty() or not definitions.has(career) or definitions[career].employment_type=="office" or not _text(workplace,true): return ""
	if not workplace.is_empty() and _call("premises",[id,workplace,definitions[career].workplaces],false)!=true: return ""
	for row: Dictionary in records_for(id,false):
		if row.career==career and row.status=="self_employed" and row.workplace==workplace:
			workers[id].next_decision=world_seconds+86400.0
			return row.id
	var key:=_add(id,career,id,workplace,{"type":"self_employed","amount":0,"source":"resident:"+id},"","self_employed")
	if not key.is_empty(): workers[id].next_decision=world_seconds+86400.0
	return key
func hire(employer: String,employee: String,career: String,workplace: String,quest_id: String,business: String="") -> String:
	if _busy or _person(employee).is_empty() or not definitions.has(career) or definitions[career].employment_type=="office" or not _text(employer) or not _text(workplace,true) or not _text(quest_id): return ""
	if not _authorized("hire",{"employer":employer,"employee":employee,"career":career,"workplace":workplace,"quest_id":quest_id,"business":business}): return ""
	if not workplace.is_empty() and _call("premises",[employee,workplace,definitions[career].workplaces],false)!=true: return ""
	if not business.is_empty() and (not businesses.has(business) or businesses[business].status!="active" or businesses[business].owner!=employer or businesses[business].workplace!=workplace): return ""
	var proof: Variant=_call("quest",["inspect",{"quest_id":quest_id}],{})
	if not proof is Dictionary or proof.get("funded")!=true or not proof.get("row") is Dictionary: return ""
	var row: Dictionary=proof.row
	if row.get("id")!=quest_id or row.get("issuer")!=employer or row.get("participant")!=employee or row.get("status") not in ["active","ready"] or not Item.whole_number(row.get("reward"),1,100000) or row.get("kind") not in definitions[career].quest_categories: return ""
	for current: Dictionary in employments.values():
		if current.quest_id==quest_id and current.status!="ended": return ""
	var key:=_add(employee,career,employer,workplace,{"type":"contract","amount":int(row.reward),"source":String(row.source)},quest_id,"active",business)
	if not key.is_empty() and not business.is_empty(): businesses[business].employees.append(key)
	return key
func set_primary(id: String,employment: String) -> bool:
	if _busy or _person(id).is_empty() or not employments.has(employment) or employments[employment].employee!=id or employments[employment].status=="ended": return false
	workers[id].primary=employment; revision+=1; return true
func end_employment(id: String,key: String) -> bool:
	if _busy or not employments.has(key) or employments[key].employee!=id or employments[key].status=="ended": return false
	var row: Dictionary=employments[key]
	row.status="ended"; row.ended_at=world_seconds
	if not row.business.is_empty() and businesses.has(row.business): businesses[row.business].employees.erase(key)
	if workers[id].primary==key:
		workers[id].primary=""
		for current: Dictionary in records_for(id,false): workers[id].primary=current.id; break
	revision+=1; return true
func register_business(owner: String,name: String,workplace: String,kind: String) -> String:
	if _busy or _person(owner).is_empty() or not _text(name) or not _text(workplace) or not kind in ["shop","restaurant","tavern","workshop","warehouse","archive","office","lodging"] or businesses.size()>=MAX_BUSINESSES: return ""
	if not _authorized("business",{"owner":owner,"name":name,"workplace":workplace,"kind":kind}) or _call("premises",[owner,workplace,[kind]],false)!=true: return ""
	for row: Dictionary in businesses.values():
		if row.status=="active" and row.workplace==workplace: return ""
	var key:="business_"+str(next_business)
	businesses[key]={"id":key,"name":name,"owner":owner,"workplace":workplace,"kind":kind,"treasury":"resident:"+owner,"employees":[],"assets":[],"status":"active","created_at":world_seconds,"closed_at":0.0}
	next_business+=1; revision+=1; return key
func close_business(key: String,owner: String) -> bool:
	if _busy or not businesses.has(key) or businesses[key].owner!=owner or businesses[key].status!="active": return false
	var row: Dictionary=businesses[key]
	for employment: String in row.employees.duplicate(): end_employment(employments[employment].employee,employment)
	row.status="closed"; row.closed_at=world_seconds; revision+=1; return true
func synchronize_positions(id: String) -> void:
	if _busy or _person(id).is_empty(): return
	var positions:=_positions()
	for row: Dictionary in records_for(id,false):
		if row.status=="office" and not _has_position(id,row.career,row.role_ref): end_employment(id,row.id)
	for group: String in ["guilds","factions"]:
		for key: String in positions.get(group,{}):
			var row: Dictionary=positions[group][key]
			if row.get("leader")!=id or row.get("status","active")!="active": continue
			var career: String="guild_leader" if group=="guilds" else "faction_leader"
			var found:=false
			for employment: Dictionary in records_for(id,false):
				if employment.career==career and employment.role_ref==key:
					found=true
					var headquarters:=String(row.get("headquarters",""))
					if employment.workplace!=headquarters: employments[employment.id].workplace=headquarters; revision+=1
			if not found: _add(id,career,("guild/" if group=="guilds" else "faction/")+key,String(row.get("headquarters","")),{"type":"office","amount":0,"source":""},"","office","",key)
func retire(id: String) -> void:
	if _busy: return
	for row: Dictionary in records_for(id,false): end_employment(id,row.id)
	for row: Dictionary in employments.values():
		if row.employer==id and row.status!="ended": end_employment(row.employee,row.id)
	for row: Dictionary in businesses.values():
		if row.owner==id and row.status=="active": close_business(row.id,id)
	# Match the historical identity cap without retaining active job machinery.
	if workers.has(id):
		while workers[id].employments.size()>1:
			var key: String=workers[id].employments.pop_front()
			employments.erase(key)
		revision+=1
func _choose(id: String) -> String:
	var person:=_person(id)
	var motivation: Dictionary=person.get("motivations",{})
	var details: Variant=_call("context",[id],{})
	var context: Dictionary=details if details is Dictionary else {}
	var skills: Array=context.get("skills",[])
	var equipment: Array=context.get("equipment",[])
	var guilds: Array=context.get("guilds",[])
	var workplaces: Array=context.get("workplaces",[])
	var resources: Dictionary=context.get("resources",{})
	var occupation:=String(context.get("occupation",person.get("occupation",""))).to_lower().replace(" ","_")
	var prior_counts: Dictionary={}
	for prior: Dictionary in records_for(id):
		if prior.status=="ended": prior_counts[prior.career]=int(prior_counts.get(prior.career,0))+1
	var best:="adventurer"
	var best_score:=-INF
	# A single bounded definition scan on this actor's daily AI decision. The
	# context provider gathers local facts once, never once per profession.
	for key: String in definitions:
		var definition: Dictionary=definitions[key]
		if definition.employment_type=="office": continue
		var qualified:=true
		for qualification: String in definition.qualifications:
			if qualification.begins_with("skill:"): qualified=qualified and qualification.trim_prefix("skill:") in skills
			elif qualification.begins_with("equipment:"): qualified=qualified and qualification.trim_prefix("equipment:") in equipment
			elif qualification.begins_with("level:") and qualification.trim_prefix("level:").is_valid_int(): qualified=qualified and int(context.get("level",person.get("level",1)))>=int(qualification.trim_prefix("level:"))
			else: qualified=false
		if not qualified: continue
		var score:=0.0
		var weight:=0.0
		for preference: String in definition.preferred_traits: score+=float(motivation.get(preference,.5))*float(definition.preferred_traits[preference])
		for value: float in definition.preferred_traits.values(): weight+=absf(value)
		if weight>0: score/=weight
		for skill: String in definition.skills:
			if skill in skills: score+=.15
		for tool: String in definition.equipment:
			if tool in equipment or int(resources.get(tool,0))>0: score+=.08
		for affiliation: String in definition.guilds:
			if affiliation in guilds: score+=.12; break
		for kind: String in definition.workplaces:
			if kind in workplaces: score+=.2; break
		if occupation==key: score+=.25
		score-=float(prior_counts.get(key,0))*.01
		score+=float(posmod((id+key).hash(),101))*.0001
		if definition.sector=="underworld" and float(motivation.get("security",.5))>.4: score-=.75
		if score>best_score: best=key; best_score=score
	return best
func _reconcile_jobs(id: String) -> void:
	for row: Dictionary in records_for(id,false):
		if row.status!="active": continue
		var proof: Variant=_call("quest",["inspect",{"quest_id":row.quest_id}],{})
		if not proof is Dictionary or proof.get("row",{}).get("status","") not in ["active","ready"]: end_employment(id,row.id)
func npc_step(id: String,now: float) -> Dictionary:
	if _busy or _person(id).is_empty() or not _time(now) or now<world_seconds: return {}
	world_seconds=now
	var worker:=_worker(id)
	if worker.is_empty(): return {}
	synchronize_positions(id)
	_reconcile_jobs(id)
	if now>=float(worker.next_decision):
		worker.next_decision=now+86400.0
		var options: Variant=_call("quest",["opportunities",{"actor_id":id,"limit":4}],{})
		if options is Dictionary:
			for offer: Dictionary in options.get("rows",[]).slice(0,4):
				if definitions.has(offer.get("career_id","")):
					var job:=hire(String(offer.get("employer","")),id,offer.career_id,String(offer.get("workplace","")),String(offer.get("quest_id","")),String(offer.get("business","")))
					if not job.is_empty(): set_primary(id,job); break
		var primary: Dictionary=employments.get(String(worker.primary),{})
		var paid:=false
		for row: Dictionary in records_for(id,false):
			if row.status=="active": paid=true
		if not paid and (primary.is_empty() or primary.status=="self_employed"):
			var selected:=_choose(id)
			var workplace: Variant=_call("workplace",[id,selected],"")
			if not workplace is String: workplace=""
			if primary.is_empty() or primary.career!=selected or primary.workplace!=workplace:
				if not primary.is_empty(): end_employment(id,primary.id)
				var next:=select_career(id,selected,workplace)
				if not next.is_empty(): set_primary(id,next)
		revision+=1
	if now<float(worker.next_action) or worker.primary.is_empty(): return {}
	var employment: Dictionary=employments[worker.primary]
	var definition: Dictionary=definitions[employment.career]
	worker.next_action=now+120.0; revision+=1
	_busy=true
	var result: Variant=_call("perform",[id,String(definition.capabilities[0]),employment.duplicate(true)],{})
	_busy=false
	_reconcile_jobs(id)
	# The adapter's real action/receipt remains the only completion authority.
	return result if result is Dictionary else {}
func _bits(id: String) -> Array[int]: return [posmod(id.hash(),BLOOM_BYTES*8),posmod((id+"/career").hash(),BLOOM_BYTES*8),posmod(("event/"+id).hash(),BLOOM_BYTES*8)]
func observe_service(event: Dictionary) -> bool:
	if _busy or not _text(event.get("event_id")) or not _text(event.get("service")) or _person(String(event.get("actor_id",""))).is_empty() or not _authorized("service_event",event): return false
	var bits:=_bits(event.event_id)
	var seen:=true
	for bit: int in bits:
		if (_events[bit>>3]&(1<<(bit%8)))==0: seen=false
	if seen: return false
	for bit: int in bits: _events[bit>>3]|=1<<(bit%8)
	var key: String=event.service
	if key in CAPABILITIES or key in KNOWN_SERVICES: revision+=1; return true
	if not candidates.has(key):
		if candidates.size()>=MAX_CANDIDATES: return false
		candidates[key]={"service":key,"count":0,"first_at":world_seconds,"last_at":world_seconds}
	candidates[key].count=mini(100000,int(candidates[key].count)+1); candidates[key].last_at=world_seconds; revision+=1
	return true
func register_definition(definition: Dictionary) -> bool:
	if _busy or definitions.has(definition.get("id","")) or custom_definitions.size()>=64 or not _definition(definition) or not _authorized("register_career",definition): return false
	definitions[definition.id]=definition.duplicate(true); custom_definitions[definition.id]=definition.duplicate(true); revision+=1; return true
func transaction_active() -> bool: return _busy
func serialize() -> Dictionary:
	return {"version":1,"world_seconds":world_seconds,"next_id":next_id,"next_business":next_business,"workers":workers.duplicate(true),"employments":employments.duplicate(true),"businesses":businesses.duplicate(true),"candidates":candidates.duplicate(true),"event_bloom":_events.hex_encode(),"custom_definitions":custom_definitions.duplicate(true)}
func restore(data: Variant) -> bool:
	if _busy: return false
	if data==null:
		for key: String in custom_definitions: definitions.erase(key)
		custom_definitions.clear(); workers.clear(); employments.clear(); businesses.clear(); candidates.clear(); world_seconds=0; next_id=1; next_business=1; _events.fill(0); revision+=1; return true
	var decoded:=validate(data)
	if decoded.is_empty(): return false
	for key: String in custom_definitions: definitions.erase(key)
	custom_definitions=decoded.custom_definitions
	for key: String in custom_definitions: definitions[key]=custom_definitions[key]
	workers=decoded.workers; employments=decoded.employments; businesses=decoded.businesses; candidates=decoded.candidates
	world_seconds=decoded.world_seconds; next_id=decoded.next_id; next_business=decoded.next_business; _events=String(decoded.event_bloom).hex_decode(); revision+=1; return true
static func _text(value: Variant,empty: bool=false) -> bool: return Item.valid_text(value,empty,128) and not "\n" in String(value) and not "\r" in String(value)
static func _time(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=9e12
static func _definition(row: Variant) -> bool:
	if not row is Dictionary or row.size()!=14 or not _text(row.get("id")) or not _text(row.get("name")) or row.get("sector") not in SECTORS or not _text(row.get("description")) or row.get("employment_type") not in ["flexible","office"]: return false
	for key: String in ["capabilities","skills","equipment","quest_categories","workplaces","guilds","economic_activities","qualifications"]:
		if not row.get(key) is Array or row[key].size()>16: return false
		for value: Variant in row[key]:
			if not _text(value): return false
	if row.capabilities.is_empty() or row.quest_categories.is_empty(): return false
	for capability: String in row.capabilities:
		if capability not in CAPABILITIES: return false
	for kind: String in row.quest_categories:
		if kind not in ["delivery","discovery","service","recovery"]: return false
	if not row.get("preferred_traits") is Dictionary or row.preferred_traits.size()>8: return false
	for key: Variant in row.preferred_traits:
		if not _text(key) or not (row.preferred_traits[key] is int or row.preferred_traits[key] is float) or not is_finite(float(row.preferred_traits[key])) or absf(float(row.preferred_traits[key]))>1: return false
	return true
static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size()!=10 or not Item.whole_number(data.get("version"),1,1) or not _time(data.get("world_seconds")) or not Item.whole_number(data.get("next_id"),1,1000000000) or not Item.whole_number(data.get("next_business"),1,1000000000): return {}
	for pair: Array in [["workers",MAX_WORKERS],["employments",MAX_EMPLOYMENTS],["businesses",MAX_BUSINESSES],["candidates",MAX_CANDIDATES],["custom_definitions",64]]:
		if not data.get(pair[0]) is Dictionary or data[pair[0]].size()>pair[1]: return {}
	if not data.get("event_bloom") is String or data.event_bloom.length()!=BLOOM_BYTES*2 or data.event_bloom.hex_decode().hex_encode()!=data.event_bloom: return {}
	var model=load("res://scripts/career_registry.gd").new()
	for key: Variant in data.custom_definitions:
		if not _definition(data.custom_definitions[key]) or data.custom_definitions[key].id!=key or model.definitions.has(key): return {}
		model.definitions[key]=data.custom_definitions[key]
	var highest:=0
	var highest_business:=0
	var referenced: Dictionary={}
	for id: Variant in data.workers:
		var row: Variant=data.workers[id]
		if not _text(id) or id in ["player","avat_ar"] or not row is Dictionary or row.size()!=4 or not _text(row.get("primary"),true) or not row.get("employments") is Array or row.employments.size()>224 or not _time(row.get("next_decision")) or not _time(row.get("next_action")): return {}
		var active:=0
		var offices:=0
		for key: Variant in row.employments:
			if not _text(key) or referenced.has(key) or not data.employments.has(key) or data.employments[key].get("employee")!=id: return {}
			referenced[key]=true
			if data.employments[key].get("status")=="office": offices+=1
			elif data.employments[key].get("status")!="ended": active+=1
		if active>8 or offices>192 or (not row.primary.is_empty() and (not row.primary in row.employments or data.employments[row.primary].get("status")=="ended")): return {}
	if referenced.size()!=data.employments.size(): return {}
	for key: Variant in data.employments:
		var row: Variant=data.employments[key]
		if not _text(key) or not String(key).begins_with("employment_") or not String(key).trim_prefix("employment_").is_valid_int(): return {}
		var serial:=int(String(key).trim_prefix("employment_"))
		if serial<1 or String(key)!="employment_"+str(serial): return {}
		highest=maxi(highest,serial)
		if not row is Dictionary or row.size()!=12 or row.get("id")!=key or not model.definitions.has(row.get("career")) or not _text(row.get("employee")) or not _text(row.get("employer")) or not _text(row.get("workplace"),true) or not _text(row.get("quest_id"),true) or not _text(row.get("business"),true) or not _text(row.get("role_ref"),true) or row.get("status") not in ["active","self_employed","office","ended"] or not _time(row.get("started_at")) or row.started_at>data.world_seconds or not _time(row.get("ended_at")) or row.ended_at>data.world_seconds: return {}
		if row.status=="ended" and row.ended_at<row.started_at: return {}
		if row.status!="ended" and row.ended_at!=0: return {}
		var pay: Variant=row.get("compensation")
		if not pay is Dictionary or pay.size()!=3 or pay.get("type") not in ["contract","self_employed","office"] or not Item.whole_number(pay.get("amount"),0,100000) or not _text(pay.get("source"),true): return {}
		if pay.type=="contract":
			if pay.amount<1 or row.quest_id.is_empty() or pay.source.is_empty(): return {}
		elif pay.amount!=0 or not row.quest_id.is_empty(): return {}
		if row.status=="active" and pay.type!="contract": return {}
		if row.status=="self_employed" and (pay.type!="self_employed" or row.employer!=row.employee or pay.source!="resident:"+String(row.employee)): return {}
		if row.status=="office" and pay.type!="office": return {}
		if row.status=="office" and (row.career not in ["guild_leader","faction_leader"] or row.role_ref.is_empty()): return {}
		if not row.business.is_empty() and not data.businesses.has(row.business): return {}
	for key: Variant in data.businesses:
		var row: Variant=data.businesses[key]
		if not _text(key) or not String(key).begins_with("business_") or not String(key).trim_prefix("business_").is_valid_int(): return {}
		var serial:=int(String(key).trim_prefix("business_"))
		if serial<1 or String(key)!="business_"+str(serial): return {}
		highest_business=maxi(highest_business,serial)
		if not row is Dictionary or row.size()!=11 or row.get("id")!=key or not _text(row.get("name")) or not _text(row.get("owner")) or row.owner in ["player","avat_ar"] or not _text(row.get("workplace")) or row.get("kind") not in ["shop","restaurant","tavern","workshop","warehouse","archive","office","lodging"] or row.get("treasury")!="resident:"+String(row.owner) or row.get("status") not in ["active","closed"] or not _time(row.get("created_at")) or row.created_at>data.world_seconds or not _time(row.get("closed_at")) or row.closed_at>data.world_seconds or not row.get("employees") is Array or row.employees.size()>MAX_WORKERS or not row.get("assets") is Array or row.assets.size()>32: return {}
		var seen: Dictionary={}
		for employment: Variant in row.employees:
			if seen.has(employment) or not data.employments.has(employment) or data.employments[employment].business!=key or data.employments[employment].status!="active": return {}
			seen[employment]=true
		for asset: Variant in row.assets:
			if not _text(asset): return {}
		if row.status=="closed" and (not row.employees.is_empty() or row.closed_at<row.created_at): return {}
	for row: Dictionary in data.employments.values():
		if row.status=="active" and not row.business.is_empty() and not row.id in data.businesses[row.business].employees: return {}
	for key: Variant in data.candidates:
		var row: Variant=data.candidates[key]
		if not _text(key) or not row is Dictionary or row.size()!=4 or row.get("service")!=key or not Item.whole_number(row.get("count"),1,100000) or not _time(row.get("first_at")) or not _time(row.get("last_at")) or row.first_at>row.last_at or row.last_at>data.world_seconds: return {}
	if highest>=int(data.next_id) or highest_business>=int(data.next_business): return {}
	var result: Dictionary=Item.json_copy(data)
	result.world_seconds=float(data.world_seconds); result.next_id=int(data.next_id); result.next_business=int(data.next_business)
	return result
