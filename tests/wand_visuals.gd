extends SceneTree
## Check actual native meshes and the authored cast trajectories at low/high Hz.
const Wand = preload("res://scripts/wand_presentation.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
const Gestures = preload("res://scripts/wand_motion.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Moves = preload("res://scripts/wand_moves.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Preview = preload("res://scripts/equipment_preview.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func run() -> void:
	var first: Node3D = Geometry.model({"family":"wand","length":.62,"tint":"00e5ff"})
	var second := Wand.model(Color("00e5ff"))
	check(first.name=="ArcWand" and first.get_child_count()==5,"Wand preview uses its four native mesh surfaces and a physical emitter marker")
	var shared := true
	var bounds := AABB()
	var vertices := 0
	for i in range(4):
		shared = shared and first.get_child(i).mesh==second.get_child(i).mesh
		bounds = bounds.merge(first.get_child(i).get_aabb())
		vertices += first.get_child(i).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	check(shared,"Repeated standard-issue wands share immutable GPU meshes")
	check(bounds.size.x<.11 and bounds.size.z<.11 and bounds.position.y>=-.151 and bounds.end.y<=.651 and vertices<1200,"The slender wand stays within its bounded handheld geometry budget")
	check(first.get_node("WandEmitter").position==Wand.TIP,"The actual emitter marker matches projectile origin geometry")
	var variants := Database.all().filter(func(entry: Dictionary): return entry.family=="wand")
	check(variants.size()==8,"The shared equipment catalogue provides exactly eight wand variants")
	for entry: Dictionary in variants:
		var tint := Color(entry.geometry.tint)
		var model := Preview.model(entry)
		var core: Material = model.get_child(3).mesh.surface_get_material(0)
		check(model.name=="ArcWand" and core.emission.to_html()==tint.to_html(),"Tower preview and native focus retain variant pigment "+String(entry.id))
		model.free()
	for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
		var move := Moves.move({"id":"test_arc_wand"},action)
		var profile: String = move.profile
		var finite := true
		var continuous := true
		var prior: Dictionary = {}
		for i in range(145):
			var sample := Motion.sample(move,i/144.0*float(move.duration))
			for key: String in Gestures.KEYS: finite = finite and sample[key].is_finite()
			if not prior.is_empty(): continuous = continuous and sample.left.distance_to(prior.left)<.06
			prior = sample
		check(finite and continuous,"The "+profile+" gesture keeps finite, continuous hand and torso paths at 144 Hz")
		var start := Motion.sample(move,0)
		var finish := Motion.sample(move,float(move.duration))
		check(start.left.distance_to(finish.left)<.001,"The "+profile+" follow-through returns to the shared dueling carry")
	var wheel := {"weapon_family":"wand","profile":"wand_wheel","duration":.58,"hits":[.19]}
	check(Motion.sample(wheel,.10).left.y<1.0 and Motion.sample(wheel,.40).left.y>1.35,"Laser Wheel visibly dips at the hip and rises through an underhand release")
	first.free()
	second.free()
	print("WAND VISUALS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
