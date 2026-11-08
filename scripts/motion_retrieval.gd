extends Node
## Async local pose constraints; physics and animation never wait for Python.
@export var enabled := true
@export var python_executable := "py" if OS.get_name() == "Windows" else "python3"
const LIMITS := {"pitch_gain":Vector2(0.6,1.4),"yaw_gain":Vector2(0.6,1.4),"bank_gain":Vector2(0.6,1.4),"sway_gain":Vector2(0.6,1.3),"settle_gain":Vector2(0.75,1.5)}
var parameters := {"pitch_gain":1.0,"yaw_gain":1.0,"bank_gain":1.0,"sway_gain":1.0,"settle_gain":1.0}
var context: Dictionary = {}
var last_decision: Dictionary = {}
var status := "local fallback"
var process_id := -1
var _session := ""
var _request_id := 0
var _last_sent := -1000
var _last_received := 0
var _last_response_id := -1
var _last_polled := -1000

func _ready() -> void:
	if not enabled: return
	var rag_root := ProjectSettings.globalize_path("res://../rag").simplify_path()
	if not FileAccess.file_exists(rag_root.path_join("context_builder.py")):
		rag_root = ProjectSettings.globalize_path("res://vendor/ted_rag")
	if not FileAccess.file_exists(rag_root.path_join("context_builder.py")):
		status = "local fallback: TED-RAG source unavailable"
		return
	_session = ProjectSettings.globalize_path("user://motion/%s-%s" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(_session)
	var args := PackedStringArray()
	if OS.get_name() == "Windows" and python_executable == "py": args.append("-3")
	args.append_array([ProjectSettings.globalize_path("res://tools/motion_retrieval.py"),"--session",_session,"--corpus",ProjectSettings.globalize_path("res://data/motion_constraints.json"),"--rag-root",rag_root])
	process_id = OS.create_process(python_executable,args,false)
	status = "awaiting TED-RAG" if process_id > 0 else "local fallback: Python unavailable"

func _process(_delta: float) -> void:
	if not enabled:
		if process_id > 0: _stop_helper()
		for name in parameters: parameters[name] = 1.0
		status = "local fallback: disabled"
		return
	if process_id <= 0: return
	var now := Time.get_ticks_msec()
	if now-_last_polled < 50: return
	_last_polled = now
	# Read only complete, atomically replaced responses for the latest context.
	var path := _session.path_join("response.json")
	if FileAccess.file_exists(path):
		var response = JSON.parse_string(FileAccess.get_file_as_string(path))
		if response is Dictionary and response.get("id",-1) == _request_id and _last_response_id != _request_id:
			if accept_response(response):
				_last_received = now
				_last_response_id = _request_id
				status = "TED-RAG live"
	if now-_last_sent >= 250 and not context.is_empty():
		_request_id += 1
		var temporary := _session.path_join("request.tmp")
		var file := FileAccess.open(temporary,FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"id":_request_id,"context":context}))
			file.close()
			DirAccess.rename_absolute(temporary,_session.path_join("request.json"))
		_last_sent = now
	if _last_received > 0 and now-_last_received > 1500:
		for name in parameters: parameters[name] = 1.0
		status = "local fallback: retrieval stale"
	if not OS.is_process_running(process_id):
		_stop_helper()
		for name in parameters: parameters[name] = 1.0
		status = "local fallback: helper stopped"

func accept_response(response: Dictionary) -> bool:
	if response.get("schema") != 1 or response.get("engine") != "TED-RAG/context_builder": return false
	var values = response.get("parameters")
	if not values is Dictionary or values.size() != LIMITS.size(): return false
	for name in LIMITS:
		var number = values.get(name)
		if not (number is float or number is int) or not is_finite(float(number)): return false
		var bounds: Vector2 = LIMITS[name]
		if float(number) < bounds.x or float(number) > bounds.y: return false
	parameters = values.duplicate()
	last_decision = response.duplicate(true)
	return true

func _exit_tree() -> void:
	_stop_helper()

func _stop_helper() -> void:
	# py.exe may launch a child interpreter; signal that child before closing py.
	if not _session.is_empty():
		var stop := FileAccess.open(_session.path_join("stop"),FileAccess.WRITE)
		if stop: stop.close()
	if process_id > 0 and OS.is_process_running(process_id): OS.kill(process_id)
	process_id = -1
