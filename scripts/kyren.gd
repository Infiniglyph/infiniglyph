extends "res://scripts/player.gd"
## Existing player skeleton, physics and combat, with Kyren's resting presentation.
const RestingVisual = preload("res://scripts/kyren_visual.gd")
const Scarf = preload("res://scripts/kyren_scarf.gd")
const Brain = preload("res://scripts/kyren_brain.gd")
const KyrenCombat = preload("res://scripts/kyren_combat.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Neon = preload("res://scripts/neon.gd")
const DamageNumber = preload("res://scripts/damage_number.gd")
const Equipment = preload("res://scripts/equipment_database.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
class AimFrame extends Node3D:
	var yaw := 0.0
	var camera: Camera3D
	func reset_follow() -> void: pass
@export var base_health := 2200.0
var opponent: CharacterBody3D
var encounter: Node
var rest_visual: Node3D
var scarf: Node3D
var head_anchor: Node3D
var scarf_anchor: Node3D
var state := &"resting"
var home_point := Vector3.ZERO
var rest_weight := 1.0
var _transition := 0.0
var _pose_clock := 0.0
var _collider: CollisionShape3D
var _standing_shape := CapsuleShape3D.new()
var _resting_shape := CapsuleShape3D.new()
var nameplate: Label3D
var _sheathed_sword: Node3D
var _sword_mount: Transform3D

func create_weapon_combat() -> Node: return KyrenCombat.new()

func _ready() -> void:
	live_motion_retrieval=false
	inventory_owner_id="kyren"
	spawn=position
	controls=Brain.new()
	controls.actor=self
	add_child(controls)
	camera_rig=AimFrame.new()
	camera_rig.camera=get_viewport().get_camera_3d()
	add_child(camera_rig)
	super._ready()
	name="Kyren"
	home_point=global_position
	spawn=home_point # Player.respawn expects world coordinates, not the home's local offset.
	visual.scale=Vector3.ONE*2
	dodge.rest_scale=visual.scale
	var gold := Neon.shared_material(RestingVisual.GOLD)
	for geometry: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
		if geometry.mesh.surface_get_material(0)==Neon.body: geometry.material_override=gold
	weapon_combat.max_health=base_health
	weapon_combat.health=base_health
	inventory.restore({"version":1,"owner_id":"kyren","items":[],"equipment":{}})
	var katana: Resource = Catalog.create(&"kyren_katana")
	inventory.add_item(katana)
	inventory.assign(&"right",katana.instance_id)
	combat.selected_slot=&"right"
	combat.sheathed=true
	weapon_combat.sync_rig()
	_sheathed_sword=weapon_combat.rig.models[&"kyren_katana"].stowed
	_sword_mount=_sheathed_sword.transform
	# Enclose the actual named blade, leaving its gold hilt and guard exposed.
	var outline: Array = []
	for point: Array in Equipment.get_item(&"kyren_katana").geometry.outline:
		if float(point[1])>.34:
			outline.append(Vector2(float(point[0])+signf(float(point[0]))*.018,.82+(float(point[1])-.82)*1.08))
	var saya := Geometry.model({"family":"katana","outline":outline,"depth":.085,"tint":"bf1934"})
	saya.name="KyrenSaya"
	_sheathed_sword.get_child(0).add_child(saya)
	target_lock.show_marker=false
	for child: Node in get_children():
		if child is CollisionShape3D:
			_collider=child
			break
	_standing_shape.height=3.75
	_standing_shape.radius=.54
	_resting_shape.height=2.65
	_resting_shape.radius=.67
	_set_standing(false)
	rest_visual=RestingVisual.new()
	add_child(rest_visual)
	head_anchor=Node3D.new()
	head_anchor.position=Vector3(0,.78,0)
	visual.chest.add_child(head_anchor)
	scarf_anchor=Node3D.new()
	scarf_anchor.position=Vector3(0,.65,0)
	visual.chest.add_child(scarf_anchor)
	scarf_anchor.add_child(rest_visual.scarf_anchor.get_child(0).duplicate())
	scarf=Scarf.new()
	scarf.anchor=rest_visual.scarf_anchor
	scarf.phase_source=dodge
	scarf.motion_source=self
	add_child(scarf)
	rest_visual.hat.reparent(head_anchor,false)
	dodge.set_tint(RestingVisual.GOLD)
	dodge.cache_geometry()
	rest_visual.hat.reparent(rest_visual.head_anchor,false)
	rest_visual.embers.phase_source=dodge
	_mount_sword(true)
	visual.hide()
	weapon_combat.set_physics_process(false)
	controls.stop()
	nameplate=Label3D.new()
	nameplate.name="Nameplate"
	nameplate.text="Kyren"
	nameplate.position.y=3.3
	nameplate.font_size=32
	nameplate.pixel_size=.005
	nameplate.modulate=RestingVisual.GOLD
	nameplate.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.visibility_range_end=28
	add_child(nameplate)

func _set_standing(standing: bool) -> void:
	_collider.shape=_standing_shape if standing else _resting_shape
	_collider.position=Vector3(0,1.9,0) if standing else Vector3(0,1.34,.13)
	collision_layer=6 if standing else 4
	collision_mask=1

func wake() -> void:
	_mount_sword(false)
	rest_visual.hat.reparent(head_anchor,false)
	scarf.anchor=scarf_anchor
	rest_visual.hide()
	visual.show()
	_set_standing(true)
	state=&"rising"
	_transition=.55
	rest_weight=1
	controls.stop()
	weapon_combat.set_physics_process(true)
	add_to_group("combat_targets")
	combat.sheathed=false
	weapon_combat.sync_rig()
	nameplate.position.y=4.2

func start_return(defeated: bool = false) -> void:
	# Encounter.finish/disengage closes combat before this reset. Never let a
	# return request relocate an opponent during an active fight.
	if is_instance_valid(encounter) and encounter.active: return
	var departure := global_position
	controls.stop()
	combat.sheathed=true
	# Shared respawn clears phase, attacks, charge, stagger, velocity, fall/footing
	# history and temporary Sky Jump geometry, using the exact global home point.
	super.respawn()
	visual.rotation=Vector3.ZERO
	visual.rebase_after_phase()
	controls.behavior="resting"
	remove_from_group("combat_targets")
	_rest()
	if defeated:
		state=&"defeated"
		_transition=3.0
	scarf.advance(0)
	if departure.distance_squared_to(home_point)>.01:
		dodge.trace(departure,false)
		dodge.trace(home_point,true)

func _rest() -> void:
	state=&"resting"
	_transition=0
	rest_weight=1
	_set_standing(false)
	if rest_visual.hat.get_parent()!=rest_visual.head_anchor:
		rest_visual.hat.reparent(rest_visual.head_anchor,false)
	scarf.anchor=rest_visual.scarf_anchor
	_mount_sword(true)
	visual.hide()
	rest_visual.show()
	weapon_combat.set_physics_process(false)
	nameplate.position.y=3.3

func _mount_sword(resting: bool) -> void:
	# Reuse the equipped model: no second sword, hurtbox or weapon controller.
	var anchor: Node3D=rest_visual.sword_anchor if resting else visual.pelvis
	if _sheathed_sword.get_parent()!=anchor: _sheathed_sword.reparent(anchor,false)
	_sheathed_sword.transform=_sword_mount
	# Lift the tip clear of the ground alongside the seated left hip.
	if resting: _sheathed_sword.rotation.x=.20

func _physics_process(delta: float) -> void:
	if state==&"resting": return
	if state==&"defeated":
		_transition-=delta
		if _transition<=0:
			_rest()
		return
	if state==&"rising":
		_transition=maxf(0,_transition-delta)
		rest_weight=_transition/.55
		if _transition==0:
			state=&"fighting"
			controls.start()
	super._physics_process(delta)

func _process(delta: float) -> void:
	_pose_clock+=delta
	if not rest_visual.visible or _pose_clock<1.0/30: return
	var camera := get_viewport().get_camera_3d()
	if is_instance_valid(camera) and camera.global_position.distance_squared_to(global_position)>22500: return
	rest_visual.animate(_pose_clock,0,false)
	_pose_clock=0

func combat_point() -> Vector3: return global_position+Vector3.UP*(1.4 if state==&"resting" else 1.85)
func combat_name() -> String: return "KYREN"
func can_attack_target(target: Node) -> bool:
	return is_instance_valid(encounter) and encounter.active and encounter.has_authority() and target==opponent

func receive_hit(amount: float, source: Vector3, attacker: Node = null, incoming: Dictionary = {}) -> float:
	if not is_instance_valid(encounter) or not encounter.has_authority() or attacker!=opponent or amount<=0 or state==&"defeated": return 0
	if not encounter.active and not encounter.start(true): return 0
	var impact_point := combat_point()+Vector3.UP*.6
	var applied := minf(health,super.receive_hit(amount,source,attacker,incoming))
	if applied>0:
		DamageNumber.make_room(get_tree())
		var number := DamageNumber.new()
		number.text="%.1f" % applied
		get_parent().add_child(number)
		number.global_position=impact_point
	return applied

func on_combat_defeat() -> void:
	if is_instance_valid(encounter): encounter.finish(true)

func respawn() -> void:
	# Genuine out-of-world defeat closes the encounter before resetting home.
	if is_instance_valid(encounter) and encounter.active: encounter.finish(true)
	else: start_return()
