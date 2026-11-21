extends RefCounted
const Catalog=preload("res://scripts/item_catalog.gd")
const Materials=preload("res://scripts/crafting_materials.gd")
static var entries: Dictionary={}
static func valid(row: Dictionary) -> bool:
	if row.get("id","").is_empty() or not row.get("ingredients") is Dictionary or row.ingredients.is_empty(): return false
	var output: Resource=Catalog.get_definition(StringName(row.get("output_item","")))
	if output==null or not Catalog.Instance.whole_number(row.get("output_quantity"),1,output.max_stack): return false
	for id: String in row.ingredients:
		if Materials.get_material(id).is_empty() or not Catalog.Instance.whole_number(row.ingredients[id],1,999): return false
		var dungeon: String=Materials.get_material(id).get("source_dungeon","")
		if not dungeon.is_empty() and row.get("source_dungeon","")!=dungeon: return false
	if output.custom_properties.get("catalog_group")=="electron_meals" and not row.ingredients.has("electrons"): return false
	return true
static func all(category: String="") -> Array:
	if entries.is_empty():
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/crafting_recipes.json"))
		for row: Dictionary in data.recipes:
			assert(valid(row) and not entries.has(row.id),"Invalid crafting recipe: "+str(row.get("id")))
			row["category"]=String(row.get("category","equipment"))
			row["source_dungeon"]=String(row.get("source_dungeon",""))
			entries[row.id]=row
	return entries.values().filter(func(row): return category.is_empty() or row.category==category)
static func get_recipe(id: String) -> Dictionary:
	all(); return entries.get(id,{}).duplicate(true)
