extends "res://tests/code_form_autonomy.gd"
class Civic extends Node:
	var calls: Array=[]
	var arrivals: Array=[]
	var conversations: Array=[]
	var succeed:=true
	var preferred:="place/north_w"
	func npc_step(record: Dictionary,_state: Dictionary,physical: bool) -> bool:
		calls.append([record.id,record.current_goal,physical])
		return succeed
	func preferred_destination(_id: String) -> String: return preferred
	func arrived(id: String,target: String) -> void: arrivals.append([id,target])
	func socialize(a: String,b: String,physical: bool) -> bool:
		conversations.append([a,b,physical]); return true
class CivicWorld extends TestWorld:
	var civic_interactions: Node
func run() -> void:
	var society:=Society.new(); root.add_child(society)
	var ledger:=Ledger.new(); society.add_child(ledger); society.economy=ledger; society.autonomy.civilization=society
	var rows: Array[Dictionary]=[row("civilian0"),row("civilian1")]
	check(society.registry.bootstrap(rows),"Civic hook fixture starts from real civilian identities")
	var world:=CivicWorld.new(); root.add_child(world); society.world=world
	var civic:=Civic.new(); world.add_child(civic); world.civic_interactions=civic
	var record: Dictionary=society.registry.records.civilian0
	var peer: Dictionary=society.registry.records.civilian1
	var state: Dictionary=society.autonomy._state(record.id)
	for goal: String in ["work","guild","explore","socialize","trade"]:
		society.registry.set_goal(record.id,goal)
		var before: int=state.actions
		check(society.autonomy.perform_action(record,state,false) and civic.calls[-1][1]==goal and state.actions==before+1,"Structured civic "+goal+" runs once with one successful action count")
	check(ledger.transfers==0 and record.guild.is_empty(),"A successful civic job prevents duplicate legacy wages or fake guild membership")
	civic.succeed=false
	society.registry.set_goal(record.id,"work")
	check(society.autonomy.perform_action(record,state,false) and ledger.transfers==1,"Unavailable civic opportunities preserve funded legacy work fallback")
	society.registry.set_goal(record.id,"guild")
	check(not society.autonomy.perform_action(record,state,false) and record.guild.is_empty(),"An attached civic authority never falls back to an unregistered affiliation")
	var friendship: Dictionary=record.relationships.duplicate()
	society.autonomy._social(record,peer,false)
	check(civic.conversations.size()==1 and not civic.conversations[-1][2] and record.relationships==friendship,"Unloaded social activity uses one structured conversation without duplicate relationship effects")
	var population:=Population.new(); world.add_child(population); world.population=population
	population.player=CharacterBody3D.new(); world.add_child(population.player)
	var source:=Resident.new(); source.profile=Profiles.all(2)[0].duplicate(true)
	source.profile.id=StringName(record.id); source.profile.name=record.name; source.profile.serial=0; source.profile.color_name="cyan"; source.profile.tint=Color.CYAN; source.population=population
	population.add_child(source); population.residents.append(source); population.by_id[source.profile.id]=source
	society.autonomy.bind_sources(); source.active=true; source.transit=&"outdoor"; source.goal=&"west_court"
	society.registry.set_goal(record.id,"explore")
	check(society.autonomy.choose_destination(source)==&"north_w","A funded objective is favored among existing reachable city destinations")
	civic.preferred="place/unreachable"
	check(society.autonomy.choose_destination(source) in [&"west_garden",&"north_w"],"A distant unknown objective cannot invent a route through geometry")
	civic.preferred="place/north_w"
	state.next_action=1e9; source.goal=&"north_w"
	society.autonomy.on_arrival(source)
	check(civic.arrivals.has([record.id,"place/north_w"]),"Actual arrivals submit quest proof even while ordinary action cooldown is active")
	source.indoor_left=INF
	var calls: int=civic.calls.size()
	check(not society.autonomy.perform_action(record,state,true) and civic.calls.size()==calls,"Suspended or combat-held inhabitants cannot run hidden civic transactions")
	check(state.size()==6 and not Autonomy.validate(society.autonomy.serialize(),society.registry.active_ids()).is_empty(),"Civic hooks preserve the existing strict six-field scheduler checkpoint")
	world.free(); society.free()
	print("CIVIC AUTONOMY: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
