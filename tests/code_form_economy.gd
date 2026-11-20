extends SceneTree
## Dynamic civilian identity, real goods, persistent receipts and conserved supply.
const Economy = preload("res://scripts/civilian_economy.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
class Actor extends Node3D:
	var weapon_combat: Node
class Fighter extends Node:
	var health := 500.0
	var max_health := 1000.0
class RejectingStore extends "res://scripts/inventory.gd":
	func add_item(_item: Resource) -> bool: return false
const CORE := ["guild_receptionist","tavern_bartender","old_worker"]
var economy: Node
var inventory: Node
var actor: Node3D
var receipts: Array[Dictionary] = []
var receipt_busy := true
var reentrant_accepts := 0
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func receipt(entry: Dictionary) -> void:
	receipts.append(entry.duplicate(true))
	receipt_busy = receipt_busy and economy.transaction_active()
	if economy.transfer(economy.guild_account,economy.player_account,1,"Reentrant receipt"): reentrant_accepts += 1

func circulating() -> int:
	var result := 0
	for amount: int in economy.balances.values(): result += amount
	return result

func legacy_snapshot(current: Dictionary) -> Dictionary:
	# The exact previous production schema, before dynamic eligibility existed.
	var old := current.duplicate(true)
	old.version = 1
	for key: String in ["active_ids","destroyed_total","npc_stores","service_tokens","factions","contracts"]: old.erase(key)
	old.balances.erase(Economy.ESCROW_ACCOUNT)
	old.audit_base.balances.erase(Economy.ESCROW_ACCOUNT)
	for key: String in ["known_ids","active_ids","destroyed_total"]: old.audit_base.erase(key)
	for event: Dictionary in old.journal:
		if event.kind=="issue": event.erase("recipients")
	return old

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Code Form economy watchdog"); quit(2))
	actor = Actor.new()
	root.add_child(actor)
	actor.weapon_combat = Fighter.new()
	actor.add_child(actor.weapon_combat)
	inventory = Inventory.new()
	inventory.owner_id = "human"
	inventory.actor = actor
	actor.add_child(inventory)
	economy = Economy.new()
	root.add_child(economy)
	economy.player_inventory = inventory
	economy.commerce_committed.connect(receipt)
	check(economy.configure("human",CORE) and economy.bless_cycle(0,CORE),"Existing natural residents receive their original opening cycle")
	check(economy.transfer("resident:guild_receptionist",economy.guild_account,100,"Opening guild capital") and economy.transfer("resident:tavern_bartender",economy.tavern_account,100,"Opening tavern capital"),"Established treasuries retain their founder-funded capital")
	check(receipts.is_empty(),"Issuance and founder transfers emit no commerce XP receipt")
	var old := legacy_snapshot(economy.serialize())
	var migrated: Dictionary = Economy.validate(JSON.parse_string(JSON.stringify(old)),inventory.serialize())
	check(not migrated.is_empty() and migrated.version==3 and migrated.last_cycle==0 and migrated.destroyed_total==0 and migrated.active_ids==migrated.natural_ids,"Version-one civilian checkpoints migrate without reissuing their opening blessing")
	var expected_balances: Dictionary=old.balances.duplicate(); expected_balances[Economy.ESCROW_ACCOUNT]=0
	check(migrated.balances==expected_balances and migrated.room_stores==old.room_stores and migrated.guild_stock==old.guild_stock,"Migration preserves every existing wallet, room inventory and treasury stock while opening only an empty escrow account")
	check(migrated.journal[0].recipients==migrated.natural_ids and economy.restore(migrated),"Historical version-one issues retain their exact saved recipient census")
	var worker: Node = economy.npc_store("old_worker")
	check(worker!=null and worker.owner_id=="resident:old_worker" and worker.process_mode==Node.PROCESS_MODE_DISABLED,"NPC goods use their own persistent ordinary inventory without active offscreen simulation")
	check(economy.npc_buy_food("old_worker",&"electron_meal") and worker.count_type(&"electron_meal")==1 and economy.balance("resident:old_worker")==92 and economy.balance(economy.tavern_account)==108,"A Code Form buys an actual meal using existing coins paid to the Tavern")
	check(receipts.size()==1 and receipts[-1].context=="food" and receipts[-1].amount==8 and receipts[-1].participants.has("old_worker") and receipts[-1].participants.has("tavern_bartender") and receipts[-1].sequence==economy.sequence,"Completed NPC commerce identifies both eligible participants and its actual circulated amount")
	var consumed_receipts: int = receipts.size()
	check(economy.npc_consume_food("old_worker",&"electron_meal") and worker.count_type(&"electron_meal")==0 and receipts.size()==consumed_receipts,"Consuming a purchased meal removes the real item without awarding a second transaction receipt")
	check(not economy.npc_consume_food("old_worker",&"electron_meal"),"An empty NPC inventory cannot manufacture a meal or consumption event")
	economy.transfer("resident:old_worker",economy.player_account,40,"Explicit settlement")
	check(economy.buy_food(&"electron_meal",inventory) and receipts[-1].participants==["tavern_bartender"],"Human purchases recognize only the participating Code Form merchant")
	check(economy.rent(0) and receipts[-1].context=="rental" and receipts[-1].participants==["guild_receptionist"],"Player rental commerce produces a merchant-only receipt without adding player XP")
	var crystal: Resource = Catalog.create(&"monster_glyph_common")
	inventory.add_item(crystal)
	check(economy.sell_crystal(crystal.instance_id,1,inventory) and receipts[-1].context=="crystal_sale" and receipts[-1].participants==["guild_receptionist"],"Player crystal sales produce meaningful Guild commerce receipts after real item transfer")
	var npc_crystal: Resource = Catalog.create(&"monster_glyph_rare")
	worker.add_item(npc_crystal)
	check(economy.npc_sell_crystal("old_worker",npc_crystal.instance_id,1) and worker.get_item(npc_crystal.instance_id)==null and economy.guild_stock.get_item(npc_crystal.instance_id)==npc_crystal,"NPC crystal sales transfer the actual unique inventory instance to Guild ownership")
	check(receipts[-1].participants.has("old_worker") and receipts[-1].participants.has("guild_receptionist") and receipts[-1].amount==75,"Both Code Form sides of a funded crystal purchase are eligible for event evaluation")
	var snapshot: Dictionary = economy.serialize()
	var count: int = receipts.size()
	economy.host_enabled = false
	check(not economy.npc_buy_food("old_worker",&"electron_meal") and not economy.retire_code_form("old_worker") and economy.serialize()==snapshot,"Non-host calls cannot change civilian goods, eligibility or balances")
	economy.host_enabled = true
	economy.external_transaction_guard = func() -> bool: return true
	check(not economy.npc_buy_food("old_worker",&"electron_meal") and not economy.enroll_code_form("unauthorized"),"An opposing authority transaction gates NPC commerce and census changes")
	economy.external_transaction_guard = Callable()
	economy.npc_validator = func(_operation: StringName,_payload: Dictionary) -> bool: return false
	check(not economy.npc_service_wage("old_worker","guild_work",1) and receipts.size()==count,"A rejected actual-service validator emits neither money nor economic event")
	economy.npc_validator = Callable()
	check(economy.npc_service_wage("old_worker","guild_work",5) and receipts[-1].context=="wage:guild_work" and receipts[-1].amount==1,"A completed recognized work service pays one existing Guild coin")
	snapshot = economy.serialize()
	count = receipts.size()
	check(not economy.npc_service_wage("old_worker","guild_work",5) and not economy.npc_service_wage("old_worker","guild_work",4) and economy.serialize()==snapshot and receipts.size()==count,"Same and older service-day serials cannot replay wages or receipts")
	check(economy.npc_service_wage("old_worker","guild_work",6) and economy.npc_service_wage("old_worker","tavern_work",5),"Later completed service days and independent recognized employers remain payable")
	check(not economy.npc_service_wage("old_worker","invent_coins",7) and not economy.npc_service_wage("old_worker","guild_work",-1),"Unknown work contexts and invalid serials cannot create wage activity")
	var supply: int = economy.issued_total
	var before_circulating := circulating()
	var before_worker: int = economy.balance("resident:old_worker")
	var before_guild: int = economy.balance(economy.guild_account)
	var before_tavern: int = economy.balance(economy.tavern_account)
	check(economy.purchase_wonder("old_worker") and worker.count_type(&"cyan_mantle")==1,"Glyphic Wonders delivers a real owned pattern instead of issuing a fake transaction")
	check(economy.balance("resident:old_worker")==before_worker-5 and circulating()==before_circulating-5 and economy.destroyed_total==5 and economy.issued_total==supply and economy.balance(economy.guild_account)==before_guild and economy.balance(economy.tavern_account)==before_tavern,"Wonders permanently destroys five coins without routing them to any ordinary account")
	check(receipts[-1].context=="wonder" and receipts[-1].counterpart=="glyphic_wonders" and receipts[-1].participants==["old_worker"],"Currency destruction remains a distinct qualified purchase context")
	economy.wonder_offers["katana"] = 5
	check(not economy.purchase_wonder("old_worker",&"katana"),"A Wonders pattern offer cannot silently turn into an unrelated weapon grant")
	count = receipts.size()
	economy.transfer("resident:old_worker",economy.tavern_account,1,"Food-looking generic transfer")
	economy.transfer(economy.tavern_account,"resident:old_worker",1,"Reciprocal return")
	check(receipts.size()==count,"Repeated reciprocal or relabeled generic transfers never emit commerce receipts")
	before_worker = economy.balance("resident:old_worker")
	check(economy.retire_code_form("old_worker") and "old_worker" not in economy.active_ids and "old_worker" in economy.natural_ids and economy.balance("resident:old_worker")==before_worker and economy.npc_store("old_worker")==worker,"Retirement preserves the expired individual's historical money and goods while removing blessing eligibility")
	check(not economy.npc_buy_food("old_worker",&"electron_meal") and not economy.npc_service_wage("old_worker","guild_work",7) and not economy.retire_code_form("old_worker"),"Retired inhabitants cannot continue shopping, earning wages or retiring repeatedly")
	check(economy.enroll_code_form("replacement_1") and economy.balance("resident:replacement_1")==0 and economy.npc_store("replacement_1").items.is_empty(),"A replacement receives a fresh zero-balance identity and no predecessor goods")
	check(not economy.enroll_code_form("replacement_1",100) and not economy.enroll_code_form("old_worker",100) and not economy.enroll_code_form("human",100),"Existing, expired and human identities cannot be reenrolled for repeated opening funds")
	check(receipts.size()==count,"Census changes create no commerce XP receipts")
	var active: Array = economy.active_ids.duplicate()
	check(economy.bless_cycle(1,active) and economy.balance("resident:replacement_1")==100 and economy.balance("resident:old_worker")==before_worker,"The next cycle pays the current active census equally without retroactive inheritance")
	check(not economy.bless_cycle(1,active) and not economy.bless_cycle(2,economy.natural_ids),"Cycle high-watermarks and exact active-census matching prevent repeated or retired payments")
	var seen: Dictionary = {}
	var unique := true
	for event: Dictionary in receipts:
		unique = unique and not seen.has(event.id) and event.participants.has("human")==false
		seen[event.id] = true
	check(unique and receipt_busy and reentrant_accepts==0,"Receipt IDs are unique, exclude humans and remain protected by transaction guards during callbacks")
	var saved: Dictionary = economy.serialize()
	var decoded: Dictionary = Economy.validate(JSON.parse_string(JSON.stringify(saved)),inventory.serialize())
	check(not decoded.is_empty() and decoded.active_ids==active and decoded.service_tokens["old_worker|guild_work"]==6,"Dynamic census, destroyed supply, goods and wage high-watermarks persist through JSON")
	check(economy.restore(decoded) and not economy.npc_service_wage("old_worker","guild_work",6),"Reload retains retired identity state and prevents wage-token replay")
	var bad := saved.duplicate(true)
	bad.active_ids.append("old_worker")
	check(Economy.validate(bad).is_empty(),"An altered active census fails audit replay")
	bad = saved.duplicate(true)
	bad.destroyed_total += 1
	bad.issued_total += 1
	check(Economy.validate(bad).is_empty(),"A forged destruction and issuance pair still fails journal reconstruction")
	bad = saved.duplicate(true)
	bad.journal[0].recipients = [12]
	check(Economy.validate(bad).is_empty(),"Malformed historical blessing recipients fail closed without unsafe sorting")
	var stored_item: Dictionary = saved.npc_stores.old_worker.items[0].duplicate(true)
	var fake_player: Dictionary = inventory.serialize()
	stored_item.owner_id = inventory.owner_id
	fake_player.items.append(stored_item)
	check(Economy.validate(saved,fake_player).is_empty(),"NPC storage cannot duplicate an instance already in player inventory")
	stored_item.owner_id = ""
	check(Economy.validate(saved,inventory.serialize(),[{"item":stored_item}]).is_empty(),"NPC storage cannot duplicate unclaimed world loot")
	bad = saved.duplicate(true)
	stored_item.owner_id = Economy.storage_owner("human",0)
	bad.room_stores["0"].items.append(stored_item.duplicate(true))
	check(Economy.validate(bad).is_empty(),"NPC storage cannot duplicate a room-terminal item")
	bad = saved.duplicate(true)
	stored_item.owner_id = "business:guild"
	bad.guild_stock.items.append(stored_item.duplicate(true))
	check(Economy.validate(bad).is_empty(),"NPC storage cannot duplicate a Guild stock instance")
	bad = saved.duplicate(true)
	stored_item.owner_id = "resident:replacement_1"
	bad.npc_stores.replacement_1.items.append(stored_item.duplicate(true))
	check(Economy.validate(bad).is_empty(),"Different Code Forms cannot own the same persisted unique instance")
	var rejecting := RejectingStore.new()
	rejecting.owner_id = "resident:replacement_1"
	economy.npc_stores.replacement_1.free()
	economy.add_child(rejecting)
	economy.npc_stores.replacement_1 = rejecting
	snapshot = economy.serialize()
	count = receipts.size()
	check(not economy.npc_buy_food("replacement_1",&"electron_meal") and not economy.purchase_wonder("replacement_1") and economy.serialize()==snapshot and receipts.size()==count,"Failed real inventory delivery cannot charge coins, destroy currency or emit commerce receipts")
	var grown := true
	for i in range(150): grown = economy.enroll_code_form("regional_"+str(i),100) and grown
	check(grown and economy.active_ids.size()==153 and economy.balance("resident:regional_0")==100,"New initial regional inhabitants receive their explicit equal opening amount once")
	check(economy.journal.size()==Economy.JOURNAL_LIMIT and economy.audit_base.sequence>0 and not Economy.validate(economy.serialize(),inventory.serialize()).is_empty(),"Register, retire, circulation and destruction remain auditable after history pruning")
	var wide := Economy.new()
	root.add_child(wide)
	var wide_ids: Array = []
	for i in range(1000): wide_ids.append("initial_"+str(i))
	check(wide.configure("another_human",wide_ids) and wide.bless_cycle(0,wide_ids) and wide.issued_total==100000 and wide.balance("player:another_human")==0,"A thousand civilian wallets receive an equal centralized blessing without a player reward")
	check(not Economy.validate(wide.serialize()).is_empty(),"A large initial census validates without the previous 256-resident limit")
	check(circulating()+economy.destroyed_total==economy.issued_total,"All circulated and permanently destroyed coins exactly equal cumulative explicit issuance")
	wide.queue_free()
	actor.queue_free()
	economy.queue_free()
	await process_frame
	print("Code Form economy verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
