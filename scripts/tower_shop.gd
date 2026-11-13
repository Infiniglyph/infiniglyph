extends CanvasLayer
## A live exchange at the civic crystal; grants go through the loot authority.
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Browser = preload("res://scripts/equipment_browser.gd")
var browser: PanelContainer
var _main_panel: PanelContainer
const SHOP_ID := &"central_tower"
const ITEMS: Array[StringName] = [&"sword_shield",&"spear",&"katana",&"twin_blades",&"health_glyph",&"eternal_scribe_robes"]
# Authoritative offer prices. Currency settlement can be added here later;
# nonzero prices are displayed but unavailable until that system exists.
@export var prices: Dictionary = {"sword_shield":0,"spear":0,"katana":0,"twin_blades":0,"health_glyph":0,"eternal_scribe_robes":0}
signal opened
signal closed
var session: Node
var is_open := false
var _screen: Control
var _status: Label
var _buttons: Array[Button] = []
var _stick := 0.0
var _repeat := 0.0
var _armed := true
var _buying := false
var _metro: Node3D

func _ready() -> void:
	name = "TowerShop"
	layer = 22
	_metro = session.actor.get_parent().get_node("CentralDistrict/Metropolis")
	session.loot.register_shop(SHOP_ID,self)
	_build()
	_screen.hide()
	set_process(false)

func anchor() -> Vector3:
	return _metro.to_global(_metro.TOWER+Vector3.UP*_metro.DAIS_HEIGHT)

func offer(id: StringName) -> Dictionary:
	if id not in ITEMS and Database.get_item(id).is_empty(): return {}
	var price: Variant = prices.get(String(id),0 if not Database.get_item(id).is_empty() else null)
	if not price is int or price<0: return {}
	return {"item_type_id":id,"price":price}

func can_use(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(_metro): return false
	if actor!=session.actor or actor.health<=0 or not actor.is_on_floor(): return false
	if actor.dodge.active or actor.weapon_combat.is_staggered() or not actor.weapon_combat.active_move.is_empty() or actor.combat.charge_action!=&"": return false
	if session.duel.active or session.duel.dialogue_open: return false
	if is_instance_valid(session.boss_encounter) and (session.boss_encounter.active or session.boss_encounter.dialogue_open): return false
	if is_instance_valid(session.world_actions) and session.world_actions.attached(): return false
	var offset: Vector3 = actor.global_position-anchor()
	if absf(offset.y)>0.4 or Vector2(offset.x,offset.z).length()>4.2: return false
	# Aim just outside the solid pedestal, rather than through it. Another
	# wall between the visitor and the monument still prevents interaction.
	var outside := Vector3(offset.x,0,offset.z).normalized()*1.55
	var query := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP,anchor()+outside+Vector3.UP,1)
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _style(focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.008,0.06,0.075,0.98) if focused else Color(0.003,0.016,0.023,0.98)
	style.border_color = Color(0.1,0.9,1) if focused else Color(0.07,0.35,0.4)
	style.set_border_width_all(2 if focused else 1)
	style.set_content_margin_all(14)
	style.set_corner_radius_all(5)
	return style

