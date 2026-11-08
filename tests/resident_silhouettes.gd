extends SceneTree
## Native appearance checks and side-by-side pose review.
const Profiles = preload("res://scripts/resident_profiles.gd")
const Visual = preload("res://scripts/resident_visual.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func end(visual: Node3D, rod: int, top: bool) -> Vector3:
	return visual.rods.get_instance_transform(rod)*Vector3(0,0.5 if top else -0.5,0)

func _initialize() -> void:
	if "--headless" in OS.get_cmdline_args():
		push_error("Silhouette inspection requires a native display.")
		quit(2)
		return
	call_deferred("run")

func run() -> void:
	var profiles := Profiles.all(100)
	var grown := Profiles.all(102)
	var stable := true
	var female := 0
	for i in range(profiles.size()):
		if profiles[i].body_profile==&"female": female += 1
		stable = stable and profiles[i].body_profile==grown[i].body_profile
	check(female==50,"The roster contains exactly fifty female and fifty male silhouettes")
	check(stable,"Named residents keep their body profile when the roster is regenerated or extended")
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	world.population.population_seed = 1893
	await ticks(25)
	var live_female := 0
	var wired := true
	var physics_same := true
	var batched := true
	var roles: Dictionary = {}
	for resident: CharacterBody3D in world.population.residents:
		var body: StringName = resident.profile.body_profile
		if body==&"female": live_female += 1
		wired = wired and resident.visual.body_profile==body
		physics_same = physics_same and is_equal_approx(resident.body_shape.shape.radius,0.27) and is_equal_approx(resident.body_shape.shape.height,1.85)
		batched = batched and resident.visual.get_child_count()==2 and resident.visual.joints.instance_count==12
		if not roles.has(resident.profile.role): roles[resident.profile.role] = {}
		roles[resident.profile.role][body] = true
	check(live_female==50 and world.population.residents.size()==100 and wired,"All one hundred actual residents use the assigned fifty-fifty visuals")
	check(physics_same,"Both silhouettes use the existing identical collision capsule")
	check(batched,"Every resident still uses only two shared primitive mesh batches")
	var mixed := true
	for role: Dictionary in roles.values(): mixed = mixed and role.size()==2
	check(mixed,"Both body profiles appear across all existing civilian jobs")
	world.queue_free()
	await ticks(2)
	var figures: Array[Node3D] = []
	var outline_ok := true
	var connections_ok := true
	for pose in range(3):
		for body: StringName in [&"male",&"female"]:
			var figure := Visual.new()
			figure.body_profile = body
			figure.position.x = (figures.size()-2.5)*0.85
			root.add_child(figure)
			for frame in range(40):
				figure.animate(1.0/60.0,1.2 if pose==1 else 0.0,pose==2)
				if body==&"female":
					var shoulders := end(figure,2,true).distance_to(end(figure,2,false))
					var hips := end(figure,1,true).distance_to(end(figure,1,false))
					var waist := end(figure,11,true).distance_to(end(figure,13,true))
					outline_ok = outline_ok and waist<hips*0.6 and waist<shoulders*0.6 and hips>0.3
					for side in range(2):
						connections_ok = connections_ok and end(figure,11+side*2,true).distance_to(end(figure,12+side*2,false))<0.0001
						connections_ok = connections_ok and end(figure,12+side*2,true).distance_to(figure.joints.get_instance_transform(2+side*3).origin)<0.0001
			figures.append(figure)
	check(outline_ok,"Female idle, walk and talk poses retain broader shoulders and hips around a narrow waist")
	check(connections_ok,"The torso outline remains connected to the waist and articulated hips")
	check(figures[0].rods.instance_count==11 and figures[1].rods.instance_count==15 and figures[0].rods.mesh==figures[1].rods.mesh,"The original male profile stays intact and the female outline shares its cylinder mesh")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,1.2,5.3)
	camera.look_at(Vector3(0,1,0))
	camera.fov = 45
	camera.current = true
	await ticks(2)
	var labels := CanvasLayer.new()
	root.add_child(labels)
	for i in range(figures.size()):
		var caption := Label.new()
		caption.text = "Male" if i%2==0 else "Female"
		caption.position = camera.unproject_position(figures[i].position)+Vector2(-26,12)
		labels.add_child(caption)
	for i in range(3):
		var title := Label.new()
		title.text = ["IDLE","WALK","TALK"][i]
		title.position = camera.unproject_position((figures[i*2].position+figures[i*2+1].position)*0.5+Vector3.UP*2.1)+Vector2(-24,0)
		labels.add_child(title)
	DirAccess.make_dir_recursive_absolute("res://captures")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/resident_silhouettes_front.png")
	for figure: Node3D in figures: figure.rotation.y = PI/5
	await ticks(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/resident_silhouettes_angle.png")
	print("Resident silhouette verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
