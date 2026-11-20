extends RefCounted
## One private, value-only checkpoint encoding job. Disk commits stay on the
## main thread so a completed older job can never overwrite a newer load/save.
const Store = preload("res://scripts/inventory_store.gd")
const Civilization = preload("res://scripts/code_form_civilization.gd")
const MAX_VALUE_DEPTH := 64
var _thread: Thread

func pending() -> bool:
	return _thread!=null

func ready() -> bool:
	return _thread!=null and not _thread.is_alive()

func start(snapshot: Dictionary) -> Error:
	if not Thread.is_main_thread(): return ERR_UNAUTHORIZED
	# A finished job must also be consumed/discarded before starting its successor.
	if pending(): return ERR_BUSY
	var core := snapshot.duplicate()
	core.erase("civilization_state")
	core.erase("building_state")
	core.erase("career_state")
	for key: String in Store.CIVIC_FIELDS: core.erase(key)
	# Inventory/catalog restoration creates temporary Nodes. It must stay here;
	# the background worker only handles civilian value models and JSON bytes.
	var captured: Dictionary=Store._decode(core,Store.has_civic_state(snapshot))
	if captured.is_empty(): return ERR_INVALID_DATA
	if Store.has_civic_state(snapshot):
		if not snapshot.has("civilization_state"): return ERR_INVALID_DATA
		var civic:=Store.canonical_civic_state(snapshot)
		if civic.is_empty(): return ERR_INVALID_DATA
		captured.merge(civic)
	if snapshot.has("building_state"):
		var model: Script=load("res://scripts/building_registry.gd")
		var buildings: Dictionary=model.validate(snapshot.building_state)
		if buildings.is_empty(): return ERR_INVALID_DATA
		captured.building_state=buildings
	if snapshot.has("career_state"):
		var model: Script=load("res://scripts/career_registry.gd")
		var careers: Dictionary=model.validate(snapshot.career_state)
		if careers.is_empty(): return ERR_INVALID_DATA
		captured.career_state=careers
	var society_bytes:=PackedByteArray()
	var has_society:=snapshot.has("civilization_state")
	if snapshot.has("civilization_state"):
		if not snapshot.civilization_state is Dictionary: return ERR_INVALID_DATA
		# The native, object-disabled binary boundary copies all live containers
		# without a costly GDScript walk of every memory/novelty scalar. Objects
		# can at most become inert EncodedObjectAsID values, rejected on decode.
		society_bytes=var_to_bytes(snapshot.civilization_state)
		if society_bytes.is_empty(): return ERR_INVALID_DATA
	_thread=Thread.new()
	var error: Error=_thread.start(_encode.bind(captured,society_bytes,has_society),Thread.PRIORITY_LOW)
	if error!=OK: _thread=null
	return error

func take_result() -> Dictionary:
	if not Thread.is_main_thread() or not ready(): return {}
	return finish()

func finish(discard_result: bool = false) -> Dictionary:
	if not Thread.is_main_thread() or _thread==null: return {}
	var result: Variant=_thread.wait_to_finish()
	_thread=null
	if discard_result: return {}
	if not result is Dictionary or not result.has("error") or not result.get("bytes") is PackedByteArray:
		return _failure(ERR_INVALID_DATA)
	return result

func discard() -> void:
	finish(true)

func _notification(what: int) -> void:
	# Callers normally finish explicitly before load, manual save and shutdown.
	# Also join a forgotten job before its Thread reference can be destroyed.
	if what==NOTIFICATION_PREDELETE and _thread!=null:
		_thread.wait_to_finish()
		_thread=null

static func _values_only(value: Variant,depth: int = 0) -> bool:
	# The depth bound rejects cyclic containers as well as pathological nesting.
	# Neither a Node nor a Resource/Callable may cross the thread boundary, even
	# if hidden in an unknown field that a canonical validator would discard.
	if depth>MAX_VALUE_DEPTH: return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING,TYPE_STRING_NAME: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			for child: Variant in value:
				if not _values_only(child,depth+1): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not (key is String or key is StringName) or not _values_only(value[key],depth+1): return false
			return true
	return false

static func _failure(error: Error) -> Dictionary:
	return {"error":error,"bytes":PackedByteArray()}

static func _encode(captured: Dictionary,society_bytes: PackedByteArray,has_society: bool) -> Dictionary:
	# This static callable retains no encoder/scene object. Every container is
	# private to this worker until wait_to_finish transfers the resulting bytes.
	if has_society:
		if not captured.has("civilian_state"): return _failure(ERR_INVALID_DATA)
		# bytes_to_var never resolves object IDs to scene objects or runs code.
		# Keep engine thread-safety checks enabled throughout this worker.
		var decoded: Variant=bytes_to_var(society_bytes)
		if not decoded is Dictionary or not _values_only(decoded): return _failure(ERR_INVALID_DATA)
		var society: Dictionary=Civilization.validate(decoded)
		if society.is_empty(): return _failure(ERR_INVALID_DATA)
		var model: Dictionary=society.registry
		var active: Array=model.slots.values()
		var paid: Array=captured.civilian_state.active_ids.duplicate()
		active.sort(); paid.sort()
		if active!=paid: return _failure(ERR_INVALID_DATA)
		var history: Array=model.records.keys()
		var accounts: Array=captured.civilian_state.natural_ids.duplicate()
		history.sort(); accounts.sort()
		if history!=accounts: return _failure(ERR_INVALID_DATA)
		var interval: float=float(model.config.blessing_days)*float(model.config.day_seconds)
		if int(captured.civilian_state.last_cycle)!=floori(float(model.world_seconds)/interval): return _failure(ERR_INVALID_DATA)
		if not Civilization.ledger_matches(society,captured.civilian_state): return _failure(ERR_INVALID_DATA)
		if captured.has("glyphic_wonders_state") and not Store.wonders_clock_matches(captured.glyphic_wonders_state,model): return _failure(ERR_INVALID_DATA)
		captured.civilization_state=society
	if Store.has_civic_state(captured) and not Store.civic_links_match(captured): return _failure(ERR_INVALID_DATA)
	if not Store.building_links_match(captured): return _failure(ERR_INVALID_DATA)
	if not Store.career_links_match(captured): return _failure(ERR_INVALID_DATA)
	var bytes: PackedByteArray=JSON.stringify(captured,"",true,true).to_utf8_buffer()
	if bytes.size()>Store.MAX_SAVE_BYTES: return _failure(ERR_OUT_OF_MEMORY)
	return {"error":OK,"bytes":bytes}
