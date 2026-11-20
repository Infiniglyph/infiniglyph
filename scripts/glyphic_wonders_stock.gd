extends RefCounted
## Persistent clock-driven offers over the shared catalog, never item ownership.
const Catalog = preload("res://scripts/item_catalog.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const Instance = preload("res://scripts/item_instance.gd")
const PERMANENT: Array[String] = ["health_glyph","shield_glyph_light","shield_glyph_medium","shield_glyph_heavy","respawn_glyph","home_respawn_glyph"]
## Older version-one saves legitimately included these in the rotating pool.
## Keep their saved selection auditable until the next scheduled rotation;
## presentation moves them to the counter immediately without rerolling wares.
const FORMER_ROTATING: Array[String] = ["respawn_glyph","home_respawn_glyph"]
const MAX_PRICE := 1000000
const MAX_POOL := 16384
const GLYPH_PRICES := {"health_glyph":20,"shield_glyph_light":25,"shield_glyph_medium":45,"shield_glyph_heavy":75,"respawn_glyph":15,"home_respawn_glyph":15}
const CATEGORY_PRICES := {"weapons":80,"cosmetics":40,"materials":12,"consumables":15,"misc":20,"furniture":60}
var seed := 0
var cycle := -1
var next_rotation := 0.0
var config := {"day_seconds":86400.0,"interval_days":7,"pedestal_count":12}
var _pool: Array[String] = []
var _selection: Array[String] = []

static func _metadata_allows(properties: Dictionary) -> bool:
	for flag: String in ["developer_only","dev_only","debug_only","test_only","non_purchasable","not_for_sale"]:
		if properties.get(flag,false)==true: return false
	for flag: String in ["purchasable","purchaseable","retail","retail_enabled","shop_eligible"]:
		if properties.has(flag) and properties[flag]==false: return false
	var acquisition:=String(properties.get("acquisition","")).to_lower().replace("-"," ")
	for phrase: String in ["developer only","dev only","debug only","test only","internal only"]:
		if phrase in acquisition: return false
	return true

static func eligible(definition: Resource) -> bool:
	if definition==null or not Instance.valid_text(definition.item_type_id,false,128) or definition.display_name.is_empty(): return false
	if not CATEGORY_PRICES.has(String(definition.category)): return false
	if not definition.is_tradeable or not definition.is_droppable or definition.category==&"key_items" or Equipment.is_retired(definition.item_type_id): return false
	if not Instance.whole_number(definition.max_stack,1,999999) or not _metadata_allows(definition.custom_properties): return false
	var equipment:=Equipment.get_item(definition.item_type_id)
	return equipment.is_empty() or _metadata_allows(equipment)

static func price_for(type: StringName) -> int:
	var definition: Resource=Catalog.get_definition(type)
	if not eligible(definition): return 0
	for key: String in ["price","glyph_coin_value"]:
		var amount: Variant=definition.custom_properties.get(key)
		if Instance.whole_number(amount,1,MAX_PRICE): return int(amount)
	# Existing developer catalog entries often have value0 or no retail price.
	# These explicit retail defaults never alter the shared item definitions.
	return int(GLYPH_PRICES.get(String(type),CATEGORY_PRICES.get(String(definition.category),20)))

static func eligible_ids() -> Array[String]:
	var result: Array[String]=[]
	for definition: Resource in Catalog.all():
		var id:=String(definition.item_type_id)
		if id not in PERMANENT and eligible(definition): result.append(id)
	result.sort()
	return result

static func _settings(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=3: return {}
	if not (input.get("day_seconds") is float or input.get("day_seconds") is int) or not is_finite(float(input.day_seconds)) or input.day_seconds<.000001 or input.day_seconds>1e9: return {}
	if not Instance.whole_number(input.get("interval_days"),1,3650) or not Instance.whole_number(input.get("pedestal_count"),1,64): return {}
	return {"day_seconds":float(input.day_seconds),"interval_days":int(input.interval_days),"pedestal_count":int(input.pedestal_count)}

static func _choose(pool: Array[String],stock_seed: int,stock_cycle: int,count: int) -> Array[String]:
	var choices: Array[String]=pool.duplicate()
	# A bounded integer shuffle is independent of global RNG state and visits.
	var state: int=(stock_seed ^ (stock_cycle*1000003)) & 0x7fffffff
	for i in range(choices.size()-1,0,-1):
		state=(state*1103515245+12345) & 0x7fffffff
		var other:=state % (i+1)
		var previous:=choices[i]
		choices[i]=choices[other]
		choices[other]=previous
	choices.resize(mini(count,choices.size()))
	return choices

func configure(stock_seed: int,day_seconds: float = 86400.0,interval_days: int = 7,pedestal_count: int = 12,now: float = 0.0) -> bool:
	if cycle>=0 or not Instance.whole_number(stock_seed,0,2147483647) or not is_finite(now) or now<0 or now>1e15: return false
	var settings:=_settings({"day_seconds":day_seconds,"interval_days":interval_days,"pedestal_count":pedestal_count})
	if settings.is_empty(): return false
	var target:=floori(now/(float(settings.day_seconds)*float(settings.interval_days)))
	if target>1000000000: return false
	seed=stock_seed
	config=settings
	return advance(now)

func advance(now: float) -> bool:
	if not is_finite(now) or now<0 or now>1e15: return false
	if _settings(config).is_empty(): return false
	var interval:=float(config.day_seconds)*float(config.interval_days)
	var target:=floori(now/interval)
	if target<=cycle or target>1000000000: return false
	var pool:=eligible_ids()
	if pool.is_empty() or pool.size()>MAX_POOL: return false
	_pool=pool
	_selection=_choose(_pool,seed,target,int(config.pedestal_count))
	cycle=target
	next_rotation=(cycle+1)*interval
	return true

func permanent_ids() -> Array[String]: return PERMANENT.duplicate()
func rotating_ids() -> Array[String]:
	var result: Array[String]=[]
	for id: String in _selection:
		if id not in PERMANENT: result.append(id)
	return result

func offer(type: StringName) -> Dictionary:
	if cycle<0: return {}
	var id:=String(type)
	var permanent:=id in PERMANENT
	var slot:=_selection.find(id)
	if not permanent and slot<0: return {}
	var price:=price_for(type)
	if price<=0: return {}
	return {"type_id":id,"price":price,"cycle":cycle,"permanent":permanent,"slot":-1 if permanent else slot}

func offers() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id: String in PERMANENT+rotating_ids():
		var current:=offer(StringName(id))
		if not current.is_empty(): result.append(current)
	return result

func serialize() -> Dictionary:
	if cycle<0: return {}
	return {"version":1,"seed":seed,"cycle":cycle,"next_rotation":next_rotation,"config":config.duplicate(),"pool":_pool.duplicate(),"selection":_selection.duplicate()}

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=7 or not Instance.whole_number(input.get("version"),1,1) or not Instance.whole_number(input.get("seed"),0,2147483647) or not Instance.whole_number(input.get("cycle"),0,1000000000): return {}
	var settings:=_settings(input.get("config"))
	if settings.is_empty() or not input.get("pool") is Array or input.pool.is_empty() or input.pool.size()>MAX_POOL or not input.get("selection") is Array: return {}
	var pool: Array[String]=[]
	var seen: Dictionary={}
	for id: Variant in input.pool:
		if not id is String or seen.has(id) or id in PERMANENT and id not in FORMER_ROTATING or not eligible(Catalog.get_definition(StringName(id))): return {}
		pool.append(id)
		seen[id]=true
	var sorted: Array[String]=pool.duplicate()
	sorted.sort()
	if sorted!=pool: return {}
	var expected:=_choose(pool,int(input.seed),int(input.cycle),int(settings.pedestal_count))
	if input.selection!=expected: return {}
	var next: float=(int(input.cycle)+1)*float(settings.day_seconds)*float(settings.interval_days)
	if not (input.get("next_rotation") is float or input.get("next_rotation") is int) or not is_finite(float(input.next_rotation)) or absf(float(input.next_rotation)-next)>maxf(.000001,absf(next)*1e-12): return {}
	return {"version":1,"seed":int(input.seed),"cycle":int(input.cycle),"next_rotation":next,"config":settings,"pool":pool,"selection":expected}

func restore(input: Variant) -> bool:
	var decoded:=validate(input)
	if decoded.is_empty(): return false
	seed=decoded.seed
	cycle=decoded.cycle
	next_rotation=decoded.next_rotation
	config=decoded.config
	_pool.assign(decoded.pool)
	_selection.assign(decoded.selection)
	return true
