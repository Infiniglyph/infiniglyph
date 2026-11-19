extends CanvasLayer
## Bounded service pages. The owning session gates local controls; time stays live.
const PAGE_SIZE := 8
const CYAN := Color(.18,.92,.98)
const INK := Color(.005,.025,.035,.98)
signal opened
signal closed
var services: Node
var is_open := false
var _choices: Array[Dictionary] = []
var _back_action := Callable()
var _page := 0
var _cursor := 0
var _stick := 0.0
var _stick_armed := true
var _repeat := 0.0
var _screen: Control
var _title: Label
var _body: Label
var _body_scroll: ScrollContainer
var _status: Label
var _paging: Label
var _rows: Array[Button] = []
var _active_buttons: Array[Button] = []
var _previous: Button
var _next: Button
var _back: Button

func _ready() -> void:
	name = "CivilianMenu"
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_screen.hide()
	set_process(false)

func _label(text: String, size: int, color: Color = CYAN) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 33
	button.add_theme_font_size_override("font_size",15)
	button.add_theme_color_override("font_color",Color(.82,.97,1))
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for state: String in ["normal","hover","focus","pressed","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(.012,.07,.085) if state in ["hover","focus","pressed"] else INK
		style.border_color = CYAN if state in ["hover","focus"] else Color(.08,.36,.42)
		style.set_border_width_all(1)
		style.set_content_margin_all(5)
		button.add_theme_stylebox_override(state,style)
	button.pressed.connect(action)
	button.focus_entered.connect(_focused.bind(button))
	button.mouse_entered.connect(func():
		if not button.disabled: button.grab_focus())
	return button

func _build() -> void:
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0,.007,.012,.72)
	_screen.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = .08
	panel.anchor_right = .92
	panel.anchor_top = .045
	panel.anchor_bottom = .955
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = Color(.12,.65,.74)
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel",style)
	_screen.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",6)
	panel.add_child(layout)
	_title = _label("",25)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(_title)
	_body_scroll = ScrollContainer.new()
	_body_scroll.custom_minimum_size.y = 90
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_body_scroll)
	_body = _label("",17,Color(.76,.9,.93))
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_scroll.add_child(_body)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",3)
	layout.add_child(rows)
	for index in range(PAGE_SIZE):
		var button := _button("",_run_choice.bind(index))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rows.add_child(button)
		_rows.append(button)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation",8)
	layout.add_child(navigation)
	_previous = _button("< PREVIOUS",change_page.bind(-1))
	_next = _button("NEXT >",change_page.bind(1))
	_back = _button("BACK",back)
	for button: Button in [_previous,_next,_back]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		navigation.add_child(button)
	_paging = _label("",13,Color(.48,.73,.78))
	layout.add_child(_paging)
	_status = _label("",15,Color(.75,1,.83))
	_status.custom_minimum_size.y = 38
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(_status)
	var help := _label("A / ENTER: choose   B / ESC: back   LEFT / RIGHT: pages   PGUP / PGDN: details   F5: save",13,Color(.48,.73,.78))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)

func show_page(title: String, body: String, choices: Array, back_action: Callable = Callable()) -> void:
	_choices.clear()
	for choice: Variant in choices:
		if choice is Dictionary: _choices.append(choice.duplicate())
	_back_action = back_action
	_page = 0
	_cursor = 0
	_title.text = title
	_body.text = body
	_body_scroll.scroll_vertical = 0
	_status.text = ""
	_stick = 0
	_stick_armed = true
	var was_open := is_open
	is_open = true
	_screen.show()
	set_process(true)
	_render()
	if not was_open: opened.emit()

func close_menu() -> void:
	if not is_open: return
	is_open = false
	_stick = 0
	_stick_armed = true
	_screen.hide()
	set_process(false)
	closed.emit()

