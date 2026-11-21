extends Node
## Event-driven, host-owned money and room contents, independent of geometry.
const Inventory = preload("res://scripts/inventory.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const WonderStock = preload("res://scripts/glyphic_wonders_stock.gd")
const Cuisine = preload("res://scripts/electron_cuisine.gd")
const FoodShields = preload("res://scripts/shield_glyphs.gd")
const ROOM_COUNT := 3
const COIN_CAP := 1000000000
const JOURNAL_LIMIT := 128
const MAX_RESIDENTS := 16384
const MAX_ACTIVE := 2048
const MAX_SERVICE_TOKENS := 65536
const MAX_FACTIONS := 64
const MAX_GUILDS := 128
const MAX_CONTRACTS := 2048
const ESCROW_ACCOUNT := "contracts:escrow"
const WAGE_SERVICES := {"guild_work":"business:guild","tavern_work":"business:tavern"}
const CRYSTALS := {"monster_glyph_common":12,"monster_glyph_uncommon":30,"monster_glyph_rare":75,"apep_lorai_catalyst":180}
const FOOD := [&"electron_meal",&"electron_draught"]
signal changed
signal food_consumed(inventory: Node, effects: Dictionary)
signal npc_food_consumed(id: String, effects: Dictionary)
signal commerce_committed(receipt: Dictionary)
signal transaction_committed(receipt: Dictionary)
signal wonder_purchase_committed(token: String,buyer: String)
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
@export_range(1,1000,1) var food_hp_cap := 350.0
@export_range(250,1000,1) var drink_shield_cap := 1000.0
@export_range(.1,4,.1) var food_quality_min := .5
@export_range(.1,4,.1) var food_quality_max := 2.0
@export_range(0,1,.01) var food_complexity_factor := .06
@export_range(0,1,.01) var food_rarity_factor := .12
var player_inventory: Node
var validator: Callable
var external_transaction_guard: Callable
var npc_validator: Callable
var world_clock: Callable
var factions: Array[String] = []
var guilds: Array[String] = []
var contracts: Dictionary = {}
var _last_receipt: Dictionary = {}
var merchant_ids := {"guild":"guild_receptionist","tavern":"tavern_bartender"}
var wonder_offers := {"cyan_mantle":5}
var wonder_shop_attached := false
var wonder_authorizer: Callable
var _used_wonder_tokens: Dictionary = {}
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
var starter_influx_applied := false
var institution_influx_applied := false
var audit_base: Dictionary = {}
var journal: Array[Dictionary] = []
var rental: Dictionary = {}
var room_stores: Dictionary = {}
var guild_stock: Node
var npc_stores: Dictionary = {}
var service_tokens: Dictionary = {}
var _initial_ids: Array[String] = []
var _busy := false
var _capture_queue: Dictionary={}

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
	for account: String in _account_ids(owner,natural_ids,[ESCROW_ACCOUNT]): balances[account] = 0
	audit_base = {"balances":balances.duplicate(),"issued_total":0,"destroyed_total":0,"last_cycle":-1,"sequence":0,"known_ids":natural_ids.duplicate(),"active_ids":active_ids.duplicate(),"starter_influx":false,"institution_influx":false}
	for room in range(ROOM_COUNT): room_stores[room] = _new_store(storage_owner(owner,room),"RoomStorage"+str(room))
	guild_stock = _new_store(guild_account,"GuildStock")
	return true

func _new_store(owner: String,label: String) -> Node:
	var store := Inventory.new()
	store.owner_id = owner
	store.name = label
	store.process_mode = Node.PROCESS_MODE_DISABLED
	_track_capture(store)
	add_child(store)
	return store

func _track_capture(store: Node) -> void:
	store.capture_cache_enabled=true
	var reference: WeakRef=weakref(store)
	store.changed.connect(_queue_capture.bind(reference))
	_queue_capture(reference)

func _queue_capture(reference: WeakRef) -> void:
	var store: Node=reference.get_ref()
	if is_instance_valid(store): _capture_queue[store.get_instance_id()]=reference

func warm_capture() -> void:
	var began:=Time.get_ticks_usec()
	var count:=0
	for key: int in _capture_queue.keys():
		var store: Node=_capture_queue[key].get_ref()
		_capture_queue.erase(key)
		if is_instance_valid(store): store.capture_values()
		count+=1
		if count>=24 or Time.get_ticks_usec()-began>=2000: break

func balance(account: String) -> int: return int(balances.get(account,0))

func _state() -> Dictionary:
	return {"balances":balances,"issued_total":issued_total,"destroyed_total":destroyed_total,"last_cycle":last_cycle,"sequence":sequence,"known_ids":natural_ids,"active_ids":active_ids,"starter_influx":starter_influx_applied,"institution_influx":institution_influx_applied}

func _append_event(entry: Dictionary) -> bool:
	entry.sequence = sequence+1
	var state := _state()
	if not _apply_event(state,entry): return false
	issued_total = state.issued_total
	destroyed_total = state.destroyed_total
	last_cycle = state.last_cycle
	sequence = state.sequence
	starter_influx_applied = state.starter_influx
	institution_influx_applied = state.institution_influx
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

func issue_starter_influx(payouts: Dictionary) -> bool:
	# One authorized rollout for the current census, not a recurring income or
	# a commerce transaction. Its receipt survives journal compaction in base.
	if not host_enabled or _busy or _externally_busy() or owner_id.is_empty() or starter_influx_applied: return false
	_busy=true
	var accepted:=_append_event({"kind":"starter_influx","payouts":payouts.duplicate(true)})
	if accepted: changed.emit()
	_busy=false
	return accepted

func issue_institution_influx(payouts: Dictionary) -> bool:
	if not host_enabled or _busy or _externally_busy() or owner_id.is_empty() or institution_influx_applied: return false
	_busy=true
	var accepted:=_append_event({"kind":"institution_influx","payouts":payouts.duplicate(true)})
	if accepted: changed.emit()
	_busy=false
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

func _receipt(context: String,amount: int,participants: Array,counterpart: String,metadata: Dictionary = {}) -> void:
	var eligible: Array[String] = []
	for id: Variant in participants:
		if String(id) in active_ids and not eligible.has(String(id)): eligible.append(String(id))
	var financial: Dictionary = journal.back() if not journal.is_empty() else {}
	var timestamp := float(world_clock.call()) if world_clock.is_valid() else 0.0
	var identity := owner_id+":commerce:"+str(sequence)
	var entry := {"id":identity,"transaction_id":identity,"sequence":sequence,"world_timestamp":timestamp,"context":context,"transaction_type":context,"amount":amount,"participants":eligible,"counterpart":counterpart,"sender_account":String(financial.get("from","")),"receiver_account":String(financial.get("to","sink:glyphic_wonders")),"asset_id":"","delivered_asset_id":"","asset_type":"","quantity":0,"asset_sender_id":"","asset_receiver_id":"","related_event_id":"","substance":"service","legality":"legal","reference_price":0}
	for key: String in metadata:
		if entry.has(key) and key not in ["id","transaction_id","sequence","amount","participants","world_timestamp","sender_account","receiver_account"]: entry[key]=metadata[key]
	# Legal consequences are independent observers; a copied value cannot rewrite
	# the subsequent civilian-only XP award or a committed inventory transfer.
	_last_receipt=entry.duplicate(true)
	transaction_committed.emit(entry.duplicate(true))
	if amount>0 and not eligible.is_empty(): commerce_committed.emit(entry.duplicate(true))

static func faction_account(key: String) -> String: return "faction:"+key
static func organization_account(key: String) -> String: return "guild:"+key

func organization_operation(request: Dictionary) -> bool:
	# Host-only atomic financing. Escrow retains its original source account.
	if not host_enabled or _busy or _externally_busy() or owner_id.is_empty(): return false
	var additions: Array[String]=[]
	var payments: Array[Dictionary]=[]
	match String(request.get("operation","")):
		"bootstrap":
			if not request.get("guilds") is Array or request.guilds.size()!=12 or not guilds.is_empty(): return false
			var groups: Dictionary={}
			for row: Variant in request.guilds:
				if not row is Dictionary or not _faction_key(row.get("id")) or row.get("faction") not in factions or row.id in additions: return false
				additions.append(row.id)
				if not groups.has(row.faction): groups[row.faction]=[]
				groups[row.faction].append(row.id)
			if groups.size()!=4: return false
			for faction: String in groups:
				if groups[faction].size()!=3: return false
				var available:=balance(faction_account(faction))
				for n in range(3):
					var amount:=available/3+(1 if n<available%3 else 0)
					if amount>0: payments.append({"from":faction_account(faction),"to":organization_account(groups[faction][n]),"amount":amount})
		"found":
			var key: Variant=request.get("guild_id")
			var source: Variant=request.get("source")
			if not _faction_key(key) or key in guilds or not source is String or not source.begins_with("resident:") or source.trim_prefix("resident:") not in active_ids or not Instance.whole_number(request.get("amount"),30,100000): return false
			additions.append(key); payments.append({"from":source,"to":organization_account(key),"amount":int(request.amount)})
		"move":
			var source: String=request.get("source","")
			var destination: String=request.get("destination","")
			if not source.begins_with("guild:") or source.trim_prefix("guild:") not in guilds or source==destination or not balances.has(destination) or not (destination.begins_with("guild:") or destination.begins_with("faction:")): return false
			if balance(source)>0: payments.append({"from":source,"to":destination,"amount":balance(source)})
		_: return false
	if guilds.size()+additions.size()>MAX_GUILDS or sequence>COIN_CAP-payments.size(): return false
	if additions.is_empty() and payments.is_empty(): return true
	var projected: Dictionary=balances.duplicate()
	for key: String in additions: projected[organization_account(key)]=0
	for payment: Dictionary in payments:
		if not projected.has(payment.from) or not projected.has(payment.to) or int(projected[payment.from])<int(payment.amount) or int(projected[payment.to])>COIN_CAP-int(payment.amount): return false
		projected[payment.from]-=int(payment.amount); projected[payment.to]+=int(payment.amount)
	_busy=true
	for key: String in additions:
		guilds.append(key); balances[organization_account(key)]=0; audit_base.balances[organization_account(key)]=0
	guilds.sort()
	for payment: Dictionary in payments:
		_append_event({"kind":"transfer","from":payment.from,"to":payment.to,"amount":int(payment.amount),"reason":"Organizational capital allocation"})
	changed.emit(); _busy=false
	return true

func register_faction(key: String) -> bool:
	if not host_enabled or _busy or _externally_busy() or owner_id.is_empty() or not _faction_key(key) or factions.has(key) or factions.size()>=MAX_FACTIONS: return false
	_busy=true
	factions.append(key); factions.sort()
	balances[faction_account(key)]=0
	audit_base.balances[faction_account(key)]=0
	changed.emit()
	_busy=false
	return true

static func _quest_serial(key: String) -> int:
	if not key.begins_with("quest_"): return 0
	var suffix:=key.trim_prefix("quest_")
	if not suffix.is_valid_int() or suffix.to_int()<1 or suffix.to_int()>COIN_CAP or str(suffix.to_int())!=suffix: return 0
	return suffix.to_int()

func reserve_contract(key: String,payer_account: String,amount: int) -> bool:
	var serial:=_quest_serial(key)
	if serial>0:
		for previous: String in contracts:
			if _quest_serial(previous)>=serial: return false
	if not host_enabled or _busy or _externally_busy() or not Instance.valid_text(key,false,128) or contracts.has(key) or contracts.size()>=MAX_CONTRACTS or not _can_pay(payer_account,ESCROW_ACCOUNT,amount): return false
	_busy=true
	var accepted:=_append_event({"kind":"transfer","from":payer_account,"to":ESCROW_ACCOUNT,"amount":amount,"reason":"Contract reservation "+key.left(100)})
	if accepted:
		contracts[key]={"source":payer_account,"amount":amount,"status":"reserved","payee":"","service":"","legality":"legal","sequence":sequence}
		changed.emit()
	_busy=false
	return accepted

func settle_contract(key: String,recipient_id: String,service: String,legality: String = "legal") -> bool:
	if not host_enabled or _busy or _externally_busy() or not contracts.has(key) or not Instance.valid_text(service,false,128) or legality not in ["legal","illegal","unknown"]: return false
	if recipient_id!=owner_id and recipient_id not in active_ids: return false
	var obligation: Dictionary=contracts[key]
	var payee:=player_account if recipient_id==owner_id else resident_account(recipient_id)
	if obligation.status!="reserved" or not _can_pay(ESCROW_ACCOUNT,payee,int(obligation.amount)): return false
	_busy=true
	var accepted:=_append_event({"kind":"transfer","from":ESCROW_ACCOUNT,"to":payee,"amount":int(obligation.amount),"reason":"Completed contract "+key.left(100)})
	if accepted:
		obligation.status="settled"; obligation.payee=recipient_id; obligation.service=service; obligation.legality=legality; obligation.sequence=sequence
		var parties: Array=[recipient_id]
		if String(obligation.source).begins_with("resident:"): parties.append(String(obligation.source).trim_prefix("resident:"))
		_receipt("contract",int(obligation.amount),parties,String(obligation.source),{"related_event_id":key,"legality":legality,"substance":"service"})
		changed.emit()
	_busy=false
	return accepted

func refund_contract(key: String) -> bool:
	if not host_enabled or _busy or _externally_busy() or not contracts.has(key): return false
	var obligation: Dictionary=contracts[key]
	if obligation.status!="reserved" or not _can_pay(ESCROW_ACCOUNT,String(obligation.source),int(obligation.amount)): return false
	_busy=true
	var accepted:=_append_event({"kind":"transfer","from":ESCROW_ACCOUNT,"to":String(obligation.source),"amount":int(obligation.amount),"reason":"Refunded contract "+key.left(100)})
	if accepted:
		obligation.status="refunded"; obligation.sequence=sequence
		changed.emit()
	_busy=false
	return accepted

func npc_sell_item(seller_id: String,buyer_id: String,iid: String,qty: int,price: int,related_event_id: String = "",legality: String = "legal") -> bool:
	if seller_id==buyer_id or not _npc_allowed(seller_id,&"npc_sell_item",{"seller_id":seller_id,"buyer_id":buyer_id,"instance_id":iid,"quantity":qty,"price":price,"legality":legality}) or buyer_id not in active_ids: return false
	if not Instance.valid_text(related_event_id,true,128) or legality not in ["legal","illegal","unknown"] or not _can_pay(resident_account(buyer_id),resident_account(seller_id),price): return false
	var source:=npc_store(seller_id)
	var destination:=npc_store(buyer_id)
	if source==null or destination==null: return false
	return _move_item(source,destination,iid,qty,{"kind":"transfer","from":resident_account(buyer_id),"to":resident_account(seller_id),"amount":price,"reason":"Code Form merchandise sale"},{"context":"item_sale","amount":price,"participants":[seller_id,buyer_id],"counterpart":resident_account(seller_id),"related_event_id":related_event_id,"legality":legality,"substance":"goods"})

func trade_item(seller_id: String,buyer_id: String,iid: String,qty: int,price: int,event_id: String,legality: String = "legal") -> bool:
	if seller_id==buyer_id or not Instance.valid_text(event_id,false,128) or legality not in ["legal","illegal","unknown"]: return false
	if seller_id!=owner_id and seller_id not in active_ids or buyer_id!=owner_id and buyer_id not in active_ids: return false
	var payload:={"seller_id":seller_id,"buyer_id":buyer_id,"instance_id":iid,"quantity":qty,"price":price,"event_id":event_id,"legality":legality}
	if owner_id in [seller_id,buyer_id]:
		if not _valid_inventory(player_inventory) or not _allowed(&"intent_trade",payload): return false
	elif not _npc_allowed(seller_id,&"npc_sell_item",payload): return false
	var seller:=player_account if seller_id==owner_id else resident_account(seller_id)
	var buyer:=player_account if buyer_id==owner_id else resident_account(buyer_id)
	if not _can_pay(buyer,seller,price): return false
	var source:=_delivery_store(seller_id)
	var destination:=_delivery_store(buyer_id)
	if source==null or destination==null: return false
	return _move_item(source,destination,iid,qty,{"kind":"transfer","from":buyer,"to":seller,"amount":price,"reason":"Accepted merchandise offer"},{"context":"item_sale","amount":price,"participants":[seller_id,buyer_id],"counterpart":seller,"related_event_id":event_id,"legality":legality,"substance":"goods"})

func prune_contracts(retained_keys: Array) -> int:
	if not host_enabled or _busy or _externally_busy(): return 0
	var keep: Dictionary={}
	for key: Variant in retained_keys:
		if not Instance.valid_text(key,false,128): return 0
		keep[key]=true
	var watermark:=""
	var highest:=0
	for key: String in contracts:
		var serial:=_quest_serial(key)
		if serial>highest: highest=serial; watermark=key
	# Preserve a single persistent serial watermark. Forgotten custom tokens
	# cannot be deduplicated safely, so they keep their bounded terminal rows.
	_busy=true
	var removed:=0
	for key: String in contracts.keys():
		if contracts[key].status!="reserved" and _quest_serial(key)>0 and key!=watermark and not keep.has(key): contracts.erase(key); removed+=1
	if removed>0: changed.emit()
	_busy=false
	return removed

func _asset_owner(owner: String) -> String:
	if owner.begins_with("resident:"): return owner.trim_prefix("resident:")
	if owner==guild_account: return "guild"
	return owner

func _delivered_id(store: Node,item: Resource) -> String:
	if store.get_item(item.instance_id)!=null: return String(item.instance_id)
	# A consumed input stack may have merged into an existing owned instance.
	for existing: Resource in store.items.values():
		if existing.item_type_id==item.item_type_id and existing.upgrade_level==item.upgrade_level and Instance.same_properties(existing.custom_properties,item.custom_properties): return String(existing.instance_id)
	return ""

func npc_steal_item(thief_id: String,victim_id: String,iid: String,qty: int,event_id: String) -> Dictionary:
	if thief_id==victim_id or victim_id not in active_ids or not Instance.valid_text(event_id,false,128) or not _npc_allowed(thief_id,&"npc_steal_item",{"id":thief_id,"thief_id":thief_id,"victim_id":victim_id,"instance_id":iid,"quantity":qty,"event_id":event_id}): return {}
	var source:=npc_store(victim_id)
	var destination:=npc_store(thief_id)
	if source==null or destination==null: return {}
	var marks:={"stolen_from":resident_account(victim_id),"stolen_event":event_id,"theft_event_id":event_id}
	if not _move_item(source,destination,iid,qty,{"kind":"delivery","from":resident_account(victim_id),"to":resident_account(thief_id),"asset_id":iid,"quantity":qty},{"context":"item_theft","transaction_type":"item_theft","amount":0,"participants":[thief_id,victim_id],"counterpart":resident_account(victim_id),"related_event_id":event_id,"legality":"illegal"},marks): return {}
	return _last_receipt.duplicate(true)

func _delivery_store(id: String) -> Node:
	if id==owner_id: return player_inventory if _valid_inventory(player_inventory) else null
	if id=="guild": return guild_stock
	return npc_store(id) if id in active_ids else null

func deliver_item(sender_id: String,recipient_id: String,instance_id: String,quantity: int,related_event_id: String,legality: String = "legal") -> Dictionary:
	if not _allowed(&"deliver_item",{"sender_id":sender_id,"recipient_id":recipient_id,"instance_id":instance_id,"quantity":quantity,"related_event_id":related_event_id}) or sender_id==recipient_id or sender_id=="guild" or not Instance.valid_text(related_event_id,false,128) or legality not in ["legal","illegal","unknown"]: return {}
	var source:=_delivery_store(sender_id)
	var destination:=_delivery_store(recipient_id)
	if source==null or destination==null: return {}
	var source_account:=player_account if sender_id==owner_id else resident_account(sender_id)
	var destination_account:=guild_account if recipient_id=="guild" else (player_account if recipient_id==owner_id else resident_account(recipient_id))
	if not _move_item(source,destination,instance_id,quantity,{"kind":"delivery","from":source_account,"to":destination_account,"asset_id":instance_id,"quantity":quantity},{"context":"item_transfer","transaction_type":"item_transfer","amount":0,"participants":[sender_id,recipient_id],"counterpart":destination_account,"related_event_id":related_event_id,"legality":legality}): return {}
	return _last_receipt.duplicate(true)

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
		var effects:=food_offer(type,item)
		if effects.is_empty(): return false
		_busy = true
		var consumed: Resource = store.take_item(item.instance_id,1)
		if consumed!=null:
			consumed.quantity = 0
			npc_food_consumed.emit(id,effects)
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

func npc_service_wage(id: String,service_key: String,serial: int,amount: int=1) -> bool:
	if not _npc_allowed(id,&"npc_service_wage",{"id":id,"service_key":service_key,"serial":serial}): return false
	if amount!=1 and not (amount==20 and service_key=="tavern_work"): return false
	var token := id+"|"+service_key
	if not WAGE_SERVICES.has(service_key) or serial<0 or serial>COIN_CAP or serial<=int(service_tokens.get(token,-1)) or not service_tokens.has(token) and service_tokens.size()>=MAX_SERVICE_TOKENS: return false
	var business: String = WAGE_SERVICES[service_key]
	if not _can_pay(business,resident_account(id),amount): return false
	_busy = true
	var accepted := _append_event({"kind":"transfer","from":business,"to":resident_account(id),"amount":amount,"reason":"Completed "+service_key})
	if accepted:
		service_tokens[token] = serial
		_receipt("wage:"+service_key,amount,[id,merchant_ids.get("guild" if business==guild_account else "tavern","")],business,{"related_event_id":token+"|"+str(serial)})
		changed.emit()
	_busy = false
	return accepted

func purchase_wonder(id: String,type: StringName = &"cyan_mantle") -> bool:
	# Keep pre-shop logical worlds compatible, without a cheap alternate route
	# around an attached shop's current merchandise and authoritative quotes.
	if wonder_shop_attached or wonder_authorizer.is_valid(): return false
	if not _npc_allowed(id,&"purchase_wonder",{"id":id,"type_id":type}): return false
	var price: Variant = wonder_offers.get(String(type))
	if not Instance.whole_number(price,1,100000): return false
	var definition: Resource = Catalog.get_definition(type)
	if definition==null or definition.category!=&"cosmetics" or definition.is_equippable: return false
	var account := resident_account(id)
	if sequence>=COIN_CAP or balance(account)<int(price): return false
	return _purchase_item(npc_store(id),type,{"kind":"destroy","from":account,"amount":int(price),"reason":"Glyphic Wonders purchase"},"wonder",[id],"glyphic_wonders")

func _authorized_wonder(buyer: String,quote: Dictionary) -> Dictionary:
	if not wonder_shop_attached or not wonder_authorizer.is_valid() or not host_enabled or _busy or _externally_busy(): return {}
	# Authorizers are callbacks too: keep nested purchases/saves out until the
	# canonical current quote has been obtained and checked.
	_busy = true
	var authorized: Variant=wonder_authorizer.call(buyer,quote.duplicate(true))
	_busy = false
	if not authorized is Dictionary or not Instance.valid_text(authorized.get("type_id"),false,128) or not Instance.valid_text(authorized.get("token"),false,128) or not Instance.whole_number(authorized.get("price"),1,WonderStock.MAX_PRICE): return {}
	var token:=String(authorized.token)
	var type:=StringName(authorized.type_id)
	if _used_wonder_tokens.has(token) or _used_wonder_tokens.size()>=MAX_SERVICE_TOKENS or WonderStock.price_for(type)!=int(authorized.price): return {}
	return {"type_id":type,"price":int(authorized.price),"token":token,"buyer":buyer}

func buy_wonder(quote: Dictionary,inventory: Node) -> bool:
	if not _valid_inventory(inventory): return false
	var authorized:=_authorized_wonder(owner_id,quote)
	if authorized.is_empty(): return false
	return _commit_wonder(inventory,player_account,authorized,[])

func npc_buy_wonder(id: String,quote: Dictionary) -> bool:
	if not _npc_allowed(id,&"npc_buy_wonder",{"id":id,"quote":quote}): return false
	var authorized:=_authorized_wonder(id,quote)
	if authorized.is_empty(): return false
	return _commit_wonder(npc_store(id),resident_account(id),authorized,[id])

func _commit_wonder(store: Node,account: String,authorized: Dictionary,participants: Array) -> bool:
	var price:=int(authorized.price)
	if not host_enabled or _busy or _externally_busy() or sequence>=COIN_CAP or balance(account)<price: return false
	return _purchase_item(store,authorized.type_id,{"kind":"destroy","from":account,"amount":price,"reason":"Glyphic Wonders purchase"},"wonder",participants,"glyphic_wonders",authorized)

func _purchase_item(store: Node,type: StringName,event: Dictionary,context: String,participants: Array,counterpart: String,wonder_commit: Dictionary = {}) -> bool:
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
		if not wonder_commit.is_empty():
			_used_wonder_tokens[wonder_commit.token]=true
			wonder_purchase_committed.emit(String(wonder_commit.token),String(wonder_commit.buyer))
		if not blocked: store.changed.emit()
		_receipt(context,int(event.amount),participants,counterpart,{"asset_id":String(item.instance_id),"delivered_asset_id":_delivered_id(store,item),"asset_type":String(type),"quantity":1,"asset_sender_id":counterpart,"asset_receiver_id":_asset_owner(String(store.owner_id)),"related_event_id":String(wonder_commit.get("token","")),"substance":"retail_sink" if context=="wonder" else "goods"})
		changed.emit()
	_busy = false
	return accepted

func transfer(from: String,to: String,amount: int,reason: String = "Transfer") -> bool:
	# Trusted host settlement; commerce uses the narrower request methods below.
	if not host_enabled or _busy or _externally_busy() or ESCROW_ACCOUNT in [from,to] or not _can_pay(from,to,amount) or not Instance.valid_text(reason): return false
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

func food_offer(type: StringName,item: Resource = null) -> Dictionary:
	var definition: Resource=Catalog.get_definition(type)
	if definition==null or not definition.custom_properties.get("civilian_food",false): return {}
	var properties: Dictionary=definition.custom_properties.duplicate(true)
	var price: Variant=properties.get("price",0)
	if type in FOOD:
		price=meal_price if type==&"electron_meal" else draught_price
		properties.base_restoration=meal_healing if type==&"electron_meal" else draught_healing
		properties.consumption_duration=meal_duration if type==&"electron_meal" else draught_duration
	if not Instance.whole_number(price,1,100000): return {}
	var settings: Dictionary={"hp_cap":food_hp_cap,"shield_cap":drink_shield_cap,"quality_min":food_quality_min,"quality_max":food_quality_max,"complexity_factor":food_complexity_factor,"rarity_factor":food_rarity_factor}
	var offer:=Cuisine.effects(properties,item.custom_properties if item!=null else {},settings)
	if offer.is_empty(): return {}
	offer.merge({"type_id":String(type),"price":int(price)})
	return offer

func can_consume_food(iid: String,inventory: Node) -> bool:
	if not is_instance_valid(inventory): return false
	var item: Resource=inventory.get_item(iid)
	if item==null or item.owner_id!=inventory.owner_id: return false
	var offer:=food_offer(item.item_type_id,item)
	if offer.is_empty(): return false
	var actor: Node=inventory.actor
	var combat: Node=actor.get("weapon_combat") if is_instance_valid(actor) else null
	if not is_instance_valid(combat) or combat.health<=0: return false
	if float(offer.shield_restore)>0:
		return FoodShields.valid(inventory.shield_state) and float(inventory.shield_state.get("points",0))<maxf(FoodShields.capacity(inventory.shield_state),float(offer.shield_capacity))
	return combat.health<combat.max_health

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

func _move_item(source: Node,destination: Node,iid: String,qty: int,coin_event: Dictionary = {},receipt: Dictionary = {},properties: Dictionary = {}) -> bool:
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
	if preview!=null: preview.custom_properties.merge(properties,true)
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
	if moved!=null: moved.custom_properties.merge(properties,true)
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
		if not receipt.is_empty():
			var metadata:=receipt.duplicate(true)
			metadata.merge({"asset_id":iid,"delivered_asset_id":_delivered_id(destination,moved),"asset_type":String(moved.item_type_id),"quantity":qty,"asset_sender_id":_asset_owner(String(source.owner_id)),"asset_receiver_id":_asset_owner(String(destination.owner_id)),"substance":"goods","reference_price":WonderStock.price_for(moved.item_type_id)},true)
			_receipt(receipt.context,int(receipt.amount),receipt.participants,receipt.counterpart,metadata)
		changed.emit()
	_busy = false
	return accepted

func consume_food(iid: String,inventory: Node) -> bool:
	if not _valid_inventory(inventory) or not _allowed(&"consume_food",{"inventory":inventory,"instance_id":iid}): return false
	var item: Resource = inventory.get_item(iid)
	if item==null or item.owner_id!=owner_id: return false
	var offer := food_offer(item.item_type_id,item)
	if not can_consume_food(iid,inventory): return false
	_busy = true
	var consumed: Resource = inventory.take_item(iid,1)
	if consumed!=null:
		consumed.quantity = 0
		food_consumed.emit(inventory,offer.duplicate(true))
		changed.emit()
	_busy = false
	return consumed!=null

func capture_values() -> Dictionary:
	return _snapshot(true)

func serialize() -> Dictionary:
	return _snapshot(false)

func _snapshot(checkpoint: bool) -> Dictionary:
	if owner_id.is_empty(): return {}
	var stores: Dictionary = {}
	for room: int in room_stores: stores[str(room)] = room_stores[room].capture_values() if checkpoint else room_stores[room].serialize()
	var npc: Dictionary = {}
	for id: String in npc_stores: npc[id] = npc_stores[id].capture_values() if checkpoint else npc_stores[id].serialize()
	return {"version":6,"guilds":guilds.duplicate(),"factions":factions.duplicate(),"contracts":contracts.duplicate(true),"owner_id":owner_id,"natural_ids":natural_ids.duplicate(),"active_ids":active_ids.duplicate(),"balances":balances.duplicate(),"issued_total":issued_total,"destroyed_total":destroyed_total,"last_cycle":last_cycle,"sequence":sequence,"audit_base":audit_base.duplicate(true),"journal":journal.duplicate(true),"rental":rental.duplicate(true),"room_stores":stores,"guild_stock":guild_stock.capture_values() if checkpoint else guild_stock.serialize(),"npc_stores":npc,"service_tokens":service_tokens.duplicate()}

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
	starter_influx_applied=bool(audit_base.starter_influx)
	institution_influx_applied=bool(audit_base.institution_influx)
	for event: Dictionary in journal:
		if event.kind=="starter_influx": starter_influx_applied=true
		if event.kind=="institution_influx": institution_influx_applied=true
	rental = decoded.rental
	service_tokens = decoded.service_tokens
	factions.assign(decoded.factions)
	guilds.assign(decoded.guilds)
	contracts = decoded.contracts
	room_stores = replacements
	_capture_queue.clear()
	for room: int in room_stores:
		room_stores[room].name = "RoomStorage"+str(room)
		room_stores[room].process_mode = Node.PROCESS_MODE_DISABLED
		_track_capture(room_stores[room])
		add_child(room_stores[room])
	guild_stock = stock
	guild_stock.name = "GuildStock"
	guild_stock.process_mode = Node.PROCESS_MODE_DISABLED
	_track_capture(guild_stock)
	add_child(guild_stock)
	npc_stores = npc
	for id: String in npc_stores:
		npc_stores[id].process_mode = Node.PROCESS_MODE_DISABLED
		_track_capture(npc_stores[id])
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

static func _account_ids(owner: String,ids: Array,extra: Array = []) -> Array[String]:
	var result: Array[String] = ["player:"+owner,"business:guild","business:tavern"]
	for id: String in ids: result.append(resident_account(id))
	for account: String in extra: result.append(account)
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
		"starter_influx":
			if entry.size()!=3 or not state.has("starter_influx") or state.starter_influx or not entry.get("payouts") is Dictionary or entry.payouts.size()!=state.active_ids.size() or entry.payouts.is_empty(): return false
			var total:=0
			for id: String in state.active_ids:
				var amount: Variant=entry.payouts.get(id)
				if not Instance.whole_number(amount,1,100000) or not coins.has(resident_account(id)) or int(coins[resident_account(id)])>COIN_CAP-int(amount): return false
				total+=int(amount)
			if state.issued_total>COIN_CAP-total: return false
			for id: String in state.active_ids: coins[resident_account(id)]+=int(entry.payouts[id])
			state.issued_total+=total
			state.starter_influx=true
		"institution_influx":
			if entry.size()!=3 or not state.has("institution_influx") or state.institution_influx or not entry.get("payouts") is Dictionary or entry.payouts.is_empty(): return false
			var total:=0
			for account: Variant in entry.payouts:
				if not account is String or not coins.has(account) or not (account.begins_with("guild:") or account.begins_with("faction:") or account in ["business:guild","business:tavern"]): return false
				var amount: Variant=entry.payouts[account]
				if not Instance.whole_number(amount,1,100000) or int(coins[account])>COIN_CAP-int(amount): return false
				total+=int(amount)
			if state.issued_total>COIN_CAP-total: return false
			for account: String in entry.payouts: coins[account]+=int(entry.payouts[account])
			state.issued_total+=total
			state.institution_influx=true
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
		"delivery":
			if entry.size()!=6 or not coins.has(entry.get("from")) or not coins.has(entry.get("to")) or entry.from==entry.to or not Instance.valid_text(entry.get("asset_id"),false,128) or not Instance.whole_number(entry.get("quantity"),1,999999): return false
		"destroy":
			if entry.size()!=5 or not entry.get("from") is String or not coins.has(entry.from) or not Instance.valid_text(entry.get("reason")) or not Instance.whole_number(entry.get("amount"),1,COIN_CAP): return false
			var amount := int(entry.amount)
			if coins[entry.from]<amount or state.destroyed_total>COIN_CAP-amount: return false
			coins[entry.from] -= amount
			state.destroyed_total += amount
		_: return false
	state.sequence = int(entry.sequence)
	return true

static func _inventory_snapshot(input: Variant,owner: String,identities: Dictionary,allow_equipment: bool=false) -> Dictionary:
	var store := Inventory.new()
	if not store.restore(input):
		store.free()
		return {}
	var snapshot: Dictionary = store.serialize()
	store.free()
	# Residents can wield their actual owned gear. Rental lockers and guild
	# stock remain unequipped storage; no civilian store receives player-only
	# respawn, shield or boss-claim state through this exception.
	if snapshot.owner_id!=owner or not allow_equipment and not snapshot.equipment.is_empty() or not snapshot.get("respawn_points",{}).is_empty() or not snapshot.get("shield_state",{}).is_empty() or not snapshot.get("boss_reward_claims",{}).is_empty(): return {}
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

static func _validate_v2(input: Variant,player: Dictionary = {},world_drops: Array = [],extra_accounts: Array = [],allow_influx: int=0) -> Dictionary:
	if not input is Dictionary: return {}
	if input.get("version")==1:
		var migrated := _migrate_v1(_validate_v1(input,player,world_drops))
		return _validate_v2(migrated,player,world_drops,extra_accounts) if not migrated.is_empty() else {}
	if input.size()!=16 or not Instance.whole_number(input.get("version"),2,2) or not Instance.valid_text(input.get("owner_id"),false,64): return {}
	var owner := String(input.owner_id)
	var known := _natural_list(input.get("natural_ids"),owner)
	if known.is_empty(): return {}
	# Lists stay sorted in the canonical save/audit format. Transient hash sets
	# keep validation linear when a world has thousands of civilian accounts.
	var known_set := _id_set(known)
	var active: Variant = _subset_ids(input.get("active_ids"),owner,known_set,MAX_ACTIVE)
	if active==null: return {}
	var accounts := _account_ids(owner,known,extra_accounts)
	var coins := _balances(input.get("balances"),accounts)
	if coins.is_empty() or not Instance.whole_number(input.get("issued_total"),0,COIN_CAP) or not Instance.whole_number(input.get("destroyed_total"),0,COIN_CAP) or not Instance.whole_number(input.get("last_cycle"),-1,COIN_CAP) or not Instance.whole_number(input.get("sequence"),0,COIN_CAP): return {}
	var total := int(input.destroyed_total)
	for value: int in coins.values(): total += value
	if total!=int(input.issued_total): return {}
	if not input.get("audit_base") is Dictionary or input.audit_base.size()!=(9 if allow_influx==2 else 8 if allow_influx==1 else 7): return {}
	if allow_influx and not input.audit_base.get("starter_influx") is bool: return {}
	if allow_influx==2 and not input.audit_base.get("institution_influx") is bool: return {}
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
	if allow_influx:
		base.starter_influx=base_input.starter_influx
		if base.sequence==0 and base.starter_influx: return {}
	if allow_influx==2:
		base.institution_influx=base_input.institution_influx
		if base.sequence==0 and base.institution_influx: return {}
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
		var snapshot := _inventory_snapshot(input.npc_stores[id],resident_account(id),identities,true)
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

static func _faction_key(key: Variant) -> bool:
	return Instance.valid_text(key,false,64) and not ":" in key and not "|" in key

static func _validate_v3(input: Variant,player: Dictionary = {},world_drops: Array = [],guild_accounts: Array = [],allow_influx: int=0) -> Dictionary:
	if not input is Dictionary: return {}
	if Instance.whole_number(input.get("version"),1,2):
		var migrated:=_validate_v2(input,player,world_drops)
		if migrated.is_empty(): return {}
		migrated.version=3; migrated.factions=[]; migrated.contracts={}
		migrated.balances[ESCROW_ACCOUNT]=0; migrated.audit_base.balances[ESCROW_ACCOUNT]=0
		return _validate_v3(migrated,player,world_drops,guild_accounts)
	if input.get("version")!=3 or input.size()!=18 or not input.get("factions") is Array or input.factions.size()>MAX_FACTIONS or not input.get("contracts") is Dictionary or input.contracts.size()>MAX_CONTRACTS: return {}
	var faction_ids: Array[String]=[]
	var extra: Array[String]=[ESCROW_ACCOUNT]
	for account: String in guild_accounts: extra.append(account)
	for key: Variant in input.factions:
		if not _faction_key(key) or faction_ids.has(key): return {}
		faction_ids.append(key); extra.append(faction_account(key))
	faction_ids.sort()
	var core: Dictionary=input.duplicate(true)
	core.version=2; core.erase("factions"); core.erase("contracts")
	var result:=_validate_v2(core,player,world_drops,extra,allow_influx)
	if result.is_empty(): return {}
	var reservations: Dictionary={}
	var reserved:=0
	var known:=_id_set(result.natural_ids)
	for key: Variant in input.contracts:
		if not Instance.valid_text(key,false,128): return {}
		var row: Variant=input.contracts[key]
		if not row is Dictionary or row.size()!=7 or not result.balances.has(row.get("source")) or row.source==ESCROW_ACCOUNT or not Instance.whole_number(row.get("amount"),1,COIN_CAP) or row.get("status") not in ["reserved","settled","refunded"] or not Instance.whole_number(row.get("sequence"),1,result.sequence) or row.get("legality") not in ["legal","illegal","unknown"]: return {}
		if row.status=="settled":
			if row.get("payee")!=result.owner_id and not known.has(row.get("payee")): return {}
			if not Instance.valid_text(row.get("service"),false,128): return {}
		else:
			if row.get("payee")!="" or row.get("service")!="" or row.legality!="legal": return {}
		if row.status=="reserved": reserved+=int(row.amount)
		reservations[key]={"source":String(row.source),"amount":int(row.amount),"status":String(row.status),"payee":String(row.payee),"service":String(row.service),"legality":String(row.legality),"sequence":int(row.sequence)}
	if reserved!=int(result.balances[ESCROW_ACCOUNT]): return {}
	result.version=3; result.factions=faction_ids; result.contracts=reservations
	return result

static func _validate_v4(input: Variant,player: Dictionary = {},world_drops: Array = [],allow_influx: int=0) -> Dictionary:
	if not input is Dictionary: return {}
	if Instance.whole_number(input.get("version"),1,3):
		var legacy:=_validate_v3(input,player,world_drops)
		if legacy.is_empty(): return {}
		legacy.version=4; legacy.guilds=[]
		return legacy
	if input.get("version")!=4 or input.size()!=19 or not input.get("guilds") is Array or input.guilds.size()>MAX_GUILDS: return {}
	var keys: Array[String]=[]
	var accounts: Array[String]=[]
	for key: Variant in input.guilds:
		if not _faction_key(key) or key in keys: return {}
		keys.append(key); accounts.append(organization_account(key))
	keys.sort()
	var core: Dictionary=input.duplicate(true)
	core.version=3; core.erase("guilds")
	var result:=_validate_v3(core,player,world_drops,accounts,allow_influx)
	if result.is_empty(): return {}
	result.version=4; result.guilds=keys
	return result

static func validate(input: Variant,player: Dictionary = {},world_drops: Array = []) -> Dictionary:
	if not input is Dictionary: return {}
	var current: bool=(input.get("version")==5 or input.get("version")==6)
	var institutions: bool=input.get("version")==6
	var core: Dictionary=input.duplicate(true)
	if current: core.version=4
	var result:=_validate_v4(core,player,world_drops,2 if institutions else 1 if current else 0)
	if result.is_empty(): return {}
	if not current: result.audit_base.starter_influx=false
	if not institutions: result.audit_base.institution_influx=false
	result.version=6
	return result
