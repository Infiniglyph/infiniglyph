extends SceneTree
## Controller/keyboard UI paths use real owned item data and real loot transactions.
const UI = preload("res://scripts/inventory_ui.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Loot = preload("res://scripts/loot_authority.gd")
class Actor extends Node3D:
	var visual := Node3D.new()
	var weapon_combat: Node
var scene: Node3D
var actor: Actor
var inventory: Node
var loot: Node
var ui: CanvasLayer
var checks := 0
var failures := 0
var signals_seen := {"open":0,"close":0,"save":0}

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error("FAIL: "+message)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	ui._input(event)

func pad(code: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = true
	ui._input(event)

func axis(code: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = code
	event.axis_value = value
	ui._input(event)

func find_type(id: StringName) -> String:
	for iid in inventory.items:
		if inventory.items[iid].item_type_id==id: return String(iid)
	return ""

func _initialize() -> void: call_deferred("run")

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	actor = Actor.new()
	scene.add_child(actor)
	actor.add_child(actor.visual)
	inventory = Inventory.new()
	inventory.owner_id = "ui-test"
	inventory.actor = actor
	actor.add_child(inventory)
	inventory.seed_starter()
	for entry in [[&"light_shard",12],[&"signal_tonic",3],[&"civic_key",1],[&"cyan_mantle",1],[&"echo_fragment",2]]:
		check(inventory.add_item(Catalog.create(entry[0],entry[1])),"UI fixture adds catalog item "+String(entry[0]))
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30,0.2,30)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	floor_body.position.y = -0.1
	loot = Loot.new()
	scene.add_child(loot)
	loot.register_inventory(inventory)
	ui = UI.new()
	ui.actor = actor
	ui.inventory = inventory
	ui.loot = loot
	scene.add_child(ui)
	ui.opened.connect(func(): signals_seen.open += 1)
	ui.closed.connect(func(): signals_seen.close += 1)
	ui.save_requested.connect(func(): signals_seen.save += 1)
	await frames()
	check(not ui.is_open and not ui._screen.visible,"The inventory starts closed")
	ui.open_menu()
	await frames()
	check(ui.is_open and ui.layer==20 and ui.process_mode==Node.PROCESS_MODE_ALWAYS,"Inventory opens above the HUD with independent UI processing")
	check(signals_seen.open==1 and ui.category_buttons.size()==6,"Opening emits once and exposes all six real categories")
	check(ui.item_rows.size()==4 and ui.visible_ids.size()==4,"Starter weapons appear as four individual items")
	var katana := find_type(&"katana")
	ui.select_item(katana)
	check(ui._name_label.text=="Katana" and "Afterimage Waltz" in ui._arts.text and "22 / 22" in ui._stats.text,"Inspection shows actual weapon name, damage and all authored weapon arts")
	key(KEY_DOWN)
	check(ui.selected_iid!=katana,"Keyboard arrows navigate the item selection")
	key(KEY_RIGHT)
	check(ui.category_index==1 and ui.tab_index==0,"Keyboard left/right change item categories")
	check("stored cosmetic pattern" in ui._arts.text.to_lower(),"Unwearable cosmetic patterns remain stored items")
	ui.activate_selection()
	check(ui._modal_buttons.size()==2 and ui._modal_buttons[0].text=="DROP","Cosmetics have no fabricated equip or use action")
	pad(JOY_BUTTON_B)
	check(ui.mode==&"" and ui.is_open,"Controller B dismisses an action menu before closing inventory")
	ui.select_item(find_type(&"civic_key"))
	ui.activate_selection()
	check(ui._modal_buttons.size()==1 and ui._modal_buttons[0].text=="BACK","Exclusive key items expose no drop or transfer action")
	key(KEY_ESCAPE)
	key(KEY_F5)
	check(signals_seen.save==1,"F5 requests an explicit checkpoint save")
	pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(ui.tab_index==1 and ui.equipment_buttons.size()==5,"Controller RB opens four weapon directions and the Body clothing slot")
	pad(JOY_BUTTON_A)
	pad(JOY_BUTTON_A)
	check(ui.mode==&"weapon_pick","Controller A opens the owned-weapon chooser for a direction")
	pad(JOY_BUTTON_A) # Katana sorts first.
	check(inventory.weapon_slot(&"up")==&"right" and inventory.equipped_item(&"right")==null,"A weapon can be assigned to another direction through the host transaction")
	pad(JOY_BUTTON_A)
	pad(JOY_BUTTON_DPAD_DOWN)
	pad(JOY_BUTTON_A)
	check(inventory.equipped_item(&"up")==null,"Equipment menu can unequip a direction through the host")
	ui.select_item(katana)
	pad(JOY_BUTTON_A)
	pad(JOY_BUTTON_A)
	check(ui.mode==&"slots" and ui._modal_buttons.size()==5,"Inventory Equip exposes all four target directions plus Back")
	pad(JOY_BUTTON_DPAD_DOWN)
	pad(JOY_BUTTON_A)
	check(inventory.weapon_slot(&"left")==&"right","Inventory slot chooser can assign the selected weapon to LEFT")
	loot.validator = func(_operation: StringName,_inventory: Node,_payload: Dictionary): return false
	ui._equip(&"down",katana)
	check(inventory.weapon_slot(&"down")==&"down" and "could not" in ui._status.text,"A rejected host equip leaves equipment intact and reports failure")
	loot.validator = Callable()
	var shards := find_type(&"light_shard")
	ui.select_item(shards)
	pad(JOY_BUTTON_A)
	pad(JOY_BUTTON_A)
	check(ui.mode==&"quantity" and ui._quantity_max==12,"Dropping a stack opens an explicit quantity selector")
	pad(JOY_BUTTON_DPAD_RIGHT)
	pad(JOY_BUTTON_DPAD_RIGHT)
	check(ui._quantity==3,"Controller left/right changes the requested stack quantity")
	pad(JOY_BUTTON_A)
	check(inventory.get_item(shards).quantity==9 and loot.pickups.size()==1,"Confirmed drop transfers only the selected quantity into a physical pickup")
	var pickup: Node3D = loot.pickups.values()[0]
	check(pickup.item_instance.quantity==3 and pickup.item_instance.owner_id=="","The dropped stack has the correct world quantity and no inventory owner")
	check("placed in the city" in ui._status.text,"Successful actions show a visible result")
	ui.select_category(0)
	var before: int = ui.selected_index
	axis(JOY_AXIS_LEFT_Y,0.9)
	check(ui.selected_index!=before,"Left-stick motion navigates the item list")
	axis(JOY_AXIS_LEFT_Y,0)
	axis(JOY_AXIS_TRIGGER_RIGHT,0.9)
	check(ui.category_index==1,"Right trigger advances the category")
	axis(JOY_AXIS_TRIGGER_RIGHT,0.9)
	check(ui.category_index==1,"A held trigger advances only once until it is released")
	axis(JOY_AXIS_TRIGGER_RIGHT,0)
	axis(JOY_AXIS_TRIGGER_LEFT,0.9)
	check(ui.category_index==0,"Left trigger returns to the previous category")
	axis(JOY_AXIS_TRIGGER_LEFT,0)
	ui.close_menu()
	for i in range(205):
		var item: Resource = Catalog.create(&"katana")
		item.upgrade_level = i%4
		inventory.add_item(item)
	ui.open_menu()
	ui.select_category(0)
	await frames()
	check(ui.filtered_ids.size()==209 and ui.item_rows.size()==UI.PAGE_SIZE,"Hundreds of owned items create only a single page of row controls")
	var first_page: Array = ui.visible_ids.duplicate()
	ui._next.pressed.emit()
	check(ui.page==1 and ui.visible_ids.size()==UI.PAGE_SIZE and not ui.visible_ids[0] in first_page,"Mouse page controls move to a distinct bounded page")
	ui.item_rows[3].pressed.emit()
	check(ui.selected_index==3 and ui.selected_iid==ui.visible_ids[3],"Mouse item buttons select their exact owned instance")
	await frames()
	check(ui._help.global_position.y+ui._help.size.y<=695,"A full weapon page keeps the controls inside the menu's bottom margin")
	ui.select_tab(1)
	await frames()
	check(ui._help.global_position.y+ui._help.size.y<=695,"Equipment inspection keeps the controls inside the menu's bottom margin")
	ui.select_category(3)
	await frames()
	check(ui._help.global_position.y+ui._help.size.y<=695,"The menu footer remains inside the 1280x720 viewport with a safe bottom margin")
	check(ui._equipped.global_position.y+ui._equipped.size.y<=ui._help.global_position.y,"Inspection content stays above the controls footer")
	ui._input(_key_event(KEY_F5))
	check(signals_seen.save==2 and ui.is_open and not paused,"Inventory actions remain available without pausing gameplay")
	key(KEY_ESCAPE)
	check(not ui.is_open and signals_seen.close==2,"Escape closes inventory and emits a close event for the world controller")
	scene.queue_free()
	await process_frame
	print("Inventory UI verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event
