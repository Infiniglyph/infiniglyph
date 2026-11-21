extends RefCounted
## Stable recipe identifiers can refer to existing inventory items (Bone Shards).
static var entries: Dictionary={}
static func all() -> Array:
	if entries.is_empty():
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/crafting_materials.json"))
		for row: Dictionary in data.materials:
			assert(not entries.has(row.id) and not String(row.id).is_empty())
			row["source_dungeon"]=String(row.get("source_dungeon",""))
			entries[row.id]=row
	return entries.values()
static func get_material(id: String) -> Dictionary:
	all(); return entries.get(id,{})
static func item_id(id: String) -> StringName:
	return StringName(get_material(id).get("item_id",""))
