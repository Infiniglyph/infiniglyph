extends SceneTree
const Bubble=preload("res://scripts/code_form_activity.gd")
const Registry=preload("res://scripts/code_form_registry.gd")
class Traveler extends Node:
	const OUTSIDE=&"overworld"
	var active_location:=OUTSIDE
class World extends Node3D:
	var player: CharacterBody3D
	var civilization: Node
	var code_form_activity: Node
	var dungeon_travel: Node
	var world_actions: Node
class Society extends Node:
	var registry=Registry.new()
	var world: Node3D
	var ready_for_simulation:=true
	var autonomy: RefCounted
class Sleeper extends Node3D:
	var active:=false
class Agent extends "res://scripts/code_form_autonomy.gd":
	var points: Dictionary={}
	func simulation_position(id: String) -> Vector3: return points.get(id,Vector3(1000,0,0))
	func choose_goal(_record: Dictionary,_state: Dictionary) -> String: return "rest"
	func perform_action(_record: Dictionary,_state: Dictionary,_physical: bool) -> bool: completed_actions+=1; return true
	func _unavailable(_id: String,_source: Node=null) -> bool: return false
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run() -> void:
	check(Bubble.predictive_distance_squared(Vector3(0,300,0),Vector3.ZERO,Vector3.ZERO)==90000,"The bubble measures height rather than an infinite horizontal cylinder")
	check(Bubble.predictive_distance_squared(Vector3(200,0,0),Vector3.ZERO,Vector3(100,0,0))<128*128,"Fast driving anticipates people ahead before they enter the current sphere")
	check(Bubble.predictive_distance_squared(Vector3(0,-200,0),Vector3.ZERO,Vector3(0,-100,0))<128*128,"Falling receives the same three-dimensional look-ahead")
	check(Bubble.predictive_distance_squared(Vector3(0,300,0),Vector3.ZERO,Vector3(100,0,0))==90000,"Horizontal speed cannot activate the entire city hundreds of metres below a Sky Jump")
	var world:=World.new(); root.add_child(world)
	world.player=CharacterBody3D.new(); world.add_child(world.player)
	world.dungeon_travel=Traveler.new(); world.add_child(world.dungeon_travel)
	var society:=Society.new(); society.world=world; world.civilization=society; world.add_child(society)
	var agent:=Agent.new(); agent.civilization=society; society.autonomy=agent
	var rows: Array[Dictionary]=[]
	for i in range(100):
		var id:="region/"+str(i)
		rows.append({"id":id,"slot":id,"name":id,"occupation":"resident","personality":"curious","respawn":{"location":"overworld","position":[0.0,0.0,0.0],"yaw":0.0}})
		if i<3: agent.points[id]=Vector3(i,0,0)
	society.registry.bootstrap(rows)
	var original_agent=preload("res://scripts/code_form_autonomy.gd").new()
	original_agent.civilization=society
	var sleeper:=Sleeper.new(); world.add_child(sleeper)
	original_agent._sources["region/99"]=weakref(sleeper)
	society.registry.records["region/99"].respawn.position=[900.0,0.0,0.0]
	check(original_agent.simulation_position("region/99")==Vector3(900,0,0),"A dormant body's origin transform cannot activate a distant resident's AI")
	sleeper.active=true
	check(original_agent.simulation_position("region/99")==Vector3.ZERO,"An active body's actual position takes precedence over its old home")
	var bubble:=Bubble.new(); bubble.world=world; world.code_form_activity=bubble; world.add_child(bubble); bubble.set_process(false)
	bubble.refresh(true)
	check(bubble.local_ids.size()==3 and bubble.contains(Vector3(127,0,0)) and not bubble.contains(Vector3(0,161,0)),"Only nearby identities enter the full-detail set")
	agent.process_batch(1)
	check(agent.last_local_steps==3 and agent.last_background_steps==2 and agent.states.size()==5,"Near citizens get frequent turns and distant full decisions have a fixed two-turn budget")
	for i in range(60): society.registry.world_seconds+=24; agent.process_batch(1)
	check(agent.states.size()==100 and agent.cursor<100,"Round-robin background work eventually reaches every persistent identity")
	agent.points["region/99"]=Vector3(180,0,0); bubble.refresh(true)
	var rebuilt: int=bubble.index_rebuilds
	agent.points["region/99"]=Vector3(150,0,0); bubble._clock=0; bubble.refresh()
	check(bubble.is_local("region/99") and bubble.index_rebuilds==rebuilt,"A local cell query observes moving records without rebuilding the full census")
	agent.points.erase("region/99"); bubble.refresh(true)
	world.player.position=Vector3(1000,0,0); bubble.refresh()
	check(bubble.local_ids.size()==97 and not bubble.is_local("region/0"),"A teleport refreshes the bubble immediately instead of waiting for a clock interval")
	world.dungeon_travel.active_location=&"pyramid"; bubble.refresh()
	check(bubble.local_ids.is_empty() and not bubble.contains(Vector3(1000,0,0)),"Overlapping instance coordinates cannot activate the outdoor population")
	agent.process_batch(1)
	check(agent.last_local_steps==0 and agent.last_background_steps==2,"An interior keeps only the bounded outdoor background simulation")
	agent.process_batch(1,true)
	check(agent.last_background_steps==12,"Explicit offline catch-up still performs its bounded complete census pass")
	world.dungeon_travel.active_location=world.dungeon_travel.OUTSIDE
	bubble.enabled=false; agent.process_batch(1)
	check(agent.last_background_steps==12 and bubble.contains(Vector3(1e6,1e6,1e6)),"Disabling the bubble restores the existing scheduling and range behavior")
	check(not agent.serialize().has("local_ids") and not Registry.validate(society.registry.serialize()).is_empty(),"Activity indexes remain transient without changing persistent citizen state")
	world.queue_free(); await process_frame
	print("Code Form activity: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
