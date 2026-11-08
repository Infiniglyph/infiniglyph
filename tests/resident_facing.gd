extends SceneTree
## Verify the rendered gait against the resident's real facing calculation.
## Run with a display; the headless renderer returns stub MultiMesh transforms.
const Resident = preload("res://scripts/city_resident.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for body_profile: StringName in [&"male",&"female"]: verify_body(body_profile)
	print("RESIDENT FACING: ",failures," failures")
	await process_frame
	quit(1 if failures else 0)

func verify_body(body_profile: StringName) -> void:
	print("BODY PROFILE: ",body_profile)
	var resident = Resident.new()
	resident.profile = {"name":"Facing probe","serial":0,"tint":Color.CYAN,"color_name":"cyan","role":"resident","home":&"plaza_w","body_profile":body_profile}
	root.add_child(resident)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var visual: Node3D = resident.visual
	var facing_ok := true
	var knees_ok := true
	var lean_ok := true
	var swing_ok := true
	var stance_ok := true
	var arms_ok := true
	var shoulders_ok := true
	for heading in range(8):
		var direction := Vector3.BACK.rotated(Vector3.UP,heading*TAU/8)
		resident.face(resident.global_position+direction,1.0)
		facing_ok = facing_ok and visual.global_basis.z.normalized().dot(direction)>0.999
		for speed in [0.6,1.5]:
			visual.walking = 1.0
			visual.phase = 0
			visual.animate(0.0,speed,false)
			for frame in range(120):
				var before: Vector3 = visual.joints.get_instance_transform(4).origin
				var previous_cycle: float = visual.phase
				visual.animate(1.0/60.0,speed,false)
				var after: Vector3 = visual.joints.get_instance_transform(4).origin
				var middle_cycle: float = (previous_cycle+float(visual.phase))*0.5
				if absf(float(visual.phase)-previous_cycle)<0.2:
					if cos(middle_cycle)>0.2: swing_ok = swing_ok and after.z>before.z
					if cos(middle_cycle)<-0.2: stance_ok = stance_ok and after.z<before.z
				var spine: Transform3D = visual.rods.get_instance_transform(0)
				lean_ok = lean_ok and (visual.global_basis*spine.basis.y).dot(direction)>0
				shoulders_ok = shoulders_ok and absf(visual.rods.get_instance_transform(2).basis.y.length()-0.46)<0.0001
				for side in range(2):
					var hip: Vector3 = visual.joints.get_instance_transform(2+side*3).origin
					var knee: Vector3 = visual.joints.get_instance_transform(3+side*3).origin
					var foot: Vector3 = visual.joints.get_instance_transform(4+side*3).origin
					var axis := (foot-hip).normalized()
					var bend := knee-hip-axis*(knee-hip).dot(axis)
					knees_ok = knees_ok and (visual.global_basis*bend).dot(direction)>0.0001
					var upper_arm: Transform3D = visual.rods.get_instance_transform(7+side*2)
					var shoulder := upper_arm*Vector3(0,-0.5,0)
					var hand: Vector3 = visual.joints.get_instance_transform(9+side*2).origin
					arms_ok = arms_ok and (hand.z-shoulder.z-0.07)*foot.z<=0.00001
	check(facing_ok,"Visual front follows travel in all eight headings")
	check(knees_ok,"Both rendered knees bend toward travel throughout slow and fast walk cycles")
	check(lean_ok,"Chest leans toward travel")
	check(swing_ok and stance_ok,"Swing foot advances and support foot recedes relative to the body")
	check(arms_ok,"Arms counter-swing against their matching legs")
	check(shoulders_ok,"Shoulder bars retain their full width")
	resident.queue_free()
