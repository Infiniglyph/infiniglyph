extends SceneTree
const Visual=preload("res://scripts/resident_visual.gd")
const Presence=preload("res://scripts/code_form_presence.gd")
const Neon=preload("res://scripts/neon.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1100,700)
	var scene:=Node3D.new(); root.add_child(scene)
	var camera:=Camera3D.new(); scene.add_child(camera)
	camera.position=Vector3(3.6,2.8,7.8); camera.look_at(Vector3(0,1.1,0)); camera.current=true
	var viewer:=CharacterBody3D.new(); scene.add_child(viewer); viewer.position=Vector3(0,0,80)
	var lines:=ImmediateMesh.new(); lines.surface_begin(Mesh.PRIMITIVE_LINES,Neon.material(Color(.015,.11,.14)))
	for i in range(-6,7):
		lines.surface_add_vertex(Vector3(i,0,-6)); lines.surface_add_vertex(Vector3(i,0,6))
		lines.surface_add_vertex(Vector3(-6,0,i)); lines.surface_add_vertex(Vector3(6,0,i))
	lines.surface_end()
	var grid:=MeshInstance3D.new(); grid.mesh=lines; scene.add_child(grid)
	for i in range(3):
		var actor:=Node3D.new(); scene.add_child(actor); actor.position.x=(i-1)*2.0
		var figure:=Visual.new(); figure.tint=Color(.12,.82,.9); actor.add_child(figure)
		var presence:=Presence.new(); presence.actor=actor; presence.viewer=viewer; presence.figure=figure; actor.add_child(presence)
		presence.refresh(); presence._process([.15,.32,.6][i]); presence.set_process(false)
		var label:=Label3D.new(); label.text=["RECONSTRUCTING","ASSEMBLING","PRESENT"][i]; label.position.y=2.25; label.font_size=24; label.pixel_size=.003; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; actor.add_child(label)
	for i in range(24): await process_frame
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png("res://.godot/code-form-reconstruction.png")
	print("NPC reconstruction capture ",error_string(error))
	scene.queue_free(); await process_frame; quit(0 if error==OK else 1)
