extends SceneTree
const Store=preload("res://scripts/inventory_store.gd")
var world: Node3D
var checks:=0
var failures:=0
var reentry_checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func send(intent: String,parameters: Dictionary={}) -> Dictionary:
	return world.communication.send("player",world.civic_interactions._speaker,intent,parameters,{},false,world.communication.conversation_id)
func place(point: Dictionary) -> void:
	world.communication.close_conversation("fixture")
	world.civilian_services.menu.close_menu()
	world.player.global_position=point.anchor.global_position+Vector3(0,.3,1.4)
	world.player.velocity=Vector3.ZERO
	world.player.fall_damage.reset()
	world.player.visual.rebase_after_phase()
	world.controls.set_gameplay_enabled(true)
	await frames(5)
func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	world.neon_glow_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	world.civilization.simulation_enabled=false
	for i in range(300):
		await frames(1)
		if world.civic_interactions.initialized: break
	var civic: Node=world.civic_interactions
	var society: Node=world.civilization
	var quests: Node=world.quest_system
	var economy: Node=world.civilian_services.economy
	check(civic.initialized,"Real world attaches and initializes shared civic authorities")
	if not civic.initialized: world.queue_free(); await frames(); quit(1); return
	world.population.set_physics_process(false)
	for resident: Node in world.population.residents: resident.deactivate()
	var security_capital: int=economy.balance("faction:security")
	for guild: Dictionary in quests.organizations.guilds_for_faction("security"):
		security_capital+=economy.balance(String(guild.treasury))
		for obligation: Dictionary in economy.contracts.values():
			if obligation.source==guild.treasury and obligation.status=="reserved": security_capital+=int(obligation.amount)
	check(economy.factions.size()==4 and economy.guilds.size()==12 and security_capital>0,"Finite founding capital remains in affiliated guild treasuries and funded obligations")
	var before: Dictionary=economy.serialize()
	civic.bootstrap()
	check(economy.sequence==before.sequence,"Repeated bootstrap does not duplicate capital or contract funding")
	check(quests.available("player","underworld").is_empty() and not quests.join("player","underworld"),"Underworld contracts and membership remain private before introduction")
	var point: Dictionary={}
	for entry: Dictionary in world.civilian_services.establishments.points:
		if entry.get("id")=="board_security": point=entry; break
	check(not point.is_empty(),"Security board exists in actual guild geometry")
	await place(point)
	check(civic.begin_service(point,""),"Board uses the six-intent communication channel")
	check(not world.controls.gameplay_enabled and not paused,"Conversation gates gameplay without pausing simulation")
	var public_rows: Array=quests.available("player","security",true)
	check(not public_rows.is_empty() and not quests.accept(public_rows[0].id,"player",civic._now()),"Public can inspect work but cannot accept before membership")
	check(send("accept_guild",{"faction":"security"}).accepted and quests.is_member("player","security"),"Semantic guild acceptance changes the persistent membership authority")
	var patrol: Dictionary=public_rows[0]
	check(send("accept_quest",{"quest_id":patrol.id}).accepted and quests.model.instances[patrol.id].status=="active","Semantic contract acceptance reserves one real participant")
	var money: int=economy.balance(economy.player_account)
	check(quests.consume_event({"event_id":"forged","event_type":"service","actor_id":"player","target_id":patrol.objective.target_id,"service":"patrol","quantity":1,"timestamp":civic._now()}).is_empty(),"Unverified dialogue/world claims cannot complete paid work")
	world.communication.close_conversation("fixture")
	world.player.global_position=civic.destination(patrol.objective.target_id)+Vector3.UP*.3
	world.player.velocity=Vector3.ZERO
	civic.arrived("player",patrol.objective.target_id)
	quests.advance_to(civic._now())
	check(quests.model.instances[patrol.id].status=="completed" and economy.balance(economy.player_account)==money+patrol.reward,"Verified physical patrol arrival pays exactly the finite escrow reward")
	civic.arrived("player",patrol.objective.target_id)
	check(economy.balance(economy.player_account)==money+patrol.reward,"Repeated arrival cannot duplicate quest payment")
	var contact:=String(civic._contact())
	var contact_point: Dictionary={}
	for entry: Dictionary in world.civilian_services._points():
		if entry.get("id")=="tavern_adventurer": contact_point=entry; break
	check(not contact_point.is_empty(),"Private contact is an actual tavern resident")
	await place(contact_point)
	check(civic.begin_service(contact_point,contact),"Tavern contact shares normal conversation controls")
	check(send("request_help",{"topic":"introduction"}).reply.intent=="refuse","Stranger cannot obtain the private introduction by merely asking")
	var favor:=String(civic.request_favor(contact,"player"))
	if favor.is_empty():
		for row: Dictionary in quests.available("player"):
			if row.issuer==contact and row.faction.is_empty(): favor=row.id; break
	check(not favor.is_empty() and quests.accept(favor,"player",civic._now()),"A resident can fund a personal need through the same quest engine")
	# Use a real paid purchase, not a reward-spawned item.
	var bartender: Dictionary={}
	for entry: Dictionary in world.civilian_services._points():
		if entry.kind=="bartender": bartender=entry; break
	await place(bartender)
	world.civilian_services.current=bartender
	world.civilian_services._home()
	check(economy.buy_food(&"electron_meal",world.player.inventory),"Player purchases the requested delivery from the real finite economy")
	world.civilian_services.menu.close_menu()
	await place(contact_point)
	civic.begin_service(contact_point,contact)
	check(civic.complete_delivery(quests.model.instances[favor],"player"),"Delivery transfers an actual owned item to the named resident")
	quests.advance_to(civic._now())
	check(quests.model.instances[favor].status=="completed" and civic._friend(contact,"player")>=.1,"Completed favor earns trust and the funded reward")
	check(send("request_help",{"topic":"introduction"}).reply.intent=="agree" and quests.model.introductions.has("player"),"Friendly tavern contact grants a private introduction")
	check(send("accept_guild",{"faction":"underworld"}).accepted and quests.is_member("player","underworld"),"Private affiliation becomes available after the earned introduction")
	check(economy.transfer("resident:"+contact,economy.player_account,8,"Fixture trade funded from existing contact coins"),"Dialogue trade uses accounted existing purchasing funds")
	var contact_stock: Node=economy.npc_store(contact)
	var meal_id:=""
	for item: Resource in contact_stock.items.values():
		if item.item_type_id==&"electron_meal": meal_id=String(item.instance_id); break
	var quote: Dictionary=send("ask_price",{"instance_id":meal_id,"quantity":1,"seller_id":contact,"buyer_id":"player"})
	check(quote.get("accepted",false) and quote.get("reply",{}).get("parameters",{}).has("quote_token"),"Actual-world semantic trade issues a bound stock and price offer")
	if quote.get("reply",{}).get("parameters",{}).has("quote_token"):
		var trade_before: int=economy.balance(economy.player_account)
		var bought: Dictionary=send("accept_trade",quote.reply.parameters)
		check(bought.get("accepted",false) and economy.balance(economy.player_account)==trade_before-int(quote.reply.parameters.price) and contact_stock.count_type(&"electron_meal")==0,"UIC acceptance passes the protected Services adapter and atomically transfers coins and goods")
		var owned_meal:=""
		for item: Resource in world.player.inventory.items.values():
			if item.item_type_id==&"electron_meal": owned_meal=String(item.instance_id); break
		var sale: Dictionary=send("offer_item",{"instance_id":owned_meal,"quantity":1})
		check(sale.get("accepted",false) and send("accept_trade",sale.reply.parameters).get("accepted",false) and contact_stock.count_type(&"electron_meal")==1,"The same semantic exchange lets a player offer owned goods to a real NPC buyer")
	var witness:=contact
	world.law.changed.connect(func():
		if not world.law.get("_busy"): return
		reentry_checks+=1
		check(world.inventory_session._capture_checkpoint().is_empty() and not world.inventory_session.load_checkpoint("user://tests/absent.json"),"Law mutation blocks checkpoint capture/load before touching another authority")
	)
	var case: Dictionary=world.law.record_crime({"event_id":"fixture/assault","kind":"assault","offender":"player","victim":contact,"witnesses":[witness]})
	check(not case.is_empty() and world.law.wanted_level("player")==1,"Actual witnessed crime creates a separate evidence and wanted record")
	check(reentry_checks>0,"The real legal callback exercised checkpoint reentry protection")
	check(world.law.record_crime({"event_id":"fixture/assault","kind":"assault","offender":"player","victim":contact,"witnesses":[witness]}).is_empty(),"Legal event dedup prevents repeated punishment")
	world.communication.close_conversation("fixture")
	var snapshot: Dictionary=world.inventory_session._capture_checkpoint()
	check(snapshot.has("quest_state") and not Store.decode(snapshot).is_empty(),"Whole checkpoint validates linked quests, escrow, communication, law and XP provenance")
	var checkpoint:="user://tests/civic_integration.json"
	check(world.inventory_session.save_checkpoint(checkpoint,true),"Integrated civic state saves atomically")
	check(world.inventory_session.load_checkpoint(checkpoint),"Integrated civic state restores atomically")
	check(quests.is_member("player","underworld") and world.law.wanted_level("player")==1 and economy.balance(economy.player_account)>0,"Membership, evidence, completed rewards and coins survive cold-style restore")
	var pedestrian: CharacterBody3D=world.population.residents[0]
	pedestrian.active=true
	pedestrian.show()
	pedestrian.global_position=world.player.global_position+Vector3(0,0,2)
	pedestrian.wait=0
	check(civic.begin_for_source(pedestrian),"Moving resident opens the shared conversation")
	await frames(8)
	check(world.communication.is_open and pedestrian.wait>0 and pedestrian.state=="talking","Conversation keeps its real speaker nearby while the world stays live")
	world.communication.close_conversation("fixture")
	check(pedestrian.state!="talking" and pedestrian.wait<=.5,"Closing conversation releases the resident's normal behavior")
	print("CIVIC INTEGRATION: ",checks," checks, ",failures," failures")
	world.queue_free(); await frames(3)
	quit(1 if failures else 0)
