extends SceneTree
## Optional Dark Box issue provenance crosses the same strict inventory,
## civilian and asynchronous value-only checkpoint boundaries as other systems.
const Store=preload("res://scripts/inventory_store.gd")
const Encoder=preload("res://scripts/checkpoint_encoder.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Patrol=preload("res://scripts/dark_box_patrols.gd")
var checks:=0
var failures:=0
var inventory: Node
var economy: Node
var registry: RefCounted
var encoder:=Encoder.new()
var wand_id: String

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)

func snapshot() -> Dictionary:
	return {"version":1,"policy":"singleplayer_checkpoint","session_id":"singleplayer","inventory":inventory.serialize(),"world_drops":[],"markers":[],"civilian_state":economy.serialize(),"civilization_state":{"version":1,"registry":registry.serialize(),"saved_unix":Time.get_unix_time_from_system(),"autonomy":{"version":1,"cursor":0,"states":{}}},"dark_box_state":{"version":1,"issued":{"officer":wand_id},"defeated_until":{"officer":600.0}}}

func worker_result() -> Dictionary:
	for i in range(1000):
		if encoder.ready(): return encoder.take_result()
		await process_frame
	encoder.discard()
	return {}

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("TEST WATCHDOG");quit(2))
	inventory=Inventory.new(); inventory.owner_id="local"; root.add_child(inventory)
	economy=Economy.new(); economy.player_inventory=inventory; root.add_child(economy)
	registry=Registry.new()
	var rows: Array[Dictionary]=[]
	for id: String in ["officer","partner"]: rows.append({"slot":"hub/"+id,"id":id,"name":id,"occupation":"guard","personality":"pragmatic","respawn":{"location":"overworld","position":[0,.2,0],"yaw":0}})
	check(registry.bootstrap(rows) and economy.configure("local",registry.active_ids()) and economy.bless_cycle(0,registry.active_ids()),"Real civilian identities and a conserved ledger form the officer checkpoint fixture")
	var wand: Resource=Catalog.create(&"dark_box_arc_wand")
	check(wand!=null and economy.npc_store("officer").add_item(wand) and economy.npc_store("officer").assign(&"up",wand.instance_id),"Standard issue is a real owned and equipped catalogue item")
	wand_id=wand.instance_id
	var base:=snapshot()
	check(not Store.decode(base).is_empty(),"Officer issue provenance and a future recovery deadline survive strict checkpoint validation")
	check(not Store.decode(JSON.parse_string(JSON.stringify(base))).is_empty(),"Dark Box state survives canonical JSON numeric and identity conversion")
	var equipped:=Store.decode(base)
	check(equipped.civilian_state.npc_stores.officer.equipment.up==wand_id,"Strict civilian checkpoints preserve a resident's actual equipped weapon identity")
	var storage_weapon: Resource=Catalog.create(&"katana")
	economy.guild_stock.add_item(storage_weapon)
	var forbidden:=snapshot()
	forbidden.civilian_state.guild_stock.equipment={"right":storage_weapon.instance_id}
	check(Store.decode(forbidden).is_empty(),"Allowing civilian equipment does not allow guild stock to become an equipped actor")
	var locker_weapon: Resource=Catalog.create(&"katana")
	economy.room_stores[0].add_item(locker_weapon)
	forbidden=snapshot()
	forbidden.civilian_state.room_stores["0"].equipment={"right":locker_weapon.instance_id}
	check(Store.decode(forbidden).is_empty(),"Rental storage also remains unequipped under the scoped civilian exception")
	var legacy:=base.duplicate(true); legacy.erase("dark_box_state")
	check(not Store.decode(legacy).is_empty(),"Legacy checkpoints without optional Dark Box state remain valid")
	var invalid:=base.duplicate(true); invalid.dark_box_state.issued.partner=wand_id
	check(Store.decode(invalid).is_empty() and encoder.start(invalid)==ERR_INVALID_DATA,"One actual issued wand cannot be attributed to two officer identities")
	invalid=base.duplicate(true); invalid.dark_box_state.issued["invented-officer"]="unowned-provenance"
	check(Store.decode(invalid).is_empty(),"Unregistered officer identities cannot acquire persisted issue provenance")
	check(encoder.start(invalid)==OK,"Cross-registry officer validation uses the worker's isolated society capture")
	var result:=await worker_result()
	check(result.get("error")==ERR_INVALID_DATA and result.get("bytes",PackedByteArray()).is_empty(),"The asynchronous worker rejects unknown officer identities without producing checkpoint bytes")
	check(encoder.start(snapshot())==OK,"The private encoder accepts an actual equipped resident inventory")
	result=await worker_result()
	var equipped_bytes: Variant=JSON.parse_string(result.get("bytes",PackedByteArray()).get_string_from_utf8())
	check(result.get("error")==OK and equipped_bytes is Dictionary and equipped_bytes.civilian_state.npc_stores.officer.equipment.up==wand_id and not Store.decode(equipped_bytes).is_empty(),"Value-only worker encoding preserves actual civilian equipment assignments")
	invalid=base.duplicate(true); invalid.dark_box_state.defeated_until.officer=-1
	check(Store.decode(invalid).is_empty() and encoder.start(invalid)==ERR_INVALID_DATA,"Invalid recovery times are rejected before a worker starts")
	invalid=base.duplicate(true); invalid.dark_box_state.defeated_until.partner=300
	check(Store.decode(invalid).is_empty(),"A recovery deadline requires an actual historical issue record")
	var sword: Resource=Catalog.create(&"katana")
	inventory.add_item(sword)
	invalid=snapshot(); invalid.dark_box_state.issued.officer=sword.instance_id
	check(Store.decode(invalid).is_empty(),"Existing item provenance cannot point at a different weapon class")
	var moved: Resource=economy.npc_store("officer").take_item(wand_id,1)
	check(moved!=null and inventory.add_item(moved) and not Store.decode(snapshot()).is_empty(),"A sold or transferred wand retains valid original issue provenance in its new owner's inventory")
	inventory.take_item(wand_id,1)
	check(not Store.decode(snapshot()).is_empty(),"An issued wand may be absent after loss without granting a replacement on load")
	var private_capture:=snapshot()
	check(encoder.start(private_capture)==OK,"Canonical Dark Box state enters the private value-only encoder")
	private_capture.dark_box_state.issued.officer="mutated-after-capture"
	private_capture.dark_box_state.defeated_until.officer=99999.0
	result=await worker_result()
	var decoded: Variant=JSON.parse_string(result.get("bytes",PackedByteArray()).get_string_from_utf8())
	check(result.get("error")==OK and decoded is Dictionary and decoded.dark_box_state.issued.officer==wand_id and decoded.dark_box_state.defeated_until.officer==600.0 and not Store.decode(decoded).is_empty(),"Worker output privately preserves officer recovery and unique issue identities despite later source mutation")
	check(Patrol.validate({"version":1,"issued":{},"defeated_until":{}}).size()==3,"An empty legacy patrol model is valid without spawning or issuing equipment")
	economy.free(); inventory.free()
	print("DARK BOX CHECKPOINT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
