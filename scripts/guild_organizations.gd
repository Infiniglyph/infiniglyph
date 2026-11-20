extends RefCounted
## Persistent institutions. Coins remain exclusively in the audited ledger.
const Item=preload("res://scripts/item_instance.gd")
const MAX_GUILDS:=128
const MAX_MEMBERS:=4096
const MAX_HISTORY:=64
const MAX_SUPPORT:=64
const GOVERNANCE:=["election","appointed","merit","challenge"]
const GENERALISTS:={"exploration":"adventurers_guild","underworld":"lit_mob","security":"dark_box","commerce":"trade_united"}
var factions: Dictionary={}
var guilds: Dictionary={}
var supports: Dictionary={}
var world_seconds:=0.0
var next_id:=1
var next_review:=0.0
var review_cursor:=0
var revision:=0
var _callbacks: Dictionary={}
var _busy:=false
var _pending_sweep:=""

func configure(callbacks: Dictionary) -> void: _callbacks=callbacks
func _person(id: String) -> Dictionary:
	var callback: Callable=_callbacks.get("identity",Callable())
	var row: Variant=callback.call(id) if callback.is_valid() else {}
	return row if row is Dictionary and row.get("active",false) and row.get("kind","") in ["player","code_form"] else {}
func _native(id: String) -> bool: return _person(id).get("kind")=="code_form"
func _authorized(operation: String,payload: Dictionary) -> bool:
	var callback: Callable=_callbacks.get("authorize",Callable())
	return callback.is_valid() and callback.call(operation,payload)==true
func _finance(request: Dictionary) -> bool:
	var callback: Callable=_callbacks.get("finance",Callable())
	return callback.is_valid() and callback.call(request)==true
func _event(row: Dictionary,kind: String,actor: String="",target: String="") -> void:
	# Membership churn updates the roster without evicting institutional history.
	if kind not in ["joined","left"]:
		row.history.append({"type":kind,"at":world_seconds,"actor":actor,"target":target})
		if row.history.size()>MAX_HISTORY: row.history.remove_at(1)
	revision+=1
	var callback: Callable=_callbacks.get("outcome",Callable())
	if callback.is_valid(): callback.call({"organization_id":row.id,"type":kind,"actor":actor,"target":target,"at":world_seconds})
func _guild(definition: Dictionary,now: float) -> Dictionary:
	return {"id":definition.id,"name":definition.name,"faction":definition.faction,"classification":definition.classification,"specialty":definition.specialty,"governance":definition.governance,"leader":"","members":[],"treasury":"guild:"+String(definition.id),"assets":[],"reputation":0.0,"relationships":{},"headquarters":"","founded_at":now,"status":"active","history":[],"nominations":{},"successor":"","empty_since":-1.0,"last_activity":now,"parent":"","merged_into":""}
func bootstrap(ids: Array,now: float,legacy_memberships: Dictionary={}) -> bool:
	if _busy or not guilds.is_empty() or not _time(now): return false
	var definitions: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/guilds.json"))
	var faction_definitions: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/factions.json"))
	if not definitions is Dictionary or not faction_definitions is Dictionary: return false
	var natives: Array[String]=[]
	for id: Variant in ids:
		if _native(String(id)) and not natives.has(String(id)): natives.append(String(id))
	natives.sort()
	if natives.size()<12: return false
	_busy=true
	if not _finance({"operation":"bootstrap","guilds":definitions.guilds.duplicate(true)}): _busy=false; return false
	world_seconds=now
	for definition: Dictionary in faction_definitions.factions:
		factions[definition.id]={"id":definition.id,"name":definition.name,"purpose":definition.purpose,"guilds":[],"leader":"","governance":"election","reputation":0.0,"relationships":{},"history":[],"headquarters":""}
	var index:=0
	for definition: Dictionary in definitions.guilds:
		var row:=_guild(definition,now)
		row.members.append(natives[index]); row.leader=natives[index]
		guilds[row.id]=row; factions[row.faction].guilds.append(row.id)
		_event(row,"founded",row.leader)
		index+=1
	for id: String in natives:
		if index<24: index+=1; continue
		var key: String=guilds.keys()[(index-24)%guilds.size()]
		if not guilds[key].members.has(id): guilds[key].members.append(id)
		index+=1
	for id: String in legacy_memberships:
		if _person(id).is_empty(): continue
		for faction: String in legacy_memberships[id]:
			var key: String=GENERALISTS.get(faction,"")
			if guilds.has(key) and not guilds[key].members.has(id): guilds[key].members.append(id)
	for key: String in factions:
		# Separate electorate/position: never derive faction leader from a guild.
		var candidate:=""
		for row: Dictionary in guilds_for_faction(key):
			for member: String in row.members:
				if candidate.is_empty() and member!=row.leader: candidate=member
		if candidate.is_empty(): candidate=guilds[factions[key].guilds.back()].leader
		factions[key].leader=candidate
		_event(factions[key],"faction_leadership",factions[key].leader)
	next_review=now+86400.0
	_busy=false
	return true
