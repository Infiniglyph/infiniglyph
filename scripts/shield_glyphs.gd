extends RefCounted
## Consumable armor pools, separate from retired cosmetic/equipped shields.
const TIERS := {"light":250.0,"medium":500.0,"heavy":1000.0}
const ITEMS := {&"shield_glyph_light":"light",&"shield_glyph_medium":"medium",&"shield_glyph_heavy":"heavy"}
const PRIORITY: Array[StringName] = [&"shield_glyph_heavy",&"shield_glyph_medium",&"shield_glyph_light"]

static func preferred_item(inventory: Node) -> Resource:
	if not is_instance_valid(inventory): return null
	for type_id in PRIORITY:
		for item: Resource in inventory.items.values():
			if item.item_type_id==type_id and item.owner_id==inventory.owner_id and item.is_valid(): return item
	return null

static func valid(state: Variant) -> bool:
	if not state is Dictionary: return false
	if state.is_empty(): return true
	if state.size()!=2 or state.get("tier","") not in TIERS: return false
	var points: Variant=state.get("points")
	return (points is float or points is int) and is_finite(float(points)) and float(points)>=0 and float(points)<=TIERS[state.tier]

static func capacity(state: Dictionary) -> float: return TIERS.get(state.get("tier",""),0.0)
