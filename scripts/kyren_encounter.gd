extends CanvasLayer
## Optional, owner-scoped encounter. All damage and movement stay in shared combat.
const Journal = preload("res://scripts/encounter_progress.gd")
const Progress = preload("res://scripts/kyren_progress.gd")
const Salt = preload("res://scripts/kyren_salt.gd")
const Dialogue = preload("res://scripts/kyren_dialogue.gd")
const Debug = preload("res://scripts/kyren_debug.gd")
const REWARDS: Array[StringName] = [&"kyren_hat",&"kyren_scarf",&"kyren_katana"]
var reward_rng := RandomNumberGenerator.new()
@export var persistence_enabled := true
@export var debug_enabled := false
@export var save_path := "user://encounters_v1.json"
@export var disengage_seconds := 12.0
var player: CharacterBody3D
var boss: CharacterBody3D
var home: Node3D
var active := false
var dialogue_open := false
var progress: Dictionary = Progress.fresh()
var salt := Salt.new()
var dialogue := Dialogue.new()
var panel: PanelContainer
var yes: Button
var no: Button
var subtitle: Label
var bar_root: Control
var health_bar: ProgressBar
var strain_bar: ProgressBar
var salt_label: Label
var _mouse := Input.MOUSE_MODE_CAPTURED
var _check_clock := 0.0
var _save_clock := 0.0
var _unseen := 0.0
var _greeted := false
var _damaged := false
var _starter_only := true
var _landed := false
var _patterns: Dictionary = {}
var _jumps: Array[float] = []
var _environment_serial := -1
var _last_technique := ""
var _pattern_serial := ""
var _repetitions := 0
var _last_salt_state: StringName = &"smug"

func networked() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer!=null and not peer is OfflineMultiplayerPeer

func has_authority() -> bool: return not networked() or multiplayer.is_server()

func _ready() -> void:
	name="KyrenEncounter"
	layer=5
	reward_rng.randomize()
	persistence_enabled=persistence_enabled and not "--script" in OS.get_cmdline_args() and not networked()
	debug_enabled=OS.is_debug_build() and (debug_enabled or "--kyren-debug" in OS.get_cmdline_user_args())
	add_child(salt)
	add_child(dialogue)
	boss.opponent=player
	boss.controls.opponent=player
	boss.encounter=self
	player.kyren_encounter=self
	salt.reaction.connect(_reaction)
	player.weapon_combat.contact_resolved.connect(_player_contact)
	boss.weapon_combat.contact_resolved.connect(_boss_contact)
	player.weapon_combat.attack_started.connect(_observed_attack)
	player.weapon_combat.attack_finished.connect(_player_finished)
	boss.weapon_combat.attack_finished.connect(_boss_finished)
	player.weapon_combat.environment_contact.connect(_environment)
	player.air_stepped.connect(_sky_jump)
	_build_ui()
	if persistence_enabled: load_checkpoint()
	if debug_enabled:
		var debugger := Debug.new()
		debugger.encounter=self
		add_child(debugger)

func _other_encounter() -> bool:
	return (is_instance_valid(player.boss_encounter) and (player.boss_encounter.active or player.boss_encounter.dialogue_open)) or (is_instance_valid(player.sparring_duel) and (player.sparring_duel.active or player.sparring_duel.dialogue_open))

func can_talk() -> bool:
	if not has_authority() or active or _other_encounter() or player.health<=0 or boss.state==&"defeated": return false
	if is_instance_valid(player.world_actions) and player.world_actions.attached(): return false
	return player.global_position.distance_to(boss.global_position)<5.0 and boss.controls.can_see()

func interact() -> void:
	if dialogue_open or not can_talk() or not player.controls.gameplay_enabled: return
	dialogue_open=true
	_mouse=Input.mouse_mode
	player.controls.set_gameplay_enabled(false)
	player.weapon_combat.cancel()
	player.combat.reset()
	player._jump_after_dodge=false
	panel.show()
	no.grab_focus()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	dialogue.say(&"challenge",salt.value,context(),true)

func answer(accepted: bool) -> void:
	if not dialogue_open: return
	dialogue_open=false
	panel.hide()
	player.controls.set_gameplay_enabled(true)
	Input.mouse_mode=_mouse
	if accepted: start()

