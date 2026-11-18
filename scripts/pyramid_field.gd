extends Node3D
## A visible warning becomes a bounded, floor-owned combat volume. No hidden hits.
const Neon = preload("res://scripts/neon.gd")
const Glyphs = preload("res://scripts/dungeon_glyphs.gd")
var combat: Node
var actor: CharacterBody3D
var move: Dictionary
var radius:=3.0
var delay:=.8
var age:=0.0
var next_pulse:=0.0
var pulses:=0
var alive:=true
var ink: StandardMaterial3D

func _ready() -> void:
	name="Telegraphed"+String(move.field).to_pascal_case()
	add_to_group("pyramid_fields")
	var points:=PackedVector3Array()
	for i in range(48):
		points.append_array([Vector3(cos(i*TAU/48)*radius,.03,sin(i*TAU/48)*radius),Vector3(cos((i+1)*TAU/48)*radius,.03,sin((i+1)*TAU/48)*radius)])
	for i in range(6):
		var at:=Vector3(cos(i*TAU/6)*radius*.75,.06,sin(i*TAU/6)*radius*.75)
		for path: Array in Glyphs.paths(i):
			for j in range(1,path.size()):
				for p: Vector2 in [path[j-1],path[j]]: points.append(at+Vector3(p.x*.6,0,p.y*.6))
	ink=Neon.shared_material(Color("b76aff") if move.field=="venom" else Color("4efbf4") if move.field=="flood" else Color("ffbc4d")).duplicate()
	ink.albedo_color=ink.albedo_color*.45
	add_child(Neon.lines(points,ink))
	next_pulse=delay

func reclaim() -> void:
	if not alive: return
	alive=false
	if is_instance_valid(combat): combat.fields.erase(self)
	queue_free()

func _physics_process(delta: float) -> void:
	if not alive: return
	if not is_instance_valid(actor) or actor.dead or not actor.encounter.can_fight() or not actor.encounter.same_floor(actor,actor.opponent) or combat.is_staggered():
		reclaim()
		return
	age+=delta
	if age>=delay: ink.albedo_color=Color("be65fa") if move.field=="venom" else Color("4df7ef") if move.field=="flood" else Color("ffbd48")
	var max_pulses:=4 if move.field in ["glyph","venom"] else 1
	if pulses<max_pulses and age>=next_pulse:
		var shape:=SphereShape3D.new()
		shape.radius=radius
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=shape
		query.transform.origin=global_position+Vector3.UP*.6
		query.collision_mask=6
		query.exclude=[actor.get_rid()]
		var hits: Array=actor.get_world_3d().direct_space_state.intersect_shape(query,16)
		var nearby: Array=[]
		for hit: Dictionary in hits:
			if absf(hit.collider.global_position.y-global_position.y)<1.8: nearby.append(hit)
		combat.resolve_strike(move,-1,query.transform.origin,nearby,false,true)
		pulses+=1
		next_pulse+=.85
	if pulses>=max_pulses and age>next_pulse-.55: reclaim()

func _exit_tree() -> void:
	if is_instance_valid(combat): combat.fields.erase(self)