func guild(id: String) -> Dictionary: return guilds.get(id,{}).duplicate(true)
func guilds_for_faction(faction: String,include_closed: bool=false) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for row: Dictionary in guilds.values():
		if row.faction==faction and (include_closed or row.status=="active"): result.append(row.duplicate(true))
	return result
func memberships_of(id: String) -> Array[String]:
	var result: Array[String]=[]
	for row: Dictionary in guilds.values():
		if row.status=="active" and id in row.members: result.append(row.id)
	return result
func is_member(id: String,key: String) -> bool: return guilds.has(key) and guilds[key].status=="active" and id in guilds[key].members
func join(id: String,key: String,private_access: bool=false) -> bool:
	if _busy or _person(id).is_empty() or not guilds.has(key) or guilds[key].status!="active": return false
	var row: Dictionary=guilds[key]
	if row.faction=="underworld" and not private_access: return false
	if id in row.members: return true
	if row.members.size()>=MAX_MEMBERS: return false
	_busy=true
	row.members.append(id); row.empty_since=-1.0
	if row.leader.is_empty(): _succeed(row)
	_event(row,"joined",id)
	_busy=false
	return true
func leave(id: String,key: String) -> bool:
	if _busy or not is_member(id,key): return false
	var row: Dictionary=guilds[key]
	_busy=true
	row.members.erase(id); row.nominations.erase(id)
	for voter: String in row.nominations.keys():
		if row.nominations[voter]==id: row.nominations.erase(voter)
	if row.successor==id: row.successor=""
	if row.leader==id: row.leader=""; _succeed(row)
	if row.members.is_empty(): row.empty_since=world_seconds
	_event(row,"left",id)
	_busy=false
	return true
func nominate(voter: String,key: String,candidate: String) -> bool:
	if _busy or not is_member(voter,key) or not is_member(candidate,key) or not _native(candidate): return false
	guilds[key].nominations[voter]=candidate; revision+=1
	return true
func appoint(leader: String,key: String,successor: String) -> bool:
	if _busy or not guilds.has(key) or guilds[key].leader!=leader or not is_member(successor,key) or not _native(successor): return false
	guilds[key].successor=successor; revision+=1
	return true
func change_leader(key: String,candidate: String,actor: String,method: String="resignation") -> bool:
	if _busy or not guilds.has(key) or not is_member(candidate,key) or not _native(candidate): return false
	var row: Dictionary=guilds[key]
	if method=="resignation":
		if actor!=row.leader: return false
	elif not _authorized("leadership",{"guild_id":key,"candidate":candidate,"actor":actor,"method":method}): return false
	var old: String=row.leader
	row.leader=candidate; row.nominations.clear(); row.successor=""
	_event(row,"leadership/"+method,candidate,old)
	return true
