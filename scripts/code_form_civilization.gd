extends Node
## One civilian-only clock and logical society, independent of loaded worlds.
const Registry = preload("res://scripts/code_form_registry.gd")
const Autonomy = preload("res://scripts/code_form_autonomy.gd")
const EconomicAudit = preload("res://scripts/economic_xp_audit.gd")
const StarterCapital = preload("res://scripts/code_form_starter_capital.gd")
signal identities_replaced(changes: Array)
var world: Node3D
var registry := Registry.new()
var autonomy := Autonomy.new()
var economic_audit := EconomicAudit.new()
var last_economic_review: Dictionary = {}
var economy: Node
var ready_for_simulation := false
@export var simulation_enabled := true
var world_seconds: float:
	get: return registry.world_seconds
var _clock := 0.0
var _dirty_clock := 0.0
var _busy := false
var _saved_unix := 0.0
var _bindings: Array[Dictionary] = []
var _initial_registry: Dictionary = {}
var _ledger_ready := false
var _pending_replacements: Array = []
var last_error := ""

func _ready() -> void:
	name="CodeFormCivilization"
	economy=world.civilian_services.economy
	autonomy.civilization=self
	world.population.civilization=self
	if is_instance_valid(world.district_life): world.district_life.civilization=self
	economy.commerce_committed.connect(_commerce)
	economy.world_clock=func(): return world_seconds
	# A clock batch must not be saved halfway between a retirement and admission.
	world.loot.external_transaction_guard=func(): return economy.transaction_active() or _busy
	call_deferred("_bootstrap")

func transaction_active() -> bool: return _busy

func _descriptor(at: Vector3) -> Dictionary:
	return {"location":"overworld","position":[at.x,at.y,at.z],"yaw":0.0}

func _driver_home(at: Vector3) -> Vector3:
	# Drivers return beside the road, outside the car/wreck's collision volume.
	var best:=at+Vector3(7,0,0)
	var distance:=INF
	for record: Dictionary in world.district_life.resident_records:
		var candidate: Vector3=record.route[0]
		var d:=at.distance_squared_to(candidate)
		if d<distance and world.district_life.pedestrian_clear(candidate):
			best=candidate; distance=d
	return best

func _row(slot: String, id: String, profile: Dictionary, at: Vector3) -> Dictionary:
	var occupation:=String(profile.get("role","resident"))
	return {"slot":slot,"id":id,"name":String(profile.get("name",id)),"occupation":occupation if not occupation.is_empty() else "adventurer","personality":String(profile.get("attitude","curious")),"respawn":_descriptor(at)}

func _bootstrap() -> void:
	while is_inside_tree() and (not world.population.ready_for_visitors or (is_instance_valid(world.district_life) and not world.district_life._built)):
		await get_tree().physics_frame
	if not is_inside_tree(): return
	var rows: Array[Dictionary]=[]
	for person: Node3D in world.population.residents:
		var legacy:=String(person.profile.id)
		var slot:="hub/"+legacy
		rows.append(_row(slot,legacy,person.profile,world.population.points.get(person.profile.home,person.global_position)))
		_bindings.append({"slot":slot,"source":person})
	if is_instance_valid(world.district_life):
		for record: Dictionary in world.district_life.resident_records:
			var slot:=String(record.get("code_form_slot","region/"+str(record.id)))
			# An ejected driver is the same civilian, with a pedestrian body.
			if not slot.begins_with("driver/"): rows.append(_row(slot,slot,record.profile,record.route[0]))
			_bindings.append({"slot":slot,"record":record})
		for vehicle: Dictionary in world.district_life.vehicle_records:
			var slot:="driver/"+str(vehicle.id)
			rows.append(_row(slot,slot,vehicle.driver,_driver_home(vehicle.point)))
			_bindings.append({"slot":slot,"driver":vehicle.driver})
	for person: Node3D in world.civilian_services._people:
		var id:=String(person.get_meta("natural_resident_id"))
		var at:=person.global_position
		at.y=maxf(.15,at.y)
		rows.append(_row("service/"+id,id,{"name":person.get_child(1).text.get_slice("\n",0),"role":person.get_meta("role","adventurer"),"attitude":"pragmatic" if "keeper" in id or "receptionist" in id else "curious"},at))
		_bindings.append({"slot":"service/"+id,"source":person})
	if not registry.bootstrap(rows):
		last_error="Civilian identity bootstrap failed."
		push_error(last_error)
		return
	_initial_registry=registry.serialize()
	_saved_unix=Time.get_unix_time_from_system()
	ready_for_simulation=true
	economic_audit.configure(String(economy.owner_id),int(economy.sequence))
	bind_sources()
	if not world.inventory_session._checkpoint_pending: reconcile_economy()

