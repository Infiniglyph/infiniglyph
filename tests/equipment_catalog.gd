extends SceneTree
const Database = preload("res://scripts/equipment_database.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var start := Time.get_ticks_usec()
	var all := Database.all()
	var catalog := Catalog.all()
	print("CATALOG LOAD: ",(Time.get_ticks_usec()-start)/1000.0," ms; definitions=",catalog.size())
	var summary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/summary.json"))
	var named: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment/named_weapons.json"))
	check(all.size()==int(summary.counterparts)+named.items.size(),"Every audited counterpart and authored named design is registered")
	var names: Dictionary = {}
	var valid := true
	var effects_inert := true
	var owned := Inventory.new()
	var families: Dictionary = {}
	var geometries: Dictionary = {}
	for entry: Dictionary in all:
		valid = valid and Database.valid(entry) and not names.has(entry.name)
		names[entry.name] = true
		effects_inert = effects_inert and entry.effects.is_empty()
		families[entry.family] = entry
		geometries[JSON.stringify(entry.geometry)] = entry.geometry
		var instance: Resource = Catalog.create(StringName(entry.id))
		valid = valid and instance!=null and owned.add_item(instance)
	check(valid,"Every counterpart has a unique title, valid definition and owned instance")
	check(effects_inert,"No infusion, ring, armor, mana or stamina effects are silently activated")
	var serialized: Dictionary = Store.encode(owned)
	var restored := Inventory.new()
	check(not serialized.is_empty() and restored.restore(serialized.inventory) and restored.items.size()==all.size(),"The entire catalog survives existing version-one checkpoint ownership serialization")
	var mesh_start := Time.get_ticks_usec()
	var geometry_ok := true
	var vertices := 0
	for geometry: Dictionary in geometries.values():
		var model := Geometry.model(geometry)
		for node: MeshInstance3D in model.get_children():
			geometry_ok = geometry_ok and node.mesh.get_surface_count()>0
			vertices += node.mesh.surface_get_array_len(0)
		model.free()
	check(geometry_ok,"Every equipment family builds actual solid and wire geometry")
	print("FAMILY GEOMETRY: ",families.size()," families; ",geometries.size()," distinct profiles; ",vertices," vertices; ",(Time.get_ticks_usec()-mesh_start)/1000.0," ms")
	var signatures: Dictionary = {}
	var animations_ok := true
	for id: StringName in [&"fractured_moon",&"event_horizon",&"last_argument"]:
		var entry := Database.get_item(id)
		var basic := Library.move(id,&"attack_right",0,false)
		var next := Library.move(id,&"attack_right",1,false)
		var air := Library.move(id,&"attack_right",0,true)
		check(basic.name!=next.name and basic.combo_index==0 and next.combo_index==1 and air.aerial and air.motion!=basic.motion,String(id)+" has distinct combo stages and aerial curves")
		var signature := str(Motion.sample(basic,float(basic.duration)*.42))
		signatures[signature] = true
		for sequence: Array in entry.moves.values():
			for move: Dictionary in sequence:
				animations_ok = animations_ok and float(move.hits[0])>=float(move.windup) and float(move.hits[-1])<float(move.duration) and move.motion.size()>=5
		var charged := Library.charged_move(id,&"special_x",1)
		var plain := Library.move(id,&"special_x")
		check(charged.damage>plain.damage and charged.hits.size()>plain.hits.size(),String(id)+" retains the existing charged-release extension")
	check(signatures.size()==3 and animations_ok,"Named weapons have different actual joint curves and valid hit windows")
	var sample: Dictionary
	for entry: Dictionary in all:
		if entry.family=="head": sample=entry; break
	var instance: Resource = owned.items.values().filter(func(i: Resource): return i.item_type_id==StringName(sample.id))[0]
	check(owned.assign(&"head",instance.instance_id) and not owned.assign(&"body",instance.instance_id),"Cosmetic pieces only fit their authored equipment slots")
	check(Geometry.cache.size()<=Geometry.CACHE_LIMIT,"Procedural geometry cache remains bounded")
	owned.free()
	restored.free()
	print("EQUIPMENT CATALOG: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
