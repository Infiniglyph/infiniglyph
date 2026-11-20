extends RefCounted
## Shared native catalog. New entries need no inventory or loot-controller code.
const Definition = preload("res://scripts/item_definition.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Weapons = preload("res://scripts/weapon_library.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const CIVIC_GROUPS := {"residential_furniture":"Residential Furniture","commercial_furniture":"Commercial Furniture","functional_equipment":"Functional Equipment","decorations":"Decorations","electron_meals":"Electron Meals","drinks_desserts":"Drinks and Desserts"}
static var definitions: Dictionary = {}

static func _add(id: StringName, title: String, description: String, category: StringName, stack: int = 1, equippable: bool = false, droppable: bool = true, tradeable: bool = true, properties: Dictionary = {}) -> void:
	var definition := Definition.new()
	definition.item_type_id = id
	definition.display_name = title
	definition.description = description
	definition.category = category
	definition.max_stack = stack
	definition.is_equippable = equippable
	definition.is_droppable = droppable
	definition.is_tradeable = tradeable
	definition.custom_properties = properties.duplicate(true)
	definitions[id] = definition

static func _prepare() -> void:
	if not definitions.is_empty(): return
	var descriptions := {&"down":"A luminous longsword paired with a solid shield. Sweep, thrust and hold the line.",&"left":"A long digital spear whose precise point and circular flourishes control distance.",&"right":"A two-handed light blade carried in waki-gamae. Crescent cuts follow committed hip turns.",&"up":"Paired light blades with rapid exchanges, spinning lattice cuts and twin comet arts."}
	for slot: StringName in Weapons.LOADOUTS:
		var weapon: Dictionary = Weapons.loadout(slot)
		var left: Dictionary = Weapons.move(slot,&"attack_left")
		var right: Dictionary = Weapons.move(slot,&"attack_right")
		var specials: Array[Dictionary] = []
		var actions: Array[StringName] = [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
		for i in range(actions.size()):
			var move: Dictionary = Weapons.move(slot,actions[i])
			specials.append({"input":["X / Q","Y / R","RT+X / V+Q","RT+Y / V+R"][i],"name":move.name,"damage":move.damage,"reach":move.reach})
		_add(weapon.id,weapon.name,descriptions[slot],&"weapons",1,true,true,true,{"weapon_slot":String(slot),"guard":weapon.guard,"damage_left":left.damage,"damage_right":right.damage,"reach":maxf(left.reach,right.reach),"specials":specials})
	for tier: String in ["common","uncommon","rare"]:
		var glyph_color: String={"common":"67ffff","uncommon":"c68aff","rare":"ffd16a"}[tier]
		var glyph_scale: float={"common":.48,"uncommon":.72,"rare":1.05}[tier]
		_add(StringName("monster_glyph_"+tier),tier.capitalize()+" Remnant Glyph","A stable glyph left when a defeated creature dissolves. Its size and brilliance reflect the strength of its former bearer. Collectible material.",&"materials",99,false,true,true,{"monster_glyph":true,"rarity":tier.capitalize(),"glyph_color":glyph_color,"glyph_scale":glyph_scale})
	_add(&"bone_shards","Bone Shards","Small golden fragments recovered from a restless skeleton. A material awaiting a new purpose.",&"materials",99)
	_add(&"venom_fang","Venom Fang","A preserved fang recovered from the serpent pit. A collectible material; its future use has yet to be determined.",&"materials",99)
	_add(&"apep_lorai_catalyst","Apep–Lorai Catalyst","A violet-gold crystal left by Lorai, the child of Apep. Two patterns run through its heart, neither erasing the other. A rare collectible material; no crafting power is currently assigned.",&"materials",99,false,true,true,{"rarity":"Legendary","glyph_coin_value":180,"glyph_color":"bc49ff","glyph_scale":1.15})
	_add(&"light_shard","Light Shard","A compact fragment of stable light, prized as a material.",&"materials",99)
	_add(&"health_glyph","Health Glyph","Restore 350 HP. Hold RT and press B, or press H. Consumed only when injured.",&"consumables",99,false,true,true,{"healing":350})
	for tier: String in ["light","medium","heavy"]:
		var points: int={"light":250,"medium":500,"heavy":1000}[tier]
		_add(StringName("shield_glyph_"+tier),tier.capitalize()+" Shield Glyph","Use from Inventory to establish %d shield points. Shields absorb combat damage before HP. Replaces the current shield; does not stack or regenerate. Lost on death." % points,&"consumables",99,false,true,true,{"shield_capacity":points,"shield_tier":tier})
	for kind: String in ["respawn","home"]:
		var id: StringName=&"respawn_glyph" if kind=="respawn" else &"home_respawn_glyph"
		_add(id,"Respawn Glyph" if kind=="respawn" else "Home Respawn Glyph","Place from Inventory on clear ground to bind a reusable reconstruction point. Choose between your Respawn Glyph, Home Respawn Glyph, and default spawn on death. One active point of each kind; placing another replaces the previous point of that kind.",&"consumables",20,false,true,true,{"respawn_kind":kind})
	_add(&"signal_tonic","Signal Tonic","An amber pulse sealed in glass, awaiting a purpose.",&"consumables",20)
	_add(&"electron_meal","Electron Meal","A warm lattice of nourishing charge, prepared at the tavern. Eat over two seconds to recover 60 HP.",&"consumables",20,false,true,true,{"civilian_food":true,"catalog_group":"electron_meals","cuisine_kind":"food","complexity":1,"rarity":"Common","base_restoration":60,"price":8,"consumption_duration":2.0,"healing":60})
	_add(&"electron_draught","Electron Draught","A bright, gently fizzing measure of refined electrons. Drink over three seconds to restore 120 shield points.",&"consumables",20,false,true,true,{"civilian_food":true,"catalog_group":"drinks_desserts","cuisine_kind":"drink","complexity":1,"rarity":"Common","base_restoration":120,"price":12,"consumption_duration":3.0,"shield_restore":120})
	_add(&"civic_key","Civic Access Glyph","A civic credential keyed to its current bearer.",&"key_items",1,false,false,false)
	_add(&"cyan_mantle","Cyan Mantle Pattern","An encoded weave of cyan light.",&"cosmetics",1)
	_add(&"eternal_scribe_robes","Eternal Scribe Robes","Dark open-front robes from The Infinite Library, edged in silver with a scholar's hood and living mathematical inscriptions. Cosmetic clothing; equip in Body.",&"cosmetics",1,true,true,true,{"cosmetic_slot":"body","robe_id":"eternal_scribe"})
	_add(&"echo_fragment","Echo Fragment","A preserved city signal, faintly repeating an unfamiliar melody.",&"misc",50)
	for entry: Dictionary in Equipment.all():
		var properties := {"equipment_id":entry.id,"family":entry.family,"rarity":entry.rarity,"glyph_coin_value":entry.value,"acquisition":entry.acquisition,"effects":entry.effects}
		if entry.category=="weapons": properties.weapon_slot = entry.slot
		else: properties.cosmetic_slot = entry.slot
		if entry.has("legacy_slot"): properties.legacy_cosmetic_slot = entry.legacy_slot
		_add(StringName(entry.id),entry.name,entry.description,StringName(entry.category),1,true,true,true,properties)

	_load_civilization_catalog()

static func _load_civilization_catalog() -> void:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/civilization_items.json"))
	if not data is Dictionary or data.get("version")!=1 or not data.get("items") is Array:
		push_error("Civilization item catalog is invalid.")
		return
	for row: Variant in data.items:
		if not row is Dictionary or not Instance.valid_text(row.get("id")) or definitions.has(StringName(row.id)) or not Instance.valid_text(row.get("name")) or not row.get("properties") is Dictionary or not Instance.json_value(row.properties) or not CIVIC_GROUPS.has(row.properties.get("catalog_group")) or not Instance.whole_number(row.get("stack"),1,99):
			push_error("Civilization item catalog contains an invalid or duplicate entry.")
			continue
		_add(StringName(row.id),String(row.name),String(row.get("description","")),StringName(row.get("category","misc")),int(row.stack),false,true,true,row.properties)

static func civilization_ids(group: String = "") -> Array[StringName]:
	_prepare()
	var result: Array[StringName]=[]
	for definition: Resource in definitions.values():
		if not definition.custom_properties.get("civilization_catalog",false): continue
		if group.is_empty() or definition.custom_properties.get("catalog_group")==group: result.append(definition.item_type_id)
	return result

static func food_ids() -> Array[StringName]:
	_prepare()
	var result: Array[StringName]=[]
	for definition: Resource in definitions.values():
		if definition.custom_properties.get("civilian_food",false): result.append(definition.item_type_id)
	return result

static func get_definition(id: StringName) -> Resource:
	_prepare()
	# Minimal historical definitions validate old saves only. They are absent
	# from all offers and cannot be created or restored into live ownership.
	if Equipment.is_retired(id):
		var family: String = Equipment.retired[String(id)]
		var definition := Definition.new()
		definition.item_type_id = id
		definition.max_stack = 1
		definition.is_equippable = true
		definition.category = &"cosmetics" if family=="shield" else &"weapons"
		definition.custom_properties = {"cosmetic_slot":"shield"} if family=="shield" else {"weapon_slot":"down"}
		return definition
	return definitions.get(id)

static func all() -> Array:
	_prepare()
	return definitions.values()

static func create(id: StringName, quantity: int = 1) -> Resource:
	if Equipment.is_retired(id): return null
	var definition: Resource = get_definition(id)
	if definition == null or quantity<1 or quantity>definition.max_stack: return null
	var item := Instance.new()
	item.item_type_id = id
	item.instance_id = Instance.new_id()
	item.quantity = quantity
	return item
