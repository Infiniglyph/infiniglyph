extends SceneTree
## Private checkpoint captures, worker validation and explicit join/discard.
const Encoder = preload("res://scripts/checkpoint_encoder.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Economy = preload("res://scripts/civilian_economy.gd")
const Registry = preload("res://scripts/code_form_registry.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
var checks := 0
var failures := 0
var encoder: RefCounted
var economy: Node
var inventory: Node
var registry: RefCounted
var ticks := 0
var watchdog_at := 0

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	ticks+=1
	if watchdog_at>0 and Time.get_ticks_msec()>watchdog_at:
		push_error("Checkpoint encoder watchdog")
		quit(2)
	return false

func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)

func row(index: int) -> Dictionary:
	var id := "region/"+str(index)
	return {"slot":id,"id":id,"name":"Encoder Citizen "+str(index),"occupation":"gardener","personality":"curious","respawn":{"location":"overworld","position":[float(index),.2,0.0],"yaw":0.0}}

func society(model: RefCounted) -> Dictionary:
	return {"version":1,"registry":model.serialize(),"saved_unix":Time.get_unix_time_from_system(),"autonomy":{"version":1,"cursor":0,"states":{}}}

func snapshot() -> Dictionary:
	return {"version":1,"policy":"singleplayer_checkpoint","session_id":"singleplayer","inventory":inventory.serialize(),"world_drops":[],"markers":[],"civilian_state":economy.serialize(),"civilization_state":society(registry)}

func wait_result() -> Dictionary:
	var deadline := Time.get_ticks_msec()+15000
	while encoder.pending() and not encoder.ready() and Time.get_ticks_msec()<deadline:
		await process_frame
	if not encoder.ready():
		check(false,"Worker finishes within the bounded test deadline")
		encoder.discard()
		return {}
	return encoder.take_result()

func error_job(input: Dictionary,label: String) -> void:
	check(encoder.start(input)==OK,label+" starts as a value-only worker validation")
	var result := await wait_result()
	check(result.get("error")==ERR_INVALID_DATA and result.get("bytes",PackedByteArray()).is_empty() and not encoder.pending(),label+" returns an error without commit bytes and frees its slot")

func run() -> void:
	watchdog_at=Time.get_ticks_msec()+90000
	inventory=Inventory.new()
	inventory.owner_id="encoder_human"
	root.add_child(inventory)
	var item: Resource=Catalog.create(&"katana",1)
	item.custom_properties={"engraving":"Captured original","nested":{"values":[1,2,3]}}
	inventory.add_item(item)
	registry=Registry.new()
	var initial_rows: Array[Dictionary]=[row(0),row(1)]
	check(registry.bootstrap(initial_rows),"Two real logical citizens form a bounded checkpoint fixture")
	economy=Economy.new()
	root.add_child(economy)
	economy.player_inventory=inventory
	check(economy.configure(inventory.owner_id,registry.active_ids()) and economy.bless_cycle(0,registry.active_ids()),"A real audited ledger matches the fixture census")
	encoder=Encoder.new()
	check(not encoder.pending() and not encoder.ready() and encoder.take_result().is_empty() and encoder.finish().is_empty(),"An idle encoder has no ready result or joinable job")
	var original := snapshot()
	var expected := Store.decode(original)
	check(not expected.is_empty(),"The reference checkpoint validates through the synchronous store")
	var invalid := original.duplicate(true)
	invalid.policy="foreign_policy"
	check(encoder.start(invalid)==ERR_INVALID_DATA and not encoder.pending(),"Invalid core ownership/policy is rejected on the main thread before a worker exists")
	invalid=original.duplicate(true)
	invalid.civilian_state.balances[economy.player_account]=1
	check(encoder.start(invalid)==ERR_INVALID_DATA and not encoder.pending(),"An unconserved inventory/economy core cannot launch an encoding job")
	var hidden := Node.new()
	invalid=original.duplicate(true)
	invalid.civilization_state.unexpected={"nested":[hidden]}
	await error_job(invalid,"A scene Node embedded in civilian state")
	hidden.free()
	invalid=original.duplicate(true)
	invalid.civilization_state.unexpected=[RefCounted.new()]
	await error_job(invalid,"A non-Node Object embedded in civilian state")
	var loop: Array=[]
	loop.append(loop)
	invalid=original.duplicate(true)
	invalid.unexpected=loop
	check(encoder.start(invalid)==OK,"Unknown core fields are canonicalized away before the private worker capture")
	var ignored_result:=await wait_result()
	var ignored: Variant=JSON.parse_string(ignored_result.get("bytes",PackedByteArray()).get_string_from_utf8())
	check(ignored_result.get("error")==OK and ignored is Dictionary and not ignored.has("unexpected"),"An ignored cyclic container never enters native serialization or the worker")
	loop.clear()
	check(encoder.start(original)==OK and encoder.pending(),"A valid private capture starts exactly one worker")
	check(encoder.start(original)==ERR_BUSY,"A second start cannot replace an in-flight or unconsumed job")
	original.inventory.items[0].custom_properties.nested.values[0]=999
	original.inventory.items.clear()
	original.civilization_state.registry.records["region/0"].name="Mutated after capture"
	original.civilian_state.balances[economy.player_account]=999
	original.civilian_state.active_ids.clear()
	var result := await wait_result()
	check(result.get("error")==OK and not result.bytes.is_empty(),"Worker returns UTF-8 bytes only after successful validation")
	var decoded: Variant=JSON.parse_string(result.bytes.get_string_from_utf8())
	check(decoded is Dictionary and Store.decode(decoded)==expected,"Encoded inventory, nested properties, census and balances retain their captured values despite later mutation")
	check(not encoder.pending() and not encoder.ready() and encoder.take_result().is_empty(),"Taking a result joins once and leaves no stale ready result")
	invalid=snapshot()
	invalid.civilization_state.autonomy.states={"unknown":{}}
	await error_job(invalid,"Malformed civilian decisions")
	invalid=snapshot()
	var third:=Registry.new()
	var third_rows: Array[Dictionary]=[row(0),row(1),row(2)]
	third.bootstrap(third_rows)
	invalid.civilization_state=society(third)
	await error_job(invalid,"A registry and active-wallet census mismatch")
	check(economy.enroll_code_form("historical_extra") and economy.retire_code_form("historical_extra"),"A valid separate historical wallet can be constructed without modifying active citizens")
	await error_job(snapshot(),"A historical-wallet and registry-history mismatch")
	# Return to the original paired model before independently testing cycles.
	check(economy.restore(expected.civilian_state),"The fixture restores its exact original audited ledger")
	check(economy.bless_cycle(1,registry.active_ids()),"A financially valid later blessing is available for a clock mismatch test")
	await error_job(snapshot(),"A paid blessing cycle ahead of the civilian clock")
	check(economy.restore(expected.civilian_state),"The fixture restores its pre-test cycle")
	check(encoder.start(snapshot())==OK,"A valid job can start after prior worker failures")
	result=encoder.finish()
	check(result.get("error")==OK and not result.bytes.is_empty() and not encoder.pending(),"Explicit finish synchronously joins for a manual save/load boundary")
	check(encoder.start(snapshot())==OK and encoder.finish(true).is_empty() and not encoder.pending(),"Explicit finish can discard old bytes before a newer load or manual save")
	check(encoder.start(snapshot())==OK,"Another job starts after a discarded result")
	encoder.discard()
	check(not encoder.pending() and encoder.take_result().is_empty(),"Discard joins and never exposes the stale result")
	# Saturate real valid civilian working sets to keep the worker occupied across
	# scene frames. No artificial sleep or scene objects exist in the worker.
	var large:=Registry.new()
	var rows: Array[Dictionary]=[]
	for i in range(1122): rows.append(row(i))
	check(large.bootstrap(rows),"A production-sized 1122-person registry bootstraps")
	var large_economy:=Economy.new()
	root.add_child(large_economy)
	large_economy.configure(inventory.owner_id,large.active_ids())
	large_economy.bless_cycle(0,large.active_ids())
	var ordinary := snapshot()
	ordinary.civilian_state=large_economy.serialize()
	ordinary.civilization_state=society(large)
	var ordinary_began:=Time.get_ticks_usec()
	check(encoder.start(ordinary)==OK,"An ordinary production-sized capture starts through the native binary boundary")
	var ordinary_capture_ms:=float(Time.get_ticks_usec()-ordinary_began)/1000.0
	result=await wait_result()
	check(result.get("error")==OK,"Ordinary production-sized checkpoint encodes on the worker")
	print("MEASURE checkpoint_encoder_ordinary ",JSON.stringify({"capture_ms":ordinary_capture_ms,"bytes":result.get("bytes",PackedByteArray()).size(),"total_ms":float(Time.get_ticks_usec()-ordinary_began)/1000.0}))
	for i in range(128): registry.record_event({"event_type":"discovery","actor_id":"region/0","target_id":"encoder-landmark-"+str(i),"rarity":"common","significance":1.0,"event_id":"encoder-discovery-"+str(i)})
	var sample: Dictionary=registry.records["region/0"]
	for record: Dictionary in large.records.values():
		record.novelty=sample.novelty.duplicate(true)
		record.event_bloom=sample.event_bloom
		for i in range(24): record.memories.append({"type":"discovery","target":"landmark-"+str(i),"summary":"A meaningful remembered route through the city and its surrounding districts.","importance":.7,"timestamp":0.0})
	var big := snapshot()
	big.civilian_state=large_economy.serialize()
	big.civilization_state=society(large)
	var began := Time.get_ticks_usec()
	check(encoder.start(big)==OK,"A saturated production-sized capture starts without synchronous society validation")
	var capture_ms:=float(Time.get_ticks_usec()-began)/1000.0
	var before_ticks:=ticks
	var running_frames:=0
	var deadline:=Time.get_ticks_msec()+60000
	while not encoder.ready() and Time.get_ticks_msec()<deadline:
		running_frames+=1
		await process_frame
		# Fixed-fps headless can otherwise spin thousands of simulated seconds
		# per real second and starve a deliberately low-priority background job.
		OS.delay_msec(1)
	check(running_frames>1 and ticks>before_ticks,"Scene processing keeps advancing while the long value-validation/JSON job runs")
	check(encoder.pending() and encoder.start(snapshot())==ERR_BUSY,"A finished but unconsumed job still owns its slot")
	result=encoder.take_result()
	check(result.get("error")==OK and result.bytes.size()>1000000,"The saturated worker returns the complete large checkpoint without thread-safety errors")
	print("MEASURE checkpoint_encoder ",JSON.stringify({"capture_ms":capture_ms,"worker_scene_frames":running_frames,"bytes":result.get("bytes",PackedByteArray()).size(),"total_ms":float(Time.get_ticks_usec()-began)/1000.0}))
	var forgotten: RefCounted=Encoder.new()
	check(forgotten.start(snapshot())==OK,"A final short job can test forgotten-owner cleanup")
	var reference: WeakRef=weakref(forgotten)
	forgotten=null
	check(reference.get_ref()==null,"Dropping the encoder joins its thread without a callable ownership cycle")
	large_economy.free()
	economy.free()
	inventory.free()
	print("Checkpoint encoder verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