func _input(event: InputEvent) -> void:
	if not dialogue_open: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode if event.physical_keycode else event.keycode:
			KEY_LEFT,KEY_RIGHT,KEY_TAB: (no if yes.has_focus() else yes).grab_focus()
			KEY_ENTER,KEY_SPACE: answer(yes.has_focus())
			KEY_ESCAPE: answer(false)
			_: return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT: (no if yes.has_focus() else yes).grab_focus()
			JOY_BUTTON_A: answer(yes.has_focus())
			JOY_BUTTON_B,JOY_BUTTON_BACK: answer(false)
			_: return
		get_viewport().set_input_as_handled()

func start(aggression: bool = false) -> bool:
	if not has_authority() or active or _other_encounter() or player.health<=0 or boss.state==&"defeated": return false
	if not aggression and not can_talk(): return false
	if dialogue_open: answer(false)
	active=true
	progress.kyren.challenges+=1
	_damaged=false
	_starter_only=true
	_landed=false
	_patterns.clear()
	_jumps.clear()
	_last_technique=""
	_pattern_serial=""
	_repetitions=0
	_unseen=0
	salt.begin()
	_last_salt_state=salt.state()
	boss.weapon_combat.reset()
	boss.wake()
	player.set_collision_layer_value(2,true)
	player.add_to_group("combat_targets")
	if persistence_enabled: save_checkpoint()
	return true

func _release() -> void:
	player.set_collision_layer_value(2,false)
	player.remove_from_group("combat_targets")
	if player.target_lock.opponent==boss: player.target_lock.clear()
	player.weapon_combat.cancel()
	player.combat.blocking=false

func finish(player_won: bool) -> void:
	if not has_authority() or not active: return
	active=false # Lethal callbacks occur inside the shared multihit resolver.
	var defeat_position := boss.global_position
	_release()
	var previously_lost: bool = progress.wins>0
	if not progress.intro_completed:
		progress.intro_completed=true
		progress.first_victory=player_won
		progress.first_outcome="victory" if player_won else "defeat"
	progress["wins" if player_won else "losses"]+=1
	progress.last_outcome="victory" if player_won else "defeat"
	progress.kyren.consecutive_defeats=int(progress.kyren.consecutive_defeats)+1 if player_won else 0
	salt.end(player_won,int(progress.kyren.consecutive_defeats),int(progress.wins))
	var pattern := ""
	var most := 0
	for key: String in _patterns:
		if int(_patterns[key])>most:
			most=int(_patterns[key])
			pattern=key
	progress.kyren.pattern=pattern
	var rare: Array[String] = []
	if player_won:
		if progress.kyren.consecutive_defeats>=3 and not progress.kyren.three_defeats_seen:
			progress.kyren.three_defeats_seen=true
			rare.append_array(["three_defeats_first","three_defeats_second"])
		if not _damaged: rare.append("perfect_victory")
		if _landed and _starter_only:
			for line: Dictionary in dialogue.lines:
				if "starter_victory" in line.triggers:
					rare.append(line.id)
					break
	elif previously_lost: rare.append("revenge_victory")
	if rare.is_empty(): dialogue.say(&"defeat" if player_won else &"victory",salt.value,{"opening":true},true)
	else: dialogue.queue_special(rare)
	if player_won: _drop_reward(defeat_position)
	boss.start_return(player_won)
	if persistence_enabled and not save_checkpoint():
		player.get_parent().inventory_session.show_notice("Kyren progress save failed; retry before quitting.",6)

func _drop_reward(at: Vector3) -> void:
	var loot: Node3D = player.loot_authority
	if not is_instance_valid(loot): return
	var selected: StringName = REWARDS[reward_rng.randi_range(0,REWARDS.size()-1)]
	var pickup: Node3D = loot.spawn_reward(selected,at)
	var by_tree := pickup==null
	# Aerial/void defeats may have no usable support below them. The authored
	# clearing is a safe fallback; choose the item once, without rerolling.
	if pickup==null: pickup=loot.spawn_reward(selected,boss.home_point)
	var session: Node = player.get_parent().get("inventory_session")
	if is_instance_valid(session):
		session.show_notice("Kyren dropped "+pickup.interaction_name()+(" by his tree." if by_tree else ".")+" G / RT to collect." if pickup!=null else "Kyren's reward could not be placed.",6)

