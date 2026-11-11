extends SceneTree
## Pure model/save checks; no game scene, frame polling, or external assets.
const Inventory = preload("res://scripts/inventory.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Store = preload("res://scripts/inventory_store.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a)==JSON.stringify(b)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var a := Inventory.new()
	var b := Inventory.new()
	b.owner_id = "peer-b"
	check(Catalog.get_definition(&"unknown") == null and Catalog.create(&"unknown") == null,"Unknown catalog IDs cannot mint items")
	check(Catalog.all().size()>=11 and Catalog.get_definition(&"health_glyph").category==&"consumables" and Catalog.get_definition(&"eternal_scribe_robes").is_equippable,"Catalog includes Health Glyphs, weapons, wearable robes and all existing categories")
	check(Catalog.create(&"katana",2) == null and Catalog.create(&"light_shard",0) == null,"Catalog quantities respect stack limits")
	a.seed_starter()
	check(a.items.size()==4 and a.equipment.size()==4,"A fresh character gets exactly four unique starter weapons")
	var starter := a.serialize()
	a.seed_starter()
	check(same(starter,a.serialize()),"Repeated starter seeding cannot duplicate equipment")
	var identities: Dictionary = {}
	for id: String in a.items:
		check(id.length()==32 and not identities.has(id),"Equipment has a unique opaque instance identity")
		identities[id] = true
	for slot: StringName in Inventory.SLOTS:
		check(a.weapon_slot(slot)==slot,"Default direction resolves to its existing canonical moveset: "+String(slot))
	var katana: Resource = a.equipped_item(&"right")
	katana.upgrade_level = 7
	katana.custom_properties = {"inscription":"return home","stats":{"power":1.25,"precision":1.2345678901234567},"runes":["red",2,true]}
	check(a.assign(&"up",katana.instance_id) and a.weapon_slot(&"up")==&"right" and a.equipped_item(&"right")==null,"Any owned weapon moves to another direction without cloning")
	check(not a.assign(&"wrong",katana.instance_id) and not a.assign(&"down","missing"),"Invalid directions and absent items cannot be equipped")
	var before := a.serialize()
	check(a.take_item(katana.instance_id,2)==null and same(before,a.serialize()),"Failed quantity removal leaves equipment and items unchanged")
	var transferred: Resource = a.take_item(katana.instance_id)
	check(transferred==katana and transferred.owner_id.is_empty() and a.equipped_item(&"up")==null,"Removing unique gear first unequips and preserves the exact instance")
	check(b.add_item(transferred) and transferred.owner_id==b.owner_id and transferred.upgrade_level==7 and transferred.custom_properties.inscription=="return home","A new collector owns the same upgraded weapon and properties")
	check(not a.add_item(transferred),"An inventory rejects a resource still owned by another player")
	check(not b.add_item(transferred),"Submitting the same owned instance twice cannot duplicate it")
	var returned: Resource = b.take_item(transferred.instance_id)
	check(a.add_item(returned) and returned.instance_id==katana.instance_id and returned.upgrade_level==7,"Ownership can transfer back without an original-owner entitlement or reset")
	var shard: Resource = Catalog.create(&"light_shard",90)
	var extra: Resource = Catalog.create(&"light_shard",20)
	check(a.add_item(shard) and a.add_item(extra) and shard.quantity==99 and extra.quantity==11,"Matching stacks fill to the maximum and retain the incoming remainder identity")
	var absorbed: Resource = Catalog.create(&"light_shard",3)
	check(a.add_item(absorbed) and extra.quantity==14 and absorbed.quantity==0 and not a.add_item(absorbed),"Complete stack absorption consumes its input resource once")
	var variant: Resource = Catalog.create(&"light_shard",2)
	variant.custom_properties = {"grade":"prismatic"}
	var upgraded: Resource = Catalog.create(&"light_shard",2)
	upgraded.upgrade_level = 1
	check(a.add_item(variant) and a.add_item(upgraded) and variant.quantity==2 and upgraded.quantity==2,"Custom properties and upgrade levels keep unlike stacks separate")
	check(Instance.same_properties({"nested":[2,{"value":3.0}]},{"nested":[2.0,{"value":3}]}),"Matching nested numeric properties ignore JSON int/float representation")
	var shard_id: String = shard.instance_id
	var split: Resource = a.take_item(shard_id,8)
	check(split != null and split.instance_id != shard_id and split.quantity==8 and shard.quantity==91 and split.owner_id.is_empty(),"Partial removal creates a new stack identity without changing the retained identity")
	check(b.add_item(split) and split.owner_id==b.owner_id,"A split stack can transfer to a different collector")
	var key: Resource = Catalog.create(&"civic_key")
	var cosmetic: Resource = Catalog.create(&"cyan_mantle")
	check(a.add_item(key) and a.add_item(cosmetic) and not a.assign(&"down",key.instance_id) and not a.assign(&"left",cosmetic.instance_id),"Key/cosmetic data cannot masquerade as a supported weapon slot")
	check(not Catalog.get_definition(&"civic_key").is_tradeable and not Catalog.get_definition(&"civic_key").is_droppable,"Exclusive item protection is driven by flags")
	a.assign(&"up",katana.instance_id)
	var eligible: Array = a.eligible_equipped()
	check(eligible.size()==a.equipment.size() and eligible.has(katana.instance_id) and not eligible.has(cosmetic.instance_id),"Death eligibility contains unique equipped transferable gear only")
	var definition: Resource = Catalog.get_definition(&"katana")
	definition.is_tradeable = false
	check(not a.eligible_equipped().has(katana.instance_id),"A nontradeable weapon is excluded even when droppable")
	definition.is_tradeable = true
	var copied: Resource = Instance.from_dict(JSON.parse_string(JSON.stringify(katana.to_dict(),"",true,true)))
	check(copied != null and copied.instance_id==katana.instance_id and copied.custom_properties==katana.custom_properties and copied.upgrade_level==7,"Instance JSON round-trip preserves identity, upgrades and nested properties")
	var malformed: Dictionary = katana.to_dict()
	malformed.quantity = 1.5
	check(Instance.from_dict(malformed)==null,"Fractional item quantities are rejected")
	malformed = katana.to_dict()
	malformed.custom_properties = {"not_serializable":Vector3.ONE}
	check(Instance.from_dict(malformed)==null,"Nonserializable custom properties are rejected")
	malformed = katana.to_dict()
	malformed.item_type_id = "unknown"
	check(Instance.from_dict(malformed)==null,"Unknown item IDs are rejected during deserialization")
	var restored := Inventory.new()
	var encoded := a.serialize()
	check(restored.restore(JSON.parse_string(JSON.stringify(encoded,"",true,true))) and same(restored.serialize(),encoded),"Owned data and arbitrary directional assignments survive JSON save/load")
	var bad := encoded.duplicate(true)
	bad.items.append(bad.items[0].duplicate(true))
	before = restored.serialize()
	check(not restored.restore(bad) and same(before,restored.serialize()),"Duplicate instance IDs reject the entire restore atomically")
	bad = encoded.duplicate(true)
	bad.equipment["up"] = "missing"
	check(not restored.restore(bad) and same(before,restored.serialize()),"Dangling equipment assignments reject the entire restore")
	bad = encoded.duplicate(true)
	bad.equipment["left"] = bad.equipment["up"]
	check(not restored.restore(bad) and same(before,restored.serialize()),"One unique item cannot be assigned to two directions in a save")
	bad = encoded.duplicate(true)
	bad.items[0].owner_id = "foreign"
	check(not restored.restore(bad) and same(before,restored.serialize()),"A save cannot mix foreign-owned items into a local inventory")
	var empty := Inventory.new()
	check(empty.restore({"version":1,"owner_id":"local","items":[],"equipment":{}}),"A legitimately empty owned save is valid")
	empty.seed_starter()
	check(empty.items.is_empty() and empty.equipment.is_empty(),"Loading empty inventory never restores lost starter weapons")
	var world_item: Resource = Catalog.create(&"spear")
	world_item.upgrade_level = 3
	var drop := {"pickup_id":"pickup-one","item":world_item.to_dict(),"position":[1.0,2.0,-3.0],"death_owner_id":"local"}
	var checkpoint := Store.encode(a,[drop],[],"test-session")
	check(not checkpoint.is_empty() and checkpoint.markers.size()==1 and checkpoint.markers[0].instance_id==world_item.instance_id,"One checkpoint includes owned items, world instances and derived death markers")
	var round_trip := Store.decode(JSON.parse_string(JSON.stringify(checkpoint)))
	check(not round_trip.is_empty() and round_trip.world_drops[0].item.upgrade_level==3,"Whole-session checkpoint survives JSON round-trip")
	bad = checkpoint.duplicate(true)
	bad.world_drops[0].item = katana.to_dict()
	bad.world_drops[0].item.owner_id = ""
	check(Store.decode(bad).is_empty(),"Checkpoint rejects an instance present in both inventory and world")
	bad = checkpoint.duplicate(true)
	bad.world_drops.append(bad.world_drops[0].duplicate(true))
	check(Store.decode(bad).is_empty(),"Checkpoint rejects duplicate pickup and world instance IDs")
	bad = checkpoint.duplicate(true)
	bad.world_drops[0].position[0] = INF
	check(Store.decode(bad).is_empty(),"World pickup positions must be finite")
	bad = checkpoint.duplicate(true)
	bad.markers = [{"instance_id":"stolen","owner_id":"local","position":[0,0,0]}]
	check(Store.decode(bad).markers[0].instance_id==world_item.instance_id,"Stale independent marker data cannot track acquired items")
	var path := "res://.godot/inventory-model-tests/checkpoint-"+Instance.new_id()+".json"
	check(Store.store(path,checkpoint)==OK and not Store.load_snapshot(path).is_empty(),"Whole checkpoints write and load through a temporary-file commit")
	var disk := Store.load_snapshot(path)
	var accurate := false
	for entry: Dictionary in disk.inventory.items:
		if entry.instance_id == katana.instance_id: accurate = entry.custom_properties.stats.precision==katana.custom_properties.stats.precision
	check(accurate,"Disk checkpoints preserve full-precision mutable numeric properties")
	var main_text := FileAccess.get_file_as_string(path)
	var file := FileAccess.open(path+".bak",FileAccess.WRITE)
	file.store_string(main_text)
	file.close()
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string("corrupt checkpoint")
	file.close()
	check(not Store.load_snapshot(path).is_empty() and FileAccess.get_file_as_string(path)=="corrupt checkpoint","A valid interrupted-write backup loads without overwriting a corrupt source")
	file = FileAccess.open(path+".bak",FileAccess.WRITE)
	file.store_string("also corrupt")
	file.close()
	check(Store.load_snapshot(path).is_empty() and FileAccess.get_file_as_string(path)=="corrupt checkpoint","Both invalid files fail closed without writing or seeding")
	check(Store.store(path,{})==ERR_INVALID_DATA and FileAccess.get_file_as_string(path)=="corrupt checkpoint","Invalid snapshots cannot overwrite an existing save")
	check(Store.store(path,checkpoint)==OK and not Store.load_snapshot(path).is_empty(),"A later valid whole checkpoint replaces an existing file through the backup commit")
	var many := Inventory.new()
	var started := Time.get_ticks_usec()
	for index in range(400):
		var item: Resource = Catalog.create(&"echo_fragment",1)
		item.custom_properties = {"signal":index}
		many.add_item(item)
	var hundreds := many.serialize()
	var loaded_many := Inventory.new()
	check(many.items.size()==400 and loaded_many.restore(hundreds) and loaded_many.items.size()==400,"Hundreds of distinct property-bearing stacks save and restore without polling")
	print("Inventory 400-item add/save/restore: ",float(Time.get_ticks_usec()-started)/1000.0," ms")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
	for inventory: Node in [a,b,restored,empty,many,loaded_many]: inventory.free()
	print("Inventory model verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
