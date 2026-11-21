extends SceneTree
const Craft=preload("res://scripts/terminal_crafting.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Passives=preload("res://scripts/equipment_passives.gd")
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func stock(store: Node,id: StringName,amount: int) -> void:
	check(store.add_item(Catalog.create(id,amount)),"Can store "+String(id))
func run():
	create_timer(60).timeout.connect(func(): quit(2))
	var owner:=Inventory.new(); owner.owner_id="player"; root.add_child(owner)
	var storage:=Inventory.new(); storage.owner_id="terminal:fixture"; root.add_child(storage)
	for row: Dictionary in Craft.Materials.all():
		stock(owner,StringName(row.item_id),2); stock(owner,StringName(row.item_id),3)
		check(owner.count_type(StringName(row.item_id))==5 and owner.restore(JSON.parse_string(JSON.stringify(owner.serialize()))),"Material stacking and JSON reload preserve "+row.id)
	check(Craft.Materials.item_id("tomb_bone_shards")==&"bone_shards","The tomb material reuses actual dropped Bone Shards instead of duplicating definitions")
	for recipe: Dictionary in Craft.Recipes.all(): check(Craft.Recipes.valid(recipe),"Valid exact-ID recipe "+recipe.id)
	for item: Resource in owner.items.values():
		if item.item_type_id==&"melted_ore": owner.take_item(item.instance_id,3); break
	var missing:=owner.serialize(); var before_storage:=storage.serialize()
	check(not Craft.transact(owner,storage,"forge_tomb_blade") and owner.serialize()==missing and storage.serialize()==before_storage,"Missing industrial amounts leave both inventories byte-equivalent")
	owner.restore({"version":1,"owner_id":"player","items":[],"equipment":{}})
	stock(owner,&"electrons",1); stock(storage,&"electrons",3); stock(storage,&"hadron_grains",4)
	check(Craft.transact(owner,storage,"prepare_electron_rice") and owner.count_type(&"electron_rice")==1 and owner.count_type(&"electrons")==0 and storage.count_type(&"electrons")==2,"A craft combines owned inventory and terminal storage and deducts once")
	check(Craft.transact(owner,storage,"prepare_electron_rice") and owner.count_type(&"electron_rice")==2,"Repeated crafting uses only the remaining owned materials")
	var snapshot:=owner.serialize()
	check(not Craft.transact(owner,storage,"prepare_electron_rice") and owner.serialize()==snapshot,"An exhausted recipe cannot mint another output")
	stock(storage,&"electrons",2); stock(storage,&"hadron_grains",2)
	owner.capture_cache_enabled=true; storage.capture_cache_enabled=true
	owner.capture_values(); storage.capture_values()
	var coherent:={"ok":false}
	check(Craft.transact(owner,storage,"prepare_electron_rice","",func(): coherent.ok=owner.capture_values()==owner.serialize() and storage.capture_values()==storage.serialize()) and coherent.ok,"Property commit observers see fresh coherent snapshots while inventory signals are held")
	stock(owner,&"melted_ore",9); stock(owner,&"glyph_crystal",10)
	snapshot=owner.serialize()
	check(not Craft.transact(owner,storage,"forge_tomb_blade") and owner.serialize()==snapshot,"Extra ordinary crystals never substitute for the exact dungeon material")
	stock(storage,&"bone_shards",2)
	check(Craft.transact(owner,storage,"forge_tomb_blade") and owner.count_type(&"tomb_blade")==1 and storage.count_type(&"bone_shards")==0,"Tomb Blade consumes its real dungeon fragments")
	var blade: Resource=owner.items.values().filter(func(item): return item.item_type_id==&"tomb_blade")[0]
	owner.assign(&"down",blade.instance_id); snapshot=owner.serialize()
	check(not Craft.transact(owner,storage,"",blade.instance_id) and owner.serialize()==snapshot,"An equipped weapon cannot be recycled accidentally")
	owner.unequip(&"down"); var ore:=owner.count_type(&"melted_ore"); var identity: String=blade.instance_id
	check(Craft.transact(owner,storage,"",identity) and owner.get_item(identity)==null and owner.count_type(&"melted_ore")==ore+2 and owner.count_type(&"bone_shards")==0,"Recycling consumes the weapon and recovers reduced ore without dungeon refunds")
	check(not Craft.transact(owner,storage,"",identity),"Replaying a consumed recycling identity cannot duplicate ore")
	var ring: Resource=Catalog.create(&"eq_r_20004e5c"); owner.add_item(ring); owner.assign(&"ring1",ring.instance_id)
	var bonuses:=Passives.total(owner)
	check(bonuses.hp>0 and Passives.for_item(Catalog.Instance.from_dict(ring.to_dict()),Catalog.get_definition(ring.item_type_id))==Passives.for_item(ring,Catalog.get_definition(ring.item_type_id)),"Named ring affinity and random instance roll survive JSON without rerolling")
	owner.unequip(&"ring1"); check(Passives.total(owner).hp==0,"Carried rings grant no passive benefits until equipped")
	var reentry:={"attempts":0,"accepted":false}
	stock(owner,&"electrons",2); stock(owner,&"hadron_grains",2)
	owner.changed.connect(func(): reentry.attempts+=1; reentry.accepted=Craft.transact(owner,storage,"prepare_electron_rice"))
	check(Craft.transact(owner,storage,"prepare_electron_rice") and reentry.attempts==1 and not reentry.accepted,"Observers cannot reenter the crafting transaction while its final signals publish")
	check(owner.restore(JSON.parse_string(JSON.stringify(owner.serialize()))) and storage.restore(JSON.parse_string(JSON.stringify(storage.serialize()))),"Crafted outputs and terminal storage retain ordinary save/load compatibility")
	var tonic: Resource=Catalog.get_definition(&"signal_tonic")
	check(tonic.custom_properties.get("civilian_food",false) and tonic.custom_properties.get("shield_restore",0)>0,"Signal Tonic has a real drink/shield recovery purpose")
	var full:=Inventory.new(); full.owner_id="full"; root.add_child(full)
	for i in range(Inventory.MAX_ITEMS):
		var item: Resource=Catalog.create(&"echo_fragment"); item.owner_id=full.owner_id; item.custom_properties={"fixture":i}; full.items[item.instance_id]=item
	stock(storage,&"electrons",3); stock(storage,&"hadron_grains",3)
	check(Craft.transact(full,storage,"prepare_electron_rice") and storage.count_type(&"electron_rice")==1,"A full actor inventory sends output into accessible terminal storage")
	for i in range(Inventory.MAX_ITEMS-storage.items.size()):
		var item: Resource=Catalog.create(&"echo_fragment"); item.owner_id=storage.owner_id; item.custom_properties={"fixture":i}; storage.items[item.instance_id]=item
	stock(storage,&"electrons",2); stock(storage,&"hadron_grains",2)
	# Keep both ingredient stacks and the existing rice stack full enough that
	# consumption frees no slot and output cannot merge with its full stack.
	for item: Resource in storage.items.values():
		if item.item_type_id==&"electron_rice": item.quantity=Catalog.get_definition(item.item_type_id).max_stack
	var full_before:=full.serialize(); var storage_before:=storage.serialize()
	check(not Craft.transact(full,storage,"prepare_electron_rice") and full.serialize()==full_before and storage.serialize()==storage_before,"Two full stores reject output capacity without consuming partial ingredient stacks")
	full.free()
	owner.free(); storage.free()
	print("TERMINAL CRAFTING: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
