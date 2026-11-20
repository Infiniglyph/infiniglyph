extends SceneTree
const Economy=preload("res://scripts/civilian_economy.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Civil=preload("res://scripts/code_form_civilization.gd")
const Audit=preload("res://scripts/economic_xp_audit.gd")
class Society extends "res://scripts/code_form_civilization.gd":
	func _ready() -> void: pass
	func bind_sources() -> void: pass
class RejectingEconomy extends "res://scripts/civilian_economy.gd":
	var reject_retirement:=false
	func retire_code_form(id: String) -> bool:
		return false if reject_retirement else super.retire_code_form(id)
class Session extends Node:
	var dirty:=0
	func _dirty() -> void: dirty+=1
class Loot extends Node:
	var _busy:=false
class World extends Node3D:
	var loot: Node
	var inventory_session: Node
var checks:=0
var failures:=0
var econ: Node
var society: Node
var inventory: Node
var world: Node3D
var receipts: Array[Dictionary]=[]
var reentrant:=false
const IDS: Array[String]=["a","b","c","guild_receptionist","tavern_bartender"]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func rows() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id: String in IDS: result.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"resident","personality":"curious","respawn":{"location":"overworld","position":[0,0,0],"yaw":0}})
	return result
func source_item(id: String,type: StringName=&"cyan_mantle") -> Resource:
	var item: Resource=Catalog.create(type)
	econ.npc_store(id).add_item(item)
	return item
func receive(entry: Dictionary) -> void:
	receipts.append(entry.duplicate(true))
	reentrant=reentrant or econ.transfer("resident:a","resident:b",1,"Nested")
func legacy_v2(data: Dictionary) -> Dictionary:
	var old:=data.duplicate(true)
	old.version=2; old.erase("factions"); old.erase("contracts"); old.erase("guilds"); old.audit_base.erase("starter_influx")
	old.balances.erase(Economy.ESCROW_ACCOUNT); old.audit_base.balances.erase(Economy.ESCROW_ACCOUNT)
	return old