func change_faction_leader(key: String,candidate: String,actor: String,method: String="election") -> bool:
	if _busy or not factions.has(key) or not _native(candidate): return false
	var member:=false
	for row: Dictionary in guilds_for_faction(key):
		if candidate in row.members: member=true
	if not member or not _authorized("faction_leadership",{"faction":key,"candidate":candidate,"actor":actor,"method":method}): return false
	var old: String=factions[key].leader
	factions[key].leader=candidate; _event(factions[key],"faction_leadership/"+method,candidate,old)
	return true
func _score(id: String,row: Dictionary) -> float:
	var person:=_person(id)
	var score:=float(person.get("level",1))+float(person.get("reputation",0))
	var motivations: Dictionary=person.get("motivations",{})
	score+=float(motivations.get("knowledge" if row.faction=="exploration" else "wealth" if row.faction in ["commerce","underworld"] else "security",.5))*10.0
	if row.governance=="election":
		for candidate: String in row.nominations.values():
			if candidate==id: score+=100.0
	return score
func _succeed(row: Dictionary) -> void:
	var best: String=""
	var score:=-INF
	if row.governance=="appointed" and is_member(row.successor,row.id) and _native(row.successor): best=row.successor
	else:
		for id: String in row.members:
			if not _native(id): continue
			var value:=_score(id,row)
			if value>score: score=value; best=id
	var old: String=row.leader
	row.leader=best; row.nominations.clear(); row.successor=""
	if old!=best: _event(row,"succession/"+String(row.governance),best,old)
func support(founder: String,supporter: String,faction: String,specialty: String,weight: float=1.0) -> bool:
	if _busy or founder==supporter or not _native(founder) or not _native(supporter) or not factions.has(faction) or not _text(specialty) or not is_finite(weight) or weight<.5 or weight>1: return false
	if not _authorized("support",{"founder":founder,"supporter":supporter,"faction":faction,"specialty":specialty,"weight":weight}): return false
	if not supports.has(founder):
		if supports.size()>=MAX_SUPPORT: return false
		supports[founder]={"faction":faction,"specialty":specialty,"supporters":{},"at":world_seconds}
	var row: Dictionary=supports[founder]
	if row.faction!=faction or row.specialty!=specialty or row.supporters.size()>=16: return false
	row.supporters[supporter]=weight; revision+=1
	return true
func found(founder: String,name: String,faction: String,specialty: String,amount: int=30,parent: String="") -> String:
	if _busy or not _native(founder) or not _text(name) or not supports.has(founder) or guilds.size()>=MAX_GUILDS or amount<30 or amount>100000: return ""
	var support_row: Dictionary=supports[founder]
	if support_row.faction!=faction or support_row.specialty!=specialty or world_seconds-float(support_row.at)>86400*30: return ""
	var members: Array=[founder]
	for id: String in support_row.supporters:
		if _native(id): members.append(id)
	if members.size()<4: return ""
	if not parent.is_empty():
		if not guilds.has(parent) or guilds[parent].status!="active" or guilds[parent].faction!=faction: return ""
		for id: String in members:
			if not is_member(id,parent): return ""
	var key:="guild_"+str(next_id)
	_busy=true
	if not _finance({"operation":"found","guild_id":key,"source":"resident:"+founder,"amount":amount}): _busy=false; return ""
	var row:=_guild({"id":key,"name":name,"faction":faction,"classification":"specialist","specialty":specialty,"governance":"election"},world_seconds)
	row.members=members; row.leader=founder; row.parent=parent
	guilds[key]=row; factions[faction].guilds.append(key); next_id+=1; supports.erase(founder)
	_busy=false
	if not parent.is_empty():
		for id: String in members: leave(id,parent)
		_event(guilds[parent],"splinter",founder,key)
	_event(row,"founded" if parent.is_empty() else "splinter_founded",founder,parent)
	return key