func bind_sources() -> void:
	for binding: Dictionary in _bindings:
		var record: Dictionary=registry.for_slot(binding.slot)
		if record.is_empty(): continue
		var id:=String(record.id)
		if binding.has("source") and is_instance_valid(binding.source):
			var source: Node=binding.source
			source.set_meta("code_form_id",id)
			source.set_meta("code_form_slot",binding.slot)
			if "code_form_id" in source: source.set("code_form_id",id)
			if binding.slot.begins_with("service/"):
				source.get_child(1).text=String(record.name)+"\n"+String(source.get_meta("role",""))
		if binding.has("record"):
			binding.record.code_form_id=id
			binding.record.code_form_slot=binding.slot
		if binding.has("driver"):
			binding.driver.code_form_id=id
			binding.driver.code_form_slot=binding.slot
	if is_instance_valid(world.district_life):
		for source: Node in world.district_life.people.values():
			if source.record.has("code_form_id"):
				source.set_meta("code_form_id",source.record.code_form_id)
				source.set_meta("code_form_slot",source.record.code_form_slot)
				if "code_form_id" in source: source.set("code_form_id",source.record.code_form_id)
	var reception: Dictionary=registry.for_slot("service/guild_receptionist")
	var bar: Dictionary=registry.for_slot("service/tavern_bartender")
	economy.merchant_ids={"guild":reception.get("id",""),"tavern":bar.get("id","")}
	autonomy.bind_sources()

func reconcile_economy() -> bool:
	# Older checkpoints have only the original 104 wallets. Admit the rest once;
	# later replacement accounts start empty rather than inheriting old wealth.
	for id: String in registry.active_ids():
		if id not in economy.natural_ids:
			if not economy.enroll_code_form(id,int(registry.config.blessing_amount) if int(registry.records[id].get("generation",0))==0 else 0): return false
	bind_sources()
	_ledger_ready=true
	return true

func id_for_source(source: Node) -> String:
	if not is_instance_valid(source): return ""
	var id:=String(source.get_meta("code_form_id",""))
	if id.is_empty() and "code_form_id" in source: id=String(source.get("code_form_id"))
	if id.is_empty() and source.get("record") is Dictionary: id=String(source.record.get("code_form_id",""))
	return id if registry.records.get(id,{}).get("active",false) else ""

func ensure_starter_capital() -> bool:
	if economy.starter_influx_applied: return true
	# Wait until checkpoint, census, governance and careers are authoritative.
	# No per-body calls and no scans at all after this single ledger event.
	if _busy or not ready_for_simulation or not _ledger_ready or world.inventory_session._checkpoint_pending or world.inventory_session._loading or not world.civic_interactions.initialized: return false
	var amounts:=StarterCapital.payouts(registry.records,registry.active_ids(),world.quest_system.organizations,world.careers.model)
	return economy.issue_starter_influx(amounts)

func record_event(event: Dictionary) -> Dictionary:
	if not ready_for_simulation or event.get("event_type")=="economic" or event.get("type")=="economic": return {}
	return registry.record_event(event)

func record_interaction(id: String, kind: String, target: String, positive: bool = true) -> void:
	if not registry.records.get(id,{}).get("active",false): return
	var day:=int(world_seconds/float(registry.config.day_seconds))
	# A conversation matters once per day; repeated input cannot wash away
	# an assault or farm friendship. This cooldown survives save/load.
	for memory: Dictionary in registry.records[id].memories:
		if memory.type==kind and memory.target==target and int(float(memory.timestamp)/float(registry.config.day_seconds))==day: return
	registry.remember(id,kind,target,("A welcome encounter with " if positive else "An unwelcome encounter with ")+target,.6)
	registry.relate(id,target,.03 if positive else -.08)
	record_event({"event_type":"social","actor_id":id,"target_id":target,"rarity":"common","significance":.5,"event_id":"social/"+id+"/"+target+"/"+str(day)})

