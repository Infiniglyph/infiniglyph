extends Node
signal special_hold_cancelled(token: StringName)
var gameplay_enabled := true
var interaction_requested := false
var interaction_context: Node
var _rt_interaction_latched := false
var _resume_triggers := {JOY_AXIS_TRIGGER_LEFT:false,JOY_AXIS_TRIGGER_RIGHT:false}
var _held_specials: Dictionary = {}
## Right-stick camera motion becomes one directional target request per flick.
var move := Vector2.ZERO
var look := Vector2.ZERO
var jump_requested := false
var dodge_requested := false
var sprint := false
var boost := false
var _boost_had_movement := false
var mouse_look := Vector2.ZERO
@export var stick_deadzone := 0.18
const TRIGGER_PRESS := 0.55
const TRIGGER_RELEASE := 0.40
const SHEATHE_HOLD_TIME := 0.45
const WEAPON_KEYS := {KEY_DOWN:&"down",KEY_LEFT:&"left",KEY_RIGHT:&"right",KEY_UP:&"up"}
const WEAPON_BUTTONS := {JOY_BUTTON_DPAD_DOWN:&"down",JOY_BUTTON_DPAD_LEFT:&"left",JOY_BUTTON_DPAD_RIGHT:&"right",JOY_BUTTON_DPAD_UP:&"up"}
var _combat_requests: Array[Dictionary] = []
var _combat_keys: Dictionary = {}
var _combat_buttons: Dictionary = {}
var _combat_mouse: Dictionary = {}
var _keyboard_block := false
var _keyboard_modifier := false
var _pad_block := false
var _pad_modifier := false
var _combat_pad := -1
var _down_sources: Dictionary = {}
var _down_elapsed := 0.0
var _down_fired := false
var _down_cancelled := false
var _lock_requests: Array[Dictionary] = []
var _flick_armed := true
const TARGET_KEYS := {KEY_J:Vector2.LEFT,KEY_L:Vector2.RIGHT,KEY_I:Vector2.UP,KEY_K:Vector2.DOWN}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _unhandled_input(event: InputEvent) -> void:
	if not gameplay_enabled: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_look += event.relative
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		if event.keycode == KEY_SPACE: jump_requested = true
		if event.keycode == KEY_CTRL: toggle_boost()
		if event.physical_keycode == KEY_E or event.keycode == KEY_E: dodge_requested = true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var was_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not was_captured: return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		jump_requested = true
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_LEFT_STICK:
		toggle_boost()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		dodge_requested = true
	_combat_input(event)

func sample() -> void:
	if not gameplay_enabled:
		move = Vector2.ZERO
		look = Vector2.ZERO
		mouse_look = Vector2.ZERO
		sprint = false
		return
	move = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	look = Vector2.ZERO
	sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var id := pads[0]
		move += filtered(Vector2(Input.get_joy_axis(id,JOY_AXIS_LEFT_X),Input.get_joy_axis(id,JOY_AXIS_LEFT_Y)))
		look = filtered(Vector2(Input.get_joy_axis(id,JOY_AXIS_RIGHT_X),Input.get_joy_axis(id,JOY_AXIS_RIGHT_Y)))
		sample_target_flick(look,id)
		_combat_pad = id
		var left_value := Input.get_joy_axis(id,JOY_AXIS_TRIGGER_LEFT)
		_pad_block = trigger_held(left_value,_pad_block) if trigger_released(JOY_AXIS_TRIGGER_LEFT,left_value) else false
		set_right_trigger(Input.get_joy_axis(id,JOY_AXIS_TRIGGER_RIGHT))
		# Full analog deflection runs; partial deflection walks.
		sprint = sprint or move.length() > 0.72
	move = move.limit_length()
	if boost and move.length() > 0.05: _boost_had_movement = true
	elif _boost_had_movement:
		boost = false
		_boost_had_movement = false
	if pads.is_empty(): sample_target_flick(Vector2.ZERO)

func sample_target_flick(stick: Vector2, device: int = -1) -> void:
	if stick.length()<0.25:
		_flick_armed = true
	elif _flick_armed and stick.length()>=0.65:
		_flick_armed = false
		var direction := Vector2(signf(stick.x),0) if absf(stick.x)>=absf(stick.y) else Vector2(0,signf(stick.y))
		_lock_requests.append({"direction":direction,"device":device})

