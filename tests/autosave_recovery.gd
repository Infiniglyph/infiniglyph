extends SceneTree
const Store=preload("res://scripts/inventory_store.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
var world: Node3D
var session: Node
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=1) -> void:
	for i in range(count): await physics_frame; await process_frame
func finish_job() -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while session._encoder.pending() and not session._encoder.ready() and Time.get_ticks_msec()<deadline:
		await frames()
		OS.delay_msec(1)
	check(session._encoder.ready(),"A private checkpoint job completes without blocking scene frames")
	session._poll_autosave()
func run() -> void:
	create_timer(300).timeout.connect(func(): push_error("Autosave recovery watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false; world.world_memory_enabled=false
	world.boss_encounters_enabled=false; world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.civilization.simulation_enabled=false
	world.player.visual.retrieval.enabled=false; world.sparring_partner.visual.retrieval.enabled=false
	for i in range(600):
		await frames()
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	check(world.civic_interactions.initialized,"Complete civic and career authorities initialize")
	world.process_mode=Node.PROCESS_MODE_DISABLED
	session=world.inventory_session
	session.save_path="user://tests/autosave_recovery.json"
	session.persistence_enabled=true
	# Run enough actual society/quest turns to expire contracts and compact the
	# board repeatedly. No rendered NPC needs to receive an individual AI turn.
	for tick in range(240):
		check_tick(world.civilization.advance_real(1))
		world.civic_interactions._process(1)
		world.building_civilization._process(1)
		if tick%60!=59: continue
		var snapshot: Dictionary=session._capture_checkpoint()
		check(session._encoder.start(snapshot)==OK,"A later populated checkpoint starts after contract churn")
		await finish_job()
		check(session.last_autosave_error.is_empty(),"Expired/pruned contracts cannot break linked checkpoint validation")
	check(not Store.load_snapshot(session.save_path).is_empty(),"The populated checkpoint survives a strict disk round trip")
	session.persistence_enabled=true
	session._discard_autosave()
	for i in range(100): session._dirty()
	check(session._save_queued and not session._encoder.pending() and session._autosave_wait==session.AUTOSAVE_DEBOUNCE,"A burst of changes coalesces into one delayed capture")
	session._autosave_wait=0; session._autosave()
	world.player.inventory.add_item(Catalog.create(&"health_glyph",1))
	check(session._save_again,"An inventory change during encoding retains the need for a newer checkpoint")
	await finish_job()
	check(session._save_queued and not session._encoder.pending() and session._autosave_wait==session.AUTOSAVE_INTERVAL,"A follow-up capture observes the minimum interval instead of saving continuously")
	session._autosave_wait=0; session._autosave(); await finish_job()
	var latest:=Store.load_snapshot(session.save_path)
	check(not latest.is_empty() and latest.inventory==world.player.inventory.serialize(),"The next checkpoint includes the newest inventory mutation")
	var blocker:=FileAccess.open("user://tests/autosave-blocked-parent",FileAccess.WRITE)
	blocker.store_string("Intentional fixture file, not a directory."); blocker.close()
	session.save_path="user://tests/autosave-blocked-parent/checkpoint.json"
	session._dirty(); session._autosave_wait=0; session._autosave(); await finish_job()
	check(session._autosave_failures==1 and session._save_queued and session._autosave_wait==15 and session.last_autosave_error.begins_with("disk commit"),"An actual disk error preserves dirty state and applies a 15 second retry delay")
	for i in range(100): session._dirty(); session._autosave()
	check(not session._encoder.pending() and session._autosave_wait==15,"Repeated changes cannot bypass failed-save backoff or start a hot retry loop")
	world.player.inventory.add_item(Catalog.create(&"health_glyph",1))
	session.save_path="user://tests/autosave_recovered.json"
	session._autosave_wait=0; session._autosave(); await finish_job()
	latest=Store.load_snapshot(session.save_path)
	check(session.last_autosave_error.is_empty() and session._autosave_failures==0 and not latest.is_empty() and latest.inventory==world.player.inventory.serialize(),"Retry recovers to disk with all live changes and clears the failure state")
	session.persistence_enabled=false; session._discard_autosave()
	world.queue_free(); await frames(3)
	print("Autosave recovery: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
func check_tick(ok: bool) -> void:
	if not ok: check(false,"Society clock advances under contract churn")
