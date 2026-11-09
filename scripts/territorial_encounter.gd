extends CanvasLayer
## Reusable encounter lifecycle/authority/journal boundary. The district stays live.
const Journal = preload("res://scripts/encounter_progress.gd")
const Neon = preload("res://scripts/neon.gd")
signal encounter_started(is_intro: bool)
signal encounter_finished(player_won: bool, is_intro: bool)
signal progression_changed
@export var encounter_id := &"greefer"
@export_multiline var introduction := "Another human? You people really don't know when to quit."
@export_multiline var defeat_line := "Pathetic. Go back to your own world."
@export_multiline var victory_line := "...Impossible. You're human."
@export_multiline var rematch_line := "Back again? I remember how that ended."
@export_multiline var rematch_after_victory := "Your last victory was an accident, human."
@export var save_path := "user://encounters_v1.json"
@export var persistence_enabled := true
@export var auto_trigger := true
var player: CharacterBody3D
var boss: CharacterBody3D
var active := false
var is_intro := true
var participated := false
var progress: Dictionary = Journal.fresh()
var entries: Dictionary = {}
var result_text := ""
var result_time := 0.0
var challenge_point := Vector3(5,0.045,-40)
var objective: Label
var dialogue: Label
var bar_root: Control
var health_bar: ProgressBar
var strain_bar: ProgressBar
var boss_name: Label
var _check_clock := 0.0
var _beacon: Node3D
var _perch: Node3D

func networked() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer

func has_authority() -> bool:
	return not networked() or multiplayer.is_server()

func can_progress() -> bool:
	return bool(progress.intro_completed)

func _ready() -> void:
	name = "GreeferEncounter"
	layer = 5
	persistence_enabled = persistence_enabled and not "--script" in OS.get_cmdline_args() and not networked()
	# Existing isolated gameplay tests keep the perched boss, but opt into his
	# automatic encounter explicitly. Normal launches always enable detection.
	auto_trigger = auto_trigger and (not "--script" in OS.get_cmdline_args() or "--boss-encounters" in OS.get_cmdline_user_args())
	if persistence_enabled: load_checkpoint()
	_perch = Neon.block(get_parent(),Vector3(0,86.4,-64),Vector3(8,0.5,8))
	_perch.name = "CentralTowerPerch"
	var points := PackedVector3Array()
	for i in range(32):
		var a := i*TAU/32
		var b := (i+1)*TAU/32
		points.append_array([Vector3(cos(a),0,sin(a))*1.05,Vector3(cos(b),0,sin(b))*1.05])
	_beacon = Neon.lines(points,Neon.material(Color(0.85,0.06,1)))
	_beacon.name = "GreeferChallengeSigil"
	get_parent().add_child(_beacon)
	_beacon.position = challenge_point
	_build_hud()

