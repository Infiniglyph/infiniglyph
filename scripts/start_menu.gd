extends CanvasLayer
## Live system overlay: it gates local input and never pauses the scene tree.
signal quit_requested
var actor: CharacterBody3D
var session: Node
var is_open := false
var settings_open := false
var persist_settings := true
var settings_path := "user://settings_v1.cfg"
var _previous_mouse := Input.MOUSE_MODE_CAPTURED
var _screen: Control
var _home: PanelContainer
var _settings: PanelContainer
var _status: Label
var _focus_controls: Array[Control] = []
var _home_controls: Array[Control] = []
var _settings_controls: Array[Control] = []
var _yield_button: Button
var _stick := Vector2.ZERO
var _stick_armed := true
var _repeat_clock := 0.0
var _mouse: HSlider
var _stick_speed: HSlider
var _fov: HSlider
var _volume: HSlider
var _shake: CheckBox
var _shadows: HSlider
var _glow: HSlider
var _resolution: HSlider

func _ready() -> void:
	name = "StartMenu"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	persist_settings = not "--script" in OS.get_cmdline_args()
	_build()
	_screen.hide()
	set_process(false)
	if persist_settings: load_settings()

func _frame() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.003,0.018,0.025,0.97)
	style.border_color = Color(0.08,0.8,0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(20)
	return style

func _label(value: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color(0.85,0.97,1))
	return label

func _panel(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -235
	panel.offset_right = 235
	panel.offset_top = -275
	panel.offset_bottom = 275
	panel.add_theme_stylebox_override("panel",_frame())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	panel.add_child(box)
	var heading := _label(title,24)
	heading.modulate = Color(0.1,0.95,1)
	box.add_child(heading)
	box.add_child(_label("WORLD LIVE  /  Game keeps running",14))
	_screen.add_child(panel)
	return panel

func _button(box: VBoxContainer, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 46
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size",20)
	var normal := _frame()
	normal.bg_color = Color(0.005,0.035,0.045)
	normal.border_color = Color(0.08,0.3,0.36)
	button.add_theme_stylebox_override("normal",normal)
	var focus := _frame()
	focus.bg_color = Color(0.015,0.12,0.15)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus",focus)
	button.add_theme_stylebox_override("hover",focus)
	button.pressed.connect(action)
	box.add_child(button)
	return button

func _slider(box: VBoxContainer, title: String, minimum: float, maximum: float, step_value: float, initial: float, action: Callable) -> HSlider:
	var label := _label(title,16)
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.value = initial
	slider.custom_minimum_size.y = 24
	slider.value_changed.connect(action)
	var update_label := func(value: float):
		label.text = title+"  "+(("%.4f" % value) if step_value<0.001 else (("%.1f" % value) if step_value<1 else ("%.0f" % value)))
	slider.value_changed.connect(update_label)
	update_label.call(initial)
	slider.focus_entered.connect(func(): label.modulate = Color(0.12,0.95,1))
	slider.focus_exited.connect(func(): label.modulate = Color.WHITE)
	box.add_child(slider)
	_settings_controls.append(slider)
	return slider

func _build() -> void:
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	var shade := ColorRect.new()
	shade.color = Color(0,0.006,0.01,0.58)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(shade)
	_home = _panel("INFINIGLYPH  /  SYSTEM")
	var box := _home.get_child(0) as VBoxContainer
	_home_controls.append(_button(box,"Resume",close_menu))
	_home_controls.append(_button(box,"Settings",show_settings))
	_home_controls.append(_button(box,"Unstick",recover_player))
	_yield_button = _button(box,"Yield sparring duel",yield_duel)
	_home_controls.append(_yield_button)
	_home_controls.append(_button(box,"Quit Game",quit_game))
	_status = _label("",16)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 52
	_status.modulate = Color(1,0.58,0.22)
	box.add_child(_status)
	box.add_child(_label("START / ESC: back   A / ENTER: select",13))
	_settings = _panel("SETTINGS")
	box = _settings.get_child(0) as VBoxContainer
	box.add_theme_constant_override("separation",9)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.anchor_left = 0.25
	_settings.anchor_right = 0.75
	_settings.anchor_top = 0.04
	_settings.anchor_bottom = 0.96
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var settings_box := VBoxContainer.new()
	settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_box.add_theme_constant_override("separation",9)
	scroll.add_child(settings_box)
	var outer_box := box
	box = settings_box
	_mouse = _slider(box,"Mouse look sensitivity",0.0005,0.006,0.0001,actor.camera_rig.mouse_sensitivity,func(value: float): actor.camera_rig.mouse_sensitivity = value)
	_stick_speed = _slider(box,"Controller look sensitivity",0.5,5,0.1,actor.camera_rig.stick_sensitivity,func(value: float): actor.camera_rig.stick_sensitivity = value)
	_fov = _slider(box,"Field of view",60,95,1,actor.camera_rig.camera.fov,func(value: float): actor.camera_rig.camera.fov = value)
	_volume = _slider(box,"Master volume",0,100,1,100,func(value: float):
		AudioServer.set_bus_mute(0,value<=0)
		AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,value/100))))
	_shake = CheckBox.new()
	_shake.text = "Camera impact shake"
	_shake.button_pressed = actor.weapon_combat.rules.camera_shake_enabled
	_shake.add_theme_font_size_override("font_size",18)
	_shake.toggled.connect(func(value: bool): actor.weapon_combat.rules.camera_shake_enabled = value)
	box.add_child(_shake)
	_settings_controls.append(_shake)
	var graphics: Node = get_parent().graphics
	box.add_child(_label("GRAPHICS",20))
	_shadows = _slider(box,"Maximum nearby streetlight shadows",0,16,1,graphics.shadow_budget,func(value: float):
		graphics.shadow_budget = int(value)
		graphics.apply_quality())
	_glow = _slider(box,"Neon glow",0,2,1,graphics.glow_quality,func(value: float):
		graphics.glow_quality = int(value)
		graphics.apply_quality())
	var glow_label: Label = box.get_child(box.get_child_count()-2)
	var glow_text := func(value: float): glow_label.text = "Neon glow  "+["Off","Soft","Full"][int(value)]
	_glow.value_changed.connect(glow_text)
	glow_text.call(_glow.value)
	_resolution = _slider(box,"3D resolution (%)",50,100,5,graphics.resolution_percent,func(value: float):
		graphics.resolution_percent = int(value)
		graphics.apply_quality())
	box.add_child(_label("Lower 3D resolution improves speed; UI stays sharp.",13))
	box = outer_box
	_settings_controls.append(_button(box,"Back",show_home))
	box.add_child(_label("LEFT / RIGHT: adjust   B / ESC: back",13))
	_settings.hide()

