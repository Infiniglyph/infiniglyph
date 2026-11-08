extends SceneTree
const Sparks = preload("res://scripts/spark_burst.gd")
const Feedback = preload("res://scripts/impact_feedback.gd")
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
	var scene := Node3D.new()
	root.add_child(scene)
	var sparks := Sparks.new()
	scene.add_child(sparks)
	var red := Color(1,0.025,0.065)
	var orange := Color(1,0.38,0.015)
	sparks.ignite(Vector3.FORWARD,red,orange,1,28,12345)
	var reds := 0
	var oranges := 0
	var slowest := 100.0
	var fastest := 0.0
	for i in range(sparks.count):
		if sparks.colors[i] == red: reds += 1
		if sparks.colors[i] == orange: oranges += 1
		slowest = minf(slowest,sparks.velocities[i].length())
		fastest = maxf(fastest,sparks.velocities[i].length())
	check(reds>0 and oranges>0 and reds+oranges == 28,"Each damage flight mixes saturated neon red and orange sparks")
	check(fastest-slowest>2 and sparks.lifetimes[0] != sparks.lifetimes[1],"Independent speeds and lifetimes replace the uniform radial burst")
	sparks.redraw(0.08)
	var near_positions := sparks.positions.duplicate()
	sparks.redraw(0.2)
	var moving := 0
	for i in range(sparks.count):
		if sparks.positions[i].distance_to(near_positions[i])>0.2 and sparks.positions[i].length()>0.3: moving += 1
	check(moving == 28,"All sparks leave the impact point and visibly travel, rather than scaling a stamp")
	check(sparks.trails.get_surface_count() == 1,"Each flight renders in a single small pooled mesh")
	var ballistic := sparks.flight(0,0.2)-sparks.velocities[0]*((1-exp(-sparks.DRAG*0.2))/sparks.DRAG)
	check(ballistic.y<-0.2,"Sparks arc downward as their momentum fades")
	var end_positions := sparks.positions.duplicate()
	for hz in [30,60,120]:
		sparks.ignite(Vector3.FORWARD,red,orange,1,28,12345)
		for step in range(int(hz*0.2)): sparks.redraw(float(step+1)/hz)
		var matching := true
		for i in range(sparks.count): matching = matching and sparks.positions[i].is_equal_approx(end_positions[i])
		check(matching,"Spark flights match at %d Hz" % hz)
	sparks.redraw(0.7)
	check(not sparks.visible and sparks.trails.get_surface_count() == 0,"Sparks fully fade and clear their geometry after the longest lifetime")
	var feedback := Feedback.new()
	scene.add_child(feedback)
	for i in range(80): feedback.confirm("hit",Vector3(2,1,3),Vector3.FORWARD,null,null,true)
	check(feedback.bursts.size() == 12 and feedback.get_child_count() == 16,"Rapid impacts reuse 12 spark flights and four audio voices")
	check(feedback.bursts[0].mesh.count<=28 and feedback.bursts[0].mesh.global_position == Vector3(2,1,3),"Pool reuse preserves the actual contact location and per-burst particle cap")
	feedback._process(0.7)
	var hidden := 0
	for burst: Dictionary in feedback.bursts:
		if not burst.mesh.visible: hidden += 1
	check(hidden == 12,"Rapid effects finish without leaving emissive geometry behind")
	scene.queue_free()
	await process_frame
	print("Spark verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
