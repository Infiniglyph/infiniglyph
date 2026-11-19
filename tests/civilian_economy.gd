extends SceneTree
## Real inventories, conserved ledger settlement and strict checkpoint ownership.
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
var checks := 0
var failures := 0
var economy: Node
var inventory: Node
var actor: Node3D
var consumed: Array[Dictionary] = []
var reentrant_accepts := 0
const RESIDENTS := ["guild_receptionist","tavern_bartender","native_test"]

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func add(type: StringName,qty: int = 1) -> Resource:
	var item: Resource = Catalog.create(type,qty)
	inventory.add_item(item)
	return item

func total() -> int:
	var result := 0
	for amount: int in economy.balances.values(): result += amount
	return result

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Civilian economy test timed out"); quit(1))
	actor = Actor.new()
	root.add_child(actor)
	actor.weapon_combat = Fighter.new()
	actor.add_child(actor.weapon_combat)
	inventory = Inventory.new()
	inventory.owner_id = "visitor"
	inventory.actor = actor
	actor.add_child(inventory)
	economy = Economy.new()
	root.add_child(economy)
	economy.player_inventory = inventory
	economy.food_consumed.connect(func(_inventory: Node,effects: Dictionary): consumed.append(effects))
	check(not economy.configure("visitor",["visitor"]) and economy.owner_id.is_empty(),"A visiting player cannot be configured as a natural blessing recipient")
	check(not economy.configure("visitor",["native_test","native_test"]),"Duplicate resident identities cannot receive duplicate blessings")
	check(economy.configure("visitor",RESIDENTS) and economy.configure("visitor",RESIDENTS),"Pristine configuration registers distinct accounts without issuing money")
	check(total()==0 and economy.balance(economy.player_account)==0 and economy.balance(economy.guild_account)==0 and economy.balance(economy.tavern_account)==0,"Player and independent businesses begin with zero coins")
	check(not economy.rent(0) and not economy.buy_food(&"electron_meal",inventory),"Empty wallets cannot rent rooms or purchase meals")
	check(economy.bless_cycle(0,RESIDENTS),"The host explicitly issues the opening blessing cycle")
	var equal := true
	for id: String in RESIDENTS: equal = equal and economy.balance(Economy.resident_account(id))==100
	check(equal and total()==300 and economy.issued_total==300 and economy.balance(economy.player_account)==0,"Every natural resident receives the same amount while the visiting human receives none")
	check(not economy.bless_cycle(0,RESIDENTS) and not economy.bless_cycle(1,RESIDENTS+["visitor"]),"Repeated cycles and visitor-expanded eligibility cannot issue additional coins")
	check(economy.transfer("resident:guild_receptionist",economy.guild_account,100,"Opening capital") and economy.transfer("resident:tavern_bartender",economy.tavern_account,100,"Opening capital"),"Founders transfer their existing blessings to separate business treasuries")
	check(total()==300 and economy.balance(economy.guild_account)==100 and economy.balance(economy.tavern_account)==100,"Founder capital preserves issued supply and independent business balances")
	var common := add(&"monster_glyph_common",10)
	common.custom_properties = {"recovered_from":"test encounter"}
	var rare := add(&"monster_glyph_rare",2)
	var sword := add(&"katana")
	sword.upgrade_level = 7
	sword.custom_properties = {"engraving":"A remembered journey"}
	inventory.assign(&"right",sword.instance_id)
	var before: Dictionary = inventory.serialize()
	check(not economy.sell_crystal(rare.instance_id,2,inventory) and inventory.serialize()==before and economy.balance(economy.guild_account)==100,"A guild cannot buy more crystals than its existing treasury can afford")
	check(not economy.sell_crystal(sword.instance_id,1,inventory),"The crystal counter refuses unrelated weapons")
	economy.host_enabled = false
	check(not economy.sell_crystal(rare.instance_id,1,inventory) and not economy.bless_cycle(1,RESIDENTS),"Non-host calls cannot mutate commerce or issue currency")
	economy.host_enabled = true
	economy.external_transaction_guard = func() -> bool: return true
	check(not economy.sell_crystal(rare.instance_id,1,inventory) and not economy.transfer("resident:native_test",economy.player_account,1) and inventory.serialize()==before,"Another active authority transaction blocks economic transfers before any mutation")
	economy.external_transaction_guard = Callable()
	economy.validator = func(_op: StringName,_payload: Dictionary) -> bool: return false
	check(not economy.sell_crystal(rare.instance_id,1,inventory) and inventory.serialize()==before,"A rejected proximity or interaction validator leaves items and balances intact")
	economy.validator = Callable()
	var impostor := Inventory.new()
	impostor.owner_id = inventory.owner_id
	impostor.actor = actor
	actor.add_child(impostor)
	var false_crystal: Resource = Catalog.create(&"monster_glyph_common")
	impostor.add_item(false_crystal)
	check(not economy.sell_crystal(false_crystal.instance_id,1,impostor),"A second inventory cannot impersonate the bound player account")
	check(economy.sell_crystal(rare.instance_id,1,inventory) and economy.sell_crystal(common.instance_id,2,inventory),"The guild purchases only affordable selected crystal quantities")
	check(economy.balance(economy.player_account)==99 and economy.balance(economy.guild_account)==1 and economy.balance(economy.tavern_account)==100 and total()==300,"Crystal sales move existing guild coins to the seller without changing total supply")
	check(inventory.get_item(rare.instance_id).quantity==1 and common.quantity==8 and economy.guild_stock.count_type(&"monster_glyph_rare")==1 and economy.guild_stock.count_type(&"monster_glyph_common")==2,"Sold crystal stacks are physically transferred into persistent guild stock")
	check(not economy.can_enter(1) and economy.rent(1) and economy.can_enter(1),"Paying for a room grants only its authorized rental access")
	check(economy.balance(economy.player_account)==69 and economy.balance(economy.guild_account)==31 and total()==300,"Room payment transfers exactly the configured price to the guild")
	check(not economy.can_enter(0) and not economy.rent(0),"An active rental cannot silently authorize or replace a different room")
	var expiry: float = economy.rental.expires_at
	check(expiry>Time.get_unix_time_from_system()+3599 and expiry<Time.get_unix_time_from_system()+3601,"Rental access uses the configured persistent absolute deadline")
	check(economy.buy_food(&"electron_meal",inventory) and economy.buy_food(&"electron_draught",inventory),"The Tavern sells real meal and drink instances")
	check(economy.balance(economy.player_account)==49 and economy.balance(economy.tavern_account)==120 and economy.balance(economy.guild_account)==31 and total()==300,"Food payments reach only the Tavern treasury and conserve total currency")
	var meal: Resource
	for item: Resource in inventory.items.values():
		if item.item_type_id==&"electron_meal": meal = item
	actor.weapon_combat.health = 1000
	check(not economy.consume_food(meal.instance_id,inventory) and consumed.is_empty(),"Full-health characters do not waste a food item")
	actor.weapon_combat.health = 500
	check(economy.consume_food(meal.instance_id,inventory) and consumed.size()==1 and consumed[0].duration==2 and consumed[0].healing==60 and inventory.count_type(&"electron_meal")==0,"Consumption removes exactly one meal and emits its timed effect for the character controller")
	check(not economy.consume_food(meal.instance_id,inventory),"A consumed instance cannot be replayed for another effect")
	check(not economy.transfer_storage(0,sword.instance_id,1,true,inventory),"Storage in another unrented room remains inaccessible")
	var callback := func():
		if economy.buy_food(&"electron_meal",inventory): reentrant_accepts += 1
	inventory.changed.connect(callback)
	check(economy.transfer_storage(1,sword.instance_id,1,true,inventory),"An equipped unique weapon can enter its rented room's actual inventory")
	var store: Node = economy.room_stores[1]
	check(inventory.get_item(sword.instance_id)==null and store.get_item(sword.instance_id)==sword and sword.owner_id==Economy.storage_owner("visitor",1) and inventory.equipped_item(&"right")==null,"Storage transfers the original unique Resource, identity, and equipment assignment atomically")
	check(sword.upgrade_level==7 and sword.custom_properties.engraving=="A remembered journey" and reentrant_accepts==0,"Storage preserves upgrades and properties while rejecting reentrant purchase callbacks")
	inventory.changed.disconnect(callback)
	check(not economy.transfer_storage(1,sword.instance_id,1,true,inventory),"Repeated rapid deposit cannot duplicate an item already in storage")
	check(economy.transfer_storage(1,common.instance_id,3,true,inventory) and common.quantity==5,"Partial deposits split only the requested quantity")
	var stored_common: Resource
	for item: Resource in store.items.values():
		if item.item_type_id==&"monster_glyph_common": stored_common = item
	check(stored_common!=null and stored_common.instance_id!=common.instance_id and stored_common.custom_properties==common.custom_properties,"Split storage stacks receive unique IDs and retain their original custom properties")
	check(economy.transfer_storage(1,stored_common.instance_id,3,false,inventory) and common.quantity==8 and store.count_type(&"monster_glyph_common")==0,"Withdrawals obey inventory stack merging without duplicating either identity")
	var checkpoint: Dictionary = economy.serialize()
	var decoded: Dictionary = Economy.validate(JSON.parse_string(JSON.stringify(checkpoint)),inventory.serialize())
	check(not decoded.is_empty() and decoded.issued_total==300,"Economy, journal, rental and stored items survive strict JSON checkpoint validation")
	var invalid: Dictionary = checkpoint.duplicate(true)
	invalid.balances[economy.player_account] += 1
	check(Economy.validate(invalid).is_empty(),"Currency balances cannot diverge from issued supply")
	invalid = checkpoint.duplicate(true)
	invalid.journal[0].amount += 1
	check(Economy.validate(invalid).is_empty(),"Tampered transaction history fails replay against the saved balances")
	invalid = checkpoint.duplicate(true)
	invalid.room_stores["0"].items.append(invalid.room_stores["1"].items[0].duplicate(true))
	invalid.room_stores["0"].items[-1].owner_id = Economy.storage_owner("visitor",0)
	check(Economy.validate(invalid).is_empty(),"The same unique item cannot appear in two different room inventories")
	var copied_player: Dictionary = inventory.serialize()
	var stored_copy: Dictionary = checkpoint.room_stores["1"].items[0].duplicate(true)
	stored_copy.owner_id = inventory.owner_id
	copied_player.items.append(stored_copy)
	check(Economy.validate(checkpoint,copied_player).is_empty(),"Checkpoint validation rejects an item duplicated between player and room storage")
	var world_item: Dictionary = checkpoint.room_stores["1"].items[0].duplicate(true)
	world_item.owner_id = ""
	check(Economy.validate(checkpoint,inventory.serialize(),[{"item":world_item}]).is_empty(),"Stored items cannot also be restored as unclaimed world drops")
	var before_economy: Dictionary = economy.serialize()
	check(not economy.restore(invalid) and economy.serialize()==before_economy,"An invalid economy restore leaves all live accounts and room contents untouched")
	check(economy.restore(decoded) and economy.can_enter(1) and economy.room_stores[1].get_item(sword.instance_id).upgrade_level==7,"Valid restoration reconstructs logical storage and rental access independently of geometry")
	store = economy.room_stores[1]
	economy.rental.expires_at = Time.get_unix_time_from_system()-1
	check(not economy.can_enter(1) and not economy.transfer_storage(1,sword.instance_id,1,false,inventory) and store.get_item(sword.instance_id)!=null,"Expired access locks the terminal while preserving its stored items")
	check(economy.rent(1) and economy.can_enter(1) and economy.transfer_storage(1,sword.instance_id,1,false,inventory),"Renewing an expired room restores access to its persistent contents")
	check(inventory.get_item(sword.instance_id).custom_properties.engraving=="A remembered journey" and total()==300,"Storage renewal and withdrawal preserve unique properties and coin conservation")
	var rejecting := RejectingStore.new()
	rejecting.restore(economy.room_stores[1].serialize())
	economy.room_stores[1].free()
	economy.add_child(rejecting)
	economy.room_stores[1] = rejecting
	before = inventory.serialize()
	check(not economy.transfer_storage(1,sword.instance_id,1,true,inventory) and inventory.serialize()==before and rejecting.items.is_empty(),"An unexpected destination rejection rolls the original source and destination back without item loss")
	var full_store := Inventory.new()
	full_store.owner_id = Economy.storage_owner("visitor",1)
	rejecting.free()
	economy.add_child(full_store)
	economy.room_stores[1] = full_store
	var stacked: Resource = Catalog.create(&"monster_glyph_common",98)
	stacked.custom_properties = common.custom_properties.duplicate(true)
	full_store.add_item(stacked)
	var base_item: Resource = Catalog.create(&"katana")
	for i in range(Inventory.MAX_ITEMS-1):
		var filler: Resource = base_item.duplicate(true)
		filler.instance_id = "storage-capacity-"+str(i)
		full_store.add_item(filler)
	before = inventory.serialize()
	check(full_store.items.size()==Inventory.MAX_ITEMS and not economy.transfer_storage(1,sword.instance_id,1,true,inventory) and inventory.serialize()==before,"A full room respects actual inventory capacity and preserves a rejected unique item")
	check(economy.transfer_storage(1,common.instance_id,1,true,inventory) and full_store.items.size()==Inventory.MAX_ITEMS and full_store.get_item(stacked.instance_id).quantity==99,"At full capacity an existing compatible stack can still accept its remaining free quantity")
	before = inventory.serialize()
	check(not economy.transfer_storage(1,common.instance_id,1,true,inventory) and inventory.serialize()==before,"A full compatible stack cannot hide an overflow which needs another inventory slot")
	full_store.items.clear() # Discard only the artificial capacity fixture.
	# Exercise bounded history pruning and replay, without inventing currency.
	var settled := true
	for i in range(140):
		settled = economy.transfer("resident:native_test",economy.player_account,1,"Test settlement") and economy.transfer(economy.player_account,"resident:native_test",1,"Test return") and settled
	check(settled,"Hundreds of explicit settlements transfer existing currency without issuing new supply")
	var bounded: Dictionary = economy.serialize()
	check(bounded.journal.size()==Economy.JOURNAL_LIMIT and bounded.audit_base.sequence>0 and not Economy.validate(bounded,inventory.serialize()).is_empty(),"Pruned audit history remains bounded and exactly replays from its validated anchor")
	check(total()==economy.issued_total and total()==300 and not paused,"The final ledger conserves issued coins while the world stays unpaused")
	var human_balance: int = economy.balance(economy.player_account)
	var resident_balances: Dictionary = {}
	for id: String in RESIDENTS: resident_balances[id] = economy.balance(Economy.resident_account(id))
	var next_equal: bool = economy.bless_cycle(1,RESIDENTS)
	for id: String in RESIDENTS: next_equal = next_equal and economy.balance(Economy.resident_account(id))==resident_balances[id]+100
	check(next_equal and total()==600 and economy.issued_total==600 and economy.balance(economy.player_account)==human_balance and not economy.bless_cycle(1,RESIDENTS),"A later explicit blessing remains equal, excludes the visitor, and cannot be replayed")
	check(not Economy.validate(economy.serialize(),inventory.serialize()).is_empty(),"Later issuance still validates after older transaction history has been pruned")
	actor.queue_free()
	economy.queue_free()
	await process_frame
	print("Civilian economy verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
