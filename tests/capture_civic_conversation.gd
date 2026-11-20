extends SceneTree
## Native production-world communication/input review. All funding remains real;
## extra long-title patrols are fixture publications through the quest authority.
var world: Node3D
var actor: CharacterBody3D
var ui: CanvasLayer
var checks:=0
var failures:=0

func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func pad(button: JoyButton,down: bool) -> void:
	var event:=InputEventJoypadButton.new()
	event.button_index=button; event.pressed=down
	root.push_input(event)
func key(code: Key,down: bool=true) -> void:
	var event:=InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=down
	root.push_input(event)
func tap_key(code: Key) -> void:
	key(code); await frames(1); key(code,false); await frames(1)
func finish_exchange() -> void:
	for i in range(10):
		ui.finish_line()
		if ui._queue.is_empty(): break
		ui.advance()
	ui.finish_line()
func no_combat() -> bool:
	return actor.weapon_combat.active_move.is_empty() and actor.combat.charge_action==&"" and not actor.dodge.active and not actor._jump_after_dodge

func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("Civic native review watchdog"); quit(2))
	root.content_scale_size=Vector2i(1280,720)
	root.size=Vector2i(1280,720)
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	actor=world.player
	ui=world.communication
	actor.visual.retrieval.enabled=false
	world.sparring_partner.visual.retrieval.enabled=false
	world.civilization.simulation_enabled=false
	for i in range(360):
		await frames(1)
		if world.civic_interactions.initialized: break
	var civic: Node=world.civic_interactions
	check(civic.initialized,"Actual world initializes civic authorities for native input review")
	if not civic.initialized: world.queue_free(); await frames(); quit(1); return
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	var board: Dictionary={}
	for point: Dictionary in world.civilian_services.establishments.points:
		if point.get("id")=="board_security": board=point; break
	check(not board.is_empty(),"Production Security board has a physical interaction anchor")
	if board.is_empty(): world.queue_free(); await frames(); quit(1); return
	actor.global_position=board.anchor.global_position+Vector3(0,.3,1.4)
	actor.velocity=Vector3.ZERO
	actor.fall_damage.reset()
	actor.visual.rebase_after_phase()
	await frames(12)
	check(world.civilian_services.near(board) and civic.begin_service(board,""),"The real nearby Security board opens the shared channel")
	check(ui.is_open and not world.controls.gameplay_enabled and not paused,"Production session gates gameplay while the city remains live")
	pad(JOY_BUTTON_Y,true)
	check(not world.quest_system.is_member("player","security"),"The first Y finishes greeting text without silently joining")
	pad(JOY_BUTTON_Y,true)
	check(not world.quest_system.is_member("player","security"),"A repeated held Y cannot choose a contextual action")
	pad(JOY_BUTTON_Y,false)
	pad(JOY_BUTTON_Y,true); pad(JOY_BUTTON_Y,false)
	check(world.quest_system.is_member("player","security"),"A released fresh controller Y joins through the real membership authority")
	finish_exchange()
	check("Membership recorded" in ui.latest_text and "security" in ui.latest_text,"The actual authoritative membership reply is visible")
	# Exercise all six bounded cards with real escrow rather than fake UI rows.
	var title: String=world.quest_system.model.templates.security_service.title
	world.quest_system.model.templates.security_service.title="Public safety patrol across the outer city neighborhoods and lantern-lit residential streets"
	var published:=0
	civic._busy=true
	var target: String="place/"+String(world.population.points.keys()[0])
	for i in range(5):
		var id: String=world.quest_system.create_contract("security_service","faction/security","faction:security",{"need_id":"native_ui_patrol/"+str(i),"target_id":target,"service":"patrol"},civic._now())
		if not id.is_empty(): published+=1
	civic._busy=false
	world.quest_system.model.templates.security_service.title=title
	check(published==5,"Five long-title fixture patrols reserve actual finite Security treasury funds")
	await tap_key(KEY_Q)
	check(ui.branch=="quests" and ui.nodes.size()==6,"Keyboard Q opens the real six-card funded-work branch")
	# The same space/A used to jump must be consumed while text is being shown.
	var before_y: float=actor.global_position.y
	key(KEY_SPACE); key(KEY_SPACE,false)
	finish_exchange()
	await frames(4)
	check(no_combat() and actor.global_position.y<=before_y+.1 and actor.velocity.y<1,"Conversation keyboard/controller input cannot leak attacks, dodges or a jump")
	check("Rewards are held in escrow" in ui.latest_text,"Real work instructions survive authored wording in the subtitle")
	for i in range(30): await process_frame; await RenderingServer.frame_post_draw
	var fit:=root.get_visible_rect().encloses(ui._panel.get_global_rect())
	for label: Label in ui._labels:
		if label.is_visible_in_tree():
			fit=fit and root.get_visible_rect().encloses(label.get_global_rect())
			print("CIVIC LABEL ",label.text," rect=",label.get_global_rect()," lines=",label.get_line_count())
	check(fit,"Six long contract cards, reply and footer fit the 1280-by-720 production viewport")
	if "--capture" in OS.get_cmdline_user_args():
		check(root.get_texture().get_image().save_png("res://.godot/civic-conversation.png")==OK,"Native civic conversation screenshot is saved")
	await tap_key(KEY_ESCAPE)
	check(not ui.is_open and not world.start_menu.is_open and world.controls.gameplay_enabled,"Escape closes communication without opening the system menu")
	check(civic.begin_service(board,""),"Board communication reopens after a clean exit")
	await tap_key(KEY_B)
	check(not ui.is_open and world.inventory_session.ui.is_open and not world.controls.gameplay_enabled,"Inventory replaces the conversation cleanly through its actual keyboard mapping")
	world.inventory_session.ui.close_menu()
	check(world.controls.gameplay_enabled and no_combat(),"Closing inventory restores gameplay without queued combat input")
	print("Civic native communication verification: ",checks," checks, ",failures," failures")
	world.queue_free(); await frames(3)
	quit(1 if failures else 0)