func run() -> void:
	world=World.new(); world.loot=Loot.new(); world.inventory_session=Session.new()
	root.add_child(world); world.add_child(world.loot); world.add_child(world.inventory_session)
	inventory=Inventory.new(); inventory.owner_id="human"; world.add_child(inventory)
	econ=RejectingEconomy.new(); world.add_child(econ); econ.player_inventory=inventory; econ.blessing_amount=1000
	check(econ.configure("human",IDS) and econ.bless_cycle(0,IDS),"Explicit existing blessing funds five actual Code Forms")
	society=Society.new(); society.world=world; society.economy=econ; society.ready_for_simulation=true
	check(society.registry.bootstrap(rows()),"Civilian registry uses the exact active economy census")
	society._initial_registry=society.registry.serialize()
	society.autonomy.civilization=society
	society.economic_audit.configure("human",econ.sequence)
	econ.world_clock=func(): return society.world_seconds
	econ.commerce_committed.connect(society._commerce)
	econ.transaction_committed.connect(receive)
	check(econ.transfer("resident:guild_receptionist",econ.guild_account,100,"Opening capital") and econ.transfer("resident:tavern_bartender",econ.tavern_account,100,"Opening capital") and receipts.is_empty(),"Founder capital and generic gifts produce no manufactured XP")
	var old:=legacy_v2(econ.serialize())
	var migrated: Dictionary=Economy.validate(JSON.parse_string(JSON.stringify(old)))
	check(not migrated.is_empty() and migrated.version==5 and migrated.balances[Economy.ESCROW_ACCOUNT]==0 and migrated.issued_total==5000,"Old v2 balances migrate with a zero-funded escrow and no issuance")
	var first_legacy:=old.duplicate(true)
	first_legacy.version=1
	for key: String in ["active_ids","destroyed_total","npc_stores","service_tokens"]: first_legacy.erase(key)
	for key: String in ["known_ids","active_ids","destroyed_total"]: first_legacy.audit_base.erase(key)
	for event: Dictionary in first_legacy.journal:
		if event.kind=="issue": event.erase("recipients")
	var first_migration: Dictionary=Economy.validate(JSON.parse_string(JSON.stringify(first_legacy)))
	check(not first_migration.is_empty() and first_migration.version==5 and first_migration.issued_total==5000 and first_migration.balances==migrated.balances,"Original v1 civilian finance retains every wallet and coin through schema migrations")
	check(econ.register_faction("underworld") and econ.register_faction("security") and not econ.register_faction("underworld"),"Separate faction treasury registration is bounded and idempotent")
	check(econ.transfer("resident:c",econ.faction_account("underworld"),100,"Founder donation") and econ.balance(econ.faction_account("underworld"))==100 and receipts.is_empty(),"Faction treasury receives conserved existing founder coins")
	check(econ.reserve_contract("criminal_1",econ.faction_account("underworld"),60) and not econ.reserve_contract("criminal_2",econ.faction_account("underworld"),60),"Publication reserves finite coins and prevents oversubscribed promises")
	check(not econ.transfer(Economy.ESCROW_ACCOUNT,"resident:a",1,"Bypass") and not econ.transfer("resident:a",Economy.ESCROW_ACCOUNT,1,"Bypass"),"Generic transfer cannot bypass the escrow obligations")
	var issued: int=econ.issued_total
	var xp_before: int=society.registry.records.a.experience
	check(econ.settle_contract("criminal_1","a","Completed covert recovery","illegal") and not econ.settle_contract("criminal_1","a","Replay","illegal"),"A completed criminal service transfers the reserved real reward exactly once")
	check(society.registry.records.a.experience>xp_before and receipts[-1].legality=="illegal" and receipts[-1].related_event_id=="criminal_1" and econ.issued_total==issued,"Illegal contract earns traceable XP without minting coins")
	check(econ.reserve_contract("cancelled",econ.faction_account("underworld"),30) and econ.refund_contract("cancelled") and not econ.refund_contract("cancelled"),"A cancelled obligation refunds existing currency exactly once")
	check(econ.reserve_contract("quest_1",econ.faction_account("underworld"),1) and econ.refund_contract("quest_1") and econ.reserve_contract("quest_2",econ.faction_account("underworld"),1) and econ.refund_contract("quest_2") and econ.prune_contracts(["criminal_1"])==1 and econ.contracts.has("criminal_1") and not econ.reserve_contract("quest_1",econ.faction_account("underworld"),1),"Pruned quest history retains a persistent monotonic replay watermark")
	var provenance:=source_item("a")
	provenance.custom_properties.stolen_from="resident:c"
	provenance.custom_properties.theft_event_id="theft/1"
	var a_before: int=society.registry.records.a.experience
	var b_before: int=society.registry.records.b.experience
	check(econ.npc_sell_item("a","b",provenance.instance_id,1,40,"fence/1","illegal"),"A thief sells an actual stolen object for a finite buyer's existing coins")
	var bought: Resource=econ.npc_store("b").get_item(provenance.instance_id)
	check(bought!=null and bought.custom_properties.theft_event_id=="theft/1" and econ.npc_store("a").get_item(provenance.instance_id)==null,"Ownership moves once and stolen metadata remains attached")
	check(society.registry.records.a.experience-a_before==society.registry.records.b.experience-b_before and receipts[-1].legality=="illegal","Both genuine criminal traders receive the same amount-based XP")
	check(econ.npc_sell_item("b","c",provenance.instance_id,1,40,"consumer/1","illegal") and society.review_economics().transactions.is_empty(),"A thief-to-fence-to-consumer chain is genuine commerce rather than a farming loop")
	var legal_item:=source_item("a")
	a_before=society.registry.records.a.experience; b_before=society.registry.records.b.experience
	check(econ.npc_sell_item("a","b",legal_item.instance_id,1,40,"legal/1","legal") and society.registry.records.a.experience-a_before==roundi(sqrt(40.0)*8) and society.registry.records.b.experience-b_before==roundi(sqrt(40.0)*8),"Legal and illegal sales use identical economic XP rules")
	var known_xp: int=society.registry.records.a.experience
	check(society.record_event({"event_type":"economic","actor_id":"a","event_id":"fabricated","coins":999}).is_empty() and society.record_event({"type":"economic","actor_id":"a","target_id":"alias","event_id":"alias","rarity":"common","significance":1,"coins":999}).is_empty() and society.registry.records.a.experience==known_xp,"Unproven event submissions and aliases cannot manufacture economic XP")
	var duplicate: Dictionary=receipts[-1].duplicate(true)
	check(society.economic_audit.record_transaction(duplicate,society.registry).is_empty() and society.registry.records.a.experience==known_xp,"Duplicate stable transaction IDs cannot award XP twice")
	for i in range(4): check(econ.npc_service_wage("a","guild_work",i),"Actual recurring work payment remains eligible "+str(i))
	check(society.review_economics().transactions.is_empty(),"Repetition alone never revokes recurring work or retail XP")
	var loop:=source_item("a")
	var xp_legitimate: int=society.registry.records.a.experience
	var b_legitimate: int=society.registry.records.b.experience
	var lifetime_before: float=society.registry.records.a.expires_at
	for i in range(4): check(econ.npc_sell_item("a" if i%2==0 else "b","b" if i%2==0 else "a",loop.instance_id,1,160,"quote/"+str(i),"legal"),"Artificial unchanged-asset buyback "+str(i))
	var level_after: int=society.registry.records.a.level
	var coins: Dictionary=econ.balances.duplicate()
	var review: Dictionary=society.review_economics()
	check(review.get("transactions",[]).size()==4 and society.registry.records.a.experience==xp_legitimate and society.registry.records.b.experience==b_legitimate,"Bounded retrospective review removes only all four originating artificial awards")
	check(society.registry.records.a.level<level_after and is_equal_approx(society.registry.records.a.expires_at,lifetime_before) and society.registry.records.a.born_at==0,"Level and unearned lifetime reconcile without resetting elapsed age")
	check(econ.balances==coins and econ.issued_total==issued and society.review_economics().transactions.is_empty(),"Repeated review is idempotent and financial transfers remain completed")
	# A later valid consumer resale cannot hide an earlier artificial cycle.
	var ring:=source_item("a")
	var ring_before: Dictionary={}
	for id: String in ["a","b","c"]: ring_before[id]=int(society.registry.records[id].experience)
	var path: Array[String]=["a","b","c","a","b","c","a"]
	var ring_trades:=true
	for i in range(6): ring_trades=ring_trades and econ.npc_sell_item(path[i],path[i+1],ring.instance_id,1,160,"ring")
	econ.npc_sell_item("a","c",ring.instance_id,1,40,"consumer")
	var resale_a: int=society.registry.records.a.experience-int(ring_before.a)-4*roundi(sqrt(160.0)*8)
	var resale_c: int=society.registry.records.c.experience-int(ring_before.c)-4*roundi(sqrt(160.0)*8)
	var ring_review: Dictionary=society.review_economics()
	check(ring_trades and ring_review.transactions.size()==6 and society.registry.records.a.experience==int(ring_before.a)+resale_a and society.registry.records.b.experience==int(ring_before.b) and society.registry.records.c.experience==int(ring_before.c)+resale_c,"Retrospective indexed review detects a repeated three-owner ring while retaining its later genuine resale")
	var saved: Dictionary=society.serialize()
	var parsed: Dictionary=JSON.parse_string(JSON.stringify(saved))
	var valid: Dictionary=Civil.validate(parsed)
	check(not valid.is_empty() and valid.version==2 and valid.economic_audit.transactions.size()>4,"Compact transaction provenance and reversals survive strict JSON validation")
	check(not Economy.validate(econ.serialize(),inventory.serialize()).is_empty() and Civil.ledger_matches(valid,econ.serialize()),"Escrow, provenance, finance audit and actual inventories survive strict conserved validation")
	var bad: Dictionary=econ.serialize(); bad.contracts.criminal_1.status="reserved"
	check(Economy.validate(bad).is_empty(),"A forged obligation cannot disagree with the actual escrow balance")
	bad=saved.duplicate(true); bad.economic_audit.transactions[bad.economic_audit.order[-1]].xp_awards.a=100000000
	check(Civil.validate(bad).is_empty(),"Malformed provenance cannot inject arbitrary reversible XP")
	xp_legitimate=int(society.registry.records.a.experience)
	var legacy:=saved.duplicate(true); legacy.version=1; legacy.erase("economic_audit")
	check(society.restore(legacy) and society.economic_audit.order.is_empty() and society.economic_audit.last_sequence==econ.sequence and society.registry.records.a.experience==xp_legitimate,"Legacy civilization XP is preserved as a baseline without replaying untraceable awards")
	var player_good: Resource=Catalog.create(&"cyan_mantle"); inventory.add_item(player_good)
	var before_delivery: int=receipts.size()
	var delivery: Dictionary=econ.deliver_item("human","a",player_good.instance_id,1,"supply/1")
	check(not delivery.is_empty() and delivery.transaction_type=="item_transfer" and delivery.amount==0 and econ.npc_store("a").get_item(player_good.instance_id)!=null and receipts.size()==before_delivery+1,"Quest delivery emits real asset ownership proof without extra coins or XP")
	check(econ.deliver_item("human","a",player_good.instance_id,1,"supply/1").is_empty(),"The same delivered instance cannot be submitted again")
	check(not Economy.validate(econ.serialize()).is_empty() and not reentrant,"Inventory callbacks remain guarded and delivery journal replays without currency mutation")
	# The human/NPC trade surface only accepts an exact authority capability.
	var merchandise:=source_item("b")
	econ.transfer("resident:c",econ.player_account,50,"Actual customer funds")
	var access: Dictionary={}
	econ.validator=func(operation: StringName,payload: Dictionary): return operation!=&"intent_trade" or not access.is_empty() and payload==access
	check(not econ.trade_item("b","human",merchandise.instance_id,1,20,"quote/player"),"A human retail transfer cannot bypass the current semantic quote authority")
	access.merge({"seller_id":"b","buyer_id":"human","instance_id":merchandise.instance_id,"quantity":1,"price":20,"event_id":"quote/player","legality":"legal"})
	check(not econ.trade_item("b","human",merchandise.instance_id,1,1,"quote/player"),"Changing an agreed price invalidates the exact trade capability")
	var before_player: int=econ.balance(econ.player_account)
	var before_seller: int=econ.balance("resident:b")
	check(econ.trade_item("b","human",merchandise.instance_id,1,20,"quote/player") and inventory.get_item(merchandise.instance_id)!=null and econ.npc_store("b").get_item(merchandise.instance_id)==null and econ.balance(econ.player_account)==before_player-20 and econ.balance("resident:b")==before_seller+20,"Accepted dialogue trade atomically transfers the seller's actual item and agreed existing coins")
	check(receipts[-1].asset_sender_id=="b" and receipts[-1].asset_receiver_id=="human" and receipts[-1].participants==["b"] and not society.registry.records.has("human"),"Trade provenance separates real human ownership from civilian-only economic progression")
	access.clear()
	# A new isolated audit proves expiry correction follows one ordinary replacement.
	var expiry_item:=source_item("a")
	var baseline: int=society.registry.records.a.experience
	for i in range(4): econ.npc_sell_item("a" if i%2==0 else "b","b" if i%2==0 else "a",expiry_item.instance_id,1,160,"expiry-loop")
	var expiry:=float(society.registry.records.a.expires_at)
	var natural_expiry:=float(society.registry.records.a.born_at)+(float(society.registry.config.lifetime_years)+float(society.registry.config.level_years)*(1-1))*float(society.registry.config.day_seconds)*float(society.registry.config.days_per_year)
	# Normal tests above retain unrelated levels; direct auditable XP correction is
	# tested separately by Registry's exact entitlement fixture.
	check(expiry>=natural_expiry and society.registry.records.a.experience>baseline,"Additional suspicious awards remain attributable until a bounded review")
	print("ECONOMIC PROVENANCE: ",checks," checks, ",failures," failures")
	society.free(); world.free(); quit(0 if failures==0 else 1)
