extends Node
## Authority adapters shared by physical conversations and bounded model life.
## Text is presentation; receipts, inventory and verified arrivals decide effects.
const Item=preload("res://scripts/item_instance.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const IntentTrade=preload("res://scripts/intent_trade.gd")
var world: Node3D
var trade:=IntentTrade.new()
var initialized:=false
var _bootstrap_access:=false
var _delivery_access: Dictionary={}
var _proofs: Dictionary={}
var _clock:=0.0
var _speaker:=""
var _point: Dictionary={}
var _source: WeakRef
var _source_wait:=0.0
var _source_state:=""
var _busy:=false
var _post_day:=-1
var _pending_cases: Array[String]=[]

func _society(): return world.civilization
func _economy(): return world.civilian_services.economy
func _quests(): return world.quest_system
func _now() -> float: return float(_society().world_seconds)
func _registry(): return _society().registry
func _contact() -> String: return String(_registry().slots.get("service/tavern_adventurer",""))
func _day() -> int: return floori(_now()/float(_registry().config.day_seconds))

func _ready() -> void:
	name="CivilizationInteractions"
	trade.world=world
	world.quest_system.setup({"identity":identity,"authorize":authorize_quest,"finance":finance_quest,"outcome":quest_outcome})
	world.law.identity_provider=identity
	world.communication.identity_provider=identity
	world.communication.context_provider=conversation_nodes
	world.communication.outcome_handler=handle_message
	world.communication.interrupt_guard=conversation_invalid
	world.communication.opened.connect(world.inventory_session._opened)
	world.communication.closed.connect(world.inventory_session._closed)
	world.communication.closed.connect(trade.clear)
	world.communication.closed.connect(_release_source)
	world.quest_system.changed.connect(world.inventory_session._dirty)
	world.law.changed.connect(world.inventory_session._dirty)
	world.law.case_recorded.connect(_case_recorded)
	_economy().transaction_committed.connect(transaction_committed)
	if is_instance_valid(world.theft_reactions): world.theft_reactions.crime_observed.connect(observe_crime)
	_society().identities_replaced.connect(_quests().on_replacements)
	world.player.defeated.connect(func(): world.communication.close_conversation("defeated"))
	call_deferred("_start")

func _start() -> void:
	while is_inside_tree() and (not _society().ready_for_simulation or world.inventory_session._checkpoint_pending): await get_tree().physics_frame
	if is_inside_tree() and not initialized: bootstrap()

func restored_state(has_civic_state: bool) -> void:
	# A current checkpoint already contains its complete contracts and funding.
	# Loading it cannot publish jobs, transfer capital or enroll extra members.
	initialized=has_civic_state
	trade.clear()
	_post_day=_day() if has_civic_state else -1
	_pending_cases.clear()
	for entry: Dictionary in world.law.open_cases(): _pending_cases.append(String(entry.id))
	if not has_civic_state: bootstrap()

func identity(id: String) -> Dictionary:
	if id=="player": return {"id":id,"name":"Traveler","kind":"player","active":true}
	if id=="avat_ar": return {"id":id,"name":"Avat Ar","kind":"unique","active":true,"merchant":true}
	if id.begins_with("board/") or id.begins_with("faction/"):
		var key:=id.get_slice("/",1)
		if _quests().model.factions.has(key) and (not id.begins_with("board/") or key!="underworld"):
			return {"id":id,"name":_quests().model.factions[key].name,"kind":"institution","active":true}
	var record: Dictionary=_registry().records.get(id,{})
	if record.is_empty(): return {}
	var result:=record.duplicate(false)
	result.kind="code_form"
	return result

func bootstrap() -> bool:
	if _busy or not _society().ready_for_simulation or _economy().transaction_active(): return false
	_busy=true
	_bootstrap_access=true
	var active: Array=_registry().active_ids()
	var founder:=_contact()
	var index:=0
	for faction: String in ["security","commerce","exploration","underworld"]:
		# Registered faction accounts are the persistent migration marker. Capital
		# is transferred from existing wallets, never minted on restore/entry.
		if faction not in _economy().factions:
			if not _economy().register_faction(faction): _busy=false; _bootstrap_access=false; return false
			for n in range(6 if faction!="underworld" else 1):
				var donor: String=founder if faction=="underworld" else String(active[(index+n)%active.size()])
				var amount:=mini(40 if faction=="underworld" else 10,_economy().balance("resident:"+donor))
				if amount>0: _economy().transfer("resident:"+donor,"faction:"+faction,amount,"Founding guild contribution")
				if faction=="underworld": _quests().introduce(donor,donor)
				_quests().join(donor,faction)
			index+=6
	# Existing Adventurers retain their established affiliation as exploration
	# members; new residents choose affiliations during ordinary decisions.
	for id: String in active:
		if _registry().records[id].get("guild","")=="adventurers_guild": _quests().join(id,"exploration")
	if not founder.is_empty():
		_quests().introduce(founder,founder)
		_quests().join(founder,"underworld")
	_bootstrap_access=false
	initialized=true
	_post_day=-1
	_busy=false
	post_opportunities()
	return true

func _node(intent: String,label: String,parameters: Dictionary={},enabled: bool=true,subject: String="") -> Dictionary:
	return {"intent":intent,"label":label,"parameters":parameters,"enabled":enabled,"subject_id":subject}

func begin_for_source(source: Node) -> bool:
	var id:=String(_society().id_for_source(source))
	if id.is_empty(): return false
	world.communication.close_conversation("replaced")
	_source=weakref(source); _point={}; _speaker=id
	_source_wait=float(source.get("wait")) if source.get("wait")!=null else 0.0
	_source_state=String(source.get("state")) if source.get("state")!=null else ""
	return world.communication.begin(id,"player",{"branch":"greeting"})

func begin_service(point: Dictionary,id: String) -> bool:
	if not initialized: return false
	world.communication.close_conversation("replaced")
	_point=point; _source=null
	_speaker="board/"+String(point.faction) if point.kind=="board" else id
	if _speaker.is_empty(): return false
	return world.communication.begin(_speaker,"player",{"branch":"greeting","faction":String(point.get("faction",""))})

func begin_merchant(point: Dictionary) -> bool:
	world.communication.close_conversation("replaced")
	_point=point; _source=null; _speaker="avat_ar"
	return world.communication.begin("avat_ar","player",{"branch":"greeting","merchant":true})

func conversation_invalid() -> bool:
	if world.player.health<=0 or world.player.transition_locked or world.inventory_session._loading: return true
	if world.start_menu.is_open or world.inventory_session.ui.is_open or world.inventory_session.shop.is_open: return true
	if not _point.is_empty():
		return not (world.glyphic_wonders._near(_point) if _speaker=="avat_ar" else world.civilian_services.near(_point))
	var source: Node=_source.get_ref() if _source!=null else null
	return not is_instance_valid(source) or source.get_world_3d()!=world.player.get_world_3d() or source.global_position.distance_to(world.player.global_position)>5 or not identity(_speaker).get("active",false) or _society().autonomy._unavailable(_speaker,source)

func _release_source() -> void:
	var source: Node=_source.get_ref() if _source!=null else null
	if is_instance_valid(source) and source.get("state")=="talking":
		source.set("state",_source_state)
		if source.get("wait")!=null: source.set("wait",minf(_source_wait,.5))
	_source=null

func _hold_source() -> void:
	if not world.communication.is_open or _source==null: return
	var source: Node=_source.get_ref()
	if not is_instance_valid(source): return
	if source.get("wait")!=null: source.set("wait",maxf(float(source.get("wait")),.4))
	if source.get("state")!=null: source.set("state","talking")
	if source.get("caption") is Label3D: source.caption.hide()
	if source.has_method("face"): source.face(world.player.global_position,.2)

func conversation_nodes(speaker: String,listener: String,branch: String,context: Dictionary) -> Array:
	var npc:=listener if speaker=="player" else speaker
	var faction:=String(context.get("faction",""))
	if npc.begins_with("board/"): faction=npc.get_slice("/",1)
	if branch in ["trade","sell"]:
		var options: Array=trade.nodes("player",npc) if branch=="sell" else trade.nodes(npc,"player")
		if branch=="trade": options.append(_node("offer_item","Offer one of my items",{"branch":"sell"}))
		options.append(_node("return","Back"))
		return options
	if branch=="identity":
		return [_node("request_trade","Trade owned goods"),_node("ask_work","Work and favors"),_node("ask_rumor","Known news"),_node("ask_guild","Affiliations"),_node("return","Back"),_node("farewell","Leave")]
	if branch=="quests":
		var rows: Array=_quests().available("player",faction)
		var options: Array=[]
		var page:=int(context.get("page",0))
		for row: Dictionary in rows.slice(page*4,page*4+4):
			if faction.is_empty() and row.issuer!=npc: continue
			var title:=String(row.title)
			if title.length()>74: title=title.left(73)+"…"
			var eligible: bool=row.faction.is_empty() or _quests().is_member("player",row.faction)
			if row.objective.service=="investigate" and world.law.cases.get(String(row.objective.target_id),{}).get("offender")=="player": eligible=false
			options.append(_node("accept_quest",title+" · "+str(row.reward)+" coins",{"quest_id":row.id},eligible,row.id))
		if rows.size()>(page+1)*4: options.append(_node("ask_work","More work",{"page":page+1,"faction":faction}))
		options.append(_node("return","Back"))
		return options
	if branch=="progress":
		var options: Array=[]
		for row: Dictionary in _quests().for_participant("player",false).slice(0,4):
			var objective: Dictionary=row.objective
			options.append(_node("report_quest",String(row.title)+" · "+str(objective.progress)+"/"+str(objective.count),{"quest_id":row.id},true,row.id))
		options.append(_node("return","Back")); return options
	if branch=="guilds":
		var options: Array=[]
		for key: String in ["security","commerce","exploration"]:
			options.append(_node("accept_guild",("Member: " if _quests().is_member("player",key) else "Join ")+String(_quests().model.factions[key].name),{"faction":key}))
		if _quests().model.introductions.has("player"): options.append(_node("accept_guild","Private affiliation",{"faction":"underworld"}))
		options.append(_node("return","Back")); return options
	if npc=="avat_ar":
		return [_node("browse_goods","Browse permanent glyphs"),_node("request_info","About Glyphic Wonders"),_node("ask_identity","The First Merchant"),_node("ask_rumor","What's new?"),_node("farewell","Leave")]
	if not faction.is_empty():
		return [_node("ask_work","Browse funded contracts",{"faction":faction}),_node("accept_guild",("Already a member" if _quests().is_member("player",faction) else "Join ")+String(_quests().model.factions[faction].name),{"faction":faction}),_node("report_quest","My work"),_node("ask_guild","About this guild",{"faction":faction}),_node("farewell","Leave")]
	var options: Array=[_node("request_trade","Discuss trading"),_node("ask_work","Work and favors"),_node("report_quest","My work"),_node("ask_guild","Guild affiliations"),_node("ask_rumor","Known news"),_node("farewell","Leave")]
	if _point.get("kind") in ["reception","bartender"]: options[0]=_node("browse_goods","Rooms and crystal sales" if _point.kind=="reception" else "Meals and drinks")
	if npc==_contact() and _friend(npc,"player")>=.1:
		options[4]=_node("request_help","A private introduction",{"topic":"introduction"})
	elif not _point.is_empty() and _point.kind=="adventurer": options[0]=_node("ask_identity","Ask about their plans")
	return options

func _friend(id: String,other: String) -> float: return float(_registry().records.get(id,{}).get("relationships",{}).get(other,0.0))

func _reply(intent: String,parameters: Dictionary={},extra: Dictionary={}) -> Dictionary:
	var result:={"accepted":true,"reply":{"intent":intent,"parameters":parameters},"facts":[parameters]}
	result.merge(extra,true)
	return result

func handle_message(message: Dictionary) -> Dictionary:
	var actor:=String(message.speaker_id)
	var listener:=String(message.listener_id)
	if not identity(actor).get("active",false) or not identity(listener).get("active",false): return {"accepted":false}
	var intent:=String(message.intent)
	var p: Dictionary=message.parameters
	var npc:=actor if listener=="player" else listener
	var record: Dictionary=_registry().records.get(npc,{})
	if actor=="player" and (not world.communication.is_open or message.conversation_id!=world.communication.conversation_id or npc!=_speaker or conversation_invalid()): return {"accepted":false}
	if intent=="offer_item" and p.get("branch")=="sell": return _reply("inform",{"detail":"Choose an owned item to offer."},{"branch":"sell"})
	if intent in ["ask_price","offer_trade","propose_price","accept_trade","decline_trade","offer_item"]:
		# NPC replies to an already settled player choice are presentation, not
		# a second request to settle the same offer in the opposite direction.
		if listener=="player": return {"accepted":true}
		var outcome: Dictionary=trade.handle(message)
		if outcome.get("nodes") is Array: outcome.nodes.append(_node("return","Back"))
		return outcome
	match intent:
		"greet","thank","apologize","affection":
			if not record.is_empty(): _society().record_interaction(npc,"conversation",listener if actor==npc else actor)
			if actor!="player" and not _registry().records.get(actor,{}).is_empty(): _society().record_interaction(actor,"conversation",listener)
			_interview(actor,listener)
			return _reply("greet",{"name":identity(npc).name,"goal":record.get("current_goal","trade")})
		"farewell": return _reply("farewell",{}, {"close":true})
		"return": return _reply("acknowledge",{}, {"branch":"greeting","context":{"page":0}})
		"request_trade","browse_goods":
			if actor=="player" and not _point.is_empty() and (npc=="avat_ar" or _point.get("kind") in ["reception","bartender"]):
				call_deferred("_open_services",npc)
				return _reply("agree",{}, {"close":true})
			return _reply("inform",{"detail":"Inspect actual goods or offer an item from your inventory. Accepted trades transfer existing coins and owned stock."},{"branch":"trade"})
		"ask_identity":
			if npc=="avat_ar": return _reply("introduce",{"name":"Avat Ar","role":"The First Merchant","detail":"I supplied food and water after the first Great Blessings. Trade gave those blessings a purpose."})
			return _reply("introduce",{"name":identity(npc).name,"role":record.get("occupation","resident"),"goal":record.get("current_goal","rest")},{"branch":"identity"})
		"request_info","ask_guild":
			if npc=="avat_ar": return _reply("inform",{"detail":"The displays rotate; Health and Shield Glyphs remain at my counter. Purchases remove coins from circulation."})
			var faction:=String(p.get("faction",npc.get_slice("/",1) if npc.begins_with("board/") else ""))
			if _quests().model.factions.has(faction) and (faction!="underworld" or _quests().model.introductions.has(actor)):
				var detail:=String(_quests().model.factions[faction].purpose)
				if faction=="security": detail+=" Your wanted level: "+str(world.law.wanted_level(actor))+". Evidence is investigated separately from trade and economic XP."
				return _reply("inform",{"name":_quests().model.factions[faction].name,"detail":detail,"treasury":_economy().balance("faction:"+faction)})
			return _reply("inform",{"detail":"Public contracts are visible to everyone. Membership is required to accept them."},{"branch":"guilds"})
		"accept_guild":
			var key:=String(p.get("faction",""))
			if not _quests().join(actor,key): return _reply("refuse",{"reason":"A trusted private introduction is required."})
			if actor!="player": _registry().remember(actor,"guild",key,"Joined "+String(_quests().model.factions[key].name)+".",.7)
			return _reply("agree",{"faction":key,"detail":"Membership recorded. Funded work is available on the board."})
		"request_help":
			if actor=="player" and npc==_contact() and p.get("topic")=="introduction" and _quests().introduce(actor,npc):
				return _reply("agree",{"detail":"A trusted contact has privately introduced you. You may join and discuss private work here."},{"branch":"guilds"})
			return _reply("refuse",{"reason":"Trust grows through help that is actually delivered."})
		"ask_work","ask_quest","offer_help":
			var faction:=String(p.get("faction","underworld" if npc==_contact() and _quests().is_member(actor,"underworld") else ""))
			if not record.is_empty() and faction.is_empty(): request_favor(npc,actor)
			if actor!="player":
				for row: Dictionary in _quests().available(actor,faction):
					if faction.is_empty() and row.issuer!=listener: continue
					if _quests().accept(row.id,actor,_now()): return _reply("offer_work",{"quest_id":row.id,"reward":row.reward,"detail":row.title})
				return _reply("refuse",{"reason":"No suitable funded work is available."})
			return _reply("offer_work",{"detail":"Rewards are held in escrow. Deliveries consume the requested item; arrivals must be reached in person."},{"branch":"quests","context":{"faction":faction,"page":int(p.get("page",0))}})
		"accept_quest","accept_work":
			var id:=String(p.get("quest_id",""))
			var proposed: Dictionary=_quests().model.instances.get(id,{})
			if proposed.get("objective",{}).get("service")=="investigate" and world.law.cases.get(String(proposed.objective.target_id),{}).get("offender")==actor:
				return _reply("refuse",{"reason":"An offender cannot investigate their own case."})
			if not _quests().accept(id,actor,_now()): return _reply("refuse",{"reason":"Membership, funds or availability changed."})
			var row: Dictionary=_quests().model.instances[id]
			if row.objective.service=="investigate": world.law.investigate(String(row.objective.target_id),actor)
			return _reply("agree",{"quest_id":id,"detail":describe_objective(row),"reward":row.reward})
		"report_quest":
			var id:=String(p.get("quest_id",""))
			if id.is_empty(): return _reply("inform",{"detail":"Select work to inspect or deliver. Survey and patrol objectives complete on verified arrival."},{"branch":"progress"})
			var row: Dictionary=_quests().model.instances.get(id,{})
			if row.is_empty() or row.participant!=actor: return {"accepted":false}
			_interview(actor,npc)
			var delivered:=complete_delivery(row,actor)
			return _reply("thank" if delivered else "inform",{"quest_id":id,"detail":describe_objective(row),"status":row.status})
		"ask_rumor":
			var memories: Array=record.get("memories",[])
			for entry: Dictionary in memories:
				if entry.type in ["discovery","guild","quest","work","purchase"]:
					return _reply("share_rumor",{"fact_id":String(entry.type)+"/"+String(entry.target),"detail":entry.summary})
			return _reply("inform",{"detail":"I have no first-hand news to share."})
		"threaten","hostility":
			if not record.is_empty(): _society().record_interaction(npc,"threat",actor,false)
			if listener!="avat_ar": world.law.record_crime({"event_id":message.event_id,"kind":"threat","offender":actor,"victim":listener,"witnesses":[listener]})
			return _reply("refuse",{"reason":"Threats are remembered."})
		"share_rumor","share_info":
			# Sharing requires an existing first-hand semantic memory, not a text
			# claim supplied by the caller. Exact knowledge is copied with source.
			for entry: Dictionary in _registry().records.get(actor,{}).get("memories",[]):
				if String(entry.type)+"/"+String(entry.target)==p.get("fact_id"):
					_registry().remember(listener,"heard",actor+"/"+String(entry.target),String(entry.summary),.35)
					return _reply("acknowledge",{"fact_id":p.fact_id,"source":actor})
			return {"accepted":false}
	return _reply("acknowledge")

func _open_services(npc: String) -> void:
	world.communication.close_conversation("services")
	if npc=="avat_ar": world.glyphic_wonders._counter()
	else: world.civilian_services._home()

func describe_objective(row: Dictionary) -> String:
	var objective: Dictionary=row.objective
	if row.status=="completed": return "Completed. "+str(row.reward)+" coins transferred from the issuer's escrow."
	if objective.service=="investigate":
		var entry: Dictionary=world.law.cases.get(String(objective.target_id),{})
		var names: Array[String]=[]
		for id: String in entry.get("witnesses",[]): names.append(String(identity(id).get("name",id)))
		return "Interview a recorded witness about "+String(entry.get("kind","the case"))+": "+", ".join(names)+". Speak to them or report this work while nearby."
	if row.kind=="delivery": return "Bring "+str(objective.count)+" "+Catalog.get_definition(StringName(objective.item_type)).display_name+" to "+String(identity(row.issuer).get("name","the guild"))+" and report the delivery."
	var point:=destination(String(objective.target_id))
	return String(row.title)+" at "+String(objective.target_id)+(" · X %.0f / Z %.0f" % [point.x,point.z] if point.is_finite() else "")+"."

func authorize_quest(operation: String,payload: Dictionary) -> bool:
	match operation:
		"event": return _proofs.has(payload.get("event_id")) and _proofs[payload.event_id]==payload
		"introduce": return _bootstrap_access or payload.get("contact_id")==_contact() and _quests().is_member(_contact(),"underworld") and _friend(_contact(),String(payload.get("participant","")))>=.1
		"publish","delegate":
			if not _busy: return false
			var issuer:=String(payload.get("issuer",""))
			return payload.get("source")==("faction:"+issuer.trim_prefix("faction/") if issuer.begins_with("faction/") else "resident:"+issuer)
		"fail": return payload.get("reason") in ["retired","evidence_resolved"]
	return false

func finance_quest(request: Dictionary) -> bool:
	match String(request.operation):
		"reserve": return _economy().reserve_contract(request.quest_id,request.source,int(request.amount))
		"pay": return _economy().settle_contract(request.quest_id,_economy().owner_id if request.beneficiary=="player" else request.beneficiary,String(request.service),String(request.legality))
		"refund": return _economy().refund_contract(request.quest_id)
	return false

func quest_outcome(result: Dictionary) -> void:
	for id: String in [String(result.issuer),String(result.participant)]:
		if _registry().records.get(id,{}).get("active",false):
			_registry().remember(id,"quest",String(result.quest_id),String(result.status)+" "+String(result.kind)+" obligation.",.7)
	if result.status=="completed":
		if _registry().records.get(result.issuer,{}).get("active",false): _registry().relate(result.issuer,result.participant,.1)
		if result.participant=="player": world.inventory_session.show_notice("Work completed · "+str(result.reward)+" Glyph Coins",5)

func _event(event: Dictionary) -> Array:
	_proofs[event.event_id]=event.duplicate(true)
	var result: Array=_quests().consume_event(event)
	_proofs.erase(event.event_id)
	return result

func delivery_authorized(payload: Dictionary) -> bool: return not _delivery_access.is_empty() and payload==_delivery_access

func complete_delivery(row: Dictionary,actor: String) -> bool:
	if row.status!="active" or row.kind!="delivery" or row.participant!=actor: return false
	if not _recipient_near(actor,String(row.objective.recipient_id)): return false
	var inventory: Node=world.player.inventory if actor=="player" else _economy().npc_store(actor)
	if not is_instance_valid(inventory): return false
	for item: Resource in inventory.items.values():
		if String(item.item_type_id)!=String(row.objective.item_type): continue
		var qty:=mini(int(item.quantity),int(row.objective.count)-int(row.objective.progress))
		var sender:=String(_economy().owner_id) if actor=="player" else actor
		var event_id:="delivery/"+Item.new_id()
		_delivery_access={"sender_id":sender,"recipient_id":String(row.objective.recipient_id),"instance_id":String(item.instance_id),"quantity":qty,"related_event_id":event_id}
		var receipt: Dictionary=_economy().deliver_item(sender,row.objective.recipient_id,item.instance_id,qty,event_id,row.legality)
		_delivery_access={}
		return not receipt.is_empty()
	return false

func transaction_committed(receipt: Dictionary) -> void:
	if receipt.get("context")=="item_transfer":
		var actor:=String(receipt.asset_sender_id)
		if actor==_economy().owner_id: actor="player"
		_event({"event_id":String(receipt.transaction_id),"event_type":"delivery","actor_id":actor,"target_id":"","timestamp":_now(),"item_type":String(receipt.asset_type),"recipient_id":String(receipt.asset_receiver_id),"quantity":int(receipt.quantity)})
	if receipt.get("context")=="item_theft":
		var thief:=String(receipt.asset_receiver_id)
		var victim:=String(receipt.asset_sender_id)
		var witnesses:=nearby_witnesses(thief,[thief])
		if _recipient_near(thief,victim) and victim not in witnesses: witnesses.append(victim)
		world.law.record_crime({"event_id":String(receipt.transaction_id),"kind":"theft","offender":thief,"victim":victim,"witnesses":witnesses,"asset_id":String(receipt.asset_id),"transaction_id":String(receipt.transaction_id)})
	# Criminality is not evidence by itself. Only actual nearby witnesses below
	# create cases; every genuine receipt remains eligible for civilian XP.
	if receipt.get("legality")=="illegal" and receipt.get("context")=="item_sale":
		var seller:=String(receipt.asset_sender_id)
		var buyer:=String(receipt.asset_receiver_id)
		if seller==_economy().owner_id: seller="player"
		if buyer==_economy().owner_id: buyer="player"
		var witnesses:=nearby_witnesses(seller,[seller,buyer])
		if not witnesses.is_empty(): world.law.record_crime({"event_id":String(receipt.transaction_id),"kind":"stolen_trade","offender":seller,"victim":"","witnesses":witnesses,"asset_id":String(receipt.asset_id),"transaction_id":String(receipt.transaction_id)})

func observe_crime(event: Dictionary) -> void:
	var offender: Node=event.get("offender")
	var victim: Node=event.get("victim")
	var offender_id:="player" if offender==world.player else String(_society().id_for_source(offender))
	var victim_id:="player" if victim==world.player else String(_society().id_for_source(victim))
	var witnesses: Array=[]
	for source: Node in event.get("witnesses",[]):
		var id:=String(_society().id_for_source(source))
		if not id.is_empty(): witnesses.append(id)
	world.law.record_crime({"event_id":event.event_id,"kind":event.kind,"offender":offender_id,"victim":victim_id,"witnesses":witnesses,"asset_id":String(event.get("asset_id",""))})

func nearby_witnesses(id: String,excluded: Array) -> Array:
	var origin: Vector3=position_for(id)
	if not origin.is_finite(): return []
	var witnesses: Array=[]
	for other: String in _society().autonomy._sources:
		if other in excluded: continue
		var body: Node=_society().autonomy._source(other)
		if not is_instance_valid(body) or not body.is_visible_in_tree() or body.get_world_3d()!=world.player.get_world_3d(): continue
		if origin.distance_to(body.global_position)>15: continue
		var ray:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP,body.global_position+Vector3.UP,1)
		if body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): witnesses.append(other)
		if witnesses.size()>=6: break
	return witnesses

