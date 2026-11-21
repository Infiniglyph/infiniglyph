extends SceneTree
const Store=preload("res://scripts/inventory_store.gd")
const Encoder=preload("res://scripts/checkpoint_encoder.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Audit=preload("res://scripts/economic_xp_audit.gd")
const Quests=preload("res://scripts/universal_quests.gd")
const Communication=preload("res://scripts/universal_communication.gd")
const Law=preload("res://scripts/civilian_law.gd")
var checks:=0
var failures:=0
var inventory: Node
var economy: Node
var registry: RefCounted
var quests: RefCounted
var communication: CanvasLayer
var law: Node
var encoder:=Encoder.new()
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func snapshot(civic: bool=true) -> Dictionary:
	var audit:=Audit.new(); audit.configure("local",economy.sequence)
	var society: Dictionary={"version":2,"registry":registry.serialize(),"saved_unix":Time.get_unix_time_from_system(),"autonomy":{"version":1,"cursor":0,"states":{}},"economic_audit":audit.serialize()}
	var result: Dictionary={"version":1,"policy":"singleplayer_checkpoint","session_id":"singleplayer","inventory":inventory.serialize(),"world_drops":[],"markers":[],"civilian_state":economy.serialize(),"civilization_state":society}
	if civic: result.merge({"quest_state":quests.serialize(),"communication_state":communication.serialize(),"law_state":law.serialize()})
	return result
func finance(request: Dictionary) -> bool:
	match request.operation:
		"reserve": return economy.reserve_contract(request.quest_id,request.source,request.amount)
		"pay": return economy.settle_contract(request.quest_id,"local" if request.beneficiary=="player" else request.beneficiary,request.service,request.legality)
		"refund": return economy.refund_contract(request.quest_id)
	return false
func identity(id: String) -> Dictionary:
	if id=="player": return {"kind":"player","active":true}
	return {"kind":"code_form","active":registry.records.get(id,{}).get("active",false)} if registry.records.has(id) else {}
func worker_result() -> Dictionary:
	for i in range(1000):
		if encoder.ready(): return encoder.take_result()
		await process_frame
	encoder.discard(); return {}
func run() -> void:
	inventory=Inventory.new(); inventory.owner_id="local"; root.add_child(inventory)
	economy=Economy.new(); economy.player_inventory=inventory; root.add_child(economy)
	economy.configure("local",["worker","merchant","contact"]); economy.bless_cycle(0,["worker","merchant","contact"])
	registry=Registry.new()
	var rows: Array[Dictionary]=[]
	for id: String in ["worker","merchant","contact"]: rows.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"supplier","personality":"friendly","respawn":{"location":"overworld","position":[0,.2,0],"yaw":0}})
	registry.bootstrap(rows)
	for faction: String in ["security","commerce","exploration","underworld"]: economy.register_faction(faction)
	economy.transfer("resident:merchant","faction:exploration",40,"Founding funds")
	quests=Quests.new(); quests.configure({"identity":identity,"authorize":func(_op: String,_payload: Dictionary): return true,"finance":finance})
	communication=Communication.new()
	communication.profiles.profile("player",{"kind":"player"}); communication.profiles.profile("worker",{"kind":"code_form"})
	var message: Dictionary=communication.protocol.make_message("player","worker","greet","",{},"friendly","",0)
	communication.protocol.receive(message,func(_message: Dictionary): return {"accepted":true,"facts":[{"greeted":true}]})
	law=Law.new(); law.identity_provider=identity
	law.record_crime({"event_id":"real-theft","kind":"theft","offender":"worker","victim":"merchant","witnesses":["contact"]})
	check(not Store.decode(snapshot(false)).is_empty(),"Legacy checkpoints without all three civic systems remain valid")
	var id: String=quests.create_contract("exploration_discovery","faction/exploration","faction:exploration",{"target_id":"city/market"},0)
	quests.join("player","exploration"); quests.accept(id,"player",0)
	var base:=snapshot()
	check(not Store.decode(base).is_empty(),"A real funded active quest, UIC memory and witnessed case share one strict checkpoint")
	check(not Store.decode(JSON.parse_string(JSON.stringify(base))).is_empty(),"Civic records survive a full-precision JSON parse and canonical validation")
	var stripped:=base.duplicate(true)
	for key: String in Store.CIVIC_FIELDS: stripped.erase(key)
	check(Store.decode(stripped).is_empty() and encoder.start(stripped)==OK,"Escrow obligations enter background validation")
	check((await worker_result()).get("error")==ERR_INVALID_DATA,"Removing every civic field cannot disguise newer escrow obligations as a legacy save")
	for missing: String in ["quest_state","communication_state","law_state","civilian_state","civilization_state"]:
		var invalid:=base.duplicate(true); invalid.erase(missing)
		check(Store.decode(invalid).is_empty(),"Civic state rejects a missing linked "+missing)
	var invalid:=base.duplicate(true); invalid.quest_state.world_seconds=100
	check(Store.decode(invalid).is_empty(),"A future quest clock cannot precede the authoritative civilization clock")
	invalid=base.duplicate(true); invalid.quest_state.memberships["boss"]=[]
	check(Store.decode(invalid).is_empty(),"An unregistered boss cannot acquire persisted civilian/player faction state")
	invalid=base.duplicate(true); invalid.quest_state.instances[id].reward=11
	check(Store.decode(invalid).is_empty(),"An internally valid quest cannot change its actual escrow reward")
	invalid=base.duplicate(true); invalid.quest_state.instances.clear()
	check(Store.decode(invalid).is_empty(),"An open financial reservation cannot be orphaned from its work obligation")
	invalid=base.duplicate(true); invalid.law_state.cases.case_1.timestamp=1
	check(Store.decode(invalid).is_empty(),"Witnessed cases cannot claim events from the future")
	invalid=base.duplicate(true); invalid.law_state.cases.case_1.witnesses=["dungeon_enemy"]
	check(Store.decode(invalid).is_empty(),"Witness identities must belong to the historical civilization or player")
	invalid=base.duplicate(true); invalid.communication_state.protocol.recent[0].listener_id="invented"
	check(Store.decode(invalid).is_empty(),"Conversation participants are crosschecked against persistent identities")
	invalid=base.duplicate(true); invalid.communication_state.protocol.facts[0].world_timestamp=1
	check(Store.decode(invalid).is_empty(),"Structured conversational knowledge cannot come from a future world clock")
	invalid=base.duplicate(true); invalid.civilization_state.economic_audit.owner_id="foreign"
	check(Store.decode(invalid).is_empty(),"Economic audit provenance must match the actual ledger owner")
	check(encoder.start(base)==OK,"Asynchronous saves capture all three canonical civic value models")
	var result:=await worker_result()
	var decoded: Variant=JSON.parse_string(result.get("bytes",PackedByteArray()).get_string_from_utf8())
	check(result.get("error")==OK and decoded is Dictionary and not Store.decode(decoded).is_empty(),"The private encoder checks linked civic state and emits a valid complete checkpoint")
	invalid=base.duplicate(true); invalid.quest_state.world_seconds=1
	check(encoder.start(invalid)==OK,"A cross-clock mismatch is deferred with the isolated civilization value snapshot")
	result=await worker_result()
	check(result.get("error")==ERR_INVALID_DATA and result.get("bytes",PackedByteArray()).is_empty(),"The worker rejects linked clock tampering without producing commit bytes")
	quests.consume_event({"event_id":"real-discovery","event_type":"discovery","actor_id":"player","target_id":"city/market","timestamp":0})
	var completed:=snapshot()
	check(not Store.decode(completed).is_empty() and economy.balance("player:local")==10,"Completed player work persists with exactly matching paid escrow and real coins")
	invalid=completed.duplicate(true); invalid.civilian_state.contracts[id].payee="worker"
	check(Store.decode(invalid).is_empty(),"A completed quest cannot claim another recipient's payment")
	check(quests.restore(null) and quests.instances.is_empty() and quests.memberships.is_empty(),"Legacy reset clears civic quest records without finance callbacks")
	law.free(); communication.free(); economy.free(); inventory.free()
	print("Quest checkpoint: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
