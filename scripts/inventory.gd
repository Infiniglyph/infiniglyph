extends Node
## Event-driven owned data. Transfers are validated by the session loot service.
const Catalog = preload("res://scripts/item_catalog.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const RespawnData = preload("res://scripts/respawn_glyph_data.gd")
const Shields = preload("res://scripts/shield_glyphs.gd")
const SLOTS: Array[StringName] = [&"down",&"left",&"right",&"up"]
const EQUIPMENT_SLOTS: Array[StringName] = [&"down",&"left",&"right",&"up",&"body",&"head",&"hands",&"legs",&"ring1",&"ring2"]
const MAX_ITEMS := 4096
signal changed
signal equipment_changed
@export var owner_id := "local"
var capture_cache_enabled:=false
var _capture_dirty:=true
var _capture_cache: Dictionary={}

func _init() -> void:
	changed.connect(_invalidate_capture)

func _invalidate_capture() -> void: _capture_dirty=true

var actor: Node3D
var items: Dictionary = {}
var equipment: Dictionary = {}
var _seeded := false
var starter_glyphs_granted := false
var shield_state: Dictionary = {}
var respawn_points: Dictionary = {}
var boss_reward_claims: Dictionary = {}

static func valid_boss_claims(value: Variant) -> bool:
	if not value is Dictionary or value.size()>1: return false
	for key in value:
		if key!="ahkmet_lorai" or not value[key] is bool or not value[key]: return false
	return true

func count_type(type: StringName) -> int:
	var total := 0
	for item: Resource in items.values():
		if item.item_type_id == type and item.owner_id == owner_id: total += item.quantity
	return total

func introduce_health_glyphs() -> void:
	# One migration grant for existing saves as well as new players, never a refill.
	if starter_glyphs_granted: return
	starter_glyphs_granted = true # Claim before changed signals can reenter.
	if not add_item(Catalog.create(&"health_glyph",3)): starter_glyphs_granted = false

func seed_starter() -> void:
	# A valid empty save represents real losses, never a reason to mint gear.
	if _seeded: return
	_seeded = true
	if not items.is_empty() or not equipment.is_empty(): return
	for slot: StringName in SLOTS:
		var id: StringName = {&"down":&"sword_shield",&"left":&"spear",&"right":&"katana",&"up":&"twin_blades"}[slot]
		var item: Resource = Catalog.create(id)
		item.owner_id = owner_id
		items[item.instance_id] = item
		equipment[slot] = item.instance_id
	equipment_changed.emit()
	changed.emit()

func get_item(iid: String) -> Resource:
	return items.get(iid)

func add_item(item: Resource) -> bool:
	if item == null or not item.has_method("is_valid") or not item.is_valid() or not Instance.valid_text(owner_id): return false
	if Equipment.is_retired(item.item_type_id) or items.has(item.instance_id) or (not item.owner_id.is_empty() and item.owner_id != owner_id): return false
	var definition: Resource = Catalog.get_definition(item.item_type_id)
	var remaining: int = item.quantity
	var merges: Array[Dictionary] = []
	if definition.max_stack>1:
		for existing: Resource in items.values():
			if existing.item_type_id != item.item_type_id or existing.upgrade_level != item.upgrade_level or not Instance.same_properties(existing.custom_properties,item.custom_properties): continue
			if not existing.is_valid() or existing.owner_id != owner_id: return false
			var amount := mini(remaining,definition.max_stack-existing.quantity)
			if amount>0:
				merges.append({"item":existing,"amount":amount})
				remaining -= amount
			if remaining == 0: break
	if remaining>0 and items.size()>=MAX_ITEMS: return false
	for merge: Dictionary in merges: merge.item.quantity += merge.amount
	# A fully absorbed stack is consumed, so the same Resource cannot be
	# accidentally submitted twice. Unique equipment always keeps its ID.
	item.quantity = remaining
	item.owner_id = owner_id
	if remaining>0: items[item.instance_id] = item
	changed.emit()
	return true

func take_item(iid: String, qty: int = 1) -> Resource:
	var item: Resource = get_item(iid)
	if item == null or not item.is_valid() or item.owner_id != owner_id or qty<1 or qty>item.quantity: return null
	var result: Resource
	if qty == item.quantity:
		result = item
	else:
		result = Catalog.create(item.item_type_id,qty)
		result.upgrade_level = item.upgrade_level
		result.custom_properties = item.custom_properties.duplicate(true)
	var unequipped := false
	for slot: StringName in equipment.keys():
		if equipment[slot] == iid:
			equipment.erase(slot)
			unequipped = true
	if qty == item.quantity: items.erase(iid)
	else: item.quantity -= qty
	result.owner_id = ""
	if unequipped: equipment_changed.emit()
	changed.emit()
	return result

func equipped_item(slot: StringName) -> Resource:
	return get_item(equipment.get(slot,""))

func assign(slot: StringName, iid: String) -> bool:
	var item: Resource = get_item(iid)
	if item == null or not item.is_valid() or item.owner_id != owner_id: return false
	var definition: Resource = Catalog.get_definition(item.item_type_id)
	if not fits_slot(definition,slot): return false
	if equipment.get(slot,"") == iid: return true
	for existing: StringName in equipment.keys():
		if equipment[existing] == iid: equipment.erase(existing)
	equipment[slot] = iid
	equipment_changed.emit()
	changed.emit()
	return true

func unequip(slot: StringName) -> bool:
	if not slot in EQUIPMENT_SLOTS or not equipment.has(slot): return false
	equipment.erase(slot)
	equipment_changed.emit()
	changed.emit()
	return true

static func fits_slot(definition: Resource, slot: StringName) -> bool:
	if definition==null or not definition.is_equippable: return false
	if slot in [&"body",&"head",&"hands",&"legs"]: return definition.category==&"cosmetics" and definition.custom_properties.get("cosmetic_slot","")==String(slot)
	if slot in [&"ring1",&"ring2"]: return definition.custom_properties.get("cosmetic_slot","")=="ring"
	return slot in SLOTS and definition.category==&"weapons" and StringName(definition.custom_properties.get("weapon_slot","")) in SLOTS

func weapon_slot(slot: StringName) -> StringName:
	var item: Resource = equipped_item(slot)
	if item == null or item.owner_id != owner_id: return &""
	var definition: Resource = Catalog.get_definition(item.item_type_id)
	return StringName(definition.custom_properties.get("weapon_slot","")) if definition != null else &""

func eligible_equipped() -> Array:
	var result: Array[String] = []
	for slot: StringName in EQUIPMENT_SLOTS:
		var item: Resource = equipped_item(slot)
		if item == null or not item.is_valid() or item.owner_id != owner_id or result.has(item.instance_id): continue
		var definition: Resource = Catalog.get_definition(item.item_type_id)
		if definition.is_equippable and definition.is_droppable and definition.is_tradeable: result.append(item.instance_id)
	return result

func capture_values() -> Dictionary:
	if capture_cache_enabled and not _capture_dirty: return _capture_cache
	# Checkpoint-only ownership transfer. Defer catalog lookup, JSON
	# normalization and validation of every item to the private save worker.
	# Transactions and restores continue using the strict serialize() boundary.
	var entries: Array[Dictionary]=[]
	for iid: String in items:
		var item: Resource=items[iid]
		if item==null or item.instance_id!=iid or item.owner_id!=owner_id: return {}
		entries.append({"item_type_id":String(item.item_type_id),"instance_id":String(item.instance_id),"quantity":item.quantity,"upgrade_level":item.upgrade_level,"custom_properties":item.custom_properties.duplicate(true),"owner_id":String(item.owner_id)})
	var assignments: Dictionary={}
	for slot: StringName in equipment: assignments[String(slot)]=equipment[slot]
	var result:={"version":1,"owner_id":owner_id,"items":entries,"equipment":assignments,"starter_glyphs_granted":starter_glyphs_granted}
	if not shield_state.is_empty(): result.shield_state=shield_state.duplicate()
	if not respawn_points.is_empty(): result.respawn_points=respawn_points.duplicate(true)
	if not boss_reward_claims.is_empty(): result.boss_reward_claims=boss_reward_claims.duplicate()
	if capture_cache_enabled:
		_capture_cache=result
		_capture_dirty=false
	return result

func serialize() -> Dictionary:
	if not Instance.valid_text(owner_id) or items.size()>MAX_ITEMS: return {}
	var entries: Array[Dictionary] = []
	for iid: String in items:
		var item: Resource = items[iid]
		if item == null or item.instance_id != iid or item.owner_id != owner_id: return {}
		var encoded: Dictionary = item.to_dict()
		if encoded.is_empty(): return {}
		entries.append(encoded)
	var assignments: Dictionary = {}
	for slot: StringName in equipment:
		assignments[String(slot)] = equipment[slot]
	var result: Dictionary={"version":1,"owner_id":owner_id,"items":entries,"equipment":assignments,"starter_glyphs_granted":starter_glyphs_granted}
	if not shield_state.is_empty(): result.shield_state=shield_state.duplicate()
	if not RespawnData.valid(respawn_points): return {}
	if not respawn_points.is_empty(): result.respawn_points=respawn_points.duplicate(true)
	if not valid_boss_claims(boss_reward_claims): return {}
	if not boss_reward_claims.is_empty(): result.boss_reward_claims=boss_reward_claims.duplicate()
	return result

func restore(data: Variant) -> bool:
	if not data is Dictionary or not Instance.whole_number(data.get("version"),1,1): return false
	if not Instance.valid_text(data.get("owner_id")) or not data.get("items") is Array or not data.get("equipment") is Dictionary or data.items.size()>MAX_ITEMS: return false
	if data.has("starter_glyphs_granted") and not data.starter_glyphs_granted is bool: return false
	if not Shields.valid(data.get("shield_state",{})): return false
	if not RespawnData.valid(data.get("respawn_points",{})): return false
	if not valid_boss_claims(data.get("boss_reward_claims",{})): return false
	for record: Dictionary in data.get("respawn_points",{}).values():
		if record.location!="overworld" and record.location!="pyramid/"+String(data.owner_id): return false
	var restored: Dictionary = {}
	for entry: Variant in data.items:
		var item: Resource = Instance.from_dict(entry)
		if item == null or item.owner_id != String(data.owner_id) or restored.has(item.instance_id): return false
		restored[item.instance_id] = item
	var assignments: Dictionary = {}
	var assigned: Dictionary = {}
	var corrected_slots: Dictionary = {}
	for key: Variant in data.equipment:
		if not Instance.valid_text(key): return false
		var slot := StringName(key)
		var iid: Variant = data.equipment[key]
		if not (slot in EQUIPMENT_SLOTS or slot==&"shield") or not Instance.valid_text(iid) or not restored.has(String(iid)) or assigned.has(String(iid)): return false
		var item: Resource = restored[String(iid)]
		var definition: Resource = Catalog.get_definition(item.item_type_id)
		if Equipment.is_retired(item.item_type_id):
			var family: String = Equipment.retired[String(item.item_type_id)]
			if not ((family=="shield" and slot==&"shield") or (family in ["talisman","bow","crossbow"] and slot in SLOTS)): return false
			assigned[String(iid)] = true
			continue
		if not fits_slot(definition,slot):
			# Six portrait labels were previously classified as Body. Preserve
			# their ownership when loading that checkpoint and move the worn piece
			# into its corrected slot if free. All other invalid slots still fail.
			if definition.custom_properties.get("legacy_cosmetic_slot","")!=String(slot): return false
			var corrected := StringName(definition.custom_properties.get("cosmetic_slot",""))
			if not fits_slot(definition,corrected): return false
			corrected_slots[corrected] = String(iid)
			assigned[String(iid)] = true
			continue
		assignments[slot] = String(iid)
		assigned[String(iid)] = true
	for slot: StringName in corrected_slots:
		if not assignments.has(slot): assignments[slot] = corrected_slots[slot]
	for iid: String in restored.keys():
		if Equipment.is_retired(restored[iid].item_type_id): restored.erase(iid)
	owner_id = String(data.owner_id)
	items = restored
	equipment = assignments
	_seeded = true
	starter_glyphs_granted = data.get("starter_glyphs_granted",false)
	shield_state = data.get("shield_state",{}).duplicate()
	respawn_points = data.get("respawn_points",{}).duplicate(true)
	boss_reward_claims = data.get("boss_reward_claims",{}).duplicate()
	equipment_changed.emit()
	changed.emit()
	return true