func destination(id: String) -> Vector3:
	if id.begins_with("place/"):
		var point: Variant=world.population.points.get(StringName(id.trim_prefix("place/")))
		if point is Vector3: return world.population.to_global(point)
	return Vector3(INF,INF,INF)

func post_opportunities() -> void:
	if not initialized or _busy or _post_day==_day(): return
	_post_day=_day()
	_busy=true
	var targets: Array=world.population.points.keys()
	if not targets.is_empty():
		for key: String in ["security","commerce","exploration"]:
			var terms:={"need_id":key+"/day/"+str(_day()),"target_id":"place/"+String(targets[posmod((key+str(_day())).hash(),targets.size())])}
			var template:=key+"_service" if key!="exploration" else "exploration_discovery"
			if key=="commerce":
				template="commerce_delivery"; terms={"need_id":key+"/day/"+str(_day()),"item_type":"electron_meal","recipient_id":"guild"}
			elif key=="security": terms.service="patrol"
			_quests().create_contract(template,"faction/"+key,"faction:"+key,terms,_now())
	var contact:=_contact()
	if not contact.is_empty() and _economy().npc_store(contact).count_type(&"electron_draught")==0:
		_quests().create_contract("underworld_delivery","faction/underworld","faction:underworld",{"need_id":"private/day/"+str(_day()),"item_type":"electron_draught","recipient_id":contact},_now())
	_busy=false

