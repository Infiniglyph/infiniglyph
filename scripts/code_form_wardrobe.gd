extends RefCounted
## Real owned equipment determines status. Issuance is a one-time migration,
## while subsequent wants spend existing coins through normal commerce.
const Catalog=preload("res://scripts/item_catalog.gd")
const Equipment=preload("res://scripts/equipment_database.gd")
const STARTERS:={"body":"eq_a_11607e48","head":"eq_a_1365c040","hands":"eq_a_11a3a5b0","legs":"eq_a_1166a098"}
const LEGACY_STARTERS:={"body":"eq_a_114fb568","head":"eq_a_11c9c380","hands":"eq_a_129f6ad0","legs":"eq_a_11ab4ab8"}
const UNIFORM:={"body":"eq_a_14c4b7e8","head":"eq_a_13750280","hands":"eq_a_portrait_03451","legs":"eq_a_13c15978"}

static func issue(store: Node,state: Dictionary,officer: bool=false) -> bool:
	var key:="uniform_issued" if officer else "attire_issued"
	if state.get(key,false): return _migrate_starters(store) if not officer else false
	var outfit: Dictionary=UNIFORM if officer else STARTERS
	# Prepare before mutation so catalog/capacity failure cannot grant half a set.
	var additions: Dictionary={}
	for slot: String in outfit:
		if not officer and store.equipped_item(StringName(slot))!=null: continue
		var item: Resource=Catalog.create(StringName(outfit[slot]))
		if item==null: return false
		item.custom_properties={"issued_to":String(store.owner_id),"issue":"dark_box_uniform" if officer else "civic_starter"}
		additions[slot]=item
	if store.items.size()+additions.size()>store.MAX_ITEMS: return false
	for slot: String in additions:
		if not store.add_item(additions[slot]): return false
		store.assign(StringName(slot),additions[slot].instance_id)
	state[key]=true
	return true

static func _migrate_starters(store: Node) -> bool:
	# Exchange only an owner's original issue. Sold/lost pieces are not refilled,
	# purchased Braided items keep their identity, and upgraded outfits stay worn.
	var changed:=false
	for item: Resource in store.items.values():
		if item.owner_id!=store.owner_id or item.custom_properties.get("issued_to")!=store.owner_id or item.custom_properties.get("issue")!="braided_starter": continue
		for slot: String in LEGACY_STARTERS:
			if item.item_type_id!=StringName(LEGACY_STARTERS[slot]): continue
			var replacement: Resource=Catalog.create(StringName(STARTERS[slot]))
			if replacement==null: continue
			replacement.upgrade_level=item.upgrade_level
			replacement.custom_properties=item.custom_properties.duplicate(true)
			replacement.custom_properties.issue="civic_starter"
			var worn: bool=store.equipped_item(StringName(slot))==item
			var previous: Resource=store.take_item(item.instance_id)
			if previous==null: continue
			if not store.add_item(replacement):
				store.add_item(previous)
				if worn: store.assign(StringName(slot),previous.instance_id)
				continue
			if worn: store.assign(StringName(slot),replacement.instance_id)
			changed=true
	return changed

static func item_drip(type: StringName,properties: Dictionary={}) -> float:
	var definition: Resource=Catalog.get_definition(type)
	if definition==null: return 0
	var rarity:=String(definition.custom_properties.get("rarity","Common")).to_lower()
	var rank: float={"common":1,"crafted":1.5,"uncommon":2,"rare":3,"epic":4,"legendary":5,"unique":6}.get(rarity,1)
	var value:=float(definition.custom_properties.get("glyph_coin_value",definition.custom_properties.get("price",10)))
	var complexity:=float(definition.custom_properties.get("complexity",1))
	var raw: Variant=properties.get("quality",1)
	var quality:=clampf(float(raw),.5,2) if (raw is int or raw is float) and is_finite(float(raw)) else 1.0
	return clampf((rank*7+sqrt(maxf(0,value))*.7+complexity)*quality,1,100)

static func drip(store: Node) -> int:
	var total:=0.0
	for slot: StringName in [&"body",&"head",&"hands",&"legs"]:
		var item: Resource=store.equipped_item(slot)
		if item!=null: total+=item_drip(item.item_type_id,item.custom_properties)
	return roundi(total/4.0)

static func home_drip(row: Dictionary) -> int:
	var total:=0.0
	for placement: Dictionary in row.get("placements",{}).values():
		total+=item_drip(StringName(placement.item.item_type_id),placement.item.get("custom_properties",{}))*.35
	return roundi(clampf(total,0,100))

static func upgrade_slot(store: Node,type: StringName,id: String,turn: int) -> StringName:
	var entry:=Equipment.get_item(type)
	if entry.get("category")!="cosmetics" or entry.get("slot") not in ["body","head","hands","legs"]: return &""
	var slot:=StringName(entry.slot)
	var current: Resource=store.equipped_item(slot)
	if current==null: return slot
	if current.item_type_id==type: return &""
	# People also seek a different look; stable identity/turn variation prevents
	# buying every offered item or treating price as the only expression of taste.
	var improvement:=item_drip(type)-item_drip(current.item_type_id,current.custom_properties)
	return slot if improvement>2 or (improvement>=-2 and posmod((id+String(type)+str(turn)).hash(),9)==0) else &""

static func status(value: int) -> String:
	if value>=75: return "Celebrated"
	if value>=50: return "Distinguished"
	if value>=30: return "Well dressed"
	return "Everyday"
