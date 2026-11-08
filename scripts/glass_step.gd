extends Node3D
## A transient visual foothold: translucent planar facets, circuit marks and
## cyan fracture edges. No collider, particles, textures, or lingering platform.
const Neon = preload("res://scripts/neon.gd")
const LIFETIME := 0.62
var impulse := Vector3.UP*7.5
var response_strength := 1.0
var age := 0.0
var shards: Array[Node3D] = []
var directions: Array[Vector3] = []
var edge: StandardMaterial3D
var fill: StandardMaterial3D

func _ready() -> void:
	name = "DigitalGlassStep"
	add_to_group("digital_glass_steps")
	response_strength = clampf(impulse.length()/7.5,0.5,2.0)
	scale = Vector3.ONE*sqrt(response_strength)
	edge = Neon.material(Color(0.45,0.98,1,1))
	edge.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill = Neon.material(Color(0.05,0.7,0.8,0.16))
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim: Array[Vector3] = [Vector3(-0.46,0,-0.32),Vector3(0,0,-0.32),Vector3(0.46,0,-0.32),Vector3(0.46,0,0),Vector3(0.46,0,0.32),Vector3(0,0,0.32),Vector3(-0.46,0,0.32),Vector3(-0.46,0,0)]
	for i in range(8):
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i+1)%8]
		var shard := Node3D.new()
		add_child(shard)
		shards.append(shard)
		directions.append((a+b).normalized())
		var face := ImmediateMesh.new()
		face.surface_begin(Mesh.PRIMITIVE_TRIANGLES,fill)
		for p in [Vector3.ZERO,b,a]:
			face.surface_set_normal(Vector3.UP)
			face.surface_add_vertex(p)
		face.surface_end()
		var visual := MeshInstance3D.new()
		visual.mesh = face
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.add_child(visual)
		shard.add_child(Neon.lines(PackedVector3Array([Vector3.ZERO,a,a,b,b,Vector3.ZERO]),edge))
	# Rectilinear circuit etchings distinguish it from an air-pressure ring.
	var traces := PackedVector3Array([Vector3(-0.3,0.003,-0.1),Vector3(-0.08,0.003,-0.1),Vector3(-0.08,0.003,-0.1),Vector3(-0.08,0.003,0.16),Vector3(0.08,0.003,-0.17),Vector3(0.3,0.003,-0.17),Vector3(0.3,0.003,-0.17),Vector3(0.3,0.003,0.1)])
	add_child(Neon.lines(traces,edge))

func _process(delta: float) -> void:
	age += delta
	var fracture := maxf(0,age-0.10)*sqrt(response_strength)
	var opacity := pow(maxf(0,1-age/LIFETIME),1.4)
	edge.albedo_color.a = opacity
	fill.albedo_color.a = opacity*0.16
	for i in range(shards.size()):
		shards[i].position = directions[i]*(fracture*0.32+fracture*fracture*0.4)+Vector3.DOWN*fracture*fracture*0.7
		shards[i].rotation = Vector3(fracture*(0.7 if i%2 else -0.7),fracture*0.2,fracture*(0.4 if i%3 else -0.4))
	if age >= LIFETIME: queue_free()
