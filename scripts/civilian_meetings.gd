extends RefCounted
## A small number of consenting local friends make an actual appointment.
## Movement belongs to the same validated route walkers as every other visit.
var errands: Node
var plans: Dictionary={}
var reserved: Dictionary={}

func consider(id: String) -> bool:
	if reserved.has(id): return true
	if plans.size()>=3: return false
	var autonomy=errands._autonomy()
	var row: Dictionary=autonomy._registry().records.get(id,{})
	if row.get("current_goal")!="socialize": return false
	var route_record: Dictionary=autonomy._regional_records.get(id,{})
	if route_record.is_empty() or route_record.get("combat",false) or route_record.has("career_commute") or route_record.get("wonders_route",false): return false
	for peer: String in row.relationships:
		if float(row.relationships[peer])<.2 or reserved.has(peer) or errands.active.has(peer): continue
		var other: Dictionary=autonomy._registry().records.get(peer,{})
		var friend: Dictionary=autonomy._regional_records.get(peer,{})
		if not other.get("active",false) or friend.is_empty() or autonomy._unavailable(peer) or friend.get("combat",false) or friend.has("career_commute") or friend.get("wonders_route",false): continue
		if float(other.relationships.get(id,0))<.1 or maxf(float(autonomy._state(peer).hunger),float(autonomy._state(peer).thirst))>=.5: continue
		var recently_met:=false
		for memory: Dictionary in row.memories:
			if memory.type=="appointment" and memory.target==peer and errands._now()-float(memory.timestamp)<autonomy._day(): recently_met=true
		if recently_met or route_record.point.distance_to(friend.point)>64: continue
		var path:=PackedVector3Array()
		for side: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
			path=errands._path(route_record.point,friend.point+side*1.5)
			if not path.is_empty(): break
		if path.is_empty(): continue
		var outward:=path.duplicate()
		for i in range(path.size()-2,-1,-1): path.append(path[i])
		var return_index:=path.size()-1
		var base: PackedVector3Array=route_record.route.duplicate()
		for i in range(base.size()): path.append(base[(int(route_record.cursor)+i)%base.size()])
		plans[id]={"id":id,"peer":peer,"record":route_record,"friend":friend,"route":base,"cursor":int(route_record.cursor),"arrival":outward.size()-1,"return":return_index,"phase":"walking","remaining":8.0,"deadline":errands._now()+120*autonomy._scale()}
		reserved[id]=id; reserved[peer]=id
		route_record.route=path; route_record.cursor=1; route_record.wait=0.0
		for pair: Array in [[id,peer],[peer,id]]:
			autonomy._registry().remember(pair[0],"appointment",pair[1],"Arranged to meet "+String(autonomy._registry().records[pair[1]].name)+" in the neighborhood.",.5)
		return true
	return false

func describe(id: String) -> String:
	if not reserved.has(id): return ""
	var plan: Dictionary=plans.get(reserved[id],{})
	if plan.is_empty(): return ""
	var other:=String(plan.peer) if id==plan.id else String(plan.id)
	return "I've arranged to meet "+String(errands._autonomy()._registry().records.get(other,{}).get("name","a friend"))+" nearby."

func on_arrival(record: Dictionary) -> bool:
	var id:=String(record.get("code_form_id",""))
	var plan: Dictionary=plans.get(id,{})
	if plan.is_empty(): return false
	if int(record.cursor)==int(plan.arrival) and plan.phase=="walking":
		if record.point.distance_to(plan.friend.point)<=3:
			plan.phase="talking"
			var registry=errands._autonomy()._registry()
			errand_social(registry.records[id],registry.records[plan.peer])
		else: plan.phase="returning"
	elif int(record.cursor)==int(plan["return"]): call_deferred("finish",id)
	return true

func errand_social(a: Dictionary,b: Dictionary) -> void:
	errands._autonomy()._social(a,b,true)
	for pair: Array in [[a,b],[b,a]]:
		var source: Node=errands._autonomy()._source(pair[0].id)
		if is_instance_valid(source) and is_instance_valid(source.get("caption")):
			source.caption.text="Good to catch up, "+String(pair[1].name)+"."
			source.state="meeting a friend"; source.record.meetings=maxi(1,int(source.record.get("meetings",0)))

func process(delta: float) -> void:
	for id: String in plans.keys():
		var plan: Dictionary=plans[id]
		if plan.phase=="returning": continue
		if errands._autonomy()._unavailable(id) or errands._autonomy()._unavailable(String(plan.peer)) or errands._now()>float(plan.deadline):
			plan.phase="returning"; reserved.erase(plan.peer)
			continue
		plan.friend.wait=1.0
		var peer: Node=errands._autonomy()._source(plan.peer)
		if is_instance_valid(peer): peer.wait=1.0
		if plan.phase!="talking": continue
		plan.record.wait=1.0
		var actor: Node=errands._autonomy()._source(id)
		if is_instance_valid(actor): actor.wait=1.0
		plan.remaining=maxf(0,float(plan.remaining)-delta)
		if plan.remaining==0:
			plan.phase="returning"; reserved.erase(plan.peer)

func finish(id: String) -> void:
	var plan: Dictionary=plans.get(id,{})
	if plan.is_empty(): return
	plan.record.route=plan.route; plan.record.cursor=plan.cursor
	reserved.erase(id); reserved.erase(plan.peer); plans.erase(id)

func clear() -> void:
	for plan: Dictionary in plans.values():
		plan.phase="returning"; reserved.erase(plan.peer)
