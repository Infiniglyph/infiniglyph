extends SceneTree
## Route real key/GUI/controller events through the complete live game scene.
const Catalog = preload("res://scripts/item_catalog.gd")
var world: Node3D
var actor: CharacterBody3D
var controls: Node
var ui: CanvasLayer
var checks := 0
var failures := 0
var attacks := 0
var leaked := false

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
		if is_instance_valid(ui) and ui.is_open:
			leaked = leaked or controls.gameplay_enabled or not controls.move.is_zero_approx() or controls.jump_requested or controls.dodge_requested or actor.dodge.active or not actor.weapon_combat.active_move.is_empty()

func key(code: Key, character: String = "", ctrl: bool = false, echo: bool = false) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.window_id = ui.type_filter.get_popup().get_window_id() if ui.type_filter.get_popup().visible else root.get_window_id()
		event.physical_keycode = code
		event.unicode = character.unicode_at(0) if pressed and not character.is_empty() else 0
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		event.echo = echo and pressed
		Input.parse_input_event(event)
		await frames(1)

func pad(code: JoyButton) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames(1)

func clear_text() -> void:
	await key(KEY_A,"",true)
	await key(KEY_BACKSPACE)

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	actor = world.player
	controls = world.controls
	ui = world.inventory_session.ui
	actor.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	actor.weapon_combat.attack_started.connect(func(_move: Dictionary): attacks += 1)
	actor.inventory.add_item(Catalog.create(&"paintbrush_cyan"))
	actor.inventory.add_item(Catalog.create(&"paintbrush_gold"))
	await frames(20)
	check(not ui.is_open and controls.gameplay_enabled,"The real scene starts with inventory closed and gameplay enabled")
	await key(KEY_B,"b")
	check(ui.is_open and not controls.gameplay_enabled,"The mapped keyboard B event opens the inventory and captures gameplay")
	var origin: Vector3 = actor.global_position
	var elapsed: float = world.population.elapsed
	await key(KEY_SLASH,"/")
	check(ui.search_focused() and ui.query.text.is_empty(),"Slash focuses the native search field without inserting a slash")
	await key(KEY_B,"b")
	check(ui.is_open and ui.search_focused() and ui.query.text=="b","Typing B remains text rather than toggling the inventory")
	for entry: Array in [[KEY_R,"r"],[KEY_U,"u"],[KEY_S,"s"],[KEY_H,"h"]]: await key(entry[0],entry[1])
	check(ui.query.text=="brush" and ui.filtered_ids.size()==2,"Real Unicode key events build brush and filter to the two owned brushes")
	check(ui.category_index==0 and ui.type_filter.selected==0 and ui.mode.is_empty(),"Search typing preserves category, type and action-menu state")
	await key(KEY_ENTER)
	check(ui.is_open and not ui.search_focused() and ui.mode.is_empty(),"Enter first leaves search without activating an item action")
	check(not world.start_menu.is_open,"Leaving search cannot open Start or Settings")
	await key(KEY_SLASH,"/")
	await clear_text()
	check(ui.search_focused() and ui.query.text.is_empty(),"Native Ctrl+A and Backspace edit search without inventory shortcuts")
	for entry: Array in [[KEY_W,"w"],[KEY_A,"a"],[KEY_S,"s"],[KEY_D,"d"],[KEY_F,"f"],[KEY_SPACE," "],[KEY_E,"e"],[KEY_Q,"q"]]: await key(entry[0],entry[1])
	check(ui.query.text=="wasdf eq","WASD, F, Space and gameplay keys remain ordinary search text")
	check(ui.category_index==0 and ui.type_filter.selected==0 and ui.tab_index==0 and ui.mode.is_empty(),"Text navigation letters cannot change categories, filters, tabs or actions")
	check(Vector2(actor.position.x-origin.x,actor.position.z-origin.z).length()<0.02 and not leaked and attacks==0,"Typing never moves, jumps, dodges or attacks with the player")
	check(not paused and world.population.elapsed>elapsed,"Inventory search leaves the world and NPC simulation running")
	await key(KEY_ESCAPE)
	check(ui.is_open and not ui.search_focused() and not world.start_menu.is_open,"Escape first blurs search without closing inventory or opening Start")
	await key(KEY_B,"b")
	check(not ui.is_open and controls.gameplay_enabled and not world.start_menu.is_open,"B closes inventory after search has relinquished focus")
	await key(KEY_B,"b")
	await key(KEY_SLASH,"/")
	check(ui.is_open and ui.search_focused(),"Keyboard inventory can reopen and focus search after a text B press")
	await pad(JOY_BUTTON_BACK)
	check(not ui.is_open and controls.gameplay_enabled and not ui.query.has_focus(),"Controller Select closes inventory even while search owns keyboard focus")
	await pad(JOY_BUTTON_BACK)
	check(ui.is_open and not controls.gameplay_enabled,"Controller Select reopens the same inventory normally")
	var filter_before: int = ui.type_filter.selected
	var text_before: String = ui.query.text
	await key(KEY_F,"f")
	check(ui.type_filter.selected==posmod(filter_before+1,ui.type_filter.item_count) and ui.query.text==text_before,"F outside search cycles the type exactly once without appending text")
	filter_before = ui.type_filter.selected
	await key(KEY_SLASH,"/")
	await pad(JOY_BUTTON_Y)
	check(ui.type_filter.selected==posmod(filter_before+1,ui.type_filter.item_count) and not ui.search_focused(),"Controller Y cycles the type from focused search without a weapon art")
	check(ui.mode.is_empty() and attacks==0 and not leaked and controls._combat_requests.is_empty(),"Inventory filter controls never leak combat or dodge requests")
	ui.type_filter.get_popup().popup()
	await frames()
	check(ui.type_filter.get_popup().visible,"The real inventory's native type dropdown is open for window input")
	await key(KEY_B,"b")
	check(ui.is_open and ui.type_filter.get_popup().visible and not controls.gameplay_enabled,"Keyboard B inside the native dropdown cannot toggle the inventory")
	await key(KEY_ESCAPE)
	check(ui.is_open and not ui.type_filter.get_popup().visible and not world.start_menu.is_open,"Escape closes the native dropdown before the inventory or Start menu")
	ui.type_filter.get_popup().popup()
	await frames()
	await pad(JOY_BUTTON_BACK)
	check(not ui.is_open and not ui.type_filter.get_popup().visible and controls.gameplay_enabled,"Controller Select closes inventory and its open dropdown together")
	await pad(JOY_BUTTON_BACK)
	check(ui.is_open and not ui.type_filter.get_popup().visible,"Reopening inventory cannot leave an earlier native dropdown stranded")
	await key(KEY_SLASH,"/")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(not ui.is_open and not world.start_menu.is_open and controls.gameplay_enabled,"A second Escape closes the inventory and restores gameplay without opening Start")
	check(world.inventory_session._inventory_sources.is_empty() and not world.inventory_session._inventory_pending,"Text and menu events leave no stale inventory hold sources")
	world.queue_free()
	await frames(2)
	print("Inventory search input verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
