extends RefCounted
## Whole single-player checkpoints only. Multiplayer ownership belongs to host.
const Inventory = preload("res://scripts/inventory.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
const Economy = preload("res://scripts/civilian_economy.gd")
const Civilization = preload("res://scripts/code_form_civilization.gd")
const WonderStock = preload("res://scripts/glyphic_wonders_stock.gd")
const Quests = preload("res://scripts/universal_quests.gd")
const Law = preload("res://scripts/civilian_law.gd")
const CIVIC_FIELDS := ["quest_state","communication_state","law_state"]
const VERSION := 1
const POLICY := "singleplayer_checkpoint"
const MAX_WORLD_DROPS := 4096
# The persistent civilian census can legitimately exceed the old item-only
# eight MiB ceiling. Per-record and population bounds still validate contents.
const MAX_SAVE_BYTES := 128*1024*1024

static func encode(inventory: Node, world_drops: Array = [], markers: Array = [], session_id: String = "singleplayer", location: String = "overworld", location_state: Dictionary = {}, civilian_state: Dictionary = {}, civilization_state: Dictionary = {}, stock_state: Dictionary = {}, quest_state: Dictionary = {}, communication_state: Dictionary = {}, law_state: Dictionary = {}) -> Dictionary:
	if inventory == null or not inventory.has_method("serialize"): return {}
	var data: Dictionary={"version":VERSION,"policy":POLICY,"session_id":session_id,"inventory":inventory.serialize(),"world_drops":world_drops,"markers":markers}
	if location!="overworld": data.location_context=location
	if not location_state.is_empty(): data.location_state=location_state
	if not civilian_state.is_empty(): data.civilian_state=civilian_state
	if not civilization_state.is_empty(): data.civilization_state=civilization_state
	if not stock_state.is_empty(): data.glyphic_wonders_state=stock_state
	if not quest_state.is_empty(): data.quest_state=quest_state
	if not communication_state.is_empty(): data.communication_state=communication_state
	if not law_state.is_empty(): data.law_state=law_state
	return decode(data)

static func decode(data: Variant) -> Dictionary:
	return _decode(data,false)

static func _decode(data: Variant,deferred_civic_links: bool) -> Dictionary:
	if not data is Dictionary or not Instance.whole_number(data.get("version"),VERSION,VERSION) or data.get("policy") != POLICY: return {}
	if not Instance.valid_text(data.get("session_id")) or not data.get("world_drops") is Array or data.world_drops.size()>MAX_WORLD_DROPS: return {}
	if data.has("markers") and not data.markers is Array: return {}
	if data.has("location_context") and not Instance.valid_text(data.location_context): return {}
	var state: Dictionary={}
	if data.has("location_state"):
		if not data.location_state is Dictionary: return {}
		var input: Dictionary=data.location_state
		if input.has("ahkmet"):
			var boss: Variant=input.ahkmet
			if not boss is Dictionary or boss.size()!=2 or not Instance.whole_number(boss.get("phase"),1,2): return {}
			if not (boss.get("hp") is float or boss.get("hp") is int) or not is_finite(float(boss.hp)) or float(boss.hp)<=0 or float(boss.hp)>100000: return {}
			state.ahkmet={"phase":int(boss.phase),"hp":float(boss.hp)}
		if input.has("enemy_defeats"):
			if not input.enemy_defeats is Array or input.enemy_defeats.size()>512: return {}
			var unique: Dictionary={}
			for id: Variant in input.enemy_defeats:
				if not Instance.valid_text(id) or unique.has(String(id)): return {}
				unique[String(id)]=true
			state.enemy_defeats=unique.keys()
		if input.has("floor_id") and not Instance.valid_text(input.floor_id): return {}
		if input.has("floor_id"): state.floor_id=String(input.floor_id)
		if input.has("position"):
			if not input.position is Array or input.position.size()!=3: return {}
			for coordinate: Variant in input.position:
				if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate))>1000000: return {}
			state.position=input.position.duplicate()
		if input.has("yaw"):
			if not (input.yaw is float or input.yaw is int) or not is_finite(float(input.yaw)): return {}
			state.yaw=wrapf(float(input.yaw),-PI,PI)
	var inventory := Inventory.new()
	if not inventory.restore(data.get("inventory")):
		inventory.free()
		return {}
	var owned: Dictionary = inventory.serialize()
	var identities: Dictionary = {}
	# Include validated retired identities so migration cannot mask duplicates.
	for entry: Dictionary in data.inventory.items: identities[entry.instance_id] = true
	inventory.free()
	var pickup_ids: Dictionary = {}
	var drops: Array[Dictionary] = []
	var markers: Array[Dictionary] = []
	for entry: Variant in data.world_drops:
		if not entry is Dictionary or not Instance.valid_text(entry.get("pickup_id")) or not entry.get("position") is Array or entry.position.size()!=3: return {}
		if pickup_ids.has(String(entry.pickup_id)): return {}
		var position: Array[float] = []
		for coordinate: Variant in entry.position:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate))>1000000: return {}
			position.append(float(coordinate))
		var item: Resource = Instance.from_dict(entry.get("item"))
		if item == null or not item.owner_id.is_empty() or identities.has(item.instance_id): return {}
		var death_owner: Variant = entry.get("death_owner_id","")
		if not Instance.valid_text(death_owner,true): return {}
		var timer := Pickup.loss_timer_from_row(entry)
		if timer.is_empty(): return {}
		identities[item.instance_id] = true
		pickup_ids[String(entry.pickup_id)] = true
		if Equipment.is_retired(item.item_type_id): continue
		drops.append({"pickup_id":String(entry.pickup_id),"item":item.to_dict(),"position":position,"death_owner_id":String(death_owner)})
		if timer.dismissed:
			drops[-1].loss_dismissed = true
			drops[-1].loss_expires_at = timer.expires_at
		if not String(death_owner).is_empty():
			markers.append({"instance_id":item.instance_id,"owner_id":String(death_owner),"position":position.duplicate()})
			if timer.dismissed:
				markers[-1].dismissed = true
				markers[-1].expires_at = timer.expires_at
		if entry.has("location_id"):
			if not Instance.valid_text(entry.location_id): return {}
			if entry.location_id!="overworld": drops[-1].location_id=String(entry.location_id)
	# Marker ownership/location is reconstructed from unclaimed drops. A stale
	# UI marker never authorizes restoring or tracking an acquired weapon.
	var decoded: Dictionary={"version":VERSION,"policy":POLICY,"session_id":String(data.session_id),"inventory":owned,"world_drops":drops,"markers":markers}
	if data.get("location_context","overworld")!="overworld": decoded.location_context=String(data.location_context)
	if not state.is_empty(): decoded.location_state=state
	if data.has("civilian_state"):
		var civilian:=Economy.validate(data.civilian_state,owned,drops)
		if civilian.is_empty(): return {}
		decoded.civilian_state=civilian
		# A pre-quest save has no escrow history. Removing all civic fields from
		# a newer save must not turn funded work into an orphaned legacy account.
		if not deferred_civic_links and not has_civic_state(data) and not civilian.contracts.is_empty(): return {}
	if data.has("civilization_state"):
		if not decoded.has("civilian_state"): return {}
		var society:=Civilization.validate(data.civilization_state)
		if society.is_empty(): return {}
		# Civilization.validate already canonicalized the complete registry.
		# Rebuilding and validating that model twice more makes large saves stall.
		var model: Dictionary=society.registry
		var active: Array=model.slots.values()
		var paid: Array=decoded.civilian_state.active_ids.duplicate()
		active.sort()
		paid.sort()
		if active!=paid: return {}
		var historical: Array=model.records.keys()
		var accounts: Array=decoded.civilian_state.natural_ids.duplicate()
		historical.sort(); accounts.sort()
		if historical!=accounts: return {}
		var blessing_interval: float=float(model.config.blessing_days)*float(model.config.day_seconds)
		if int(decoded.civilian_state.last_cycle)!=floori(model.world_seconds/blessing_interval): return {}
		if not Civilization.ledger_matches(society,decoded.civilian_state): return {}
		decoded.civilization_state=society
	if data.has("glyphic_wonders_state"):
		if not decoded.has("civilian_state"): return {}
		# Eligibility/price metadata touches the shared catalog. This validation
		# stays on the main thread, including the async encoder's core capture.
		var stock:=WonderStock.validate(data.glyphic_wonders_state)
		if stock.is_empty(): return {}
		if decoded.has("civilization_state") and not wonders_clock_matches(stock,decoded.civilization_state.registry): return {}
		decoded.glyphic_wonders_state=stock
	if has_civic_state(data):
		var civic:=canonical_civic_state(data)
		if civic.is_empty(): return {}
		decoded.merge(civic)
		if not civic_links_match(decoded): return {}
	return decoded

