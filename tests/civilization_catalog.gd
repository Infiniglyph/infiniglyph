extends SceneTree
## Shared catalog, real owned cuisine and matching native furniture geometry.
const Catalog=preload('res://scripts/item_catalog.gd')
const Cuisine=preload('res://scripts/electron_cuisine.gd')
const Geometry=preload('res://scripts/furniture_geometry.gd')
const Economy=preload('res://scripts/civilian_economy.gd')
const Inventory=preload('res://scripts/inventory.gd')
const Services=preload('res://scripts/civilian_services.gd')
const Shields=preload('res://scripts/shield_glyphs.gd')
const Stock=preload('res://scripts/glyphic_wonders_stock.gd')
const Tower=preload('res://scripts/tower_shop.gd')
const Entry=preload('res://scripts/equipment_entry.gd')
const Preview=preload('res://scripts/equipment_preview.gd')
const Filters=preload('res://scripts/equipment_filters.gd')
const Autonomy=preload('res://scripts/code_form_autonomy.gd')
const Registry=preload('res://scripts/code_form_registry.gd')
class Society extends Node:
	var registry=Registry.new()
	var economy: Node
	var world: Node3D
class Fighter extends Node:
	signal changed
	var health:=500.0
	var max_health:=1000.0
class Actor extends Node3D:
	var inventory: Node
	var weapon_combat: Node
	var transition_locked:=false
	var health: float:
		get: return weapon_combat.health
class WorldStub extends Node3D:
	var player: Node
var checks:=0
var failures:=0
var actor: Actor
var inventory: Node
var economy: Node
var services: Node
var mock: WorldStub
var meals:=0
var npc_meals:=0
var commerce:=0
func _initialize() -> void: call_deferred('run')
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print('PASS: ',label)
	else: failures+=1; push_error('FAIL: '+label)
func add(type: StringName,props: Dictionary={}) -> Resource:
	var item: Resource=Catalog.create(type)
	item.custom_properties=props
	inventory.add_item(item)
	return item
func finish_food() -> void:
	services._process(4.0)
