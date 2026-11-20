extends SceneTree
## Real storefront clearance, persistent civilians, funded inventory purchases
## and physical arrivals. The shop adapter isolates Autonomy's public contract;
## the production shop/quote tests cover its player UI and offer expiry.
const Autonomy = preload("res://scripts/code_form_autonomy.gd")
const Registry = preload("res://scripts/code_form_registry.gd")
const Economy = preload("res://scripts/civilian_economy.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Stock = preload("res://scripts/glyphic_wonders_stock.gd")
const Exterior = preload("res://scripts/glyphic_wonders_exterior.gd")

class World extends Node3D:
	var population: Node3D
	var district_life: Node3D
	var wider_world: Node3D
	var glyphic_wonders: Node

class Regions extends Node3D:
	var glyphic_wonders: Node3D
	static func surface_at(_x: float,_z: float) -> float: return 0.0

class Life extends "res://scripts/district_life.gd":
	func build() -> void: pass # Exercise two existing records, not another city.

class Society extends Node:
	var registry = Registry.new()
	var autonomy = Autonomy.new()
	var economy: Node
	var world: Node3D
	func id_for_source(source: Node) -> String:
		return String(source.get_meta("code_form_id",""))
	func record_event(event: Dictionary) -> Dictionary: return registry.record_event(event)
	func commerce(receipt: Dictionary) -> void:
		for id: String in receipt.participants:
			registry.record_event({"event_type":"economic","actor_id":id,"target_id":"glyphic_wonders","rarity":"common","significance":1.0,"coins":receipt.amount,"event_id":String(receipt.id)+"/"+id})

class Shop extends Node:
	var stock = Stock.new()
	var society: Node
	var attempts := 0
	var physical_purchases := 0
	var coarse_purchases := 0
	var enabled := true
	func authorize(buyer: String,quote: Dictionary) -> Dictionary:
		var offer: Dictionary=stock.offer(&"health_glyph")
		if not enabled or offer.is_empty() or not society.registry.records.get(buyer,{}).get("active",false): return {}
		return {"type_id":"health_glyph","price":offer.price,"token":quote.token}
	func npc_shop(record: Dictionary,physical: bool = false) -> bool:
		attempts += 1
		var accepted: bool=society.economy.npc_buy_wonder(record.id,{"token":"autonomy/"+str(attempts)})
		if accepted:
			if physical: physical_purchases += 1
			else: coarse_purchases += 1
		return accepted

var checks := 0
var failures := 0

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 1
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else: failures += 1; push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count): await physics_frame; await process_frame

