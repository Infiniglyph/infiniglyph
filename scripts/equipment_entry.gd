extends RefCounted
## Shared presentation metadata for the testing exchange and physical shops.
const Database = preload("res://scripts/equipment_database.gd")
const Catalog = preload("res://scripts/item_catalog.gd")

static func for_id(id: StringName) -> Dictionary:
	var entry := Database.get_item(id)
	if not entry.is_empty(): return entry
	var definition: Resource = Catalog.get_definition(id)
	if definition==null: return {}
	var family := "body" if id==&"eternal_scribe_robes" else "consumable" if definition.category==&"consumables" else String(id)
	return {"id":String(id),"name":definition.display_name,"description":definition.description,"category":String(definition.category),"kind":"starter","family":family,"rarity":"Civic","value":0,"acquisition":"Tower Exchange","geometry":{"family":family,"length":1.2,"tint":"75eaff"}}
