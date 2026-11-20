extends RefCounted
## Invoked by the real patrol fixture while borrowed officer stores are live.
## It observes teardown at the exact store-free boundary, not after a frame
## happened to delete the bodies and hide an unsafe ordering.
const Store=preload("res://scripts/inventory_store.gd")

func _frames(count: int=2) -> void:
	var tree: SceneTree=Engine.get_main_loop()
	for i in range(count):
		await tree.physics_frame
		await tree.process_frame

func _observe_borrowers(patrols: Node3D) -> Dictionary:
	var result:={"count":0,"safe":true,"actors":[],"stores":{}}
	for id: String in patrols.fighters:
		var actor: CharacterBody3D=patrols.fighters[id]
		var inventory: Node=actor.inventory
		result.actors.append(actor)
		result.stores[id]=inventory.get_instance_id()
		var actor_ref: WeakRef=weakref(actor)
		var inventory_ref: WeakRef=weakref(inventory)
		inventory.tree_exiting.connect(func():
			var body: CharacterBody3D=actor_ref.get_ref()
			var store: Node=inventory_ref.get_ref()
			result.count=int(result.count)+1
			result.safe=bool(result.safe) and is_instance_valid(body) and is_instance_valid(store) and body.is_queued_for_deletion() and body.process_mode==Node.PROCESS_MODE_DISABLED and not store.equipment_changed.is_connected(body.combat.refresh_equipment) and not store.equipment_changed.is_connected(body._clothing_changed) and store.actor!=body,
			CONNECT_ONE_SHOT)
	return result

func _one_copy_per_issue(world: Node3D,patrols: Node3D) -> bool:
	var seen: Dictionary={}
	for inventory: Node in world.civilian_services.economy.npc_stores.values():
		for item: Resource in inventory.items.values(): seen[item.instance_id]=int(seen.get(item.instance_id,0))+1
	for item: Resource in world.player.inventory.items.values(): seen[item.instance_id]=int(seen.get(item.instance_id,0))+1
	for id: String in patrols.issued:
		if int(seen.get(patrols.issued[id],0))!=1: return false
	return true

func _redeploy(world: Node3D,patrols: Node3D,vehicle: CharacterBody3D) -> bool:
	if not patrols.bootstrap() or not patrols.units.has(int(vehicle.record.id)): return false
	vehicle.has_driver=true
	vehicle.signed_speed=0
	vehicle.global_position=vehicle.record.point
	world.player.global_position=vehicle.global_position+Vector3(7,0,10)
	world.player.velocity=Vector3.ZERO
	return patrols.deploy(vehicle)

