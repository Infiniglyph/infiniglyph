extends SceneTree
const Economy=preload("res://scripts/civilian_economy.gd")
const Civil=preload("res://scripts/code_form_civilization.gd")
class Society extends "res://scripts/code_form_civilization.gd":
	func _ready() -> void: pass
var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run() -> void:
	var economy:=Economy.new(); root.add_child(economy); economy.blessing_amount=100000
	economy.configure("human",["worker","guild_receptionist"]); economy.bless_cycle(0,economy.active_ids)
	economy.transfer("resident:guild_receptionist",economy.guild_account,10000,"Real treasury funding")
	var society:=Society.new(); society.economy=economy; society.ready_for_simulation=true
	var rows: Array[Dictionary]=[]
	for id: String in ["worker","guild_receptionist"]: rows.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"resident","personality":"curious","respawn":{"location":"overworld","position":[0,0,0],"yaw":0}})
	society.registry.bootstrap(rows); society.economic_audit.configure("human",economy.sequence)
	economy.commerce_committed.connect(society._commerce)
	var first: Dictionary={}
	economy.commerce_committed.connect(func(receipt: Dictionary):
		if first.is_empty(): first.merge(receipt.duplicate(true)))
	var committed:=true
	var start:=Time.get_ticks_usec()
	for i in range(2100): committed=committed and economy.npc_service_wage("worker","guild_work",i)
	var elapsed:=Time.get_ticks_usec()-start
	check(committed and economy.balance(economy.guild_account)==7900,"Two thousand genuine wage transfers use a finite existing treasury")
	check(society.economic_audit.order.size()==2048 and society.economic_audit.transactions.size()==2048 and economy.journal.size()==128,"Economic provenance and financial journals remain independently bounded")
	var previous_xp: int=society.registry.records.worker.experience
	check(not society.economic_audit.transactions.has(first.id) and society.economic_audit.record_transaction(first,society.registry).is_empty() and society.registry.records.worker.experience==previous_xp,"Persistent sequence highwater rejects duplicate XP even after old detail is pruned")
	start=Time.get_ticks_usec()
	var before: int=society.economic_audit.review_cursor
	var review: Dictionary=society.review_economics(1000000)
	var review_us:=Time.get_ticks_usec()-start
	check(review.transactions.is_empty() and society.economic_audit.review_cursor-before==16,"An oversized review request still visits at most sixteen transaction rows")
	check(not Civil.validate(JSON.parse_string(JSON.stringify(society.serialize()))).is_empty() and Civil.ledger_matches(society.serialize(),economy.serialize()),"The saturated audit survives strict JSON validation and recent financial provenance crosschecks")
	print("ECONOMIC AUDIT SCALE: ",checks," checks, ",failures," failures; 2100 commits ",elapsed/1000.0,"ms, review ",review_us/1000.0,"ms")
	society.free(); economy.free(); quit(0 if failures==0 else 1)
