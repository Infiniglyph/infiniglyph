extends Node3D
## Bounded, short-lived glyph strokes. These are attack presentation, not platforms.
const Neon = preload("res://scripts/neon.gd")
var profile := "sweep"
var radius := 2.0
var arc := 120.0
var color := Color.CYAN
var age := 0.0
var lifetime := 0.42
var ink: StandardMaterial3D

func _ready() -> void:
	name = "WeaponGlyph"
	add_to_group("weapon_effects")
	ink = Neon.material(color)
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var points := PackedVector3Array()
	match profile:
		"parry":
			for i in range(8):
				var a := i*TAU/8
				var b := (i+1)*TAU/8
				var ray := Vector3(cos(a),sin(a),0)
				points.append_array([ray*radius*0.55,Vector3(cos(b),sin(b),0)*radius*0.55,ray*radius*0.8,ray*radius*1.4])
			points.append_array([Vector3(-radius,-radius,0),Vector3(radius,radius,0),Vector3(-radius,radius,0),Vector3(radius,-radius,0)])
		"beam","spiral","comets":
			for lane in range(2):
				for i in range(32):
					var a := i/32.0
					var b := (i+1)/32.0
					var amplitude := 0.12 if profile == "beam" else 0.28
					points.append_array([Vector3(cos(a*TAU*3+lane*PI)*amplitude,sin(a*TAU*3+lane*PI)*amplitude,a*radius),Vector3(cos(b*TAU*3+lane*PI)*amplitude,sin(b*TAU*3+lane*PI)*amplitude,b*radius)])
			points.append_array([Vector3.ZERO,Vector3(0,0,radius)])
		"rain":
			for i in range(5):
				var angle := (i-2)*0.23
				var tip := Vector3(sin(angle)*radius*0.7,-0.7,cos(angle)*radius*0.65)
				points.append_array([tip+Vector3.UP*2.6,tip,tip,tip+Vector3(-0.15,0.4,0),tip,tip+Vector3(0.15,0.4,0)])
		"lattice":
			for row in range(3):
				for column in range(-2,3):
					var center := Vector3(column*0.44,(row-1)*0.35,0.7+row*radius/3)
					points.append_array([center+Vector3(-0.3,-0.25,-0.12),center+Vector3(0.3,0.25,0.12),center+Vector3(-0.3,0.25,0.12),center+Vector3(0.3,-0.25,-0.12)])
		"pillar":
			for i in range(3):
				var center := Vector3((i-1)*0.55,0,radius*0.55)
				points.append_array([center+Vector3(-0.28,-0.6,0),center+Vector3(0.28,1.4,0),center+Vector3(0.28,-0.6,0),center+Vector3(-0.28,1.4,0)])
		_:
			var full := profile in ["orbit","aegis","slam"]
			var angle_range := TAU if full else deg_to_rad(arc)
			var bands := 3 if profile in ["aegis","cross","waltz"] else 2
			for band in range(bands):
				for i in range(36):
					var a := -angle_range*0.5+i*angle_range/36
					var b := -angle_range*0.5+(i+1)*angle_range/36
					var height := (band-1)*0.28
					var r := radius*(0.78+band*0.10)
					var va := Vector3(sin(a)*r,height+sin(a)*0.22,cos(a)*r)
					var vb := Vector3(sin(b)*r,height+sin(b)*0.22,cos(b)*r)
					if profile == "cross":
						va.y += va.x*(0.65 if band%2 == 0 else -0.65)
						vb.y += vb.x*(0.65 if band%2 == 0 else -0.65)
					if profile == "slam":
						va.y = -0.82
						vb.y = -0.82
					points.append_array([va,vb])
			if profile in ["slam","aegis"]:
				for i in range(8):
					var direction := Vector3(sin(i*TAU/8),0,cos(i*TAU/8))
					points.append_array([direction*0.3+Vector3.DOWN*0.75,direction*radius+Vector3.DOWN*0.75])
			if profile == "waltz":
				for i in range(3):
					var c := Vector3((i-1)*0.65,0,0.5+i*0.6)
					points.append_array([c+Vector3(0,-0.7,0),c+Vector3(0,0.55,0),c+Vector3(-0.3,0.1,0),c+Vector3(0.45,0.6,0.4)])
	add_child(Neon.lines(points,ink))
	scale = Vector3.ONE*0.8

func _process(delta: float) -> void:
	age += delta
	var progress := clampf(age/lifetime,0,1)
	ink.albedo_color.a = pow(1-progress,1.3)
	scale = Vector3.ONE*lerpf(0.8,1.08,progress)
	if profile == "orbit": rotation.y = progress*0.7
	if profile == "rain": position.y -= delta*1.1
	if progress >= 1: queue_free()
