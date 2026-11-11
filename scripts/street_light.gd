extends Node3D
## Local -Z points toward the avenue. Every fixture part is a solid orange box.
const Neon = preload("res://scripts/neon.gd")
var light: SpotLight3D

func _ready() -> void:
	name = "OrangeStreetLight"
	add_to_group("street_lights")
	var orange := Neon.shared_material(Neon.ORANGE)
	Neon.block(self, Vector3(0,0.12,0), Vector3(0.65,0.24,0.65), orange)
	Neon.block(self, Vector3(0,2.95,0), Vector3(0.16,5.5,0.16), orange)
	Neon.block(self, Vector3(0,5.68,-1), Vector3(0.16,0.16,2.16), orange)
	Neon.block(self, Vector3(0,5.64,-2), Vector3(0.8,0.24,0.6), orange)
	Neon.block(self, Vector3(0,5.511,-2), Vector3(0.64,0.018,0.44), orange, orange)
	light = SpotLight3D.new()
	light.name = "OrangeLight"
	light.position = Vector3(0,5.48,-2)
	light.rotation.x = -PI*0.5
	light.light_color = Neon.ORANGE
	light.light_energy = 12.0
	light.light_specular = 0.0
	light.spot_range = 13.0
	light.spot_angle = 55.0
	light.spot_attenuation = 0.65
	light.shadow_enabled = true
	light.shadow_normal_bias = 0.15
	add_child(light)
