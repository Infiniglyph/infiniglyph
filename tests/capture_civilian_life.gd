extends SceneTree
const Visual=preload("res://scripts/resident_visual.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Wardrobe=preload("res://scripts/code_form_wardrobe.gd")
func _initialize(): call_deferred("run")
func run():
	var stage=Node3D.new(); root.add_child(stage)
	for i in range(3):
		var figure=Visual.new(); figure.tint=Color("6fffff"); stage.add_child(figure); figure.position.x=(i-1)*2.6
		var store=Inventory.new(); store.owner_id="resident:gallery"+str(i); stage.add_child(store)
		var state={"attire_issued":false,"uniform_issued":false}; Wardrobe.issue(store,state,i==1)
		figure.sync_clothing(store)
		if i==2: figure.sitting=true; figure.activity="meal"
		figure.animate(.2,0,false)
		var label=Label3D.new(); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.text=["CIVIC STARTER","DARK BOX UNIFORM","SEATED MEAL"][i]; label.font_size=34; label.pixel_size=.006; stage.add_child(label); label.position=Vector3((i-1)*2.6,2.6,0)
	var camera=Camera3D.new(); stage.add_child(camera); camera.position=Vector3(2.8,3.3,8); camera.look_at(Vector3(0,1.2,0)); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=6; camera.current=true
	for i in range(20): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/civilian_life.png")
	print("CAPTURE civilian_life")
	quit()
