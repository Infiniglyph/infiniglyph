extends RefCounted
## Additional pages in the existing terminal menu, with its normal controls.
const Craft=preload("res://scripts/terminal_crafting.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
var menu: CanvasLayer
var provider: Callable
var back: Callable
var category:=""
func _init(surface: CanvasLayer,context: Callable,return_to: Callable):
	menu=surface; provider=context; back=return_to
func _choice(text: String,action: Callable,enabled: bool=true) -> Dictionary:
	return {"text":text,"call":action,"enabled":enabled}
func open() -> void:
	menu.show_page("TERMINAL / CRAFTING","Use owned materials from your inventory and this terminal's accessible storage. Outputs enter your inventory, or storage when the inventory is full.",[
		_choice("Meals, drinks and desserts",list_recipes.bind("cuisine")),_choice("Weapons and clothing",list_recipes.bind("equipment")),_choice("Rings and accessories",list_recipes.bind("accessories")),_choice("Recycle unequipped weapons and armor",recycling),_choice("Material registry",materials)],back)
func _context() -> Dictionary:
	return provider.call() if provider.is_valid() else {}
func _release(context: Dictionary) -> void:
	if context.get("temporary",false): context.storage.free()
func list_recipes(group: String) -> void:
	category=group
	var context:=_context()
	if context.is_empty(): menu.close_menu(); return
	var options: Array=[]
	for recipe: Dictionary in Craft.Recipes.all(group):
		var ready:=true
		for id: String in recipe.ingredients: ready=ready and Craft.available(id,context.inventory,context.storage)>=int(recipe.ingredients[id])
		options.append(_choice(Catalog.get_definition(StringName(recipe.output_item)).display_name+"  |  "+("READY" if ready else "Missing materials"),detail.bind(recipe.id)))
	_release(context)
	menu.show_page("TERMINAL / "+group.to_upper(),"Select a recipe to inspect exact requirements and available quantities.",options,open)
func detail(id: String) -> void:
	var context:=_context(); var recipe:=Craft.Recipes.get_recipe(id)
	if context.is_empty() or recipe.is_empty(): menu.close_menu(); return
	var text: String="Output: "+Catalog.get_definition(StringName(recipe.output_item)).display_name+" x"+str(int(recipe.output_quantity))+"\n\nIngredients (inventory + accessible storage):"
	var ready:=true
	for material: String in recipe.ingredients:
		var have:=Craft.available(material,context.inventory,context.storage); var need:=int(recipe.ingredients[material])
		text+="\n"+Craft.Materials.get_material(material).name+": %d / %d%s" % [have,need,"  MISSING "+str(need-have) if have<need else ""]
		ready=ready and have>=need
	if not recipe.source_dungeon.is_empty(): text+="\n\nDungeon: "+String(recipe.source_dungeon).capitalize()+". Its associated materials cannot be substituted."
	_release(context)
	menu.show_page("CRAFT / "+Catalog.get_definition(StringName(recipe.output_item)).display_name,text,[_choice("Craft one",execute.bind(id,""),ready)],list_recipes.bind(category))
func recycling() -> void:
	var context:=_context()
	if context.is_empty(): menu.close_menu(); return
	var options: Array=[]
	for item: Resource in context.inventory.items.values():
		var amount:=Craft.recovery(item)
		if amount>0 and item.instance_id not in context.inventory.equipment.values(): options.append(_choice("Recycle "+Catalog.get_definition(item.item_type_id).display_name+"  ->  %d Melted Ore" % amount,execute.bind("",item.instance_id)))
	_release(context)
	menu.show_page("TERMINAL / RECYCLING","Consumes one selected unequipped item. Returns reduced structural ore; dungeon materials are never recovered.",options,open)
func materials() -> void:
	var context:=_context()
	if context.is_empty(): menu.close_menu(); return
	var text:=""
	for row: Dictionary in Craft.Materials.all(): text+="%s (%s): %d\n%s\n\n" % [row.name,row.category,Craft.available(row.id,context.inventory,context.storage),row.description]
	_release(context)
	menu.show_page("TERMINAL / MATERIAL REGISTRY",text,[],open)
func execute(recipe: String,iid: String) -> void:
	var context:=_context()
	if context.is_empty(): menu.close_menu(); return
	var ok:=Craft.transact(context.inventory,context.storage,recipe,iid,context.get("commit",Callable()))
	_release(context)
	if iid.is_empty(): detail(recipe)
	else: recycling()
	menu.set_status("Crafted item added." if ok and iid.is_empty() else "Equipment recycled into ore." if ok else Craft.last_error,not ok)