func request_favor(issuer: String,participant: String) -> String:
	if _busy or not identity(issuer).get("active",false) or _friend(issuer,participant)<-.2: return ""
	# Delegation begins with an actual missing supply; a satisfied resident
	# cannot request another meal just because someone repeats the question.
	if _economy().npc_store(issuer).count_type(&"electron_meal")>0: return ""
	_busy=true
	var id:=String(_quests().request_work(issuer,"personal_delivery","resident:"+issuer,{"need_id":"meal/day/"+str(_day()),"item_type":"electron_meal","recipient_id":issuer,"eligible":[participant]},_now()))
	_busy=false
	return id

func npc_step(record: Dictionary,state: Dictionary,physical: bool) -> bool:
	if not initialized: return false
	var id:=String(record.id)
	var goal:=String(record.current_goal)
	var affiliations: Array=_quests().model.memberships.get(id,[])
	var joined:=false
	# A private introduction still requires a relationship for model citizens.
	if _friend(_contact(),id)>=.1 and not _quests().model.introductions.has(id): _quests().introduce(id,_contact())
	if _quests().model.introductions.has(id) and float(record.motivations.get("wealth",.5))>.65: _quests().join(id,"underworld")
	if affiliations.is_empty() and goal in ["guild","work","explore"]:
		var best:="exploration" if goal=="explore" else ("commerce" if float(record.motivations.get("wealth",.5))>.65 else "security")
		joined=_quests().join(id,best)
		if joined:
			_registry().remember(id,"guild",best,"Joined "+String(_quests().model.factions[best].name)+".",.7)
			_society().record_event({"event_type":"guild","actor_id":id,"target_id":best,"rarity":"uncommon","event_id":"guild/join/"+id+"/"+best})
			affiliations=_quests().model.memberships.get(id,[])
	if goal in ["work","guild","explore"]:
		for quest: Dictionary in _quests().for_participant(id,false):
			if quest.objective.service=="investigate":
				var entry: Dictionary=world.law.cases.get(String(quest.objective.target_id),{})
				for witness: String in entry.get("witnesses",[]):
					if _recipient_near(id,witness):
						world.communication.send(id,witness,"greet")
						return true
			if quest.kind=="delivery":
				if _economy().npc_store(id).items.is_empty(): _economy().npc_buy_food(id,StringName(quest.objective.item_type))
				if complete_delivery(quest,id): return true
		for faction: String in affiliations:
			for quest: Dictionary in _quests().available(id,faction):
				if quest.objective.service=="investigate" and world.law.cases.get(String(quest.objective.target_id),{}).get("offender")==id: continue
				if _quests().accept(quest.id,id,_now()):
					_registry().remember(id,"quest",quest.id,"Accepted funded "+String(quest.kind)+" work.",.6)
					return true
	if goal=="trade" and criminal_opportunity(record,state,physical): return true
	if goal=="socialize":
		var ids: Array=_registry().active_ids()
		var peer:=String(ids[posmod(id.hash()+int(state.turn),ids.size())])
		if peer==id: return false
		var near: bool=position_for(id).distance_to(position_for(peer))<9
		if physical and not near: return false
		var choice: Dictionary=world.communication.choose_autonomous(record,identity(peer),{"nodes":[_node("greet","Greet"),_node("ask_work","Find work"),_node("offer_help","Offer assistance")]},int(state.turn))
		if choice.is_empty(): return false
		var outcome: Dictionary=world.communication.send(id,peer,String(choice.intent),choice.parameters,{},near and not world.communication.is_open)
		return outcome.get("accepted",false)
	return joined

