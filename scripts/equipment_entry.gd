extends RefCounted
## Shared presentation metadata for the testing exchange and physical shops.
const Database = preload("res://scripts/equipment_database.gd")
const Catalog = preload("res://scripts/item_catalog.gd")

static func for_id(id: StringName) -> Dictionary:
	var entry := Database.get_item(id)
	if not entry.is_empty(): return entry
	var definition: Resource = Catalog.get_definition(id)
	if definition==null: return {}
	var properties: Dictionary=definition.custom_properties
	if properties.get("civilization_catalog",false) or properties.get("civilian_food",false):
		var size: Array=properties.get("size",[.55,.65,.55])
		var length:=maxf(float(size[0]),maxf(float(size[1]),float(size[2])))
		return {"id":String(id),"name":definition.display_name,"description":definition.description,"category":String(definition.category),"catalog_group":String(properties.get("catalog_group","")),"kind":"civic_item","family":String(properties.get("furniture_kind",properties.get("cuisine_kind","food"))),"rarity":String(properties.get("rarity","Common")),"value":int(properties.get("price",0)),"acquisition":"Glyphic Wonders / Tower Exchange testing catalogue","geometry":{"renderer":"civic_item","family":String(properties.get("furniture_kind",properties.get("cuisine_kind","food"))),"length":length,"size":size,"tint":String(properties.get("tint","75eaff")),"properties":properties.duplicate(true)}}
	var family := "body" if id==&"eternal_scribe_robes" else "consumable" if definition.category==&"consumables" else String(id)
	return {"id":String(id),"name":definition.display_name,"description":definition.description,"category":String(definition.category),"kind":"starter","family":family,"rarity":"Civic","value":0,"acquisition":"Tower Exchange","geometry":{"family":family,"length":1.2,"tint":"75eaff"}}
