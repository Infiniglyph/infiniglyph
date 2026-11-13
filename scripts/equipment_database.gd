extends RefCounted
## Content-only registry. No ownership, input, physics, or external references.
static var entries: Dictionary = {}
static var _prepared := false

static func prepare() -> void:
	if _prepared: return
	_prepared = true
	for path: String in ["res://data/equipment/catalog.json","res://data/equipment/named_weapons.json"]:
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not document is Dictionary or document.get("version")!=1 or not document.get("items") is Array:
			push_error("Invalid equipment content: "+path)
			continue
		for item: Dictionary in document.items:
			if not valid(item) or entries.has(StringName(item.id)):
				push_error("Invalid or duplicate equipment definition in "+path)
				continue
			entries[StringName(item.id)] = item

static func valid(item: Dictionary) -> bool:
	for key: String in ["id","name","description","category","kind","family","slot","combat_kind","rarity","acquisition"]:
		if not item.get(key) is String or item[key].is_empty(): return false
	if not item.get("geometry") is Dictionary or not item.get("effects") is Array: return false
	if not item.get("value") is float and not item.get("value") is int: return false
	if item.kind=="named":
		if not item.get("moves") is Dictionary: return false
		for action: String in ["attack_left","attack_right","special_x","special_y","special_rt_x","special_rt_y"]:
			for suffix: String in ["","_air"]:
				var sequence: Variant = item.moves.get(action+suffix)
				if not sequence is Array or sequence.is_empty(): return false
				for move: Variant in sequence:
					if not move is Dictionary or not move.get("motion") is Array or move.motion.size()<2: return false
					if not move.get("hits") is Array or move.hits.is_empty() or float(move.get("duration",0))<=0: return false
					if float(move.hits[0])<float(move.get("windup",0)) or float(move.hits[-1])>=float(move.duration): return false
					var previous := -1.0
					for frame: Variant in move.motion:
						if not frame is Dictionary or float(frame.get("t",-1))<=previous or float(frame.t)>1: return false
						previous = float(frame.t)
						for key: String in ["right","left","right_rotation","left_rotation","hip","chest"]:
							if not frame.get(key) is Array or frame[key].size()!=3: return false
	return item.category in ["weapons","cosmetics","misc"] and item.id.length()<=128

static func get_item(id: StringName) -> Dictionary:
	prepare()
	return entries.get(id,{})

static func all() -> Array:
	prepare()
	return entries.values()

static func is_weapon(id: StringName) -> bool:
	var item := get_item(id)
	return item.get("category")=="weapons"