static func has_civic_state(data: Dictionary) -> bool:
	for key: String in CIVIC_FIELDS:
		if data.has(key): return true
	return false

static func canonical_civic_state(data: Dictionary) -> Dictionary:
	# These small value models validate on the main thread in asynchronous saves;
	# the worker receives only their canonical private dictionaries.
	for key: String in CIVIC_FIELDS:
		if not data.has(key): return {}
	var quests:=Quests.validate(data.quest_state)
	var law:=Law.validate(data.law_state)
	var communication_script: Script=load("res://scripts/universal_communication.gd")
	if communication_script==null: return {}
	var communication: Dictionary=communication_script.validate(data.communication_state)
	if quests.is_empty() or law.is_empty() or communication.is_empty(): return {}
	return {"quest_state":quests,"law_state":law,"communication_state":communication}

static func _known_person(id: String,registry: Dictionary) -> bool:
	return id=="player" or registry.records.has(id)

static func _known_speaker(id: String,registry: Dictionary) -> bool:
	if _known_person(id,registry) or id=="avat_ar": return true
	if id in ["board/security","board/commerce","board/exploration"]: return true
	return id in ["faction/security","faction/commerce","faction/exploration","faction/underworld"]

static func civic_links_match(data: Dictionary) -> bool:
	# Pure canonical-value checks, shared by synchronous decoding and the worker.
	# No scene, catalog, UI, Resource creation or live authority is consulted.
	if not data.has("civilization_state") or not data.has("civilian_state"): return false
	for key: String in CIVIC_FIELDS:
		if not data.has(key): return false
	var registry: Dictionary=data.civilization_state.registry
	var ledger: Dictionary=data.civilian_state
	var quests: Dictionary=data.quest_state
	var now: float=float(registry.world_seconds)
	if float(quests.world_seconds)>now+.00001: return false
	for id: String in quests.memberships:
		if not _known_person(id,registry): return false
		for faction: String in quests.memberships[id]:
			if not faction in ledger.factions: return false
	for id: String in quests.introductions:
		if not _known_person(id,registry) or not _known_person(quests.introductions[id],registry): return false
	for id: String in quests.instances:
		var row: Dictionary=quests.instances[id]
		if not _known_person(row.issuer,registry) and not row.issuer in ["faction/security","faction/commerce","faction/exploration","faction/underworld"]: return false
		if not row.participant.is_empty() and not _known_person(row.participant,registry): return false
		if not row.faction.is_empty() and not row.faction in ledger.factions: return false
		for eligible: String in row.eligible:
			if not _known_person(eligible,registry): return false
		if not String(row.objective.recipient_id).is_empty() and row.objective.recipient_id!="guild" and not _known_speaker(row.objective.recipient_id,registry): return false
		if row.status in ["active","ready"] and row.participant!="player" and not registry.records[row.participant].active: return false
		if not ledger.contracts.has(id): return false
		var escrow: Dictionary=ledger.contracts[id]
		if row.source!=escrow.source or int(row.reward)!=int(escrow.amount): return false
		if row.status=="completed":
			var payee: String=String(data.inventory.owner_id) if row.participant=="player" else String(row.participant)
			if escrow.status!="settled" or escrow.payee!=payee or escrow.service!=row.kind or escrow.legality!=row.legality: return false
		elif row.status in ["cancelled","failed","expired"]:
			if escrow.status!="refunded": return false
		elif escrow.status!="reserved": return false
	for id: String in ledger.contracts:
		if ledger.contracts[id].status=="reserved" and not quests.instances.has(id): return false
		if id.begins_with("quest_") and id.trim_prefix("quest_").is_valid_int() and id=="quest_"+str(int(id.trim_prefix("quest_"))) and int(id.trim_prefix("quest_"))>=int(quests.next_id): return false
	for row: Dictionary in data.law_state.cases.values():
		if float(row.timestamp)>now+.00001 or float(row.resolved_at)>now+.00001 or not _known_person(row.offender,registry): return false
		if not row.victim.is_empty() and not _known_person(row.victim,registry): return false
		if not row.investigator.is_empty() and not _known_person(row.investigator,registry): return false
		for witness: String in row.witnesses:
			if not _known_person(witness,registry): return false
	var communication: Dictionary=data.communication_state
	for id: String in communication.profiles.records:
		if not _known_speaker(id,registry): return false
		for context: Dictionary in communication.profiles.records[id].context:
			if not _known_speaker(context.listener_id,registry): return false
	for rows: Array in [communication.protocol.recent,communication.protocol.facts]:
		for row: Dictionary in rows:
			if not _known_speaker(row.speaker_id,registry) or not _known_speaker(row.listener_id,registry) or float(row.world_timestamp)>now+.00001: return false
	return true