func player_defeated() -> void:
	finish(false)
	player.request_respawn()

func disengage() -> void:
	if not active or not has_authority(): return
	active=false
	salt.active=false
	_release()
	boss.start_return()
	if persistence_enabled: save_checkpoint()

func context() -> Dictionary:
	return {"combat":active,"opening":not active or boss.weapon_combat.active_move.is_empty(),"winning":player.health/player.weapon_combat.max_health<boss.health/boss.weapon_combat.max_health,"previous_sky":progress.kyren.pattern=="sky","previous_parry":progress.kyren.pattern=="parry","previous_loss":progress.wins>0,"repeated_three":_repetitions>=3}

func _pattern(key: String) -> void: _patterns[key]=int(_patterns.get(key,0))+1

func _reaction(trigger: StringName) -> void:
	if active: dialogue.say(trigger,salt.value,context(),trigger==&"parry_domination")

func _boss_contact(event: Dictionary) -> void:
	if not active or event.attacker!=player: return
	if salt._seen.has(String(event.get("event_id",""))): return
	if float(event.damage)>0:
		_landed=true
		var incoming: Dictionary = event.incoming
		_starter_only=_starter_only and String(incoming.get("item_id",player.weapon_combat.equipment_key(player.combat.selected_slot))) in ["sword_shield","spear","katana","twin_blades"]
		var technique: String = String(incoming.get("item_id",""))+":"+String(incoming.get("action",incoming.get("name","")))
		var attack_key: String = event.get("attack_key",event.get("event_id",""))
		if attack_key!=_pattern_serial:
			_pattern_serial=attack_key
			if technique!=_last_technique:
				_last_technique=technique
				_repetitions=0
			_repetitions+=1
			if _repetitions>=2: _pattern("repeat")
	salt.contact(event,true)

func _player_contact(event: Dictionary) -> void:
	if not active: return
	if float(event.damage)>0: _damaged=true # Includes chip and environmental damage.
	if event.attacker!=boss: return
	if salt._seen.has(String(event.get("event_id",""))): return
	_unseen=0
	if event.outcome==&"parry":
		_pattern("parry")
		if String(event.incoming.get("action","")).begins_with("special_"): dialogue.say(&"special_parried",salt.value,context())
	salt.contact(event,false)

func _observed_attack(move: Dictionary) -> void:
	if not active or not boss.controls.can_see(): return
	boss.controls.observe(move)
	if String(move.get("action","")).begins_with("special_"):
		_pattern("art")
		dialogue.say(&"weapon_art",salt.value,context())

func _sky_jump(_origin: Vector3, _side: int) -> void:
	if not active or not boss.controls.can_see(): return
	_jumps.append(salt.clock)
	while not _jumps.is_empty() and _jumps[0]<salt.clock-5: _jumps.pop_front()
	_pattern("sky")
	if _jumps.size()>=2: dialogue.say(&"sky_jump_spam",salt.value,context())

func _player_finished(move: Dictionary, hits: int) -> void:
	if active and hits==0 and boss.global_position.distance_to(player.global_position)<float(move.get("reach",0))+1 and boss.controls.can_see(): dialogue.say(&"miss",salt.value,context())

func _boss_finished(_move: Dictionary, _hits: int) -> void:
	# Parried attacks are cancelled before completion. A completed whiff/block
	# breaks the sequence, rather than crediting unrelated later parries.
	if active:
		salt.consecutive_parries=0
		salt._streak_awarded=false

func _environment(collider: Node3D, serial: int) -> void:
	if not active or serial==_environment_serial: return
	_environment_serial=serial
	if collider==home.structure.body: dialogue.say(&"house_contact",salt.value,context())
	elif collider==home.tree.structure.body: dialogue.say(&"tree_contact",salt.value,context())

func save_checkpoint(path: String = "") -> bool:
	if not has_authority() or networked(): return false
	progress.kyren.salt=salt.value
	progress.kyren.lingering_floor=salt.lingering_floor
	if not Progress.valid(progress): return false
	var destination := path if path!="" else save_path
	var entries := Journal.read(destination,player.inventory.owner_id)
	entries.kyren=progress.duplicate(true)
	return Journal.store(destination,player.inventory.owner_id,entries)==OK

