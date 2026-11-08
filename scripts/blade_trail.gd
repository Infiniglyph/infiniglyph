extends MeshInstance3D
const Neon = preload("res://scripts/neon.gd")
var samples: Array[Dictionary] = []
var ink: StandardMaterial3D
var trail_mesh := ImmediateMesh.new()

func _ready() -> void:
	name = "BladeTrail"
	mesh = trail_mesh
	ink = Neon.material(Color(0.5,0.9,1,0.7))
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update(delta: float, segments: Array, color: Color) -> void:
	for sample in samples: sample.age += delta
	samples = samples.filter(func(sample: Dictionary) -> bool: return sample.age < 0.18)
	for blade in range(segments.size()):
		var segment: Dictionary = segments[blade]
		samples.append({"a":segment.a,"b":segment.b,"age":0.0,"blade":blade})
	while samples.size() > 20: samples.pop_front()
	trail_mesh.clear_surfaces()
	if samples.size() < 2: return
	ink.albedo_color = color
	ink.albedo_color.a = 0.65
	trail_mesh.surface_begin(Mesh.PRIMITIVE_LINES,ink)
	var previous: Dictionary = {}
	for sample: Dictionary in samples:
		if previous.has(sample.blade):
			trail_mesh.surface_add_vertex(previous[sample.blade])
			trail_mesh.surface_add_vertex(sample.b)
		trail_mesh.surface_add_vertex(sample.a)
		trail_mesh.surface_add_vertex(sample.b)
		previous[sample.blade] = sample.b
	trail_mesh.surface_end()
