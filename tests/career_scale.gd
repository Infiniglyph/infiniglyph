extends SceneTree
const Careers=preload("res://scripts/career_registry.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run() -> void:
	var model:=Careers.new()
	model.configure({"identity":func(id: String): return {"active":true,"kind":"code_form","level":5,"occupation":"","motivations":{"wealth":.5,"knowledge":.7,"mastery":.6,"security":.5,"loyalty":.4,"novelty":.7,"social":.4}} if id.begins_with("scale/") else {},"quest":func(_operation: String,_payload: Dictionary): return {},"perform":func(_id: String,_capability: String,_employment: Dictionary): return {},"context":func(_id: String): return {"guilds":["adventurers_guild"],"equipment":["spear"],"skills":["exploration"],"workplaces":[],"resources":{}}})
	var start:=Time.get_ticks_usec()
	for n in range(2048): model.npc_step("scale/"+str(n),0)
	var initial: float=(Time.get_ticks_usec()-start)/1000.0
	check(model.workers.size()==2048 and model.employments.size()==2048,"The full active census can choose from all seventy-four career definitions")
	start=Time.get_ticks_usec()
	for n in range(2048): model.npc_step("scale/"+str(n),1)
	var ordinary: float=(Time.get_ticks_usec()-start)/1000.0
	check(model.employments.size()==2048,"Ordinary scheduled steps do not create duplicate occupations")
	start=Time.get_ticks_usec()
	for n in range(2048): model.npc_step("scale/"+str(n),86401)
	var daily: float=(Time.get_ticks_usec()-start)/1000.0
	var encoded:=JSON.stringify(model.serialize())
	check(not Careers.validate(JSON.parse_string(encoded)).is_empty(),"A full census survives strict career JSON validation")
	check(encoded.to_utf8_buffer().size()<4*1024*1024,"Full-census career state remains bounded below four MiB")
	print("CAREER SCALE census=2048 initial_ms=",initial," ordinary_ms=",ordinary," daily_ms=",daily," save_bytes=",encoded.to_utf8_buffer().size())
	print("Career scale: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
