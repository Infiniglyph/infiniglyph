extends Node
## Event-driven, host-owned money and room contents, independent of geometry.
const Inventory = preload("res://scripts/inventory.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const ROOM_COUNT := 3
const COIN_CAP := 1000000000
const JOURNAL_LIMIT := 128
const MAX_RESIDENTS := 16384
const MAX_ACTIVE := 2048
const MAX_SERVICE_TOKENS := 65536
const WAGE_SERVICES := {"guild_work":"business:guild","tavern_work":"business:tavern"}
const CRYSTALS := {"monster_glyph_common":12,"monster_glyph_uncommon":30,"monster_glyph_rare":75,"apep_lorai_catalyst":180}
const FOOD := [&"electron_meal",&"electron_draught"]
signal changed
signal food_consumed(inventory: Node, effects: Dictionary)
signal commerce_committed(receipt: Dictionary)
@export var host_enabled := true
@export_range(1,100000,1) var rental_price := 30
@export_range(1,604800,1) var rental_duration := 3600.0
@export_range(1,100000,1) var blessing_amount := 100
@export var meal_price := 8
@export var draught_price := 12
@export var meal_duration := 2.0
@export var draught_duration := 3.0
@export var meal_healing := 60.0
@export var draught_healing := 120.0
var player_inventory: Node
var validator: Callable
var external_transaction_guard: Callable
var npc_validator: Callable
var merchant_ids := {"guild":"guild_receptionist","tavern":"tavern_bartender"}
var wonder_offers := {"cyan_mantle":5}
var owner_id := ""
var player_account := ""
var guild_account := "business:guild"
var tavern_account := "business:tavern"
var natural_ids: Array[String] = []
var active_ids: Array[String] = []
var balances: Dictionary = {}
var issued_total := 0
var destroyed_total := 0
var last_cycle := -1
var sequence := 0
var audit_base: Dictionary = {}
var journal: Array[Dictionary] = []
var rental: Dictionary = {}
var room_stores: Dictionary = {}
var guild_stock: Node
var npc_stores: Dictionary = {}
var service_tokens: Dictionary = {}
var _initial_ids: Array[String] = []
var _busy := false

static func resident_account(id: String) -> String: return "resident:"+id
static func storage_owner(owner: String,room: int) -> String: return "room:"+owner+":"+str(room)

func transaction_active() -> bool: return _busy

func _externally_busy() -> bool:
	return external_transaction_guard.is_valid() and bool(external_transaction_guard.call())

func configure(owner: String, eligible_natural_ids: Array) -> bool:
	if not host_enabled or _busy or _externally_busy() or not Instance.valid_text(owner,false,64): return false
	var ids := _natural_list(eligible_natural_ids,owner)
	if ids.is_empty() or ids.size()>MAX_ACTIVE: return false
	if not owner_id.is_empty(): return owner_id==owner and ids==natural_ids
	owner_id = owner
	player_account = "player:"+owner
	natural_ids.assign(ids)
	active_ids.assign(ids)
	_initial_ids.assign(ids)
	for account: String in _account_ids(owner,natural_ids): balances[account] = 0
	audit_base = {"balances":balances.duplicate(),"issued_total":0,"destroyed_total":0,"last_cycle":-1,"sequence":0,"known_ids":natural_ids.duplicate(),"active_ids":active_ids.duplicate()}
	for room in range(ROOM_COUNT): room_stores[room] = _new_store(storage_owner(owner,room),"RoomStorage"+str(room))
	guild_stock = _new_store(guild_account,"GuildStock")
	return true

func _new_store(owner: String,label: String) -> Node:
	var store := Inventory.new()
	store.owner_id = owner
	store.name = label
	store.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(store)
	return store

func balance(account: String) -> int: return int(balances.get(account,0))

func _state() -> Dictionary:
	return {"balances":balances,"issued_total":issued_total,"destroyed_total":destroyed_total,"last_cycle":last_cycle,"sequence":sequence,"known_ids":natural_ids,"active_ids":active_ids}

func _append_event(entry: Dictionary) -> bool:
	entry.sequence = sequence+1
	var state := _state()
	if not _apply_event(state,entry): return false
	issued_total = state.issued_total
	destroyed_total = state.destroyed_total
	last_cycle = state.last_cycle
	sequence = state.sequence
	journal.append(entry.duplicate(true))
	if journal.size()>JOURNAL_LIMIT:
		_apply_event(audit_base,journal.pop_front())
	return true

func bless_cycle(cycle: int, eligible_natural_ids: Array) -> bool:
	# Only explicit host issuance. Visiting humans have no resident accounts.
	if not host_enabled or _busy or _externally_busy() or owner_id.is_empty() or cycle<=last_cycle or cycle<0: return false
	var recipients: Array[String] = []
	if not eligible_natural_ids.is_empty():
		recipients = _natural_list(eligible_natural_ids,owner_id)
		if recipients.is_empty(): return false
	if recipients!=active_ids: return false
	if not Instance.whole_number(blessing_amount,1,100000): return false
	_busy = true
	var accepted := _append_event({"kind":"issue","cycle":cycle,"amount":blessing_amount,"recipients":recipients})
	if accepted: changed.emit()
	_busy = false
	return accepted

func enroll_code_form(id: String,opening_amount: int = 0) -> bool:
	if not host_enabled or _busy or _externally_busy() or owner_id.is_empty() or natural_ids.has(id): return false
	if _natural_list([id],owner_id).is_empty() or natural_ids.size()>=MAX_RESIDENTS or active_ids.size()>=MAX_ACTIVE or opening_amount<0 or opening_amount>100000: return false
	var account := resident_account(id)
	_busy = true
	balances[account] = 0
	audit_base.balances[account] = 0
	var accepted := _append_event({"kind":"enroll","resident_id":id,"amount":opening_amount})
	if not accepted:
		balances.erase(account)
		audit_base.balances.erase(account)
	else: changed.emit()
	_busy = false
	return accepted

func retire_code_form(id: String) -> bool:
	if not host_enabled or _busy or _externally_busy() or id not in active_ids: return false
	_busy = true
	var accepted := _append_event({"kind":"retire","resident_id":id})
	if accepted: changed.emit()
	_busy = false
	return accepted

func npc_store(id: String) -> Node:
	if not natural_ids.has(id): return null
	if npc_stores.has(id): return npc_stores[id]
	if not host_enabled or _busy or _externally_busy(): return null
	npc_stores[id] = _new_store(resident_account(id),"CodeFormStore"+str(npc_stores.size()))
	return npc_stores[id]

func _npc_allowed(id: String,operation: StringName,payload: Dictionary) -> bool:
	return host_enabled and not _busy and not _externally_busy() and id in active_ids and (not npc_validator.is_valid() or bool(npc_validator.call(operation,payload)))

func _receipt(context: String,amount: int,participants: Array,counterpart: String) -> void:
	var eligible: Array[String] = []
	for id: Variant in participants:
		if String(id) in active_ids and not eligible.has(String(id)): eligible.append(String(id))
	if eligible.is_empty(): return
	commerce_committed.emit({"id":owner_id+":commerce:"+str(sequence),"sequence":sequence,"context":context,"amount":amount,"participants":eligible,"counterpart":counterpart})

func npc_buy_food(id: String,type: StringName) -> bool:
	if not _npc_allowed(id,&"npc_buy_food",{"id":id,"type_id":type}): return false
	var offer := food_offer(type)
	if offer.is_empty() or not _can_pay(resident_account(id),tavern_account,offer.price): return false
	var store := npc_store(id)
	return _purchase_item(store,type,{"kind":"transfer","from":resident_account(id),"to":tavern_account,"amount":offer.price,"reason":"Code Form tavern purchase"},"food",[id,merchant_ids.get("tavern","")],tavern_account)

func npc_consume_food(id: String,type: StringName) -> bool:
	if not _npc_allowed(id,&"npc_consume_food",{"id":id,"type_id":type}) or food_offer(type).is_empty(): return false
	var store := npc_store(id)
	if store==null: return false
	for item: Resource in store.items.values():
		if item.item_type_id!=type: continue
		_busy = true
		var consumed: Resource = store.take_item(item.instance_id,1)
		if consumed!=null:
			consumed.quantity = 0
			changed.emit()
		_busy = false
		return consumed!=null
	return false

func npc_sell_crystal(id: String,iid: String,qty: int) -> bool:
	if not _npc_allowed(id,&"npc_sell_crystal",{"id":id,"instance_id":iid,"quantity":qty}): return false
	var store := npc_store(id)
	var item: Resource = store.get_item(iid) if store!=null else null
	if item==null or qty<=0 or qty>item.quantity: return false
	var unit := crystal_price(item.item_type_id)
	if unit<=0 or qty>COIN_CAP/unit or not _can_pay(guild_account,resident_account(id),unit*qty): return false
	return _move_item(store,guild_stock,iid,qty,{"kind":"transfer","from":guild_account,"to":resident_account(id),"amount":unit*qty,"reason":"Code Form crystal purchase"},{"context":"crystal_sale","amount":unit*qty,"participants":[id,merchant_ids.get("guild","")],"counterpart":guild_account})

func npc_service_wage(id: String,service_key: String,serial: int) -> bool:
	if not _npc_allowed(id,&"npc_service_wage",{"id":id,"service_key":service_key,"serial":serial}): return false
	var token := id+"|"+service_key
	if not WAGE_SERVICES.has(service_key) or serial<0 or serial>COIN_CAP or serial<=int(service_tokens.get(token,-1)) or not service_tokens.has(token) and service_tokens.size()>=MAX_SERVICE_TOKENS: return false
	var business: String = WAGE_SERVICES[service_key]
	if not _can_pay(business,resident_account(id),1): return false
	_busy = true
	var accepted := _append_event({"kind":"transfer","from":business,"to":resident_account(id),"amount":1,"reason":"Completed "+service_key})
	if accepted:
		service_tokens[token] = serial
		_receipt("wage:"+service_key,1,[id,merchant_ids.get("guild" if business==guild_account else "tavern","")],business)
		changed.emit()
	_busy = false
	return accepted

func purchase_wonder(id: String,type: StringName = &"cyan_mantle") -> bool:
	if not _npc_allowed(id,&"purchase_wonder",{"id":id,"type_id":type}): return false
	var price: Variant = wonder_offers.get(String(type))
	if not Instance.whole_number(price,1,100000): return false
	var definition: Resource = Catalog.get_definition(type)
	if definition==null or definition.category!=&"cosmetics" or definition.is_equippable: return false
	var account := resident_account(id)
	if sequence>=COIN_CAP or balance(account)<int(price): return false
	return _purchase_item(npc_store(id),type,{"kind":"destroy","from":account,"amount":int(price),"reason":"Glyphic Wonders purchase"},"wonder",[id],"glyphic_wonders")

func _purchase_item(store: Node,type: StringName,event: Dictionary,context: String,participants: Array,counterpart: String) -> bool:
	if store==null: return false
	var item: Resource = Catalog.create(type)
	var shadow := _shadow(store)
	if item==null or shadow==null:
		if shadow!=null: shadow.free()
		return false
	var fits: bool = shadow.add_item(item.duplicate(true))
	shadow.free()
	if not fits: return false
	_busy = true
	var before: Dictionary = store.serialize()
	var blocked: bool = store.is_blocking_signals()
	store.set_block_signals(true)
	var accepted: bool = store.add_item(item)
	if accepted:
		accepted = _append_event(event)
		if not accepted: store.restore(before)
	store.set_block_signals(blocked)
	if accepted:
		if not blocked: store.changed.emit()
		_receipt(context,int(event.amount),participants,counterpart)
		changed.emit()
	_busy = false
	return accepted

func transfer(from: String,to: String,amount: int,reason: String = "Transfer") -> bool:
	# Trusted host settlement; commerce uses the narrower request methods below.
	if not host_enabled or _busy or _externally_busy() or not _can_pay(from,to,amount) or not Instance.valid_text(reason): return false
	_busy = true
	var accepted := _append_event({"kind":"transfer","from":from,"to":to,"amount":amount,"reason":reason})
	if accepted: changed.emit()
	_busy = false
	return accepted

func _can_pay(from: String,to: String,amount: int) -> bool:
	return sequence<COIN_CAP and from!=to and balances.has(from) and balances.has(to) and amount>0 and amount<=COIN_CAP and balance(from)>=amount and balance(to)<=COIN_CAP-amount

func _allowed(operation: StringName,payload: Dictionary) -> bool:
	return host_enabled and not _busy and not _externally_busy() and not owner_id.is_empty() and (not validator.is_valid() or bool(validator.call(operation,payload)))

func _valid_inventory(inventory: Node) -> bool:
	return is_instance_valid(inventory) and inventory is Inventory and inventory.owner_id==owner_id and is_instance_valid(player_inventory) and player_inventory==inventory

func can_enter(room: int) -> bool:
	return room>=0 and room<ROOM_COUNT and rental.get("owner","")==owner_id and rental.get("room",-1)==room and float(rental.get("expires_at",0))>Time.get_unix_time_from_system()

func rent(room: int) -> bool:
	if room<0 or room>=ROOM_COUNT or not _allowed(&"rent",{"room":room}): return false
	if not Instance.whole_number(rental_price,1,100000) or not is_finite(rental_duration) or rental_duration<1 or rental_duration>604800: return false
	if not _can_pay(player_account,guild_account,rental_price): return false
	if not rental.is_empty() and can_enter(int(rental.room)) and rental.room!=room: return false
	_busy = true
	if not _append_event({"kind":"transfer","from":player_account,"to":guild_account,"amount":rental_price,"reason":"Room rental"}):
		_busy = false
		return false
	var begins := maxf(Time.get_unix_time_from_system(),float(rental.get("expires_at",0))) if rental.get("room",-1)==room else Time.get_unix_time_from_system()
	rental = {"room":room,"owner":owner_id,"expires_at":begins+rental_duration}
	_receipt("rental",rental_price,[merchant_ids.get("guild","")],guild_account)
	changed.emit()
	_busy = false
	return true

func crystal_price(type: StringName) -> int: return int(CRYSTALS.get(String(type),0))

func sell_crystal(iid: String,qty: int,inventory: Node) -> bool:
	if not _valid_inventory(inventory) or not _allowed(&"sell_crystal",{"inventory":inventory,"instance_id":iid,"quantity":qty}): return false
	var item: Resource = inventory.get_item(iid)
	if item==null or qty<=0 or qty>item.quantity: return false
	var unit := crystal_price(item.item_type_id)
	if unit<=0 or qty>COIN_CAP/unit: return false
	var amount := unit*qty
	if not _can_pay(guild_account,player_account,amount): return false
	return _move_item(inventory,guild_stock,iid,qty,{"kind":"transfer","from":guild_account,"to":player_account,"amount":amount,"reason":"Monster crystal purchase"},{"context":"crystal_sale","amount":amount,"participants":[merchant_ids.get("guild","")],"counterpart":guild_account})

func food_offer(type: StringName) -> Dictionary:
	if type not in FOOD: return {}
	var offer := {"type_id":String(type),"price":meal_price if type==&"electron_meal" else draught_price,"duration":meal_duration if type==&"electron_meal" else draught_duration,"healing":meal_healing if type==&"electron_meal" else draught_healing}
	if not Instance.whole_number(offer.price,1,100000): return {}
	if not is_finite(float(offer.duration)) or offer.duration<.1 or offer.duration>60: return {}
	if not is_finite(float(offer.healing)) or offer.healing<=0 or offer.healing>1000: return {}
	return offer

func buy_food(type: StringName,inventory: Node) -> bool:
	if not _valid_inventory(inventory) or not _allowed(&"buy_food",{"inventory":inventory,"type_id":type}): return false
	var offer := food_offer(type)
	if offer.is_empty() or not _can_pay(player_account,tavern_account,offer.price): return false
	return _purchase_item(inventory,type,{"kind":"transfer","from":player_account,"to":tavern_account,"amount":offer.price,"reason":"Tavern purchase"},"food",[merchant_ids.get("tavern","")],tavern_account)

func transfer_storage(room: int,iid: String,qty: int,to_storage: bool,inventory: Node) -> bool:
	if not _valid_inventory(inventory) or not can_enter(room): return false
	if not _allowed(&"storage",{"inventory":inventory,"room":room,"instance_id":iid,"quantity":qty,"to_storage":to_storage}): return false
	var store: Node = room_stores[room]
	return _move_item(inventory if to_storage else store,store if to_storage else inventory,iid,qty)

func _shadow(source: Node) -> Node:
	var copy := Inventory.new()
	if not copy.restore(source.serialize()):
		copy.free()
		return null
	return copy

func _move_item(source: Node,destination: Node,iid: String,qty: int,coin_event: Dictionary = {},receipt: Dictionary = {}) -> bool:
	var item: Resource = source.get_item(iid)
	if item==null or qty<=0 or qty>item.quantity or item.owner_id!=source.owner_id: return false
	var definition: Resource = Catalog.get_definition(item.item_type_id)
	if definition==null or not definition.is_tradeable or not definition.is_droppable: return false
	var from_shadow := _shadow(source)
	var to_shadow := _shadow(destination)
	if from_shadow==null or to_shadow==null:
		if from_shadow!=null: from_shadow.free()
		if to_shadow!=null: to_shadow.free()
		return false
	var preview: Resource = from_shadow.take_item(iid,qty)
	var fits: bool = preview!=null and to_shadow.add_item(preview)
	from_shadow.free()
	to_shadow.free()
	if not fits: return false
	_busy = true
	var before: Dictionary = source.serialize()
	var destination_before: Dictionary = destination.serialize()
	var source_blocked: bool = source.is_blocking_signals()
	var destination_blocked: bool = destination.is_blocking_signals()
	source.set_block_signals(true)
	destination.set_block_signals(true)
	var moved: Resource = source.take_item(iid,qty)
	var accepted: bool = moved!=null and destination.add_item(moved)
	if accepted and not coin_event.is_empty(): accepted = _append_event(coin_event)
	if not accepted:
		source.restore(before)
		destination.restore(destination_before)
	source.set_block_signals(source_blocked)
	destination.set_block_signals(destination_blocked)
	if accepted:
		if not source_blocked:
			source.equipment_changed.emit()
			source.changed.emit()
		if not destination_blocked: destination.changed.emit()
		if not receipt.is_empty(): _receipt(receipt.context,int(receipt.amount),receipt.participants,receipt.counterpart)
		changed.emit()
	_busy = false
	return accepted

func consume_food(iid: String,inventory: Node) -> bool:
	if not _valid_inventory(inventory) or not _allowed(&"consume_food",{"inventory":inventory,"instance_id":iid}): return false
	var item: Resource = inventory.get_item(iid)
	if item==null or item.owner_id!=owner_id: return false
	var offer := food_offer(item.item_type_id)
	if offer.is_empty(): return false
	var actor: Node = inventory.actor
	var combat: Node = actor.get("weapon_combat") if is_instance_valid(actor) else null
	if not is_instance_valid(combat) or combat.health<=0 or combat.health>=combat.max_health: return false
	_busy = true
	var consumed: Resource = inventory.take_item(iid,1)
	if consumed!=null:
		consumed.quantity = 0
		food_consumed.emit(inventory,offer.duplicate(true))
		changed.emit()
	_busy = false
	return consumed!=null

func serialize() -> Dictionary:
	if owner_id.is_empty(): return {}
	var stores: Dictionary = {}
	for room: int in room_stores: stores[str(room)] = room_stores[room].serialize()
	var npc: Dictionary = {}
	for id: String in npc_stores: npc[id] = npc_stores[id].serialize()
	return {"version":2,"owner_id":owner_id,"natural_ids":natural_ids.duplicate(),"active_ids":active_ids.duplicate(),"balances":balances.duplicate(),"issued_total":issued_total,"destroyed_total":destroyed_total,"last_cycle":last_cycle,"sequence":sequence,"audit_base":audit_base.duplicate(true),"journal":journal.duplicate(true),"rental":rental.duplicate(true),"room_stores":stores,"guild_stock":guild_stock.serialize(),"npc_stores":npc,"service_tokens":service_tokens.duplicate()}

func restore(data: Variant) -> bool:
	if not host_enabled or _busy or _externally_busy(): return false
	var decoded := validate(data,player_inventory.serialize() if is_instance_valid(player_inventory) else {})
	if decoded.is_empty() or not owner_id.is_empty() and decoded.owner_id!=owner_id: return false
	for id: String in _initial_ids:
		if id not in decoded.natural_ids: return false
	var replacements: Dictionary = {}
	for room in range(ROOM_COUNT):
		var store := Inventory.new()
		if not store.restore(decoded.room_stores[str(room)]):
			store.free()
			for previous: Node in replacements.values(): previous.free()
			return false
		replacements[room] = store
	var stock := Inventory.new()
	stock.restore(decoded.guild_stock)
	var npc: Dictionary = {}
	for id: String in decoded.npc_stores:
		var store := Inventory.new()
		store.restore(decoded.npc_stores[id])
		npc[id] = store
	_busy = true
	for previous: Node in room_stores.values(): previous.free()
	if is_instance_valid(guild_stock): guild_stock.free()
	for previous: Node in npc_stores.values(): previous.free()
	owner_id = decoded.owner_id
	player_account = "player:"+owner_id
	natural_ids.assign(decoded.natural_ids)
	active_ids.assign(decoded.active_ids)
	balances = decoded.balances
	issued_total = decoded.issued_total
	destroyed_total = decoded.destroyed_total
	last_cycle = decoded.last_cycle
	sequence = decoded.sequence
	audit_base = decoded.audit_base
	journal.assign(decoded.journal)
	rental = decoded.rental
	service_tokens = decoded.service_tokens
	room_stores = replacements
	for room: int in room_stores:
		room_stores[room].name = "RoomStorage"+str(room)
		room_stores[room].process_mode = Node.PROCESS_MODE_DISABLED
		add_child(room_stores[room])
	guild_stock = stock
	guild_stock.name = "GuildStock"
	guild_stock.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(guild_stock)
	npc_stores = npc
	for id: String in npc_stores:
		npc_stores[id].process_mode = Node.PROCESS_MODE_DISABLED
		add_child(npc_stores[id])
	changed.emit()
	_busy = false
	return true

static func _natural_list(input: Variant,owner: String) -> Array[String]:
	var result: Array[String] = []
	if not input is Array or input.is_empty() or input.size()>MAX_RESIDENTS: return result
	var seen: Dictionary = {}
	for id: Variant in input:
		if not Instance.valid_text(id,false,64): return []
		var natural_id := String(id)
		if natural_id==owner or ":" in natural_id or "|" in natural_id or seen.has(natural_id): return []
		seen[natural_id] = true
		result.append(natural_id)
	result.sort()
	return result

static func _id_set(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id: String in ids: result[id] = true
	return result

static func _account_ids(owner: String,ids: Array) -> Array[String]:
	var result: Array[String] = ["player:"+owner,"business:guild","business:tavern"]
	for id: String in ids: result.append(resident_account(id))
	return result

static func _balances(input: Variant,accounts: Array[String]) -> Dictionary:
	if not input is Dictionary or input.size()!=accounts.size(): return {}
	var result: Dictionary = {}
	for account: String in accounts:
		if not Instance.whole_number(input.get(account),0,COIN_CAP): return {}
		result[account] = int(input[account])
	return result

static func _apply_legacy_event(state: Dictionary,entry: Dictionary,ids: Array) -> bool:
	if not Instance.whole_number(entry.get("sequence"),1,COIN_CAP) or int(entry.sequence)!=state.sequence+1: return false
	var coins: Dictionary = state.balances
	if entry.get("kind")=="issue":
		if entry.size()!=4 or not Instance.whole_number(entry.get("cycle"),0,COIN_CAP) or entry.cycle<=state.last_cycle or not Instance.whole_number(entry.get("amount"),1,100000): return false
		var amount := int(entry.amount)
		if state.issued_total>COIN_CAP-amount*ids.size(): return false
		for id: String in ids:
			if int(coins.get(resident_account(id),COIN_CAP))>COIN_CAP-amount: return false
		for id: String in ids: coins[resident_account(id)] += amount
		state.issued_total += amount*ids.size()
		state.last_cycle = int(entry.cycle)
	elif entry.get("kind")=="transfer":
		if entry.size()!=6 or not Instance.valid_text(entry.get("reason")) or not entry.get("from") is String or not entry.get("to") is String: return false
		if entry.from==entry.to or not coins.has(entry.from) or not coins.has(entry.to) or not Instance.whole_number(entry.get("amount"),1,COIN_CAP): return false
		var amount := int(entry.amount)
		if coins[entry.from]<amount or coins[entry.to]>COIN_CAP-amount: return false
		coins[entry.from] -= amount
		coins[entry.to] += amount
	else: return false
	state.sequence = int(entry.sequence)
	return true

static func _apply_event(state: Dictionary,entry: Dictionary) -> bool:
	if not Instance.whole_number(entry.get("sequence"),1,COIN_CAP) or int(entry.sequence)!=state.sequence+1: return false
	var coins: Dictionary = state.balances
	match entry.get("kind"):
		"issue":
			if entry.size()!=5 or not Instance.whole_number(entry.get("cycle"),0,COIN_CAP) or entry.cycle<=state.last_cycle or not Instance.whole_number(entry.get("amount"),1,100000) or not entry.get("recipients") is Array: return false
			var recipients: Array = entry.recipients.duplicate()
			for id: Variant in recipients:
				if not (id is String or id is StringName): return false
			recipients.sort()
			if recipients!=state.active_ids: return false
			var amount := int(entry.amount)
			if state.issued_total>COIN_CAP-amount*recipients.size(): return false
			for id: String in recipients:
				if int(coins.get(resident_account(id),COIN_CAP))>COIN_CAP-amount: return false
			for id: String in recipients: coins[resident_account(id)] += amount
			state.issued_total += amount*recipients.size()
			state.last_cycle = int(entry.cycle)
		"enroll":
			if entry.size()!=4 or not entry.get("resident_id") is String or entry.resident_id in state.known_ids or state.known_ids.size()>=MAX_RESIDENTS or state.active_ids.size()>=MAX_ACTIVE or not Instance.whole_number(entry.get("amount"),0,100000): return false
			var account := resident_account(entry.resident_id)
			if not coins.has(account) or coins[account]!=0 or state.issued_total>COIN_CAP-int(entry.amount): return false
			state.known_ids.append(entry.resident_id)
			state.known_ids.sort()
			state.active_ids.append(entry.resident_id)
			state.active_ids.sort()
			coins[account] = int(entry.amount)
			state.issued_total += int(entry.amount)
		"retire":
			if entry.size()!=3 or not entry.get("resident_id") is String or entry.resident_id not in state.active_ids: return false
			state.active_ids.erase(entry.resident_id)
		"transfer":
			if entry.size()!=6 or not Instance.valid_text(entry.get("reason")) or not entry.get("from") is String or not entry.get("to") is String or entry.from==entry.to: return false
			if not coins.has(entry.from) or not coins.has(entry.to) or not Instance.whole_number(entry.get("amount"),1,COIN_CAP): return false
			var amount := int(entry.amount)
			if coins[entry.from]<amount or coins[entry.to]>COIN_CAP-amount: return false
			coins[entry.from] -= amount
			coins[entry.to] += amount
		"destroy":
			if entry.size()!=5 or not entry.get("from") is String or not coins.has(entry.from) or not Instance.valid_text(entry.get("reason")) or not Instance.whole_number(entry.get("amount"),1,COIN_CAP): return false
			var amount := int(entry.amount)
			if coins[entry.from]<amount or state.destroyed_total>COIN_CAP-amount: return false
			coins[entry.from] -= amount
			state.destroyed_total += amount
		_: return false
	state.sequence = int(entry.sequence)
	return true

static func _inventory_snapshot(input: Variant,owner: String,identities: Dictionary) -> Dictionary:
	var store := Inventory.new()
	if not store.restore(input):
		store.free()
		return {}
	var snapshot: Dictionary = store.serialize()
	store.free()
	if snapshot.owner_id!=owner or not snapshot.equipment.is_empty() or not snapshot.get("respawn_points",{}).is_empty() or not snapshot.get("shield_state",{}).is_empty() or not snapshot.get("boss_reward_claims",{}).is_empty(): return {}
	for item: Dictionary in snapshot.items:
		if identities.has(item.instance_id): return {}
		identities[item.instance_id] = true
	return snapshot

static func _validate_v1(input: Variant,player: Dictionary = {},world_drops: Array = []) -> Dictionary:
	if not input is Dictionary or input.size()!=12 or not Instance.whole_number(input.get("version"),1,1) or not Instance.valid_text(input.get("owner_id"),false,64): return {}
	var owner := String(input.owner_id)
	var ids := _natural_list(input.get("natural_ids"),owner)
	if ids.is_empty(): return {}
	var accounts := _account_ids(owner,ids)
	var coins := _balances(input.get("balances"),accounts)
	if coins.is_empty() or not Instance.whole_number(input.get("issued_total"),0,COIN_CAP) or not Instance.whole_number(input.get("last_cycle"),-1,COIN_CAP) or not Instance.whole_number(input.get("sequence"),0,COIN_CAP): return {}
	var total := 0
	for value: int in coins.values(): total += value
	if total!=int(input.issued_total): return {}
	if not input.get("audit_base") is Dictionary or input.audit_base.size()!=4: return {}
	var base_coins := _balances(input.audit_base.get("balances"),accounts)
	if base_coins.is_empty() or not Instance.whole_number(input.audit_base.get("issued_total"),0,COIN_CAP) or not Instance.whole_number(input.audit_base.get("last_cycle"),-1,COIN_CAP) or not Instance.whole_number(input.audit_base.get("sequence"),0,int(input.sequence)): return {}
	var base := {"balances":base_coins,"issued_total":int(input.audit_base.issued_total),"last_cycle":int(input.audit_base.last_cycle),"sequence":int(input.audit_base.sequence)}
	total = 0
	for value: int in base_coins.values(): total += value
	if total!=base.issued_total: return {}
	if base.sequence==0 and (base.issued_total!=0 or base.last_cycle!=-1): return {}
	if not input.get("journal") is Array or input.journal.size()>JOURNAL_LIMIT: return {}
	var replay: Dictionary = base.duplicate(true)
	var entries: Array[Dictionary] = []
	for event: Variant in input.journal:
		if not event is Dictionary or not _apply_legacy_event(replay,event,ids): return {}
		entries.append(Instance.json_copy(event))
	if replay.balances!=coins or replay.issued_total!=int(input.issued_total) or replay.last_cycle!=int(input.last_cycle) or replay.sequence!=int(input.sequence): return {}
	if not input.get("rental") is Dictionary: return {}
	var rental_record: Dictionary = input.rental
	if not rental_record.is_empty():
		if rental_record.size()!=3 or rental_record.get("owner")!=owner or not Instance.whole_number(rental_record.get("room"),0,ROOM_COUNT-1): return {}
		if not (rental_record.get("expires_at") is float or rental_record.get("expires_at") is int) or not is_finite(float(rental_record.expires_at)) or rental_record.expires_at<=0: return {}
	var identities: Dictionary = {}
	if not player.is_empty():
		if player.get("owner_id")!=owner or not player.get("items") is Array: return {}
		for item: Variant in player.items:
			if not item is Dictionary or not Instance.valid_text(item.get("instance_id")) or identities.has(item.instance_id): return {}
			identities[item.instance_id] = true
	for drop: Variant in world_drops:
		if not drop is Dictionary or not drop.get("item") is Dictionary or not Instance.valid_text(drop.item.get("instance_id")) or identities.has(drop.item.instance_id): return {}
		identities[drop.item.instance_id] = true
	if not input.get("room_stores") is Dictionary or input.room_stores.size()!=ROOM_COUNT: return {}
	var stores: Dictionary = {}
	for room in range(ROOM_COUNT):
		var snapshot := _inventory_snapshot(input.room_stores.get(str(room)),storage_owner(owner,room),identities)
		if snapshot.is_empty(): return {}
		stores[str(room)] = snapshot
	var stock := _inventory_snapshot(input.get("guild_stock"),"business:guild",identities)
	if stock.is_empty(): return {}
	return {"version":1,"owner_id":owner,"natural_ids":ids,"balances":coins,"issued_total":int(input.issued_total),"last_cycle":int(input.last_cycle),"sequence":int(input.sequence),"audit_base":base,"journal":entries,"rental":Instance.json_copy(rental_record),"room_stores":stores,"guild_stock":stock}

static func _migrate_v1(legacy: Dictionary) -> Dictionary:
	if legacy.is_empty(): return {}
	var result := legacy.duplicate(true)
	result.version = 2
	result.active_ids = result.natural_ids.duplicate()
	result.destroyed_total = 0
	result.npc_stores = {}
	result.service_tokens = {}
	result.audit_base.known_ids = result.natural_ids.duplicate()
	result.audit_base.active_ids = result.natural_ids.duplicate()
	result.audit_base.destroyed_total = 0
	for event: Dictionary in result.journal:
		if event.kind=="issue": event.recipients = result.natural_ids.duplicate()
	return result

static func _subset_ids(input: Variant,owner: String,known: Dictionary,maximum: int = MAX_RESIDENTS) -> Variant:
	if not input is Array or input.size()>maximum: return null
	if input.is_empty(): return []
	var ids := _natural_list(input,owner)
	if ids.is_empty(): return null
	for id: String in ids:
		if not known.has(id): return null
	return ids

static func validate(input: Variant,player: Dictionary = {},world_drops: Array = []) -> Dictionary:
	if not input is Dictionary: return {}
	if input.get("version")==1:
		var migrated := _migrate_v1(_validate_v1(input,player,world_drops))
		return validate(migrated,player,world_drops) if not migrated.is_empty() else {}
	if input.size()!=16 or not Instance.whole_number(input.get("version"),2,2) or not Instance.valid_text(input.get("owner_id"),false,64): return {}
	var owner := String(input.owner_id)
	var known := _natural_list(input.get("natural_ids"),owner)
	if known.is_empty(): return {}
	# Lists stay sorted in the canonical save/audit format. Transient hash sets
	# keep validation linear when a world has thousands of civilian accounts.
	var known_set := _id_set(known)
	var active: Variant = _subset_ids(input.get("active_ids"),owner,known_set,MAX_ACTIVE)
	if active==null: return {}
	var accounts := _account_ids(owner,known)
	var coins := _balances(input.get("balances"),accounts)
	if coins.is_empty() or not Instance.whole_number(input.get("issued_total"),0,COIN_CAP) or not Instance.whole_number(input.get("destroyed_total"),0,COIN_CAP) or not Instance.whole_number(input.get("last_cycle"),-1,COIN_CAP) or not Instance.whole_number(input.get("sequence"),0,COIN_CAP): return {}
	var total := int(input.destroyed_total)
	for value: int in coins.values(): total += value
	if total!=int(input.issued_total): return {}
	if not input.get("audit_base") is Dictionary or input.audit_base.size()!=7: return {}
	var base_input: Dictionary = input.audit_base
	var base_coins := _balances(base_input.get("balances"),accounts)
	var base_known: Variant = _subset_ids(base_input.get("known_ids"),owner,known_set)
	var base_active: Variant = _subset_ids(base_input.get("active_ids"),owner,known_set,MAX_ACTIVE)
	if base_known==null or base_active==null or base_coins.is_empty() or not Instance.whole_number(base_input.get("issued_total"),0,COIN_CAP) or not Instance.whole_number(base_input.get("destroyed_total"),0,COIN_CAP) or not Instance.whole_number(base_input.get("last_cycle"),-1,COIN_CAP) or not Instance.whole_number(base_input.get("sequence"),0,int(input.sequence)): return {}
	var base_known_set := _id_set(base_known)
	for id: String in base_active:
		if not base_known_set.has(id): return {}
	for id: String in known:
		if not base_known_set.has(id) and base_coins[resident_account(id)]!=0: return {}
	var base := {"balances":base_coins,"issued_total":int(base_input.issued_total),"destroyed_total":int(base_input.destroyed_total),"last_cycle":int(base_input.last_cycle),"sequence":int(base_input.sequence),"known_ids":base_known,"active_ids":base_active}
	total = base.destroyed_total
	for value: int in base_coins.values(): total += value
	if total!=base.issued_total or base.destroyed_total>base.issued_total: return {}
	if base.sequence==0 and (base.issued_total!=0 or base.destroyed_total!=0 or base.last_cycle!=-1 or base.active_ids!=base.known_ids): return {}
	if not input.get("journal") is Array or input.journal.size()>JOURNAL_LIMIT: return {}
	var replay := base.duplicate(true)
	var entries: Array[Dictionary] = []
	for event: Variant in input.journal:
		if not event is Dictionary or not _apply_event(replay,event): return {}
		entries.append(Instance.json_copy(event))
	if replay.balances!=coins or replay.issued_total!=int(input.issued_total) or replay.destroyed_total!=int(input.destroyed_total) or replay.last_cycle!=int(input.last_cycle) or replay.sequence!=int(input.sequence) or replay.known_ids!=known or replay.active_ids!=active: return {}
	if not input.get("rental") is Dictionary: return {}
	var rental_record: Dictionary = input.rental
	if not rental_record.is_empty():
		if rental_record.size()!=3 or rental_record.get("owner")!=owner or not Instance.whole_number(rental_record.get("room"),0,ROOM_COUNT-1): return {}
		if not (rental_record.get("expires_at") is float or rental_record.get("expires_at") is int) or not is_finite(float(rental_record.expires_at)) or rental_record.expires_at<=0: return {}
	var identities: Dictionary = {}
	if not player.is_empty():
		if player.get("owner_id")!=owner or not player.get("items") is Array: return {}
		for item: Variant in player.items:
			if not item is Dictionary or not Instance.valid_text(item.get("instance_id")) or identities.has(item.instance_id): return {}
			identities[item.instance_id] = true
	for drop: Variant in world_drops:
		if not drop is Dictionary or not drop.get("item") is Dictionary or not Instance.valid_text(drop.item.get("instance_id")) or identities.has(drop.item.instance_id): return {}
		identities[drop.item.instance_id] = true
	if not input.get("room_stores") is Dictionary or input.room_stores.size()!=ROOM_COUNT: return {}
	var stores: Dictionary = {}
	for room in range(ROOM_COUNT):
		var snapshot := _inventory_snapshot(input.room_stores.get(str(room)),storage_owner(owner,room),identities)
		if snapshot.is_empty(): return {}
		stores[str(room)] = snapshot
	var stock := _inventory_snapshot(input.get("guild_stock"),"business:guild",identities)
	if stock.is_empty(): return {}
	if not input.get("npc_stores") is Dictionary or input.npc_stores.size()>MAX_RESIDENTS: return {}
	var npc: Dictionary = {}
	for id: Variant in input.npc_stores:
		if not id is String or not known_set.has(id): return {}
		var snapshot := _inventory_snapshot(input.npc_stores[id],resident_account(id),identities)
		if snapshot.is_empty(): return {}
		npc[id] = snapshot
	if not input.get("service_tokens") is Dictionary or input.service_tokens.size()>MAX_SERVICE_TOKENS: return {}
	var tokens: Dictionary = {}
	for token: Variant in input.service_tokens:
		if not token is String: return {}
		var parts := String(token).split("|")
		if parts.size()!=2 or not known_set.has(parts[0]) or not WAGE_SERVICES.has(parts[1]) or not Instance.whole_number(input.service_tokens[token],0,COIN_CAP): return {}
		tokens[token] = int(input.service_tokens[token])
	return {"version":2,"owner_id":owner,"natural_ids":known,"active_ids":active,"balances":coins,"issued_total":int(input.issued_total),"destroyed_total":int(input.destroyed_total),"last_cycle":int(input.last_cycle),"sequence":int(input.sequence),"audit_base":base,"journal":entries,"rental":Instance.json_copy(rental_record),"room_stores":stores,"guild_stock":stock,"npc_stores":npc,"service_tokens":tokens}
