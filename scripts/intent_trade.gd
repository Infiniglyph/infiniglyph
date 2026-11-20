extends RefCounted
## Ephemeral semantic offers backed by the seller's real ordinary inventory.
## The economy owns goods, balances, receipts and rollback; dialogue owns none.
const Catalog=preload("res://scripts/item_catalog.gd")
const Item=preload("res://scripts/item_instance.gd")
const Message=preload("res://scripts/intent_message.gd")
const MAX_QUOTES:=64
const MAX_PRICE:=1000000000
var world: Node
var _quotes: Dictionary={}
var _authorization: Dictionary={}
var _busy:=false
var _last_clock:=0.0
var _active_quote:=""

func _economy(): return world.civilian_services.economy if is_instance_valid(world) and is_instance_valid(world.get("civilian_services")) else null
func _registry(): return world.civilization.registry if is_instance_valid(world) and is_instance_valid(world.get("civilization")) else null
func _now() -> float: return float(world.civilization.world_seconds) if _registry()!=null else 0.0
func _raw(id: String) -> String: return String(_economy().owner_id) if id=="player" else id
func _live(id: String) -> bool:
	if _economy()==null: return false
	if id=="player": return is_instance_valid(_economy().player_inventory) and not String(_economy().owner_id).is_empty()
	if _registry()==null or not _registry().records.get(id,{}).get("active",false) or not id in _economy().active_ids: return false
	var autonomy: Variant=world.civilization.get("autonomy")
	return not (autonomy is RefCounted and autonomy.has_method("_unavailable") and autonomy._unavailable(id))

func _near(seller: String,buyer: String) -> bool:
	var civic: Node=world.get("civic_interactions")
	if not is_instance_valid(civic) or not civic.has_method("_recipient_near"): return false
	if "player" in [seller,buyer]:
		var actor: Node=world.get("player")
		if not is_instance_valid(actor) or float(actor.get("health"))<=0 or actor.get("transition_locked")==true: return false
		var travel: Node=world.get("dungeon_travel")
		if is_instance_valid(travel) and travel.active_location!=travel.OUTSIDE: return false
		var session: Node=world.get("inventory_session")
		if is_instance_valid(session) and session.networked(): return false
		return civic._recipient_near("player",seller if buyer=="player" else buyer)
	return civic._recipient_near(seller,buyer)

func transaction_active() -> bool: return _busy
func clear() -> void:
	if _busy: return
	_quotes.clear(); _authorization.clear(); _last_clock=_now()

func _prune() -> void:
	var now:=_now()
	if now<_last_clock: _quotes.clear()
	_last_clock=now
	for token: String in _quotes.keys():
		if now>=float(_quotes[token].expires_at): _quotes.erase(token)
	while _quotes.size()>MAX_QUOTES: _quotes.erase(_quotes.keys()[0])

func _stock(seller: String) -> Node:
	if not _live(seller): return null
	if seller=="player": return _economy().player_inventory
	return _economy().npc_store(seller)

func _item(seller: String,iid: String) -> Resource:
	var store:=_stock(seller)
	if not is_instance_valid(store): return null
	var item: Resource=store.get_item(iid)
	if item==null or item.owner_id!=store.owner_id: return null
	var definition: Resource=Catalog.get_definition(item.item_type_id)
	return item if definition!=null and definition.is_tradeable and definition.is_droppable else null

func _unit_price(item: Resource) -> int:
	var definition: Resource=Catalog.get_definition(item.item_type_id)
	var food: Dictionary=_economy().food_offer(item.item_type_id)
	if not food.is_empty(): return int(food.price)
	var crystal: int=_economy().crystal_price(item.item_type_id)
	if crystal>0: return crystal
	var listed: Variant=definition.custom_properties.get("glyph_coin_value",0)
	if Item.whole_number(listed,1,MAX_PRICE): return int(listed)
	if definition.category==&"consumables": return 8
	if definition.category==&"weapons": return 40
	return 20

func _minimum(row: Dictionary) -> int:
	var relation: float=float(_registry().records.get(row.seller,{}).get("relationships",{}).get(row.buyer,0.0))
	return maxi(1,ceili(float(row.base_price)*.8)) if relation>=.1 else int(row.base_price)

