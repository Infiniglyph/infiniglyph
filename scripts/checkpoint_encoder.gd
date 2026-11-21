extends RefCounted
## One private, value-only checkpoint encoding job. Disk commits stay on the
## main thread so a completed older job can never overwrite a newer load/save.
const Store = preload("res://scripts/inventory_store.gd")
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
	# Snapshot serializers already detach their values from the live models.
	# Public callers also retain their input, so give the worker its own copy.
	var private: Dictionary={}
	for key: String in ["version","policy","session_id","inventory","world_drops","markers","location_context","location_state","civilian_state","civilization_state","glyphic_wonders_state","quest_state","communication_state","law_state","building_state","career_state","dark_box_state"]:
		if snapshot.has(key): private[key]=snapshot[key]
	return _launch(private.duplicate(true))

func start_owned(snapshot: Dictionary) -> Error:
	# Only the session's freshly serialized checkpoint uses ownership transfer.
	# Nothing may retain/mutate this dictionary after calling this method.
	if not Thread.is_main_thread(): return ERR_UNAUTHORIZED
	if pending(): return ERR_BUSY
	return _launch(snapshot)

func _launch(private_snapshot: Dictionary) -> Error:
	if private_snapshot.get("version")!=Store.VERSION or private_snapshot.get("policy")!=Store.POLICY: return ERR_INVALID_DATA
	# Initialize immutable catalog content on its owning thread once. Validation
	# only reads these definitions; it never edits a shared Resource. Inventory
	# Nodes created by decode belong exclusively to the worker and never enter
	# an active SceneTree. Keep Godot's thread-safety checks enabled.
	Store.Equipment.prepare()
	Store.Inventory.Catalog._prepare()
	load("res://scripts/dark_box_patrols.gd")
	_thread=Thread.new()
	var error: Error=_thread.start(_encode.bind(private_snapshot),Thread.PRIORITY_LOW)
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

static func _failure(error: Error, stage: String = "encoding") -> Dictionary:
	return {"error":error,"bytes":PackedByteArray(),"stage":stage}

static func _encode(snapshot: Dictionary) -> Dictionary:
	# No live containers or scene objects are used by this worker. Unknown
	# object/cyclic fields are rejected before any model reads them.
	if not _values_only(snapshot): return _failure(ERR_INVALID_DATA,"value boundary")
	var diagnostic: Dictionary={}
	var captured:=Store._decode(snapshot,false,diagnostic)
	if captured.is_empty(): return _failure(ERR_INVALID_DATA,String(diagnostic.get("stage","checkpoint validation")))
	var bytes: PackedByteArray=JSON.stringify(captured,"",true,true).to_utf8_buffer()
	if bytes.size()>Store.MAX_SAVE_BYTES: return _failure(ERR_OUT_OF_MEMORY)
	return {"error":OK,"bytes":bytes}
