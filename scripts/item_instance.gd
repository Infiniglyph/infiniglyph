extends Resource
## One transferable item/stack identity. Serialization never embeds Resources.
@export var item_type_id: StringName = &""
@export var instance_id := ""
@export_range(1,999999,1) var quantity := 1
@export_range(0,9999,1) var upgrade_level := 0
@export var custom_properties: Dictionary = {}
@export var owner_id := ""

static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func valid_text(value: Variant, allow_empty: bool = false, maximum: int = 128) -> bool:
	return (value is String or value is StringName) and (allow_empty or not String(value).is_empty()) and String(value).length()<=maximum

static func whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=minimum and float(value)<=maximum

static func json_value(value: Variant, depth: int = 0) -> bool:
	if depth>8: return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL: return true
		TYPE_INT: return value>=-9007199254740991 and value<=9007199254740991 # Exact JSON integer range.
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING,TYPE_STRING_NAME: return String(value).length()<=4096
		TYPE_ARRAY:
			if value.size()>256: return false
			for entry: Variant in value:
				if not json_value(entry,depth+1): return false
			return true
		TYPE_DICTIONARY:
			if value.size()>256: return false
			for key: Variant in value:
				if not valid_text(key,false,128) or not json_value(value[key],depth+1): return false
			return true
	return false

static func json_copy(value: Variant) -> Variant:
	# Godot's JSON reader represents every number as a float. Canonicalize
	# integral values so nested saved properties still match acquired stacks.
	match typeof(value):
		TYPE_FLOAT:
			return int(value) if absf(value)<=9007199254740991 and value==floorf(value) else value
		TYPE_STRING_NAME: return String(value)
		TYPE_ARRAY:
			var entries: Array = []
			for entry: Variant in value: entries.append(json_copy(entry))
			return entries
		TYPE_DICTIONARY:
			var entries: Dictionary = {}
			for key: Variant in value: entries[String(key)] = json_copy(value[key])
			return entries
	return value

static func same_properties(a: Variant, b: Variant) -> bool:
	# Compare JSON values without allocating a normalized copy for every
	# candidate stack. Numeric equality survives JSON's int/float conversion.
	if (a is int or a is float) and (b is int or b is float): return float(a)==float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_properties(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not same_properties(a[i],b[i]): return false
		return true
	return a==b

func is_valid() -> bool:
	if not valid_text(item_type_id) or not valid_text(instance_id) or not valid_text(owner_id,true): return false
	if not whole_number(quantity,1,999999) or not whole_number(upgrade_level,0,9999) or not json_value(custom_properties): return false
	# Resolve lazily so catalog factories can construct instances without a
	# circular script preload dependency.
	var catalog: Script = load("res://scripts/item_catalog.gd")
	var definition: Resource = catalog.get_definition(item_type_id)
	return definition != null and quantity<=definition.max_stack

func to_dict() -> Dictionary:
	if not is_valid(): return {}
	return {"item_type_id":String(item_type_id),"instance_id":instance_id,"quantity":quantity,"upgrade_level":upgrade_level,"custom_properties":json_copy(custom_properties),"owner_id":owner_id}

static func from_dict(data: Variant) -> Resource:
	if not data is Dictionary: return null
	for key: String in ["item_type_id","instance_id","quantity","upgrade_level","custom_properties","owner_id"]:
		if not data.has(key): return null
	if not valid_text(data.item_type_id) or not valid_text(data.instance_id) or not valid_text(data.owner_id,true): return null
	if not whole_number(data.quantity,1,999999) or not whole_number(data.upgrade_level,0,9999): return null
	if not data.custom_properties is Dictionary or not json_value(data.custom_properties): return null
	var result: Resource = load("res://scripts/item_instance.gd").new()
	result.item_type_id = StringName(data.item_type_id)
	result.instance_id = String(data.instance_id)
	result.quantity = int(data.quantity)
	result.upgrade_level = int(data.upgrade_level)
	result.custom_properties = json_copy(data.custom_properties)
	result.owner_id = String(data.owner_id)
	return result if result.is_valid() else null
