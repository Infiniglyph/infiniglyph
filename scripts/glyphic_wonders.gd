extends Node
## Logical shop lifetime is independent of its lazily rendered grand hall.
const Stock = preload("res://scripts/glyphic_wonders_stock.gd")
const Merchant = preload("res://scripts/avat_ar_visual.gd")
const Display = preload("res://scripts/glyphic_merchandise.gd")
const Menu = preload("res://scripts/civilian_menu.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Entry = preload("res://scripts/equipment_entry.gd")
const Instance = preload("res://scripts/item_instance.gd")
@export var stock_seed := 381907
@export_range(1,3650) var rotation_days := 7
@export_range(1,12) var display_count := 12
var world: Node3D
var stock := Stock.new()
var menu: CanvasLayer
var hall: Node3D
var merchant: Node3D
var displays: Array[Node3D]=[]
var current: Dictionary={}
var _quotes: Dictionary={}
var _points: Array[Dictionary]=[]
var _refresh_pending := false
var _clock := 0.0
var _sign: Label3D
var _last_customer := false

func _ready() -> void:
	name="GlyphicWonders"
	stock.configure(stock_seed,86400.0,rotation_days,display_count,now())
	var economy: Node=world.civilian_services.economy
	economy.wonder_shop_attached=true
	economy.wonder_authorizer=_authorize
	economy.wonder_purchase_committed.connect(_committed)
	menu=Menu.new()
	menu.services=self
	add_child(menu)
	menu.opened.connect(world.inventory_session._opened)
	menu.closed.connect(world.inventory_session._closed)
	world.inventory_session.glyphic_wonders=self
	world.player.defeated.connect(func(): menu.close_menu(); _quotes.clear())

func now() -> float:
	var society: Node=world.get("civilization") if is_instance_valid(world) else null
	return float(society.world_seconds) if is_instance_valid(society) else 0.0

func refresh_stock() -> bool:
	if not stock.advance(now()): return false
	_invalidate_quotes()
	if is_instance_valid(hall) and not _refresh_pending:
		_refresh_pending=true
		call_deferred("_refresh_displays")
	if is_instance_valid(menu) and menu.is_open:
		menu.show_page("The displays are changing!","Avat Ar: A fresh selection, right on time! Please inspect the new display before purchasing.",[{"text":"Continue browsing","call":menu.close_menu}])
	world.inventory_session._dirty()
	return true

func _invalidate_quotes() -> void:
	_quotes.clear()
	# Every outstanding quote is gone; old successful tokens cannot become valid
	# again. Bound the economy's extra duplicate guard over very long sessions.
	world.civilian_services.economy._used_wonder_tokens.clear()

func serialize() -> Dictionary:
	refresh_stock()
	return stock.serialize()

func restore(data: Variant) -> bool:
	var replacement:=Stock.new()
	if data==null:
		var society: Node=world.get("civilization")
		var day: float=float(society.registry.config.day_seconds) if is_instance_valid(society) else 86400.0
		if not replacement.configure(stock_seed,day,rotation_days,display_count,now()): return false
	elif not replacement.restore(data): return false
	stock=replacement
	_invalidate_quotes()
	if is_instance_valid(menu): menu.close_menu()
	if is_instance_valid(hall): _refresh_displays()
	return true

func attach_hall(content: Node3D) -> void:
	hall=content
	refresh_stock()
	merchant=Merchant.new()
	hall.add_child(merchant)
	merchant.global_transform=hall.merchant_anchor.global_transform
	var caption:=Label3D.new()
	caption.text="Avat Ar\nThe First Merchant"
	caption.position.y=3.25
	caption.font_size=38
	caption.pixel_size=.006
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.modulate=Color("f6caff")
	merchant.add_child(caption)
	_sign=Label3D.new()
	_sign.position=Vector3(0,4.8,-39)
	_sign.font_size=48
	_sign.pixel_size=.0055
	_sign.modulate=Color("e18cff")
	_sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	hall.add_child(_sign)
	_refresh_displays()
	_update_sign()

func detach_hall() -> void:
	menu.close_menu()
	_invalidate_quotes()
	hall=null
	merchant=null
	_sign=null
	displays.clear()
	_points.clear()
	current.clear()
	_last_customer=false

func _refresh_displays() -> void:
	_refresh_pending=false
	if not is_instance_valid(hall): return
	for display: Node3D in displays:
		if is_instance_valid(display): display.get_parent().remove_child(display); display.queue_free()
	displays.clear()
	_points.clear()
	var ids: Array[String]=stock.rotating_ids()
	for index in range(mini(ids.size(),hall.pedestals.size())):
		var offer: Dictionary=stock.offer(StringName(ids[index]))
		if offer.is_empty(): continue
		var display:=Display.new()
		display.type_id=StringName(ids[index])
		display.price=int(offer.price)
		hall.pedestals[index].add_child(display)
		displays.append(display)
		_points.append({"kind":"display","type_id":ids[index],"anchor":hall.pedestals[index],"label":"Inspect "+Catalog.get_definition(StringName(ids[index])).display_name})
	for anchor: Marker3D in hall.counter_points:
		_points.append({"kind":"counter","anchor":anchor,"label":"Talk to Avat Ar"})

func _update_sign() -> void:
	if is_instance_valid(_sign): _sign.text="ROTATING SHOWCASE\nNew wares in "+rotation_text()

func rotation_text() -> String:
	var seconds:=maxf(0,stock.next_rotation-now())
	var day:=float(stock.config.day_seconds)
	var hours:=ceili(seconds/day*24)
	return "%d days, %02d hours" % [hours/24,hours%24]

func _near(point: Dictionary) -> bool:
	var actor: Node3D=world.player
	var anchor: Node3D=point.get("anchor")
	if not is_instance_valid(hall) or not is_instance_valid(anchor) or not world.dungeon_travel.is_wonders(): return false
	if actor.get_world_3d()!=anchor.get_world_3d() or actor.global_position.distance_to(anchor.global_position)>4.2: return false
	var target:=anchor.global_position+Vector3.UP*.8
	var query:=PhysicsRayQueryParameters3D.create(actor.combat_point(),target,1,[actor.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _player_ready() -> bool:
	var actor: Node=world.player
	if world.inventory_session._loading or world.inventory_session._checkpoint_pending: return false
	if world.start_menu.is_open or world.inventory_session.ui.is_open or world.inventory_session.shop.is_open or world.civilian_services.menu.is_open: return false
	return actor.health>0 and not actor.transition_locked and actor.is_on_floor() and not actor.dodge.active and not actor.weapon_combat.is_staggered() and actor.weapon_combat.active_move.is_empty() and not world.world_actions.attached()

func _selling_point(point: Dictionary,offer: Dictionary) -> bool:
	# A nearby arbitrary marker is not a shop. Bind sales to this hall's actual
	# counter or the current item occupying the quoted physical pedestal.
	if point not in _points: return false
	if offer.permanent: return point.get("kind")=="counter"
	return point.get("kind")=="display" and point.get("type_id")==offer.type_id

func nearest() -> Dictionary:
	if not world.controls.gameplay_enabled or not _player_ready(): return {}
	var closest: Dictionary={}
	var distance:=INF
	for point: Dictionary in _points:
		if not _near(point): continue
		var d: float=world.player.global_position.distance_to(point.anchor.global_position)
		if d<distance: closest=point; distance=d
	return closest

func interact() -> bool:
	current=nearest()
	if current.is_empty(): return false
	refresh_stock()
	if current.kind=="counter":
		merchant.welcome()
		if is_instance_valid(world.get("civic_interactions")): return world.civic_interactions.begin_merchant(current)
		_counter()
	else: _inspect(current)
	return true

func _counter() -> void:
	if not _player_ready() or current.get("kind")!="counter": return
	if not _near(current): menu.close_menu(); return
	merchant.set_expression(&"welcoming")
	var choices: Array=[]
	for id: String in stock.permanent_ids():
		var offer: Dictionary=stock.offer(StringName(id))
		choices.append({"text":Catalog.get_definition(StringName(id)).display_name+"  /  "+str(offer.price)+" coins","call":_inspect.bind(current,id)})
	choices.append({"text":"About the shop","call":_information})
	choices.append({"text":"The First Merchant?","call":_history})
	choices.append({"text":"Leave the counter","call":menu.close_menu})
	menu.show_page("Avat Ar  /  Glyphic Wonders","Ah! A new customer. Welcome, welcome! Mind the dimensions... they are a bit larger on the inside. The displays hold today's curiosities; Health and Shield Glyphs are always here.\n\nYour coins: %d  |  New selection in %s" % [_player_balance(),rotation_text()],choices)

func _information() -> void:
	if not _player_ready() or current.get("kind")!="counter" or not _near(current): return
	merchant.set_expression(&"excited")
	menu.show_page("Today's wonders","A little room outside, a great deal of possibility inside! Approach a display to inspect its wares. My selection changes every %d game days; entering and leaving won't hurry it along.\n\nHealth and Shield Glyphs remain at my counter. Coins spent here leave circulation. The goods, of course, are yours.\n\nNext rotation in %s." % [int(stock.config.interval_days),rotation_text()],[{"text":"Back to Avat Ar","call":_counter}],_counter)

func _history() -> void:
	if not _player_ready() or current.get("kind")!="counter" or not _near(current): return
	merchant.set_expression(&"thoughtful")
	menu.show_page("The First Merchant","When the first residents received the Great Blessings, I offered food and water in exchange for their coins. Trade gave those blessings a purpose. Others followed with goods, services and skills of their own. Markets grew; guilds and cooperation followed.\n\nAvat Ar: A civilization is full of fascinating customers. And fascinating customers require fascinating merchandise!",[{"text":"Back to Avat Ar","call":_counter}],_counter)

func _player_balance() -> int:
	var economy: Node=world.civilian_services.economy
	return economy.balance(economy.player_account)

func _inspect(point: Dictionary,permanent_type: String = "") -> void:
	if not _player_ready(): return
	if not _near(point): menu.close_menu(); return
	refresh_stock()
	var id:=StringName(permanent_type if not permanent_type.is_empty() else String(point.get("type_id","")))
	var offer: Dictionary=stock.offer(id)
	if offer.is_empty(): menu.set_status("This display has changed. Inspect its new item.",true); return
	var quote:=_quote(world.player.inventory.owner_id,offer,point)
	var entry:=Entry.for_id(id)
	var body:=String(entry.description)+"\n\n"+String(entry.family).replace("_"," ").capitalize()+"  /  "+String(entry.rarity)+"\nPrice: %d Glyph Coins   |   You have: %d\nOwned: %d\n\n" % [int(offer.price),_player_balance(),world.player.inventory.count_type(id)]
	body+="Always available at Avat Ar's counter." if offer.permanent else "On display until the next rotation in "+rotation_text()+"."
	var back: Callable=_counter if offer.permanent else menu.close_menu
	menu.show_page(String(entry.name),body,[{"text":"Buy one for %d Glyph Coins" % int(offer.price),"enabled":_player_balance()>=int(offer.price),"call":_buy.bind(quote)},{"text":"Back","call":back}],back)

func _quote(buyer: String,offer: Dictionary,point: Dictionary={},physical: bool=false) -> Dictionary:
	if buyer==world.player.inventory.owner_id and (not _selling_point(point,offer) or not _near(point)): return {}
	if _quotes.size()>=256: _quotes.clear()
	var token:=Instance.new_id()
	var quote: Dictionary=offer.duplicate(true)
	quote.token=token
	_quotes[token]={"buyer":buyer,"quote":quote.duplicate(true),"point":point,"physical":physical,"expires":now()+float(stock.config.day_seconds)/12.0}
	return quote

func _authorize(buyer: String,quote: Dictionary) -> Dictionary:
	if world.inventory_session._loading or world.inventory_session._checkpoint_pending: return {}
	refresh_stock()
	var token: Variant=quote.get("token")
	if not token is String or not _quotes.has(token): return {}
	var issued: Dictionary=_quotes[token]
	if issued.buyer!=buyer or issued.quote!=quote or now()>float(issued.expires): return {}
	var canonical: Dictionary=stock.offer(StringName(quote.get("type_id","")))
	if canonical.is_empty(): return {}
	var expected: Dictionary=quote.duplicate()
	expected.erase("token")
	if canonical!=expected: return {}
	if buyer==world.player.inventory.owner_id:
		if not menu.is_open or not _player_ready() or not _selling_point(issued.point,canonical) or not _near(issued.point): return {}
	else:
		if not _npc_ready(buyer,bool(issued.physical)): return {}
	return {"type_id":canonical.type_id,"price":canonical.price,"token":token}

func _committed(token: String,_buyer: String) -> void:
	_quotes.erase(token)

func _buy(quote: Dictionary) -> void:
	var success: bool=world.civilian_services.economy.buy_wonder(quote,world.player.inventory)
	if success:
		merchant.set_expression(&"excited")
		menu.show_page("A splendid choice!","Avat Ar: Yours, with my compliments!\n\nAdded "+Catalog.get_definition(StringName(quote.type_id)).display_name+" to your inventory.\nRemaining coins: "+str(_player_balance()),[{"text":"Continue browsing","call":menu.close_menu}])
	else: menu.set_status("Purchase unavailable. Check your coins, inventory space and the current display.",true)

func _npc_ready(id: String,physical: bool) -> bool:
	if world.inventory_session._loading or world.inventory_session._checkpoint_pending: return false
	var society: Node=world.get("civilization")
	if not is_instance_valid(society) or not society.ready_for_simulation: return false
	var record: Dictionary=society.registry.records.get(id,{})
	if record.is_empty() or not record.get("active",false): return false
	if society.autonomy._unavailable(id): return false
	var point: Vector3=society.autonomy.shopping_position(id)
	var outside: bool=world.dungeon_travel.active_location==world.dungeon_travel.OUTSIDE
	if physical: return point.is_finite() and point.distance_to(world.wider_world.glyphic_wonders.arrival_anchor.global_position)<10
	# Nearby visible shoppers use the real frontage arrival, never a remote buy.
	return not outside or not point.is_finite() or point.distance_to(world.player.global_position)>100

func npc_shop(record: Dictionary,physical: bool = false) -> bool:
	var id:=String(record.get("id",""))
	if not _npc_ready(id,physical): return false
	record=world.civilization.registry.records[id]
	refresh_stock()
	var economy: Node=world.civilian_services.economy
	var balance: int=economy.balance("resident:"+id)
	var inventory: Node=economy.npc_store(id)
	if not is_instance_valid(inventory): return false
	var best: Dictionary={}
	var highest: float=-INF
	var motives: Dictionary=record.get("motivations",{})
	for offer: Dictionary in stock.offers():
		if int(offer.price)>balance: continue
		var type:=StringName(offer.type_id)
		if inventory.count_type(type)>0: continue
		var definition: Resource=Catalog.get_definition(type)
		var score:=float(posmod((id+String(type)+str(stock.cycle)).hash(),100))/100.0
		if type==&"health_glyph": score+=float(motives.get("survival",.5))
		elif String(type).begins_with("shield_glyph_"): score+=float(motives.get("security",.5))
		elif definition.category==&"weapons": score+=float(motives.get("mastery",.5))
		else: score+=float(motives.get("novelty",.5))
		if score>highest: highest=score; best=offer
	if best.is_empty(): return false
	var quote:=_quote(id,best,{},physical)
	var success: bool=economy.npc_buy_wonder(id,quote)
	if not success: _quotes.erase(quote.token)
	else:
		world.civilization.registry.remember(id,"purchase","glyphic_wonders/"+String(best.type_id),"Bought "+Catalog.get_definition(StringName(best.type_id)).display_name+" at Glyphic Wonders.",.65)
	return success

func _process(delta: float) -> void:
	_clock+=delta
	if _clock<.25: return
	_clock=0
	refresh_stock()
	_update_sign()
	if menu.is_open and (not _player_ready() or not _near(current)): menu.close_menu()
	if not is_instance_valid(merchant): return
	var near_customer: bool=world.player.get_world_3d()==merchant.get_world_3d() and world.player.global_position.distance_to(merchant.global_position)<12
	merchant.customer=world.player if near_customer else null
	if near_customer and not _last_customer: merchant.welcome()
	_last_customer=near_customer
