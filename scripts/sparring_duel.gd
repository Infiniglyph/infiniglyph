extends CanvasLayer
## Explicit invitation, nonlethal rounds and one owner for duel cleanup.
const TALK_RANGE := 2.8
var player: CharacterBody3D
var partner: CharacterBody3D
var active := false
var dialogue_open := false
var selected_yes := false
var saved_health := 0.0
var result_time := 0.0
var result_text := ""
var panel: PanelContainer
var question: Label
var yes: Button
var no: Button
var hint: Label

func _ready() -> void:
	name = "SparringDuel"
	layer = 8
	player.sparring_duel = self
	player.controls.interaction_context = self
	partner.sparring_duel = self
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -95
	panel.offset_bottom = 95
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.008,0.012,0.018,1)
	background.border_color = Color(0.8,0.28,0.04)
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	background.content_margin_left = 24
	background.content_margin_right = 24
	background.content_margin_top = 20
	background.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel",background)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	panel.add_child(box)
	question = Label.new()
	question.text = "EMBER\nDo you want to fight?"
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.add_theme_font_size_override("font_size",24)
	question.modulate = Color(1,0.6,0.28)
	box.add_child(question)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation",24)
	box.add_child(buttons)
	yes = Button.new()
	yes.text = "Yes - let's spar"
	yes.custom_minimum_size = Vector2(195,44)
	buttons.add_child(yes)
	no = Button.new()
	no.text = "Not now"
	no.custom_minimum_size = Vector2(195,44)
	buttons.add_child(no)
	yes.pressed.connect(func(): answer(true))
	no.pressed.connect(func(): answer(false))
	add_child(panel)
	panel.hide()
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-300,-190)
	hint.custom_minimum_size.x = 600
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size",20)
	hint.modulate = Color(1,0.6,0.28)
	add_child(hint)

func can_talk() -> bool:
	if active or dialogue_open or player.dodge.active or not player.is_on_floor(): return false
	if player.global_position.distance_to(partner.global_position)>TALK_RANGE: return false
	var ray := PhysicsRayQueryParameters3D.create(player.combat_point(),partner.combat_point(),1,[player.get_rid(),partner.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func interact() -> void:
	if active:
		finish(false,"Round ended - you yielded.")
		return
	if not can_talk(): return
	dialogue_open = true
	player.controls.set_gameplay_enabled(false)
	player.weapon_combat.cancel()
	player.combat.reset()
	player.velocity = Vector3.ZERO
	player.target_lock.clear()
	panel.show()
	selected_yes = false
	no.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func answer(accepted: bool) -> void:
	if not dialogue_open: return
	dialogue_open = false
	panel.hide()
	player.controls.set_gameplay_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if accepted: start()

func start() -> void:
	if active or player.global_position.distance_to(partner.global_position)>TALK_RANGE+0.5: return
	active = true
	saved_health = player.weapon_combat.health
	player.weapon_combat.cancel()
	player.weapon_combat.health = player.weapon_combat.max_health
	player.add_to_group("combat_targets")
	player.set_collision_layer_value(2,true)
	partner.begin_duel()
	player.target_lock.select(partner)
	result_time = 0
	result_text = ""

func finish(player_won: bool, message: String = "") -> void:
	if not active: return
	# Close the damage gate before cancelling either actor (including inside a hit).
	active = false
	partner.return_home()
	player.dodge.cancel()
	player.target_lock.clear()
	player.controls.reset_combat_input()
	player.controls.consume_jump()
	player.controls.consume_dodge()
	player._jump_after_dodge = false
	player.combat.reset()
	player.weapon_combat.cancel()
	player.weapon_combat.clear_stagger()
	player.weapon_combat.psi_meter = 0
	player.weapon_combat.health = saved_health
	player.weapon_combat.parry_remaining = 0
	player.velocity = Vector3.ZERO
	player.fall_damage.reset()
	player.remove_from_group("combat_targets")
	player.set_collision_layer_value(2,false)
	result_text = message if message != "" else ("You win! Ember: Well fought. Again?" if player_won else "Ember wins. Ember: Ready for another round?")
	result_time = 5
	player.weapon_combat.changed.emit()

func _process(delta: float) -> void:
	result_time = maxf(0,result_time-delta)
	if dialogue_open:
		hint.text = "Left / Right: choose   Enter / A: answer   Escape / B: cancel"
		if player.global_position.distance_to(partner.global_position)>TALK_RANGE+1: answer(false)
	elif active:
		hint.text = "SPARRING  |  Ember %d / %d HP  |  G: yield  /  START: system menu" % [ceili(partner.health),ceili(partner.weapon_combat.max_health)]
		if player.global_position.distance_to(partner.home)>60: finish(false,"Round ended - outside the sparring area.")
	elif result_time>0: hint.text = result_text
	else: hint.text = "G / RT: talk to Ember" if can_talk() else ""
	if player.controls.get("interaction_context") == self and player.controls.has_method("consume_interaction") and player.controls.consume_interaction(): interact()

func _input(event: InputEvent) -> void:
	if not dialogue_open: return
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code in [KEY_LEFT,KEY_RIGHT,KEY_TAB]:
			selected_yes = not selected_yes
			(yes if selected_yes else no).grab_focus()
		elif code in [KEY_ENTER,KEY_SPACE]: answer(yes.has_focus())
		elif code == KEY_ESCAPE: answer(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT:
				selected_yes = not selected_yes
				(yes if selected_yes else no).grab_focus()
			JOY_BUTTON_A: answer(yes.has_focus())
			JOY_BUTTON_B,JOY_BUTTON_BACK: answer(false)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if dialogue_open: answer(false)
		if active: finish(false,"Round ended - talk to Ember to spar again.")