func consume_lock_requests() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for request in _lock_requests: result.append(request.direction)
	_lock_requests.clear()
	return result

func toggle_boost() -> void:
	boost = not boost
	_boost_had_movement = false

func filtered(value: Vector2) -> Vector2:
	var length := value.length()
	if length < stick_deadzone: return Vector2.ZERO
	return value.normalized() * minf(1.0,(length-stick_deadzone)/(1.0-stick_deadzone))

func consume_jump() -> bool:
	var value := jump_requested
	jump_requested = false
	return value

func consume_dodge() -> bool:
	var value := dodge_requested
	dodge_requested = false
	return value

func is_blocking() -> bool:
	return _keyboard_block or _pad_block

func special_modified() -> bool:
	return _keyboard_modifier or _pad_modifier

func trigger_held(value: float, held: bool) -> bool:
	return value > TRIGGER_RELEASE if held else value >= TRIGGER_PRESS

func set_right_trigger(value: float) -> void:
	if not trigger_released(JOY_AXIS_TRIGGER_RIGHT,value): return
	if value<=TRIGGER_RELEASE: _rt_interaction_latched = false
	var held := trigger_held(value,_pad_modifier)
	var fresh := held and not _pad_modifier
	_pad_modifier = held
	if fresh and not _rt_interaction_latched and is_instance_valid(interaction_context) and interaction_context.can_talk():
		_rt_interaction_latched = true
		interaction_requested = true

func consume_combat_requests() -> Array[Dictionary]:
	var requests := _combat_requests
	_combat_requests = []
	return requests

func _request(kind: StringName, value: StringName, device: int = -1) -> void:
	_combat_requests.append({"kind":kind,"value":value,"device":device})

func consume_interaction() -> bool:
	var result := interaction_requested
	interaction_requested = false
	return result

func trigger_released(axis: int, value: float) -> bool:
	# LT/RT navigate categories in the menu. Require a neutral trigger before
	# returning to guard/modifier/interaction after a UI closes.
	if _resume_triggers[axis] and value<=TRIGGER_RELEASE: _resume_triggers[axis] = false
	return not _resume_triggers[axis]

func set_gameplay_enabled(enabled: bool) -> void:
	gameplay_enabled = enabled
	if not enabled:
		_resume_triggers[JOY_AXIS_TRIGGER_LEFT] = true
		_resume_triggers[JOY_AXIS_TRIGGER_RIGHT] = true
	reset_combat_input()
	jump_requested = false
	dodge_requested = false
	interaction_requested = false
	move = Vector2.ZERO
	look = Vector2.ZERO
	mouse_look = Vector2.ZERO
	boost = false

func _special(button: StringName, device: int = -1, pressed: bool = true) -> void:
	# Resolve the modifier on the face-button press. A combo emits only its own
	# command, never both the base special and the modified one.
	var token := StringName("%d:%s" % [device,button])
	if pressed:
		if _held_specials.has(token): return
		var action := StringName("special_rt_"+button if special_modified() else "special_"+button)
		_held_specials[token] = device
		_combat_requests.append({"kind":&"special_press","value":action,"token":token,"device":device})
	elif _held_specials.has(token):
		_held_specials.erase(token)
		_request(&"special_release",token,device)

func _press_down(device: int) -> void:
	if _down_sources.is_empty():
		_down_elapsed = 0
		_down_fired = false
		_down_cancelled = false
	_down_sources[device] = true

func _release_down(device: int) -> void:
	if not _down_sources.has(device): return
	_down_sources.erase(device)
	if _down_sources.is_empty() and not _down_fired and not _down_cancelled:
		_request(&"weapon",&"down",device)

func update_combat_hold(delta: float) -> void:
	if _down_sources.is_empty() or _down_fired or _down_cancelled: return
	_down_elapsed += delta
	if _down_elapsed >= SHEATHE_HOLD_TIME:
		_down_fired = true
		_request(&"sheathe",&"",int(_down_sources.keys()[0]))

