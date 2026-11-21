extends RefCounted
## Stable per-instance rolls: name selects an affinity, rarity sets its budget.
## No rerolls on loading/trading/equipping and no inventory schema migration.
static func for_item(item: Resource,definition: Resource) -> Dictionary:
	if item==null or definition==null or definition.custom_properties.get("cosmetic_slot")!="ring": return {}
	var rank: float={"common":1,"crafted":1.5,"uncommon":2,"rare":3,"epic":4,"legendary":5,"unique":6}.get(String(definition.custom_properties.get("rarity","common")).to_lower(),1)
	var seed_value:=absi((String(item.item_type_id)+item.instance_id).hash())
	var roll:=.85+float(seed_value%301)/1000.0
	var name: String=definition.display_name.to_lower()
	var stat: String=["hp","damage","defense"][seed_value%3]
	for word in ["soul","hearth","life","promise","tomb"]:
		if word in name: stat="hp"; break
	for word in ["fang","claw","sekhmet","blade","fury"]:
		if word in name: stat="damage"; break
	for word in ["ward","sobek","guard","bulwark","oath"]:
		if word in name: stat="defense"; break
	var budget:={"hp":25.0,"damage":.0125,"defense":.006}
	var result:={stat:snappedf(float(budget[stat])*rank*roll,1 if stat=="hp" else .001)}
	if rank>=3:
		var second: String=["hp","damage","defense"][(seed_value/301)%3]
		if second==stat: second="hp" if stat!="hp" else "damage"
		result[second]=snappedf(float(budget[second])*rank*.4,1 if second=="hp" else .001)
	return result
static func total(inventory: Node) -> Dictionary:
	var result:={"hp":0.0,"damage":0.0,"defense":0.0}
	if not is_instance_valid(inventory): return result
	var catalog: Script=load("res://scripts/item_catalog.gd")
	for slot: StringName in [&"ring1",&"ring2"]:
		var item: Resource=inventory.equipped_item(slot)
		if item==null: continue
		var effects:=for_item(item,catalog.get_definition(item.item_type_id))
		for key: String in effects: result[key]+=float(effects[key])
	return result
static func describe(item: Resource,definition: Resource) -> String:
	var effects:=for_item(item,definition)
	var lines: Array[String]=[]
	for stat: String in effects:
		lines.append("+%d maximum HP" % effects[stat] if stat=="hp" else "+%.1f%% damage" % (effects[stat]*100) if stat=="damage" else "%.1f%% incoming damage reduction" % (effects[stat]*100))
	return "\n".join(lines)