func load_checkpoint(path: String = "") -> bool:
	if not has_authority() or networked() or active: return false
	var entries := Journal.read(path if path!="" else save_path,player.inventory.owner_id)
	if not Progress.valid(entries.get("kyren")): return false
	progress=entries.kyren.duplicate(true)
	salt.lingering_floor=float(progress.kyren.lingering_floor)
	salt.set_value(float(progress.kyren.salt))
	return true

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and dialogue_open: answer(false)
	if what==NOTIFICATION_EXIT_TREE and persistence_enabled and is_instance_valid(player) and is_instance_valid(player.inventory): save_checkpoint()

func _process(delta: float) -> void:
	if not has_authority(): return
	salt.advance(delta)
	dialogue.advance(delta)
	subtitle.text="KYREN\n"+dialogue.current_text if not dialogue.current_text.is_empty() else ""
	bar_root.visible=active
	if active:
		health_bar.max_value=boss.weapon_combat.max_health
		health_bar.value=boss.health
		strain_bar.max_value=boss.weapon_combat.rules.max_psi
		strain_bar.value=boss.weapon_combat.psi_meter
		salt_label.text="KYREN    /    SALT %03d%%  ·  %s" % [salt.value,String(salt.state()).to_upper()]
	_save_clock+=delta
	if _save_clock>15:
		_save_clock=0
		if persistence_enabled: save_checkpoint()
	_check_clock+=delta
	if _check_clock<.2: return
	var tick := _check_clock
	_check_clock=0
	var distance: float = player.global_position.distance_to(boss.global_position)
	if dialogue_open and not can_talk(): answer(false)
	if active:
		if distance>100 and not boss.controls.can_see(): _unseen+=tick
		elif distance>160: _unseen+=tick
		else: _unseen=0
		if _unseen>disengage_seconds:
			disengage()
		elif salt.state()!=_last_salt_state and boss.weapon_combat.active_move.is_empty():
			_last_salt_state=salt.state()
			dialogue.say(_last_salt_state,salt.value,context())
		elif boss.controls.behavior=="measuring": dialogue.say(&"taunt",salt.value,context())
	elif distance>12: _greeted=false
	elif not _greeted and can_talk() and player.controls.gameplay_enabled:
		_greeted=true
		dialogue.say(&"return_greet" if progress.kyren.challenges>0 else &"greet",salt.value,context(),true)

func _build_ui() -> void:
	subtitle=Label.new()
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	subtitle.offset_left=-370
	subtitle.offset_right=370
	subtitle.offset_top=140
	subtitle.offset_bottom=240
	subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size",21)
	subtitle.add_theme_constant_override("outline_size",6)
	subtitle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)
	bar_root=Control.new()
	bar_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_root.position=Vector2(-260,-72)
	bar_root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(bar_root)
	salt_label=Label.new()
	salt_label.position.y=-28
	salt_label.modulate=Color(1,.68,.12)
	bar_root.add_child(salt_label)
	health_bar=_bar(0,14,Color(.8,.12,.05))
	strain_bar=_bar(18,3,Color(1,.68,.12))
	bar_root.hide()
	panel=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-270
	panel.offset_right=270
	panel.offset_top=-85
	panel.offset_bottom=85
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	panel.add_child(box)
	var prompt := Label.new()
	prompt.text="KYREN\nChallenge the swordsman beneath the tree?"
	prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prompt)
	var row := HBoxContainer.new()
	row.alignment=BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	yes=Button.new()
	yes.text="Challenge"
	no=Button.new()
	no.text="Not now"
	for button: Button in [yes,no]:
		button.custom_minimum_size=Vector2(205,44)
		row.add_child(button)
	var help := Label.new()
	help.text="Left / Right: choose   A / Enter: answer   B / Escape: cancel"
	help.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)
	yes.pressed.connect(func(): answer(true))
	no.pressed.connect(func(): answer(false))
	add_child(panel)
	panel.hide()

func _bar(y: float, height: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position=Vector2(0,y)
	bar.size=Vector2(520,height)
	bar.show_percentage=false
	bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color=color
	bar.add_theme_stylebox_override("fill",style)
	bar_root.add_child(bar)
	return bar
