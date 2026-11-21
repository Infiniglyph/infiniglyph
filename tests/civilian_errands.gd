extends SceneTree
const Needs=preload("res://scripts/code_form_needs.gd")
var world: Node3D
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run():
	create_timer(180).timeout.connect(func(): push_error("Errand watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false; world.world_memory_enabled=false; world.boss_encounters_enabled=false; world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.civilization.simulation_enabled=false
	for i in range(600):
		await physics_frame; await process_frame
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var autonomy=world.civilization.autonomy
	var economy=world.civilian_services.economy
	world.civilization.ensure_starter_capital()
	var selected:=""
	var nearest: Array=world.district_life.resident_records.duplicate()
	var door: Vector3=world.civilian_services.establishments.tavern_entry.global_position
	nearest.sort_custom(func(a: Dictionary,b: Dictionary): return a.point.distance_squared_to(door)<b.point.distance_squared_to(door))
	var probes:=0
	for record: Dictionary in nearest:
		var id:=String(record.get("code_form_id",""))
		if record.point.distance_to(door)>96 or probes>=30: break
		probes+=1
		var state: Dictionary=autonomy._state(id); state.hunger=.7; state.thirst=.75
		economy.transfer("resident:"+id,"business:tavern",economy.balance("resident:"+id),"Fixture starts penniless")
		if world.civilian_errands.consider(id): selected=id; break
	check(not selected.is_empty(),"A real local resident finds a collision-validated tavern trip from an existing street route")
	if selected.is_empty(): print("PROBES ",probes); world.queue_free(); await process_frame; quit(1); return
	var visit: Dictionary=world.civilian_errands.active[selected]
	var record: Dictionary=visit.record
	var original: PackedVector3Array=visit.base_route.duplicate()
	var store: Node=economy.npc_store(selected)
	var worked:=false; var bought:=false; var ate:=false
	for i in range(3000):
		world.district_life.advance_journey(record,.25)
		world.civilian_errands._process(.25)
		if world.civilian_errands.active.has(selected):
			var phase: String=world.civilian_errands.active[selected].phase
			worked=worked or phase=="shift"
			bought=bought or store.count_type(&"electron_meal")>0 and store.count_type(&"electron_draught")>0
			ate=ate or phase=="eat"
		if not world.civilian_errands.active.has(selected): break
		if i%20==0: await process_frame
	check(worked,"A penniless resident completes a timed funded tavern shift before ordering")
	check(bought,"The purchase delivers a real meal and drink into the resident's owned inventory")
	check(ate and autonomy._state(selected).hunger<.05 and autonomy._state(selected).thirst<.05,"Consumption happens at the reserved seat and restores both civilian needs")
	check(store.count_type(&"electron_meal")==0 and store.count_type(&"electron_draught")==0,"Eating and drinking consume the actual purchased items")
	check(not world.civilian_errands.active.has(selected) and record.route==original,"The resident walks out and returns to the original safe route")
	check(economy.service_tokens.has(selected+"|tavern_work"),"The wage has a saved anti-replay proof")
	check(not economy.npc_service_wage(selected,"tavern_work",floori(world.civilization.world_seconds/(autonomy._day()*.5)),20),"The same completed shift cannot pay twice")
	var appointed:=false
	var visitor:=""
	for a: Dictionary in nearest.slice(0,12):
		if appointed: break
		var left:=String(a.get("code_form_id",""))
		for b: Dictionary in nearest.slice(0,12):
			var right:=String(b.get("code_form_id",""))
			if left==right or a.point.distance_to(b.point)>64: continue
			autonomy._state(left).hunger=.1; autonomy._state(left).thirst=.1
			autonomy._state(right).hunger=.1; autonomy._state(right).thirst=.1
			world.civilization.registry.relate(left,right,.6); world.civilization.registry.relate(right,left,.6)
			world.civilization.registry.set_goal(left,"socialize",right)
			if world.civilian_errands.meetings.consider(left): appointed=true; visitor=left; break
	check(appointed,"Two existing friends can arrange a reachable local appointment")
	var talked:=false
	if appointed:
		var plan: Dictionary=world.civilian_errands.meetings.plans[visitor]
		for i in range(2000):
			world.district_life.advance_journey(plan.record,.25)
			var body: Node=autonomy._source(visitor)
			if is_instance_valid(body): body.global_position=plan.record.point
			world.civilian_errands._process(.25)
			talked=talked or plan.phase=="talking"
			if not world.civilian_errands.meetings.plans.has(visitor): break
			if i%20==0: await process_frame
	check(talked and world.civilian_errands.meetings.plans.is_empty(),"The appointment becomes an in-person conversation and releases both friends afterward")
	# Repeat with the actual CharacterBody3D active, not the distant route model.
	world.civilian_errands.set_process(false)
	world.district_life.simulation_lod_enabled=false
	world.player.global_position=record.point+Vector3(5,.2,0)
	world.process_mode=Node.PROCESS_MODE_INHERIT
	for i in range(60): await physics_frame; await process_frame
	var physical: Node=autonomy._source(selected)
	var loaded:=is_instance_valid(physical) and physical is CharacterBody3D
	check(loaded,"The same resident reconstructs as a real nearby physics body")
	var visible_ate:=false
	var finished:=false
	if loaded:
		physical.set_physics_process(false); physical.set_virtualized(false)
		physical.wait=0; record.wait=0
		var state: Dictionary=autonomy._state(selected); state.hunger=.7; state.thirst=.75
		economy.transfer("business:tavern","resident:"+selected,20,"Fixture customer budget")
		world.civilian_errands._retry.erase(selected)
		var began: bool=world.civilian_errands.consider(selected)
		check(began,"The visible resident accepts a real counter and chair route")
		Engine.time_scale=4
		for i in range(1800 if began else 0):
			await physics_frame
			physical._physics_process(1.0/15.0)
			world.civilian_errands._process(1.0/15.0)
			visible_ate=visible_ate or physical.visual.sitting
			await process_frame
			if began and not world.civilian_errands.active.has(selected): finished=true; break
		Engine.time_scale=1
	check(visible_ate,"The actual moving physics body reaches its chair and uses the seated meal pose")
	check(finished and autonomy._state(selected).hunger<.05 and autonomy._state(selected).thirst<.05,"The visible loop consumes the purchased goods and walks back outside")
	print("MEASURE local_errand ",JSON.stringify({"id":selected,"probes":probes,"worked":worked,"bought":bought,"ate":ate,"remaining":world.civilian_errands.active.size()}))
	world.queue_free(); await process_frame
	print("CIVILIAN ERRANDS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
