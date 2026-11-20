extends SceneTree
const Stock=preload("res://scripts/glyphic_wonders_stock.gd")
const Store=preload("res://scripts/inventory_store.gd")
const Encoder=preload("res://scripts/checkpoint_encoder.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
var checks:=0
var failures:=0
var inventory: Node
var economy: Node
var registry: RefCounted
var stock: RefCounted
var encoder: RefCounted
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func society() -> Dictionary:
	return {"version":1,"registry":registry.serialize(),"saved_unix":Time.get_unix_time_from_system(),"autonomy":{"version":1,"cursor":0,"states":{}}}
func raw() -> Dictionary:
	return {"version":1,"policy":"singleplayer_checkpoint","session_id":"singleplayer","inventory":inventory.serialize(),"world_drops":[],"markers":[],"civilian_state":economy.serialize(),"civilization_state":society(),"glyphic_wonders_state":stock.serialize()}
func result() -> Dictionary:
	var deadline:=Time.get_ticks_msec()+10000
	while not encoder.ready() and Time.get_ticks_msec()<deadline: await process_frame
	if not encoder.ready():
		check(false,"The checkpoint worker completes")
		encoder.discard()
		return {}
	return encoder.take_result()
func run() -> void:
	inventory=Inventory.new()
	inventory.owner_id="human"
	root.add_child(inventory)
	economy=Economy.new()
	root.add_child(economy)
	economy.player_inventory=inventory
	economy.configure("human",["worker"])
	economy.bless_cycle(0,["worker"])
	registry=Registry.new()
	registry.config.day_seconds=1.0
	var rows: Array[Dictionary]=[{"id":"worker","slot":"hub/worker","name":"Worker","occupation":"gardener","personality":"curious","respawn":{"location":"overworld","position":[0.0,.2,0.0],"yaw":0.0}}]
	registry.bootstrap(rows)
	stock=Stock.new()
	stock.configure(441,1,7,12,0)
	encoder=Encoder.new()
	var old:=Store.encode(inventory,[],[],"singleplayer","overworld",{},economy.serialize(),society())
	check(not old.is_empty() and not old.has("glyphic_wonders_state"),"Existing civilization checkpoints remain valid when shop state is absent")
	var partial:=Store.encode(inventory,[],[],"singleplayer","overworld",{},economy.serialize(),{},stock.serialize())
	check(not partial.is_empty() and partial.glyphic_wonders_state==stock.serialize(),"A partial civilian checkpoint can persist stock when no civilian clock is present")
	var unowned:=partial.duplicate(true)
	unowned.erase("civilian_state")
	check(Store.decode(unowned).is_empty() and encoder.start(unowned)==ERR_INVALID_DATA,"Stock without its owning civilian economy fails before worker dispatch")
	var whole:=Store.encode(inventory,[],[],"singleplayer","overworld",{},economy.serialize(),society(),stock.serialize())
	check(not whole.is_empty() and whole.glyphic_wonders_state==stock.serialize(),"The final optional encode parameter preserves a coherent complete shop checkpoint")
	var fresh:=Stock.new()
	check(fresh.restore(JSON.parse_string(JSON.stringify(whole)).glyphic_wonders_state) and fresh.serialize()==stock.serialize(),"JSON restoration retains the exact current offers and next rotation")
	var malformed:=raw()
	malformed.glyphic_wonders_state.selection[0]="civic_key"
	check(Store.decode(malformed).is_empty() and encoder.start(malformed)==ERR_INVALID_DATA,"Malformed/nonretail shop state is rejected by main-thread catalog validation")
	var later:=Stock.new()
	later.configure(441,1,7,12,7)
	var mismatch:=raw()
	mismatch.glyphic_wonders_state=later.serialize()
	check(Store.decode(mismatch).is_empty(),"Stock from a future rotation cannot pair with an earlier civilian clock")
	check(encoder.start(mismatch)==OK,"Async capture defers the pure clock cross-check until society validation")
	var encoded:=await result()
	check(encoded.get("error")==ERR_INVALID_DATA and encoded.get("bytes",PackedByteArray()).is_empty(),"Worker rejects a stale/future cycle without producing commit bytes")
	var different_day:=Stock.new()
	different_day.configure(441,2,7,12,0)
	mismatch=raw()
	mismatch.glyphic_wonders_state=different_day.serialize()
	check(Store.decode(mismatch).is_empty() and encoder.start(mismatch)==OK,"A different day-length configuration fails despite sharing cycle zero")
	encoded=await result()
	check(encoded.get("error")==ERR_INVALID_DATA and encoded.get("bytes",PackedByteArray()).is_empty(),"Worker independently enforces the canonical world-clock unit")
	var private_capture:=raw()
	check(encoder.start(private_capture)==OK,"A coherent shop checkpoint starts its value-only encoding worker")
	private_capture.glyphic_wonders_state.selection.clear()
	private_capture.glyphic_wonders_state.config.interval_days=99
	encoded=await result()
	var decoded: Variant=JSON.parse_string(encoded.get("bytes",PackedByteArray()).get_string_from_utf8())
	check(encoded.get("error")==OK and decoded is Dictionary and Stock.validate(decoded.glyphic_wonders_state)==stock.serialize(),"Worker stock values remain private when the caller mutates its original arrays/configuration")
	check(not Store.decode(decoded).is_empty(),"Worker-produced bytes also pass the full main-thread catalog/census validator")
	registry.advance_to(7)
	stock.advance(7)
	whole=Store.encode(inventory,[],[],"singleplayer","overworld",{},economy.serialize(),society(),stock.serialize())
	check(not whole.is_empty() and whole.glyphic_wonders_state.cycle==1 and whole.civilization_state.registry.world_seconds==7,"Exactly-on-boundary clock and shop advancement produce a coherent next rotation")
	check(encoder.start(raw())==OK,"The updated rotation can be encoded asynchronously")
	encoded=await result()
	var path:="user://tests/glyphic_wonders_checkpoint.json"
	check(encoded.get("error")==OK and Store._commit_encoded(path,encoded.bytes)==OK,"Only successfully encoded bytes reach the existing main-thread atomic file commit")
	var loaded:=Store.load_snapshot(path)
	check(not loaded.is_empty() and loaded.glyphic_wonders_state==stock.serialize(),"An actual disk checkpoint reloads the same saved selection and clock boundary")
	malformed=raw()
	malformed.glyphic_wonders_state.next_rotation+=1
	check(Store.store(path,malformed)==ERR_INVALID_DATA and Store.load_snapshot(path)==loaded,"Rejected stock corruption cannot overwrite the last valid checkpoint")
	var standalone:=partial.duplicate(true)
	check(encoder.start(standalone)==OK,"A valid partial civilian/shop snapshot also uses the worker")
	encoded=await result()
	check(encoded.get("error")==OK,"The worker does not invent a civilian clock requirement for legacy partial worlds")
	var legacy_stock: Dictionary=stock.serialize()
	var legacy_pool: Array[String]=["respawn_glyph","home_respawn_glyph"]
	for index in range(10): legacy_pool.append(legacy_stock.pool[index])
	legacy_pool.sort()
	legacy_stock.pool=legacy_pool
	legacy_stock.selection=Stock._choose(legacy_pool,int(legacy_stock.seed),int(legacy_stock.cycle),int(legacy_stock.config.pedestal_count))
	check(stock.restore(legacy_stock) and not Store.decode(raw()).is_empty(),"Whole checkpoints accept an old rotating pool after its Respawn Glyphs become permanent stock")
	check(encoder.start(raw())==OK,"The worker captures a legacy rotating pool without rerolling its saved merchandise")
	encoded=await result()
	var promoted: Variant=JSON.parse_string(encoded.get("bytes",PackedByteArray()).get_string_from_utf8())
	var restored:=Stock.new()
	check(encoded.get("error")==OK and promoted is Dictionary and not Store.decode(promoted).is_empty() and restored.restore(promoted.glyphic_wonders_state) and restored.serialize()==legacy_stock,"Legacy stock survives value-only worker encoding, JSON and strict whole-checkpoint reload")
	check(restored.offer(&"respawn_glyph").permanent and restored.offer(&"home_respawn_glyph").permanent and not restored.rotating_ids().has("respawn_glyph") and not restored.rotating_ids().has("home_respawn_glyph"),"Both reconstruction glyphs remain available at the counter immediately after loading old stock")
	economy.free()
	inventory.free()
	print("Glyphic Wonders checkpoint verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
