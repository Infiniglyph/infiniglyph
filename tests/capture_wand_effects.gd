extends SceneTree
## Five actual effect meshes sampled in a neutral native-rendered arena.
const Effect = preload("res://scripts/wand_effect.gd")
const Moves = preload("res://scripts/wand_moves.gd")
const Lines = preload("res://scripts/robe_lines.gd")
class Caster:
	extends CharacterBody3D
	var transition_locked := false
	func can_attack_target(_target: Node) -> bool: return true
class Receiver:
	extends Node
	var health := 100.0
	signal environment_contact(collider: Node3D, attack_serial: int)
	func resolve_strike(_move: Dictionary,_pulse: int,_origin: Vector3,_candidates: Array,_first: bool,_projectile: bool) -> void: pass
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var caster := Caster.new()
	stage.add_child(caster)
	caster.position = Vector3(-20,0,0)
	var combat := Receiver.new()
	stage.add_child(combat)
	var floor := StaticBody3D.new()
	stage.add_child(floor)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30,.1,20)
	collider.shape = shape
	collider.position = Vector3(0,-.05,4)
	floor.add_child(collider)
	stage.add_child(Lines.grid(24,16,2,Color("073b48")))
	for i in range(2): await physics_frame
	var names := ["LASER FLICK","SLITHER SHOT","LASER VOLLEY","GROUND CAST","LASER WHEEL"]
	var actions: Array[StringName] = [&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
	for i in range(5):
		var move := Moves.move({"id":"capture_wand"},actions[i])
		var effect := Effect.new()
		effect.configure(caster,combat,move,Vector3((i-2)*4.6,1,0),Vector3.BACK,Color("75eaff"))
		stage.add_child(effect)
		effect.set_physics_process(false)
		for frame in range(4 if i==0 else 12 if i in [1,4] else 8 if i==2 else 25): effect._physics_process(1.0/60)
		var title := Label3D.new()
		title.text = names[i]
		title.font_size = 48
		title.pixel_size = .008
		title.modulate = Color("75eaff")
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stage.add_child(title)
		title.position = Vector3((i-2)*4.6,.15,8.8)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.5
	camera.position = Vector3(0,11,17)
	camera.look_at(Vector3(0,.6,3.5))
	camera.current = true
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/wand_effects.png")
	print("CAPTURE wand_effects: five actual effect meshes")
	quit()
