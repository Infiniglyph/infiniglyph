extends SceneTree
const Autonomy=preload("res://scripts/code_form_autonomy.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
const Resident=preload("res://scripts/city_resident.gd")
const Profiles=preload("res://scripts/resident_profiles.gd")

class Ledger extends Node:
	var coins: Dictionary={"business:guild":100,"business:tavern":100}
	var wages: Dictionary={}
	var transfers:=0
	func balance(id: String) -> int: return int(coins.get(id,0))
	func npc_service_wage(id: String,key: String,day: int) -> bool:
		var token:=id+"/"+key+"/"+str(day)
		if wages.has(token) or coins["business:guild"]<=0: return false
		coins["business:guild"]-=1
		coins["resident:"+id]=balance("resident:"+id)+1
		wages[token]=true; transfers+=1
		return true
	func npc_consume_food(_id: String,_type: StringName) -> bool: return false
	func npc_buy_food(_id: String,_type: StringName) -> bool: return false
	func purchase_wonder(_id: String) -> bool: return false

class Society extends Node:
	var registry=Registry.new()
	var economy: Node
	var autonomy=Autonomy.new()
	var world: Node3D
	func id_for_source(source: Node) -> String:
		var id:=String(source.get_meta("code_form_id",""))
		return id if registry.records.get(id,{}).get("active",false) else ""
	func record_event(event: Dictionary) -> Dictionary:
		var normalized:=event.duplicate(true)
		normalized.type=normalized.get("event_type",normalized.get("type",""))
		return registry.record_event(normalized)
	func record_interaction(id: String,kind: String,target: String,positive: bool=true) -> void:
		registry.remember(id,kind,target,"A conversation.",.5)
		registry.relate(id,target,.03 if positive else -.08)

class Population extends Node3D:
	var civilization: Node
	var reactions: Node3D
	var residents: Array[CharacterBody3D]=[]
	var active_residents: Array[CharacterBody3D]=[]
	var by_id: Dictionary={}
	var points: Dictionary={&"west_court":Vector3.ZERO,&"west_garden":Vector3(-20,0,0),&"north_w":Vector3(0,0,-20)}
	var place_neighborhood: Dictionary={&"west_court":&"hub",&"west_garden":&"hub",&"north_w":&"hub"}
	var neighborhood_places: Dictionary={&"hub":[&"west_court",&"west_garden",&"north_w"]}
	var entrances: Dictionary={}
	var player: CharacterBody3D
	var speaker: CharacterBody3D
	var speaker_time:=0.0
	var reserved_outdoors:=0
	func nearest_id(_at: Vector3) -> StringName: return &"west_court"
	func place_name(id: StringName) -> String: return String(id).replace("_"," ")
	func goal_load(_id: StringName) -> int: return 0

class TestWorld extends Node3D:
	var population: Node3D
	var district_life: Node3D

var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)

func row(id: String) -> Dictionary:
	return {"id":id,"slot":"hub/"+id,"name":id.capitalize(),"occupation":"gardener","personality":"curious","respawn":{"location":"overworld","position":[0.0,0.04,0.0],"yaw":0.0}}

