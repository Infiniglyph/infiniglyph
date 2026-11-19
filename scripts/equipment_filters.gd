extends RefCounted
## Shared weapon groups for the Exchange and the owned-item browser.
const Types = preload("res://scripts/inventory_item_type.gd")
const WEAPON_NAMES := ["ALL","DAGGERS","SWORDS","HEAVY","POLEARMS","PAIRED","OTHER","SCRIBE","DISCS","PAINTBRUSHES"]
const WEAPON_GROUPS := [[],["dagger"],["sword_shield","sword","curved_sword","katana"],["axe","hammer","greatsword"],["spear","halberd","scythe"],["twin_blades","fist"],["staff","chime","whip"],["scribe"],["disc","dual_disc"],["paintbrush"]]

static func weapon_matches(family: String, index: int) -> bool:
	return index==0 or (index>0 and index<WEAPON_GROUPS.size() and family in WEAPON_GROUPS[index])

static func choices(category: StringName) -> Array:
	match category:
		&"weapons": return WEAPON_NAMES
		&"cosmetics": return ["ALL","BODY","HEAD","HANDS","LEGS","PATTERNS"]
		&"consumables": return ["ALL","HEALTH GLYPHS","SHIELD GLYPHS","RESPAWN GLYPHS","OTHER"]
		&"misc": return ["ALL","RINGS","OTHER"]
	return ["ALL"]

static func family(definition: Resource) -> String:
	return String(definition.custom_properties.get("family",definition.item_type_id))

static func matches(definition: Resource, index: int) -> bool:
	if definition==null: return false
	if index==0: return true
	if index<0 or index>=choices(definition.category).size(): return false
	var properties: Dictionary = definition.custom_properties
	match definition.category:
		&"weapons": return weapon_matches(family(definition),index)
		&"cosmetics":
			if index==5: return not definition.is_equippable
			return definition.is_equippable and properties.get("cosmetic_slot","")==["","body","head","hands","legs"][index]
		&"consumables":
			var kind := 1 if properties.has("healing") and not properties.get("civilian_food",false) else 2 if properties.has("shield_capacity") else 3 if properties.has("respawn_kind") else 4
			return kind==index
		&"misc":
			var ring: bool = family(definition)=="ring" or properties.get("cosmetic_slot")=="ring"
			return ring if index==1 else not ring
	return false

static func searchable_text(definition: Resource) -> String:
	return (String(definition.display_name)+" "+Types.label(definition)+" "+family(definition).replace("_"," ")).to_lower()
