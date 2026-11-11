extends CanvasLayer
## An event-driven inventory view; the world controller owns the local input gate.
const Catalog = preload("res://scripts/item_catalog.gd")
const Library = preload("res://scripts/weapon_library.gd")
const CATEGORIES := [&"weapons",&"cosmetics",&"consumables",&"materials",&"key_items",&"misc"]
const CATEGORY_NAMES := ["WEAPONS","ARMOR / COSMETICS","CONSUMABLES","MATERIALS","KEY ITEMS","MISCELLANEOUS"]
const CATEGORY_GLYPHS := ["/|","<>" ,"+","#","*","::"]
const DIRECTIONS := [&"up",&"left",&"right",&"down"]
const EQUIPMENT_SLOTS := [&"up",&"left",&"right",&"down",&"body"]
const PAGE_SIZE := 8
const CYAN := Color(0.12,0.9,0.96)
const WHITE := Color(0.9,0.96,0.98)
const MUTED := Color(0.42,0.62,0.68)
const ORANGE := Color(1,0.48,0.12)
signal opened
signal closed
signal save_requested
var actor: Node3D
var inventory: Node
var loot: Node
var is_open := false
var tab_index := 0
var category_index := 0
var selected_index := 0
var page := 0
var selected_iid := ""
var visible_ids: Array[String] = []
var filtered_ids: Array[String] = []
var mode: StringName = &""
var item_rows: Array[Button] = []
var category_buttons: Array[Button] = []
var tab_buttons: Array[Button] = []
var equipment_buttons: Array[Button] = []
var _modal_buttons: Array[Button] = []
var _modal_index := 0
var _quantity := 1
var _quantity_max := 1
var _target_slot: StringName = &"down"
var _stick := Vector2.ZERO
var _stick_direction := Vector2.ZERO
var _repeat_timer := 0.0
var _trigger_latched := {JOY_AXIS_TRIGGER_LEFT:false,JOY_AXIS_TRIGGER_RIGHT:false}
var _screen: Control
var _rows: VBoxContainer
var _category_column: VBoxContainer
var _list_title: Label
var _page_label: Label
var _empty_label: Label
var _name_label: Label
var _meta_label: Label
var _description: Label
var _stats: Label
var _arts: Label
var _equipped: Label
var _summary: Label
var _status: Label
var _help: Label
var _actions_button: Button
var _previous: Button
var _next: Button
var _modal: Control
var _modal_panel: PanelContainer
var _modal_rows: VBoxContainer
var _quantity_label: Label

func _ready() -> void:
	name = "InventoryUI"
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_screen.hide()
	set_process(false)
	if is_instance_valid(inventory):
		if inventory.has_signal("changed"): inventory.changed.connect(refresh)
		if inventory.has_signal("equipment_changed"): inventory.equipment_changed.connect(refresh)
	if is_instance_valid(actor) and actor.get("weapon_combat") != null:
		actor.weapon_combat.changed.connect(_refresh_summary)
	refresh()