func _legality(item: Resource) -> String:
	for key: String in ["stolen_from","stolen_event","theft_event_id"]:
		if not str(item.custom_properties.get(key,"")).is_empty(): return "illegal"
	return "legal"

func _node(intent: String,label: String,parameters: Dictionary,subject: String="") -> Dictionary:
	return {"intent":intent,"label":label,"parameters":parameters,"subject_id":subject,"enabled":true}

func nodes(npc: String,buyer: String) -> Array:
	var result: Array=[]
	if _busy or npc==buyer or not _live(buyer) or not _near(npc,buyer): return result
	_prune()
	var store:=_stock(npc)
	if not is_instance_valid(store): return result
	for item: Resource in store.items.values():
		if _item(npc,item.instance_id)==null: continue
		var definition: Resource=Catalog.get_definition(item.item_type_id)
		result.append(_node("offer_item" if npc=="player" else "ask_price",("Offer " if npc=="player" else "Inspect ")+String(definition.display_name).left(64),{"instance_id":String(item.instance_id),"quantity":1,"seller_id":npc,"buyer_id":buyer},item.instance_id))
		if result.size()>=4: break
	return result

func _quote(seller: String,buyer: String,iid: String,quantity: int) -> Dictionary:
	_prune()
	if seller==buyer or not _live(seller) or not _live(buyer) or not _near(seller,buyer): return {}
	var item:=_item(seller,iid)
	if item==null or quantity<1 or quantity>int(item.quantity): return {}
	var unit:=_unit_price(item)
	if unit<1 or quantity>MAX_PRICE/unit: return {}
	var ttl: float=float(_registry().config.day_seconds)/12.0
	var token: String="trade_"+Item.new_id()
	var definition: Resource=Catalog.get_definition(item.item_type_id)
	var row: Dictionary={"token":token,"seller":seller,"buyer":buyer,"instance_id":iid,"item_type":String(item.item_type_id),"item_name":definition.display_name,"quantity":quantity,"price":unit*quantity,"base_price":unit*quantity,"expires_at":_now()+ttl,"legality":_legality(item),"upgrade_level":int(item.upgrade_level),"properties":item.custom_properties.duplicate(true)}
	_quotes[token]=row; _prune()
	return row

func _current(token: String,buyer: String,seller: String) -> Dictionary:
	_prune()
	var row: Dictionary=_quotes.get(token,{})
	if row.is_empty() or row.buyer!=buyer or row.seller!=seller or not _live(buyer) or not _live(seller) or not _near(seller,buyer): return {}
	var item:=_item(seller,row.instance_id)
	if item==null or int(item.quantity)<int(row.quantity) or String(item.item_type_id)!=row.item_type or int(item.upgrade_level)!=int(row.upgrade_level) or not Item.same_properties(item.custom_properties,row.properties): return {}
	return row

func _parameters(row: Dictionary) -> Dictionary:
	return {"quote_token":row.token,"instance_id":row.instance_id,"item_name":row.item_name,"quantity":row.quantity,"price":row.price,"seller_id":row.seller,"buyer_id":row.buyer}

func _choices(row: Dictionary) -> Array:
	var options: Array=[_node("accept_trade",("Sell " if row.seller=="player" else "Buy ")+String(row.item_name).left(64)+" for "+str(row.price)+" coins",_parameters(row),row.instance_id)]
	var minimum:=_minimum(row)
	if minimum<int(row.price):
		var counter:=_parameters(row); counter.price=minimum
		options.append(_node("propose_price","Offer "+str(minimum)+" coins",counter,row.instance_id))
	options.append(_node("decline_trade","Decline this offer",{"quote_token":row.token},row.instance_id))
	return options

func _offered(row: Dictionary) -> Dictionary:
	return {"accepted":true,"reply":{"intent":"quote_price","parameters":_parameters(row),"subject_id":row.instance_id},"nodes":_choices(row),"branch":"trade","context":{"seller_id":row.seller,"buyer_id":row.buyer}}

func _refuse(reason: String) -> Dictionary:
	return {"accepted":false,"reason":reason,"reply":{"intent":"refuse","parameters":{"reason":reason}}}

func authorized(payload: Dictionary) -> bool:
	if not _busy or _authorization.is_empty() or payload!=_authorization: return false
	var row: Dictionary=_quotes.get(_active_quote,{})
	return not row.is_empty() and not _current(_active_quote,row.buyer,row.seller).is_empty()

