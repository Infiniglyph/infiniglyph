extends SceneTree
const Commute=preload("res://scripts/career_commute.gd")
const Shell=preload("res://scripts/building_shell.gd")
const Chunk=preload("res://scripts/world_chunk.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
const Buildings=preload("res://scripts/building_registry.gd")
const Quests=preload("res://scripts/quest_system.gd")
const Careers=preload("res://scripts/career_system.gd")
const Actions=preload("res://scripts/career_actions.gd")
const Resident=preload("res://scripts/neighborhood_resident.gd")
class Autonomy extends RefCounted:
	var world: Node
	var record: Dictionary={}
	func _unavailable(_id: String) -> bool: return record.get("combat",false)
	func on_arrival(source: Node) -> void: world.career_commute.on_arrival(source.record)
	func on_regional_arrival(row: Dictionary) -> void: world.career_commute.on_arrival(row)
class Society extends Node:
	var registry: RefCounted
	var autonomy:=Autonomy.new()
	var world_seconds:=0.0
class Services extends Node:
	var economy: Node
class BuildingRuntime extends Node:
	var model:=Buildings.new()
class Civic extends "res://scripts/civilization_interactions.gd":
	var source: Node3D
	var journey: Dictionary={}
	func _ready() -> void: pass
	func position_for(id: String) -> Vector3:
		if id!="worker": return Vector3(40,0,40)
		return source.global_position if is_instance_valid(source) else journey.get("point",Vector3.INF)
class Life extends "res://scripts/district_life.gd":
	func _ready() -> void:
		_capsule.height=1.85; _capsule.radius=.29; _pedestrian_query.shape=_capsule
	func pose_interval(_at: Vector3) -> float: return .1
class TestWorld extends Node3D:
	var civilization: Node
	var civilian_services: Node
	var civic_interactions: Node
	var quest_system: Node
	var building_civilization: Node
	var careers: Node
	var career_actions: RefCounted
	var career_commute: RefCounted
var world: TestWorld
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func record() -> Dictionary:
	return {"id":0,"code_form_id":"worker","code_form_slot":"region/0","point":Vector3(-12,.04,14),"route":PackedVector3Array([Vector3(-12,.04,14),Vector3(12,.04,14),Vector3(12,.04,-14),Vector3(-12,.04,-14)]),"cursor":1,"checked":true,"valid":true,"wait":0.0,"meetings":0,"profile":{"id":"route","name":"Worker","role":"artisan","attitude":"friendly","tint":Color.CYAN,"body_profile":&"male"}}
func run() -> void:
	create_timer(200).timeout.connect(func(): push_error("Career commute watchdog"); quit(2))
	world=TestWorld.new(); root.add_child(world)
	var exterior:=Chunk.new(); world.add_child(exterior)
	exterior.box(Vector3(0,-.25,0),Vector3(100,.5,100),"Ground",Color.CYAN)
	var shell:=Shell.new(); world.add_child(shell); shell.configure("workshop",Vector3(18,14,24)); shell.bake_exterior(exterior,Vector3.ZERO); exterior.commit(); shell.ensure_local_contents_loaded()
	var descriptor: Dictionary=shell.descriptor(Vector3.ZERO,"city")
	var helper:=Commute.new(); helper.world=world; world.career_commute=helper
	world.civilization=Society.new(); world.add_child(world.civilization); world.civilization.autonomy.world=world
	world.civilization.registry=Registry.new()
	var seeds: Array[Dictionary]=[]
	for id: String in ["worker","owner"]: seeds.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"artificer","personality":"friendly","respawn":{"location":"overworld","position":[-12,.04,14],"yaw":0}})
	check(world.civilization.registry.bootstrap(seeds),"Original native identities enter the unchanged canonical registry")
	world.civilian_services=Services.new(); world.add_child(world.civilian_services)
	var economy:=Economy.new(); world.civilian_services.add_child(economy); world.civilian_services.economy=economy; economy.configure("human",["worker","owner"]); economy.bless_cycle(0,["worker","owner"])
	world.building_civilization=BuildingRuntime.new(); world.add_child(world.building_civilization)
	var model: RefCounted=world.building_civilization.model
	model.register(descriptor); model.claim("workshop","worker",0); model.set_use("workshop","worker","workshop",0)
	var station: Resource=Catalog.create(&"crafting_station"); station.owner_id=Buildings.owner_key("workshop")
	check(model.install("workshop","worker",station.to_dict(),[-4.0,0.0,-4.0],0,0),"The commute destination is an actual installed owned production station")
	var furniture: Node3D=load("res://scripts/furniture_geometry.gd").for_id(&"crafting_station",true); world.add_child(furniture); furniture.position=Vector3(-4,0,-4)
	world.civic_interactions=Civic.new(); world.civic_interactions.world=world; world.add_child(world.civic_interactions); world.civic_interactions.initialized=true; world.civic_interactions.set_process(false)
	world.quest_system=Quests.new(); world.add_child(world.quest_system)
	world.quest_system.setup({"identity":world.civic_interactions.identity,"authorize":world.civic_interactions.authorize_quest,"finance":world.civic_interactions.finance_quest})
	var actions:=Actions.new(); actions.world=world; world.career_actions=actions
	world.careers=Careers.new(); world.add_child(world.careers)
	world.careers.setup({"identity":world.civic_interactions.identity,"authorize":world.civic_interactions.career_authorize,"quest":world.civic_interactions.career_quest,"perform":actions.perform,"premises":actions.premises,"organizations":func(): return {}})
	world.civic_interactions._busy=true
	var task: String=world.quest_system.create_contract("personal_service","owner","resident:owner",{"target_id":"workshop","service":"craft","reward":4},0)
	world.civic_interactions._busy=false
	world.quest_system.accept(task,"worker",0)
	var employment: String=world.careers.hire("owner","worker","artificer","workshop",task)
	if employment.is_empty(): print("HIRE DIAGNOSTIC task=",task," quest=",world.quest_system.model.instances," identities=",world.civilization.registry.records.keys()," funds=",economy.balance("resident:owner")," premises=",actions.premises("worker","workshop",["workshop"])," proof=",world.civic_interactions.career_quest("inspect",{"quest_id":task}))
	check(not task.is_empty() and not employment.is_empty(),"The worker's profession is backed by a real reserved shared-quest contract")
	var owned: Node=economy.npc_store("worker"); owned.add_item(Catalog.create(&"light_shard",2)); owned.add_item(Catalog.create(&"bone_shards",1))
	var life:=Life.new(); life.civilization=world.civilization; world.add_child(life); life.set_physics_process(false)
	life.actor=CharacterBody3D.new(); world.add_child(life.actor); life.actor.position=Vector3(30,0,30)
	await frames(4)
	var journey:=record(); var original: PackedVector3Array=journey.route.duplicate(); var start: Vector3=journey.point
	check(helper.request(journey,descriptor,Vector3(-4,0,-4)) and journey.point==start and journey.career_commute.base_route==original,"A reachable front door adds a bounded reversible detour without moving the resident or changing their original route")
	if not journey.has("career_commute"): world.queue_free(); await frames(); quit(1); return
	check(journey.route[journey.career_commute.station_index].distance_to(Vector3(-4,0,-4))>1.5,"The station destination is a clear adjacent working position rather than the occupied object's center")
	var size: int=journey.route.size()
	var station_index: int=journey.career_commute.station_index
	check(helper.request(journey,descriptor,Vector3(-4,0,-4)) and journey.route.size()==size,"Repeated scheduling does not nest or grow commute paths")
	var blocked:=record(); shell.set_accessible(false); await frames()
	check(not helper.request(blocked,descriptor,Vector3(-4,0,-4)) and blocked.route==original,"A closed real doorway rejects the commute without corrupting the public route")
	shell.set_accessible(true); await frames()
	var far:=record(); far.point=Vector3(80,.04,80); far.route=PackedVector3Array([far.point,far.point+Vector3(10,0,0)])
	check(not helper.request(far,descriptor,Vector3(-4,0,-4)),"An unrelated remote journey cannot claim a city-wide commute shortcut")
	var resident:=Resident.new(); resident.life=life; resident.record=journey; life.add_child(resident)
	world.civic_interactions.source=resident; world.civilization.autonomy.record=journey
	var before_coins: int=economy.balance("resident:worker")
	helper.on_arrival(journey)
	check(owned.count_type(&"single_chair")==0 and economy.balance("resident:worker")==before_coins,"Scheduling and intermediate route arrivals cannot fabricate production or compensation")
	var paid_at:=Vector3.INF; var returned:=false; var collided:=false
	for i in range(9500):
		resident.wait=minf(resident.wait,.05) # Shorten only fixture pauses; movement remains actual capsule physics.
		await frames(1)
		if owned.count_type(&"single_chair")==1 and not paid_at.is_finite(): paid_at=resident.global_position
		if i>5 and resident.global_position.distance_to(start)<.8 and (not journey.has("career_commute") or int(journey.cursor)>station_index*2): returned=true; break
		if absf(resident.global_position.x)>50 or absf(resident.global_position.z)>50: collided=true; break
	check(paid_at.is_finite() and paid_at.distance_to(Vector3(-4,0,-4))<3.5 and not collided,"A real player-sized civilian physically walks through the shell's door to the installed station")
	check(owned.count_type(&"single_chair")==1 and owned.count_type(&"light_shard")==0 and owned.count_type(&"bone_shards")==0 and world.quest_system.model.instances[task].status=="completed" and economy.balance("resident:worker")==before_coins+4,"Verified physical arrival runs the existing career action, consumes owned inputs and settles its funded work exactly once")
	check(returned,"The same actual capsule reverses the clear entry path and returns to its original street journey")
	check(not journey.has("career_commute") and journey.route==original,"Completed employment releases its detour only after safe physical egress onto the original street graph")
	var modeled:=record(); check(helper.request(modeled,descriptor,Vector3(-4,0,-4)),"The same validated route supports an unloaded resident record")
	world.civic_interactions.source=null; world.civic_interactions.journey=modeled
	var saw_station:=false; var bounded:=true
	for i in range(1500):
		var before: Vector3=modeled.point; modeled.wait=0.0
		life.advance_journey(modeled,.1)
		bounded=bounded and before.distance_to(modeled.point)<.14
		if modeled.point.distance_to(modeled.career_commute.approach)<.1: saw_station=true
		if i>5 and modeled.point.distance_to(start)<.2 and modeled.cursor>int(modeled.career_commute.station_index)*2: break
	check(saw_station and bounded and owned.count_type(&"single_chair")==1,"Unloaded movement follows the same physical path in bounded steps and never invents another product or reward")
	print("Career commute: ",checks," checks, ",failures," failures")
	world.queue_free(); await frames(3); quit(1 if failures else 0)
