extends RefCounted
## Whole single-player checkpoints only. Multiplayer ownership belongs to host.
const Inventory = preload("res://scripts/inventory.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const VERSION := 1
const POLICY := "singleplayer_checkpoint"
const MAX_WORLD_DROPS := 4096
const MAX_SAVE_BYTES := 8*1024*1024

static func encode(inventory: Node, world_drops: Array = [], markers: Array = [], session_id: String = "singleplayer", location: String = "overworld", location_state: Dictionary = {}) -> Dictionary:
	if inventory == null or not inventory.has_method("serialize"): return {}
	var data: Dictionary={"version":VERSION,"policy":POLICY,"session_id":session_id,"inventory":inventory.serialize(),"world_drops":world_drops,"markers":markers}
	if location!="overworld": data.location_context=location
	if not location_state.is_empty(): data.location_state=location_state
	return decode(data)

static func decode(data: Variant) -> Dictionary:
	if not data is Dictionary or not Instance.whole_number(data.get("version"),VERSION,VERSION) or data.get("policy") != POLICY: return {}
	if not Instance.valid_text(data.get("session_id")) or not data.get("world_drops") is Array or data.world_drops.size()>MAX_WORLD_DROPS: return {}
	if data.has("markers") and not data.markers is Array: return {}
	if data.has("location_context") and not Instance.valid_text(data.location_context): return {}
	var state: Dictionary={}
	if data.has("location_state"):
		if not data.location_state is Dictionary: return {}
		var input: Dictionary=data.location_state
		if input.has("ahkmet"):
			var boss: Variant=input.ahkmet
			if not boss is Dictionary or boss.size()!=2 or not Instance.whole_number(boss.get("phase"),1,2): return {}
			if not (boss.get("hp") is float or boss.get("hp") is int) or not is_finite(float(boss.hp)) or float(boss.hp)<=0 or float(boss.hp)>100000: return {}
			state.ahkmet={"phase":int(boss.phase),"hp":float(boss.hp)}
		if input.has("enemy_defeats"):
			if not input.enemy_defeats is Array or input.enemy_defeats.size()>512: return {}
			var unique: Dictionary={}
			for id: Variant in input.enemy_defeats:
				if not Instance.valid_text(id) or unique.has(String(id)): return {}
				unique[String(id)]=true
			state.enemy_defeats=unique.keys()
		if input.has("floor_id") and not Instance.valid_text(input.floor_id): return {}
		if input.has("floor_id"): state.floor_id=String(input.floor_id)
		if input.has("position"):
			if not input.position is Array or input.position.size()!=3: return {}
			for coordinate: Variant in input.position:
				if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate))>1000000: return {}
			state.position=input.position.duplicate()
		if input.has("yaw"):
			if not (input.yaw is float or input.yaw is int) or not is_finite(float(input.yaw)): return {}
			state.yaw=wrapf(float(input.yaw),-PI,PI)
	var inventory := Inventory.new()
	if not inventory.restore(data.get("inventory")):
		inventory.free()
		return {}
	var owned: Dictionary = inventory.serialize()
	var identities: Dictionary = {}
	# Include validated retired identities so migration cannot mask duplicates.
	for entry: Dictionary in data.inventory.items: identities[entry.instance_id] = true
	inventory.free()
	var pickup_ids: Dictionary = {}
	var drops: Array[Dictionary] = []
	var markers: Array[Dictionary] = []
	for entry: Variant in data.world_drops:
		if not entry is Dictionary or not Instance.valid_text(entry.get("pickup_id")) or not entry.get("position") is Array or entry.position.size()!=3: return {}
		if pickup_ids.has(String(entry.pickup_id)): return {}
		var position: Array[float] = []
		for coordinate: Variant in entry.position:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate))>1000000: return {}
			position.append(float(coordinate))
		var item: Resource = Instance.from_dict(entry.get("item"))
		if item == null or not item.owner_id.is_empty() or identities.has(item.instance_id): return {}
		var death_owner: Variant = entry.get("death_owner_id","")
		if not Instance.valid_text(death_owner,true): return {}
		identities[item.instance_id] = true
		pickup_ids[String(entry.pickup_id)] = true
		if Equipment.is_retired(item.item_type_id): continue
		drops.append({"pickup_id":String(entry.pickup_id),"item":item.to_dict(),"position":position,"death_owner_id":String(death_owner)})
		if not String(death_owner).is_empty():
			markers.append({"instance_id":item.instance_id,"owner_id":String(death_owner),"position":position.duplicate()})
		if entry.has("location_id"):
			if not Instance.valid_text(entry.location_id): return {}
			if entry.location_id!="overworld": drops[-1].location_id=String(entry.location_id)
	# Marker ownership/location is reconstructed from unclaimed drops. A stale
	# UI marker never authorizes restoring or tracking an acquired weapon.
	var decoded: Dictionary={"version":VERSION,"policy":POLICY,"session_id":String(data.session_id),"inventory":owned,"world_drops":drops,"markers":markers}
	if data.get("location_context","overworld")!="overworld": decoded.location_context=String(data.location_context)
	if not state.is_empty(): decoded.location_state=state
	return decoded

static func store(path: String, snapshot: Dictionary) -> Error:
	var validated := decode(snapshot)
	if validated.is_empty(): return ERR_INVALID_DATA
	var text := JSON.stringify(validated,"",true,true)
	if text.to_utf8_buffer().size()>MAX_SAVE_BYTES: return ERR_OUT_OF_MEMORY
	var absolute := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK: return directory_error
	var temporary := absolute+".tmp-"+Instance.new_id()
	var backup := absolute+".bak"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return write_error
	var existing := FileAccess.file_exists(absolute)
	if existing:
		if FileAccess.file_exists(backup):
			var remove_error := DirAccess.remove_absolute(backup)
			if remove_error != OK:
				DirAccess.remove_absolute(temporary)
				return remove_error
		var backup_error := DirAccess.rename_absolute(absolute,backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return backup_error
	var commit_error := DirAccess.rename_absolute(temporary,absolute)
	if commit_error != OK:
		if existing: DirAccess.rename_absolute(backup,absolute)
		DirAccess.remove_absolute(temporary)
		return commit_error
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	return OK

static func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {}
	if file.get_length()>MAX_SAVE_BYTES:
		file.close()
		return {}
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(contents) != OK: return {}
	return decode(parser.data)

static func load_snapshot(path: String) -> Dictionary:
	var main := _read(path)
	if not main.is_empty(): return main
	# A process interruption between the two renames can leave only .bak.
	# Loading never repairs/overwrites either file; the live session decides.
	return _read(path+".bak")
