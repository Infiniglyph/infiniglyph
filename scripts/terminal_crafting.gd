extends RefCounted
## Shared player/native authority. Callers verify physical terminal access.
## Prepare both inventories off-tree, then publish one synchronous commit.
const Inventory=preload("res://scripts/inventory.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Recipes=preload("res://scripts/crafting_recipes.gd")
const Materials=preload("res://scripts/crafting_materials.gd")
static var busy:=false
static var last_error:=""

static func available(material: String,inventory: Node,storage: Node=null) -> int:
	var id:=Materials.item_id(material)
	return inventory.count_type(id)+(storage.count_type(id) if is_instance_valid(storage) and storage!=inventory else 0)

static func recovery(item: Resource) -> int:
	if item==null: return 0
	var definition: Resource=Catalog.get_definition(item.item_type_id)
	if definition==null or not definition.is_equippable or definition.category not in [&"weapons",&"cosmetics"] or not definition.is_droppable or not definition.is_tradeable: return 0
	var yield_amount:=1
	var costs: Array[int]=[]
	for recipe: Dictionary in Recipes.all():
		if recipe.output_item==String(item.item_type_id): costs.append(int(recipe.ingredients.get("melted_ore",0))/int(recipe.output_quantity))
	if not costs.is_empty(): yield_amount=maxi(0,mini(costs.min()-1,3))
	return yield_amount

static func _fail(message: String) -> bool:
	last_error=message; busy=false; return false

static func transact(inventory: Node,storage: Node,recipe_id: String="",recycle_iid: String="",storage_commit: Callable=Callable()) -> bool:
	if busy: return false
	last_error=""; busy=true
	if not is_instance_valid(inventory) or storage==inventory: return _fail("Invalid terminal inventory.")
	var live: Array[Node]=[inventory]
	if is_instance_valid(storage): live.append(storage)
	var staged: Array[Node]=[]
	for source: Node in live:
		var copy:=Inventory.new()
		if not copy.restore(source.serialize()):
			copy.free()
			for candidate: Node in staged: candidate.free()
			return _fail("Inventory validation failed; nothing was changed.")
		staged.append(copy)
	var output: Resource
	var ok:=true
	var inherited: Dictionary={}
	if not recycle_iid.is_empty():
		var selected: Resource=staged[0].get_item(recycle_iid)
		var yield_amount:=recovery(selected)
		if yield_amount<=0 or recycle_iid in staged[0].equipment.values(): ok=false
		else:
			for key: String in ["stolen_from","stolen_event","theft_event_id"]:
				if selected.custom_properties.has(key): inherited[key]=selected.custom_properties[key]
			ok=staged[0].take_item(recycle_iid)!=null
			output=Catalog.create(&"melted_ore",yield_amount)
	else:
		var recipe:=Recipes.get_recipe(recipe_id)
		ok=not recipe.is_empty() and Recipes.valid(recipe)
		if ok:
			for material: String in recipe.ingredients:
				var remaining:=int(recipe.ingredients[material])
				for source: Node in staged:
					for item: Resource in source.items.values():
						if item.item_type_id!=Materials.item_id(material) or remaining<=0: continue
						var amount:=mini(remaining,int(item.quantity))
						for key: String in ["stolen_from","stolen_event","theft_event_id"]:
							if item.custom_properties.has(key): inherited[key]=item.custom_properties[key]
						if source.take_item(item.instance_id,amount)==null: ok=false
						remaining-=amount
				if remaining>0: ok=false
			output=Catalog.create(StringName(recipe.output_item),int(recipe.output_quantity))
	# Matching materials are exact IDs; ordinary crystals cannot replace tomb
	# fragments. Outputs go to the actor, then their accessible storage if full.
	if ok and output!=null:
		output.custom_properties=inherited
		ok=staged[0].add_item(output)
		if not ok and staged.size()>1: ok=staged[1].add_item(output)
	else: ok=false
	if not ok:
		for candidate: Node in staged: candidate.free()
		return _fail("Missing ingredients, equipped recycling item, or no output space. Nothing was changed.")
	var before: Array[Dictionary]=[]
	var blocked: Array[bool]=[]
	for i in range(live.size()):
		before.append(live[i].serialize()); blocked.append(live[i].is_blocking_signals()); live[i].set_block_signals(true)
		ok=live[i].restore(staged[i].serialize()) and ok
	# restore() normally invalidates capture through changed. Its signals are
	# held here, so dirty frozen snapshots before any property commit observer.
	for source: Node in live: source._invalidate_capture()
	if not ok:
		for i in range(live.size()): live[i].restore(before[i])
	elif storage_commit.is_valid(): storage_commit.call()
	for i in range(live.size()):
		live[i].set_block_signals(blocked[i]); staged[i].free()
	if ok:
		for source: Node in live:
			if not source.is_blocking_signals(): source.equipment_changed.emit(); source.changed.emit()
	busy=false
	return ok
