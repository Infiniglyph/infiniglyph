extends SceneTree
## Owned-instance filtering, real controls and host-authoritative item actions.
const UI = preload("res://scripts/inventory_ui.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const ItemType = preload("res://scripts/inventory_item_type.gd")
const Loot = preload("res://scripts/loot_authority.gd")
class Actor extends Node3D:
	var visual := Node3D.new()
	var weapon_combat: Node
class Fighter extends Node:
	signal changed
	var health := 1000.0
	var max_health := 1000.0
	var paintbrush_settings := preload("res://scripts/paintbrush_settings.gd").new()
	var equation_trace_settings := preload("res://scripts/equation_trace_settings.gd").new()
	func can_act() -> bool: return true
var scene: Node3D
var actor: Actor
var inventory: Node
var loot: Node3D
var ui: CanvasLayer
var checks := 0
var failures := 0
var owned: Dictionary = {}
var generated: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func add(type: StringName,quantity: int = 1) -> String:
	var item: Resource = Catalog.create(type,quantity)
	if item==null or not inventory.add_item(item):
		push_error("Fixture cannot add "+String(type))
		failures += 1
		return ""
	owned[String(type)] = item.instance_id
	return item.instance_id

func search(text: String) -> void:
	ui.query.text = text
	ui.query.text_changed.emit(text)

func key(code: Key,reverse: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.shift_pressed = reverse
	ui._input(event)

func pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	ui._input(event)

func family(iid: String) -> String:
	var item: Resource = inventory.get_item(iid)
	var definition: Resource = Catalog.get_definition(item.item_type_id)
	return String(definition.custom_properties.get("family",item.item_type_id))

func matches_families(choices: Array) -> bool:
	if ui.filtered_ids.is_empty(): return false
	for iid: String in ui.filtered_ids:
		if family(iid) not in choices: return false
	return true

func contains_type(type: StringName) -> bool:
	for iid: String in ui.filtered_ids:
		if inventory.get_item(iid).item_type_id==type: return true
	return false

func selected_safe() -> bool:
	return ui.selected_iid.is_empty() if ui.filtered_ids.is_empty() else ui.selected_iid in ui.visible_ids and inventory.get_item(ui.selected_iid)!=null

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("Inventory filter verification timed out"); quit(1))
	root.size = Vector2i(1280,720)
	scene = Node3D.new()
	root.add_child(scene)
	actor = Actor.new()
	scene.add_child(actor)
	actor.add_child(actor.visual)
	actor.weapon_combat = Fighter.new()
	actor.add_child(actor.weapon_combat)
	inventory = Inventory.new()
	inventory.owner_id = "inventory-filter-test"
	inventory.actor = actor
	actor.add_child(inventory)
	inventory.seed_starter()
	for iid: String in inventory.items: owned[String(inventory.get_item(iid).item_type_id)] = iid
	var wanted := ["dagger","sword","curved_sword","axe","hammer","greatsword","spear","halberd","scythe","twin_blades","fist","staff","chime","whip","scribe","disc","dual_disc","paintbrush","body","head","hands","legs","ring"]
	for entry: Dictionary in Database.all():
		if entry.family in wanted and not generated.has(entry.family):
			generated[entry.family] = add(StringName(entry.id))
	for color: String in ["cyan","violet","gold","mint","pink","blue","silver","ember"]:
		if not owned.has("paintbrush_"+color): add(StringName("paintbrush_"+color))
	for entry: Array in [[&"eternal_scribe_robes",1],[&"cyan_mantle",1],[&"health_glyph",3],[&"shield_glyph_light",2],[&"shield_glyph_medium",2],[&"shield_glyph_heavy",2],[&"respawn_glyph",2],[&"home_respawn_glyph",2],[&"signal_tonic",3],[&"light_shard",5],[&"civic_key",1],[&"echo_fragment",2]]: add(entry[0],entry[1])
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30,.2,30)
	collision.shape = shape
	floor_body.add_child(collision)
	scene.add_child(floor_body)
	floor_body.position.y = -.1
	loot = Loot.new()
	scene.add_child(loot)
	loot.register_inventory(inventory)
	ui = UI.new()
	ui.actor = actor
	ui.inventory = inventory
	ui.loot = loot
	scene.add_child(ui)
	await frames()
	ui.open_menu()
	await frames()
	check(UI.CATEGORIES.size()==7 and ui.category_buttons.size()==7,"Type filters preserve the six existing category indices and add furniture")
	check(ui.type_filter.item_count==10 and ui.type_filter.selected==0 and ui.query.text.is_empty(),"Weapon inventory starts with all ten Exchange-compatible type choices")
	check(ui.filtered_ids.size()>UI.PAGE_SIZE and ui.item_rows.size()==UI.PAGE_SIZE,"A mixed owned weapon collection remains paged into bounded row controls")
	var sets := [[],["dagger"],["sword","curved_sword","katana","sword_shield"],["axe","hammer","greatsword"],["spear","halberd","scythe"],["twin_blades","fist"],["staff","chime","whip"],["scribe"],["disc","dual_disc"],["paintbrush"]]
	for index in range(1,sets.size()):
		ui.select_filter(index)
		check(matches_families(sets[index]) and selected_safe(),"Weapon type "+ui.type_filter.get_item_text(index)+" shows only matching owned families")
	ui.select_filter(2)
	check(contains_type(&"katana") and contains_type(&"sword_shield"),"Original Katana and Longsword + Shield share the sword filter with generated swords")
	ui.select_filter(4)
	check(contains_type(&"spear"),"The original Spear is included with generated polearms")
	ui.select_filter(5)
	check(contains_type(&"twin_blades"),"Original Twin Blades appear with paired weapons")
	ui.select_filter(9)
	search("ViOlEt")
	check(ui.filtered_ids.size()==1 and contains_type(&"paintbrush_violet"),"Case-insensitive name search intersects the active Paintbrush type filter")
	ui.select_filter(2)
	check(ui.filtered_ids.is_empty() and ui.selected_iid.is_empty(),"Search and type intersect rather than admitting a weapon from another family")
	ui.activate_selection()
	check(ui.mode.is_empty() and ui._actions_button.disabled and ui._empty_label.visible,"Empty filtered results expose no stale item action")
	ui.select_item(owned.katana)
	check(ui.selected_iid==owned.katana and owned.katana in ui.visible_ids and ui.tab_index==0,"Direct selection reveals its exact owned instance despite restrictive type and query filters")
	ui.select_filter(9)
	search("paintbrush")
	check(ui.filtered_ids.size()==8,"All eight owned Paintbrush color variants appear under the class family search")
	ui.type_filter.select(0)
	ui.type_filter.item_selected.emit(0)
	search("  katana  ")
	check(contains_type(&"katana"),"Search trims surrounding whitespace before matching readable weapon types")
	search("longsword + shield")
	check(ui.filtered_ids.size()==1 and contains_type(&"sword_shield"),"Search resolves the readable original weapon type beyond its internal item ID")
	search("dual_disc")
	check(ui.filtered_ids.size()==1 and generated.dual_disc in ui.filtered_ids,"Search also recognizes a generated weapon's internal family independently of its display name")
	search("")
	ui._next.pressed.emit()
	check(ui.page==1,"The all-weapons fixture reaches a later real inventory page")
	ui.select_filter(9)
	check(ui.page==0 and ui.selected_index==0 and selected_safe(),"Changing type resets pagination and selection before rebuilding rows")
	search("ember")
	check(ui.page==0 and ui.filtered_ids.size()==1 and contains_type(&"paintbrush_ember"),"Changing search resets pagination and preserves an exact matching instance")
	ui.select_filter(0)
	search("")
	ui.cycle_filter()
	check(ui.type_filter.selected==1,"The shared filter cycling API advances to the next type")
	ui.cycle_filter(-1)
	check(ui.type_filter.selected==0,"The shared cycling API supports reverse navigation")
	key(KEY_F)
	check(ui.type_filter.selected==1,"Keyboard F cycles the inventory type filter")
	key(KEY_F,true)
	check(ui.type_filter.selected==0,"Keyboard Shift+F reverses the inventory type filter")
	pad(JOY_BUTTON_Y)
	check(ui.type_filter.selected==1,"Controller Y cycles inventory types without changing categories")
	ui.query.grab_focus()
	await frames()
	var focused_filter: int = ui.type_filter.selected
	key(KEY_F)
	key(KEY_SPACE)
	check(ui.type_filter.selected==focused_filter and ui.mode.is_empty(),"Typing into search cannot cycle types or activate a stale item action")
	ui.query.release_focus()
	ui.select_category(1)
	check(ui.type_filter.item_count==6 and ui.type_filter.selected==0 and ui.query.text.is_empty(),"Changing category resets type and search to the appropriate cosmetic choices")
	for index in range(1,5):
		ui.select_filter(index)
		var slot: String = ["","body","head","hands","legs"][index]
		var valid: bool = not ui.filtered_ids.is_empty()
		for iid: String in ui.filtered_ids:
			var definition: Resource = Catalog.get_definition(inventory.get_item(iid).item_type_id)
			valid = valid and definition.custom_properties.get("cosmetic_slot","")==slot
		check(valid,"Cosmetic type "+slot+" shows only armor for its actual equipment slot")
	ui.select_filter(1)
	check(contains_type(&"eternal_scribe_robes"),"Original Eternal Scribe Robes are recognized as Body armor")
	ui.select_filter(5)
	check(ui.filtered_ids.size()==1 and contains_type(&"cyan_mantle"),"Pattern filter isolates stored cosmetic patterns from wearable armor")
	ui.select_filter(0)
	search("head")
	check(ui.filtered_ids.size()>=1 and generated.head in ui.filtered_ids,"Cosmetic search recognizes readable equipment-slot type names")
	ui.select_category(2)
	check(ui.type_filter.item_count==7,"Consumables preserve five existing filters and add meals plus drinks/desserts")
	ui.select_filter(1)
	check(ui.filtered_ids.size()==1 and contains_type(&"health_glyph"),"Health Glyph type isolates the healing stack")
	ui.select_filter(2)
	check(ui.filtered_ids.size()==3 and contains_type(&"shield_glyph_heavy") and contains_type(&"shield_glyph_medium") and contains_type(&"shield_glyph_light"),"Shield Glyph filter includes all three protection tiers")
	ui.select_filter(3)
	check(ui.filtered_ids.size()==2 and contains_type(&"respawn_glyph") and contains_type(&"home_respawn_glyph"),"Respawn filter includes reusable normal and Home Respawn Glyphs")
	ui.select_filter(4)
	check(ui.filtered_ids.size()==1 and contains_type(&"signal_tonic"),"Other consumables retain items outside the three glyph classes")
	ui.select_category(5)
	check(ui.type_filter.item_count==3,"Miscellaneous offers All, Rings, and Other filters")
	ui.select_filter(1)
	check(ui.filtered_ids.size()==1 and generated.ring in ui.filtered_ids,"Ring filter isolates the actual generated wearable ring")
	ui.select_filter(2)
	check(ui.filtered_ids.size()==1 and contains_type(&"echo_fragment"),"Other miscellaneous items remain available independently of rings")
	for category: int in [3,4]:
		ui.select_category(category)
		check(ui.type_filter.item_count==1 and not ui.filtered_ids.is_empty(),"Category "+String(UI.CATEGORIES[category])+" retains a functional All filter")
	ui.select_category(0)
	ui.select_filter(9)
	search("violet")
	var inspected: String = ui.selected_iid
	ui.close_menu()
	ui.open_menu()
	check(ui.type_filter.selected==9 and ui.query.text=="violet" and ui.selected_iid==inspected,"Closing and reopening preserves the user's current type, query, and exact item")
	ui.select_tab(1)
	check(ui.equipment_buttons.size()==UI.EQUIPMENT_SLOTS.size(),"Filtering the inventory leaves all ten equipment slots available")
	ui.select_tab(0)
	check(ui.type_filter.selected==9 and ui.query.text=="violet" and ui.filtered_ids.size()==1,"A trip through Equipment retains the inventory's active filters")
	# External ownership changes rebuild filtered rows and cannot leave behind a
	# selected instance which is no longer in this inventory.
	ui.activate_selection()
	check(not ui.mode.is_empty(),"The selected filtered item opens its real item-action menu")
	var removed: Resource = inventory.take_item(inspected,1)
	check(removed!=null and ui.filtered_ids.is_empty() and ui.selected_iid.is_empty() and ui._actions_button.disabled,"External removal clears the only matching result and its actionable selection")
	check(ui.mode.is_empty(),"External removal closes the old item's modal before another instance can inherit its action")
	ui.activate_selection()
	check(ui.mode.is_empty(),"A removed filtered item cannot reopen stale equipment or drop actions")
	var replacement: String = add(&"paintbrush_violet")
	check(ui.filtered_ids.size()==1 and ui.selected_iid==replacement and replacement!=inspected,"External inventory additions refresh filters to the new exact owned instance")
	loot.validator = func(_operation: StringName,_inventory: Node,_payload: Dictionary) -> bool: return false
	ui._equip(&"down",replacement)
	check(inventory.equipment.get(&"down","")!=replacement and "could not" in ui._status.text,"Filtered item actions still obey the host's ownership validator")
	loot.validator = Callable()
	ui._equip(&"down",replacement)
	check(inventory.equipment.get(&"down","")==replacement and ui.type_filter.selected==9 and ui.query.text=="violet","A filtered owned weapon equips through the real authority without losing the search")
	ui._quantity = 1
	ui._drop()
	check(inventory.get_item(replacement)==null and loot.pickups.size()==1 and ui.selected_iid.is_empty(),"Dropping the filtered item transfers the real instance and safely empties the result set")
	ui.select_category(0)
	ui.select_filter(9)
	search("paintbrush")
	await frames()
	check(root.get_visible_rect().encloses(ui.query.get_global_rect()) and root.get_visible_rect().encloses(ui.type_filter.get_global_rect()),"Search and type controls fit completely inside the 1280x720 viewport")
	check(ui._help.get_global_rect().end.y<=695 and ui._equipped.get_global_rect().end.y<=ui._help.get_global_rect().position.y,"Filter controls and paged rows preserve the inspection and footer margins")
	check(not paused and ui.is_open,"Searching and filtering never pause the running world")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/inventory_filters.png")
	scene.queue_free()
	await process_frame
	print("Inventory filter verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
