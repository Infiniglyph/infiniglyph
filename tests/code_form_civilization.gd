extends SceneTree
## Whole-world civilian integration, ownership, time, replacement and checkpoints.
const Store = preload("res://scripts/inventory_store.gd")
const Registry = preload("res://scripts/code_form_registry.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var society: Node
var economy: Node
var checks := 0
var failures := 0
var save_path := "user://tests/code_form_society.json"

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

func circulating() -> int:
	var total:=0
	for coins: int in economy.balances.values(): total+=coins
	return total

func stable(snapshot: Dictionary) -> Dictionary:
	var copy:=snapshot.duplicate(true)
	copy.erase("saved_unix")
	return copy

func equivalent(a: Variant,b: Variant) -> bool:
	# Godot's decimal JSON parser may discard the last binary float digit.
	# Integral progression/currency remain exact; time/hunger allow roundoff.
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a)-float(b))<=maxf(1e-9,maxf(absf(float(a)),absf(float(b)))*1e-12)
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in range(a.size()):
			if not equivalent(a[i],b[i]): return false
		return true
	return a==b

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Civilization integration watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	world.dungeon_enemies_enabled=false
	world.death_drop_probability=0
	root.add_child(world)
	society=world.civilization
	economy=world.civilian_services.economy
	society.simulation_enabled=false
	var intent:=Intent.new()
	root.add_child(intent)
	world.player.controls=intent
	world.camera_rig.controls=intent
	world.inventory_session.controls=intent
	world.player.visual.retrieval.enabled=false
	for i in range(240):
		await frames(1)
		if society.ready_for_simulation: break
	check(society.ready_for_simulation,"The real world bootstraps civilian identities after its physical census is ready")
	if not society.ready_for_simulation: quit(1); return
	world.population.set_physics_process(false)
	world.district_life.set_physics_process(false)
	var count: int=world.population.residents.size()+world.district_life.resident_records.size()+world.district_life.vehicle_records.size()+4
	check(society.registry.active_ids().size()==count and count>1000,"City, regional pedestrians, drivers and service staff each have a unique persistent identity")
	check(economy.active_ids==society.registry.active_ids(),"The entire active civilian census matches the ledger's blessing eligibility")
	check(circulating()+economy.destroyed_total==economy.issued_total and economy.issued_total==count*100,"Opening migration admits new civilians once without duplicating old residents' blessings")
	check(economy.balance(economy.player_account)==0 and not society.registry.records.has("player"),"The visiting player receives no civilian wallet blessing or progression record")
	for excluded: String in ["player","kyren","ahkmet","lorai","monster","enemy"]:
		check(not society.record_event({"event_type":"combat","actor_id":excluded,"target_id":"world","rarity":"unique","significance":1,"event_id":"excluded/"+excluded}).get("accepted",false),"Non-civilian event is rejected: "+excluded)
	var resident: CharacterBody3D=world.population.residents[0]
	var id: String=society.id_for_source(resident)
	var person: Dictionary=society.registry.records[id]
	check(not id.is_empty() and person.level==1 and person.experience==0,"Visible civilian bodies resolve their explicit Level 1 identity")
	var year: float=society.registry.config.day_seconds*society.registry.config.days_per_year
	var initial_life: float=society.registry.remaining_lifetime(id)
	check(is_equal_approx(initial_life,100*year),"Every initial civilian has exactly 100 game years of granted lifetime")
	var state: Dictionary=society.autonomy._state(id)
	state.next_action=1e12; state.next_decision=1e12
	check(society.advance_real(3600) and is_equal_approx(society.world_seconds,86400),"One real hour advances the single authoritative clock by one game day")
	check(is_equal_approx(society.registry.remaining_lifetime(id),initial_life-86400),"The same clock reduces remaining lifetime without a per-body timer")
	var event: Dictionary={"event_type":"discovery","actor_id":id,"target_id":"new/vault","rarity":"rare","significance":1,"event_id":"discovery/vault"}
	check(society.record_event(event).xp==80 and not society.record_event(event).accepted,"A structured meaningful event grants rarity XP once")
	society.record_event({"event_type":"guild","actor_id":id,"target_id":"test/contract","rarity":"uncommon","significance":1,"event_id":"contract/first"})
	check(person.level==2 and is_equal_approx(society.registry.remaining_lifetime(id),initial_life-86400+100*year),"Leveling adds 100 years to the remaining lifetime rather than resetting its clock")
	society.record_interaction(id,"conversation","player")
	var trust: float=person.relationships.player
	var xp: int=person.experience
	for i in range(20): society.record_interaction(id,"conversation","player")
	check(is_equal_approx(trust,.03) and person.relationships.player==trust and person.experience==xp,"Repeated conversation input cannot farm friendship or XP")
	society.autonomy.on_combat(resident,"defeated")
	check(person.relationships.player<-.2 and "remember" in society.autonomy.dialogue_line(resident),"A remembered defeat changes subsequent civilian dialogue")
	var record_before: Dictionary=person.duplicate(true)
	check(not society.registry.combat_respawn(id).is_empty() and person==record_before,"Combat respawn preserves identity, XP, level and lifetime")
	var receipt_xp: int=person.experience
	var keeper_xp: int=society.registry.records.tavern_bartender.experience
	check(economy.npc_buy_food(id,&"electron_meal"),"Civilian commerce transfers actual coins and delivers an actual meal")
	check(person.experience>receipt_xp and society.registry.records.tavern_bartender.experience>keeper_xp,"Both civilian participants receive XP only after successful meaningful commerce")
	var transfer_xp: int=person.experience
	check(economy.transfer("resident:"+id,economy.tavern_account,1,"Ordinary transfer") and person.experience==transfer_xp,"Generic transfers do not generate circulation XP")
	var issued: int=economy.issued_total
	var wonder_buyer: Dictionary={}
	for candidate: String in society.registry.active_ids():
		if world.glyphic_wonders._npc_ready(candidate,false) and economy.balance("resident:"+candidate)>=20:
			wonder_buyer=society.registry.records[candidate]
			break
	var wonder_inventory: Node=economy.npc_store(String(wonder_buyer.id)) if not wonder_buyer.is_empty() else null
	var wonder_counts: Dictionary={}
	if wonder_inventory!=null:
		for item: Resource in wonder_inventory.items.values(): wonder_counts[item.item_type_id]=wonder_inventory.count_type(item.item_type_id)
	var destroyed_before: int=economy.destroyed_total
	var wonder_bought: bool=not wonder_buyer.is_empty() and world.glyphic_wonders.npc_shop(wonder_buyer,false)
	var delivered:=0
	var actual_price:=0
	if wonder_inventory!=null:
		for item: Resource in wonder_inventory.items.values():
			var difference: int=wonder_inventory.count_type(item.item_type_id)-int(wonder_counts.get(item.item_type_id,0))
			if difference>0:
				delivered+=difference
				actual_price=int(world.glyphic_wonders.stock.offer(item.item_type_id).price)
	check(wonder_bought and delivered==1 and actual_price>0 and economy.destroyed_total-destroyed_before==actual_price and economy.issued_total==issued and not economy.purchase_wonder(String(wonder_buyer.get("id",""))),"An offered Glyphic Wonders purchase delivers one real item and destroys its actual retail price while closing the old cheap bypass")
	check(circulating()+economy.destroyed_total==issued,"Ordinary exchanges and destruction remain auditable against total issuance")
	var start: float=society.world_seconds
	check(society.advance_real(1e9,true) and is_equal_approx(society.world_seconds-start,6*86400),"Offline catch-up is capped at six real hours, corresponding to six game days")
	var to_bless: float=(30*86400-society.world_seconds)/24.0
	issued=economy.issued_total
	check(society.advance_real(to_bless) and economy.last_cycle==1 and economy.issued_total-issued==count*100,"A 30-day boundary issues exactly 100 coins to every active civilian")
	issued=economy.issued_total
	check(society.advance_real(0) and economy.issued_total==issued,"Reprocessing an already settled boundary cannot duplicate a blessing")
	var background_id: String=society.registry.slots["driver/0"]
	var background: Dictionary=society.registry.records[background_id]
	background.current_goal="guild"
	var background_state: Dictionary=society.autonomy._state(background_id)
	check(society.autonomy.perform_action(background,background_state,false) and background.guild=="adventurers_guild" and background.experience>0,"A civilian with no loaded pedestrian body can accomplish a meaningful guild action")
	check(society.autonomy.states.size()<=count,"Logical schedules remain bounded by the active population")
	check(world.inventory_session.save_checkpoint(save_path,true),"A real checkpoint commits society, clock, wallets, goods, player items and world drops together")
	var saved: Dictionary=Store.load_snapshot(save_path)
	check(not saved.is_empty() and saved.has("civilization_state"),"The society survives the actual full-precision JSON file round trip")
	var saved_society: Dictionary=stable(society.serialize())
	var saved_economy: String=JSON.stringify(economy.serialize(),"",true,true)
	society.advance_real(10)
	var loaded: bool=world.inventory_session.load_checkpoint(save_path)
	check(loaded and equivalent(stable(society.serialize()),saved_society) and JSON.stringify(economy.serialize(),"",true,true)==saved_economy,"Manual load restores the exact society and economy without repeating offline rewards")
	var invalid: Dictionary=saved.duplicate(true)
	invalid.civilian_state.active_ids.pop_back()
	check(Store.decode(invalid).is_empty(),"Checkpoint validation rejects a society and ledger with different active identities")
	invalid=saved.duplicate(true)
	invalid.civilization_state.registry.config.blessing_days=31
	check(Store.decode(invalid).is_empty(),"A clock and paid blessing cycle mismatch is rejected before mutating the world")
	var travel: Node=world.dungeon_travel
	check(travel.restore_location(travel.pyramid_id),"The existing dungeon instance accepts the same player while the civilian world stays outside")
	var in_dungeon_time: float=society.world_seconds
	society.simulation_enabled=true
	await frames(75)
	society.simulation_enabled=false
	check(society.world_seconds>in_dungeon_time and travel.outside_root.process_mode==Node.PROCESS_MODE_DISABLED,"The real civilian clock continues while the outdoor 3D world is disabled inside a dungeon")
	check(travel.restore_location(travel.OUTSIDE),"The player can return from the instance without changing civilian identities")
	var session: Node=world.inventory_session
	session.save_path="user://tests/code_form_autosave.json"
	session.persistence_enabled=true
	var prepare_start:=Time.get_ticks_usec()
	session._dirty()
	await frames(1)
	print("Civilian autosave capture/dispatch wall ms: ",float(Time.get_ticks_usec()-prepare_start)/1000.0)
	check(session._encoder.pending(),"Large civilian autosaves dispatch immutable validation and encoding to a private worker")
	society.registry.remember(id,"discovery","async/latest","A discovery made while the previous save was encoding.",.7)
	session._dirty()
	var frames_during_save:=0
	for i in range(600):
		if not session._save_queued: break
		await frames(1)
		frames_during_save+=1
	check(not session._save_queued and frames_during_save>0,"The scene continues processing frames while the autosave worker finishes")
	var asynchronous: Dictionary=Store.load_snapshot(session.save_path)
	var latest_saved:=false
	if not asynchronous.is_empty():
		for memory: Dictionary in asynchronous.civilization_state.registry.records[id].memories:
			if memory.target=="async/latest": latest_saved=true
	check(latest_saved,"A change during encoding queues a fresh checkpoint after the earlier snapshot commits")
	session._dirty()
	await frames(1)
	check(not session.load_checkpoint("user://tests/missing_code_form_checkpoint.json") and session._encoder.pending(),"A failed load leaves an already captured autosave queued for the unchanged live world")
	check(session.load_checkpoint(save_path) and not session._encoder.pending(),"Manual checkpoint load joins and discards an older autosave before replacing live state")
	session.persistence_enabled=false
	var snapshot: Dictionary=society.serialize()
	var issued_before: int=economy.issued_total
	# Compress the configured calendar consistently to exercise real retirement
	# without simulating centuries or bypassing lifetime validation.
	var reg: Dictionary=snapshot.registry
	reg.config.day_seconds=1.0; reg.config.days_per_year=1
	reg.config.real_seconds_per_day=1.0; reg.config.blessing_days=100000
	reg.world_seconds=100000.0
	for row: Dictionary in reg.records.values():
		row.born_at=100000.0
		row.expires_at=100000.0+100.0*row.level
		for memory: Dictionary in row.memories: memory.timestamp=100000.0
	snapshot.autonomy={"version":1,"cursor":0,"states":{}}
	check(society.restore(snapshot),"Calendar configuration and lifetime metadata restore as one validated society")
	var old: String=society.registry.slots["region/0"]
	var old_coins: int=economy.balance("resident:"+old)
	var active_count: int=society.registry.slots.size()
	check(society.advance_real(100),"A full civilian generation can expire in one bounded population transaction")
	var replacement: String=society.registry.slots["region/0"]
	check(replacement!=old and not society.registry.records[old].active and society.registry.active_ids().size()==active_count,"Each expired identity produces exactly one distinct active replacement")
	var fresh: Dictionary=society.registry.records[replacement]
	check(fresh.level==1 and fresh.experience<80 and fresh.personality!=society.registry.records[old].personality and fresh.generation==1,"Replacements start with fresh progression and their own personality")
	check(economy.balance("resident:"+old)==old_coins and economy.balance("resident:"+replacement)==0 and economy.issued_total==issued_before,"Retirement preserves old economic history and creates an empty replacement wallet")
	check(economy.active_ids==society.registry.active_ids() and world.district_life.resident_records[0].code_form_id==replacement,"The active financial census and regional body binding follow the replacement")
	check(not Store.encode(world.player.inventory,world.loot.serialize_world(),[],world.loot.session_id,"overworld",{},economy.serialize(),society.serialize()).is_empty(),"The replaced population can still be encoded and validated as a coherent checkpoint")
	check(world.civilian_services.reset_state() and society.registry.replacement_serial==0 and society.world_seconds==0 and economy.active_ids==society.registry.active_ids(),"The existing civilian reset hook restores the complete coherent initial society rather than only 104 wallets")
	print("Code Form civilization checks: %d; failures: %d; civilians: %d" % [checks,failures,count])
	root.remove_child(world)
	world.free()
	intent.free()
	quit(0 if failures==0 else 1)