static func wonders_clock_matches(stock: Dictionary,registry: Dictionary) -> bool:
	# Only canonical scalar fields are read here. Unlike Stock.validate, this
	# cross-check is safe on a worker after main-thread catalog validation.
	if float(stock.config.day_seconds)!=float(registry.config.day_seconds): return false
	var interval: float=float(stock.config.day_seconds)*float(stock.config.interval_days)
	return int(stock.cycle)==floori(float(registry.world_seconds)/interval)

static func store(path: String, snapshot: Dictionary) -> Error:
	var validated := decode(snapshot)
	if validated.is_empty(): return ERR_INVALID_DATA
	return _commit_encoded(path,JSON.stringify(validated,"",true,true).to_utf8_buffer())

static func _commit_encoded(path: String, bytes: PackedByteArray) -> Error:
	# Internal commit boundary: callers must have validated this immutable
	# encoding with Store.decode or CheckpointEncoder. Never accepts live state.
	if bytes.is_empty(): return ERR_INVALID_DATA
	if bytes.size()>MAX_SAVE_BYTES: return ERR_OUT_OF_MEMORY
	var absolute := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK: return directory_error
	var temporary := absolute+".tmp-"+Instance.new_id()
	var backup := absolute+".bak"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return write_error
	var existing := FileAccess.file_exists(absolute)
	if existing:
		if FileAccess.file_exists(backup):
			var remove_error := DirAccess.remove_absolute(backup)
			if remove_error != OK:
				DirAccess.remove_absolute(temporary)
				return remove_error
		var backup_error := DirAccess.rename_absolute(absolute,backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return backup_error
	var commit_error := DirAccess.rename_absolute(temporary,absolute)
	if commit_error != OK:
		if existing: DirAccess.rename_absolute(backup,absolute)
		DirAccess.remove_absolute(temporary)
		return commit_error
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	return OK

static func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {}
	if file.get_length()>MAX_SAVE_BYTES:
		file.close()
		return {}
	var contents := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(contents) != OK: return {}
	return decode(parser.data)

static func load_snapshot(path: String) -> Dictionary:
	var main := _read(path)
	if not main.is_empty(): return main
	# A process interruption between the two renames can leave only .bak.
	# Loading never repairs/overwrites either file; the live session decides.
	return _read(path+".bak")
