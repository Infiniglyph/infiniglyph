extends Node3D
## Short-lived cyan phase rings. Orange remains reserved for actual lights.
const Neon = preload("res://scripts/neon.gd")
const LIFETIME := 0.28
var materializing := false
var color := Color(0.16,0.9,1.0)
var age := 0.0
var ink: StandardMaterial3D

func _ready() -> void:
	name = "PhaseArrival" if materializing else "PhaseDeparture"
	add_to_group("phase_traces")
	ink = Neon.material(color)
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for ring_index in range(3):
		var radius := 0.34+ring_index*0.18
		var points := PackedVector3Array()
		for i in range(24):
			var a := i*TAU/24
			var b := (i+1)*TAU/24
			points.append_array([Vector3(cos(a)*radius,(ring_index-1)*0.42,sin(a)*radius),Vector3(cos(b)*radius,(ring_index-1)*0.42,sin(b)*radius)])
		add_child(Neon.lines(points,ink))
	scale = Vector3.ONE*(0.12 if materializing else 1.0)

func _process(delta: float) -> void:
	age += delta
	var progress := clampf(age/LIFETIME,0,1)
	var curve := 1-pow(1-progress,3) if materializing else pow(progress,3)
	scale = Vector3.ONE*lerpf(0.12 if materializing else 1.0,1.2 if materializing else 0.08,curve)
	ink.albedo_color.a = 1-progress
	if age >= LIFETIME: queue_free()
