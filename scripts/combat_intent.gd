extends Node
## Ordered combat input contract. WeaponCombat resolves requests into timed moves.
signal action_requested(action: StringName, weapon_slot: StringName)
signal weapon_slot_selected(slot: StringName)
signal block_changed(held: bool)
signal sheathed_changed(sheathed: bool)
signal changed
signal charge_started(action: StringName, weapon_slot: StringName)
const CHARGE_MIN := 0.4
const CHARGE_FULL := 1.2
var charge_action: StringName = &""
var charge_slot: StringName = &"down"
var charge_token: StringName = &""
var charge_elapsed := 0.0
var released_charge := 0.0
const SLOTS := [&"down",&"left",&"right",&"up"]
const ACTIONS := [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
var selected_slot: StringName = &"down"
var blocking := false
var permission: Callable
var loadout_resolver: Callable
var fresh_block := true
var _held_last_poll := false
var sheathed := false
var last_action: StringName = &""
var last_action_slot: StringName = &"down"

func resolve_slot(slot: StringName) -> StringName:
	return StringName(loadout_resolver.call(slot)) if loadout_resolver.is_valid() else slot

func has_weapon(slot: StringName) -> bool:
	return resolve_slot(slot) != &""

func refresh_equipment() -> void:
	cancel_charge()
	if not has_weapon(selected_slot):
		if blocking:
			blocking = false
			block_changed.emit(false)
		sheathed = true
	weapon_slot_selected.emit(selected_slot)
	changed.emit()

func advance_charge(delta: float) -> void:
	if charge_action != &"": charge_elapsed = minf(CHARGE_FULL,charge_elapsed+delta)

func charge_strength() -> float:
	if charge_action == &"" or charge_elapsed<CHARGE_MIN: return 0
	return lerpf(0.25,1.0,clampf((charge_elapsed-CHARGE_MIN)/(CHARGE_FULL-CHARGE_MIN),0,1))

func cancel_charge(token: StringName = &"") -> void:
	if token != &"" and token != charge_token: return
	charge_action = &""
	charge_token = &""
	charge_elapsed = 0
	changed.emit()

func poll(controls: Node) -> void:
	var held: bool = controls.is_blocking() if controls.has_method("is_blocking") else false
	held = held and has_weapon(selected_slot)
	fresh_block = held and not _held_last_poll
	_held_last_poll = held
	var allowed := not permission.is_valid() or bool(permission.call())
	if not allowed:
		blocking = false
		cancel_charge()
		if controls.has_method("consume_combat_requests"): controls.consume_combat_requests()
		return
	if held != blocking:
		blocking = held
		block_changed.emit(blocking)
		changed.emit()
	if not controls.has_method("consume_combat_requests"): return
	for request: Dictionary in controls.consume_combat_requests():
		if request.kind == &"special_press":
			if not request.value in ACTIONS: continue
			if not has_weapon(selected_slot): continue
			cancel_charge()
			if sheathed:
				sheathed = false
				sheathed_changed.emit(false)
			charge_action = request.value
			charge_slot = selected_slot
			charge_token = request.token
			charge_started.emit(charge_action,charge_slot)
		elif request.kind == &"special_release":
			if charge_action == &"" or request.value != charge_token: continue
			var action := charge_action
			var slot := charge_slot
			released_charge = charge_strength()
			cancel_charge()
			last_action = action
			last_action_slot = slot
			action_requested.emit(action,slot)
			released_charge = 0
		elif request.kind == &"weapon":
			if not SLOTS.has(request.value): continue
			cancel_charge()
			selected_slot = request.value
			if sheathed and has_weapon(selected_slot):
				sheathed = false
				sheathed_changed.emit(false)
			if not has_weapon(selected_slot): sheathed = true
			weapon_slot_selected.emit(selected_slot)
		elif request.kind == &"sheathe":
			if not has_weapon(selected_slot): continue
			cancel_charge()
			sheathed = not sheathed
			sheathed_changed.emit(sheathed)
		elif request.kind == &"action" and request.value in ACTIONS:
			if not has_weapon(selected_slot): continue
			cancel_charge()
			# Draw first, then dispatch this same input against the current slot.
			# No synthetic selection event: drawing must not switch the loadout.
			if sheathed:
				sheathed = false
				sheathed_changed.emit(false)
			last_action = request.value
			last_action_slot = selected_slot
			action_requested.emit(last_action,last_action_slot)
		changed.emit()

func reset() -> void:
	_held_last_poll = false
	cancel_charge()
	if blocking:
		blocking = false
		block_changed.emit(false)
	last_action = &""
	changed.emit()