func _commerce(receipt: Dictionary) -> void:
	if not ready_for_simulation or economy==null or not economy.transaction_active() or int(receipt.get("sequence",-1))!=int(economy.sequence) or economy.journal.is_empty(): return
	var event: Dictionary=economy.journal.back()
	if event.kind not in ["transfer","destroy"] or int(event.amount)!=int(receipt.get("amount",0)) or event.get("from")!=receipt.get("sender_account") or String(event.get("to","sink:glyphic_wonders"))!=receipt.get("receiver_account"): return
	if economic_audit.owner_id.is_empty(): economic_audit.configure(String(economy.owner_id),0)
	economic_audit.record_transaction(receipt,registry)

func review_economics(budget: int = EconomicAudit.REVIEW_BATCH) -> Dictionary:
	if _busy or not ready_for_simulation or economy==null or not economy.host_enabled or economy.transaction_active() or economy._externally_busy(): return {}
	var ids: Array[String]=economic_audit.find_reversals(world_seconds,float(registry.config.day_seconds),budget)
	if ids.is_empty():
		last_economic_review={"transactions":[],"corrections":{},"removed_xp":{}}
		return last_economic_review.duplicate(true)
	var before_registry:=registry.serialize()
	var before_economy: Dictionary=economy.serialize()
	var before_audit:=economic_audit.serialize()
	_busy=true
	_pending_replacements.clear()
	var result:=economic_audit.apply_reversals(ids,registry)
	var accepted:=not result.is_empty() and _advance_to(world_seconds)
	if not accepted:
		registry.restore(before_registry)
		economy.restore(before_economy)
		economic_audit.restore(before_audit,before_registry)
		last_error="Economic XP correction could not commit its lifetime/ledger reconciliation."
		result={}
	else:
		for change: Dictionary in _pending_replacements: autonomy.replace_source(change.slot,change.old_id,change.new_id)
		if not _pending_replacements.is_empty():
			bind_sources()
			identities_replaced.emit(_pending_replacements.duplicate(true))
		last_economic_review=result.duplicate(true)
		if is_instance_valid(world) and is_instance_valid(world.inventory_session): world.inventory_session._dirty()
	_pending_replacements.clear()
	_busy=false
	return result

func on_replacements(replacements: Array) -> bool:
	for change: Dictionary in replacements:
		if not economy.retire_code_form(String(change.old_id)) or not economy.enroll_code_form(String(change.new_id),0):
			last_error="The ledger rejected a civilian replacement."
			return false
	_pending_replacements.append_array(replacements)
	return true

func _advance_to(target: float) -> bool:
	var replacements: Array=registry.advance_to(target)
	if registry.world_seconds<target-.00001 or not registry.last_error.is_empty():
		last_error=String(registry.get("last_error"))
		return false
	return on_replacements(replacements)

