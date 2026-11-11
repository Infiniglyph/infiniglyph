extends SceneTree
## Stress the actual weapon attachments at large world coordinates. Grip
## orientation must never change the local wrist endpoint, even after minutes.
const Visual = preload("res://scripts/character_visual.gd")
const Rig = preload("res://scripts/weapon_rig.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor := Node3D.new()
	root.add_child(actor)
	var visual := Visual.new()
	visual.live_retrieval = false
	actor.add_child(visual)
	var rig := Rig.new()
	rig.visual = visual
	visual.add_child(rig)
	var rest := Vector3(0,-0.29,0)
	for at: Vector3 in [Vector3.ZERO,Vector3(1024,3,-1048),Vector3(-1048,35,1024)]:
		actor.position = at
		rig.right_hand.position = rest
		rig.left_hand.position = rest
		var worst := 0.0
		var axis_error := 0.0
		for tick in range(24000):
			var t := tick/60.0
			visual.rotation.y = t*0.55
			visual.pelvis.rotation = Vector3(sin(t)*0.1,sin(t*0.9)*0.25,cos(t)*0.05)
			visual.chest.rotation = Vector3(sin(t*1.3)*0.25,cos(t*0.8)*0.4,sin(t)*0.12)
			for id: String in ["RightArm","LeftArm"]:
				var arm: Node3D = visual.joints[id]
				arm.rotation = Vector3(sin(t*1.2)*0.8,cos(t*0.7)*0.2,sin(t*0.4)*0.4)
				arm.get_node("Hinge").rotation = Vector3(-0.5+sin(t)*0.4,0,0)
			var right := Vector3(sin(t),t*0.3,cos(t)*0.5)
			var left := Vector3(cos(t),-t*0.3,sin(t)*0.5)
			rig.orient(right,left)
			var expected: Basis = visual.chest.global_basis*Basis.from_euler(right)
			# The same orientation-only path also handles katana tip clearance.
			if tick%7==0:
				expected = Basis(Vector3.FORWARD,0.15)*expected
				rig.orient_hand(rig.right_hand,expected)
			worst = maxf(worst,maxf(rig.right_hand.position.distance_to(rest),rig.left_hand.position.distance_to(rest)))
			axis_error = maxf(axis_error,(rig.right_hand.global_basis.y-expected.y).length())
		check(worst<0.00001,"24,000 changing poses keep both grips at the wrist at %s (max drift %.6f m)" % [at,worst])
		check(axis_error<0.00001,"World weapon orientation is preserved at %s (axis error %.6f)" % [at,axis_error])
		for slot: StringName in [&"down",&"left",&"right",&"up"]:
			rig.equip(slot,false)
			var segments: Array = rig.blade_segments()
			check(segments[0].a.distance_to(visual.joints.RightArm.get_node("Hinge").to_global(rest))<0.0001,"The %s blade hit segment starts at the actual right wrist at %s" % [slot,at])
			if slot==&"up": check(segments[1].a.distance_to(visual.joints.LeftArm.get_node("Hinge").to_global(rest))<0.0001,"The second twin blade stays on the left wrist at %s" % at)
	actor.queue_free()
	await process_frame
	print("Weapon grip drift verification: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