func merge(source: String,destination: String,actor: String) -> bool:
	if _busy or source==destination or not guilds.has(source) or not guilds.has(destination): return false
	var row: Dictionary=guilds[source]
	var target: Dictionary=guilds[destination]
	if row.status!="active" or target.status!="active" or row.faction!=target.faction or row.members.size()+target.members.size()>MAX_MEMBERS: return false
	var assets: Array=target.assets.duplicate()
	for asset: String in row.assets:
		if not asset in assets: assets.append(asset)
	if assets.size()>32: return false
	if not _authorized("merge",{"source":source,"destination":destination,"actor":actor,"source_leader":row.leader,"destination_leader":target.leader}): return false
	_busy=true
	if not _finance({"operation":"move","source":row.treasury,"destination":target.treasury}): _busy=false; return false
	for id: String in row.members:
		if not id in target.members: target.members.append(id)
	target.assets=assets; row.assets.clear()
	row.members.clear(); row.leader=""; row.status="merged"; row.merged_into=destination
	_event(row,"merged",actor,destination); _event(target,"absorbed",actor,source)
	_busy=false
	return true
func dissolve(key: String,actor: String="") -> bool:
	if _busy or not guilds.has(key) or guilds[key].status!="active": return false
	var row: Dictionary=guilds[key]
	if not row.members.is_empty() and not _authorized("dissolve",{"guild_id":key,"actor":actor,"leader":row.leader}): return false
	_busy=true
	if not _finance({"operation":"move","source":row.treasury,"destination":"faction:"+String(row.faction)}): _busy=false; return false
	row.status="dissolved"; row.members.clear(); row.leader=""
	_event(row,"dissolved",actor); _busy=false
	return true
func set_headquarters(key: String,reference: String) -> bool:
	if _busy or not guilds.has(key) or not _text(reference,true): return false
	guilds[key].headquarters=reference; revision+=1; return true
func set_faction_headquarters(key: String,reference: String) -> bool:
	if _busy or not factions.has(key) or not _text(reference,true): return false
	factions[key].headquarters=reference; revision+=1; return true
func relate(key: String,target: String,delta: float) -> bool:
	if _busy or not guilds.has(key) or not guilds.has(target) or key==target or not is_finite(delta): return false
	var row: Dictionary=guilds[key]
	if not row.relationships.has(target) and row.relationships.size()>=24: return false
	row.relationships[target]=clampf(float(row.relationships.get(target,0))+delta,-1,1)
	if absf(float(row.relationships[target]))>=.75: _event(row,"alliance" if row.relationships[target]>0 else "rivalry","",target)
	else: revision+=1
	return true
func record_contract(key: String,quest_id: String,status: String,participant: String) -> void:
	if not guilds.has(key) or not _text(quest_id) or not status in ["completed","failed","expired","cancelled"]: return
	var row: Dictionary=guilds[key]
	row.last_activity=world_seconds
	row.reputation=clampf(float(row.reputation)+(.05 if status=="completed" else -.02),-1,1)
	_event(row,"contract/"+status,participant,quest_id)
func retire(id: String) -> void:
	if _busy: return
	for key: String in memberships_of(id): leave(id,key)
	supports.erase(id)
	for row: Dictionary in supports.values(): row.supporters.erase(id)
	for row: Dictionary in factions.values():
		if row.leader==id:
			var candidate:=""
			for guild_row: Dictionary in guilds_for_faction(row.id):
				for member: String in guild_row.members:
					if _native(member) and candidate.is_empty(): candidate=member
			row.leader=candidate; _event(row,"faction_succession",candidate,id)
func advance_to(now: float) -> bool:
	if _busy or not _time(now) or now<world_seconds: return false
	world_seconds=now
	if guilds.is_empty() or now<next_review: return true
	# One organization per review call; no population-by-guild scan per frame.
	var keys: Array=guilds.keys()
	var row: Dictionary=guilds[keys[review_cursor%keys.size()]]
	review_cursor=(review_cursor+1)%keys.size(); next_review=now+3600.0
	if row.status=="active":
		for id: String in row.members.duplicate():
			if _person(id).is_empty(): leave(id,row.id)
		if row.leader.is_empty() or not _native(row.leader): _succeed(row)
		elif row.governance in ["election","merit"] and not row.nominations.is_empty(): _succeed(row)
		if row.members.is_empty():
			if float(row.empty_since)<0: row.empty_since=now; revision+=1
			elif now-float(row.empty_since)>=86400*7: dissolve(row.id)
	if row.status!="active": _pending_sweep=row.id
	for founder: String in supports.keys():
		if now-float(supports[founder].at)>86400*30: supports.erase(founder); revision+=1
	return true