func open_menu() -> void:
	if is_open: return
	if session.ui.is_open: session.ui.close_menu()
	if session.duel.dialogue_open: session.duel.answer(false)
	if is_instance_valid(session.boss_encounter) and session.boss_encounter.dialogue_open: session.boss_encounter.answer(false)
	_previous_mouse = Input.mouse_mode
	is_open = true
	set_process(true)
	actor.controls.set_gameplay_enabled(false)
	actor.weapon_combat.cancel()
	actor.combat.reset()
	actor._jump_after_dodge = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_screen.show()
	_status.text = ""
	show_home()

func close_menu() -> void:
	if not is_open: return
	save_settings()
	is_open = false
	set_process(false)
	_screen.hide()
	actor.controls.set_gameplay_enabled(true)
	Input.mouse_mode = _previous_mouse
	_stick = Vector2.ZERO
	_stick_armed = true

func show_home() -> void:
	settings_open = false
	_settings.hide()
	_home.show()
	_yield_button.visible = session.duel.active
	_focus_controls = []
	for control: Control in _home_controls:
		if control.visible: _focus_controls.append(control)
	_focus_controls[0].grab_focus()
	if is_open: save_settings()

func show_settings() -> void:
	settings_open = true
	_home.hide()
	_settings.show()
	_focus_controls = _settings_controls.duplicate()
	_focus_controls[0].grab_focus()

func recover_player() -> void:
	var result: Dictionary = actor.unstuck.recover()
	if result.ok:
		close_menu()
		session.show_notice(result.message)
	else: _status.text = result.message

func yield_duel() -> void:
	if session.duel.active: session.duel.interact()
	close_menu()

func quit_game() -> void:
	save_settings()
	if session.persistence_enabled and not session.networked(): session.save_checkpoint()
	quit_requested.emit()
	get_tree().quit()

func _back() -> void:
	if settings_open: show_home()
	else: close_menu()

