extends SceneTree
## The actual asynchronous TED-RAG helper, independent of city rendering fixtures.
const Retrieval=preload("res://scripts/motion_retrieval.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func wait_policy(retrieval: Node,profile: String) -> bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		if retrieval.status=="TED-RAG live" and not retrieval.last_world_decision.is_empty() and retrieval.last_world_decision.profiles[0]==profile: return true
		OS.delay_msec(10)
		await process_frame
	return false
func run() -> void:
	var retrieval:=Retrieval.new()
	retrieval.context={"speed":.2,"grounded":true}
	retrieval.world_context={"speed":.2,"crowd":1.0,"combat":0.0}
	root.add_child(retrieval)
	var live:=await wait_policy(retrieval,"crowded")
	check(live,"The live TED-RAG helper blends the authored crowd constraints")
	if live:
		var crowd_range: float=retrieval.world_policy().near_range
		var worker: int=retrieval.process_id
		var constraint: Dictionary=retrieval.last_world_decision.get("constraint",{})
		check(is_equal_approx(float(constraint.get("weight_sum",0)),1) and constraint.get("terms",[]).size()==2,"The existing builder returns two normalized weighted components")
		retrieval.world_context={"speed":.3,"crowd":.3,"combat":1.0}
		check(await wait_policy(retrieval,"combat") and retrieval.world_policy().near_range>crowd_range,"Combat still retrieves its broader visual-detail neighborhood")
		check(retrieval.process_id==worker,"Changing context reuses the same asynchronous worker")
		var bounded:=true
		for key: String in retrieval.WORLD_LIMITS:
			var bounds: Vector2=retrieval.WORLD_LIMITS[key]
			var value: float=retrieval.world_policy()[key]
			bounded=bounded and value>=bounds.x and value<=bounds.y
		check(bounded,"Weighted results remain inside all authored policy limits")
		var bad: Dictionary=retrieval.last_decision.duplicate(true)
		bad.world_attention.parameters.near_range=1e6
		check(retrieval.accept_response(bad) and retrieval.world_policy()==retrieval.WORLD_DEFAULTS,"An invalid retrieved policy immediately uses local defaults")
	retrieval.enabled=false
	await process_frame; await process_frame
	check(retrieval.process_id==-1 and retrieval.world_policy()==retrieval.WORLD_DEFAULTS,"Disabling retrieval stops its helper and leaves safe local policy")
	retrieval.queue_free()
	await process_frame
	print("WEIGHTED CONSTRAINT INTEGRATION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