func run(world: Node3D,patrols: Node3D,vehicle: CharacterBody3D,check: Callable) -> void:
	var session: Node=world.inventory_session
	var expected: Dictionary=patrols.serialize()
	var observed:=_observe_borrowers(patrols)
	var good_path:="user://dark_box_deployed_checkpoint.json"
	var saved: bool=session.save_checkpoint(good_path,true)
	check.call(not observed.actors.is_empty() and saved,"A full checkpoint captures deployed officers and their actual borrowed NPC stores")
	if not saved:
		_diagnose(session._capture_checkpoint(),world)
		return
	var loaded: bool=session.load_checkpoint(good_path)
	check.call(loaded and observed.count==observed.actors.size() and observed.safe,"Checkpoint load detaches and disables every deployed body before freeing its borrowed store")
	check.call(patrols.fighters.is_empty() and patrols.units.is_empty() and not patrols.ready_for_patrols and patrols.serialize()==expected,"Loading preserves issue provenance while clearing runtime crew reservations for reconstruction")
	var replaced:=true
	for id: String in observed.stores:
		var inventory: Node=world.civilian_services.economy.npc_store(id)
		if not is_instance_valid(inventory) or inventory.get_instance_id()==int(observed.stores[id]): replaced=false
	check.call(replaced,"Loaded officers receive newly restored authoritative store Nodes rather than stale pointers")
	await _frames()
	check.call(observed.actors.all(func(actor): return not is_instance_valid(actor)),"Deferred officer teardown finishes safely after successful checkpoint loading")
	check.call(_redeploy(world,patrols,vehicle),"Restored patrols rebuild crew reservations and can deploy again from the witnessed wanted state")
	check.call(patrols.serialize()==expected and _one_copy_per_issue(world,patrols),"Reconstructing a loaded patrol does not issue duplicate wand copies")
	# Build an internally valid checkpoint whose shell dimensions disagree
	# with this running world's physical manifest. Store validation succeeds;
	# the later building adapter rejects it after the economy swap, exercising
	# the real rollback path and a second inventory replacement.
	var malformed: Dictionary=session._capture_checkpoint()
	var properties: Dictionary=malformed.get("building_state",{}).get("records",{})
	if properties.is_empty():
		check.call(false,"The full-world fixture exposes an owned shell for a later-adapter rollback test")
		return
	var key: String=properties.keys()[0]
	properties[key].size[0]=float(properties[key].size[0])+.25
	var bad_path:="user://dark_box_late_rejection_checkpoint.json"
	var before_economy: Dictionary=world.civilian_services.economy.serialize()
	var before_buildings: Dictionary=world.building_civilization.serialize()
	observed=_observe_borrowers(patrols)
	check.call(Store.store(bad_path,malformed)==OK,"A changed shell manifest passes value validation before the runtime adapter's stricter check")
	check.call(not session.load_checkpoint(bad_path),"A later building-manifest rejection triggers checkpoint rollback")
	check.call(observed.count==observed.actors.size() and observed.safe and patrols.fighters.is_empty(),"Rollback also frees borrowed stores only after their bodies and signal bindings are detached")
	check.call(patrols.serialize()==expected and world.civilian_services.economy.serialize()==before_economy and world.building_civilization.serialize()==before_buildings,"Rejected loading rolls back exact officer provenance, inventory ownership and building state")
	await _frames()
	check.call(observed.actors.all(func(actor): return not is_instance_valid(actor)) and not session._loading and not session._restoring_checkpoint,"Failed loading leaves neither queued borrowers nor a stuck checkpoint transaction")
	check.call(_redeploy(world,patrols,vehicle) and _one_copy_per_issue(world,patrols),"Patrols rebuild and deploy without duplicate equipment after rollback")

func _diagnose(snapshot: Dictionary,world: Node3D) -> void:
	if snapshot.is_empty():
		print("DARK BOX CHECKPOINT DIAG: ",JSON.stringify({"empty_capture":true,"loading":world.inventory_session._loading,"pending":world.inventory_session._checkpoint_pending,"civic_busy":world.inventory_session._civic_busy(),"building_ready":world.building_civilization.ready_for_use,"civilization_ready":world.civilization.ready_for_simulation,"civilization_busy":world.civilization.transaction_active()}))
		return
	var economy: Script=load("res://scripts/civilian_economy.gd")
	var society: Script=load("res://scripts/code_form_civilization.gd")
	var buildings: Script=load("res://scripts/building_registry.gd")
	var careers: Script=load("res://scripts/career_registry.gd")
	var patrol: Script=load("res://scripts/dark_box_patrols.gd")
	var stock: Script=load("res://scripts/glyphic_wonders_stock.gd")
	var core:=snapshot.duplicate()
	for key: String in ["civilian_state","civilization_state","glyphic_wonders_state","building_state","career_state","dark_box_state"]+Store.CIVIC_FIELDS: core.erase(key)
	print("DARK BOX CHECKPOINT DIAG: ",JSON.stringify({"core":not Store.decode(core).is_empty(),"economy":not economy.validate(snapshot.civilian_state,snapshot.inventory,snapshot.world_drops).is_empty(),"society":not society.validate(snapshot.civilization_state).is_empty(),"civic_model":not Store.canonical_civic_state(snapshot).is_empty(),"civic_links":Store.civic_links_match(snapshot),"stock":not stock.validate(snapshot.glyphic_wonders_state).is_empty(),"building_model":not buildings.validate(snapshot.building_state).is_empty(),"building_links":Store.building_links_match(snapshot),"career_model":not careers.validate(snapshot.career_state).is_empty(),"career_links":Store.career_links_match(snapshot),"patrol_model":not patrol.validate(snapshot.dark_box_state).is_empty(),"patrol_links":Store.dark_box_links_match(snapshot)}))
