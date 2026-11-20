extends SceneTree
const Actions=preload("res://scripts/career_actions.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
const Quests=preload("res://scripts/quest_system.gd")
const Law=preload("res://scripts/civilian_law.gd")
const Buildings=preload("res://scripts/building_registry.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
class Autonomy extends RefCounted:
	var states: Dictionary={}
	var _sources: Dictionary={}
	func _unavailable(_id: String) -> bool: return false
class Society extends Node:
	var registry: RefCounted
	var autonomy:=Autonomy.new()
	var world_seconds:=0.0
class Services extends Node:
	var economy: Node
class BuildingRuntime extends Node:
	var model:=Buildings.new()
class Civic extends "res://scripts/civilization_interactions.gd":
	var points: Dictionary={}
	func _ready() -> void: pass
	func position_for(id: String) -> Vector3: return points.get(id,Vector3(INF,INF,INF))
	func destination(_id: String) -> Vector3: return Vector3.ZERO
class Transport extends Node:
	var civic: Node
	var serial:=0
	func send(from: String,to: String,intent: String,p: Dictionary={}) -> Dictionary:
		serial+=1
		return civic.trade.handle({"message_id":"career-msg/"+str(serial),"event_id":"career-event/"+str(serial),"speaker_id":from,"listener_id":to,"intent":intent,"subject_id":"","parameters":p,"emotion":"neutral","conversation_id":"career-trade","world_timestamp":0.0})
class TestWorld extends Node3D:
	var civilization: Node
	var civilian_services: Node
	var civic_interactions: Node
	var quest_system: Node
	var law: Node
	var communication: Node
	var building_civilization: Node
var world: TestWorld
var actions: RefCounted
var economy: Node
var checks:=0
var failures:=0
var ids: Array=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func job(template: String,actor: String,terms: Dictionary) -> String:
	var issuer: String=ids.back()
	var id: String=world.quest_system.create_contract(template,issuer,"resident:"+issuer,terms,0)
	world.quest_system.accept(id,actor,0)
	return id
func install(type: StringName) -> String:
	var item: Resource=Catalog.create(type); item.owner_id=Buildings.owner_key("workshop")
	return item.instance_id if world.building_civilization.model.install("workshop",ids[0],item.to_dict(),[-4.0,0.0,-3.0],0.0,0) else ""
func run() -> void:
	world=TestWorld.new(); root.add_child(world)
	world.civilization=Society.new(); world.add_child(world.civilization)
	world.civilization.registry=Registry.new()
	var seeds: Array[Dictionary]=[]
	for n in range(16):
		var id:="resident_"+str(n).pad_zeros(2); ids.append(id)
		seeds.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"merchant","personality":"friendly","respawn":{"location":"overworld","position":[0,.2,0],"yaw":0}})
	world.civilization.registry.bootstrap(seeds)
	world.civilian_services=Services.new(); world.add_child(world.civilian_services)
	economy=Economy.new(); world.civilian_services.add_child(economy); world.civilian_services.economy=economy
	economy.configure("human",ids); economy.bless_cycle(0,ids)
	world.quest_system=Quests.new(); world.add_child(world.quest_system)
	world.law=Law.new(); world.law.world=world; world.add_child(world.law)
	world.civic_interactions=Civic.new(); world.civic_interactions.world=world; world.add_child(world.civic_interactions)
	world.civic_interactions.initialized=true; world.civic_interactions.trade.world=world
	world.quest_system.setup({"identity":world.civic_interactions.identity,"authorize":func(op: String,row: Dictionary): return op=="publish" or world.civic_interactions.authorize_quest(op,row),"finance":world.civic_interactions.finance_quest,"organization_finance":economy.organization_operation,"organization_authorize":func(_op: String,_row: Dictionary): return true})
	for faction: String in ["security","commerce","exploration","underworld"]:
		economy.register_faction(faction); economy.transfer("resident:"+ids[14],"faction:"+faction,20,"Founding funds")
	world.quest_system.bootstrap_organizations(ids,0)
	world.law.identity_provider=world.civic_interactions.identity
	world.communication=Transport.new(); world.communication.civic=world.civic_interactions; world.add_child(world.communication)
	world.building_civilization=BuildingRuntime.new(); world.add_child(world.building_civilization)
	var buildings: RefCounted=world.building_civilization.model
	buildings.register({"id":"workshop","point":Vector3.ZERO,"size":Vector3(20,4,20),"layout":{}})
	buildings.claim("workshop",ids[0],0); buildings.set_use("workshop",ids[0],"workshop",0)
	actions=Actions.new(); actions.world=world
	economy.npc_validator=func(operation: StringName,payload: Dictionary):
		if operation==&"npc_sell_item": return world.civic_interactions.trade.authorized(payload)
		if operation==&"deliver_item": return world.civic_interactions.delivery_authorized(payload)
		return true
	economy.transaction_committed.connect(world.civic_interactions.transaction_committed)
	for id: String in ids:
		world.civic_interactions.points[id]=Vector3.ZERO
		world.civilization.registry.records[id].motivations.wealth=.9
		world.civilization.registry.records[id].motivations.security=.1
		economy.npc_store(id).add_item(Catalog.create(&"electron_meal"))
		world.civilization.registry.relate(ids[0],id,.2)
	var actor: String=ids[0]
	var employment: Dictionary={"employee":actor,"workplace":"workshop","role_ref":"dark_box"}
	check(actions.perform("player","production",employment).is_empty() and actions.perform("avat_ar","trade",{}).is_empty(),"Special entities cannot invoke ordinary civilian career actions")
	check(not actions.premises(actor,"workshop",["shop"] ) and actions.premises(actor,"workshop",["workshop"]),"Workplaces must have compatible functional use and actual access")
	var store: Node=economy.npc_store(actor)
	store.add_item(Catalog.create(&"light_shard",4)); store.add_item(Catalog.create(&"bone_shards",2))
	var before: Dictionary=store.serialize()
	check(actions.perform(actor,"production",employment).is_empty() and store.serialize()==before,"Owned ingredients alone cannot produce goods without an installed station")
	var station: String=install(&"crafting_station")
	check(not station.is_empty(),"The actual building model installs an owned crafting station")
	world.civic_interactions.points[actor]=Vector3(100,0,100)
	check(actions.perform(actor,"production",employment).is_empty() and store.serialize()==before,"A remote workshop cannot fabricate an offsite worker's goods")
	world.civic_interactions.points[actor]=Vector3(-4,0,-3)
	var task: String=job("personal_service",actor,{"target_id":"workshop","service":"craft","reward":4})
	var coins: int=economy.balance("resident:"+actor)
	var made: Dictionary=actions.perform(actor,"production",employment)
	check(made.get("performed",false) and store.count_type(&"single_chair")==1 and store.count_type(&"light_shard")==2 and store.count_type(&"bone_shards")==1,"Craftsperson consumes real owned materials and produces one actual catalog furnishing")
	check(world.quest_system.model.instances[task].status=="completed" and economy.balance("resident:"+actor)==coins+4,"A real station conversion advances and pays a funded shared service contract")
	buildings.remove("workshop",actor,station,0)
	buildings.set_use("workshop",actor,"tavern",0)
	check(not install(&"cooking_station").is_empty(),"Cooking requires a separately installed reusable kitchen station")
	task=job("personal_service",actor,{"target_id":"workshop","service":"prepare_meal","reward":3})
	var meals: int=store.count_type(&"electron_meal")
	var cooked: Dictionary=actions.perform(actor,"food_preparation",employment)
	check(cooked.get("performed",false) and store.count_type(&"electron_meal")==meals+1 and store.count_type(&"light_shard")==1 and world.quest_system.model.instances[task].status=="completed","Chef converts owned stable light into an actual Electron Meal and verified service")
	var empty: Dictionary=employment.duplicate(); empty.workplace=""
	check(actions.perform(actor,"food_preparation",empty).is_empty(),"A title without usable premises cannot conjure food")
	world.civic_interactions.points[actor]=Vector3.ZERO
	world.quest_system.join_guild(actor,"adventurers_guild")
	task=world.quest_system.create_contract("exploration_discovery","guild/adventurers_guild","guild:adventurers_guild",{"guild_id":"adventurers_guild","target_id":"place/survey","reward":3},0); world.quest_system.accept(task,actor,0)
	check(actions.perform(actor,"exploration",employment).get("performed",false) and world.quest_system.model.instances[task].status=="completed","Adventurer completes a verified actual arrival discovery")
	task=job("personal_delivery",actor,{"item_type":"electron_meal","recipient_id":ids.back(),"reward":3})
	var recipient: Node=economy.npc_store(ids.back()); meals=recipient.count_type(&"electron_meal")
	var delivered: Dictionary=actions.perform(actor,"delivery",employment)
	check(delivered.get("performed",false) and recipient.count_type(&"electron_meal")==meals+1 and world.quest_system.model.instances[task].status=="ready","Courier transfers actual inventory before the busy ledger defers reward settlement")
	world.quest_system.advance_to(0)
	check(world.quest_system.model.instances[task].status=="completed","The actual committed courier receipt pays once the shared ledger transaction finishes")
	var case: Dictionary=world.law.record_crime({"event_id":"witnessed_case","kind":"theft","offender":ids[3],"victim":ids[4],"witnesses":[ids[4]],"asset_id":"known_owned_asset","transaction_id":"known_receipt"})
	world.quest_system.join_guild(actor,"inquest")
	task=world.quest_system.create_contract("security_service","guild/inquest","guild:inquest",{"guild_id":"inquest","target_id":case.id,"service":"investigate","reward":3},0); world.quest_system.accept(task,actor,0)
	check(actions.perform(actor,"enforcement",employment).get("performed",false) and world.law.cases[case.id].status=="resolved" and world.quest_system.model.instances[task].status=="completed","Security Officer interviews a real nearby recorded witness and resolves its funded investigation")
	var quantity:=0
	for item: Resource in store.items.values(): quantity+=item.quantity
	check(actions.perform(actor,"trade",employment).get("performed",false),"Merchant executes actual semantic quote and agreement against a nearby funded buyer")
	var after_quantity:=0
	for item: Resource in store.items.values(): after_quantity+=item.quantity
	check(after_quantity==quantity-1,"Merchant sale removes exactly one actual owned good")
	world.quest_system.join_guild(actor,"dark_box")
	check(actions.perform(actor,"administration",employment).get("performed",false),"Guild Administrator recruits an actual nearby trusted eligible member")
	world.civilization.registry.records[actor].relationships.clear()
	check(actions.perform(actor,"theft",employment).get("performed",false),"Thief uses actual ownership theft and witnessed law rather than an invented wage event")
	var stolen:=false
	for item: Resource in store.items.values():
		if item.custom_properties.has("stolen_from"): stolen=true
	check(stolen and world.law.wanted_level(actor)>0,"Criminal acquisition retains actual stolen provenance and separate wanted evidence")
	var total: int=economy.destroyed_total
	for amount: int in economy.balances.values(): total+=amount
	check(total==economy.issued_total and not Economy.validate(economy.serialize()).is_empty(),"Eight functional career actions conserve finite coins and validate actual inventory ownership")
	world.free()
	print("Career actions: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