func sweep_closed() -> bool:
	if _busy or _pending_sweep.is_empty(): return false
	var key: String=_pending_sweep
	_pending_sweep=""
	if not guilds.has(key) or guilds[key].status=="active": return false
	var row: Dictionary=guilds[key]
	var destination: String="faction:"+String(row.faction)
	var next: String=String(row.merged_into)
	var visited: Dictionary={key:true}
	while not next.is_empty() and guilds.has(next) and not visited.has(next):
		visited[next]=true
		if guilds[next].status=="active": destination=guilds[next].treasury; break
		next=String(guilds[next].merged_into)
	_busy=true
	var moved:=_finance({"operation":"move","source":row.treasury,"destination":destination})
	_busy=false
	return moved
func transaction_active() -> bool: return _busy
func serialize() -> Dictionary:
	return {"version":1,"factions":factions.duplicate(true),"guilds":guilds.duplicate(true),"supports":supports.duplicate(true),"world_seconds":world_seconds,"next_id":next_id,"next_review":next_review,"review_cursor":review_cursor}
func restore(data: Variant) -> bool:
	if _busy: return false
	if data==null:
		factions.clear(); guilds.clear(); supports.clear(); world_seconds=0; next_id=1; next_review=0; review_cursor=0; _pending_sweep=""; revision+=1; return true
	var decoded:=validate(data)
	if decoded.is_empty(): return false
	factions=decoded.factions; guilds=decoded.guilds; supports=decoded.supports
	world_seconds=decoded.world_seconds; next_id=decoded.next_id; next_review=decoded.next_review; review_cursor=decoded.review_cursor; revision+=1
	_pending_sweep=""
	return true