func _frame(background: Color, border: Color = Color(0.05,0.35,0.4), width: int = 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = background
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(4)
	result.content_margin_left = 14
	result.content_margin_right = 14
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	return result

func _label(value: String, size_value: int = 16, color: Color = WHITE) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size",size_value)
	result.add_theme_color_override("font_color",color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _button(value: String, call: Callable, height: float = 40) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = height
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.add_theme_font_size_override("font_size",16)
	result.add_theme_color_override("font_color",MUTED)
	result.add_theme_color_override("font_hover_color",WHITE)
	result.add_theme_color_override("font_focus_color",WHITE)
	result.add_theme_stylebox_override("normal",_frame(Color(0.005,0.022,0.03)))
	result.add_theme_stylebox_override("hover",_frame(Color(0.02,0.11,0.13),CYAN))
	result.add_theme_stylebox_override("focus",_frame(Color(0.015,0.09,0.11),CYAN,2))
	result.add_theme_stylebox_override("pressed",_frame(Color(0.02,0.14,0.16),CYAN,2))
	result.pressed.connect(call)
	return result

func _mark(button: Button, selected: bool) -> void:
	var box := _frame(Color(0.015,0.085,0.10) if selected else Color(0.005,0.022,0.03),CYAN if selected else Color(0.035,0.20,0.24))
	if selected:
		box.border_width_left = 4
		box.border_color = CYAN
	button.add_theme_stylebox_override("normal",box)
	button.add_theme_color_override("font_color",WHITE if selected else MUTED)

func _line(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = Color(0.05,0.32,0.37)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _build() -> void:
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.001,0.008,0.013,0.985)
	_screen.add_child(backdrop)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margins.add_theme_constant_override("margin_"+side,40)
	for side in ["top","bottom"]: margins.add_theme_constant_override("margin_"+side,26)
	_screen.add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",12)
	margins.add_child(layout)
	var title_row := HBoxContainer.new()
	layout.add_child(title_row)
	var title := _label("I N F I N I G L Y P H   /   FIELD KIT",24,CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_summary = _label("",16,MUTED)
	title_row.add_child(_summary)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation",8)
	layout.add_child(tab_row)
	for index in range(2):
		var button := _button(["INVENTORY","EQUIPMENT"][index],select_tab.bind(index),40)
		button.custom_minimum_size.x = 205
		tab_row.add_child(button)
		tab_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(spacer)
	var save := _button("F5  SAVE",func(): save_requested.emit(),40)
	save.custom_minimum_size.x = 130
	tab_row.add_child(save)
	var close := _button("CLOSE  [ESC]",close_menu,40)
	close.custom_minimum_size.x = 150
	tab_row.add_child(close)
	_line(layout)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",18)
	layout.add_child(content)
	_category_column = VBoxContainer.new()
	_category_column.custom_minimum_size.x = 180
	_category_column.add_theme_constant_override("separation",7)
	content.add_child(_category_column)
	_category_column.add_child(_label("CATEGORIES",13,MUTED))
	for index in range(CATEGORIES.size()):
		var button := _button(CATEGORY_GLYPHS[index]+"   "+CATEGORY_NAMES[index],select_category.bind(index),49)
		button.add_theme_font_size_override("font_size",14)
		_category_column.add_child(button)
		category_buttons.append(button)
	var note := _label("OWNED ITEMS\n\nAssign any weapon to\nany quick-select direction.",13,MUTED)
	_category_column.add_child(note)
	var list_column := VBoxContainer.new()
	list_column.custom_minimum_size.x = 360
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_column.size_flags_stretch_ratio = 0.9
	list_column.add_theme_constant_override("separation",6)
	content.add_child(list_column)
	_list_title = _label("",17,CYAN)
	list_column.add_child(_list_title)
	_rows = VBoxContainer.new()
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation",5)
	list_column.add_child(_rows)
	_empty_label = _label("",16,MUTED)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(_empty_label)
	var paging := HBoxContainer.new()
	paging.add_theme_constant_override("separation",8)
	list_column.add_child(paging)
	_previous = _button("<",func(): _change_page(-1),30)
	_previous.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_previous.custom_minimum_size.x = 44
	paging.add_child(_previous)
	_page_label = _label("",13,MUTED)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paging.add_child(_page_label)
	_next = _button(">",func(): _change_page(1),30)
	_next.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next.custom_minimum_size.x = 44
	paging.add_child(_next)
	_actions_button = _button("A / ENTER   ITEM ACTIONS",activate_selection,38)
	list_column.add_child(_actions_button)
	var inspection := PanelContainer.new()
	inspection.custom_minimum_size.x = 440
	inspection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspection.size_flags_stretch_ratio = 1.1
	inspection.add_theme_stylebox_override("panel",_frame(Color(0.004,0.018,0.025),Color(0.06,0.42,0.47)))
	content.add_child(inspection)
	var inspect_rows := VBoxContainer.new()
	inspect_rows.add_theme_constant_override("separation",8)
	inspection.add_child(inspect_rows)
	inspect_rows.add_child(_label("ITEM INSPECTION",13,CYAN))
	_name_label = _label("",27,WHITE)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_rows.add_child(_name_label)
	_meta_label = _label("",14,ORANGE)
	inspect_rows.add_child(_meta_label)
	_description = _label("",14,MUTED)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_rows.add_child(_description)
	_line(inspect_rows)
	_stats = _label("",16,WHITE)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_rows.add_child(_stats)
	_arts = _label("",14,CYAN)
	_arts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_rows.add_child(_arts)
	var inspection_spacer := Control.new()
	inspection_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspect_rows.add_child(inspection_spacer)
	_equipped = _label("",14,ORANGE)
	_equipped.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_rows.add_child(_equipped)
	_line(layout)
	_status = _label("",14,ORANGE)
	layout.add_child(_status)
	_help = _label("",14,MUTED)
	layout.add_child(_help)
	_build_modal()

func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_modal)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0,0.004,0.008,0.8)
	_modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(center)
	_modal_panel = PanelContainer.new()
	_modal_panel.custom_minimum_size.x = 500
	_modal_panel.add_theme_stylebox_override("panel",_frame(Color(0.004,0.023,0.03),CYAN,2))
	center.add_child(_modal_panel)
	_modal_rows = VBoxContainer.new()
	_modal_rows.add_theme_constant_override("separation",10)
	_modal_panel.add_child(_modal_rows)
	_modal.hide()

func open_menu() -> void:
	if is_open: return
	is_open = true
	_screen.show()
	mode = &""
	_modal.hide()
	_stick = Vector2.ZERO
	_stick_direction = Vector2.ZERO
	set_process(true)
	refresh()
	set_status("Select an item to inspect it. Your field kit is saved with the city.")
	opened.emit()

func close_menu() -> void:
	if not is_open: return
	is_open = false
	mode = &""
	_modal.hide()
	_screen.hide()
	set_process(false)
	closed.emit()

func toggle() -> void:
	if is_open: close_menu()
	else: open_menu()

func set_status(message: String, error: bool = false) -> void:
	_status.text = message
	_status.modulate = Color(1,0.3,0.22) if error else WHITE

func _refresh_summary() -> void:
	if not is_instance_valid(_summary): return
	var count: int = inventory.items.size() if is_instance_valid(inventory) else 0
	var hp := "HP %d / %d   |   " % [ceili(actor.weapon_combat.health),ceili(actor.weapon_combat.max_health)] if is_instance_valid(actor) and actor.get("weapon_combat") != null else ""
	_summary.text = hp+"%d ITEMS" % count

func _definition(item: Resource) -> Resource:
	return Catalog.get_definition(item.item_type_id) if item != null else null

func _item_name(iid: String) -> String:
	var item: Resource = inventory.get_item(iid)
	var definition := _definition(item)
	return String(definition.display_name) if definition != null else "Empty"

func _equipped_slots(iid: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for slot: StringName in EQUIPMENT_SLOTS:
		if String(inventory.equipment.get(slot,""))==iid and not iid.is_empty(): result.append(slot)
	return result

func select_tab(index: int) -> void:
	tab_index = posmod(index,2)
	selected_index = 0
	page = 0
	selected_iid = ""
	_close_modal()
	refresh()

func select_category(index: int) -> void:
	category_index = posmod(index,CATEGORIES.size())
	tab_index = 0
	selected_index = 0
	page = 0
	selected_iid = ""
	_close_modal()
	refresh()

func select_item(iid: String) -> void:
	var item: Resource = inventory.get_item(iid)
	var definition := _definition(item)
	if definition == null: return
	tab_index = 0
	category_index = maxi(0,CATEGORIES.find(definition.category))
	selected_iid = iid
	refresh()

func refresh() -> void:
	if not is_instance_valid(_rows) or not is_instance_valid(inventory): return
	_refresh_summary()
	if not is_open: return
	for i in range(tab_buttons.size()): _mark(tab_buttons[i],i==tab_index)
	for i in range(category_buttons.size()): _mark(category_buttons[i],i==category_index and tab_index==0)
	_clear_rows()
	if tab_index==1: _refresh_equipment()
	else: _refresh_items()
	_inspect()
	_help.text = "A / ENTER: actions    B / ESC: back    LB / RB: tabs    LT / RT or LEFT / RIGHT: categories    F5: save"

func _clear_rows() -> void:
	for child in _rows.get_children():
		if child==_empty_label: continue
		_rows.remove_child(child)
		child.queue_free()
	item_rows.clear()
	equipment_buttons.clear()
	_empty_label.hide()

func _refresh_items() -> void:
	filtered_ids.clear()
	for iid in inventory.items:
		var item: Resource = inventory.get_item(String(iid))
		var definition := _definition(item)
		if definition != null and definition.category==CATEGORIES[category_index]: filtered_ids.append(String(iid))
	filtered_ids.sort_custom(func(a: String,b: String):
		var left := _item_name(a)
		var right := _item_name(b)
		return a<b if left==right else left.naturalnocasecmp_to(right)<0)
	if selected_iid in filtered_ids:
		var index := filtered_ids.find(selected_iid)
		page = index/PAGE_SIZE
		selected_index = index%PAGE_SIZE
	var pages := maxi(1,ceili(filtered_ids.size()/float(PAGE_SIZE)))
	page = clampi(page,0,pages-1)
	visible_ids.clear()
	for index in range(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,filtered_ids.size())): visible_ids.append(filtered_ids[index])
	selected_index = clampi(selected_index,0,maxi(0,visible_ids.size()-1))
	selected_iid = visible_ids[selected_index] if not visible_ids.is_empty() else ""
	_list_title.text = CATEGORY_NAMES[category_index]+"   /   %d" % filtered_ids.size()
	if visible_ids.is_empty():
		_empty_label.show()
		_empty_label.text = "No "+CATEGORY_NAMES[category_index].to_lower()+" in your field kit."
		if category_index==1: _empty_label.text += "\n\nClothing can be equipped in Body."
	for index in range(visible_ids.size()):
		var iid := visible_ids[index]
		var item: Resource = inventory.get_item(iid)
		var slots := _equipped_slots(iid)
		var suffix := "  x%d" % item.quantity if item.quantity>1 else ""
		if item.upgrade_level>0: suffix += "  +%d" % item.upgrade_level
		if not slots.is_empty(): suffix += "  ["+String(slots[0]).to_upper()+"]"
		var button := _button(CATEGORY_GLYPHS[category_index]+"   "+_item_name(iid)+suffix,_select_row.bind(index),40)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_rows.add_child(button)
		_mark(button,index==selected_index)
		item_rows.append(button)
	_page_label.text = "%d / %d    |    %d per page" % [page+1,pages,PAGE_SIZE]
	_previous.disabled = page<=0
	_next.disabled = page>=pages-1
	_actions_button.disabled = visible_ids.is_empty()
	_actions_button.text = "A / ENTER   ITEM ACTIONS"

func _refresh_equipment() -> void:
	selected_index = clampi(selected_index,0,EQUIPMENT_SLOTS.size()-1)
	visible_ids.clear()
	_list_title.text = "WEAPONS / CLOTHING"
	for index in range(EQUIPMENT_SLOTS.size()):
		var slot: StringName = EQUIPMENT_SLOTS[index]
		var iid := String(inventory.equipment.get(slot,""))
		visible_ids.append(iid)
		var button := _button(String(slot).to_upper()+"    /    "+_item_name(iid),_select_row.bind(index),52)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_rows.add_child(button)
		_mark(button,index==selected_index)
		equipment_buttons.append(button)
	selected_iid = visible_ids[selected_index]
	var note := _label("Any owned weapon can occupy a direction.\nEmpty directions cannot draw or attack.\nBody holds cosmetic clothing.",14,MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(note)
	_page_label.text = "4 WEAPON DIRECTIONS / 1 CLOTHING SLOT"
	_previous.disabled = true
	_next.disabled = true
	_actions_button.disabled = false
	_actions_button.text = "A / ENTER   CHANGE / UNEQUIP"

func _select_row(index: int) -> void:
	selected_index = index
	selected_iid = visible_ids[index] if index<visible_ids.size() else ""
	refresh()

func _change_page(direction: int) -> void:
	page += direction
	selected_index = 0
	selected_iid = ""
	refresh()

func _inspect() -> void:
	var item: Resource = inventory.get_item(selected_iid)
	var definition := _definition(item)
	if item==null or definition==null:
		_name_label.text = "Empty slot" if tab_index==1 else "Nothing selected"
		_meta_label.text = String(EQUIPMENT_SLOTS[selected_index]).to_upper() if tab_index==1 else CATEGORY_NAMES[category_index]
		_description.text = "Choose Change to assign an owned weapon or clothing." if tab_index==1 else "Choose another category or pick up an item in the city."
		_stats.text = ""
		_arts.text = ""
		_equipped.text = ""
		return
	_name_label.text = definition.display_name
	_meta_label.text = "%s   |   QTY %d   |   UPGRADE +%d" % [String(definition.category).replace("_"," ").to_upper(),item.quantity,item.upgrade_level]
	_description.text = definition.description
	var canonical := StringName(definition.custom_properties.get("weapon_slot",&""))
	if not canonical.is_empty() and definition.category==&"weapons":
		var left: Dictionary = Library.move(canonical,&"attack_left")
		var right: Dictionary = Library.move(canonical,&"attack_right")
		_stats.text = "LEFT / RIGHT DAMAGE    %d / %d\nREACH    %.2f / %.2f m     GUARD    %d%%" % [left.damage,right.damage,left.reach,right.reach,int(Library.loadout(canonical).guard*100)]
		_arts.text = "WEAPON ARTS"
		var bindings := ["X / Q","Y / R","RT+X / V+Q","RT+Y / V+R"]
		var actions := [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
		for index in range(4):
			var move: Dictionary = Library.move(canonical,actions[index])
			_arts.text += "\n%s   %s\n%d damage  /  %.1f m reach" % [bindings[index],move.name,move.damage,move.reach]
	else:
		_stats.text = "STACK LIMIT    %d\nDROP    %s     TRADE    %s" % [definition.max_stack,"YES" if definition.is_droppable else "NO","YES" if definition.is_tradeable else "NO"]
		_arts.text = ("BODY CLOTHING\nCosmetic; movement and combat values stay unchanged." if definition.is_equippable else "Stored cosmetic pattern.") if definition.category==&"cosmetics" else "Stored in your field kit.\nNo use action is available for this item."
	var slots := _equipped_slots(selected_iid)
	var names: Array[String] = []
	for slot: StringName in slots: names.append(String(slot).to_upper())
	_equipped.text = "ASSIGNED   "+", ".join(names) if not names.is_empty() else "NOT ASSIGNED"

func activate_selection() -> void:
	if not mode.is_empty():
		if _modal_index<_modal_buttons.size(): _modal_buttons[_modal_index].pressed.emit()
		return
	if tab_index==1:
		_target_slot = EQUIPMENT_SLOTS[selected_index]
		_begin_modal(&"equipment","%s EQUIPMENT" % String(_target_slot).to_upper())
		_modal_choice("CHANGE CLOTHING" if _target_slot==&"body" else "CHANGE WEAPON",_choose_weapon)
		if not selected_iid.is_empty(): _modal_choice("UNEQUIP",func(): _unequip_slot(_target_slot))
		_modal_choice("BACK",_close_modal)
		return
	var item: Resource = inventory.get_item(selected_iid)
	var definition := _definition(item)
	if definition==null: return
	_begin_modal(&"actions",definition.display_name)
	if definition.category==&"weapons" and definition.is_equippable: _modal_choice("EQUIP TO DIRECTION",_choose_slot)
	if definition.category==&"cosmetics" and definition.is_equippable: _modal_choice("WEAR IN BODY",_equip.bind(&"body",selected_iid))
	if not _equipped_slots(selected_iid).is_empty(): _modal_choice("UNEQUIP",_unequip_item)
	if definition.is_droppable and definition.is_tradeable: _modal_choice("DROP",_choose_quantity)
	if _modal_buttons.is_empty(): _modal_rows.add_child(_label("This item has no available actions.",15,MUTED))
	_modal_choice("BACK",_close_modal)

func _begin_modal(next_mode: StringName, title: String) -> void:
	mode = next_mode
	_modal_index = 0
	_modal_buttons.clear()
	for child in _modal_rows.get_children():
		_modal_rows.remove_child(child)
		child.queue_free()
	_modal_rows.add_child(_label(title,23,CYAN))
	_line(_modal_rows)
	_modal.show()

func _modal_choice(title: String, call: Callable) -> void:
	var button := _button(title,call,44)
	_modal_rows.add_child(button)
	_modal_buttons.append(button)
	_update_modal_focus()

func _update_modal_focus() -> void:
	for index in range(_modal_buttons.size()): _mark(_modal_buttons[index],index==_modal_index)

func _close_modal() -> void:
	mode = &""
	_modal.hide()
	_modal_buttons.clear()

func _choose_slot() -> void:
	_begin_modal(&"slots","ASSIGN "+_item_name(selected_iid))
	for slot: StringName in DIRECTIONS:
		_modal_choice(String(slot).to_upper()+"   /   "+_item_name(String(inventory.equipment.get(slot,""))),_equip.bind(slot,selected_iid))
	_modal_choice("BACK",_close_modal)

func _choose_weapon() -> void:
	_begin_modal(&"weapon_pick","CHOOSE EQUIPMENT FOR "+String(_target_slot).to_upper())
	var choices: Array[String] = []
	for iid in inventory.items:
		var definition := _definition(inventory.get_item(String(iid)))
		if inventory.fits_slot(definition,_target_slot): choices.append(String(iid))
	choices.sort_custom(func(a: String,b: String): return _item_name(a).naturalnocasecmp_to(_item_name(b))<0)
	# Weapon choice remains paged in the normal inventory for larger collections.
	if choices.size()>8:
		_modal_rows.add_child(_label("Choose an item in Inventory, then equip it.",15,MUTED))
		_modal_choice("OPEN INVENTORY",func(): select_category(1 if _target_slot==&"body" else 0))
	else:
		for iid: String in choices: _modal_choice(_item_name(iid),_equip.bind(_target_slot,iid))
	if choices.is_empty(): _modal_rows.add_child(_label("No compatible owned items are available.",15,MUTED))
	_modal_choice("BACK",_close_modal)

func _equip(slot: StringName, iid: String) -> void:
	var title := _item_name(iid)
	var success: bool = is_instance_valid(loot) and loot.request_equip(inventory,slot,iid)
	_close_modal()
	refresh()
	set_status(title+" assigned to "+String(slot).to_upper()+"." if success else "This item could not be assigned.",not success)

func _unequip_slot(slot: StringName) -> void:
	var success: bool = is_instance_valid(loot) and loot.request_unequip(inventory,slot)
	_close_modal()
	refresh()
	set_status(String(slot).to_upper()+" is now empty." if success else "This direction could not be unequipped.",not success)

func _unequip_item() -> void:
	var success := true
	for slot: StringName in _equipped_slots(selected_iid):
		success = is_instance_valid(loot) and loot.request_unequip(inventory,slot) and success
	_close_modal()
	refresh()
	set_status("Item unequipped." if success else "This item could not be unequipped.",not success)

func _choose_quantity() -> void:
	var item: Resource = inventory.get_item(selected_iid)
	if item==null:
		_close_modal()
		return
	_quantity = 1
	_quantity_max = item.quantity
	_begin_modal(&"quantity","DROP "+_item_name(selected_iid))
	_modal_rows.add_child(_label("LEFT / RIGHT: quantity    |    Dropped items can be collected again.",13,MUTED))
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation",16)
	_modal_rows.add_child(amount_row)
	var minus := _button("-",_adjust_quantity.bind(-1),42)
	minus.custom_minimum_size.x = 65
	minus.alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_row.add_child(minus)
	_quantity_label = _label("",26,WHITE)
	_quantity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_row.add_child(_quantity_label)
	var plus := _button("+",_adjust_quantity.bind(1),42)
	plus.custom_minimum_size.x = 65
	plus.alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_row.add_child(plus)
	_adjust_quantity(0)
	_modal_choice("DROP SELECTED QUANTITY",_drop)
	_modal_choice("CANCEL",_close_modal)

func _adjust_quantity(amount: int) -> void:
	_quantity = clampi(_quantity+amount,1,_quantity_max)
	_quantity_label.text = "%d / %d" % [_quantity,_quantity_max]

func _drop() -> void:
	var forward: Vector3 = actor.visual.global_basis.z if actor.get("visual") != null else -actor.global_basis.z
	var at := actor.global_position+Vector3(forward.x,0,forward.z).normalized()*1.2
	var success: bool = is_instance_valid(loot) and loot.request_drop(inventory,selected_iid,_quantity,at)
	_close_modal()
	refresh()
	var error := "Drop failed. There is no safe placement here."
	if is_instance_valid(loot) and loot.get("last_error") != null and not String(loot.last_error).is_empty(): error = String(loot.last_error)
	set_status("Dropped item placed in the city." if success else error,not success)

func navigate(direction: Vector2) -> void:
	if not is_open: return
	if not mode.is_empty():
		if mode==&"quantity" and direction.x!=0:
			_adjust_quantity(int(signf(direction.x)))
		elif direction.y!=0 and not _modal_buttons.is_empty():
			_modal_index = posmod(_modal_index+int(signf(direction.y)),_modal_buttons.size())
			_update_modal_focus()
		return
	if direction.x!=0:
		if tab_index==0: select_category(category_index+int(signf(direction.x)))
		return
	if direction.y==0: return
	var count := visible_ids.size()
	if count==0: return
	var index := selected_index+int(signf(direction.y))
	if tab_index==0 and index>=count and (page+1)*PAGE_SIZE<filtered_ids.size():
		_change_page(1)
		return
	if tab_index==0 and index<0 and page>0:
		page -= 1
		selected_index = PAGE_SIZE-1
		selected_iid = ""
		refresh()
		return
	_select_row(posmod(index,count))

func back() -> void:
	if not mode.is_empty(): _close_modal()
	else: close_menu()

func _input(event: InputEvent) -> void:
	if not is_open: return
	var handled := true
	if event is InputEventKey:
		if not event.pressed: return
		var code: int = event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if event.echo and not code in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_W,KEY_A,KEY_S,KEY_D]:
			get_viewport().set_input_as_handled()
			return
		if code in [KEY_ESCAPE,KEY_B]:
			get_viewport().set_input_as_handled()
			back()
			return
		match code:
			KEY_UP,KEY_W: navigate(Vector2.UP)
			KEY_DOWN,KEY_S: navigate(Vector2.DOWN)
			KEY_LEFT,KEY_A: navigate(Vector2.LEFT)
			KEY_RIGHT,KEY_D: navigate(Vector2.RIGHT)
			KEY_ENTER,KEY_KP_ENTER,KEY_SPACE: activate_selection()
			KEY_ESCAPE,KEY_B: back()
			KEY_TAB: select_tab(tab_index+1)
			KEY_F5: save_requested.emit()
			_: handled = false
	elif event is InputEventJoypadButton:
		if not event.pressed: return
		if event.button_index==JOY_BUTTON_B:
			get_viewport().set_input_as_handled()
			back()
			return
		match event.button_index:
			JOY_BUTTON_DPAD_UP: navigate(Vector2.UP)
			JOY_BUTTON_DPAD_DOWN: navigate(Vector2.DOWN)
			JOY_BUTTON_DPAD_LEFT: navigate(Vector2.LEFT)
			JOY_BUTTON_DPAD_RIGHT: navigate(Vector2.RIGHT)
			JOY_BUTTON_A: activate_selection()
			JOY_BUTTON_B: back()
			JOY_BUTTON_LEFT_SHOULDER: if mode.is_empty(): select_tab(tab_index-1)
			JOY_BUTTON_RIGHT_SHOULDER: if mode.is_empty(): select_tab(tab_index+1)
			_: handled = false
	elif event is InputEventJoypadMotion:
		if event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
			if event.axis==JOY_AXIS_LEFT_X: _stick.x = event.axis_value
			else: _stick.y = event.axis_value
			var direction := Vector2.ZERO
			if _stick.length()>0.6: direction = Vector2(signf(_stick.x),0) if absf(_stick.x)>absf(_stick.y) else Vector2(0,signf(_stick.y))
			if direction!=_stick_direction:
				_stick_direction = direction
				if not direction.is_zero_approx(): navigate(direction)
				_repeat_timer = 0.36
		elif event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
			var held: bool = event.axis_value>0.55
			if held and not _trigger_latched[event.axis] and mode.is_empty(): select_category(category_index+(-1 if event.axis==JOY_AXIS_TRIGGER_LEFT else 1))
			_trigger_latched[event.axis] = held
		else: handled = false
	else: handled = false
	if handled: get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _stick_direction.is_zero_approx(): return
	_repeat_timer -= delta
	if _repeat_timer<=0:
		navigate(_stick_direction)
		_repeat_timer = 0.13
