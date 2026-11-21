extends SceneTree
const Economy=preload("res://scripts/civilian_economy.gd")
const Policy=preload("res://scripts/code_form_starter_capital.gd")
const Store=preload("res://scripts/inventory_store.gd")
var world: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=1) -> void:
	for i in range(count): await physics_frame; await process_frame
func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Starter capital integration watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false; world.world_memory_enabled=false
	world.boss_encounters_enabled=false; world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.civilization.simulation_enabled=false
	world.civic_interactions.set_process(false)
	world.player.visual.retrieval.enabled=false; world.sparring_partner.visual.retrieval.enabled=false
	for i in range(600):
		await frames()
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	check(world.civic_interactions.initialized,"Real census and founding governance initialize before grants")
	if not world.civic_interactions.initialized: quit(1); return
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var society: Node=world.civilization
	var economy: Node=world.civilian_services.economy
	var ids: Array=society.registry.active_ids()
	var legacy: Dictionary=economy.serialize()
	legacy.version=4; legacy.audit_base.erase("starter_influx"); legacy.audit_base.erase("institution_influx")
	check(economy.restore(legacy) and not economy.starter_influx_applied,"An existing world with its actual v4 wallets remains eligible")
	var before: Dictionary=economy.balances.duplicate()
	var issued_before: int=economy.issued_total
	var xp_before: Dictionary={}
	for id: String in ids: xp_before[id]=society.registry.records[id].experience
	var expected:=Policy.payouts(society.registry.records,ids,world.quest_system.organizations,world.careers.model)
	world.civic_interactions._process(1)
	check(economy.starter_influx_applied and ids.size()==1122,"The normal civic loop issues capital to all 1,122 current citizens")
	var sum:=0; var complete:=true; var same_xp:=true
	for id: String in ids:
		sum+=int(expected[id])
		complete=complete and economy.balance("resident:"+id)==int(before["resident:"+id])+int(expected[id])
		same_xp=same_xp and society.registry.records[id].experience==xp_before[id]
	check(complete and economy.issued_total>issued_before+sum and economy.institution_influx_applied,"Every real wallet receives exactly its current role/standing grant")
	check(same_xp and economy.balance(economy.player_account)==before[economy.player_account],"Issuance leaves civilian XP and the visiting player's wallet unchanged")
	var leaders_correct:=true
	for faction: Dictionary in world.quest_system.organizations.factions.values(): leaders_correct=leaders_correct and int(expected[faction.leader])>=Policy.FACTION_LEADER
	for guild: Dictionary in world.quest_system.organizations.guilds.values(): leaders_correct=leaders_correct and int(expected[guild.leader])>=Policy.GUILD_LEADER
	check(leaders_correct,"Founding guild and faction leaders receive their actual office tier")
	var paid: Dictionary=economy.serialize()
	check(not Economy.validate(paid).is_empty(),"A full post-influx economy still passes strict replay validation")
	check(world.inventory_session.save_checkpoint("user://tests/starter_capital.json",true),"The real checkpoint encoder saves the grant with civic state")
	check(not Store.load_snapshot("user://tests/starter_capital.json").is_empty(),"The complete checkpoint decodes after a disk round trip")
	check(world.inventory_session.load_checkpoint("user://tests/starter_capital.json"),"The real checkpoint loader restores the paid society")
	var after_load: int=economy.issued_total
	for i in range(5): world.civic_interactions._process(1)
	check(economy.starter_influx_applied and economy.issued_total==after_load and society.ensure_starter_capital(),"Reloading and repeated civic ticks never mint the grant again")
	print("STARTER CAPITAL WORLD: ",JSON.stringify({"citizens":ids.size(),"influx":sum,"issued_before":issued_before,"issued_after":after_load}))
	world.queue_free(); await frames(3)
	print("Starter capital integration: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
