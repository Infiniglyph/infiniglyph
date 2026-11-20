extends SceneTree
## CPU timings for the real logical society, civic services and building loop.
## Deliberately frozen bodies isolate simulation cost; these are not FPS results.
var world: Node3D
var label := "baseline"
var samples := 256
var timings: Dictionary = {}
var failures := 0
var diagnostic := false
var recording := false
var callbacks: Dictionary = {}
class TimedAutonomy:
	extends "res://scripts/code_form_autonomy.gd"
	var report: Callable
	func choose_goal(record: Dictionary,state: Dictionary) -> String:
		var start:=Time.get_ticks_usec()
		var result:=super.choose_goal(record,state)
		report.call("autonomy/choose_goal",Time.get_ticks_usec()-start)
		return result
	func _shopping_interest(record: Dictionary,coins: int) -> float:
		var start:=Time.get_ticks_usec()
		var result:=super._shopping_interest(record,coins)
		report.call("autonomy/shopping_interest",Time.get_ticks_usec()-start)
		return result
	func perform_action(record: Dictionary,state: Dictionary,physical: bool) -> bool:
		var start:=Time.get_ticks_usec()
		var result:=super.perform_action(record,state,physical)
		report.call("autonomy/perform_action",Time.get_ticks_usec()-start)
		return result

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label=argument.trim_prefix("--label=").validate_filename()
		if argument.begins_with("--samples="): samples=clampi(int(argument.trim_prefix("--samples=")),16,1024)
		if argument=="--diagnostic": diagnostic=true
	call_deferred("run")

func frames(count: int=1) -> void:
	for i in range(count): await physics_frame; await process_frame

func measure(component: String,operation: Callable,record: bool) -> void:
	var start:=Time.get_ticks_usec()
	operation.call()
	if record:
		if not timings.has(component): timings[component]=[]
		timings[component].append(Time.get_ticks_usec()-start)

func tick(record: bool) -> void:
	recording=record
	measure("clock_and_autonomy",func():
		if not world.civilization.advance_real(1.0): failures+=1,record)
	measure("economic_review",func(): world.civilization.review_economics(),record)
	measure("civic_services",func(): world.civic_interactions._process(1.0),record)
	measure("building_services",func(): world.building_civilization._process(.5),record)

func timed_callback(original: Callable,key: String,arguments: Array) -> Variant:
	var start:=Time.get_ticks_usec()
	var result: Variant=original.callv(arguments)
	report_callback(key,Time.get_ticks_usec()-start)
	return result

func report_callback(key: String,usec: int) -> void:
	if recording:
		if not callbacks.has(key): callbacks[key]={"calls":0,"usec":0}
		callbacks[key].calls+=1; callbacks[key].usec+=usec

func wrap_callbacks(model: RefCounted,prefix: String) -> void:
	for key: String in model._callbacks.keys():
		var original: Callable=model._callbacks[key]
		# These adapters use at most three positional arguments.
		var count:=original.get_argument_count()
		if count==0: model._callbacks[key]=func(): return timed_callback(original,prefix+key,[])
		elif count==1: model._callbacks[key]=func(a): return timed_callback(original,prefix+key,[a])
		elif count==2: model._callbacks[key]=func(a,b): return timed_callback(original,prefix+key,[a,b])
		elif count==3: model._callbacks[key]=func(a,b,c): return timed_callback(original,prefix+key,[a,b,c])

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Code Form profile watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.civilization.simulation_enabled=false
	world.player.visual.retrieval.enabled=false
	world.sparring_partner.visual.retrieval.enabled=false
	for i in range(600):
		await frames()
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	if not world.civic_interactions.initialized or not world.building_civilization._guild_premises_ready:
		push_error("Production society did not initialize"); quit(1); return
	# Only this diagnostic stops scheduled body updates. Methods below exercise
	# production authority synchronously, without touching the user's checkpoint.
	world.process_mode=Node.PROCESS_MODE_DISABLED
	if diagnostic:
		var previous: RefCounted=world.civilization.autonomy
		var profiled:=TimedAutonomy.new()
		profiled.civilization=world.civilization; profiled.report=report_callback
		profiled.states=previous.states; profiled.cursor=previous.cursor
		profiled._sources=previous._sources; profiled._regional_records=previous._regional_records
		world.civilization.autonomy=profiled
		wrap_callbacks(world.careers.model,"career/")
		wrap_callbacks(world.quest_system.model,"quest/")
	for i in range(96): tick(false)
	for i in range(samples): tick(true)
	var summary: Dictionary={}
	for component: String in timings:
		var values: Array=timings[component]
		values.sort()
		var total:=0.0
		for value: int in values: total+=value
		summary[component]={"mean_ms":total/values.size()/1000.0,"median_ms":float(values[values.size()/2])/1000.0,"p95_ms":float(values[ceili(values.size()*.95)-1])/1000.0,"max_ms":float(values.back())/1000.0}
	var economy: Node=world.civilian_services.economy
	var total_coins:=0
	for amount: int in economy.balances.values(): total_coins+=amount
	var result:={"label":label,"samples":samples,"cpu":OS.get_processor_name(),"engine":Engine.get_version_info().string,"components":summary,"active_citizens":world.civilization.registry.slots.size(),"autonomy_states":world.civilization.autonomy.states.size(),"decisions":world.civilization.autonomy.decisions,"completed_actions":world.civilization.autonomy.completed_actions,"world_seconds":world.civilization.world_seconds,"workers":world.careers.model.workers.size(),"employments":world.careers.model.employments.size(),"contracts":world.quest_system.model.instances.size(),"coin_supply_valid":total_coins+economy.destroyed_total==economy.issued_total,"notes":"Frozen production bodies; direct real simulation/service calls. Not an FPS benchmark; other desktop processes remain running."}
	print("CODE FORM PROFILE ",JSON.stringify(result))
	if diagnostic: print("NESTED CALLBACK PROFILE ",JSON.stringify(callbacks))
	var file:=FileAccess.open("res://.godot/code-form-profile-"+label+".json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"\t")); file.close()
	if not result.coin_supply_valid or result.active_citizens!=result.autonomy_states: failures+=1
	world.queue_free()
	await frames(3)
	quit(1 if failures else 0)
