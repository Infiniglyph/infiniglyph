extends RefCounted
## Presentation-only types; inventory ownership and equipment rules stay in Catalog.
const Database = preload("res://scripts/equipment_database.gd")
const WEAPONS := {
	"sword_shield":"Longsword + Shield", "fist":"Fist Weapon", "dagger":"Dagger",
	"sword":"Sword", "curved_sword":"Curved Sword", "greatsword":"Greatsword",
	"katana":"Katana", "axe":"Axe", "twin_blades":"Twin Blades", "hammer":"Hammer",
	"spear":"Spear", "scythe":"Scythe", "halberd":"Halberd", "whip":"Whip",
	"talisman":"Talisman", "staff":"Staff", "chime":"Chime", "bow":"Bow", "crossbow":"Crossbow"
}

static func label(definition: Resource) -> String:
	if definition==null: return "Empty"
	var properties: Dictionary = definition.custom_properties
	var entry: Dictionary = Database.get_item(definition.item_type_id)
	var family := String(properties.get("family",entry.get("family",definition.item_type_id)))
	if definition.category==&"weapons":
		return String(WEAPONS.get(family,family.replace("_"," ").capitalize()))
	if family=="ring" or properties.get("cosmetic_slot")=="ring": return "Ring"
	if definition.category==&"cosmetics":
		if not definition.is_equippable: return "Cosmetic Pattern"
		if definition.item_type_id==&"eternal_scribe_robes": return "Cloth Robe / Body"
		var slot := String(properties.get("cosmetic_slot",family))
		if slot=="shield": return "Shield / Offhand"
		var geometry: Dictionary = entry.get("geometry",{})
		var tailoring: Dictionary = geometry.get("tailoring",{})
		var cloth: bool = tailoring.get("cut",geometry.get("style","plate"))=="cloth"
		match slot:
			"body": return ("Cloth Robe" if cloth else "Plate Armour")+" / Body"
			"hands": return ("Cloth Gloves" if cloth else "Plate Gauntlets")+" / Hands"
			"legs": return ("Cloth Legwear" if cloth else "Plate Legwear")+" / Legs"
			"head":
				var head := "Hood" if cloth else "Helmet"
				# Match the garment renderer's form precedence for mixed profiles.
				if tailoring.get("mimic",false): head="Coffer Headpiece"
				elif tailoring.get("crown",false): head="Crown"
				elif tailoring.get("mask",false): head="Mask"
				elif tailoring.get("hood",false): head="Hood"
				elif tailoring.get("hat",false): head="Hat"
				return head+" / Head"
		return slot.replace("_"," ").capitalize()+" / Appearance"
	if definition.item_type_id==&"health_glyph": return "Health Glyph / Consumable"
	return String({&"consumables":"Consumable",&"materials":"Material",&"key_items":"Key Item",&"misc":"Miscellaneous"}.get(definition.category,String(definition.category).replace("_"," ").capitalize()))
