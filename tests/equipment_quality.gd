extends SceneTree
const Database = preload("res://scripts/equipment_database.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
const Moves = preload("res://scripts/equipment_moves.gd")
const Visual = preload("res://scripts/character_visual.gd")
const Garment = preload("res://scripts/equipment_garment.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Inventory = preload("res://scripts/inventory.gd")
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
	var count := 0
	var valid := true
	var unique: Dictionary = {}
	var clips: Dictionary = {}
	var feet := true
	var entries := Database.all()
	entries.sort_custom(func(a: Dictionary,b: Dictionary): return String(a.family)<String(b.family))
	for entry: Dictionary in entries:
		if entry.category!="weapons": continue
		count += 1
		var id := StringName(entry.id)
		var first := Library.move(id,&"attack_right")
		var second := Library.move(id,&"attack_right",1)
		var air := Library.move(id,&"attack_right",0,true)
		var art := Library.charged_move(id,&"special_x",1)
		valid = valid and entry.kind=="named" and first.get("retargeted",false) and first.motion.size()>=8 and first.name!=second.name and first.motion!=air.motion and art.damage>Library.move(id,&"special_x").damage
		var signature := JSON.stringify([first.motion,first.duration])
		if unique.has(signature): print("DUPLICATE MOTION: ",entry.id," / ",unique[signature])
		unique[signature] = entry.id
		if first.has("clip_id"): clips[first.clip_id] = true
		var pose := Motion.sample(first,float(first.hits[0]))
		feet = feet and pose.has("left_foot") and pose.has("right_foot") and pose.right.is_finite() and pose.hip.is_finite()
	check(count==1716 and valid,"Every new weapon is named and resolves sampled combos, aerial motion and charged arts")
	check(unique.size()==count,"Every named weapon has its own compiled motion/timing signature")
	check(clips.size()>100 and feet,"More than 100 actual source gestures supply hands, hips and footwork")
	check(Moves.banks.size()<=Moves.BANK_LIMIT and Moves.moves.size()<=Moves.CACHE_LIMIT,"Animation banks and compiled named moves remain bounded")
	var impacts_aligned := true
	for id: StringName in [&"fractured_moon",&"event_horizon",&"last_argument"]:
		for action: StringName in [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			var move := Library.charged_move(id,action,1)
			var contact := Motion.sample(move,float(move.hits[0]))
			for hit: float in move.hits:
				var next := Motion.sample(move,hit)
				impacts_aligned = impacts_aligned and contact.right.distance_to(next.right)<.001 and contact.hip.distance_to(next.hip)<.001
	check(impacts_aligned,"Each existing multi-hit and charged pulse aligns with a visible contact gesture")
	var actor := CharacterBody3D.new()
	var figure := Visual.new()
	figure.live_retrieval = false
	actor.add_child(figure)
	root.add_child(actor)
	var base_count := figure.chest.get_child_count()
	var wearable_count := 0
	var shape_count: Dictionary = {}
	for entry: Dictionary in entries:
		if entry.family not in ["body","head","hands","legs"]: continue
		wearable_count += 1
		shape_count[JSON.stringify(entry.geometry.tailoring)] = true
		var garment := Garment.new()
		figure.add_child(garment)
		garment.configure(figure,entry)
		garment._process(0)
		valid = valid and not garment.external.is_empty()
		for piece: Node3D in garment.external:
			valid = valid and piece.get_child_count()>1 and piece.global_position.is_finite()
		garment.free()
		await process_frame
	check(wearable_count==371 and valid,"All 371 wearable pieces build fitted geometry on the actual character joints")
	check(shape_count.size()>40,"Armor references select distinct cut, plate, shoulder, collar, cape and helmet constructions")
	check(figure.chest.get_child_count()==base_count,"Removing garments cleans external joint pieces without moving the base skeleton")
	var migrated := 0
	for entry: Dictionary in entries:
		if not entry.has("legacy_slot"): continue
		var inventory := Inventory.new()
		var item: Resource = Catalog.create(StringName(entry.id))
		inventory.add_item(item)
		var checkpoint: Dictionary = inventory.serialize()
		checkpoint.equipment = {"body":item.instance_id}
		var restored := inventory.restore(checkpoint)
		var equipped: Resource = inventory.equipped_item(StringName(entry.slot))
		check(restored and inventory.get_item(item.instance_id)!=null and equipped!=null and equipped.instance_id==item.instance_id and equipped.item_type_id==item.item_type_id,"A checkpoint with "+String(entry.name)+" in the former Body slot migrates without losing ownership")
		inventory.free()
		migrated += 1
	check(migrated==6,"Only the six corrected portrait classifications opt into slot migration")
	actor.queue_free()
	await process_frame
	print("EQUIPMENT QUALITY: ",checks," checks, ",failures," failures; ",count," weapons, ",clips.size()," source gestures, ",shape_count.size()," tailoring profiles")
	quit(1 if failures else 0)
