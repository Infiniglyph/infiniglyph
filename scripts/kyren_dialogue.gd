extends Node
## One subtitle channel, weighted context selection and bounded important queues.
signal selected(id: String, text: String, priority: int)
@export var global_cooldown := 3.8
@export var silence_chance := .15
var lines: Array = []
var rng := RandomNumberGenerator.new()
var clock := 0.0
var remaining := 0.0
var cooldown_remaining := 0.0
var current_text := ""
var current_id := ""
var current_priority := 0
var last_selected := ""
var _interrupt_remaining := 0.0
var _used: Dictionary = {}
var _important: Array[Dictionary] = []

func _ready() -> void:
	rng.randomize()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue/kyren.json"))
	if data is Dictionary and data.get("version")==1 and data.get("lines") is Array: lines = data.lines

func advance(delta: float) -> void:
	clock += delta
	remaining = maxf(0,remaining-delta)
	cooldown_remaining = maxf(0,cooldown_remaining-delta)
	_interrupt_remaining = maxf(0,_interrupt_remaining-delta)
	if remaining>0: return
	current_text = ""
	if cooldown_remaining==0: current_priority = 0
	if _important.is_empty(): return
	_important[0].delay -= delta
	if float(_important[0].delay)>0: return
	var next: Dictionary = _important.pop_front()
	preview(next.id)

func eligible(line: Dictionary, trigger: StringName, salt: float, context: Dictionary) -> bool:
	if not String(trigger) in line.triggers or salt<float(line.min_salt) or salt>float(line.max_salt): return false
	if line.id==last_selected or clock<float(_used.get(line.id,-INF)): return false
	for key: String in line.get("conditions",{}):
		if context.get(key,false)!=line.conditions[key]: return false
	if context.get("combat",false) and not context.get("opening",false) and String(line.text).length()>85: return false
	return true

func say(trigger: StringName, salt: float, context: Dictionary = {}, certain: bool = false) -> bool:
	if not _important.is_empty(): return false
	var options: Array[Dictionary] = []
	var weight := 0.0
	for line: Dictionary in lines:
		if not eligible(line,trigger,salt,context): continue
		var priority := int(line.priority)
		if _interrupt_remaining>0: continue
		if (remaining>0 or cooldown_remaining>0) and priority<=current_priority: continue
		options.append(line)
		weight += float(line.weight)
	if options.is_empty() or (not certain and rng.randf()<silence_chance): return false
	var pick := rng.randf()*weight
	for line: Dictionary in options:
		pick -= float(line.weight)
		if pick<=0:
			_present(line)
			return true
	_present(options[-1])
	return true

func _present(line: Dictionary) -> void:
	current_id = line.id
	last_selected = line.id
	current_text = line.text
	current_priority = int(line.priority)
	remaining = clampf(current_text.length()*.045+1.4,2.3,6.0)
	cooldown_remaining = global_cooldown
	_interrupt_remaining = .85
	_used[line.id] = clock+float(line.cooldown)
	selected.emit(current_id,current_text,current_priority)

func preview(id: String) -> bool:
	for line: Dictionary in lines:
		if line.id==id:
			_present(line)
			return true
	return false

func queue_special(ids: Array[String]) -> void:
	_important.clear()
	if ids.is_empty(): return
	preview(ids[0])
	for index in range(1,ids.size()): _important.append({"id":ids[index],"delay":1.1})

func clear() -> void:
	_important.clear()
	remaining = 0
	current_text = ""
	current_priority = 0
