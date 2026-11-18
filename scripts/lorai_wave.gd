extends Node3D
## A real expanding annulus. Crossing it above knee height avoids the ground hit.
const Neon = preload("res://scripts/neon.gd")
var actor: CharacterBody3D
var combat: Node
var move: Dictionary
var age:=0.0
var alive:=true
var radius:=1.0
var ring: Node3D
var contacted:=false

func _ready() -> void:
	add_to_group("pyramid_fields")
	var points:=PackedVector3Array()
	for i in range(64): points.append_array([Vector3(cos(i*TAU/64),0,sin(i*TAU/64)),Vector3(cos((i+1)*TAU/64),0,sin((i+1)*TAU/64))])
	ring=Neon.lines(points,Neon.shared_material(Color("ffd452")))
	add_child(ring)

func reclaim() -> void:
	if not alive: return
	alive=false
	if is_instance_valid(combat): combat.fields.erase(self)
	queue_free()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or actor.dead or actor.phase==0 or combat.is_staggered() or not actor.encounter.can_fight() or not actor.encounter.same_floor(actor,actor.opponent):
		reclaim()
		return
	var before:=radius
	age+=delta
	radius=1+age*12
	ring.scale=Vector3(radius,1,radius)
	var foe: CharacterBody3D=actor.opponent
	var distance:=Vector2(foe.global_position.x-global_position.x,foe.global_position.z-global_position.z).length()
	if not contacted and distance>=before-.7 and distance<=radius+.7 and foe.global_position.y<global_position.y+1.15:
		contacted=true
		combat.resolve_strike(move,-1,global_position+Vector3.UP*.4,[{"collider":foe,"rid":foe.get_rid(),"shape":0}],false,true)
	if radius>24: reclaim()
