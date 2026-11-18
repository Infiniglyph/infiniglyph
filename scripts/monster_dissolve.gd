extends Node3D
## Bounded anime-style deconstruction. The body erodes before its last shards
## rise away; collision and loot ownership have already resolved exactly once.
const Neon = preload("res://scripts/neon.gd")
var victim: Node3D
var _clock := 0.0
var _materials: Array[ShaderMaterial] = []
var _shards: MultiMesh
var _origin := Vector3.ZERO
static var shader: Shader

func _ready() -> void:
	name = "MonsterDissolve"
	_origin = victim.global_position
	global_position = _origin
	if shader==null:
		shader = Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform vec4 ink : source_color; uniform float progress = 0.0; varying vec3 local_point; void vertex(){local_point=VERTEX;} void fragment(){float n=fract(sin(dot(floor(local_point*45.0),vec3(12.9898,78.233,37.719)))*43758.5453); if(n<progress) discard; ALBEDO=ink.rgb; EMISSION=ink.rgb*(1.0+step(n,progress+0.10)*2.0); }"
	var by_material: Dictionary = {}
	for mesh: MeshInstance3D in victim.visual.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null or mesh.mesh.get_surface_count()==0: continue
		var original: Material = mesh.material_override if mesh.material_override!=null else mesh.mesh.surface_get_material(0)
		if not by_material.has(original):
			var material := ShaderMaterial.new()
			material.shader = shader
			var ink: Color = original.albedo_color if original is StandardMaterial3D else Color("ffc65e")
			material.set_shader_parameter("ink",ink)
			by_material[original] = material
			_materials.append(material)
		mesh.material_override = by_material[original]
	var crystal := PrismMesh.new()
	crystal.size = Vector3(.035,.12,.035)
	_shards = MultiMesh.new()
	_shards.transform_format = MultiMesh.TRANSFORM_3D
	_shards.mesh = crystal
	_shards.instance_count = 40
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _shards
	instance.material_override = Neon.shared_material(Color("ffd170"))
	add_child(instance)

func _process(delta: float) -> void:
	_clock += delta
	for material in _materials: material.set_shader_parameter("progress",clampf(_clock/.65,0,1))
	for i in range(40):
		var a := i*2.399963
		var t := _clock
		var point := Vector3(cos(a)*(.12+t*.65),fmod(i*.193,1.9)+t*.9,sin(a)*(.12+t*.65))
		var basis := Basis.from_euler(Vector3(i+t*4,a,i*.3))*Basis.from_scale(Vector3.ONE*maxf(0,1-t))
		_shards.set_instance_transform(i,Transform3D(basis,point))
	if _clock>=.68 and is_instance_valid(victim):
		victim.queue_free()
		victim = null
	if _clock>=1: queue_free()
