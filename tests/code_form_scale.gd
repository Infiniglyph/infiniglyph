extends SceneTree
## Logical-model timing and bounded-state checkpoint size. No city bodies/rendering.
const Civilization = preload("res://scripts/code_form_civilization.gd")
const Registry = preload("res://scripts/code_form_registry.gd")
const Economy = preload("res://scripts/civilian_economy.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Store = preload("res://scripts/inventory_store.gd")

class LootShell extends Node:
	var _busy := false

class WorldShell extends Node3D:
	var loot: Node
	var population: Node3D
	var district_life: Node3D

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else: failures += 1; push_error("FAIL: "+label)

func row(index: int) -> Dictionary:
	var id := "region/"+str(index)
	return {"slot":id,"id":id,"name":"Scale Citizen "+str(index),"occupation":"gardener","personality":"curious","respawn":{"location":"overworld","position":[float(index%32)*4,.05,float(index/32)*4],"yaw":0.0}}

func timed_batches(society: Node, count: int, label: String) -> Dictionary:
	var samples: Array[int] = []
	var valid := true
	var bounded := true
	for i in range(count):
		var decisions: int = society.autonomy.decisions
		var begin := Time.get_ticks_usec()
		valid = society.advance_real(1.0) and valid
		samples.append(Time.get_ticks_usec()-begin)
		bounded = bounded and society.autonomy.decisions-decisions<=12
	samples.sort()
	var total := 0
	for sample: int in samples: total += sample
	var result := {"batches":count,"mean_ms":float(total)/count/1000.0,"p95_ms":float(samples[ceili(count*.95)-1])/1000.0,"max_ms":float(samples[-1])/1000.0}
	print("MEASURE ",label," ",JSON.stringify(result))
	check(valid and bounded,label+" advances the real controller path with at most12 decisions per batch")
	return result

func filled_template() -> Dictionary:
	var model := Registry.new()
	model.bootstrap([row(0)])
	for index in range(128):
		model.record_event({"event_type":"discovery","actor_id":"region/0","target_id":"scale-landmark-"+str(index),"rarity":"common","significance":1.0,"event_id":"scale-receipt-"+str(index)})
	var sample: Dictionary = model.records["region/0"].duplicate(true)
	sample.memories.clear()
	for index in range(24):
		sample.memories.append({"type":"discovery","target":"scale-landmark-"+str(index),"summary":"I reached a distant neighborhood, discovered its local landmarks and remembered a meaningful visit.","importance":.7,"timestamp":0.0})
	return sample

func set_filled_state(society: Node, sample: Dictionary, maximum_text: bool = false) -> void:
	for record: Dictionary in society.registry.records.values():
		record.novelty=sample.novelty.duplicate(true)
		record.event_bloom=sample.event_bloom
		record.memories=sample.memories.duplicate(true)
		if maximum_text:
			for memory: Dictionary in record.memories:
				memory.type="d".repeat(32)
				memory.target=("landmark-"+str(record.id)+"-"+String(memory.target)).rpad(128,".").left(128)
				memory.summary="A meaningful remembered journey. ".repeat(20).left(512)

func snapshot_size(society: Node, inventory: Node, count: int, label: String) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var encoded: Dictionary = Store.encode(inventory,[],[],"singleplayer","overworld",{},society.economy.serialize(),society.serialize())
	var valid := not encoded.is_empty()
	check(valid,str(count)+" "+label+" state validates as a complete inventory/economy/civilization checkpoint")
	if not valid: return {}
	var data := JSON.stringify(encoded,"",true,true)
	var bytes := data.to_utf8_buffer().size()
	var result := {"bytes":bytes,"MiB":float(bytes)/(1024*1024),"configured_cap_MiB":float(Store.MAX_SAVE_BYTES)/(1024*1024),"fits_current_cap":bytes<=Store.MAX_SAVE_BYTES,"encode_ms":float(Time.get_ticks_usec()-begin)/1000.0}
	print("MEASURE ",count," ",label," checkpoint ",JSON.stringify(result))
	if label=="filled":
		var path := "user://code-form-scale-"+str(count)+".json"
		var store_begin := Time.get_ticks_usec()
		var error: Error = Store.store(path,encoded)
		print("MEASURE ",count," filled store ",JSON.stringify({"store_ms":float(Time.get_ticks_usec()-store_begin)/1000.0,"error":error}))
		check(error==(OK if bytes<=Store.MAX_SAVE_BYTES else ERR_OUT_OF_MEMORY),str(count)+" saturated checkpoint obeys the actual bounded store limit")
		if error==OK:
			var load_begin := Time.get_ticks_usec()
			var loaded := Store.load_snapshot(path)
			print("MEASURE ",count," filled load ",JSON.stringify({"load_ms":float(Time.get_ticks_usec()-load_begin)/1000.0}))
			check(not loaded.is_empty() and loaded.civilization_state.registry.records.size()==count and loaded.civilian_state.active_ids.size()==count,str(count)+" saturated checkpoint reads back every civilian and wallet from actual disk JSON")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result

func measure(count: int) -> void:
	var world := WorldShell.new()
	world.loot=LootShell.new()
	world.add_child(world.loot)
	root.add_child(world)
	var society := Civilization.new()
	society.world=world
	society.economy=Economy.new()
	world.add_child(society.economy)
	society.autonomy.civilization=society
	var initial: Array[Dictionary] = []
	for index in range(count): initial.append(row(index))
	check(society.registry.bootstrap(initial),str(count)+" persistent civilian slots bootstrap without physical bodies")
	var inventory := Inventory.new()
	inventory.owner_id="scale_human"
	world.add_child(inventory)
	society.economy.player_inventory=inventory
	check(society.economy.configure(inventory.owner_id,society.registry.active_ids()) and society.economy.bless_cycle(0,society.registry.active_ids()),str(count)+" real ledger has a matching equal-opening civilian census")
	society.ready_for_simulation=true
	var start: float = society.world_seconds
	var warmup := ceili(float(count)/12)
	timed_batches(society,warmup,str(count)+" cold")
	check(society.autonomy.states.size()==count,str(count)+" rotating batches eventually initialize every unloaded citizen")
	timed_batches(society,512,str(count)+" steady")
	check(society.world_seconds==start+(warmup+512)*24.0 and society.registry.active_ids().size()==count and society.registry.replacement_serial==0,str(count)+" ordinary clock batches preserve the census and exact configured time rate")
	snapshot_size(society,inventory,count,"ordinary")
	var sample := filled_template()
	check(sample.novelty.size()==128 and sample.memories.size()==24 and sample.event_bloom.length()==Registry.BLOOM_BYTES*2,"Saturation sample uses real semantic rewards and a fully allocated receipt Bloom")
	set_filled_state(society,sample)
	check(not Registry.validate(society.registry.serialize()).is_empty(),str(count)+" fully occupied working sets remain valid registry state")
	snapshot_size(society,inventory,count,"filled")
	timed_batches(society,256,str(count)+" filled steady")
	set_filled_state(society,sample,true)
	snapshot_size(society,inventory,count,"maximum memory text")
	society.free()
	world.free()

func run() -> void:
	measure(1122)
	measure(2048)
	print("Code Form scale: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
