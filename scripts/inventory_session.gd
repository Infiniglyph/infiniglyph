extends Node
## Local UI/interaction and a single-player checkpoint, separate from host rules.
const Interface = preload("res://scripts/inventory_ui.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const TowerShop = preload("res://scripts/tower_shop.gd")
const Regions = preload("res://scripts/world_regions.gd")
const Shields = preload("res://scripts/shield_glyphs.gd")
const LOST_GEAR_HOLD_TIME := .7
var actor: CharacterBody3D
var controls: Node
var duel: CanvasLayer
var loot: Node3D
var population: Node3D
var boss_encounter: Node
var kyren_encounter: Node
var world_actions: Node3D
var dungeon_travel: Node
var ui: CanvasLayer
var shop: CanvasLayer
@export var persistence_enabled := true
@export var save_path := "user://inventory_v1.json"
@export var live_session := false
var _loading := false
var _save_queued := false
var _previous_mouse := Input.MOUSE_MODE_CAPTURED
var _hint_clock := 0.0
var _notice_time := 0.0
var _exiting := false
var _checkpoint_usable := true
var _checkpoint_pending := false
var _resume_gameplay := false
var hint: Label
var notice: Label
var loss_hint: Label
var _loss_count := 0
var resident_dialogue: Label
var _resident_speaker: WeakRef
var _resident_time := 0.0
var _held_pickup_cooldown := 0.0
var _inventory_sources: Dictionary = {}
var _inventory_pending := false
var _inventory_hold_elapsed := 0.0
var _inventory_hold_fired := false

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
	shop = TowerShop.new()
	shop.session = self
	add_child(shop)
	shop.opened.connect(_opened)
	shop.closed.connect(_closed)
	ui.save_requested.connect(func():
		var saved := save_checkpoint()
		ui.set_status("Inventory and world drops saved." if saved else "Save failed; items remain in memory.",not saved))
	var layer := CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	hint = _label(layer,Vector2(-350,-40),Color(0.65,1,1))
	notice = _label(layer,Vector2(-350,-72),Color(1,0.6,0.25))
	loss_hint = _label(layer,Vector2(-350,-104),Color(1,0.6,0.25))
	loss_hint.name = "LostGearLocation"
	loss_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loss_hint.add_theme_font_size_override("font_size",14)
	loss_hint.hide()
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
		_begin_initial_checkpoint_load()
	elif not networked():
		seed_demo_loot()
	actor.inventory.changed.connect(_dirty)
	if not networked() and not _checkpoint_pending and _checkpoint_usable: actor.inventory.introduce_health_glyphs()
	loot.changed.connect(_dirty)
	loot.picked_up.connect(_picked_up)
	loot.markers.changed.connect(_refresh_losses)
	Input.joy_connection_changed.connect(_inventory_pad_connection_changed)
	actor.defeated.connect(func(): _cancel_inventory_hold(true))
	actor.respawned.connect(func(): _cancel_inventory_hold(true))
	_refresh_losses()
	_dirty()

func _begin_initial_checkpoint_load() -> void:
	if _checkpoint_pending or networked(): return
	_checkpoint_pending = true
	_loading = true
	_resume_gameplay = controls.gameplay_enabled
	controls.set_gameplay_enabled(false)
	call_deferred("_load_initial_checkpoint")

func _load_initial_checkpoint() -> void:
	# This session enters the tree before the outer city is built. A valid save
	# can contain a drop there, so wait for construction and a physics sync before
	# validating its real support/clearance. Keep saves and local actions gated.
	await get_tree().physics_frame
	await get_tree().process_frame
	if not is_inside_tree(): return
	var loaded := load_checkpoint()
	if not loaded:
		_checkpoint_usable = false
		# Corrupt/foreign data still fails closed without rewriting the source.
		actor.inventory.restore({"version":1,"owner_id":actor.inventory.owner_id,"items":[],"equipment":{}})
		persistence_enabled = false
		show_notice("Inventory save could not be loaded; autosave stopped.",12)
	_checkpoint_pending = false
	_loading = false
	var menu: Node = actor.get_parent().get("start_menu")
	var menu_open: bool = is_instance_valid(menu) and menu.is_open
	if _resume_gameplay and not menu_open and not ui.is_open and not shop.is_open:
		controls.set_gameplay_enabled(true)
	if loaded:
		actor.inventory.introduce_health_glyphs()
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

func _inventory_allowed() -> bool:
	if _checkpoint_pending or actor.transition_locked: return false
	if is_instance_valid(actor.respawn_selector) and actor.respawn_selector.waiting: return false
	if is_instance_valid(actor.get_parent().get("start_menu")) and actor.get_parent().start_menu.is_open: return false
	if is_instance_valid(duel) and duel.dialogue_open: return false
	if is_instance_valid(boss_encounter) and boss_encounter.dialogue_open: return false
	if is_instance_valid(kyren_encounter) and kyren_encounter.dialogue_open: return false
	return true

func _inventory_token(event: InputEvent) -> String:
	if event is InputEventJoypadButton: return "pad:%d:%d" % [event.device,event.button_index]
	if event is InputEventKey: return "key:%d" % (event.physical_keycode if event.physical_keycode!=KEY_NONE else event.keycode)
	return "inventory_action"

func _toggle_inventory() -> void:
	if not _inventory_allowed(): return
	if shop.is_open: shop.close_menu()
	ui.toggle()

func _cancel_inventory_hold(clear_sources: bool = false) -> void:
	_inventory_pending = false
	_inventory_hold_elapsed = 0
	_inventory_hold_fired = false
	if clear_sources: _inventory_sources.clear()

func _input(event: InputEvent) -> void:
	if not event.is_action("inventory_toggle"): return
	get_viewport().set_input_as_handled()
	if event.is_echo(): return
	var token := _inventory_token(event)
	if event.is_pressed():
		if _inventory_sources.has(token): return
		var first := _inventory_sources.is_empty()
		_inventory_sources[token] = true
		if not first or not _inventory_allowed(): return
		if loss_hint.visible and not ui.is_open and not shop.is_open and controls.gameplay_enabled and actor.health>0:
			_inventory_pending = true
			_inventory_hold_elapsed = 0
			_inventory_hold_fired = false
		else: _toggle_inventory()
	else:
		if not _inventory_sources.has(token): return
		_inventory_sources.erase(token)
		if not _inventory_sources.is_empty(): return
		var tap := _inventory_pending and not _inventory_hold_fired
		_cancel_inventory_hold()
		if tap: _toggle_inventory()

func _advance_inventory_hold(delta: float) -> void:
	if not _inventory_pending or _inventory_hold_fired: return
	if not _inventory_allowed() or ui.is_open or shop.is_open or not controls.gameplay_enabled or actor.health<=0 or not loss_hint.visible:
		_cancel_inventory_hold(true)
		return
	_inventory_hold_elapsed += maxf(0,delta)
	if _inventory_hold_elapsed<LOST_GEAR_HOLD_TIME: return
	_inventory_hold_fired = true
	if loot.request_dismiss_lost_gear(actor.inventory):
		_refresh_losses()
		var minutes := ceili(float(loot.dismissed_loss_lifetime)/60)
		show_notice("Lost gear hidden. Unclaimed drops disappear in %d minutes." % minutes,5)
	else: show_notice("Lost gear could not be dismissed.")

func _inventory_pad_connection_changed(_device: int, connected: bool) -> void:
	if not connected: _cancel_inventory_hold(true)

func _opened() -> void:
	_cancel_inventory_hold()
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
	if _checkpoint_pending: return false
	if ui.is_open or not controls.gameplay_enabled or duel.dialogue_open or duel.active: return false
	if is_instance_valid(dungeon_travel):
		if dungeon_travel.busy: return false
		if dungeon_travel.focused_door()!=null: return true
		if dungeon_travel.inside(): return loot.nearest_pickup(actor)!=null
	if is_instance_valid(kyren_encounter):
		if kyren_encounter.active: return false
		if kyren_encounter.can_talk(): return true
	if is_instance_valid(world_actions) and world_actions.attached(): return true
	if is_instance_valid(boss_encounter):
		if boss_encounter.active: return false
		if boss_encounter.can_challenge(): return true
	if is_instance_valid(world_actions) and not world_actions.nearest().is_empty(): return true
	if shop.can_use(actor): return true
	if is_instance_valid(world_actions) and is_instance_valid(world_actions.life) and world_actions.life.nearest_talker()!=null: return true
	return loot.nearest_pickup(actor) != null or duel.can_talk() or (is_instance_valid(population) and population.nearest_talker()!=null)

func can_yield() -> bool:
	return duel.active and controls.gameplay_enabled and not ui.is_open

func interact() -> void:
	if ui.is_open or not controls.gameplay_enabled: return
	if is_instance_valid(dungeon_travel):
		if dungeon_travel.busy: return
		var item: Node3D=loot.nearest_pickup(actor)
		if item==null and dungeon_travel.interact(): return
		if dungeon_travel.inside():
			if item!=null: loot.request_pickup(actor.inventory,item)
			return
	if is_instance_valid(kyren_encounter):
		if kyren_encounter.active: return
		if kyren_encounter.can_talk() and loot.nearest_pickup(actor)==null:
			kyren_encounter.interact()
			return
	if is_instance_valid(world_actions) and world_actions.attached():
		world_actions.leave()
		return
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
	elif shop.can_use(actor): shop.open_menu()
	elif is_instance_valid(world_actions) and not world_actions.nearest().is_empty(): world_actions.interact()
	else:
		var resident: CharacterBody3D = population.nearest_talker()
		if resident==null and is_instance_valid(world_actions) and is_instance_valid(world_actions.life): resident = world_actions.life.nearest_talker()
		if resident!=null:
			resident.talk()
			resident_dialogue.text = resident.profile.name.to_upper()+"  /  "+resident.profile.role+"\n"+resident.caption.text
			_resident_speaker = weakref(resident)
			_resident_time = 5.5

func _collect_while_writing(delta: float) -> void:
	_held_pickup_cooldown = maxf(0,_held_pickup_cooldown-delta)
	if _held_pickup_cooldown>0 or not controls.can_hold_pickup(): return
	if not controls.gameplay_enabled or ui.is_open or shop.is_open or actor.transition_locked: return
	if actor.combat.sheathed or actor.weapon_combat.equipment_key(actor.combat.selected_slot)!=&"eturnull_manuscript" or not actor.weapon_combat.can_act(): return
	if duel.active or duel.dialogue_open: return
	if is_instance_valid(dungeon_travel) and dungeon_travel.busy: return
	if is_instance_valid(kyren_encounter) and (kyren_encounter.active or kyren_encounter.dialogue_open): return
	if is_instance_valid(boss_encounter) and (boss_encounter.active or boss_encounter.dialogue_open): return
	if is_instance_valid(world_actions) and world_actions.attached(): return
	# Only loot may be collected by a held writing modifier. Never repeatedly
	# invoke interact(), which could sit down, start dialogue or enter a doorway.
	_held_pickup_cooldown = .15
	var pickup: Node3D = loot.nearest_pickup(actor)
	if pickup!=null and loot.request_pickup(actor.inventory,pickup):
		controls.claim_weapon_modifier()

func _process(delta: float) -> void:
	if not is_instance_valid(ui) or _checkpoint_pending: return
	_advance_inventory_hold(delta)
	_collect_while_writing(delta)
	if controls.consume_heal():
		if controls.gameplay_enabled and not ui.is_open:
			if loot.request_health_glyph(actor.inventory): show_notice("Health Glyph restored your light.")
			else: show_notice("Health already full." if actor.health>=actor.weapon_combat.max_health else "No Health Glyphs available.")
	if controls.consume_shield():
		if controls.gameplay_enabled and not ui.is_open:
			if loot.request_shield_glyph(actor.inventory): show_notice("%s Shield Glyph restored your protection." % str(actor.inventory.shield_state.tier).capitalize())
			elif Shields.preferred_item(actor.inventory)==null: show_notice("No Shield Glyphs available.")
			else: show_notice("Shield already provides this much protection.")
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
	if is_instance_valid(dungeon_travel):
		var door: Node3D=dungeon_travel.focused_door()
		if door!=null and loot.nearest_pickup(actor)==null:
			hint.text="G / tap RT: "+door.prompt
			return
		if dungeon_travel.inside():
			var item: Node3D=loot.nearest_pickup(actor)
			if item!=null: hint.text="G / RT: collect "+item.interaction_name()
			return
	if is_instance_valid(kyren_encounter):
		if kyren_encounter.active: return
		if kyren_encounter.can_talk() and loot.nearest_pickup(actor)==null:
			hint.text = "G / RT: talk to Kyren"
			return
	if is_instance_valid(boss_encounter) and boss_encounter.can_challenge():
		hint.text = "G / RT: challenge Greefer again"
		return
	if is_instance_valid(world_actions) and world_actions.attached():
		hint.text = "G / RT: exit | left stick: drive | L3 / Ctrl: boost | R3 / Tab: light wave" if is_instance_valid(world_actions.vehicle) else "G / tap RT / move / jump: stand up"
		return
	var pickup: Node3D = loot.nearest_pickup(actor)
	if pickup != null:
		var definition: Resource = Catalog.get_definition(pickup.item_instance.item_type_id)
		hint.text = "G / RT: collect %s  x%d" % [definition.display_name,pickup.item_instance.quantity]
	elif shop.can_use(actor): hint.text = "G / tap RT: Tower Exchange"
	elif is_instance_valid(world_actions) and not world_actions.nearest().is_empty(): hint.text = "G / tap RT: "+world_actions.nearest().label
	elif not duel.can_talk() and is_instance_valid(population):
		var talker: CharacterBody3D = population.nearest_talker()
		if talker==null and is_instance_valid(world_actions) and is_instance_valid(world_actions.life): talker = world_actions.life.nearest_talker()
		if talker!=null: hint.text = "G / RT: talk to %s  |  %s" % [talker.profile.name,talker.state]

func _picked_up(inventory: Node, item: Resource) -> void:
	if inventory != actor.inventory: return
	var definition: Resource = Catalog.get_definition(item.item_type_id)
	show_notice("Collected %s  x%d" % [definition.display_name,item.quantity])

func show_notice(message: String, duration: float = 3.0) -> void:
	notice.text = message
	_notice_time = duration

func _refresh_losses() -> void:
	if _exiting or not is_inside_tree() or not is_instance_valid(actor) or not actor.is_inside_tree(): return
	var entries: Array = loot.markers.for_owner(actor.inventory.owner_id).filter(func(entry: Dictionary): return not entry.get("dismissed",false))
	if entries.size()>_loss_count:
		show_notice("Lost gear: %d unclaimed. Hold Select / B to dismiss." % entries.size(),6)
	_loss_count = entries.size()
	loss_hint.visible = not entries.is_empty()
	loss_hint.text = ""
	if entries.is_empty(): return
	# Dictionary/serialized drop order is oldest-to-newest; recovering the latest
	# naturally reveals the previous outstanding loss without deleting any item.
	var nearest: Dictionary = entries[-1]
	var point: Vector3 = nearest.world_position
	var distance: float=actor.global_position.distance_to(point)
	# Dedicated persistent guidance must survive short pickup/save notices.
	# Move it above a speaking resident's panel rather than covering dialogue.
	loss_hint.offset_top = -202 if resident_dialogue.visible else -104
	loss_hint.offset_bottom = loss_hint.offset_top+26
	var location:=StringName(nearest.get("location_id","overworld"))
	if is_instance_valid(dungeon_travel) and location!=dungeon_travel.active_location:
		loss_hint.text="LOST GEAR  |  %s  |  return through the pyramid doorway  |  %d unclaimed" % ["PYRAMID" if location!=&"overworld" else "OPEN WORLD",entries.size()]
		return
	if location!=&"overworld":
		var floor_text: String=dungeon_travel.interior.floor_label(point) if is_instance_valid(dungeon_travel) else ""
		loss_hint.text="LOST GEAR  %.0f m  |  PYRAMID %s  X %.0f  Z %.0f  |  %d unclaimed" % [distance,floor_text,point.x,point.z,entries.size()]
		return
	loss_hint.text = "LOST GEAR  %.0f m  |  %s  |  ALT %.0f m  |  %d unclaimed" % [distance,Regions.grid_label(Regions.grid_at(point)),point.y,entries.size()]

func _dirty() -> void:
	if _exiting or not is_inside_tree() or _loading or _checkpoint_pending or not persistence_enabled or networked() or _save_queued: return
	_save_queued = true
	call_deferred("_autosave")

func _autosave() -> void:
	_save_queued = false
	if is_inside_tree() and not _exiting and persistence_enabled and not networked(): save_checkpoint("",true)

func save_checkpoint(path: String = "", silent: bool = false) -> bool:
	if _exiting or _loading or _checkpoint_pending or not is_inside_tree(): return false
	if loot.transaction_active(): return false
	if networked():
		show_notice("Session ownership is saved by the host.")
		return false
	var destination := path if not path.is_empty() else save_path
	var location: String=String(dungeon_travel.active_location) if is_instance_valid(dungeon_travel) else "overworld"
	var state: Dictionary=dungeon_travel.location_state() if is_instance_valid(dungeon_travel) else {}
	var snapshot: Dictionary = Store.encode(actor.inventory,loot.serialize_world(),[],loot.session_id,location,state)
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
	var location:=StringName(snapshot.get("location_context","overworld"))
	if is_instance_valid(dungeon_travel):
		if not dungeon_travel.can_load_location(location): return false
	elif location!=&"overworld": return false
	var owned_before: Dictionary = actor.inventory.serialize()
	var world_before: Array = loot.serialize_world()
	_loading = true
	var ok: bool = actor.inventory.restore(snapshot.inventory)
	var world_changed := false
	if ok:
		ok = loot.restore_world(snapshot.world_drops)
		world_changed = ok
	if ok and is_instance_valid(dungeon_travel): ok=dungeon_travel.restore_location(location,snapshot.get("location_state",{}))
	if not ok:
		actor.inventory.restore(owned_before)
		# restore_world is already atomic on rejection. Replacing untouched
		# drops here would leave duplicate pending colliders until frame end.
		if world_changed: loot.restore_world(world_before)
	_loading = false
	return ok

func seed_demo_loot() -> void:
	# Editor-style instances demonstrate collection without changing starter gear.
	var definitions: Array = [Catalog.get_definition(&"light_shard"),Catalog.get_definition(&"signal_tonic"),Catalog.get_definition(&"civic_key")]
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
	var glyph := Pickup.new()
	glyph.item_type_id = &"health_glyph"
	glyph.quantity = 3
	loot.add_child(glyph)
	glyph.position = Vector3(3,0.2,12)
	loot.register_pickup(glyph)
	var weapon := Pickup.new()
	weapon.item_type_id = &"katana"
	weapon.upgrade_level = 1
	weapon.custom_properties = {"engraving":"Civic training blade"}
	loot.add_child(weapon)
	weapon.position = Vector3(13,0.2,25.2)
	loot.register_pickup(weapon)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_inventory_hold(true)
		if is_instance_valid(ui) and ui.is_open: ui.close_menu()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence_enabled and not networked(): save_checkpoint()

func _exit_tree() -> void:
	_exiting = true
