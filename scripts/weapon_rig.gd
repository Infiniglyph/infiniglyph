extends Node3D
## Code-native opaque weapons with bright wire edges. Hand grips follow the
## existing forearms. Back mounts follow the chest; the katana follows the hip.
const Neon = preload("res://scripts/neon.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
var _custom_key: StringName = &""
var visual: Node3D
var right_hand: Node3D
var left_hand: Node3D
var models: Dictionary = {}
var selected: StringName = &"down"
var sheathed := false
var _edges := PackedVector3Array()
var _faces := PackedVector3Array()
var _solid: StandardMaterial3D

func _ready() -> void:
	name = "WeaponRig"
	Neon.prepare()
	_solid = Neon.dark.duplicate()
	_solid.cull_mode = BaseMaterial3D.CULL_DISABLED
	right_hand = grip("RightArm")
	left_hand = grip("LeftArm")
	for slot: StringName in Library.LOADOUTS:
		var definition := Library.loadout(slot)
		var kind: StringName = definition.id
		var right := model(kind,definition.color)
		right_hand.add_child(right)
		var left := Node3D.new()
		left_hand.add_child(left)
		if kind == &"sword_shield": left.add_child(model(&"shield",definition.color))
		elif kind == &"twin_blades": left.add_child(model(kind,definition.color))
		var stowed := Node3D.new()
		(visual.pelvis if kind == &"katana" else visual.chest).add_child(stowed)
		stowed.position = Vector3(-0.29,0.07,0.14) if kind == &"katana" else Vector3(0,0,-0.19)
		var back := model(kind,definition.color)
		stowed.add_child(back)
		var stowed_blades: Array[Node3D] = [back]
		back.rotation.z = -0.32
		if kind == &"sword_shield":
			back.position = Vector3(0.18,0.55,0)
			back.rotation.z = PI-0.45
			var shield := model(&"shield",definition.color)
			stowed.add_child(shield)
			shield.position = Vector3(0,0.20,-0.08)
		elif kind == &"katana":
			# Hilt forward at the left waist; saya and tip trail back and down.
			back.rotation = Vector3(-1.97,0.10,0)
			back.add_child(model(&"katana_saya",definition.color*0.65))
		elif kind == &"twin_blades":
			back.position = Vector3(0.15,0.34,0)
			back.rotation.z = PI-0.65
			var other := model(kind,definition.color)
			stowed.add_child(other)
			other.position = Vector3(-0.15,0.34,0)
			other.rotation.z = PI+0.65
			stowed_blades.append(other)
		models[slot] = {"right":right,"left":left,"stowed":stowed,"stowed_blades":stowed_blades}
	equip(selected,false)

func grip(arm: String) -> Node3D:
	var hand := Node3D.new()
	hand.name = "WeaponGrip"
	visual.joints[arm].get_node("Hinge").add_child(hand)
	hand.position.y = -0.29
	return hand

func equip(slot: StringName, stow: bool) -> void:
	selected = slot
	sheathed = stow
	for key: StringName in models:
		models[key].right.visible = key == slot and not stow
		models[key].left.visible = key == slot and not stow
		models[key].stowed.visible = key == slot and stow

func equip_item(id: StringName, stow: bool) -> void:
	var item := Equipment.get_item(id)
	if item.is_empty(): return
	if id!=_custom_key:
		if models.has(_custom_key):
			for key: String in ["right","left","stowed"]:
				var node: Node3D = models[_custom_key][key]
				node.get_parent().remove_child(node)
				node.queue_free()
			models.erase(_custom_key)
		_custom_key = id
		var geometry: Dictionary = item.geometry
		var kind := StringName(item.combat_kind)
		var right := Geometry.model(geometry)
		right_hand.add_child(right)
		var left := Node3D.new()
		left_hand.add_child(left)
		if kind==&"twin_blades":
			var other := geometry.duplicate(true)
			if other.get("asymmetric",false): other.length = float(other.length)*.78
			left.add_child(Geometry.model(other))
		var stored := Node3D.new()
		(visual.pelvis if kind==&"katana" else visual.chest).add_child(stored)
		stored.position = Vector3(-.29,.07,.14) if kind==&"katana" else Vector3(0,0,-.19)
		var back := Geometry.model(geometry)
		stored.add_child(back)
		back.position = Vector3(.15,.34,0)
		back.rotation.z = PI-.45
		if kind==&"katana":
			back.position = Vector3.ZERO
			back.rotation = Vector3(-1.97,.10,0)
		elif geometry.get("family",item.family) in ["scythe","spear","halberd","staff"] and item.get("attachment",{}).get("stow","back")=="back":
			# Long poles carry head-up in the same back mount as the base spear.
			# Sword tips still angle down; only the stowed model is rotated.
			back.position = Vector3.ZERO
			back.rotation.z = -.32
		var stowed_blades: Array[Node3D] = [back]
		if kind==&"twin_blades":
			var second := geometry.duplicate(true)
			if second.get("asymmetric",false): second.length = float(second.length)*.78
			var other := Geometry.model(second)
			stored.add_child(other)
			other.position = Vector3(-.15,.34,0)
			other.rotation.z = PI+.45
			stowed_blades.append(other)
		models[id] = {"right":right,"left":left,"stowed":stored,"stowed_blades":stowed_blades}
	equip(id,stow)

func orient(right: Vector3, left: Vector3) -> void:
	orient_hand(right_hand,visual.chest.global_basis*Basis.from_euler(right))
	orient_hand(left_hand,visual.chest.global_basis*Basis.from_euler(left))

func orient_hand(hand: Node3D, world_basis: Basis) -> void:
	# A global-basis assignment round-trips the global origin through the
	# parent's inverse too. Repeated float error drifts the wrist attachment,
	# especially in distant districts. Change only the local basis instead.
	hand.basis = hand.get_parent().global_basis.inverse()*world_basis

func blade_segments() -> Array:
	if sheathed or not models.has(selected): return []
	var kind: StringName = Library.loadout(selected).id
	var length := 1.74 if kind == &"spear" else (0.66 if kind == &"twin_blades" else 1.15)
	var item := Equipment.get_item(selected)
	if not item.is_empty(): length = float(item.geometry.length)
	var result := [{"a":right_hand.global_position,"b":right_hand.to_global(Vector3(0,length,0))}]
	if kind == &"twin_blades": result.append({"a":left_hand.global_position,"b":left_hand.to_global(Vector3(0,length*(.78 if item.get("geometry",{}).get("asymmetric",false) else 1.0),0))})
	return result

func _triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	_faces.append_array([a,b,c])

func _prism(polygon: Array, depth: float) -> void:
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for point: Vector2 in polygon:
		front.append(Vector3(point.x,point.y,depth*0.5))
		back.append(Vector3(point.x,point.y,-depth*0.5))
	for i in range(1,polygon.size()-1):
		_triangle(front[0],front[i],front[i+1])
		_triangle(back[0],back[i+1],back[i])
	for i in range(polygon.size()):
		var j := (i+1)%polygon.size()
		_triangle(front[i],back[i],front[j])
		_triangle(front[j],back[i],back[j])
		_edges.append_array([front[i],front[j],back[i],back[j],front[i],back[i]])

func _box(x: float, y: float, width: float, height: float, depth: float) -> void:
	_prism([Vector2(x-width*0.5,y),Vector2(x+width*0.5,y),Vector2(x+width*0.5,y+height),Vector2(x-width*0.5,y+height)],depth)

func model(kind: StringName, color: Color) -> Node3D:
	_edges = PackedVector3Array()
	_faces = PackedVector3Array()
	match kind:
		&"shield":
			_prism([Vector2(-0.36,0.28),Vector2(-0.28,0.58),Vector2(0.28,0.58),Vector2(0.36,0.28),Vector2(0.25,-0.22),Vector2(0,-0.42),Vector2(-0.25,-0.22)],0.09)
			_edges.append_array([Vector3(-0.22,0.13,0.052),Vector3(0.22,0.13,0.052),Vector3(0,-0.25,0.052),Vector3(0,0.43,0.052)])
		&"spear":
			_box(0,-0.70,0.055,2.06,0.055)
			_prism([Vector2(-0.16,1.27),Vector2(0,1.74),Vector2(0.16,1.27)],0.045)
			_box(0,1.15,0.17,0.045,0.08)
		&"katana",&"katana_saya":
			var saya := kind == &"katana_saya"
			var outline: Array = []
			for i in range(7):
				var t := i/6.0
				outline.append(Vector2(0.14*t*t-(0.065 if saya else 0.045)*(1-t*0.5),0.13+t*0.94))
			outline.append(Vector2(0.17,1.18 if saya else 1.15))
			for i in range(6,-1,-1):
				var t := i/6.0
				outline.append(Vector2(0.14*t*t+(0.065 if saya else 0.045)*(1-t*0.5),0.13+t*0.94))
			_prism(outline,0.065 if saya else 0.025)
			if saya:
				_box(0,0.12,0.15,0.045,0.08)
			else:
				_box(0,-0.23,0.055,0.35,0.055)
				_box(0,0.08,0.22,0.035,0.10)
		&"twin_blades":
			_prism([Vector2(-0.055,0.10),Vector2(-0.03,0.49),Vector2(0.12,0.66),Vector2(0.105,0.35),Vector2(0.055,0.10)],0.035)
			_box(0,-0.17,0.055,0.27,0.055)
			_box(0,0.07,0.23,0.04,0.065)
		_:
			_prism([Vector2(-0.075,0.14),Vector2(-0.065,0.96),Vector2(0,1.15),Vector2(0.065,0.96),Vector2(0.075,0.14)],0.045)
			_box(0,-0.23,0.065,0.36,0.065)
			_box(0,0.08,0.38,0.055,0.08)
			_prism([Vector2(-0.07,-0.22),Vector2(0,-0.31),Vector2(0.07,-0.22),Vector2(0,-0.17)],0.07)
	var root := Node3D.new()
	root.name = String(kind)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,_solid)
	for i in range(0,_faces.size(),3):
		var normal := (_faces[i+1]-_faces[i]).cross(_faces[i+2]-_faces[i]).normalized()
		for j in range(3):
			mesh.surface_set_normal(normal)
			mesh.surface_add_vertex(_faces[i+j])
	mesh.surface_end()
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	root.add_child(surface)
	root.add_child(Neon.lines(_edges,Neon.material(color)))
	return root
