extends SceneTree
const Economy=preload("res://scripts/civilian_economy.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Stock=preload("res://scripts/glyphic_wonders_stock.gd")
class RejectingInventory extends "res://scripts/inventory.gd":
	func add_item(_item: Resource) -> bool: return false
class FailingEconomy extends "res://scripts/civilian_economy.gd":
	var fail_settlement:=false
	func _append_event(event: Dictionary) -> bool:
		return false if fail_settlement else super._append_event(event)
var economy: Node
var inventory: Node
var stock: RefCounted
var quotes: Dictionary={}
var serial:=0
var checks:=0
var failures:=0
var commits: Array[Dictionary]=[]
var receipts: Array[Dictionary]=[]
var callback_safe:=true
var callback_accepts:=0
var current_quote: Dictionary={}
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func quote(type: StringName,buyer: String) -> Dictionary:
	serial+=1
	var token:="quote-"+str(serial)
	quotes[token]={"buyer":buyer,"offer":stock.offer(type)}
	return {"token":token}
func authorize(buyer: String,request: Dictionary) -> Dictionary:
	callback_safe=callback_safe and economy.transaction_active()
	if economy.buy_wonder(request,inventory): callback_accepts+=1
	var entry: Dictionary=quotes.get(request.get("token",""),{})
	if entry.is_empty() or entry.buyer!=buyer or entry.offer.is_empty(): return {}
	var current: Dictionary=stock.offer(StringName(entry.offer.type_id))
	if current!=entry.offer: return {}
	return {"type_id":current.type_id,"price":current.price,"token":request.token}
func committed(token: String,buyer: String) -> void:
	callback_safe=callback_safe and economy.transaction_active() and economy._used_wonder_tokens.has(token)
	commits.append({"token":token,"buyer":buyer})
	# Deliberately leave the fixture's quote present, proving the economy also
	# prevents replay independently of the controller's normal quote removal.
	if economy.buy_wonder({"token":token},inventory): callback_accepts+=1
	if economy.transfer(economy.player_account,economy.guild_account,1,"Nested settlement"): callback_accepts+=1
func circulation() -> int:
	var total:=0
	for amount: int in economy.balances.values(): total+=amount
	return total
func run() -> void:
	inventory=Inventory.new()
	inventory.owner_id="human"
	root.add_child(inventory)
	economy=FailingEconomy.new()
	root.add_child(economy)
	economy.player_inventory=inventory
	economy.configure("human",["natural_a","natural_b"])
	economy.bless_cycle(0,["natural_a","natural_b"])
	economy.transfer("resident:natural_b",economy.player_account,100,"Fund the buyer from actual resident coins")
	stock=Stock.new()
	stock.configure(1842,1,7,12,0)
	economy.wonder_shop_attached=true
	economy.wonder_authorizer=authorize
	economy.wonder_purchase_committed.connect(committed)
	economy.commerce_committed.connect(func(receipt: Dictionary): receipts.append(receipt.duplicate(true)))
	check(economy.balance(economy.player_account)==100 and economy.balance("resident:natural_a")==100 and circulation()==200,"Buyers begin with conserved, explicitly issued money")
	check(not economy.purchase_wonder("natural_a") and not economy.purchase_wonder("natural_a",&"cyan_mantle"),"An attached store closes the old five-coin cyan-mantle bypass")
	var before: Dictionary=economy.serialize()
	check(not economy.buy_wonder({"token":"invented","price":1,"type_id":"health_glyph"},inventory) and economy.serialize()==before,"Invented quotes cannot charge or deliver goods")
	current_quote=quote(&"health_glyph","human")
	current_quote.price=1
	current_quote.type_id="shield_glyph_heavy"
	check(economy.buy_wonder(current_quote,inventory) and inventory.count_type(&"health_glyph")==1 and inventory.count_type(&"shield_glyph_heavy")==0 and economy.balance(economy.player_account)==80,"The canonical current quote controls the item and price despite forged request fields")
	check(economy.destroyed_total==20 and circulation()==180 and economy.balance(economy.guild_account)==0 and economy.balance(economy.tavern_account)==0,"Every paid coin is destroyed rather than credited to a merchant or business")
	check(commits.size()==1 and receipts.is_empty() and not economy.balances.has("resident:avat_ar"),"A human purchase grants no Code Form XP and creates no Avat Ar wallet")
	before=economy.serialize()
	var items_before: Dictionary=inventory.serialize()
	check(not economy.buy_wonder(current_quote,inventory) and economy.serialize()==before and inventory.serialize()==items_before,"Repeated confirmation of a committed token neither charges twice nor duplicates delivery")
	var stale:=quote(&"health_glyph","human")
	stock.advance(7)
	check(not economy.buy_wonder(stale,inventory) and economy.serialize()==before,"Rotation expires an outstanding quote without charging the buyer")
	var npc_quote:=quote(&"shield_glyph_light","natural_a")
	check(not economy.npc_buy_wonder("natural_b",npc_quote) and economy.serialize()==before,"A quote bound to one natural buyer cannot spend another resident's funds")
	check(economy.npc_buy_wonder("natural_a",npc_quote) and economy.npc_store("natural_a").count_type(&"shield_glyph_light")==1 and economy.balance("resident:natural_a")==75,"A Code Form buys a real existing item using its own funded inventory and wallet")
	check(receipts.size()==1 and receipts[0].participants==["natural_a"] and receipts[0].counterpart=="glyphic_wonders" and receipts[0].amount==25,"Only the actual natural buyer participates in the meaningful retail XP receipt")
	var retry:=quote(&"health_glyph","human")
	var rejecting:=RejectingInventory.new()
	rejecting.owner_id="human"
	root.add_child(rejecting)
	economy.player_inventory=rejecting
	before=economy.serialize()
	check(not economy.buy_wonder(retry,rejecting) and rejecting.items.is_empty() and economy.serialize()==before and not economy._used_wonder_tokens.has(retry.token),"Actual delivery rejection preserves money, goods and quote eligibility")
	economy.player_inventory=inventory
	check(economy.buy_wonder(retry,inventory) and inventory.count_type(&"health_glyph")==2,"A delivery-failed quote remains usable once actual ownership can accept the item")
	rejecting.free()
	retry=quote(&"health_glyph","human")
	before=economy.serialize()
	items_before=inventory.serialize()
	economy.fail_settlement=true
	check(not economy.buy_wonder(retry,inventory) and economy.serialize()==before and inventory.serialize()==items_before and not economy._used_wonder_tokens.has(retry.token),"A settlement failure after tentative delivery rolls the actual inventory back atomically")
	economy.fail_settlement=false
	check(economy.buy_wonder(retry,inventory),"Settlement failure does not consume the valid quote")
	retry=quote(&"shield_glyph_heavy","human")
	before=economy.serialize()
	check(not economy.buy_wonder(retry,inventory) and economy.serialize()==before,"Insufficient funds reject a valid offer without granting items or consuming coins")
	var foreign:=Inventory.new()
	foreign.owner_id="outsider"
	root.add_child(foreign)
	check(not economy.buy_wonder(quote(&"health_glyph","human"),foreign) and foreign.items.is_empty(),"A foreign inventory cannot receive this player's purchases")
	foreign.free()
	economy.host_enabled=false
	check(not economy.buy_wonder(quote(&"health_glyph","human"),inventory) and not economy.npc_buy_wonder("natural_a",quote(&"health_glyph","natural_a")) and economy.serialize()==before,"Non-host retail calls cannot mutate goods or money")
	economy.host_enabled=true
	economy.external_transaction_guard=func(): return true
	check(not economy.buy_wonder(quote(&"health_glyph","human"),inventory) and economy.serialize()==before,"An opposing ownership transaction blocks retail settlement")
	economy.external_transaction_guard=Callable()
	check(callback_safe and callback_accepts==0,"Authorization, commit and ownership callbacks cannot reenter the economy or replay a token")
	check(circulation()+economy.destroyed_total==economy.issued_total and not Economy.validate(economy.serialize(),inventory.serialize()).is_empty(),"The final real inventories and permanently destroyed supply remain canonically auditable")
	check(economy.serialize().size()==18 and economy.serialize().version==3,"Retail quotes remain ephemeral within the audited faction-and-escrow economy checkpoint schema")
	economy.free()
	inventory.free()
	print("Glyphic Wonders purchase verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