func arrived(id: String,target: String) -> void:
	if not initialized or not identity(id).get("active",false): return
	var position: Vector3=position_for(id)
	var point:=destination(target)
	if not point.is_finite() or not position.is_finite() or position.distance_to(point)>5: return
	var submitted: Dictionary={}
	for row: Dictionary in _quests().for_participant(id,false):
		if row.objective.target_id!=target or row.kind not in ["service","discovery"]: continue
		var key:=String(row.kind)+"/"+String(row.objective.service)
		if submitted.has(key): continue
		submitted[key]=true
		# A stationary radius poll is one survey/patrol visit, not a new service
		# every frame. One proof may legitimately satisfy independent contracts.
		_event({"event_id":"arrival/"+id+"/"+target+"/"+str(_day())+"/"+key,"event_type":row.kind,"actor_id":id,"target_id":target,"timestamp":_now(),"service":row.objective.service,"quantity":1})

func _process(delta: float) -> void:
	_hold_source()
	_clock-=delta
	if _clock>0 or not initialized or world.inventory_session._loading or _society().transaction_active(): return
	_clock=.75
	_quests().advance_to(_now())
	_publish_cases()
	if world.dungeon_travel.active_location==world.dungeon_travel.OUTSIDE and world.player.health>0:
		for row: Dictionary in _quests().for_participant("player",false):
			if row.kind in ["service","discovery"]: arrived("player",row.objective.target_id)
	post_opportunities()
	_economy().prune_contracts(_quests().model.instances.keys())