func _combat_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code not in [KEY_F,KEY_V,KEY_Q,KEY_R,KEY_TAB,KEY_G] and not WEAPON_KEYS.has(code) and not TARGET_KEYS.has(code): return
		if event.echo: return
		var fresh: bool = event.pressed and not _combat_keys.has(code)
		if event.pressed: _combat_keys[code] = true
		else: _combat_keys.erase(code)
		if code == KEY_F: _keyboard_block = event.pressed
		if code == KEY_V: _keyboard_modifier = event.pressed
		if code == KEY_DOWN:
			if fresh: _press_down(-1)
			elif not event.pressed: _release_down(-1)
			return
		if code in [KEY_Q,KEY_R]:
			if fresh or not event.pressed: _special(&"x" if code == KEY_Q else &"y",-1,event.pressed)
			return
		if not fresh: return
		if code == KEY_TAB:
			_lock_requests.append({"direction":Vector2.ZERO,"device":-1})
			_flick_armed = false
		elif TARGET_KEYS.has(code): _lock_requests.append({"direction":TARGET_KEYS[code],"device":-1})
		elif code == KEY_G: interaction_requested = true
		elif WEAPON_KEYS.has(code):
			_down_cancelled = true
			_request(&"weapon",WEAPON_KEYS[code])
	elif event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return
		var fresh: bool = event.pressed and not _combat_mouse.has(event.button_index)
		if event.pressed: _combat_mouse[event.button_index] = true
		else: _combat_mouse.erase(event.button_index)
		if fresh and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_request(&"action",&"attack_left" if event.button_index == MOUSE_BUTTON_LEFT else &"attack_right")
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var pads := Input.get_connected_joypads()
		if not pads.is_empty() and event.device != pads[0]: return
		_combat_pad = event.device
		if event is InputEventJoypadMotion:
			if event.axis == JOY_AXIS_TRIGGER_LEFT and trigger_released(event.axis,event.axis_value): _pad_block = trigger_held(event.axis_value,_pad_block)
			if event.axis == JOY_AXIS_TRIGGER_RIGHT: set_right_trigger(event.axis_value)
			return
		var fresh: bool = event.pressed and not _combat_buttons.has(event.button_index)
		if event.pressed: _combat_buttons[event.button_index] = true
		else: _combat_buttons.erase(event.button_index)
		if event.button_index == JOY_BUTTON_DPAD_DOWN:
			if fresh: _press_down(event.device)
			elif not event.pressed: _release_down(event.device)
			return
		if event.button_index in [JOY_BUTTON_X,JOY_BUTTON_Y]:
			if fresh or not event.pressed: _special(&"x" if event.button_index == JOY_BUTTON_X else &"y",event.device,event.pressed)
			return
		if not fresh: return
		match event.button_index:
			JOY_BUTTON_RIGHT_STICK:
				_lock_requests.append({"direction":Vector2.ZERO,"device":event.device})
				_flick_armed = false
			JOY_BUTTON_RIGHT_SHOULDER: _request(&"action",&"attack_right",event.device)
			JOY_BUTTON_LEFT_SHOULDER: _request(&"action",&"attack_left",event.device)
			_:
				if WEAPON_BUTTONS.has(event.button_index):
					_down_cancelled = true
					_request(&"weapon",WEAPON_BUTTONS[event.button_index],event.device)

func reset_combat_input() -> void:
	_held_specials.clear()
	special_hold_cancelled.emit(&"")
	_lock_requests.clear()
	_flick_armed = false
	_combat_requests.clear()
	_combat_keys.clear()
	_combat_buttons.clear()
	_combat_mouse.clear()
	_keyboard_block = false
	_keyboard_modifier = false
	_pad_block = false
	_pad_modifier = false
	_down_sources.clear()
	_down_elapsed = 0
	_down_fired = false
	_down_cancelled = false

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or device != _combat_pad: return
	_rt_interaction_latched = false
	for token: StringName in _held_specials.keys():
		if _held_specials[token] == device:
			_held_specials.erase(token)
			special_hold_cancelled.emit(token)
	_pad_block = false
	_pad_modifier = false
	_combat_buttons.clear()
	_down_sources.erase(device)
	_combat_requests = _combat_requests.filter(func(request: Dictionary) -> bool: return request.device != device)
	_lock_requests = _lock_requests.filter(func(request: Dictionary) -> bool: return request.device != device)
	_flick_armed = false
	_combat_pad = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_combat_input()
