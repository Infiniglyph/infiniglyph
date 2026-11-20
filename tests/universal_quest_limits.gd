extends SceneTree
const Model=preload("res://scripts/universal_quests.gd")
var checks:=0
var failures:=0
var reserves:=0
var pays:=0
var refunds:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func setup(model: RefCounted) -> void:
	model.configure({"identity":func(id: String): return {"active":id=="worker","kind":"code_form"},"authorize":func(_operation: String,_row: Dictionary): return true,"finance":finance})
func finance(row: Dictionary) -> bool:
	if row.operation=="reserve": reserves+=1
	elif row.operation=="pay": pays+=1
	elif row.operation=="refund": refunds+=1
	return true
func create(model: RefCounted) -> String: return model.create_contract("exploration_discovery","faction/exploration","faction:exploration",{"target_id":"survey/site"},0)
func run() -> void:
	var model:=Model.new(); setup(model); model.join("worker","exploration")
	var first:=create(model); model.accept(first,"worker",0)
	var receipt: Dictionary={"event_id":"one-real-discovery","event_type":"discovery","actor_id":"worker","target_id":"survey/site","timestamp":0}
	model.consume_event(receipt)
	var ids: Array[String]=[]
	for i in range(Model.MAX_OPEN): ids.append(create(model))
	check(not ids.has("") and create(model).is_empty() and reserves==Model.MAX_OPEN+1,"The open-work cap rejects excess promises before any finance callback")
	for id: String in ids: model.cancel(id,"faction/exploration")
	check(refunds==Model.MAX_OPEN and model.obligations().is_empty(),"Every bounded open obligation can cancel and refund without orphaning work")
	var highest:=model.next_id
	for i in range(Model.MAX_INSTANCES+32):
		var id:=create(model)
		model.cancel(id,"faction/exploration")
	check(model.instances.size()==Model.MAX_INSTANCES and not model.instances.has(first) and model.next_id>highest+Model.MAX_INSTANCES,"Completed history prunes to a fixed bound while quest identities remain monotonic")
	var restored:=Model.new(); setup(restored)
	check(restored.restore(JSON.parse_string(JSON.stringify(model.serialize()))),"A full bounded quest archive survives strict JSON validation")
	var next:=create(restored); restored.accept(next,"worker",0)
	check(restored.consume_event(receipt).is_empty() and restored.instances[next].status=="active" and pays==1,"A replayed world event stays ineligible after its original quest history was pruned and reloaded")
	check(restored.create_contract("commerce_service","faction/commerce","faction:commerce",{"target_id":"guild","service":"work","count":65},0).is_empty(),"One quest cannot request an unbounded objective or event history")
	var began:=Time.get_ticks_usec()
	for i in range(100): restored.advance_to(float(i))
	print("MEASURE bounded quest archive100 clock ticks_ms=",float(Time.get_ticks_usec()-began)/1000.0," archive=",restored.instances.size()," save_bytes=",JSON.stringify(restored.serialize()).to_utf8_buffer().size())
	check(not paused,"Bounded logical quest simulation never pauses the scene tree")
	print("Universal quest limits: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
