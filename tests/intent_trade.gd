extends SceneTree
const Trade=preload("res://scripts/intent_trade.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
class Society extends Node:
	var registry: RefCounted
	var world_seconds:=0.0
class Services extends Node:
	var economy: Node
class Human extends Node:
	var inventory: Node
	var health:=1000
	var transition_locked:=false
class Civic extends Node:
	var near:=true
	func _recipient_near(_a: String,_b: String) -> bool: return near
class MockWorld extends Node:
	var civilization: Node
	var civilian_services: Node
	var player: Node
	var civic_interactions: Node
var world: MockWorld
var trade: RefCounted
var economy: Node
var seller: Node
var buyer: Node
var checks:=0
var failures:=0
var serial:=0
var receipts: Array=[]
var reentered:=false
var nested_accepts:=0
var current_accept: Dictionary={}

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func message(intent: String,parameters: Dictionary={},from: String="player",to: String="seller",subject: String="") -> Dictionary:
	serial+=1
	return {"message_id":"trade-message/"+str(serial),"event_id":"trade-event/"+str(serial),"speaker_id":from,"listener_id":to,"intent":intent,"subject_id":subject,"parameters":parameters,"emotion":"neutral","conversation_id":"trade-conversation","world_timestamp":world.civilization.world_seconds}
func ask(iid: String,quantity: int=1,from: String="player") -> Dictionary:
	return trade.handle(message("ask_price",{"instance_id":iid,"quantity":quantity},from))
func quote(result: Dictionary) -> Dictionary: return result.get("reply",{}).get("parameters",{})
func receipt(entry: Dictionary) -> void:
	receipts.append(entry)
	if current_accept.is_empty() or reentered: return
	reentered=true
	if trade.handle(current_accept).get("accepted",false): nested_accepts+=1
func total() -> int:
	var sum: int=economy.destroyed_total
	for amount: int in economy.balances.values(): sum+=amount
	return sum
func run() -> void:
	world=MockWorld.new(); root.add_child(world)
	world.civilization=Society.new(); world.add_child(world.civilization)
	world.civilization.registry=Registry.new()
	var rows: Array[Dictionary]=[]
	for id: String in ["seller","buyer","donor"]: rows.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"merchant","personality":"friendly","respawn":{"location":"overworld","position":[0,.2,0],"yaw":0}})
	world.civilization.registry.bootstrap(rows)
	world.civilian_services=Services.new(); world.add_child(world.civilian_services)
	world.player=Human.new(); world.add_child(world.player)
	world.player.inventory=Inventory.new(); world.player.inventory.owner_id="local"; world.player.add_child(world.player.inventory)
	economy=Economy.new(); economy.player_inventory=world.player.inventory; world.civilian_services.add_child(economy); world.civilian_services.economy=economy
	economy.configure("local",["seller","buyer","donor"]); economy.bless_cycle(0,["seller","buyer","donor"])
	economy.transfer("resident:donor","player:local",100,"Visitor payment")
	world.civic_interactions=Civic.new(); world.add_child(world.civic_interactions)
	trade=Trade.new(); trade.world=world
	economy.validator=func(operation: StringName,payload: Dictionary): return operation==&"intent_trade" and trade.authorized(payload)
	economy.npc_validator=func(operation: StringName,payload: Dictionary): return operation==&"npc_sell_item" and trade.authorized(payload)
	economy.transaction_committed.connect(receipt)
	seller=economy.npc_store("seller"); buyer=economy.npc_store("buyer")
	var blade: Resource=Catalog.create(&"katana"); blade.upgrade_level=7; blade.custom_properties.engraving="Actually owned"; seller.add_item(blade)
	var meals: Resource=Catalog.create(&"electron_meal",3); seller.add_item(meals)
	var key: Resource=Catalog.create(&"civic_key"); seller.add_item(key)
	check(trade.nodes("seller","player").size()==2 and trade.nodes("missing","player").is_empty(),"Semantic stock nodes expose actual transferable inventory and hide protected or unknown goods")
	check(not trade.authorized({}) and not economy.trade_item("seller","local",blade.instance_id,1,1,"invented"),"An invented direct player trade cannot obtain the temporary settlement capability")
	var quoted:=ask(blade.instance_id)
	var original:=quote(quoted)
	check(quoted.accepted and original.price==40 and original.instance_id==blade.instance_id and original.quantity==1,"A price question issues a real owned weapon quote using its authoritative catalog value")
	check(not trade.handle(message("propose_price",{"quote_token":original.quote_token,"price":32,"item_name":"Katana"})).accepted,"An unrelated buyer cannot demand the friendly discount")
	world.civilization.registry.records.seller.relationships.player=.2
	var counter: Dictionary=trade.handle(message("propose_price",{"quote_token":original.quote_token,"price":32,"item_name":"Katana"}))
	var agreed:=quote(counter)
	check(counter.accepted and agreed.price==32 and agreed.quote_token!=original.quote_token,"A friendly fair counteroffer creates a new exact-price quote and invalidates the old token")
	check(not trade.handle(message("accept_trade",original)).accepted,"A superseded original offer cannot be replayed after negotiation")
	var tampered: Dictionary=agreed.duplicate(); tampered.price=1
	check(not trade.handle(message("accept_trade",tampered)).accepted and world.player.inventory.get_item(blade.instance_id)==null,"Changing the source quote's price cannot buy the actual weapon cheaply")
	tampered=agreed.duplicate(); tampered.quantity=2
	check(not trade.handle(message("accept_trade",tampered)).accepted,"The accepted token cannot be relabeled with another quantity")
	check(not trade.handle(message("accept_trade",agreed,"buyer")).accepted,"A quote bound to a player cannot spend another civilian's balance")
	world.player.health=0
	check(not trade.handle(message("accept_trade",agreed)).accepted,"A dead player cannot use a still-valid semantic price offer")
	world.player.health=1000; world.player.transition_locked=true
	check(not trade.handle(message("accept_trade",agreed)).accepted,"A transition lock invalidates commit authority")
	world.player.transition_locked=false; world.civic_interactions.near=false
	check(not trade.handle(message("accept_trade",agreed)).accepted,"Walking away prevents the accepted item and coins from moving remotely")
	world.civic_interactions.near=true
	current_accept=message("accept_trade",agreed)
	var paid: Dictionary=trade.handle(current_accept)
	check(paid.accepted and world.player.inventory.get_item(blade.instance_id)!=null and seller.get_item(blade.instance_id)==null and economy.balance("player:local")==68 and economy.balance("resident:seller")==132,"Accepting the negotiated intention atomically moves the existing weapon for exactly32 existing coins")
	var owned: Resource=world.player.inventory.get_item(blade.instance_id)
	check(owned.upgrade_level==7 and owned.custom_properties.engraving=="Actually owned" and paid.facts[0].price==32,"Semantic agreement preserves unique upgrades/properties and reports actual economic facts")
	check(nested_accepts==0 and reentered and not trade.transaction_active() and not trade.authorized({}),"Economic receipt callbacks cannot reenter an in-flight semantic settlement")
	check(not trade.handle(current_accept).accepted and economy.balance("player:local")==68,"Replaying a settled quote cannot duplicate its weapon or payment")
	check(receipts.size()==1 and receipts[0].participants==["seller"] and receipts[0].asset_receiver_id=="local","Actual human trade receipts contain only the participating civilian for Code Form XP")
	var food_quote:=quote(ask(meals.instance_id,2,"buyer"))
	check(food_quote.price==16 and trade.handle(message("accept_trade",food_quote,"buyer")).accepted and buyer.count_type(&"electron_meal")==2 and seller.count_type(&"electron_meal")==1,"NPCs use the identical semantic quote and finite-inventory settlement path")
	check(receipts.back().participants==["seller","buyer"] and receipts.back().amount==16,"A genuine NPC-to-NPC sale names both eligible Code Forms in its actual receipt")
	var low_quote:=quote(ask(meals.instance_id))
	var decline: Dictionary=trade.handle(message("decline_trade",{"quote_token":low_quote.quote_token}))
	check(decline.accepted and not trade.handle(message("accept_trade",low_quote)).accepted,"Declining destroys only the ephemeral quote and cannot later be accepted")
	var expiring:=quote(ask(meals.instance_id))
	world.civilization.world_seconds=8000
	check(not trade.handle(message("accept_trade",expiring)).accepted and seller.count_type(&"electron_meal")==1,"An expired offer grants no goods and moves no coins")
	var rollback:=quote(ask(meals.instance_id))
	world.civilization.world_seconds=0
	check(not trade.handle(message("accept_trade",rollback)).accepted,"A world-clock rollback clears ephemeral offers instead of reviving them")
	var changed:=quote(ask(meals.instance_id)); meals.custom_properties.note="Stock changed"
	check(not trade.handle(message("accept_trade",changed)).accepted,"Changed owned-instance metadata requires a fresh truthful quote")
	meals.custom_properties.erase("note")
	var stolen: Resource=Catalog.create(&"light_shard",1); stolen.custom_properties.stolen_event="real-theft"; seller.add_item(stolen)
	var stolen_quote:=quote(ask(stolen.instance_id,1,"buyer"))
	check(trade.handle(message("accept_trade",stolen_quote,"buyer")).accepted and receipts.back().legality=="illegal" and receipts.back().participants==["seller","buyer"],"A real stolen item sale retains provenance and remains a genuine civilian economic event")
	var empty_wallet:=quote(ask(meals.instance_id))
	economy.transfer("player:local","resident:donor",economy.balance("player:local"),"A separate real payment")
	var before: Dictionary=economy.serialize(); var before_stock: Dictionary=seller.serialize()
	check(not trade.handle(message("accept_trade",empty_wallet)).accepted and economy.serialize()==before and seller.serialize()==before_stock,"Insufficient funds preserve both the actual stock and audited ledger")
	for i in range(Trade.MAX_QUOTES+10): ask(meals.instance_id)
	check(trade._quotes.size()==Trade.MAX_QUOTES,"Ephemeral quote memory remains capped under repeated price questions")
	trade.clear()
	check(trade._quotes.is_empty() and not trade.authorized({}),"Checkpoint/reset integration can discard all ephemeral negotiation state without moving money")
	var selling_nodes: Array=trade.nodes("player","buyer")
	check(selling_nodes.size()==1 and selling_nodes[0].intent=="offer_item" and selling_nodes[0].parameters.instance_id==blade.instance_id,"The player may semantically offer only real transferable goods they currently own")
	var player_sale: Dictionary=trade.handle(message("offer_item",{"instance_id":blade.instance_id,"quantity":1,"seller_id":"player","buyer_id":"buyer"},"player","buyer",blade.instance_id))
	var sale_quote:=quote(player_sale)
	check(player_sale.accepted and sale_quote.seller_id=="player" and sale_quote.buyer_id=="buyer" and sale_quote.price==40,"An offered player item receives a finite NPC purchase quote without moving it yet")
	check(not trade.handle(message("accept_trade",sale_quote,"buyer","player")).accepted and world.player.inventory.get_item(blade.instance_id)!=null,"An NPC cannot force completion of a quoted sale before the human confirms")
	economy.transfer("resident:buyer","resident:donor",economy.balance("resident:buyer"),"Another real expense")
	check(not trade.handle(message("accept_trade",sale_quote,"player","buyer")).accepted and world.player.inventory.get_item(blade.instance_id)!=null,"An NPC with insufficient existing money cannot acquire the player's offered gear")
	economy.transfer("resident:donor","resident:buyer",40,"Funded repayment")
	var sold: Dictionary=trade.handle(message("accept_trade",sale_quote,"player","buyer"))
	check(sold.accepted and world.player.inventory.get_item(blade.instance_id)==null and buyer.get_item(blade.instance_id)!=null and economy.balance("player:local")==40 and economy.balance("resident:buyer")==0,"Human confirmation transfers the exact existing upgraded item into NPC ownership for the NPC's actual40 coins")
	check(receipts.back().participants==["buyer"] and buyer.get_item(blade.instance_id).upgrade_level==7,"Selling player goods preserves their identity and includes only the real civilian buyer in XP receipts")
	check(total()==economy.issued_total and Economy.validate(economy.serialize(),world.player.inventory.serialize()).size()>0,"Actual semantic trading conserves the full issued supply and ordinary inventory identities")
	world.free()
	print("Intent trade: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