func position_for(id: String) -> Vector3:
	if id=="player": return world.player.global_position
	if id=="guild": return world.civilian_services.establishments.receptionist_anchor.global_position
	var point: Vector3=_society().autonomy.shopping_position(id)
	if point.is_finite(): return point
	for source: Node3D in world.civilian_services._people:
		if _society().id_for_source(source)==id: return source.global_position
	return Vector3(INF,INF,INF)

func _recipient_near(actor: String,recipient: String) -> bool:
	var from:=position_for(actor)
	var to:=position_for(recipient)
	if not from.is_finite() or not to.is_finite() or from.distance_to(to)>8: return false
	if actor=="player" and world.dungeon_travel.active_location!=world.dungeon_travel.OUTSIDE: return false
	return true

func preferred_destination(id: String) -> String:
	for row: Dictionary in _quests().for_participant(id,false):
		if row.objective.service=="investigate":
			var entry: Dictionary=world.law.cases.get(String(row.objective.target_id),{})
			for witness: String in entry.get("witnesses",[]):
				var witness_point:=position_for(witness)
				if witness_point.is_finite(): return _nearest_destination(witness_point)
		if row.kind in ["service","discovery"]: return String(row.objective.target_id)
		if row.kind=="delivery":
			var target:=position_for(String(row.objective.recipient_id))
			return _nearest_destination(target)
	return ""

