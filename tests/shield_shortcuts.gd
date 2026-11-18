extends SceneTree
## Exercise the real input, inventory transaction and live HUD together.
const Catalog = preload("res://scripts/item_catalog.gd")
var world: Node3D
var actor: CharacterBody3D
var controls: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func button(code: JoyButton, pressed: bool = true) -> void:
	var event:=InputEventJoypadButton.new()
	event.button_index=code
	event.pressed=pressed
	controls._unhandled_input(event)

func trigger(value: float) -> void:
	var event:=InputEventJoypadMotion.new()
	event.axis=JOY_AXIS_TRIGGER_RIGHT
	event.axis_value=value
	controls._unhandled_input(event)

func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=pressed
	event.echo=echo
	controls._unhandled_input(event)

func chord() -> void:
	trigger(.9)
	button(JOY_BUTTON_B)
	controls.update_combat_hold(controls.SHIELD_HOLD_TIME+.01)
	button(JOY_BUTTON_B,false)
	trigger(0)

func deplete(points: float) -> void:
	actor.weapon_combat.receive_hit(points,actor.global_position+Vector3.FORWARD,null,{"action":&"attack_right"})

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	actor=world.player
	actor.visual.retrieval.enabled=false
	actor.set_physics_process(false)
	controls=world.controls
	await frames(8)
	var inventory: Node=actor.inventory
	var actions: Node3D=world.world_actions
	var session: Node=world.inventory_session
	var health_glyphs: int=inventory.count_type(&"health_glyph")
	check(actions.shield_glyph_count.text=="Shield Glyphs  0","The live counter starts at the actual empty shield inventory")
	button(JOY_BUTTON_A)
	check(controls.consume_jump() and not controls.consume_shield(),"A alone still jumps")
	button(JOY_BUTTON_A)
	check(not controls.consume_jump(),"A held or duplicate down events cannot repeat a jump")
	button(JOY_BUTTON_A,false)
	key(KEY_SPACE)
	check(controls.consume_jump() and not controls.consume_shield(),"Physical Space alone still jumps")
	key(KEY_SPACE,false)
	# Deliberately insert the weakest first: priority must not follow slot order.
	for tier: String in ["light","medium","heavy"]:
		inventory.add_item(Catalog.create(StringName("shield_glyph_"+tier),2 if tier=="light" else 1))
	check(actions.shield_glyph_count.text=="Shield Glyphs  4","The counter totals all three owned tiers")
	check(actions.shield_glyph_count.get_global_rect().end.y<=actions.glyph_count.get_global_rect().position.y and root.get_visible_rect().encloses(actions.shield_glyph_count.get_global_rect()),"Shield count fits immediately above Health Glyphs without overlapping")
	check(actions.vehicle_status.get_global_rect().end.y<=actions.shield_glyph_count.get_global_rect().position.y,"Driving status has its own row above both glyph counters")
	var bench: Dictionary=actions.seats[0]
	actor.global_position=bench.point+bench.forward*1.1
	actor.global_position.y=.05
	actor.velocity=Vector3.ZERO
	actor.set_physics_process(true)
	await frames(15)
	actor.set_physics_process(false)
	check(session.can_talk(),"The shortcut fixture is beside a real available RT interaction")
	trigger(.9)
	check(controls._rt_pending,"A bare RT press would normally interact with this bench on release")
	button(JOY_BUTTON_B)
	controls.update_combat_hold(controls.SHIELD_HOLD_TIME-.01)
	check(not controls.shield_requested and not controls.heal_requested and not controls.dodge_requested,"RT+B waits for the hold without healing or dodging")
	controls.update_combat_hold(.02)
	check(controls.shield_requested and not controls.jump_requested and not controls.heal_requested,"Holding RT+B exclusively requests a shield")
	trigger(0)
	check(not controls.consume_interaction(),"Releasing RT after shield use cannot trigger an interaction")
	await frames()
	check(actor.weapon_combat.shield_points==1000 and inventory.count_type(&"shield_glyph_heavy")==0 and actions.shield_glyph_count.text=="Shield Glyphs  3","Quick use consumes exactly one heavy glyph first and refreshes the counter")
	check(not actions.attached() and not session.ui.is_open,"Shield use beside the bench neither sits down nor opens a menu")
	button(JOY_BUTTON_B)
	controls.update_combat_hold(2)
	check(not controls.shield_requested and not controls.heal_requested and not controls.dodge_requested,"A long hold and duplicate B-down cannot repeat a shield, heal or dodge")
	button(JOY_BUTTON_B,false)
	check(not controls.consume_heal(),"Releasing a completed shield hold never heals")
	chord()
	await frames()
	check(actions.shield_glyph_count.text=="Shield Glyphs  3" and actor.weapon_combat.shield_points==1000,"A full stronger shield does not waste a medium glyph")
	deplete(1000)
	key(KEY_V)
	key(KEY_H)
	controls.update_combat_hold(controls.SHIELD_HOLD_TIME+.01)
	check(controls.shield_requested and not controls.heal_requested,"Holding V+H is the corresponding keyboard shield chord")
	key(KEY_H,true,true)
	await frames()
	check(actor.weapon_combat.shield_points==500 and inventory.count_type(&"shield_glyph_medium")==0 and actions.shield_glyph_count.text=="Shield Glyphs  2","The keyboard chord falls back to medium when no heavy remains")
	key(KEY_H)
	controls.update_combat_hold(2)
	check(not controls.shield_requested and not controls.heal_requested,"Held H, repeats and key echo do not re-use a glyph")
	key(KEY_H,false)
	key(KEY_V,false)
	deplete(500)
	chord()
	await frames()
	check(actor.weapon_combat.shield_points==250 and inventory.count_type(&"shield_glyph_light")==1 and actions.shield_glyph_count.text=="Shield Glyphs  1","The next chord uses one light glyph when higher tiers are gone")
	check(inventory.count_type(&"health_glyph")==health_glyphs and actor.health==1000,"Shield chords preserve health glyphs and HP")
	deplete(250)
	var reentered: Array[bool]=[false]
	var callback:=func():
		if world.loot.request_shield_glyph(inventory): reentered[0]=true
	inventory.changed.connect(callback)
	chord()
	await frames()
	inventory.changed.disconnect(callback)
	check(not reentered[0] and actions.shield_glyph_count.text=="Shield Glyphs  0","The final glyph is consumed once even when an inventory callback tries to reenter")
	deplete(250)
	chord()
	await frames()
	check(actor.weapon_combat.shield_points==0 and session.notice.text=="No Shield Glyphs available.","Empty quick use consumes nothing and gives readable feedback")
	inventory.add_item(Catalog.create(&"shield_glyph_heavy",2))
	world.loot.host_enabled=false
	chord()
	await frames()
	check(inventory.count_type(&"shield_glyph_heavy")==2 and actor.weapon_combat.shield_points==0,"A non-authoritative client cannot consume a glyph through the shortcut")
	world.loot.host_enabled=true
	actor.transition_locked=true
	chord()
	await frames()
	check(inventory.count_type(&"shield_glyph_heavy")==2,"Pyramid phase transitions reject shield consumption")
	actor.transition_locked=false
	chord()
	session.ui.open_menu()
	check(not controls.shield_requested and not controls.gameplay_enabled and not paused,"Opening Inventory clears a pending shield chord without pausing the world")
	chord()
	await frames()
	check(inventory.count_type(&"shield_glyph_heavy")==2,"Inventory captures RT+B without consuming a gameplay glyph")
	session.ui.close_menu()
	trigger(.9)
	button(JOY_BUTTON_A)
	check(controls.jump_requested and not controls.shield_requested and not controls.special_modified(),"A jumps and an old trigger must return to neutral after a menu")
	controls.consume_jump()
	button(JOY_BUTTON_A,false)
	trigger(0)
	chord()
	await frames()
	check(inventory.count_type(&"shield_glyph_heavy")==1 and actor.weapon_combat.shield_points==1000,"Neutral then a fresh RT+B hold works after closing Inventory")
	check(session.save_checkpoint("user://tests/shield_shortcuts.json",true),"Shortcut consumption saves through the existing checkpoint")
	for item: Resource in inventory.items.values().duplicate():
		if item.item_type_id==&"shield_glyph_heavy": inventory.take_item(item.instance_id,item.quantity)
	check(actions.shield_glyph_count.text=="Shield Glyphs  0","Removing the remaining stack refreshes the shield counter")
	check(session.load_checkpoint("user://tests/shield_shortcuts.json") and actions.shield_glyph_count.text=="Shield Glyphs  1","Save/load restores the exact owned count in the HUD")
	trigger(0)
	trigger(.9)
	button(JOY_BUTTON_B)
	controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not controls.consume_shield() and not controls.consume_jump(),"Focus loss clears a queued shield use")
	button(JOY_BUTTON_B,false)
	trigger(0)
	chord()
	controls._on_joy_connection_changed(0,false)
	check(not controls.consume_shield(),"Controller disconnect clears a queued shield use")
	trigger(0)
	button(JOY_BUTTON_B,false)
	trigger(.9)
	button(JOY_BUTTON_A)
	check(controls.consume_jump() and not controls.consume_shield(),"RT+A always jumps with the old shield chord removed")
	button(JOY_BUTTON_A,false)
	trigger(0)
	check(not controls.consume_interaction(),"RT+A jump cannot also sit down on RT release")
	key(KEY_V)
	key(KEY_SPACE)
	check(controls.consume_jump() and not controls.consume_shield(),"V+Space always jumps")
	key(KEY_SPACE,false)
	key(KEY_V,false)
	# Tap-versus-hold shares B without double spending either consumable.
	for release_rt_first: bool in [false,true]:
		trigger(.9)
		button(JOY_BUTTON_B)
		controls.update_combat_hold(.1)
		check(not controls.heal_requested,"A short RT+B press defers healing until release")
		if release_rt_first: trigger(0)
		button(JOY_BUTTON_B,false)
		if not release_rt_first: trigger(0)
		check(controls.consume_heal() and not controls.consume_shield() and not controls.consume_dodge() and not controls.consume_interaction(),"A short RT+B tap heals once in either release order")
	key(KEY_V)
	key(KEY_H)
	key(KEY_V,false)
	key(KEY_H,false)
	check(controls.consume_heal() and not controls.consume_shield(),"A short V+H tap heals on release")
	key(KEY_H)
	check(controls.consume_heal(),"H without a modifier keeps immediate healing")
	key(KEY_H,false)
	trigger(.9)
	button(JOY_BUTTON_B)
	controls.update_combat_hold(.1)
	controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	controls.update_combat_hold(1)
	button(JOY_BUTTON_B,false)
	trigger(0)
	check(not controls.consume_heal() and not controls.consume_shield(),"Focus loss cancels an unfinished consumable hold without healing on release")
	# Real host-validated loot collection while a drawn Manuscript holds RT.
	var manuscript: Resource=Catalog.create(&"eturnull_manuscript")
	inventory.add_item(manuscript)
	inventory.assign(&"down",manuscript.instance_id)
	actor.combat.selected_slot=&"down"
	actor.combat.sheathed=false
	actor.weapon_combat.sync_rig()
	actor.weapon_combat.clear_stagger()
	var count_before: int=inventory.count_type(&"light_shard")
	var pickup: Node3D=world.loot.spawn_reward(&"light_shard",actor.global_position+Vector3.RIGHT*.7)
	check(pickup!=null,"A real nearby loot drop is available beside the bench")
	trigger(.9)
	await frames(12)
	check(inventory.count_type(&"light_shard")==count_before+1 and controls.special_modified(),"Held RT collects real loot while the Manuscript stays drawn")
	trigger(0)
	await frames()
	check(not actions.attached() and not controls.consume_interaction(),"Collecting while writing never auto-sits at the nearby bench")
	pickup=world.loot.spawn_reward(&"light_shard",actor.global_position+Vector3.RIGHT*.7)
	trigger(.9)
	button(JOY_BUTTON_B)
	await frames(12)
	check(inventory.count_type(&"light_shard")==count_before+1,"A held consumable chord cannot also collect loot")
	controls.reset_combat_input()
	world.loot.host_enabled=false
	trigger(.9)
	await frames(12)
	check(inventory.count_type(&"light_shard")==count_before+1,"Writing-stance pickups preserve host authority")
	world.loot.host_enabled=true
	actor.transition_locked=true
	await frames(12)
	check(inventory.count_type(&"light_shard")==count_before+1,"Writing-stance pickups are blocked during pyramid transitions")
	actor.transition_locked=false
	await frames(12)
	check(inventory.count_type(&"light_shard")==count_before+2,"Held RT can collect again when the transition ends")
	trigger(0)
	if "--capture" in OS.get_cmdline_user_args():
		await frames(3)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/shield_shortcuts.png")
	world.queue_free()
	await process_frame
	print("SHIELD SHORTCUTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
