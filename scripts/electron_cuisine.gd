extends RefCounted
## Food quality is an item property, never player progression or eating XP.
const RARITIES := {"common":0,"civic":0,"uncommon":1,"rare":2,"epic":3,"legendary":4,"unique":5}
const DEFAULTS := {"hp_cap":350.0,"shield_cap":1000.0,"quality_min":.5,"quality_max":2.0,"complexity_factor":.06,"rarity_factor":.12}

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high

static func effects(properties: Dictionary,item_properties: Dictionary = {},settings: Dictionary = DEFAULTS) -> Dictionary:
	if not properties.get("civilian_food",false) or properties.get("cuisine_kind","food") not in ["food","drink","dessert"]: return {}
	for key: String in DEFAULTS:
		if not _number(settings.get(key),0,1000): return {}
	if settings.quality_min<.1 or settings.quality_max>4 or settings.quality_min>settings.quality_max or settings.hp_cap<1 or settings.shield_cap<250: return {}
	var complexity_value: Variant=properties.get("complexity",1)
	if not _number(complexity_value,1,10): return {}
	var complexity:=float(complexity_value)
	var base_value: Variant=properties.get("base_restoration",properties.get("healing",0))
	if not _number(base_value,.1,1000) or not _number(properties.get("consumption_duration",2.0),.1,60): return {}
	var base:=float(base_value)
	var quality_value: Variant=item_properties.get("quality",item_properties.get("food_quality",1.0))
	var quality:=clampf(float(quality_value),float(settings.quality_min),float(settings.quality_max)) if (quality_value is float or quality_value is int) and is_finite(float(quality_value)) else 1.0
	var rarity:=String(properties.get("rarity","Common")).to_lower()
	var rank:=int(RARITIES.get(rarity,0))
	var actual_rarity: Variant=item_properties.get("rarity",rarity)
	if actual_rarity is String or actual_rarity is StringName:
		var requested:=String(actual_rarity).to_lower()
		if RARITIES.has(requested): rarity=requested; rank=int(RARITIES[requested])
	elif (actual_rarity is int or actual_rarity is float) and is_finite(float(actual_rarity)):
		rank=clampi(int(actual_rarity),0,5)
		rarity=["common","uncommon","rare","epic","legendary","unique"][rank]
	var multiplier:=clampf((1.0+float(settings.complexity_factor)*(complexity-1)+float(settings.rarity_factor)*rank)*quality,.1,4)
	var amount:=base*multiplier
	var drink: bool=properties.get("cuisine_kind","food")=="drink"
	var score:=complexity+rank*2+(quality-1)*2
	var capacity:=250.0 if score<4 else 500.0 if score<8 else 1000.0
	capacity=minf(capacity,float(settings.shield_cap))
	# Shield persistence supports the existing three canonical capacities.
	var tier:="heavy" if capacity>=1000 else "medium" if capacity>=500 else "light"
	capacity={"light":250.0,"medium":500.0,"heavy":1000.0}[tier]
	return {"duration":float(properties.get("consumption_duration",2.0)),"healing":0.0 if drink else minf(float(settings.hp_cap),amount),"hp_restore":0.0 if drink else minf(float(settings.hp_cap),amount),"shield_restore":minf(capacity,amount) if drink else 0.0,"shield_capacity":capacity if drink else 0.0,"shield_tier":tier if drink else "","quality":quality,"complexity":complexity,"rarity":rarity,"cuisine_kind":String(properties.get("cuisine_kind","food"))}
