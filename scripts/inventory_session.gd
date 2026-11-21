extends Node
## Local UI/interaction and a single-player checkpoint, separate from host rules.
const Interface = preload("res://scripts/inventory_ui.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const TowerShop = preload("res://scripts/tower_shop.gd")
const Regions = preload("res://scripts/world_regions.gd")
const Shields = preload("res://scripts/shield_glyphs.gd")
const CheckpointEncoder = preload("res://scripts/checkpoint_encoder.gd")
const LOST_GEAR_HOLD_TIME := .7
const AUTOSAVE_DEBOUNCE := .75
const AUTOSAVE_INTERVAL := 15.0
var actor: CharacterBody3D
var controls: Node
var duel: CanvasLayer
var loot: Node3D
var population: Node3D
var boss_encounter: Node
var kyren_encounter: Node
var world_actions: Node3D
var dungeon_travel: Node
var civilian_services: Node
var glyphic_wonders: Node
var ui: CanvasLayer
var shop: CanvasLayer
@export var persistence_enabled := true
@export var save_path := "user://inventory_v1.json"
@export var live_session := false
var _loading := false
var _restoring_checkpoint := false
var _save_queued := false
var _save_again := false
var _autosave_wait := 0.0
var _autosave_failures := 0
var last_autosave_error := ""
var _encoder := CheckpointEncoder.new()
var last_capture_timings: Dictionary={}
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
	ui.type_filter.get_popup().window_input.connect(_popup_inventory_input)
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
	var civilization: Node=actor.get_parent().get("civilization")
	while is_instance_valid(civilization) and not civilization.ready_for_simulation:
		await get_tree().physics_frame
		if not is_inside_tree(): return
	var buildings: Node=actor.get_parent().get("building_civilization")
	while is_instance_valid(buildings) and not buildings.ready_for_use:
		await get_tree().physics_frame
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
	_close_communication("inventory")
	if not _inventory_allowed(): return
	if is_instance_valid(civilian_services) and civilian_services.menu.is_open: civilian_services.menu.close_menu()
	if is_instance_valid(glyphic_wonders) and glyphic_wonders.menu.is_open: glyphic_wonders.menu.close_menu()
	if shop.is_open: shop.close_menu()
	ui.toggle()

func _cancel_inventory_hold(clear_sources: bool = false) -> void:
	_inventory_pending = false
	_inventory_hold_elapsed = 0
	_inventory_hold_fired = false
	if clear_sources: _inventory_sources.clear()

func _input(event: InputEvent) -> void:
	# Search owns its text keys. In particular, typing B must not also toggle
	# the inventory, whichever node receives the input event first.
	if event is InputEventKey and (ui.search_focused() or (ui.is_open and ui.type_filter.get_popup().visible)):
		_inventory_sources.erase(_inventory_token(event))
		return
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

func _popup_inventory_input(event: InputEvent) -> void:
	# The native type menu has its own input viewport. Forward View/Select to
	# the same press/release owner so it still closes the inventory there.
	if event is InputEventJoypadButton and event.is_action("inventory_toggle"):
		ui.type_filter.get_popup().set_input_as_handled()
		_input(event)

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
	var world: Node=actor.get_parent()
	if is_instance_valid(world.get("career_menu")) and world.career_menu.menu.is_open: return
	if ui.is_open or shop.is_open or (is_instance_valid(world.get("communication")) and world.communication.is_open) or (is_instance_valid(world.get("building_civilization")) and world.building_civilization.menu.is_open) or (is_instance_valid(civilian_services) and civilian_services.menu.is_open) or (is_instance_valid(glyphic_wonders) and glyphic_wonders.menu.is_open) or (is_instance_valid(world.get("start_menu")) and world.start_menu.is_open) or actor.transition_locked or actor.health<=0 or _checkpoint_pending: return
	controls.set_gameplay_enabled(true)
	Input.mouse_mode = _previous_mouse
	_dirty()

func can_talk() -> bool:
	if _checkpoint_pending: return false
	if ui.is_open or not controls.gameplay_enabled or duel.dialogue_open or duel.active: return false
	if is_instance_valid(actor.get_parent().get("building_civilization")) and not actor.get_parent().building_civilization.nearest().is_empty(): return true
	if is_instance_valid(dungeon_travel):
		if dungeon_travel.busy: return false
		if dungeon_travel.focused_door()!=null: return true
		if dungeon_travel.is_wonders(): return loot.nearest_pickup(actor)!=null or not glyphic_wonders.nearest().is_empty()
		if dungeon_travel.is_pyramid(): return loot.nearest_pickup(actor)!=null
		if dungeon_travel.is_rental():
			return not civilian_services.nearest().is_empty() or loot.nearest_pickup(actor)!=null or not world_actions.nearest().is_empty()
	if is_instance_valid(civilian_services) and not civilian_services.nearest().is_empty(): return true
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
		if dungeon_travel.is_wonders():
			if item!=null: loot.request_pickup(actor.inventory,item)
			else: glyphic_wonders.interact()
			return
		if dungeon_travel.is_pyramid():
			if item!=null: loot.request_pickup(actor.inventory,item)
			return
		if dungeon_travel.is_rental():
			# Outdoor conversation/exchange helpers cache physical actors. Only
			# this room's services, loot and world-scoped furniture belong here.
			if item!=null: loot.request_pickup(actor.inventory,item)
			elif world_actions.attached(): world_actions.leave()
			elif not civilian_services.interact(): world_actions.interact()
			return
	if is_instance_valid(kyren_encounter):
		if kyren_encounter.active: return
		if kyren_encounter.can_talk() and loot.nearest_pickup(actor)==null:
			kyren_encounter.interact()
			return
	if is_instance_valid(world_actions) and world_actions.attached():
		world_actions.leave()
		return
	var building: Node=actor.get_parent().get("building_civilization")
	if is_instance_valid(building) and loot.nearest_pickup(actor)==null and (not is_instance_valid(world_actions) or world_actions.nearest().is_empty()) and building.interact(): return
	if is_instance_valid(civilian_services) and loot.nearest_pickup(actor)==null and civilian_services.interact(): return
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
			if is_instance_valid(actor.get_parent().get("civic_interactions")) and actor.get_parent().civic_interactions.begin_for_source(resident): return
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
	_poll_autosave()
	_autosave_wait=maxf(0,_autosave_wait-delta)
	if _save_queued and not _encoder.pending() and _autosave_wait<=0: _autosave()
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
		if dungeon_travel.is_pyramid():
			var item: Node3D=loot.nearest_pickup(actor)
			if item!=null: hint.text="G / RT: collect "+item.interaction_name()
			return
		if dungeon_travel.is_wonders():
			var item: Node3D=loot.nearest_pickup(actor)
			var merchandise: Dictionary=glyphic_wonders.nearest()
			if item!=null: hint.text="G / tap RT: collect "+item.interaction_name()
			elif not merchandise.is_empty(): hint.text="G / tap RT: "+String(merchandise.label)
			return
		if dungeon_travel.is_rental():
			var item: Node3D=loot.nearest_pickup(actor)
			var service: Dictionary=civilian_services.nearest()
			var furniture: Dictionary=world_actions.nearest()
			if item!=null: hint.text="G / RT: collect "+item.interaction_name()
			elif world_actions.attached(): hint.text="G / tap RT / move / jump: stand up"
			elif not service.is_empty(): hint.text="G / tap RT: "+String(service.label)
			elif not furniture.is_empty(): hint.text="G / tap RT: "+String(furniture.label)
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
	elif is_instance_valid(civilian_services) and not civilian_services.nearest().is_empty(): hint.text="G / tap RT: "+String(civilian_services.nearest().label)
	elif shop.can_use(actor): hint.text = "G / tap RT: Tower Exchange"
	elif is_instance_valid(world_actions) and not world_actions.nearest().is_empty(): hint.text = "G / tap RT: "+world_actions.nearest().label
	elif is_instance_valid(actor.get_parent().get("building_civilization")) and not actor.get_parent().building_civilization.nearest().is_empty(): hint.text="G / tap RT: building / furnishings"
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
		var route := "return through the guild room door" if dungeon_travel.is_rental(location) or dungeon_travel.is_rental() else "return through the pyramid doorway"
		if dungeon_travel.is_wonders(location) or dungeon_travel.is_wonders(): route="return through the Glyphic Wonders doorway"
		loss_hint.text="LOST GEAR  |  %s  |  %s  |  %d unclaimed" % [dungeon_travel.location_label(location,point),route,entries.size()]
		return
	if is_instance_valid(dungeon_travel) and (dungeon_travel.is_rental(location) or dungeon_travel.is_wonders(location)):
		loss_hint.text="LOST GEAR  %.0f m  |  %s  |  %d unclaimed" % [distance,dungeon_travel.location_label(location,point),entries.size()]
		return
	if location!=&"overworld":
		var floor_text: String=dungeon_travel.interior.floor_label(point) if is_instance_valid(dungeon_travel) else ""
		loss_hint.text="LOST GEAR  %.0f m  |  PYRAMID %s  X %.0f  Z %.0f  |  %d unclaimed" % [distance,floor_text,point.x,point.z,entries.size()]
		return
	loss_hint.text = "LOST GEAR  %.0f m  |  %s  |  ALT %.0f m  |  %d unclaimed" % [distance,Regions.grid_label(Regions.grid_at(point)),point.y,entries.size()]

func _dirty() -> void:
	if _exiting or not is_inside_tree() or _loading or _checkpoint_pending or not persistence_enabled or networked(): return
	var society: Node=actor.get_parent().get("civilization")
	# Background commerce is checkpointed with the coalesced society clock.
	# Player purchases still request a save as soon as their transaction ends.
	if is_instance_valid(society) and society.transaction_active(): return
	if _save_queued:
		_save_again=true
		return
	_save_queued = true
	_autosave_wait=maxf(_autosave_wait,AUTOSAVE_DEBOUNCE)

func _autosave() -> void:
	if not _save_queued or _encoder.pending() or _autosave_wait>0: return
	if not is_inside_tree() or _exiting or not persistence_enabled or networked(): _save_queued=false; return
	_save_again=false
	var snapshot:=_capture_checkpoint()
	if snapshot.is_empty(): _autosave_wait=AUTOSAVE_DEBOUNCE; return
	var error: Error=_encoder.start_owned(snapshot)
	if error!=OK:
		_autosave_failed(error,"capture validation")

func _autosave_failed(error: int, stage: String) -> void:
	# Keep the newest live state dirty. A rejected job must never cause an
	# immediate capture/encode loop, especially on a large populated checkpoint.
	_save_queued=true
	_save_again=false
	_autosave_failures+=1
	_autosave_wait=minf(120,15*pow(2,mini(3,_autosave_failures-1)))
	var detail:="%s: %s" % [stage,error_string(error)]
	if detail!=last_autosave_error:
		push_warning("Inventory autosave rejected at "+detail+"; retaining live items and delaying retries.")
	if _autosave_failures==1: show_notice("Inventory autosave failed; current items remain in memory. Retrying shortly.",6)
	last_autosave_error=detail

func _poll_autosave() -> void:
	if not _encoder.ready(): return
	var result: Dictionary=_encoder.take_result()
	if _exiting or not persistence_enabled or networked(): _save_queued=false; _save_again=false; return
	var error:=int(result.get("error",ERR_INVALID_DATA))
	if error==OK: error=Store._commit_encoded(save_path,result.bytes)
	if error!=OK:
		_autosave_failed(error,String(result.get("stage","disk commit")))
		return
	_save_queued=false
	_autosave_failures=0
	last_autosave_error=""
	_autosave_wait=AUTOSAVE_INTERVAL
	if _save_again:
		_save_again=false
		_dirty()

func _discard_autosave() -> void:
	_encoder.finish(true)
	_save_queued=false
	_save_again=false
	_autosave_wait=0
	_autosave_failures=0
	last_autosave_error=""

func _capture_checkpoint() -> Dictionary:
	if _exiting or _loading or _checkpoint_pending or not is_inside_tree() or loot.transaction_active() or networked(): return {}
	if _civic_busy(): return {}
	var civilization: Node=actor.get_parent().get("civilization")
	if is_instance_valid(civilization) and (not civilization.ready_for_simulation or civilization.transaction_active()): return {}
	last_capture_timings={}
	var began:=Time.get_ticks_usec()
	var location: String=String(dungeon_travel.active_location) if is_instance_valid(dungeon_travel) else "overworld"
	var state: Dictionary=dungeon_travel.location_state() if is_instance_valid(dungeon_travel) else {}
	var civilian: Dictionary=civilian_services.economy.capture_values() if is_instance_valid(civilian_services) else {}
	last_capture_timings["economy"]=float(Time.get_ticks_usec()-began)/1000.0
	var society: Dictionary=civilization.capture_values() if is_instance_valid(civilization) else {}
	last_capture_timings["society"]=float(Time.get_ticks_usec()-began)/1000.0
	var snapshot: Dictionary={"version":Store.VERSION,"policy":Store.POLICY,"session_id":loot.session_id,"inventory":actor.inventory.capture_values(),"world_drops":loot.serialize_world(),"markers":[]}
	last_capture_timings["core"]=float(Time.get_ticks_usec()-began)/1000.0
	if location!="overworld": snapshot.location_context=location
	if not state.is_empty(): snapshot.location_state=state
	if not civilian.is_empty(): snapshot.civilian_state=civilian
	if not society.is_empty(): snapshot.civilization_state=society
	last_capture_timings["inventory"]=float(Time.get_ticks_usec()-began)/1000.0
	if is_instance_valid(glyphic_wonders): snapshot.glyphic_wonders_state=glyphic_wonders.serialize()
	last_capture_timings["stock"]=float(Time.get_ticks_usec()-began)/1000.0
	if is_instance_valid(actor.get_parent().get("civic_interactions")):
		snapshot.quest_state=actor.get_parent().quest_system.serialize()
		snapshot.communication_state=actor.get_parent().communication.serialize()
		snapshot.law_state=actor.get_parent().law.serialize()
	last_capture_timings["civic"]=float(Time.get_ticks_usec()-began)/1000.0
	if is_instance_valid(actor.get_parent().get("building_civilization")): snapshot.building_state=actor.get_parent().building_civilization.serialize()
	last_capture_timings["buildings"]=float(Time.get_ticks_usec()-began)/1000.0
	if is_instance_valid(actor.get_parent().get("careers")): snapshot.career_state=actor.get_parent().careers.serialize()
	last_capture_timings["careers"]=float(Time.get_ticks_usec()-began)/1000.0
	if is_instance_valid(actor.get_parent().get("dark_box_patrols")): snapshot.dark_box_state=actor.get_parent().dark_box_patrols.serialize()
	last_capture_timings["patrol"]=float(Time.get_ticks_usec()-began)/1000.0
	return snapshot

func _civic_busy() -> bool:
	var world: Node=actor.get_parent()
	var patrol: Node=world.get("dark_box_patrols")
	if is_instance_valid(patrol) and patrol.has_method("transaction_active") and patrol.transaction_active(): return true
	if is_instance_valid(world.get("careers")) and world.careers.transaction_active(): return true
	if world.get("career_actions")!=null and world.career_actions.transaction_active(): return true
	if is_instance_valid(world.get("building_civilization")) and (not world.building_civilization.ready_for_use or world.building_civilization.transaction_active()): return true
	return is_instance_valid(world.get("civic_interactions")) and (world.civic_interactions.get("_busy")==true or world.civic_interactions.trade.transaction_active() or world.law.get("_busy")==true or world.quest_system.transaction_active() or world.communication.transaction_active())

func _close_communication(reason: String) -> void:
	var world: Node=actor.get_parent()
	if is_instance_valid(world.get("career_menu")): world.career_menu.close_menu()
	if is_instance_valid(world.get("communication")): world.communication.close_conversation(reason)
	if is_instance_valid(world.get("building_civilization")) and world.building_civilization.menu.is_open: world.building_civilization.menu.close_menu()

func _capture_civic() -> Dictionary:
	var world: Node=actor.get_parent()
	if not is_instance_valid(world.get("civic_interactions")): return {}
	var state:={"quest_state":world.quest_system.serialize(),"communication_state":world.communication.serialize(),"law_state":world.law.serialize()}
	if is_instance_valid(world.get("careers")): state.career_state=world.careers.serialize()
	return state

func _restore_civic(snapshot: Dictionary) -> bool:
	var world: Node=actor.get_parent()
	if not is_instance_valid(world.get("civic_interactions")): return true
	_close_communication("checkpoint")
	world.civic_interactions.trade.clear()
	return world.quest_system.restore(snapshot.get("quest_state")) and world.communication.restore(snapshot.get("communication_state")) and world.law.restore(snapshot.get("law_state")) and (not is_instance_valid(world.get("careers")) or world.careers.restore(snapshot.get("career_state")))

func _prepare_checkpoint_borrowers() -> void:
	var errands: Node=actor.get_parent().get("civilian_errands")
	if is_instance_valid(errands): errands.clear()
	var world: Node=actor.get_parent()
	for key: String in ["dark_box_patrols","theft_reactions"]:
		var adapter: Node=world.get(key)
		if is_instance_valid(adapter) and adapter.has_method("prepare_restore"): adapter.prepare_restore()

func save_checkpoint(path: String = "", silent: bool = false) -> bool:
	if _exiting or _loading or _checkpoint_pending or not is_inside_tree(): return false
	if loot.transaction_active(): return false
	var civilization: Node=actor.get_parent().get("civilization")
	if is_instance_valid(civilization) and (not civilization.ready_for_simulation or civilization.transaction_active()): return false
	if networked():
		show_notice("Session ownership is saved by the host.")
		return false
	_discard_autosave()
	var destination := path if not path.is_empty() else save_path
	# One validation in Store.store is sufficient for this authority-owned
	# capture; avoid validating thousands of civilian records twice per save.
	var snapshot: Dictionary=_capture_checkpoint()
	var error: Error = Store.store(destination,snapshot)
	if error != OK:
		show_notice("Inventory save failed; current items remain in memory.",6)
		return false
	if not silent: show_notice("Inventory and world drops saved.")
	return true

func load_checkpoint(path: String = "") -> bool:
	if _restoring_checkpoint or networked() or loot.transaction_active() or _civic_busy(): return false
	var civilization: Node=actor.get_parent().get("civilization")
	if is_instance_valid(civilization) and (not civilization.ready_for_simulation or civilization.transaction_active()): return false
	var source := path if not path.is_empty() else save_path
	var snapshot: Dictionary = Store.load_snapshot(source)
	if snapshot.is_empty() or snapshot.session_id != loot.session_id or snapshot.inventory.owner_id != actor.inventory.owner_id: return false
	var location:=StringName(snapshot.get("location_context","overworld"))
	if is_instance_valid(dungeon_travel):
		if not dungeon_travel.can_load_location(location): return false
	elif location!=&"overworld": return false
	_discard_autosave()
	var owned_before: Dictionary = actor.inventory.serialize()
	var world_before: Array = loot.serialize_world()
	var civilian_before: Dictionary=civilian_services.economy.serialize() if is_instance_valid(civilian_services) else {}
	var society_before: Dictionary=civilization.serialize() if is_instance_valid(civilization) else {}
	var wonders_before: Dictionary=glyphic_wonders.serialize() if is_instance_valid(glyphic_wonders) else {}
	var civic_before:=_capture_civic()
	var buildings: Node=actor.get_parent().get("building_civilization")
	var building_before: Dictionary=buildings.serialize() if is_instance_valid(buildings) else {}
	var patrol: Node=actor.get_parent().get("dark_box_patrols")
	var patrol_before: Dictionary=patrol.serialize() if is_instance_valid(patrol) else {}
	_loading = true
	_restoring_checkpoint = true
	# Officer bodies borrow authoritative NPC inventory Nodes. Detach their
	# signal bindings and combat rigs while those stores are still alive;
	# economy.restore replaces and frees every NPC store synchronously.
	_prepare_checkpoint_borrowers()
	var ok: bool = actor.inventory.restore(snapshot.inventory)
	if ok and is_instance_valid(civilian_services): ok=civilian_services.economy.restore(snapshot.get("civilian_state",civilian_services.initial_state))
	if ok and is_instance_valid(civilization): ok=civilization.restore(snapshot.get("civilization_state"),false)
	if ok and is_instance_valid(glyphic_wonders): ok=glyphic_wonders.restore(snapshot.get("glyphic_wonders_state"))
	if ok: ok=_restore_civic(snapshot)
	if ok and is_instance_valid(buildings): ok=buildings.restore(snapshot.get("building_state"))
	if ok and is_instance_valid(patrol): ok=patrol.restore(snapshot.get("dark_box_state"))
	var world_changed := false
	if ok:
		ok = loot.restore_world(snapshot.world_drops)
		world_changed = ok
	if ok and is_instance_valid(dungeon_travel): ok=dungeon_travel.restore_location(location,snapshot.get("location_state",{}))
	if not ok:
		# A later adapter may have rejected an otherwise valid snapshot. Tear
		# down any rebound bodies before the rollback replaces their stores too.
		_prepare_checkpoint_borrowers()
		actor.inventory.restore(owned_before)
		if is_instance_valid(civilian_services): civilian_services.economy.restore(civilian_before)
		if is_instance_valid(civilization): civilization.restore(society_before,false)
		if is_instance_valid(glyphic_wonders): glyphic_wonders.restore(wonders_before)
		_restore_civic(civic_before)
		if is_instance_valid(buildings): buildings.restore(building_before)
		if is_instance_valid(patrol): patrol.restore(patrol_before)
		# restore_world is already atomic on rejection. Replacing untouched
		# drops here would leave duplicate pending colliders until frame end.
		if world_changed: loot.restore_world(world_before)
	if ok and is_instance_valid(civilization) and _checkpoint_pending:
		# Catch-up runs once at startup, after the whole checkpoint has committed.
		var saved_at: float=float(snapshot.get("civilization_state",{}).get("saved_unix",Time.get_unix_time_from_system()))
		if not civilization.advance_real(maxf(0,Time.get_unix_time_from_system()-saved_at),true):
			show_notice("World restored. Offline simulation could not advance: "+String(civilization.last_error),10)
	if ok and is_instance_valid(glyphic_wonders): glyphic_wonders.refresh_stock()
	if ok and is_instance_valid(civilian_services): civilian_services.food_effect={}
	if ok and is_instance_valid(actor.get_parent().get("civic_interactions")): actor.get_parent().civic_interactions.restored_state(snapshot.has("quest_state"))
	_loading = false
	_restoring_checkpoint = false
	return ok

func seed_demo_loot() -> void:
	# Editor-style instances demonstrate collection without changing starter gear.
	var definitions: Array = [Catalog.get_definition(&"light_shard"),Catalog.get_definition(&"signal_tonic")]
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
	_encoder.finish(true)