func progress(record: Dictionary) -> int: return int(record.level)*100000+int(record.experience)

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Wonders autonomy watchdog"); quit(2))
	var world := World.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,.2,100)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.position = Vector3(-112,-.1,-608)
	var regions := Regions.new()
	world.add_child(regions)
	world.wider_world = regions
	regions.glyphic_wonders = Exterior.new()
	regions.add_child(regions.glyphic_wonders)
	var life := Life.new()
	life.regions = regions
	life.actor = CharacterBody3D.new()
	world.add_child(life.actor)
	life.actor.position = Vector3(-300,0,-300)
	world.add_child(life)
	world.district_life = life
	var route := life.wonders_route()
	life.add_person(route,0,route[0],true)
	life.add_person(route,2,route[2],true)
	check(life.resident_records.size()==2 and route.size()==8 and route[5].is_equal_approx(regions.glyphic_wonders.arrival_anchor.global_position),"The storefront detour reuses two regional identities and the actual arrival marker")
	await frames(3)
	var clear := true
	for record: Dictionary in life.resident_records:
		for i in range(100):
			life.validation_probes = 0
			life.validate_walk(record)
			if record.checked: break
		clear = clear and record.checked and record.valid
	check(clear,"The complete storefront circuit and raised frontage pass real static capsule clearance")
	var society := Society.new()
	society.world = world
	society.autonomy.civilization = society
	world.add_child(society)
	life.civilization = society
	var rows: Array[Dictionary] = []
	for record: Dictionary in life.resident_records:
		rows.append({"slot":record.code_form_slot,"id":record.code_form_slot,"name":record.profile.name,"occupation":"scribe","personality":"curious","respawn":{"location":"overworld","position":[record.point.x,record.point.y,record.point.z],"yaw":0.0}})
	check(society.registry.bootstrap(rows),"Only the existing pedestrian slots enter the autonomous census")
	var inventory := Inventory.new()
	inventory.owner_id = "wonders_test_human"
	world.add_child(inventory)
	var economy := Economy.new()
	economy.player_inventory = inventory
	world.add_child(economy)
	society.economy = economy
	check(economy.configure(inventory.owner_id,society.registry.active_ids()) and economy.bless_cycle(0,society.registry.active_ids()),"Real audited civilian wallets fund the shop decisions")
	var shop := Shop.new()
	shop.society = society
	shop.stock.configure(42)
	world.add_child(shop)
	world.glyphic_wonders = shop
	economy.wonder_shop_attached = true
	economy.wonder_authorizer = shop.authorize
	economy.commerce_committed.connect(society.commerce)
	society.autonomy.bind_sources()
	var id: String = life.resident_records[0].code_form_id
	var person: Dictionary = society.registry.records[id]
	var state: Dictionary = society.autonomy._state(id)
	for key: String in person.motivations: person.motivations[key]=0.0
	for key: String in ["novelty","security","survival"]: person.motivations[key]=1.0
	var considers_shop := false
	for turn in range(32): considers_shop = considers_shop or society.autonomy.choose_goal(person,{"hunger":0.0,"turn":turn})=="wonder"
	check(considers_shop and society.autonomy._shopping_interest(person,100)>0,"Current affordable offers and personal needs can motivate a real store visit")
	check(society.autonomy._shopping_interest(person,0)==0,"A penniless civilian has no affordable shopping intention")
	society.registry.set_goal(id,"wonder")
	var wallet: int = economy.balance("resident:"+id)
	var xp := progress(person)
	check(society.autonomy.perform_action(person,state,false) and shop.coarse_purchases==1,"An unloaded civilian buys through the shared shop contract without loading the hall")
	check(economy.balance("resident:"+id)==wallet-20 and economy.destroyed_total==20 and economy.npc_store(id).count_type(&"health_glyph")==1,"A model purchase spends real coins, destroys them and delivers the existing glyph once")
	check(progress(person)>xp and society.autonomy._has_memory(person,"shop","glyphic_wonders"),"Only the committed commerce receipt gives shopping XP while the buyer remembers the purchase")
	check(not economy.purchase_wonder(id) and economy.natural_ids.size()==2,"The legacy cheap mantle path is disabled and no merchant wallet or civilian identity is added")
	shop.enabled = false
	wallet = economy.balance("resident:"+id)
	xp = progress(person)
	check(not society.autonomy.perform_action(person,state,false) and economy.balance("resident:"+id)==wallet and progress(person)==xp,"A rejected or rotated offer gives no item, coin deduction or activity XP")
	shop.enabled = true
	var first: Dictionary = life.resident_records[0]
	first.point = regions.glyphic_wonders.arrival_anchor.global_position
	first.cursor = 5
	var source: CharacterBody3D = life.spawn_person(first)
	source.set_physics_process(false)
	society.autonomy.bind_sources()
	state.next_action = 0.0
	wallet = economy.balance("resident:"+id)
	society.autonomy.on_arrival(source)
	check(shop.physical_purchases==1 and economy.balance("resident:"+id)==wallet-20 and society.autonomy.shopping_position(id).distance_to(first.point)<.01,"A real pedestrian at the doorway uses the physical shop path")
	wallet = economy.balance("resident:"+id)
	society.autonomy.on_arrival(source)
	check(economy.balance("resident:"+id)==wallet and shop.physical_purchases==1,"Repeated arrival callbacks respect the persisted shopping cooldown")
	var second: Dictionary = life.resident_records[1]
	second.point = first.point
	var other: Dictionary = society.registry.records[second.code_form_id]
	xp = progress(other)
	society.registry.set_goal(other.id,"rest")
	society.autonomy.on_regional_arrival(second)
	check(progress(other)==xp and society.autonomy._has_memory(other,"visit","glyphic_wonders"),"Passing the storefront records personal novelty without awarding idle or inspection XP")
	first.combat = true
	state.next_action = 0.0
	var attempts: int = shop.attempts
	check(not society.autonomy.perform_action(person,state,false) and shop.attempts==attempts,"A combat-suspended civilian cannot shop invisibly")
	first.combat = false
	# Walk the actual controller up the shallow entrance ramp, rather than
	# treating a clear graph or a teleported arrival as sufficient proof.
	source.position = route[4]
	first.point = source.position
	first.cursor = 5
	source.wait = 0
	state.next_action = 0.0
	var reached := false
	for i in range(360):
		await physics_frame
		source._physics_process(1.0/60.0)
		if source.global_position.distance_to(route[5])<.75: reached=true
		if reached and shop.physical_purchases==2: break
	if not reached or shop.physical_purchases!=2: print("WALK DETAIL ",JSON.stringify({"reached":reached,"position":str(source.global_position),"target":str(route[5]),"cursor":first.cursor,"wait":source.wait,"stalled":source._stalled,"purchases":shop.physical_purchases,"attempts":shop.attempts,"balance":economy.balance("resident:"+id)}))
	check(reached and shop.physical_purchases==2,"The existing regional controller walks onto the frontage and completes a physical purchase")
	var saved: Dictionary = society.autonomy.serialize()
	var state_shape := true
	for plan: Dictionary in saved.states.values(): state_shape = state_shape and plan.size()==6
	check(state_shape and not Autonomy.validate(JSON.parse_string(JSON.stringify(saved)),society.registry.active_ids()).is_empty(),"Shopping keeps the existing six-field scheduler and JSON checkpoint compatibility")
	world.free()
	print("Code Form Wonders verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
