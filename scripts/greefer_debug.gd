extends Node3D
## Optional developer view. Draws the same capsules used by live contacts.
const Neon = preload("res://scripts/neon.gd")
const Moves = preload("res://scripts/greefer_moves.gd")
var caption: Label3D
var lines: MeshInstance3D
var mesh := ImmediateMesh.new()
var material: Material

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	material = Neon.material(Color(1,0.85,0.1))
	lines = MeshInstance3D.new()
	lines.mesh = mesh
	add_child(lines)
	caption = Label3D.new()
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size = 32
	caption.pixel_size = 0.007
	caption.modulate = Color(1,0.85,0.1)
	add_child(caption)

func update(actor: CharacterBody3D, move: Dictionary, time: float) -> void:
	caption.global_position = actor.global_position+Vector3.UP*4
	caption.text = (move.name if not move.is_empty() else String(actor.state))+" / "+actor.visual.attack_phase(move,time)
	mesh.clear_surfaces()
	if move.is_empty(): return
	var segments: Array = []
	for pulse in range(move.hits.size()):
		var window := Moves.window(move,pulse)
		if time>=window.x and time<=window.y: segments.append_array(actor.visual.attack_segments(move,pulse))
	if segments.is_empty(): return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for segment: Dictionary in segments:
		var up: Vector3 = (segment.b-segment.a).normalized()
		var right := up.cross(Vector3.UP if absf(up.y)<0.95 else Vector3.RIGHT).normalized()
		var forward := right.cross(up)
		for i in range(12):
			var angle := i*TAU/12
			var next := (i+1)*TAU/12
			var a: Vector3 = (right*cos(angle)+forward*sin(angle))*float(segment.radius)
			var b: Vector3 = (right*cos(next)+forward*sin(next))*float(segment.radius)
			for end: Vector3 in [segment.a,segment.b]:
				mesh.surface_add_vertex(end+a)
				mesh.surface_add_vertex(end+b)
			mesh.surface_add_vertex(segment.a+a)
			mesh.surface_add_vertex(segment.b+a)
			# Capsule hemispheres, not a larger decorative attack area.
			for end: Vector3 in [segment.a,segment.b]:
				var sign_value := -1.0 if end == segment.a else 1.0
				mesh.surface_add_vertex(end+a)
				mesh.surface_add_vertex(end+up*sign_value*float(segment.radius))
	mesh.surface_end()
