extends SceneTree
## Real rig and catalog stow transforms; drawn geometry and wrist origins stay fixed.
const Visual = preload("res://scripts/character_visual.gd")
const Rig = preload("res://scripts/weapon_rig.gd")
const Database = preload("res://scripts/equipment_database.gd")
var checks := 0
var failures := 0

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var figure := Visual.new()
	figure.live_retrieval = false
	root.add_child(figure)
	var rig := Rig.new()
	rig.visual = figure
	figure.add_child(rig)
	var wrist_right: Transform3D = rig.right_hand.transform
	var wrist_left: Transform3D = rig.left_hand.transform
	var sample: Dictionary = {}
	var scythes := 0
	for item: Dictionary in Database.all():
		if item.category!="weapons": continue
		if not sample.has(item.family): sample[item.family] = StringName(item.id)
		if item.family!="scythe": continue
		scythes += 1
		var id := StringName(item.id)
		rig.equip_item(id,true)
		var model: Dictionary = rig.models[id]
		var blade: Node3D = model.stowed_blades[0]
		check(model.stowed.get_parent()==figure.chest and blade.basis.y.dot(Vector3.UP)>.94 and blade.position.is_zero_approx() and model.stowed.visible and not model.right.visible,String(id)+" carries its scythe head-up on the back")
		rig.equip_item(id,false)
		check(model.right.visible and not model.stowed.visible and model.right.transform.is_equal_approx(Transform3D.IDENTITY),String(id)+" draws with unchanged attack geometry")
		await process_frame
	check(scythes>0,"Every registered scythe was exercised")
	for family: String in ["spear","halberd","staff"]:
		var id: StringName = sample[family]
		rig.equip_item(id,true)
		var blade: Node3D = rig.models[id].stowed_blades[0]
		check(blade.basis.y.dot(Vector3.UP)>.94 and blade.position.is_zero_approx(),family+" shares the upright base-spear carry")
	var sword: StringName = sample.sword
	rig.equip_item(sword,true)
	check(rig.models[sword].stowed_blades[0].basis.y.dot(Vector3.UP)<-.89,"Sword tips keep their downward back angle")
	var katana: StringName = sample.katana
	rig.equip_item(katana,true)
	var katana_blade: Node3D = rig.models[katana].stowed_blades[0]
	check(rig.models[katana].stowed.get_parent()==figure.pelvis and rig.models[katana].stowed.position.is_equal_approx(Vector3(-.29,.07,.14)) and katana_blade.rotation.is_equal_approx(Vector3(-1.97,.10,0)),"Katana retains its left-hip trailing saya orientation")
	var twin: StringName = sample.twin_blades
	rig.equip_item(twin,true)
	var pair: Array = rig.models[twin].stowed_blades
	check(pair.size()==2 and pair[0].basis.y.y<-.89 and pair[1].basis.y.y<-.89 and pair[0].basis.y.x*pair[1].basis.y.x<0,"Paired blades preserve both mirrored downward mounts")
	for index in range(80):
		var id: StringName = sample.scythe if index%2==0 else sword
		rig.equip_item(id,index%3==0)
		rig.orient(Vector3(.3,.1,.2),Vector3(-.2,.15,.4))
		await process_frame
	check(rig.right_hand.position.is_equal_approx(wrist_right.origin) and rig.left_hand.position.is_equal_approx(wrist_left.origin) and rig.models.size()==5,"Repeated draw, stow, orientation and equip cycles preserve wrist origins and the bounded rig")
	rig.equip(&"left",true)
	check(rig.models.left.stowed_blades[0].basis.y.dot(Vector3.UP)>.94,"Original spear carry remains upright")
	rig.equip(&"down",true)
	check(rig.models.down.stowed_blades[0].basis.y.y<-.89,"Original sword carry remains downward")
	figure.free()
	print("WEAPON STOW: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
