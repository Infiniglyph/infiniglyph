extends Node
## Local UI/interaction and a single-player checkpoint, separate from host rules.
const Interface = preload("res://scripts/inventory_ui.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
var actor: CharacterBody3D
var controls: Node
var duel: CanvasLayer
var loot: Node3D
var population: Node3D
var boss_encounter: Node
var ui: CanvasLayer
@export var persistence_enabled := true
@export var save_path := "user://inventory_v1.json"
@export var live_session := false
var _loading := false
var _save_queued := false
var _previous_mouse := Input.MOUSE_MODE_CAPTURED
var _hint_clock := 0.0
var _notice_time := 0.0
var _exiting := false
var hint: Label
var notice: Label
var _loss_count := 0
var resident_dialogue: Label
var _resident_speaker: WeakRef
var _resident_time := 0.0

func networked() -> bool:
	if not is_inside_tree(): return live_session
	var peer := multiplayer.multiplayer_peer
	return live_session or (peer != null and not peer is OfflineMultiplayerPeer)

func _ready() -> void:
	name = "InventorySession"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Command-line test/capture tools use isolated fresh ownership. They can
	# still exercise explicit save_checkpoint/load_checkpoint with temp paths.
	persistence_enabled = persistence_enabled and not "--script" in OS.get_cmdline_args() and not networked()
	actor.loot_authority = loot
	loot.register_inventory(actor.inventory)
	loot.host_enabled = not networked() or multiplayer.is_server()
	controls.interaction_context = self
	ui = Interface.new()
	ui.actor = actor
	ui.inventory = actor.inventory
	ui.loot = loot
	add_child(ui)
	ui.opened.connect(_opened)
	ui.closed.connect(_closed)
	ui.save_requested.connect(func():
		var saved := save_checkpoint()
		ui.set_status("Inventory and world drops saved." if saved else "Save failed; items remain in memory.",not saved))
	var layer := CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	hint = _label(layer,Vector2(-350,-40),Color(0.65,1,1))
	notice = _label(layer,Vector2(-350,-72),Color(1,0.6,0.25))
	resident_dialogue = Label.new()
	resident_dialogue.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	resident_dialogue.position = Vector2(30,-172)
	resident_dialogue.size = Vector2(820,88)
	resident_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resident_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resident_dialogue.add_theme_font_size_override("font_size",18)
	resident_dialogue.add_theme_color_override("font_color",Color(0.75,0.97,1))
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0.003,0.015,0.02,0.96)
	backing.border_color = Color(0.1,0.65,0.74)
	backing.set_border_width_all(1)
	backing.set_content_margin_all(12)
	resident_dialogue.add_theme_stylebox_override("normal",backing)
	layer.add_child(resident_dialogue)
	resident_dialogue.hide()
	if persistence_enabled and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak")):
		if not load_checkpoint():
			# A corrupt checkpoint must not silently remint lost starter gear.
			actor.inventory.restore({"version":1,"owner_id":actor.inventory.owner_id,"items":[],"equipment":{}})
			persistence_enabled = false
			show_notice("Inventory save could not be loaded; autosave stopped.",12)
	elif not networked():
		seed_demo_loot()
	actor.inventory.changed.connect(_dirty)
	loot.changed.connect(_dirty)
	loot.picked_up.connect(_picked_up)
	loot.markers.changed.connect(_refresh_losses)
	_refresh_losses()
	_dirty()