func _nearest_destination(target: Vector3) -> String:
	var closest:=""
	var distance:=INF
	for key: StringName in world.population.points:
		var d: float=world.population.to_global(world.population.points[key]).distance_squared_to(target)
		if d<distance: distance=d; closest="place/"+String(key)
	return closest

func socialize(a: String,b: String,physical: bool) -> bool:
	if not initialized or a==b or not identity(a).get("active",false) or not identity(b).get("active",false): return false
	var near: bool=position_for(a).distance_to(position_for(b))<9
	if physical and not near: return false
	var options: Array=[_node("greet","Greet"),_node("ask_work","Ask for work"),_node("offer_help","Offer help")]
	for memory: Dictionary in _registry().records[a].get("memories",[]):
		if memory.type in ["discovery","guild","quest","purchase"]:
			options.append(_node("share_rumor","Share known news",{"fact_id":String(memory.type)+"/"+String(memory.target),"detail":String(memory.summary)}))
			break
	var choice: Dictionary=world.communication.choose_autonomous(identity(a),identity(b),{"nodes":options},int(_society().autonomy._state(a).turn))
	if choice.is_empty(): return false
	var result: Dictionary=world.communication.send(a,b,String(choice.intent),choice.parameters,{},near and not world.communication.is_open)
	return result.get("accepted",false)