func _label(text: String, size_value: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size_value)
	label.add_theme_color_override("font_color",Color(0.72,0.94,0.98))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _build() -> void:
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	var shade := ColorRect.new()
	shade.color = Color(0,0.008,0.015,0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(shade)
	var panel := PanelContainer.new()
	_main_panel = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.28
	panel.anchor_right = 0.72
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.93
	panel.add_theme_stylebox_override("panel",_style())
	_screen.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",10)
	scroll.add_child(box)
	box.add_child(_label("TOWER EXCHANGE",26))
	box.add_child(_label("Central tower  /  All items currently free",16))
	_add_button(box,"WEAPONS  /  Named weapons and combat styles",func(): open_browser("weapons"))
	_add_button(box,"ITEMS  /  Health Glyphs and keepsakes",func(): open_browser("items"))
	_add_button(box,"ARMOUR  /  Clothing, plate and shields",func(): open_browser("armour"))
	_status = _label("",16)
	_status.custom_minimum_size.y = 52
	_status.modulate = Color(1,0.66,0.28)
	box.add_child(_status)
	_add_button(box,"Leave exchange",close_menu)
	box.add_child(_label("A / ENTER: acquire   B / ESC: leave\nEquip weapons and clothing from inventory.",14))
	browser = Browser.new()
	browser.shop = self
	_screen.add_child(browser)

func open_browser(category: String = "weapons") -> void:
	_main_panel.hide()
	browser.show()
	browser.set_category(category)
	browser.refresh()
	if not browser.buttons.is_empty(): browser.buttons[0].grab_focus()

func close_browser() -> void:
	browser.hide()
	_main_panel.show()
	_buttons[["weapons","items","armour"].find(browser.category)].grab_focus()

func _add_button(box: VBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size",18)
	var normal := _style()
	var focused := _style(true)
	normal.set_content_margin_all(10)
	focused.set_content_margin_all(10)
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("focus",focused)
	button.add_theme_stylebox_override("hover",focused)
	button.pressed.connect(action)
	box.add_child(button)
	_buttons.append(button)

func refresh() -> void:
	if is_instance_valid(browser) and browser.visible: browser.refresh()

func open_menu() -> void:
	if is_open or not session.controls.gameplay_enabled or session.ui.is_open or not can_use(session.actor): return
	is_open = true
	_stick = 0
	_armed = true
	_repeat = 0
	_status.text = "Choose an item to add to your inventory."
	refresh()
	browser.hide()
	_main_panel.show()
	_screen.show()
	set_process(true)
	opened.emit()
	_buttons[0].grab_focus()

func close_menu() -> void:
	if not is_open: return
	is_open = false
	_screen.hide()
	set_process(false)
	closed.emit()

func buy(id: StringName) -> bool:
	if not is_open or _buying: return false
	_buying = true
	var accepted: bool = session.loot.request_shop_purchase(session.actor.inventory,SHOP_ID,id)
	_buying = false
	if accepted:
		_status.text = "Acquired %s. Added to inventory." % Catalog.get_definition(id).display_name
		refresh()
	else: _status.text = "Item unavailable. Check your inventory space and distance to the tower."
	return accepted

func _navigate(direction: int) -> void:
	var active: Array[Button] = browser.buttons if browser.visible else _buttons
	var index := active.find(get_viewport().gui_get_focus_owner())
	for step in range(active.size()):
		index = posmod(index+direction,active.size())
		if not active[index].disabled:
			active[index].grab_focus()
			return

func _accept() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var active: Array[Button] = browser.buttons if browser.visible else _buttons
	if focused is Button and focused in active and not focused.disabled: focused.pressed.emit()

func _input(event: InputEvent) -> void:
	if not is_open: return
	if browser.visible and event is InputEventKey and browser.query.has_focus() and not event.is_action_pressed("ui_cancel"): return
	# Let the session hand View / inventory over to its existing UI.
	if event.is_action_pressed("inventory_toggle") and not event.is_echo(): return
	# Consume before GUI defaults so one press cannot also buy a second item,
	# jump, dodge, drink a Glyph or release a charged weapon art.
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode if event.physical_keycode!=0 else event.keycode:
			KEY_UP,KEY_W: _navigate(-1)
			KEY_DOWN,KEY_S: _navigate(1)
			KEY_ENTER,KEY_SPACE: _accept()
			KEY_LEFT: if browser.visible: browser.change_page(-1)
			KEY_RIGHT: if browser.visible: browser.change_page(1)
			KEY_ESCAPE:
				if browser.visible: close_browser()
				else: close_menu()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP: _navigate(-1)
			JOY_BUTTON_DPAD_DOWN: _navigate(1)
			JOY_BUTTON_A: _accept()
			JOY_BUTTON_DPAD_LEFT: if browser.visible: browser.change_page(-1)
			JOY_BUTTON_DPAD_RIGHT: if browser.visible: browser.change_page(1)
			JOY_BUTTON_RIGHT_SHOULDER: if browser.visible: browser.cycle_filter()
			JOY_BUTTON_B:
				if browser.visible: close_browser()
				else: close_menu()
	elif event is InputEventJoypadMotion and event.axis==JOY_AXIS_LEFT_Y:
		_stick = event.axis_value
		if absf(_stick)<0.3: _armed = true
		elif _armed and absf(_stick)>0.6:
			_armed = false
			_repeat = 0.35
			_navigate(int(signf(_stick)))

func _process(delta: float) -> void:
	if not can_use(session.actor):
		close_menu()
		return
	if not _armed and absf(_stick)>0.6:
		_repeat -= delta
		if _repeat<=0:
			_repeat = 0.12
			_navigate(int(signf(_stick)))

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_open: close_menu()