func advance_real(seconds: float, offline: bool = false) -> bool:
	if _busy or not ready_for_simulation or economy.transaction_active() or world.loot.get("_busy")==true: return false
	if not is_finite(seconds) or seconds<0: return false
	last_error=""
	var real_seconds:=minf(seconds,float(registry.config.offline_cap_seconds)) if offline else seconds
	var target:=world_seconds+real_seconds*float(registry.config.day_seconds)/float(registry.config.real_seconds_per_day)
	var interval:=float(registry.config.blessing_days)*float(registry.config.day_seconds)
	var cycles:=floori(target/interval)-floori(world_seconds/interval)
	if cycles>64: last_error="Clock advance exceeds the bounded blessing batch."; return false
	var replacement_due:=false
	for id: String in registry.slots.values():
		if registry.records[id].expires_at<=target: replacement_due=true; break
	# Rare population/blessing transactions get an atomic rollback snapshot.
	# Ordinary one-second ticks allocate no full society or ledger copy.
	var registry_before: Dictionary=registry.serialize() if replacement_due or cycles>0 else {}
	var economy_before: Dictionary=economy.serialize() if replacement_due or cycles>0 else {}
	_busy=true
	_pending_replacements.clear()
	economy.blessing_amount=int(registry.config.blessing_amount)
	var ok:=true
	while floori(world_seconds/interval)<floori(target/interval):
		var cycle:=floori(world_seconds/interval)+1
		if not _advance_to(cycle*interval): ok=false; break
		if cycle>economy.last_cycle and not economy.bless_cycle(cycle,registry.active_ids()):
			last_error="The ledger rejected blessing cycle "+str(cycle)+"."
			ok=false
			break
	if ok: ok=_advance_to(target)
	if not ok and not registry_before.is_empty():
		registry.restore(registry_before)
		economy.restore(economy_before)
	if ok:
		for change: Dictionary in _pending_replacements:
			autonomy.replace_source(change.slot,change.old_id,change.new_id)
		if not _pending_replacements.is_empty():
			bind_sources()
			identities_replaced.emit(_pending_replacements.duplicate(true))
		# At most one coarse pass over every civilian during catch-up, never a
		# replay of hours of individual pathfinding or combat frames.
		var batches:=maxi(1,ceili(float(registry.slots.size())/float(Autonomy.BATCH_SIZE))) if offline and real_seconds>0 else 1
		for i in range(batches): autonomy.process_batch(real_seconds/float(batches),offline)
	_pending_replacements.clear()
	if ok: _saved_unix=Time.get_unix_time_from_system()
	_busy=false
	return ok

func _process(delta: float) -> void:
	if not ready_for_simulation or not simulation_enabled or world.inventory_session._checkpoint_pending or world.inventory_session._loading: return
	if not _ledger_ready:
		if reconcile_economy(): world.inventory_session._dirty()
		else: return
	_clock+=delta
	if _clock<1: return
	var elapsed:=_clock
	_clock=0
	if not advance_real(elapsed): return
	review_economics()
	_dirty_clock+=elapsed
	if _dirty_clock>=15:
		_dirty_clock=0
		world.inventory_session._dirty()

func describe(id: String) -> String:
	var record: Dictionary=registry.records.get(id,{})
	if record.is_empty(): return ""
	var years:=registry.remaining_lifetime(id)/(float(registry.config.day_seconds)*float(registry.config.days_per_year))
	var text:="%s  /  Level %d\nOccupation: %s. Current intention: %s.\nRemaining lifetime: %.1f years." % [record.name,record.level,record.occupation,String(record.current_goal).replace("_"," "),years]
	if not record.memories.is_empty(): text+="\n"+String(record.memories[-1].get("summary",""))
	return text

func serialize() -> Dictionary:
	if not ready_for_simulation: return {}
	if economic_audit.owner_id.is_empty(): economic_audit.configure(String(economy.owner_id),int(economy.sequence))
	return {"version":2,"registry":registry.serialize(),"saved_unix":Time.get_unix_time_from_system(),"autonomy":autonomy.serialize(),"economic_audit":economic_audit.serialize()}

static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary or not Registry._integer(data.get("version"),1,2) or data.size()!=(4 if data.version==1 else 5): return {}
	if not (data.get("saved_unix") is float or data.get("saved_unix") is int) or not is_finite(float(data.saved_unix)) or data.saved_unix<=0: return {}
	var decoded: Dictionary=Registry.validate(data.get("registry"))
	if decoded.is_empty(): return {}
	var active: Array=decoded.slots.values()
	var decisions: Dictionary=Autonomy.validate(data.get("autonomy"),active)
	if decisions.is_empty(): return {}
	var result:={"version":int(data.version),"registry":decoded,"saved_unix":float(data.saved_unix),"autonomy":decisions}
	if data.version==2:
		var audit:=EconomicAudit.validate(data.get("economic_audit"),decoded)
		if audit.is_empty(): return {}
		result.economic_audit=audit
	return result