func handle(input: Dictionary) -> Dictionary:
	if _busy: return _refuse("This exchange is already settling.")
	var message:=Message.validate(input)
	if message.is_empty(): return _refuse("The trade intention is incomplete.")
	if not message.intent in ["ask_price","offer_item","offer_trade","propose_price","accept_trade","decline_trade"]: return {"accepted":false,"unhandled":true}
	var buyer:=String(message.speaker_id)
	var seller:=String(message.listener_id)
	var p: Dictionary=message.parameters
	if not _live(buyer) or not _live(seller) or buyer==seller: return _refuse("Both parties must be available to trade.")
	if message.intent in ["ask_price","offer_item"]:
		if message.intent=="offer_item": seller=String(message.speaker_id); buyer=String(message.listener_id)
		if p.get("seller_id",seller)!=seller or p.get("buyer_id",buyer)!=buyer: return _refuse("This request names a different trader.")
		var iid:=String(p.get("instance_id",message.subject_id))
		if iid.is_empty(): return {"accepted":true,"reply":{"intent":"inform","parameters":{"detail":"Choose an item from my actual stock."}},"nodes":nodes(seller,buyer),"branch":"trade"}
		if not Item.whole_number(p.get("quantity",1),1,999999): return _refuse("Choose a whole quantity from the available stock.")
		var row:=_quote(seller,buyer,iid,int(p.get("quantity",1)))
		return _offered(row) if not row.is_empty() else _refuse("That owned item is no longer offered.")
	var token:=String(p.get("quote_token",""))
	var pending: Dictionary=_quotes.get(token,{})
	if pending.is_empty(): return _refuse("That offer has expired or its stock changed. Ask for a new price.")
	if not (message.speaker_id==pending.seller and message.listener_id==pending.buyer or message.speaker_id==pending.buyer and message.listener_id==pending.seller): return _refuse("This offer belongs to different traders.")
	if "player" in [pending.seller,pending.buyer]:
		if message.speaker_id!="player": return _refuse("The traveler must confirm their side of this exchange.")
	elif message.speaker_id!=pending.buyer: return _refuse("The buyer must agree to this offer.")
	buyer=pending.buyer; seller=pending.seller
	var row:=_current(token,buyer,seller)
	if row.is_empty(): return _refuse("That offer has expired or its stock changed. Ask for a new price.")
	if p.has("instance_id") and p.instance_id!=row.instance_id or p.has("quantity") and p.quantity!=row.quantity: return _refuse("The offer is for a different item or quantity.")
	if message.intent=="decline_trade":
		_quotes.erase(token)
		return {"accepted":true,"reply":{"intent":"decline_trade","parameters":{"item_name":row.item_name}},"nodes":nodes(seller,buyer),"branch":"trade"}
	if message.intent in ["offer_trade","propose_price"]:
		var proposed: Variant=p.get("price",p.get("offered_price",null))
		if not Item.whole_number(proposed,1,MAX_PRICE) or int(proposed)<_minimum(row): return _refuse("That price is below this trader's fair offer.")
		_quotes.erase(token)
		row=row.duplicate(true); row.token="trade_"+Item.new_id(); row.price=mini(int(proposed),int(row.base_price))
		_quotes[row.token]=row
		return _offered(row)
	if p.has("price") and p.price!=row.price: return _refuse("Only the exact agreed price can be accepted.")
	_busy=true
	_active_quote=token
	_authorization={"seller_id":_raw(seller),"buyer_id":_raw(buyer),"instance_id":row.instance_id,"quantity":row.quantity,"price":row.price,"event_id":row.token,"legality":row.legality}
	var accepted: bool=_economy().trade_item(_authorization.seller_id,_authorization.buyer_id,_authorization.instance_id,int(_authorization.quantity),int(_authorization.price),_authorization.event_id,_authorization.legality)
	_authorization={}; _active_quote=""; _busy=false
	if not accepted: return _refuse("The goods or available coins changed. Nothing was exchanged.")
	_quotes.erase(token)
	return {"accepted":true,"reply":{"intent":"accept_trade","parameters":_parameters(row)},"facts":[{"trade_id":row.token,"item_id":row.instance_id,"quantity":row.quantity,"price":row.price}],"nodes":nodes(seller,buyer),"branch":"trade"}