func criminal_opportunity(record: Dictionary,state: Dictionary,_physical: bool) -> bool:
	var id:=String(record.id)
	var wealth:=float(record.motivations.get("wealth",.5))
	var security:=float(record.motivations.get("security",.5))
	if wealth<.65 or security>.4 or world.law.wanted_level(id)>=3: return false
	var peers: Array=_registry().active_ids()
	var other:=String(peers[posmod((id+str(state.turn)).hash(),peers.size())])
	if other==id or not _recipient_near(id,other): return false
	var inventory: Node=_economy().npc_store(id)
	for item: Resource in inventory.items.values():
		if not item.custom_properties.has("stolen_from"): continue
		# Risk and trust affect whom a thief approaches. A sale moves an actual
		# marked item and the buyer's existing coins, independent of XP/law.
		if _friend(id,other)<-.1 or float(_registry().records[other].motivations.wealth)<.5: return false
		var offer: Dictionary=world.communication.send(other,id,"ask_price",{"instance_id":String(item.instance_id),"quantity":1,"seller_id":id,"buyer_id":other})
		if not offer.get("accepted",false) or not offer.get("reply",{}).get("parameters",{}).has("quote_token"): return false
		var agreed: Dictionary=world.communication.send(other,id,"accept_trade",offer.reply.parameters)
		if agreed.get("accepted",false):
			_registry().remember(id,"crime",other,"Sold an actually acquired stolen item.",.7)
			return true
	var victim_inventory: Node=_economy().npc_store(other)
	for item: Resource in victim_inventory.items.values():
		if _friend(id,other)>.1 or item.custom_properties.has("stolen_from"): continue
		var receipt: Dictionary=_economy().npc_steal_item(id,other,item.instance_id,1,"theft/"+Item.new_id())
		if not receipt.is_empty():
			_registry().relate(other,id,-.2)
			_registry().remember(other,"theft",id,"A resident took an item from my actual inventory.",.8)
			return true
	return false