func run() -> void:
	var society:=Society.new()
	root.add_child(society)
	var ledger:=Ledger.new()
	society.add_child(ledger)
	society.economy=ledger
	society.autonomy.civilization=society
	var rows: Array[Dictionary]=[]
	for i in range(32): rows.append(row("civilian"+str(i)))
	check(society.registry.bootstrap(rows),"Autonomy starts only from an explicit civilian census")
	for id: String in society.registry.active_ids(): ledger.coins["resident:"+id]=50
	var a: Dictionary=society.registry.records.civilian0
	var b: Dictionary=society.registry.records.civilian1
	for record: Dictionary in [a,b]:
		for key: String in record.motivations: record.motivations[key]=0.0
	a.motivations.mastery=1.0
	b.motivations.social=1.0
	check(society.autonomy.choose_goal(a,{"hunger":0.0,"turn":1})=="train" and society.autonomy.choose_goal(b,{"hunger":0.0,"turn":1})=="socialize","Different motives select different civilian intentions")
	check(society.autonomy.choose_goal(a,{"hunger":1.0,"turn":1})=="eat","Hunger changes priorities without a new combat resource")
	var motives: Dictionary=a.motivations.duplicate(true)
	for key: String in a.motivations: a.motivations[key]=0.0
	var expiration: float=a.expires_at
	a.expires_at=1.0
	check(society.autonomy.choose_goal(a,{"hunger":0.0,"turn":1}) in ["work","guild","explore"],"A short remaining lifetime favors meaningful progression opportunities")
	a.expires_at=expiration
	society.registry.remember(a.id,"combat","test","A dangerous encounter.",.8)
	check(society.autonomy.choose_goal(a,{"hunger":0.0,"turn":1})=="rest","Recent combat memories increase caution rather than automatic aggression")
	a.memories.clear()
	a.relationships[b.id]=1.0
	check(society.autonomy.choose_goal(a,{"hunger":0.0,"turn":1})=="socialize","Existing relationships influence future social plans")
	a.relationships.clear(); a.motivations=motives
	var before: int=society.autonomy.decisions
	society.autonomy.process_batch(1000000000.0)
	check(society.autonomy.decisions-before<=12 and society.autonomy.states.size()==12,"Huge elapsed input still processes at most twelve identities")
	society.autonomy.process_batch(1)
	society.autonomy.process_batch(1)
	check(society.autonomy.states.size()==32,"Rotating batches eventually cover every unloaded identity")
	for id: String in society.registry.active_ids():
		society.registry.set_goal(id,"work")
		var state: Dictionary=society.autonomy.states[id]
		state.next_decision=1000000.0; state.next_action=0.0
	society.autonomy.process_batch(1)
	check(ledger.transfers>0 and ledger.coins["business:guild"]+ledger.transfers==100,"Unloaded work uses funded transfers rather than issuing money")
	society.autonomy.process_batch(1)
	society.autonomy.process_batch(1)
	var saved: Dictionary=society.autonomy.serialize()
	var restored=Autonomy.new()
	restored.civilization=society
	check(restored.restore(saved) and restored.serialize()==saved,"Goal scheduler, appetite and cooldowns round trip exactly")
	check(restored.restore(JSON.parse_string(JSON.stringify(saved))),"A real JSON checkpoint round trip restores numeric scheduler fields")
	var total:=ledger.transfers
	restored.process_batch(0)
	check(ledger.transfers==total,"Restoring the same clock cannot replay completed wages")
	var bad:=saved.duplicate(true)
	bad.states.civilian0.hunger=NAN
	check(Autonomy.validate(bad,society.registry.active_ids()).is_empty(),"Malformed nonfinite scheduler state is rejected")
	bad=saved.duplicate(true); bad.states.player=bad.states.civilian0
	check(Autonomy.validate(bad,society.registry.active_ids()).is_empty(),"Player and undesignated entities cannot gain autonomy state")
	check(restored.restore({}) and restored.states.is_empty(),"Legacy checkpoints reset the optional decision scheduler safely")
	var state: Dictionary=society.autonomy._state(String(a.id))
	society.registry.set_goal(a.id,"guild")
	var xp: int=a.experience
	check(society.autonomy.perform_action(a,state,false) and a.guild=="adventurers_guild" and a.experience>xp,"Joining an existing guild is a meaningful one-time event")
	xp=a.experience
	check(not society.autonomy.perform_action(a,state,false) and a.experience==xp,"The same guild membership cannot repeatedly award XP")
	society.registry.set_goal(a.id,"train")
	for i in range(8): society.autonomy.perform_action(a,state,false)
	check(a.experience==xp,"Repeated idle training creates no animation XP")
	for i in range(8): society.autonomy._social(a,b)
	xp=a.experience
	for i in range(8): society.autonomy._social(a,b)
	check(a.relationships.get(b.id,0)>.2 and a.experience==xp,"Relationships develop while an existing friendship gives no repeat XP")
	var world:=TestWorld.new()
	root.add_child(world)
	var population:=Population.new()
	world.add_child(population)
	world.population=population
	society.world=world
	population.civilization=society
	population.player=CharacterBody3D.new()
	world.add_child(population.player)
	var source:=Resident.new()
	source.profile=Profiles.all(2)[0].duplicate(true)
	source.profile.id=StringName(a.id); source.profile.name=a.name
	source.profile.serial=0; source.profile.color_name="cyan"; source.profile.tint=Color.CYAN
	source.population=population
	population.add_child(source)
	population.residents.append(source)
	population.by_id[source.profile.id]=source
	society.autonomy.bind_sources()
	check(source.code_form_id==a.id and source.get_meta("code_form_id")==a.id,"Real pedestrian bodies bind a separate persistent identity")
	var affiliation: String=a.guild
	a.guild=""; society.registry.set_goal(a.id,"guild")
	source.indoor_left=INF
	check(not society.autonomy.perform_action(a,state,false) and a.guild.is_empty(),"A suspended combat source cannot perform hidden model actions")
	source.indoor_left=0.0; a.guild=affiliation
	source.active=true; source.transit=&"outdoor"; source.goal=&"west_court"
	society.registry.set_goal(a.id,"explore")
	var destination: StringName=society.autonomy.choose_destination(source)
	check(destination in [&"west_garden",&"north_w"],"Motivations select only existing reachable pedestrian destinations")
	source.transit=&"entering"
	check(society.autonomy.choose_destination(source).is_empty(),"Autonomy cannot interrupt a leased doorway passage")
	source.transit=&"outdoor"; source.reaction_time=3
	check(society.autonomy.choose_destination(source).is_empty(),"Observable danger reactions take priority over errands")
	source.reaction_time=0; source.goal=&"west_garden"
	xp=a.experience
	society.autonomy.on_arrival(source)
	var discovered: int=a.experience
	society.autonomy.on_arrival(source)
	check(discovered>xp and a.experience==discovered,"A real arrival records novelty but repeated laps do not farm XP")
	var lifetime: float=society.registry.remaining_lifetime(a.id)
	var level: int=a.level
	society.autonomy.on_combat(source,"defeated")
	check(society.registry.remaining_lifetime(a.id)==lifetime and a.level==level and society.autonomy.dialogue_line(source).contains("remember"),"Combat defeat preserves progression and changes personal memory")
	var replacements: Array=society.registry.advance_to(float(a.expires_at))
	var successor: Dictionary=society.registry.for_slot("hub/"+String(a.id))
	var legacy_id: StringName=source.profile.id
	for change: Dictionary in replacements:
		if change.old_id==a.id: society.autonomy.replace_source(change.slot,change.old_id,change.new_id)
	check(source.code_form_id==successor.id and source.profile.id==legacy_id and source.visits==0 and not source.active,"Expiration reuses one physical slot with a fresh individual and safe route IDs")
	check(not society.autonomy.states.has(a.id) and successor.memories.is_empty() and successor.level==1,"Replacement leaves old memories and scheduler history behind")
	check(Registry.validate(society.registry.serialize()).size()>0,"Autonomous memories, friendships and replacement remain valid persistent state")
	world.free()
	society.free()
	print("Code Form autonomy verification: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
