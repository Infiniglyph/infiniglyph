extends SceneTree
const Establishments=preload("res://scripts/civilian_establishments.gd")
class Walker extends CharacterBody3D:
	var direction:=Vector3.ZERO
	func _ready() -> void:
		floor_snap_length=.35
		var shape:=CapsuleShape3D.new(); shape.height=1.85; shape.radius=.28
		var collider:=CollisionShape3D.new(); collider.shape=shape; collider.position.y=.95; add_child(collider)
	func _physics_process(delta: float) -> void:
		velocity.x=direction.x*8; velocity.z=direction.z*8
		if not is_on_floor(): velocity.y-=22*delta
		else: velocity.y=0
		move_and_slide()
var failures:=0
var checks:=0
func _initialize() -> void: Engine.physics_ticks_per_second=60; call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=2) -> void:
	for i in range(count): await physics_frame; await process_frame
func walk(actor: Walker,at: Vector3) -> bool:
	for i in range(600):
		var delta:=at-actor.global_position; delta.y=0
		if delta.length()<.18: actor.direction=Vector3.ZERO; return actor.is_on_floor()
		actor.direction=delta.normalized(); await frames(1)
	return false
func run() -> void:
	var scene:=Node3D.new(); root.add_child(scene)
	var buildings:=Establishments.new(); scene.add_child(buildings)
	var actor:=Walker.new(); scene.add_child(actor)
	actor.global_position=buildings.guild.to_global(Vector3(-16.8,.18,12))
	await frames(20)
	check(buildings.faction_boards.size()==3 and not buildings.faction_boards.has("underworld"),"Exactly the three public guilds expose physical boards; Underworld has none")
	var ids: Dictionary={}
	for point: Dictionary in buildings.points:
		if point.kind==&"board": ids[String(point.id)]=point.get("faction","")
	check(ids=={"board_security":"security","board_commerce":"commerce","board_exploration":"exploration"},"Each physical board exposes its unique faction context to the shared service UI")
	for faction: String in ["exploration","commerce","security"]:
		var anchor: Marker3D=buildings.faction_boards[faction]
		var target:=anchor.global_position; target.y=Establishments.GROUND+.05
		check(await walk(actor,target),"Standing capsule reaches "+faction+" board along the public aisle")
	check(buildings.guild.get_node("GuildBatch").find_children("*","MeshInstance3D",true,false).size()==1,"Three boards remain in the existing single architecture batch")
	check(not paused,"Public board interactions leave the world running")
	scene.free()
	print("Faction boards: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
