extends "res://scripts/player.gd"
## A civilian combat adapter: shared player locomotion, AI and hit resolution.
const Brain = preload("res://scripts/sparring_brain.gd")
const Neon = preload("res://scripts/neon.gd")
const DamageNumber = preload("res://scripts/damage_number.gd")
class AimFrame extends Node3D:
	var yaw := 0.0
	var camera: Camera3D
	func reset_follow() -> void: pass
var reactions: Node3D
var identity: String
var profile: Dictionary
var opponent: CharacterBody3D
var label: Label3D
var dead := false
var female_shape: MultiMesh
var store: Node
var code_form_id := ""
var _fallback_weapons: Dictionary={}

func _ready() -> void:
	live_motion_retrieval = false
	inventory_owner_id = "resident_fighter/"+identity
	controls = Brain.new()
	controls.actor = self
	controls.opponent = opponent
	add_child(controls)
	camera_rig = AimFrame.new()
	camera_rig.camera = opponent.camera_rig.camera
	add_child(camera_rig)
	super._ready()
	name = profile.name+"_Fighting"
	collision_layer = 6 # Physical resident + existing combat hurt layer.
	var ink := Neon.material(profile.tint)
	dodge.set_tint(profile.tint)
	for geometry: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
		if geometry.mesh.surface_get_material(0)==Neon.body: geometry.material_override = ink
	if profile.get("body_profile",&"male")==&"female":
		# Retain the civilian silhouette on the articulated combat rig.
		visual.joints.LeftLeg.position.x = -0.18
		visual.joints.RightLeg.position.x = 0.18
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.023
		mesh.bottom_radius = 0.023
		mesh.height = 1
		mesh.radial_segments = 6
		female_shape = MultiMesh.new()
		female_shape.transform_format = MultiMesh.TRANSFORM_3D
		female_shape.mesh = mesh
		female_shape.instance_count = 4
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = female_shape
		instance.material_override = ink
		visual.add_child(instance)
	dodge.cache_geometry()
	if profile.tint.r>0.85 and profile.tint.g>0.15 and profile.tint.g<0.55:
		var light := OmniLight3D.new()
		light.light_color = profile.tint
		light.omni_range = 2
		light.light_energy = 0.45
		light.position.y = 1.1
		add_child(light)
	label = Label3D.new()
	label.position.y = 2.3
	label.font_size = 30
	label.pixel_size = 0.004
	label.modulate = Color(1,0.35,0.25)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	add_to_group("combat_targets")
	combat.selected_slot = [&"down",&"left",&"right",&"up"][absi(identity.hash())%4]
	combat.sheathed = false
	if is_instance_valid(store): attach_store(store)
	if not code_form_id.is_empty(): set_meta("code_form_id",code_form_id)
	weapon_combat.sync_rig()
	target_lock.show_marker = false
	target_lock.select(opponent)
	controls.start()

func attach_store(authority: Node) -> void:
	if not is_instance_valid(authority) or inventory==authority: return
	var starter: Node=inventory
	var fallback:=default_combat_fallback()
	for slot: StringName in authority.SLOTS:
		if authority.weapon_slot(slot)!=&"": fallback=false
	if fallback:
		for slot: StringName in starter.SLOTS: _fallback_weapons[slot]=starter.weapon_slot(slot)
	store=authority
	inventory=authority
	inventory.actor=self
	combat.loadout_resolver=_combat_slot
	inventory.equipment_changed.connect(combat.refresh_equipment)
	inventory.equipment_changed.connect(weapon_combat.refresh_passives)
	inventory.equipment_changed.connect(_clothing_changed)
	if is_instance_valid(starter) and starter.get_parent()==self: starter.queue_free()
	if inventory.weapon_slot(combat.selected_slot)==&"":
		for slot: StringName in inventory.SLOTS:
			if inventory.weapon_slot(slot)!=&"": combat.selected_slot=slot; break
	combat.refresh_equipment()
	combat.sheathed=false
	visual.sync_clothing(inventory)
	weapon_combat.refresh_passives()