static func ledger_matches(society: Dictionary,ledger: Dictionary) -> bool:
	if not society.has("economic_audit"): return true
	var audit: Dictionary=society.economic_audit
	if audit.owner_id!=ledger.get("owner_id") or int(audit.last_sequence)>int(ledger.get("sequence",-1)): return false
	var recent: Dictionary={}
	for event: Dictionary in ledger.get("journal",[]): recent[int(event.sequence)]=event
	var anchor:=int(ledger.get("audit_base",{}).get("sequence",0))
	for row: Dictionary in audit.transactions.values():
		if int(row.sequence)<=anchor: continue
		var event: Dictionary=recent.get(int(row.sequence),{})
		if event.get("kind") not in ["transfer","destroy"] or int(event.get("amount",0))!=int(row.amount) or event.get("from")!=row.sender_account or String(event.get("to","sink:glyphic_wonders"))!=row.receiver_account: return false
	return true

func restore(data: Variant, catch_up: bool = false) -> bool:
	if not ready_for_simulation or _busy: return false
	var previous_slots: Dictionary=registry.slots.duplicate()
	if data==null:
		# Legacy saves have finance but no civilian clock. Start their new
		# lifetimes at the latest already-paid blessing boundary.
		var initial:=_initial_registry.duplicate(true)
		for id: String in economy.natural_ids:
			if not initial.records.has(id): return false
		var origin: float=maxi(0,economy.last_cycle)*float(initial.config.blessing_days)*float(initial.config.day_seconds)
		initial.world_seconds=origin
		for row: Dictionary in initial.records.values(): row.born_at+=origin; row.expires_at+=origin
		var old_registry:=registry.serialize()
		var old_autonomy:=autonomy.serialize()
		var old_economy: Dictionary=economy.serialize()
		if not registry.restore(initial): return false
		autonomy.restore({})
		var admitted:=true
		if economy.last_cycle<0: admitted=economy.bless_cycle(0,economy.active_ids)
		if not admitted or not reconcile_economy():
			registry.restore(old_registry); autonomy.restore(old_autonomy); economy.restore(old_economy)
			return false
		for slot: String in previous_slots:
			if previous_slots[slot]!=registry.slots[slot]: autonomy.replace_source(slot,previous_slots[slot],registry.slots[slot])
		economic_audit.configure(String(economy.owner_id),int(economy.sequence))
		bind_sources()
		return true
	var decoded:=validate(data)
	if decoded.is_empty() or not ledger_matches(decoded,economy.serialize()): return false
	# A structurally valid checkpoint still belongs to this world's census.
	var saved_slots: Array=decoded.registry.slots.keys()
	var initial_slots: Array=_initial_registry.slots.keys()
	saved_slots.sort(); initial_slots.sort()
	if saved_slots!=initial_slots: return false
	var expected: Array=decoded.registry.slots.values()
	var paid: Array=economy.active_ids.duplicate()
	expected.sort(); paid.sort()
	if expected!=paid: return false
	var history: Array=decoded.registry.records.keys()
	var accounts: Array=economy.natural_ids.duplicate()
	history.sort(); accounts.sort()
	if history!=accounts: return false
	var interval: float=float(decoded.registry.config.blessing_days)*float(decoded.registry.config.day_seconds)
	if economy.last_cycle!=floori(float(decoded.registry.world_seconds)/interval): return false
	if not registry.restore(decoded.registry) or not autonomy.restore(decoded.autonomy): return false
	if decoded.has("economic_audit"): economic_audit.restore(decoded.economic_audit,decoded.registry)
	else: economic_audit.configure(String(economy.owner_id),int(economy.sequence))
	_saved_unix=float(decoded.saved_unix)
	for slot: String in previous_slots:
		if previous_slots[slot]!=registry.slots[slot]: autonomy.replace_source(slot,previous_slots[slot],registry.slots[slot])
	bind_sources()
	_ledger_ready=true
	if catch_up:
		var elapsed:=clampf(Time.get_unix_time_from_system()-_saved_unix,0,float(registry.config.offline_cap_seconds))
		if elapsed>0 and not advance_real(elapsed,true): return false
	return true
