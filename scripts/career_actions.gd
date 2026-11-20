extends RefCounted
## Narrow adapters to existing world authorities; no timers or invented wages.
const Catalog=preload("res://scripts/item_catalog.gd")
const Item=preload("res://scripts/item_instance.gd")
const Inventory=preload("res://scripts/inventory.gd")
const RECIPES:={"production":{"station":"craft","inputs":{"light_shard":2,"bone_shards":1},"output":"single_chair","service":"craft"},"food_preparation":{"station":"cooking","inputs":{"light_shard":1},"output":"electron_meal","service":"prepare_meal"}}
var world: Node
var _busy:=false
func _civic(): return world.civic_interactions if is_instance_valid(world) else null
func _economy(): return world.civilian_services.economy if is_instance_valid(world) else null
func _registry(): return world.civilization.registry if is_instance_valid(world) else null
func _now() -> float: return float(world.civilization.world_seconds)
func transaction_active() -> bool: return _busy
func _live(id: String) -> bool:
	if not is_instance_valid(world) or not is_instance_valid(world.get("civilian_services")) or not is_instance_valid(world.get("civilization")) or not is_instance_valid(world.get("civic_interactions")): return false
	if id in ["player","avat_ar"] or not _registry().records.get(id,{}).get("active",false) or id not in _economy().active_ids: return false
	var autonomy: Variant=world.civilization.get("autonomy")
	return not is_instance_valid(autonomy) or not autonomy.has_method("_unavailable") or not autonomy._unavailable(id)
func premises(id: String,workplace: String,allowed_kinds: Array) -> bool:
	if not _live(id) or not is_instance_valid(world.get("building_civilization")): return false
	var row: Dictionary=world.building_civilization.model.records.get(workplace,{})
	if row.is_empty() or row.manual_review or row.owner.is_empty(): return false
	var access: bool=row.owner==id or id in row.tenants or id in row.occupants or row.access=="public"
	if not access: return false
	var aliases: Dictionary={"restaurant":"tavern","lodging":"residence","archive":"office","guild":"guild_headquarters","guard_post":"office","renovation":"workshop","expedition":"mixed","private_contact":"hideout"}
	for kind: String in allowed_kinds:
		if row.usage==aliases.get(kind,kind) or row.usage=="mixed": return true
	return false
func _assigned(id: String) -> Array:
	return world.quest_system.for_participant(id,false)
func _result(action: String,details: Dictionary={}) -> Dictionary:
	var result: Dictionary={"performed":true,"action":action}
	result.merge(details); return result
func _arrive(id: String,enforcement: bool) -> Dictionary:
	for row: Dictionary in _assigned(id):
		if row.status!="active": continue
		if enforcement and row.objective.service=="investigate":
			var entry: Dictionary=world.law.cases.get(String(row.objective.target_id),{})
			for witness: String in entry.get("witnesses",[]):
				if not _civic()._recipient_near(id,witness): continue
				_civic()._interview(id,witness)
				if world.law.cases.get(String(row.objective.target_id),{}).get("status")=="resolved": return _result("investigation",{"quest_id":row.id})
		elif row.kind=="discovery" or enforcement and row.kind=="service" and row.objective.service in ["patrol","survey"]:
			var progress: int=int(row.objective.progress)
			_civic().arrived(id,String(row.objective.target_id))
			if int(world.quest_system.model.instances[row.id].objective.progress)>progress: return _result("discovery" if row.kind=="discovery" else "patrol",{"quest_id":row.id})
	return {}
func _deliver(id: String) -> Dictionary:
	for row: Dictionary in _assigned(id):
		if row.kind=="delivery" and row.status=="active" and _civic().complete_delivery(row,id): return _result("delivery",{"quest_id":row.id})
	return {}
func _trade(id: String) -> Dictionary:
	var actors: Array=_registry().active_ids()
	if actors.is_empty(): return {}
	var store: Node=_economy().npc_store(id)
	for offset in range(mini(6,actors.size())):
		var buyer:=String(actors[posmod(id.hash()+offset,actors.size())])
		if buyer==id or not _civic()._recipient_near(id,buyer) or not _live(buyer): continue
		for item: Resource in store.items.values().slice(0,4):
			var definition: Resource=Catalog.get_definition(item.item_type_id)
			if definition==null or not definition.is_tradeable: continue
			var offer: Dictionary=world.communication.send(buyer,id,"ask_price",{"instance_id":String(item.instance_id),"quantity":1,"seller_id":id,"buyer_id":buyer})
			var parameters: Dictionary=offer.get("reply",{}).get("parameters",{})
			if not offer.get("accepted",false) or not parameters.has("quote_token"): continue
			var result: Dictionary=world.communication.send(buyer,id,"accept_trade",parameters)
			if result.get("accepted",false): return _result("trade",{"buyer":buyer,"trade_id":parameters.quote_token})
			break
	return {}
