extends Node3D
## Enemy-only physical arrow. No homing, instant hits or player bow class.
const Neon = preload("res://scripts/neon.gd")
const Glyphs = preload("res://scripts/dungeon_glyphs.gd")
var glyph:=false
var venom:=false
var speed:=16.0
var max_life:=1.25
var visual_scale:=1.0
var combat: Node
var actor: CharacterBody3D
var move: Dictionary
var direction := Vector3.FORWARD
var age := 0.0
var alive := true
var _shape:=CapsuleShape3D.new()
var _query:=PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	name="SentinelArrow"
	var points:=PackedVector3Array([Vector3(0,0,-.55),Vector3(0,0,.12),Vector3(-.09,0,-.04),Vector3(0,0,.14),Vector3(.09,0,-.04),Vector3(0,0,.14)])
	if glyph:
		points.clear()
		for path: Array in Glyphs.paths(3 if venom else 0):
			for i in range(1,path.size()):
				for p: Vector2 in [path[i-1],path[i]]: points.append(Vector3(p.x,p.y,0)*.48)
	var strokes:=Neon.lines(points,Neon.shared_material(Color("bb66ff") if venom else Color("ffe09a")))
	strokes.scale=Vector3.ONE*visual_scale
	add_child(strokes)
	basis=Basis(Quaternion(Vector3.BACK,direction))
	_shape.radius=.10
	_query.shape=_shape
	_query.collision_mask=6
	_query.exclude=[actor.get_rid()]

func reclaim() -> void:
	if not alive: return
	alive=false
	if is_instance_valid(combat): combat.arrows.erase(self)
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(combat): combat.arrows.erase(self)

func _physics_process(delta: float) -> void:
	if not alive: return
	if not is_instance_valid(actor) or actor.dead or not actor.encounter.can_fight() or actor.weapon_combat.is_staggered() or not actor.encounter.same_floor(actor,actor.opponent):
		reclaim()
		return
	age+=delta
	if age>max_life:
		reclaim()
		return
	var previous:=global_position
	var next:=previous+direction*speed*delta
	var space:=get_world_3d().direct_space_state
	# The player also carries the world's physical-body layer. Its capsule is
	# resolved below as a fighter, never mistaken for architecture at low Hz.
	var wall:=space.intersect_ray(PhysicsRayQueryParameters3D.create(previous,next,9,[actor.get_rid(),actor.opponent.get_rid()]))
	if not wall.is_empty():
		reclaim()
		return
	_shape.height=maxf(.20,previous.distance_to(next)+.20)
	_query.transform=Transform3D(Basis(Quaternion(Vector3.UP,direction)),(previous+next)*.5)
	for hit: Dictionary in space.intersect_shape(_query,8):
		if hit.collider!=actor.opponent: continue
		hit.contact=(previous+next)*.5
		combat.resolve_strike(move,-1,previous,[hit],false,true)
		reclaim()
		return
	global_position=next
