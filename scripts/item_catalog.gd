extends RefCounted
## Shared native catalog. New entries need no inventory or loot-controller code.
const Definition = preload("res://scripts/item_definition.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Weapons = preload("res://scripts/weapon_library.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
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
	_add(&"light_shard","Light Shard","A compact fragment of stable light, prized as a material.",&"materials",99)
	_add(&"health_glyph","Health Glyph","Restore 350 HP. Hold RT and press B, or press H. Consumed only when injured.",&"consumables",99,false,true,true,{"healing":350})
	_add(&"signal_tonic","Signal Tonic","An amber pulse sealed in glass, awaiting a purpose.",&"consumables",20)
	_add(&"civic_key","Civic Access Glyph","A civic credential keyed to its current bearer.",&"key_items",1,false,false,false)
	_add(&"cyan_mantle","Cyan Mantle Pattern","An encoded weave of cyan light.",&"cosmetics",1)
	_add(&"eternal_scribe_robes","Eternal Scribe Robes","Dark open-front robes from The Infinite Library, edged in silver with a scholar's hood and living mathematical inscriptions. Cosmetic clothing; equip in Body.",&"cosmetics",1,true,true,true,{"cosmetic_slot":"body","robe_id":"eternal_scribe"})
	_add(&"echo_fragment","Echo Fragment","A preserved city signal, faintly repeating an unfamiliar melody.",&"misc",50)
	for entry: Dictionary in Equipment.all():
		var properties := {"equipment_id":entry.id,"family":entry.family,"rarity":entry.rarity,"glyph_coin_value":entry.value,"acquisition":entry.acquisition,"effects":entry.effects}
		if entry.category=="weapons": properties.weapon_slot = entry.slot
		else: properties.cosmetic_slot = entry.slot
		_add(StringName(entry.id),entry.name,entry.description,StringName(entry.category),1,true,true,true,properties)

static func get_definition(id: StringName) -> Resource:
	_prepare()
	return definitions.get(id)

static func all() -> Array:
	_prepare()
	return definitions.values()

static func create(id: StringName, quantity: int = 1) -> Resource:
	var definition: Resource = get_definition(id)
	if definition == null or quantity<1 or quantity>definition.max_stack: return null
	var item := Instance.new()
	item.item_type_id = id
	item.instance_id = Instance.new_id()
	item.quantity = quantity
	return item