func run() -> void:
	create_timer(60).timeout.connect(func(): push_error('Cuisine catalog test timed out'); quit(1))
	check(Catalog.civilization_ids().size()==80 and Catalog.food_ids().size()==26,'Exactly56placeables and24new cuisine definitions extend the shared catalogue')
	var counts:={"residential_furniture":12,"commercial_furniture":12,"functional_equipment":12,"decorations":20,"electron_meals":16,"drinks_desserts":8}
	var tower:=Tower.new()
	var eligible:=true
	var recipes:=true
	var owns:=true
	for group: String in counts:
		check(Catalog.civilization_ids(group).size()==counts[group],group+' has its complete requested collection')
	for id: StringName in Catalog.civilization_ids():
		var definition: Resource=Catalog.get_definition(id)
		var p: Dictionary=definition.custom_properties
		eligible=eligible and Stock.eligible(definition) and Stock.price_for(id)==int(p.price) and tower.offer(id).get('price',-1)==0
		var entry:=Entry.for_id(id)
		var model: Node3D=Preview.model(entry)
		recipes=recipes and model.get_child_count()==1 and entry.geometry.renderer=='civic_item'
		model.free()
		if not p.get('placeable',false): continue
		var s:=Geometry.size_of(p)
		var parts:=Geometry.boxes(p)
		recipes=recipes and not parts.is_empty() and s.is_finite() and s.x>0 and s.y>0 and s.z>0
		for box: Dictionary in parts:
			recipes=recipes and box.position.y-box.size.y*.5>=-.001 and box.position.y+box.size.y*.5<=s.y+.009
		var solid:=Geometry.for_id(id,true)
		recipes=recipes and solid.body.get_child_count()==parts.size()
		solid.free()
		var item: Resource=Catalog.create(id)
		item.owner_id='visitor'
		owns=owns and item.is_valid() and Catalog.get_definition(id)==definition and not item.to_dict().is_empty()
	check(eligible,'Every catalogue entry uses actual shared retail prices and a player-only free Tower offer')
	check(recipes,'All native previews use bottom-centred box recipes matching collision and advertised dimensions')
	check(owns,'All56placeables are real owned transferable instances, rather than decorative duplicate definitions')
	check(tower.offer(&'civic_key').is_empty(),'Restricted key items remain absent from developer offers')
	tower.free()
	var stock:=Stock.new()
	check(stock.configure(17,60,7,12,0),'Shared stock configures over the expanded catalogue')
	var original:=stock.serialize()
	check(not stock.advance(419.9) and stock.serialize()==original,'Entry and elapsed time before seven game days cannot reroll stock')
	check(stock.advance(420) and stock.cycle==1 and stock.permanent_ids()==Stock.PERMANENT,'The seventh game day rotates offers while only the four glyphs remain permanent')
	var stock_copy:=Stock.new()
	check(stock_copy.restore(JSON.parse_string(JSON.stringify(stock.serialize()))) and stock_copy.serialize()==stock.serialize(),'Expanded catalogue rotation retains exact seed, pool and selection across reload')
	check(Filters.matches(Catalog.get_definition(&'basic_bed'),1) and not Filters.matches(Catalog.get_definition(&'basic_bed'),2) and Filters.matches(Catalog.get_definition(&'ion_tea'),6) and Filters.matches(Catalog.get_definition(&'byte_bites'),5),'Owned inventory filters distinguish furniture groups and meals versus drinks/desserts')
	var base:=Cuisine.effects(Catalog.get_definition(&'electron_meal').custom_properties)
	check(base.hp_restore==60 and base.shield_restore==0,'The existing eight-coin Electron Meal retains its60HP baseline')
	var feast:=Cuisine.effects(Catalog.get_definition(&'electron_feast').custom_properties,{'quality':2,'rarity':'Legendary'})
	check(feast.hp_restore>base.hp_restore and feast.hp_restore<=350,'Recipe complexity, actual rarity and quality improve HP recovery within a configurable cap')
	var clamped:=Cuisine.effects(Catalog.get_definition(&'liquid_light').custom_properties,{'quality':1e8,'rarity':100})
	check(clamped.quality==2 and clamped.shield_restore<=1000 and clamped.shield_capacity==1000,'Unbounded instance quality and rarity are clamped before shield calculation')
	var settings: Dictionary=Cuisine.DEFAULTS.duplicate()
	settings.shield_cap=500
	check(Cuisine.effects(Catalog.get_definition(&'liquid_light').custom_properties,{'quality':2},settings).shield_capacity==500,'A configured lower shield cap chooses an existing canonical tier')
	settings.shield_cap=1
	check(Cuisine.effects(Catalog.get_definition(&'ion_tea').custom_properties,{},settings).is_empty(),'Impossible shield capacities are rejected rather than persisted as invalid pools')
	actor=Actor.new(); root.add_child(actor)
	actor.weapon_combat=Fighter.new(); actor.add_child(actor.weapon_combat)
	inventory=Inventory.new(); inventory.owner_id='visitor'; inventory.actor=actor; actor.inventory=inventory; actor.add_child(inventory)
	economy=Economy.new(); economy.player_inventory=inventory; root.add_child(economy)
	mock=WorldStub.new(); mock.player=actor
	services=Services.new(); services.world=mock; services.economy=economy; services._clock=1e9
	economy.food_consumed.connect(services._start_food)
	economy.food_consumed.connect(func(_i: Node,_e: Dictionary): meals+=1)
	economy.npc_food_consumed.connect(func(_id: String,_e: Dictionary): npc_meals+=1)
	economy.commerce_committed.connect(func(_r: Dictionary): commerce+=1)
	check(economy.configure('visitor',['native','guild_receptionist','tavern_bartender']) and economy.bless_cycle(0,['native','guild_receptionist','tavern_bartender']) and economy.transfer('resident:native',economy.player_account,100),'Cuisine fixtures use existing funded coins, never a free wallet')
	check(economy.food_offer(&'electron_meal').price==8 and economy.food_offer(&'electron_draught').price==12 and economy.food_offer(&'electron_draught').healing==0,'Existing meal and draught prices stay8/12 while draught now restores shield')
	var all_offers:=true
	for type: StringName in Catalog.food_ids(): all_offers=all_offers and not economy.food_offer(type).is_empty()
	check(all_offers and economy.food_offer(&'basic_bed').is_empty(),'Tavern authority offers all26real foods and refuses nonfood catalogue objects')
	check(economy.buy_food(&'neon_sushi',inventory) and inventory.count_type(&'neon_sushi')==1 and economy.balance(economy.tavern_account)==17,'Prepared meals use actual inventory delivery and conserved paid tavern settlement')
	var meal:=add(&'electron_meal')
	check(economy.consume_food(meal.instance_id,inventory) and meals==1 and services.food_effect.remaining==2,'Consuming removes a real owned meal and starts a finite effect')
	finish_food()
	check(actor.health==560 and services.food_effect.is_empty(),'Meal completion applies exactly60HP over its ordinary recovery cadence')
	actor.weapon_combat.health=1000
	var full_meal:=add(&'byte_bites')
	check(not economy.consume_food(full_meal.instance_id,inventory) and inventory.get_item(full_meal.instance_id)!=null,'Full-health players retain uneaten food')
	var drink:=add(&'electron_draught')
	check(economy.consume_food(drink.instance_id,inventory) and inventory.shield_state.tier=='light','A full-HP player can drink to establish a canonical light shield')
	finish_food()
	check(is_equal_approx(inventory.shield_state.points,120) and actor.health==1000 and Shields.valid(inventory.shield_state),'Drinking restores shield only and produces a valid persistent shield state')
	inventory.shield_state={'tier':'heavy','points':850.0}
	drink=add(&'electron_draught')
	check(economy.consume_food(drink.instance_id,inventory),'A weaker drink can refill an existing stronger shield')
	finish_food()
	check(inventory.shield_state.tier=='heavy' and is_equal_approx(inventory.shield_state.points,970),'Drinks never downgrade or truncate a previously established heavy pool')
	inventory.shield_state.points=1000.0
	drink=add(&'ion_tea')
	check(not economy.consume_food(drink.instance_id,inventory) and inventory.get_item(drink.instance_id)!=null,'A full shield does not waste a weaker drink')
	inventory.shield_state={}
	drink=add(&'liquid_light',{'quality':2,'rarity':'Legendary'})
	check(economy.consume_food(drink.instance_id,inventory) and inventory.shield_state.tier=='heavy','Complex high-quality drink establishes the correctly scaled canonical shield tier')
	finish_food()
	check(inventory.shield_state.points>120 and inventory.shield_state.points<=1000,'High-quality drink recovery scales within the hard shield cap')
	var restored:=Inventory.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(inventory.serialize()))),'Owned furniture/food metadata and food-created shield pools survive the real inventory schema')
	restored.free()
	check(commerce==1,'Food consumption emits no economic commerce receipt or eating XP')
	check(economy.transfer('resident:guild_receptionist','resident:native',20) and economy.npc_buy_food('native',&'refresh_packet') and economy.npc_consume_food('native',&'refresh_packet'),'NPCs purchase and consume actual new drinks with finite existing coins')
	check(npc_meals==1 and economy.npc_store('native').count_type(&'refresh_packet')==0 and economy.npc_store('native').shield_state.is_empty(),'NPC consumption emits optional effects without invalid shield state on storage inventories')
	var society:=Society.new(); society.economy=economy; root.add_child(society)
	var rows: Array[Dictionary]=[{'id':'native','slot':'hub/native','name':'Native','occupation':'gardener','personality':'curious','respawn':{'location':'overworld','position':[0.0,.04,0.0],'yaw':0.0}}]
	check(society.registry.bootstrap(rows) and economy.npc_buy_food('native',&'byte_bites') and economy.npc_buy_food('native',&'refresh_packet'),'A hungry autonomous identity owns real new cuisine before choosing another purchase')
	var autonomy:=Autonomy.new(); autonomy.civilization=society
	var state: Dictionary=autonomy._state('native')
	var record: Dictionary=society.registry.records.native
	society.registry.set_goal('native','eat')
	var coins: int=economy.balance('resident:native')
	var experience: int=record.experience
	check(autonomy.perform_action(record,state,false) and economy.npc_store('native').count_type(&'byte_bites')==0 and economy.npc_store('native').count_type(&'refresh_packet')==1 and economy.balance('resident:native')==coins,'Autonomous eating consumes an owned meal before a drink or another paid purchase')
	check(autonomy.perform_action(record,state,false) and economy.npc_store('native').count_type(&'refresh_packet')==0 and economy.balance('resident:native')==coins,'With no meals left the NPC consumes its owned drink without spending more coins')
	check(autonomy.perform_action(record,state,false) and economy.balance('resident:native')==coins-8 and economy.npc_store('native').count_type(&'electron_meal')==0,'An empty pantry uses the ordinary paid Electron Meal fallback and consumes the actual delivered item')
	check(not autonomy.perform_action(record,state,false) and record.experience==experience,'An unfunded empty pantry cannot manufacture a meal or eating XP')
	society.free()
	var before: Dictionary=inventory.serialize()
	economy.host_enabled=false
	check(not economy.consume_food(full_meal.instance_id,inventory) and inventory.serialize()==before,'Nonhost calls cannot consume owned cuisine')
	economy.host_enabled=true
	var reentered:=[false]
	actor.weapon_combat.health=500
	var recurse:=func(_i: Node,_e: Dictionary): reentered[0]=economy.consume_food(full_meal.instance_id,inventory)
	economy.food_consumed.connect(recurse)
	check(economy.consume_food(full_meal.instance_id,inventory) and not reentered[0],'Consumption callbacks cannot reenter the inventory authority')
	check(not Economy.validate(economy.serialize(),inventory.serialize()).is_empty(),'Expanded food stock preserves all existing strict economic ledger and ownership invariants')
	services.free(); mock.free(); economy.free(); actor.free()
	print('Civilization catalog: %d checks, %d failures' % [checks,failures])
	quit(0 if failures==0 else 1)