func _label(layer: CanvasLayer, at: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	label.position = at
	label.custom_minimum_size = Vector2(700,26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",4)
	layer.add_child(label)
	return label

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_toggle") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if is_instance_valid(actor.get_parent().get("start_menu")) and actor.get_parent().start_menu.is_open: return
		if is_instance_valid(duel) and duel.dialogue_open: return
		if is_instance_valid(boss_encounter) and boss_encounter.dialogue_open: return
		ui.toggle()

func _opened() -> void:
	_previous_mouse = Input.mouse_mode
	controls.set_gameplay_enabled(false)
	actor.weapon_combat.cancel()
	actor.combat.reset()
	actor._jump_after_dodge = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _closed() -> void:
	controls.set_gameplay_enabled(true)
	Input.mouse_mode = _previous_mouse
	_dirty()

func can_talk() -> bool:
	if ui.is_open or not controls.gameplay_enabled or duel.dialogue_open or duel.active: return false
	if is_instance_valid(boss_encounter):
		if boss_encounter.active: return false
		if boss_encounter.can_challenge(): return true
	return loot.nearest_pickup(actor) != null or duel.can_talk() or (is_instance_valid(population) and population.nearest_talker()!=null)

func can_yield() -> bool:
	return duel.active and controls.gameplay_enabled and not ui.is_open

func interact() -> void:
	if ui.is_open or not controls.gameplay_enabled: return
	if is_instance_valid(boss_encounter):
		if boss_encounter.active: return
		if boss_encounter.can_challenge():
			boss_encounter.interact()
			return
	if duel.active:
		duel.interact()
		return
	var pickup: Node3D = loot.nearest_pickup(actor)
	if pickup != null:
		if not loot.request_pickup(actor.inventory,pickup): show_notice("Pickup unavailable.")
	elif duel.can_talk(): duel.interact()
	elif is_instance_valid(population):
		var resident: CharacterBody3D = population.nearest_talker()
		if resident!=null:
			resident.talk()
			resident_dialogue.text = resident.profile.name.to_upper()+"  /  "+resident.profile.role+"\n"+resident.caption.text
			_resident_speaker = weakref(resident)
			_resident_time = 5.5

func _process(delta: float) -> void:
	if not is_instance_valid(ui): return
	if controls.consume_interaction(): interact()
	_resident_time = maxf(0,_resident_time-delta)
	var resident: Node3D = _resident_speaker.get_ref() if _resident_speaker!=null else null
	resident_dialogue.visible = _resident_time>0 and controls.gameplay_enabled and is_instance_valid(resident) and actor.global_position.distance_to(resident.global_position)<5
	_notice_time = maxf(0,_notice_time-delta)
	if _notice_time==0: notice.text = ""
	_hint_clock -= delta
	if _hint_clock>0: return
	_hint_clock = 0.2
	_refresh_losses()
	hint.text = ""
	if ui.is_open or not controls.gameplay_enabled or duel.active: return
	if is_instance_valid(boss_encounter) and boss_encounter.can_challenge():
		hint.text = "G / RT: challenge Greefer again"
		return
	var pickup: Node3D = loot.nearest_pickup(actor)
	if pickup != null:
		var definition: Resource = Catalog.get_definition(pickup.item_instance.item_type_id)
		hint.text = "G / RT: collect %s  x%d" % [definition.display_name,pickup.item_instance.quantity]
	elif not duel.can_talk() and is_instance_valid(population):
		var talker: CharacterBody3D = population.nearest_talker()
		if talker!=null: hint.text = "G / RT: talk to %s  |  %s" % [talker.profile.name,talker.state]

func _picked_up(inventory: Node, item: Resource) -> void:
	if inventory != actor.inventory: return
	var definition: Resource = Catalog.get_definition(item.item_type_id)
	show_notice("Collected %s  x%d" % [definition.display_name,item.quantity])

func show_notice(message: String, duration: float = 3.0) -> void:
	notice.text = message
	_notice_time = duration

func _refresh_losses() -> void:
	var entries: Array = loot.markers.for_owner(actor.inventory.owner_id)
	if entries.size()>_loss_count:
		show_notice("Lost gear remains where you fell. %d unclaimed." % entries.size(),6)
	_loss_count = entries.size()

func _dirty() -> void:
	if _exiting or not is_inside_tree() or _loading or not persistence_enabled or networked() or _save_queued: return
	_save_queued = true
	call_deferred("_autosave")

func _autosave() -> void:
	_save_queued = false
	if is_inside_tree() and not _exiting and persistence_enabled and not networked(): save_checkpoint("",true)

func save_checkpoint(path: String = "", silent: bool = false) -> bool:
	if _exiting or not is_inside_tree(): return false
	if loot.transaction_active(): return false
	if networked():
		show_notice("Session ownership is saved by the host.")
		return false
	var destination := path if not path.is_empty() else save_path
	var snapshot: Dictionary = Store.encode(actor.inventory,loot.serialize_world(),[],loot.session_id)
	var error: Error = Store.store(destination,snapshot)
	if error != OK:
		show_notice("Inventory save failed; current items remain in memory.",6)
		return false
	if not silent: show_notice("Inventory and world drops saved.")
	return true

func load_checkpoint(path: String = "") -> bool:
	if networked() or loot.transaction_active(): return false
	var source := path if not path.is_empty() else save_path
	var snapshot: Dictionary = Store.load_snapshot(source)
	if snapshot.is_empty() or snapshot.session_id != loot.session_id or snapshot.inventory.owner_id != actor.inventory.owner_id: return false
	var owned_before: Dictionary = actor.inventory.serialize()
	var world_before: Array = loot.serialize_world()
	_loading = true
	var ok: bool = actor.inventory.restore(snapshot.inventory)
	if ok: ok = loot.restore_world(snapshot.world_drops)
	if not ok:
		actor.inventory.restore(owned_before)
		loot.restore_world(world_before)
	_loading = false
	return ok

func seed_demo_loot() -> void:
	# Editor-style instances demonstrate collection without changing starter gear.
	var definitions: Array = Catalog.all()
	if definitions.is_empty(): return
	var index := 0
	for definition: Resource in definitions:
		if definition.category not in [&"materials",&"consumables",&"key_items"]: continue
		var pickup := Pickup.new()
		pickup.item_type_id = definition.item_type_id
		pickup.quantity = mini(3,definition.max_stack)
		loot.add_child(pickup)
		pickup.position = Vector3(13,0.2,18+index*2.4)
		loot.register_pickup(pickup)
		index += 1
		if index>=3: break
	var weapon := Pickup.new()
	weapon.item_type_id = &"katana"
	weapon.upgrade_level = 1
	weapon.custom_properties = {"engraving":"Civic training blade"}
	loot.add_child(weapon)
	weapon.position = Vector3(13,0.2,25.2)
	loot.register_pickup(weapon)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(ui) and ui.is_open: ui.close_menu()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence_enabled and not networked(): save_checkpoint()

func _exit_tree() -> void:
	_exiting = true
