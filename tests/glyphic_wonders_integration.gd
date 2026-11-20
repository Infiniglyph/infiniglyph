extends SceneTree
## Actual hall controller, native menus, ownership, clocks and rollback.
const Catalog=preload("res://scripts/item_catalog.gd")
const Store=preload("res://scripts/inventory_store.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var shop: Node
var economy: Node
var society: Node
var travel: Node
var session: Node
var controls: Node
var checks:=0
var failures:=0
var callback_saves:=0
var callback_buys:=0
var nested_loads:=0
var load_purchase_attempts:=0
var load_purchase_accepts:=0
var callback_record: Dictionary={}
var callback_quote: Dictionary={}
var guard_loads:=false
var checkpoint:="user://tests/glyphic_wonders_controller.json"
var rejected_checkpoint:="user://tests/glyphic_wonders_reject.json"
func _initialize() -> void:
	Engine.physics_ticks_per_second=60
	Engine.max_physics_steps_per_frame=1
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	root.push_input(event)
	await frames(2)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)
	await frames(2)
func pad(button: JoyButton) -> void:
	var event:=InputEventJoypadButton.new()
	event.button_index=button
	event.pressed=true
	root.push_input(event)
	await frames(2)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)
	await frames(2)
func place(point: Dictionary) -> void:
	world.communication.close_conversation("fixture reposition")
	shop.menu.close_menu()
	world.start_menu.close_menu()
	if session.ui.is_open: session.ui.close_menu()
	p.weapon_combat.cancel()
	p.combat.reset()
	var at: Vector3=point.anchor.global_position
	p.global_position=Vector3(at.x,.17,at.z)+(Vector3(2.8,0,0) if point.kind=="display" else Vector3(0,0,1.2))
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	p.visual.rebase_after_phase()
	controls.set_gameplay_enabled(true)
	await frames(8)
func point(kind: String) -> Dictionary:
	for entry: Dictionary in shop._points:
		if entry.kind==kind: return entry
	return {}
func last_quote() -> Dictionary:
	if shop._quotes.is_empty(): return {}
	return shop._quotes.values()[-1].quote.duplicate(true)
func inspect_counter() -> Dictionary:
	var counter:=point("counter")
	await place(counter)
	if not shop.interact(): return {}
	world.communication.close_conversation("inspect counter commerce")
	shop._counter()
	await key(KEY_ENTER)
	return last_quote()
func commit_callback(_token: String,_buyer: String) -> void:
	if session.save_checkpoint("user://tests/glyphic_wonders_reentry.json",true): callback_saves+=1
	if economy.buy_wonder(callback_quote,p.inventory): callback_buys+=1
func inventory_callback() -> void:
	if not guard_loads: return
	load_purchase_attempts+=1
	if session.load_checkpoint(checkpoint): nested_loads+=1
	if economy.buy_wonder(callback_quote,p.inventory): load_purchase_accepts+=1
	if shop.npc_shop(callback_record,false): load_purchase_accepts+=1
func counts(inventory: Node) -> Dictionary:
	var result: Dictionary={}
	for item: Resource in inventory.items.values(): result[item.item_type_id]=inventory.count_type(item.item_type_id)
	return result
