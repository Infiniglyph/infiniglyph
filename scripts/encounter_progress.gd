extends RefCounted
## Small, owner-scoped encounter journal, independent of inventory ownership.
## Only the local/host encounter manager may commit an outcome.
static func fresh() -> Dictionary:
	return {"intro_completed":false,"first_victory":false,"first_outcome":"","last_outcome":"","wins":0,"losses":0}

static func valid(data: Variant) -> bool:
	if not data is Dictionary: return false
	for key in ["intro_completed","first_victory"]:
		if not data.get(key) is bool: return false
	if not data.get("first_outcome") in ["","victory","defeat"]: return false
	if not data.get("last_outcome") in ["","victory","defeat"]: return false
	for key in ["wins","losses"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>1000000 or floorf(value)!=value: return false
	return data.intro_completed == (data.first_outcome!="") and data.intro_completed == (data.last_outcome!="") and data.first_victory == (data.first_outcome=="victory")

static func read(path: String, owner: String) -> Dictionary:
	for candidate in [path,path+".bak"]:
		var file := FileAccess.open(candidate,FileAccess.READ)
		if file == null: continue
		if file.get_length()>65536:
			file.close()
			continue
		var data: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if data is Dictionary and data.get("version") == 1 and data.get("owner_id") == owner and data.get("encounters") is Dictionary:
			var good: bool = data.encounters.size()<=32
			for entry: Variant in data.encounters.values(): good = good and valid(entry)
			if good: return data.encounters.duplicate(true)
	return {}

static func store(path: String, owner: String, entries: Dictionary) -> Error:
	if entries.size()>32 or owner.is_empty(): return ERR_INVALID_DATA
	for entry: Variant in entries.values():
		if not valid(entry): return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK: return error
	var file := FileAccess.open(absolute+".tmp",FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version":1,"owner_id":owner,"encounters":entries}))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return error
	var existing := FileAccess.file_exists(absolute)
	if existing:
		if FileAccess.file_exists(absolute+".bak"):
			error = DirAccess.remove_absolute(absolute+".bak")
			if error != OK: return error
		error = DirAccess.rename_absolute(absolute,absolute+".bak")
		if error != OK: return error
	error = DirAccess.rename_absolute(absolute+".tmp",absolute)
	if error != OK and existing: DirAccess.rename_absolute(absolute+".bak",absolute)
	return error