func _label(at: Vector2, size_value: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size",size_value)
	label.add_theme_constant_override("outline_size",5)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_color_override("font_color",Color(0.8,0.65,1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _build_hud() -> void:
	objective = _label(Vector2(30,100),16)
	dialogue = _label(Vector2(285,115),20)
	dialogue.custom_minimum_size.x = 620
	dialogue.size.x = 620
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_root = Control.new()
	bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_root.position = Vector2(-260,-210)
	add_child(bar_root)
	boss_name = Label.new()
	boss_name.text = "GREEFER  /  GRIFFIN OF CENTRAL TOWER"
	boss_name.position.y = -28
	boss_name.add_theme_font_size_override("font_size",18)
	bar_root.add_child(boss_name)
	health_bar = _bar(Vector2.ZERO,Vector2(520,14),Color(0.86,0.07,0.93))
	strain_bar = _bar(Vector2(0,18),Vector2(520,3),Color(1,0.55,0.16))
	bar_root.hide()

func _bar(at: Vector2, dimensions: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.position = at
	bar.size = dimensions
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.02,0.008,0.035,0.95)
	back.border_color = color*0.65
	back.set_border_width_all(1)
	bar.add_theme_stylebox_override("fill",fill)
	bar.add_theme_stylebox_override("background",back)
	bar_root.add_child(bar)
	return bar

func can_challenge() -> bool:
	return has_authority() and not active and progress.intro_completed and boss.state == &"perched" and player.global_position.distance_to(challenge_point)<3.0 and not player.sparring_duel.active

func start(aggression: bool = false) -> bool:
	if not has_authority() or active or boss.state == &"defeated" or player.health<=0: return false
	if player.sparring_duel.active or player.sparring_duel.dialogue_open: return false
	if not aggression and progress.intro_completed and not can_challenge(): return false
	active = true
	participated = false
	is_intro = not progress.intro_completed
	player.set_collision_layer_value(2,true)
	player.add_to_group("combat_targets")
	boss.add_to_group("combat_targets")
	boss.alert()
	result_text = introduction if is_intro else (rematch_after_victory if progress.last_outcome == "victory" else rematch_line)
	result_time = 5
	encounter_started.emit(is_intro)
	return true

func register_contact() -> void:
	if has_authority() and active: participated = true

func _release_player() -> void:
	player.set_collision_layer_value(2,false)
	player.remove_from_group("combat_targets")
	boss.remove_from_group("combat_targets")
	if player.target_lock.opponent == boss: player.target_lock.clear()

func finish(player_won: bool) -> void:
	if not has_authority() or not active: return
	# Close the gate first: lethal callbacks can arrive inside a multihit pulse.
	active = false
	_release_player()
	if is_intro:
		progress.intro_completed = true
		progress.first_victory = player_won
		progress.first_outcome = "victory" if player_won else "defeat"
	progress["wins" if player_won else "losses"] += 1
	progress.last_outcome = "victory" if player_won else "defeat"
	entries[String(encounter_id)] = progress.duplicate(true)
	if persistence_enabled and not save_checkpoint():
		get_parent().inventory_session.show_notice("Encounter cleared. Progress save failed; retry before quitting.",8)
	result_text = victory_line if player_won else defeat_line
	result_time = 7
	boss.weapon_combat.cancel()
	boss.combat.blocking = false
	if player_won: boss.set_state(&"defeated")
	else: boss.start_return()
	encounter_finished.emit(player_won,is_intro)
	progression_changed.emit()

func player_defeated() -> void:
	if participated: finish(false)
	else: disengage() # Falling before any confrontation cannot skip the intro.
	player.respawn() # Existing defeat transition, never an arrival/cinematic warp.
	player.weapon_combat.health = player.weapon_combat.max_health
	player.weapon_combat.changed.emit()

func disengage() -> void:
	if not has_authority() or not active: return
	active = false
	_release_player()
	boss.start_return()
	result_text = "Greefer returns to his tower."+("\nThe confrontation is unfinished." if not progress.intro_completed else "")
	result_time = 4

func save_checkpoint(path: String = "") -> bool:
	if not has_authority() or networked(): return false
	var destination := path if path!="" else save_path
	# Merge at commit time so a future territorial boss cannot overwrite another
	# boss's newer result with its own older in-memory copy of the journal.
	entries = Journal.read(destination,player.inventory.owner_id)
	entries[String(encounter_id)] = progress.duplicate(true)
	return Journal.store(destination,player.inventory.owner_id,entries) == OK

func load_checkpoint(path: String = "") -> bool:
	if not has_authority() or networked() or active: return false
	var loaded := Journal.read(path if path!="" else save_path,player.inventory.owner_id)
	if not loaded.has(String(encounter_id)): return false
	entries = loaded
	progress = entries[String(encounter_id)].duplicate(true)
	return true

func snapshot() -> Dictionary:
	# Host-owned data for a future transport; no competing client simulation/RPCs.
	return {"id":String(encounter_id),"active":active,"state":String(boss.state),"position":boss.position,"velocity":boss.velocity,"facing":boss.facing,"flight":boss.flight_mode,"health":boss.health,"strain":boss.weapon_combat.psi_meter,"progress":progress.duplicate(true)}

func _physics_process(delta: float) -> void:
	if not has_authority(): return
	_check_clock -= delta
	if _check_clock>0: return
	_check_clock = 0.2
	if active and not boss.in_district(player.global_position):
		disengage()
	elif auto_trigger and not active and not progress.intro_completed and boss.state == &"perched" and player.controls.gameplay_enabled:
		# The tower approach includes roofs/open air above the boulevard. No wall
		# or movement restriction can substitute for the required confrontation.
		var planar := Vector2(player.position.x,player.position.z+44)
		if planar.length()<25 and boss.can_see_player(): start()

func _process(delta: float) -> void:
	result_time = maxf(0,result_time-delta)
	bar_root.visible = active
	if active:
		health_bar.max_value = boss.weapon_combat.max_health
		health_bar.value = boss.health
		strain_bar.max_value = boss.weapon_combat.rules.max_psi
		strain_bar.value = boss.weapon_combat.psi_meter
		boss_name.text = "GREEFER  /  GRIFFIN OF CENTRAL TOWER"+("  OPEN" if boss.weapon_combat.is_staggered() else "")
	dialogue.text = result_text if result_time>0 else ""
	objective.text = "Central Tower: confront its guardian" if not progress.intro_completed and not active else ("G / RT: challenge Greefer again" if can_challenge() else "")
	if not active and is_intro and progress.intro_completed and result_time>0:
		objective.text = "First confrontation complete - explore Central District"
	_beacon.visible = progress.intro_completed