func _case_recorded(entry: Dictionary) -> void:
	if String(entry.id) not in _pending_cases: _pending_cases.append(String(entry.id))

func _publish_cases() -> void:
	# Receipt signals run inside the ledger transaction. Publish only after it
	# commits; missing budget remains a real unfunded need for later review.
	if _busy or _economy().transaction_active(): return
	for i in range(mini(2,_pending_cases.size())):
		var id:=String(_pending_cases.pop_front())
		var entry: Dictionary=world.law.cases.get(id,{})
		if entry.is_empty() or entry.status=="resolved": continue
		_busy=true
		var posted:=String(_quests().create_contract("security_service","faction/security","faction:security",{"need_id":"investigate/"+id,"target_id":id,"service":"investigate","reward":8},_now()))
		_busy=false
		if posted.is_empty() and _quests().model.last_error=="The issuer cannot fund this contract.": _pending_cases.append(id)

func _interview(actor: String,witness: String) -> void:
	for row: Dictionary in _quests().for_participant(actor,false):
		if row.objective.service!="investigate": continue
		var entry: Dictionary=world.law.cases.get(String(row.objective.target_id),{})
		if entry.is_empty() or witness not in entry.witnesses or not _recipient_near(actor,witness): continue
		if not world.law.investigate(entry.id,actor) or not world.law.resolve(entry.id,actor): continue
		_event({"event_id":"investigation/"+String(entry.id),"event_type":"service","actor_id":actor,"target_id":String(entry.id),"timestamp":_now(),"service":"investigate","quantity":1})