func _station(id: String,workplace: String,interaction: String) -> Dictionary:
	if workplace.is_empty() or not premises(id,workplace,["workshop","restaurant","tavern","mixed"]): return {}
	var row: Dictionary=world.building_civilization.model.records[workplace]
	var actor: Vector3=_civic().position_for(id)
	if not actor.is_finite(): return {}
	var base:=Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
	for placement: Dictionary in row.placements.values():
		var definition: Resource=Catalog.get_definition(StringName(placement.item.item_type_id))
		if definition==null or definition.custom_properties.get("interaction")!=interaction: continue
		var point:=base+Vector3(float(placement.position[0]),float(placement.position[1]),float(placement.position[2]))
		if actor.distance_to(point)<=4: return placement.duplicate(true)
	return {}
func _produce(id: String,capability: String,employment: Dictionary) -> Dictionary:
	var recipe: Dictionary=RECIPES[capability]
	var workplace:=String(employment.get("workplace",""))
	var station:=_station(id,workplace,recipe.station)
	if station.is_empty() or _economy().transaction_active(): return {}
	var source: Node=_economy().npc_store(id)
	for type: String in recipe.inputs:
		if source.count_type(StringName(type))<int(recipe.inputs[type]): return {}
	# Prepare all consumed inputs and the actual output off-scene. A failed
	# capacity/catalog check never removes one ingredient from live inventory.
	var candidate:=Inventory.new()
	if not candidate.restore(source.serialize()): candidate.free(); return {}
	var provenance: Array[String]=[]
	var stolen: Dictionary={}
	for type: String in recipe.inputs:
		var remaining: int=int(recipe.inputs[type])
		for item: Resource in candidate.items.values():
			if String(item.item_type_id)!=type: continue
			var taken: Resource=candidate.take_item(item.instance_id,mini(remaining,int(item.quantity)))
			if taken==null: candidate.free(); return {}
			provenance.append(String(item.instance_id)); remaining-=int(taken.quantity)
			for key: String in ["stolen_from","stolen_event","theft_event_id"]:
				if taken.custom_properties.has(key): stolen[key]=taken.custom_properties[key]
			if remaining==0: break
	var output: Resource=Catalog.create(StringName(recipe.output),1)
	if output==null: candidate.free(); return {}
	output.custom_properties={"crafted_by":id,"recipe_id":capability,"crafted_from":provenance}
	output.custom_properties.merge(stolen)
	var output_id:=String(output.instance_id)
	if not candidate.add_item(output): candidate.free(); return {}
	var prepared: Dictionary=candidate.serialize()
	candidate.free()
	_busy=true
	var committed: bool=source.restore(prepared)
	if not committed: _busy=false; return {}
	var event_id:="production/"+output_id
	for row: Dictionary in _assigned(id):
		if row.status!="active" or row.kind!="service" or row.objective.target_id!=workplace or row.objective.service!=recipe.service: continue
		_civic()._event({"event_id":event_id,"event_type":"service","actor_id":id,"target_id":workplace,"timestamp":_now(),"service":recipe.service,"quantity":1})
		break
	world.civilization.registry.remember(id,"production",workplace,"Converted owned material into "+String(Catalog.get_definition(StringName(recipe.output)).display_name)+" at an installed station.",.5)
	_busy=false
	return _result(capability,{"item_type":String(recipe.output),"instance_id":output_id,"workplace":workplace,"event_id":event_id})
func _admin(id: String,employment: Dictionary) -> Dictionary:
	var org: RefCounted=world.quest_system.organizations
	var key:=String(employment.get("role_ref",""))
	if key.is_empty():
		var affiliations: Array=org.memberships_of(id)
		if affiliations.is_empty(): return {}
		key=affiliations[0]
	if not org.guilds.has(key) or not org.is_member(id,key): return {}
	var peers: Array=_registry().active_ids()
	for offset in range(mini(6,peers.size())):
		var peer:=String(peers[posmod(id.hash()+offset,peers.size())])
		if peer==id or not _civic()._recipient_near(id,peer) or org.is_member(peer,key): continue
		# Recruitment is a real membership mutation and requires established trust.
		if _civic()._friend(id,peer)<.1: continue
		if world.quest_system.join_guild(peer,key):
			for row: Dictionary in _assigned(id):
				if row.status=="active" and row.kind=="service" and row.objective.service=="recruit" and row.objective.target_id==key:
					_civic()._event({"event_id":"recruit/"+peer+"/"+key,"event_type":"service","actor_id":id,"target_id":key,"timestamp":_now(),"service":"recruit","quantity":1})
			return _result("recruitment",{"member":peer,"guild_id":key})
	return {}
func perform(id: String,capability: String,employment: Dictionary) -> Dictionary:
	if _busy or not _live(id) or String(employment.get("employee",id))!=id: return {}
	match capability:
		"exploration": return _arrive(id,false)
		"enforcement": return _arrive(id,true)
		"trade": return _trade(id)
		"delivery": return _deliver(id)
		"production","food_preparation": return _produce(id,capability,employment)
		"theft":
			var record: Dictionary=_registry().records[id]
			var state: Dictionary=world.civilization.autonomy.states.get(id,{"turn":0})
			return _result("crime") if _civic().criminal_opportunity(record,state,false) else {}
		"administration": return _admin(id,employment)
	return {}