func set_status(text: String, error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color",Color(1,.58,.38) if error else Color(.75,1,.83))

func _render() -> void:
	var pages := maxi(1,ceili(_choices.size()/float(PAGE_SIZE)))
	_page = clampi(_page,0,pages-1)
	_active_buttons.clear()
	for row in range(PAGE_SIZE):
		var index := _page*PAGE_SIZE+row
		var button := _rows[row]
		button.visible = index<_choices.size()
		if not button.visible: continue
		var choice := _choices[index]
		button.text = String(choice.get("text",""))
		button.tooltip_text = button.text
		var action: Variant = choice.get("call")
		button.disabled = not bool(choice.get("enabled",true)) or not action is Callable or not action.is_valid()
		if not button.disabled: _active_buttons.append(button)
	_previous.disabled = _page==0
	_next.disabled = _page>=pages-1
	for button: Button in [_previous,_next,_back]:
		if not button.disabled: _active_buttons.append(button)
	_paging.text = "%d choices   |   Page %d / %d" % [_choices.size(),_page+1,pages]
	_cursor = clampi(_cursor,0,maxi(0,_active_buttons.size()-1))
	if not _active_buttons.is_empty(): _active_buttons[_cursor].grab_focus()

func _focused(button: Button) -> void:
	var index := _active_buttons.find(button)
	if index>=0: _cursor = index

func navigate(direction: int) -> void:
	if not is_open or _active_buttons.is_empty(): return
	_cursor = posmod(_cursor+direction,_active_buttons.size())
	_active_buttons[_cursor].grab_focus()

func change_page(direction: int) -> void:
	if not is_open: return
	var pages := maxi(1,ceili(_choices.size()/float(PAGE_SIZE)))
	var next := clampi(_page+direction,0,pages-1)
	if next==_page: return
	_page = next
	_cursor = 0
	_render()

func _run_choice(row: int) -> void:
	var index := _page*PAGE_SIZE+row
	if not is_open or index<0 or index>=_choices.size(): return
	var choice := _choices[index]
	var action: Variant = choice.get("call")
	if bool(choice.get("enabled",true)) and action is Callable and action.is_valid(): action.call()

func activate_selection() -> void:
	if not is_open or _active_buttons.is_empty(): return
	var button := _active_buttons[_cursor]
	if button.is_visible_in_tree() and not button.disabled: button.pressed.emit()

func back() -> void:
	if not is_open: return
	if _back_action.is_valid(): _back_action.call()
	else: close_menu()

func _input(event: InputEvent) -> void:
	if not is_open: return
	var handled := true
	if event is InputEventKey:
		if not event.pressed: return
		var code: int = event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if event.echo and code not in [KEY_UP,KEY_DOWN,KEY_W,KEY_S,KEY_LEFT,KEY_RIGHT,KEY_PAGEUP,KEY_PAGEDOWN]:
			get_viewport().set_input_as_handled()
			return
		match code:
			KEY_UP,KEY_W: navigate(-1)
			KEY_DOWN,KEY_S: navigate(1)
			KEY_LEFT: change_page(-1)
			KEY_RIGHT: change_page(1)
			KEY_ENTER,KEY_KP_ENTER,KEY_SPACE: activate_selection()
			KEY_ESCAPE,KEY_B: back()
			KEY_PAGEUP: _body_scroll.scroll_vertical -= 100
			KEY_PAGEDOWN: _body_scroll.scroll_vertical += 100
			KEY_F5: _save()
			_: handled = false
	elif event is InputEventJoypadButton:
		if not event.pressed: return
		match event.button_index:
			JOY_BUTTON_DPAD_UP: navigate(-1)
			JOY_BUTTON_DPAD_DOWN: navigate(1)
			JOY_BUTTON_DPAD_LEFT: change_page(-1)
			JOY_BUTTON_DPAD_RIGHT: change_page(1)
			JOY_BUTTON_A: activate_selection()
			JOY_BUTTON_B: back()
			_: handled = false
	elif event is InputEventJoypadMotion and event.axis==JOY_AXIS_LEFT_Y:
		_stick = event.axis_value
		if absf(_stick)<.3: _stick_armed = true
		elif _stick_armed and absf(_stick)>.6:
			_stick_armed = false
			_repeat = .35
			navigate(int(signf(_stick)))
	else: handled = false
	if handled: get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _stick_armed or absf(_stick)<=.6: return
	_repeat -= delta
	if _repeat<=0:
		_repeat = .12
		navigate(int(signf(_stick)))

func _save() -> void:
	if not is_instance_valid(services): return
	var world: Node = services.get("world")
	if not is_instance_valid(world): return
	var session: Node = world.get("inventory_session")
	if is_instance_valid(session) and session.has_method("save_checkpoint"):
		var saved: bool = session.save_checkpoint()
		set_status("Inventory, room and services saved." if saved else "Save failed; state remains in memory.",not saved)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_open: close_menu()