func _combat_slot(slot: StringName) -> StringName:
	# Previously an unarmed resident retained the temporary four basic combat
	# choices. Preserve that handling without replacing their owned wardrobe.
	for direction: StringName in inventory.SLOTS:
		if inventory.weapon_slot(direction)!=&"": return inventory.weapon_slot(slot)
	return StringName(_fallback_weapons.get(slot,&""))

func default_combat_fallback() -> bool: return true

func _clothing_changed() -> void: visual.sync_clothing(inventory)

func detach_store() -> void:
	if not is_instance_valid(store) or inventory!=store: return
	if inventory.equipment_changed.is_connected(combat.refresh_equipment): inventory.equipment_changed.disconnect(combat.refresh_equipment)
	if inventory.equipment_changed.is_connected(_clothing_changed): inventory.equipment_changed.disconnect(_clothing_changed)
	if inventory.equipment_changed.is_connected(weapon_combat.refresh_passives): inventory.equipment_changed.disconnect(weapon_combat.refresh_passives)
	if inventory.actor==self: inventory.actor=null

func _exit_tree() -> void: detach_store()

func _process(_delta: float) -> void:
	label.text = profile.name+"\nHOSTILE  %d / %d" % [ceili(health),ceili(weapon_combat.max_health)]
	label.visible = global_position.distance_to(opponent.global_position)<24 and not dead
	if female_shape!=null:
		var waist: Vector3 = visual.pelvis.position+Vector3(0,0.24,0)
		for side in [-1,1]:
			var shoulder: Vector3 = visual.to_local(visual.chest.to_global(Vector3(side*0.23,0.51,0)))
			var hip: Vector3 = visual.to_local(visual.pelvis.to_global(Vector3(side*0.18,0,0)))
			var edge := waist+Vector3(side*0.075,0,0)
			var index := 0 if side<0 else 2
			for segment: Array in [[shoulder,edge],[edge,hip]]:
				var vector: Vector3 = segment[1]-segment[0]
				var basis := Basis(Quaternion(Vector3.UP,vector.normalized()))*Basis.from_scale(Vector3(1,vector.length(),1))
				female_shape.set_instance_transform(index,Transform3D(basis,(segment[0]+segment[1])*0.5))
				index += 1

func can_attack_target(target: Node) -> bool:
	return not dead and target==opponent and reactions.can_fight()

func receive_hit(amount: float, source: Vector3, attacker: Node = null, incoming: Dictionary = {}) -> float:
	var native_wave: bool=incoming.get("vehicle_wave",false) and is_instance_valid(attacker) and attacker.has_method("driving_actor") and attacker!=opponent
	var society: Node
	if native_wave:
		society=reactions._civilization() if reactions.has_method("_civilization") else reactions.world.civilization
		native_wave=is_instance_valid(society) and not String(society.id_for_source(attacker)).is_empty()
	if dead or attacker!=opponent and not native_wave or not native_wave and not reactions.can_fight(): return 0
	var before := health
	if native_wave and amount>=before:
		set_meta("native_defeat",String(society.id_for_source(attacker)))
	var applied := minf(before,super.receive_hit(amount,source,attacker,incoming))
	if native_wave and health>0 and has_meta("native_defeat"): remove_meta("native_defeat")
	if applied>0:
		DamageNumber.make_room(get_tree())
		var number := DamageNumber.new()
		number.text = "%.1f" % applied
		get_parent().add_child(number)
		number.global_position = combat_point()+Vector3.UP*.55
	return applied

func combat_name() -> String: return profile.name

func on_combat_defeat() -> void:
	if dead: return
	dead = true
	controls.stop()
	weapon_combat.cancel()
	target_lock.clear()
	remove_from_group("combat_targets")
	collision_layer = 0
	collision_mask = 0
	hide()
	set_physics_process(false)
	weapon_combat.set_physics_process(false)
	reactions.call_deferred("finish_fighter",identity,true,self)

func respawn() -> void:
	# A fall uses the same identity/spawn recovery as combat defeat.
	on_combat_defeat()