func _navigate(direction: Vector2) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if direction.x!=0 and focused is Range:
		focused.value = clampf(focused.value+direction.x*focused.step,focused.min_value,focused.max_value)
	elif direction.y!=0 and not _focus_controls.is_empty():
		var index := _focus_controls.find(focused)
		_focus_controls[posmod(index+int(direction.y),_focus_controls.size())].grab_focus()

func _accept() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is BaseButton:
		if focused.toggle_mode: focused.button_pressed = not focused.button_pressed
		focused.pressed.emit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("system_menu_toggle") and not event.is_echo():
		if event is InputEventKey and is_instance_valid(session.boss_encounter) and session.boss_encounter.dialogue_open:
			session.boss_encounter.answer(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and session.ui.is_open: return
		get_viewport().set_input_as_handled()
		if is_open: _back()
		else: open_menu()
		return
	if not is_open: return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		match event.physical_keycode if event.physical_keycode!=0 else event.keycode:
			KEY_UP,KEY_W: _navigate(Vector2.UP)
			KEY_DOWN,KEY_S: _navigate(Vector2.DOWN)
			KEY_LEFT,KEY_A: _navigate(Vector2.LEFT)
			KEY_RIGHT,KEY_D: _navigate(Vector2.RIGHT)
			KEY_ENTER,KEY_SPACE: _accept()
			KEY_ESCAPE: _back()
	elif event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		match event.button_index:
			JOY_BUTTON_DPAD_UP: _navigate(Vector2.UP)
			JOY_BUTTON_DPAD_DOWN: _navigate(Vector2.DOWN)
			JOY_BUTTON_DPAD_LEFT: _navigate(Vector2.LEFT)
			JOY_BUTTON_DPAD_RIGHT: _navigate(Vector2.RIGHT)
			JOY_BUTTON_A: _accept()
			JOY_BUTTON_B: _back()
	elif event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		if event.axis==JOY_AXIS_LEFT_X: _stick.x = event.axis_value
		if event.axis==JOY_AXIS_LEFT_Y: _stick.y = event.axis_value
		if _stick.length()<0.3: _stick_armed = true
		elif _stick_armed and _stick.length()>0.6:
			_stick_armed = false
			_repeat_clock = 0.35
			_navigate(Vector2(signf(_stick.x),0) if absf(_stick.x)>absf(_stick.y) else Vector2(0,signf(_stick.y)))

func _process(delta: float) -> void:
	if _stick_armed or _stick.length()<0.6: return
	_repeat_clock -= delta
	if _repeat_clock<=0:
		_repeat_clock = 0.12
		_navigate(Vector2(signf(_stick.x),0) if absf(_stick.x)>absf(_stick.y) else Vector2(0,signf(_stick.y)))

func save_settings(path: String = "") -> bool:
	if not persist_settings and path.is_empty(): return false
	var config := ConfigFile.new()
	config.set_value("meta","version",1)
	config.set_value("camera","mouse",_mouse.value)
	config.set_value("camera","stick",_stick_speed.value)
	config.set_value("camera","fov",_fov.value)
	config.set_value("camera","shake",_shake.button_pressed)
	config.set_value("audio","volume",_volume.value)
	config.set_value("graphics","shadows",_shadows.value)
	config.set_value("graphics","glow",_glow.value)
	config.set_value("graphics","resolution",_resolution.value)
	return config.save(path if not path.is_empty() else settings_path)==OK

func load_settings(path: String = "") -> bool:
	var config := ConfigFile.new()
	if config.load(path if not path.is_empty() else settings_path)!=OK: return false
	if config.get_value("meta","version",1)!=1: return false
	for entry: Array in [[_mouse,"camera","mouse"],[_stick_speed,"camera","stick"],[_fov,"camera","fov"],[_volume,"audio","volume"],[_shadows,"graphics","shadows"],[_glow,"graphics","glow"],[_resolution,"graphics","resolution"]]:
		var value: Variant = config.get_value(entry[1],entry[2],entry[0].value)
		if (value is float or value is int) and is_finite(float(value)): entry[0].value = clampf(value,entry[0].min_value,entry[0].max_value)
	var shake: Variant = config.get_value("camera","shake",true)
	if shake is bool: _shake.button_pressed = shake
	return true

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_open: close_menu()