static func _text(value: Variant,empty: bool=false) -> bool: return Item.valid_text(value,empty,128) and not "\n" in String(value) and not "\r" in String(value)
static func _time(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=9e12
static func _number(value: Variant,low: float,high: float) -> bool: return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func _history(rows: Variant,now: float) -> bool:
	if not rows is Array or rows.size()>MAX_HISTORY: return false
	for row: Variant in rows:
		if not row is Dictionary or row.size()!=4 or not _text(row.get("type")) or not _time(row.get("at")) or float(row.at)>now or not _text(row.get("actor"),true) or not _text(row.get("target"),true): return false
	return true
static func _relations(rows: Variant) -> bool:
	if not rows is Dictionary or rows.size()>24: return false
	for key: Variant in rows:
		if not _text(key) or not _number(rows[key],-1,1): return false
	return true
static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size()!=8 or not Item.whole_number(data.get("version"),1,1) or not _time(data.get("world_seconds")) or not _time(data.get("next_review")) or not Item.whole_number(data.get("next_id"),1,1000000000) or not Item.whole_number(data.get("review_cursor"),0,MAX_GUILDS): return {}
	if not data.get("factions") is Dictionary or data.factions.size()>64 or not data.get("guilds") is Dictionary or data.guilds.size()>MAX_GUILDS or not data.get("supports") is Dictionary or data.supports.size()>MAX_SUPPORT: return {}
	var result: Dictionary=Item.json_copy(data)
	var highest:=0
	for key: Variant in data.guilds:
		var row: Variant=data.guilds[key]
		if not _text(key) or not row is Dictionary or row.size()!=22 or row.get("id")!=key or not _text(row.get("name")) or not data.factions.has(row.get("faction")) or row.get("classification") not in ["generalist","specialist"] or not _text(row.get("specialty")) or row.get("governance") not in GOVERNANCE or row.get("status") not in ["active","merged","dissolved"] or row.get("treasury")!="guild:"+String(key): return {}
		if String(key).begins_with("guild_"):
			var serial:=String(key).trim_prefix("guild_")
			if not serial.is_valid_int() or String(key)!="guild_"+str(int(serial)) or int(serial)<1: return {}
			highest=maxi(highest,int(serial))
		if not row.get("members") is Array or row.members.size()>MAX_MEMBERS or not _text(row.get("leader"),true) or not _text(row.get("headquarters"),true) or not _text(row.get("successor"),true) or not _text(row.get("parent"),true) or not _text(row.get("merged_into"),true): return {}
		var seen: Dictionary={}
		for id: Variant in row.members:
			if not _text(id) or seen.has(id): return {}
			seen[id]=true
		if not row.leader.is_empty() and not seen.has(row.leader): return {}
		if not row.successor.is_empty() and not seen.has(row.successor): return {}
		if row.status!="active" and (not row.members.is_empty() or not row.leader.is_empty()): return {}
		if not row.parent.is_empty() and not data.guilds.has(row.parent): return {}
		if row.status=="merged" and (row.merged_into==key or not data.guilds.has(row.merged_into)): return {}
		if row.status=="merged":
			var destination: String=row.merged_into
			var path: Dictionary={key:true}
			while not destination.is_empty():
				if path.has(destination) or not data.guilds.has(destination) or data.guilds[destination].faction!=row.faction: return {}
				path[destination]=true
				destination=String(data.guilds[destination].get("merged_into",""))
		if row.status!="merged" and not row.merged_into.is_empty(): return {}
		if not row.get("nominations") is Dictionary or row.nominations.size()>MAX_MEMBERS: return {}
		for voter: Variant in row.nominations:
			if not seen.has(voter) or not seen.has(row.nominations[voter]): return {}
		if not row.get("assets") is Array or row.assets.size()>32: return {}
		for asset: Variant in row.assets:
			if not _text(asset): return {}
		if not _time(row.get("founded_at")) or float(row.founded_at)>float(data.world_seconds) or not _time(row.get("last_activity")) or float(row.last_activity)>float(data.world_seconds) or not _number(row.get("empty_since"),-1,float(data.world_seconds)) or not _number(row.get("reputation"),-1,1) or not _relations(row.get("relationships")) or not _history(row.get("history"),data.world_seconds): return {}
	for key: Variant in data.factions:
		var row: Variant=data.factions[key]
		if not _text(key) or not row is Dictionary or row.size() not in [9,10] or row.get("id")!=key or not _text(row.get("name")) or not _text(row.get("purpose")) or not _text(row.get("leader"),true) or row.get("governance") not in GOVERNANCE or not _number(row.get("reputation"),-1,1) or not _relations(row.get("relationships")) or not _history(row.get("history"),data.world_seconds) or not row.get("guilds") is Array or row.guilds.size()>MAX_GUILDS or not _text(row.get("headquarters",""),true): return {}
		if row.size()==10 and not row.has("headquarters"): return {}
		result.factions[key].headquarters=String(row.get("headquarters",""))
		var seen: Dictionary={}
		for id: Variant in row.guilds:
			if seen.has(id) or not data.guilds.has(id) or data.guilds[id].faction!=key: return {}
			seen[id]=true
		for id: String in data.guilds:
			if data.guilds[id].faction==key and not seen.has(id): return {}
	for founder: Variant in data.supports:
		var row: Variant=data.supports[founder]
		if not _text(founder) or not row is Dictionary or row.size()!=4 or not data.factions.has(row.get("faction")) or not _text(row.get("specialty")) or not _time(row.get("at")) or row.at>data.world_seconds or not row.get("supporters") is Dictionary or row.supporters.size()>16: return {}
		for id: Variant in row.supporters:
			if not _text(id) or id==founder or not _number(row.supporters[id],.5,1): return {}
	if highest>=int(data.next_id): return {}
	result.world_seconds=float(data.world_seconds); result.next_review=float(data.next_review); result.next_id=int(data.next_id); result.review_cursor=int(data.review_cursor)
	return result
