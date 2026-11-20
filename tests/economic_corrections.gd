extends SceneTree
const Economy=preload("res://scripts/civilian_economy.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Civil=preload("res://scripts/code_form_civilization.gd")
class Society extends "res://scripts/code_form_civilization.gd":
	func _ready() -> void: pass
	func bind_sources() -> void: pass
class Treasury extends "res://scripts/civilian_economy.gd":
	var reject_retirement:=false
	func retire_code_form(id: String) -> bool: return false if reject_retirement else super.retire_code_form(id)
var checks:=0
var failures:=0
var replacements: Array=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run() -> void:
	var econ:=Treasury.new(); root.add_child(econ)
	econ.blessing_amount=1000
	econ.configure("human",["a","b"]); econ.bless_cycle(0,["a","b"])
	var society:=Society.new(); society.economy=econ; society.ready_for_simulation=true
	society.registry.config.day_seconds=1.0; society.registry.config.days_per_year=1; society.registry.config.xp_step=10
	var rows: Array[Dictionary]=[]
	for id: String in ["a","b"]: rows.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"resident","personality":"curious","respawn":{"location":"overworld","position":[0,0,0],"yaw":0}})
	check(society.registry.bootstrap(rows),"Compressed clock fixture bootstraps true Code Forms")
	society.autonomy.civilization=society
	society._initial_registry=society.registry.serialize()
	society.economic_audit.configure("human",econ.sequence)
	society.economic_audit.config.circular_window_hours=10000.0; society.economic_audit.config.review_window_days=10000.0
	econ.world_clock=func(): return society.world_seconds
	econ.commerce_committed.connect(society._commerce)
	society.identities_replaced.connect(func(changes: Array): replacements.append_array(changes))
	# Unrelated legitimate progression must survive every economic correction.
	society.registry.grant_xp("a",30); society.registry.grant_xp("b",30)
	var good_a: int=society.registry.records.a.experience
	var good_level: int=society.registry.records.a.level
	var good_expiry: float=society.registry.records.a.expires_at
	var item: Resource=Catalog.create(&"cyan_mantle"); econ.npc_store("a").add_item(item)
	var trades:=true
	for i in range(4): trades=trades and econ.npc_sell_item("a" if i%2==0 else "b","b" if i%2==0 else "a",item.instance_id,1,160)
	check(trades and society.registry.records.a.experience>good_a and society.registry.records.a.level>good_level,"Artificial awards are traced separately from legitimate combat XP")
	var first: Dictionary=society.review_economics()
	check(first.transactions.size()==4 and society.registry.records.a.experience==good_a and society.registry.records.a.level==good_level and society.registry.records.a.expires_at==good_expiry,"Live correction removes only invalid level milestones and their exact lifetime")
	var regained:=society.registry.grant_xp("a",100)
	check(regained>0 and society.registry.records.a.expires_at==good_expiry+regained*100.0,"Regaining levels grants their lifetime once after correction")
	# Restore the same unrelated baseline via the supported primitive before
	# exercising the later discovery of already-spent unearned lifetime.
	society.registry.reconcile_xp("a",good_a)
	for i in range(4): econ.npc_sell_item("a" if i%2==0 else "b","b" if i%2==0 else "a",item.instance_id,1,160,"late")
	check(society.registry.advance_to(350).is_empty() and society.world_seconds==350 and society.registry.records.a.active,"Invalid lifetime can have naturally elapsed before later discovery")
	var before_registry: Dictionary=society.registry.serialize()
	var before_money: Dictionary=econ.serialize()
	var before_xp: int=society.registry.records.a.experience
	econ.reject_retirement=true
	check(society.review_economics().is_empty() and society.registry.records.a.experience==before_xp and society.registry.serialize()==before_registry and econ.serialize()==before_money and replacements.is_empty(),"A failed financial replacement rolls back XP, lifetime, census, goods and coins atomically")
	econ.reject_retirement=false
	var committed: Dictionary=society.review_economics()
	check(committed.transactions.size()==4 and replacements.size()==2 and society.registry.slots.size()==2 and society.registry.records.size()==4,"Corrected expiry produces exactly one new Code Form per expired person")
	var successor: String=society.registry.slots["hub/a"]
	check(society.registry.records.a.born_at==0 and society.registry.records.a.retired_at==350 and society.registry.records.a.expires_at==good_expiry and society.registry.records[successor].born_at==350,"Elapsed age and entitlement remain historical; the replacement is born now")
	check(econ.balance("resident:a")==int(before_money.balances["resident:a"]) and econ.balance("resident:"+successor)==0 and econ.npc_store("a").get_item(item.instance_id)!=null,"Retired wallets and belongings survive and are never copied to a replacement")
	check(not Civil.Registry.validate(society.registry.serialize()).is_empty() and not Economy.validate(econ.serialize()).is_empty(),"Corrected historical retirement and conserved ledger validate together")
	var history: Dictionary=society.economic_audit.serialize()
	check(society.review_economics().transactions.is_empty() and replacements.size()==2 and society.economic_audit.transactions==history.transactions,"Reload/review-safe reversal cannot expire a second generation or remove XP twice")
	# Theft itself moves existing goods, without money or economic progression.
	var victim_item: Resource=Catalog.create(&"cyan_mantle"); econ.npc_store(successor).add_item(victim_item)
	var other: String=society.registry.slots["hub/b"]
	var money_before: Dictionary=econ.balances.duplicate()
	var xp_before: int=society.registry.records[other].experience
	var theft: Dictionary=econ.npc_steal_item(other,successor,victim_item.instance_id,1,"theft/new")
	check(not theft.is_empty() and theft.transaction_type=="item_theft" and theft.legality=="illegal" and theft.amount==0 and econ.balances==money_before and society.registry.records[other].experience==xp_before,"Authoritative theft transfers a real object and legal evidence, with no circulation XP")
	var stolen: Resource=econ.npc_store(other).get_item(victim_item.instance_id)
	check(stolen!=null and stolen.custom_properties.stolen_from=="resident:"+successor and stolen.custom_properties.stolen_event=="theft/new" and econ.npc_store(successor).get_item(victim_item.instance_id)==null,"Stolen provenance is attached before actual inventory ownership commits")
	print("ECONOMIC CORRECTIONS: ",checks," checks, ",failures," failures")
	society.free(); econ.free(); quit(0 if failures==0 else 1)