func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	world.death_drop_probability=0
	world.neon_glow_enabled=false
	root.add_child(world)
	p=world.player
	shop=world.glyphic_wonders
	economy=world.civilian_services.economy
	society=world.civilization
	travel=world.dungeon_travel
	session=world.inventory_session
	society.simulation_enabled=false
	world.controls.set_process_unhandled_input(false)
	controls=Intent.new()
	root.add_child(controls)
	controls.interaction_context=session
	world.controls=controls
	p.controls=controls
	world.camera_rig.controls=controls
	session.controls=controls
	p.visual.retrieval.enabled=false
	for i in range(240):
		await frames(1)
		if society.ready_for_simulation and travel.ready_for_travel: break
	check(society.ready_for_simulation and shop!=null and economy.wonder_shop_attached,"The real world attaches one persistent shop to the authoritative civilian ledger")
	if not society.ready_for_simulation: quit(1); return
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	for id: String in society.registry.active_ids():
		var schedule: Dictionary=society.autonomy._state(id)
		schedule.next_action=1e12
		schedule.next_decision=1e12
	var funded:=0
	for id: String in economy.active_ids:
		if economy.balance("resident:"+id)>=100 and funded<4:
			economy.transfer("resident:"+id,economy.player_account,100,"Controller fixture uses existing issued coins")
			funded+=1
	check(funded==4 and economy.balance(economy.player_account)==400 and not economy.balances.has("resident:avat_ar"),"Purchasing funds come from real existing wallets without an Avat Ar blessing/account")
	var initial_stock: Dictionary=shop.serialize()
	check(travel.restore_location(travel.wonders_id),"The existing location authority constructs the separate shopping hall")
	await frames(12)
	check(is_instance_valid(shop.hall) and shop.displays.size()==12 and p.get_world_3d()==shop.hall.get_world_3d(),"Twelve real catalog models and the same player occupy the independent hall World3D")
	var display: Dictionary={}
	for candidate: Dictionary in shop._points:
		if candidate.kind=="display" and shop.stock.offer(StringName(candidate.type_id)).price<=300:
			display=candidate
			break
	check(not display.is_empty(),"The current real rotating selection contains an affordable inspectable pedestal")
	await place(display)
	check(shop.interact() and shop.menu.is_open and not controls.gameplay_enabled,"Approaching the actual pedestal opens its focused purchase confirmation and captures local controls")
	callback_quote=last_quote()
	var offer: Dictionary=shop.stock.offer(StringName(display.type_id))
	var balance_before: int=economy.balance(economy.player_account)
	var destroyed_before: int=economy.destroyed_total
	var owned_before: int=p.inventory.count_type(StringName(display.type_id))
	economy.wonder_purchase_committed.connect(commit_callback)
	await key(KEY_ENTER)
	check(economy.balance(economy.player_account)==balance_before-int(offer.price) and economy.destroyed_total==destroyed_before+int(offer.price) and p.inventory.count_type(StringName(display.type_id))==owned_before+1,"Native Enter confirmation delivers the displayed item once and destroys its exact current retail price")
	check(callback_saves==0 and callback_buys==0 and p.weapon_combat.active_move.is_empty(),"Purchase callbacks cannot save or reenter settlement and confirmation never starts a combat move")
	var ledger: Dictionary=economy.serialize()
	check(not economy.buy_wonder(callback_quote,p.inventory) and economy.serialize()==ledger,"The actual controller and economy reject replay of the committed quote")
	shop.menu.close_menu()
	var fake_anchor:=Marker3D.new()
	shop.hall.add_child(fake_anchor)
	fake_anchor.global_position=display.anchor.global_position
	var fake: Dictionary={"kind":"display","type_id":display.type_id,"anchor":fake_anchor,"label":"Invented point"}
	check(shop._quote(p.inventory.owner_id,offer,fake).is_empty(),"An arbitrary nearby marker cannot impersonate a canonical selling pedestal")
	check(shop._quote(p.inventory.owner_id,shop.stock.offer(&"health_glyph"),display).is_empty(),"Permanent glyphs cannot be quoted from rotating pedestals")
	fake_anchor.queue_free()
	var counter: Dictionary=point("counter")
	await place(counter)
	check(shop._quote(p.inventory.owner_id,offer,counter).is_empty(),"A genuine counter cannot sell rotating showcase merchandise")
	var counter_opened: bool=shop.interact()
	world.communication.close_conversation("inspect counter commerce")
	shop._counter()
	check(counter_opened and shop.menu._choices.size()==7,"Avat Ar's physical counter provides four permanent glyph offers and bounded dialogue choices")
	await key(KEY_ENTER)
	var permanent_quote:=last_quote()
	check(not permanent_quote.is_empty() and permanent_quote.type_id=="health_glyph", "The counter's first native selection inspects the shared Health Glyph")
	world.start_menu.open_menu()
	check(world.start_menu.is_open and not shop.menu.is_open and not economy.buy_wonder(permanent_quote,p.inventory),"Opening Start closes the shop and invalidates confirmation authority while retaining live world time")
	shop._inspect(counter,"health_glyph")
	check(not shop.menu.is_open,"A stale inspection callback cannot reopen shopping underneath Start")
	world.start_menu.close_menu()
	permanent_quote=await inspect_counter()
	await pad(JOY_BUTTON_BACK)
	check(session.ui.is_open and not shop.menu.is_open and not economy.buy_wonder(permanent_quote,p.inventory),"Select/View transfers focus to inventory and blocks an old shop confirmation")
	session.ui.close_menu()
	permanent_quote=await inspect_counter()
	var clock_before: float=society.world_seconds
	check(society.advance_real(301),"The shared authoritative clock advances while a confirmation is outstanding")
	ledger=economy.serialize()
	check(not economy.buy_wonder(permanent_quote,p.inventory) and economy.serialize()==ledger and society.world_seconds>clock_before,"Expired quote timing rejects a purchase without deducting coins")
	permanent_quote=await inspect_counter()
	var seconds_to_rotation: float=(shop.stock.next_rotation-society.world_seconds)/24.0
	check(society.advance_real(seconds_to_rotation) and shop.refresh_stock(),"A seven-day clock boundary refreshes the real loaded showcase")
	ledger=economy.serialize()
	check(not economy.buy_wonder(permanent_quote,p.inventory) and economy.serialize()==ledger,"A rotation during confirmation gracefully rejects the replaced offer")
	await frames(4)
	check(shop.displays.size()==12 and shop.stock.cycle==1 and shop._quotes.is_empty(),"The hall replaces its models once and clears outstanding quote authority")
	permanent_quote=await inspect_counter()
	var copied_stock: Dictionary=shop.serialize()
	check(travel.restore_location(travel.OUTSIDE),"Exiting the hall restores the city context")
	await frames(4)
	check(not is_instance_valid(shop.hall) and not economy.buy_wonder(permanent_quote,p.inventory) and shop.serialize()==copied_stock,"Unloading the hall removes interaction authority without rerolling stock")
	var shopper: Dictionary={}
	for id: String in society.registry.active_ids():
		if shop._npc_ready(id,false) and economy.balance("resident:"+id)>=20:
			shopper=society.registry.records[id]
			break
	check(not shopper.is_empty(),"A real distant natural civilian is eligible for coarse offscreen shopping")
	var buyer_store: Node=economy.npc_store(String(shopper.id))
	var buyer_before:=counts(buyer_store)
	var coins_before: int=economy.balance("resident:"+String(shopper.id))
	destroyed_before=economy.destroyed_total
	var xp_before: int=shopper.experience
	check(shop.npc_shop(shopper,false),"A coarse distant shopper uses real current offers and its own inventory")
	var delivered:=0
	var paid:=0
	for item: Resource in buyer_store.items.values():
		var delta: int=buyer_store.count_type(item.item_type_id)-int(buyer_before.get(item.item_type_id,0))
		if delta>0: delivered+=delta; paid=int(shop.stock.offer(item.item_type_id).price)
	check(delivered==1 and paid>0 and economy.balance("resident:"+String(shopper.id))==coins_before-paid and economy.destroyed_total==destroyed_before+paid and shopper.experience>xp_before,"The offscreen purchase has one actual item, conserved destruction and natural-buyer commerce XP")
	check(not economy.purchase_wonder(String(shopper.id)),"Autonomous shoppers cannot bypass current stock using the legacy cheap pattern")
	check(travel.restore_location(travel.wonders_id),"Reentry reconstructs displays from persistent current stock")
	await frames(12)
	check(shop.serialize()==copied_stock,"Exiting and reentering cannot reroll the saved selection")
	check(session.save_checkpoint(checkpoint,true),"An actual whole-world checkpoint stores current rotation with society and real purchases")
	var saved:=Store.load_snapshot(checkpoint)
	check(not saved.is_empty() and saved.glyphic_wonders_state==shop.serialize(),"The actual disk snapshot includes coherent catalog-validated shop state")
	society.advance_real(7*3600)
	shop.refresh_stock()
	await frames(4)
	callback_quote=await inspect_counter()
	for id: String in society.registry.active_ids():
		if economy.balance("resident:"+id)>=100 and shop._npc_ready(id,false):
			callback_record=society.registry.records[id]
			break
	check(not shop._authorize(p.inventory.owner_id,callback_quote).is_empty() and not callback_record.is_empty(),"A valid open-menu player quote and funded coarse NPC exist immediately before load callbacks")
	p.inventory.changed.connect(inventory_callback)
	guard_loads=true
	check(session.load_checkpoint(checkpoint) and nested_loads==0,"Checkpoint restoration rejects reentry from inventory callbacks")
	guard_loads=false
	check(load_purchase_attempts>0 and load_purchase_accepts==0,"Inventory restoration callbacks cannot execute player or natural-civilian retail purchases while models are incomplete")
	await frames(8)
	check(shop.stock.serialize()==saved.glyphic_wonders_state and society.world_seconds==saved.civilization_state.registry.world_seconds,"Manual loading restores the saved stock and exact matching world clock")
	var failed:=saved.duplicate(true)
	var unsupported: Resource=Catalog.create(&"light_shard")
	failed.world_drops.append({"pickup_id":"unsupported_wonders_drop","item":unsupported.to_dict(),"position":[0.0,1000.0,0.0],"death_owner_id":"","location_id":String(travel.wonders_id)})
	check(Store.store(rejected_checkpoint,failed)==OK,"A spatially unsupported drop can exercise post-model restore failure rather than syntax rejection")
	var live_stock: Dictionary=shop.serialize()
	ledger=economy.serialize()
	var live_items: Dictionary=p.inventory.serialize()
	check(not session.load_checkpoint(rejected_checkpoint) and shop.serialize()==live_stock and economy.serialize()==ledger and p.inventory.serialize()==live_items,"A later ownership/spatial restore failure rolls shop, money and player goods back together")
	check(not session._restoring_checkpoint and not economy.transaction_active(),"Successful and failed restore paths release their transaction guards")
	print("Glyphic Wonders controller integration: ",checks," checks, ",failures," failures")
	root.remove_child(world)
	world.free()
	controls.free()
	quit(1 if failures else 0)
