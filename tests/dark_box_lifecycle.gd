extends SceneTree
## Exercise patrol state transitions without loading an entire city fixture.
const Patrols = preload("res://scripts/dark_box_patrols.gd")
class Registry:
	extends RefCounted
	var records := {"officer_a":{"active":true}}
class Organizations:
	extends RefCounted
	func is_member(_id: String,_guild: String) -> bool: return true
class Autonomy:
	extends RefCounted
	var _regional_records: Dictionary = {}
	var _sources: Dictionary = {}
class Civilization:
	extends Node
	var world_seconds := 100.0
	var registry: RefCounted
	var autonomy: RefCounted
class Quests:
	extends Node
	var organizations: RefCounted
class Session:
	extends Node
	var _loading := false
	var _checkpoint_pending := false
	func _dirty() -> void: pass
class Law:
	extends Node
	signal case_recorded(row: Dictionary)
	func wanted_level(_id: String) -> int: return 0
class Player:
	extends CharacterBody3D
	signal defeated
	signal respawned
	var health := 100.0
class Life:
	extends Node3D
	var vehicles: Dictionary = {}
	var vehicle_records: Array = []
class Vehicle:
	extends CharacterBody3D
	var has_driver := false
	var player_driver: Node
	var health := 1000.0
	var patrol := true
	var _blocked := false
	var record: Dictionary = {}
	func set_npc_driving(_boost: bool,_trail: bool = false) -> void: pass
	func clear_patrol() -> void: patrol=false
class World:
	extends Node3D
	var civilization: Node
	var inventory_session: Node
	var law: Node
	var player: CharacterBody3D
	var district_life: Node3D
	var quest_system: Node
	var dungeon_travel: Node
	var theft_reactions: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func run() -> void:
	var world := World.new()
	world.civilization = Civilization.new()
	world.civilization.registry = Registry.new()
	world.civilization.autonomy = Autonomy.new()
	world.quest_system = Quests.new()
	world.quest_system.organizations = Organizations.new()
	world.inventory_session = Session.new()
	world.law = Law.new()
	world.player = Player.new()
	world.district_life = Life.new()
	root.add_child(world)
	for child: Node in [world.civilization,world.quest_system,world.inventory_session,world.law,world.player,world.district_life]: world.add_child(child)
	var vehicle := Vehicle.new()
	vehicle.record = {"id":7,"kind":"motorcycle","driver":{"code_form_id":"officer_a"},"traffic":true,"taken":false,"route":PackedVector3Array([Vector3.ZERO,Vector3(0,0,200)]),"cursor":1}
	world.district_life.add_child(vehicle)
	world.district_life.vehicles[7] = vehicle
	world.district_life.vehicle_records.append(vehicle.record)
	var patrol := Patrols.new()
	patrol.world = world
	world.add_child(patrol)
	patrol.set_physics_process(false)
	patrol.ready_for_patrols = true
	patrol.units[7] = {"members":["officer_a"],"deployed":true,"route":vehicle.record.route.duplicate(),"record":vehicle.record,"last_seen":0.0}
	patrol._reserved["officer_a"] = 7
	patrol.defeated_until["officer_a"] = 200.0
	patrol.issued["officer_a"] = "issued_arc_wand"
	patrol._physics_process(.6)
	check(not patrol.units[7].deployed and not vehicle.has_driver,"A defeated officer's empty unit waits out its recovery cooldown")
	world.civilization.world_seconds = 201.0
	patrol._physics_process(.6)
	check(vehicle.has_driver,"A recovered crew resumes driving instead of leaving its patrol permanently unmanned")
	# A checkpoint can be loaded during a mounted-to-foot deployment. Clearing
	# its transient bodies must leave a usable physical vehicle behind.
	patrol.units[7].deployed = true
	vehicle.has_driver = false
	var saved := patrol.serialize()
	check(patrol.restore(saved),"A deployed patrol's persistent issue/cooldown state restores")
	check(vehicle.has_driver,"Restoring deployed units returns their living crew to the physical vehicle")
	world.free()
	print("DARK BOX LIFECYCLE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
