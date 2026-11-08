extends "res://scripts/player.gd"
## A full player actor driven by an input brain, sharing every move/defense rule.
const Brain = preload("res://scripts/sparring_brain.gd")
const Neon = preload("res://scripts/neon.gd")
const DamageNumber = preload("res://scripts/damage_number.gd")
class AimFrame extends Node3D:
	var yaw := 0.0
	var camera: Camera3D
	func reset_follow() -> void: pass
var opponent: CharacterBody3D
var home := Vector3(14,0.12,-35)
var label: Label3D
var light: OmniLight3D
var body_ink: StandardMaterial3D

func _ready() -> void:
	live_motion_retrieval = false
	inventory_owner_id = "ember"
	spawn = home
	controls = Brain.new()
	controls.actor = self
	controls.opponent = opponent
	add_child(controls)
	camera_rig = AimFrame.new()
	camera_rig.camera = opponent.camera_rig.camera
	add_child(camera_rig)
	super._ready()
	name = "Ember"
	target_lock.show_marker = false
	body_ink = Neon.material(Neon.ORANGE)
	dodge.set_tint(Neon.ORANGE)
	for geometry: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
		if geometry.mesh.surface_get_material(0) == Neon.body: geometry.material_override = body_ink
	# The dodge caches restoration materials. Capture the orange body before
	# return_home/cancel can restore the cyan defaults cached during super._ready.
	dodge.cache_geometry()
	# Orange marks a real light source here as it does on the street fixtures.
	light = OmniLight3D.new()
	light.position.y = 1.25
	light.light_color = Neon.ORANGE
	light.light_energy = 0.9
	light.omni_range = 3.5
	add_child(light)
	label = Label3D.new()
	label.position.y = 2.3
	label.font_size = 32
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1,0.6,0.28)
	add_child(label)
	return_home()

func return_home() -> void:
	controls.stop()
	dodge.cancel()
	target_lock.clear()
	combat.reset()
	weapon_combat.reset()
	combat.selected_slot = &"right"
	combat.sheathed = true
	weapon_combat.sync_rig()
	remove_from_group("combat_targets")
	set_collision_layer_value(2,false)
	position = home
	velocity = Vector3.ZERO
	fall_damage.reset()
	visual.rotation.y = -PI*0.5
	visual.rebase_after_phase()
	air_step_count = 0
	_jump_after_dodge = false
	for step in _glass_steps:
		if is_instance_valid(step): step.queue_free()
	_glass_steps.clear()
	label.text = "EMBER\nSPARRING PARTNER"
	weapon_combat.status = "Ready"

func begin_duel() -> void:
	add_to_group("combat_targets")
	set_collision_layer_value(2,true)
	combat.sheathed = false
	weapon_combat.sync_rig()
	weapon_combat.health = weapon_combat.max_health
	target_lock.select(opponent)
	controls.start()
	label.text = "EMBER\nSPARRING"

func can_attack_target(target: Node) -> bool:
	return is_instance_valid(sparring_duel) and sparring_duel.active and target == opponent

func combat_name() -> String: return "EMBER"

func on_parried(source: Vector3) -> void:
	super.on_parried(source)

func receive_hit(amount: float, source: Vector3, attacker: Node = null, incoming: Dictionary = {}) -> float:
	if not is_instance_valid(sparring_duel) or not sparring_duel.active: return 0
	var before := health
	var applied := minf(before,super.receive_hit(amount,source,attacker,incoming))
	if applied>0 and sparring_duel.active:
		DamageNumber.make_room(get_tree())
		var number := DamageNumber.new()
		number.text = "%.1f" % applied
		get_parent().add_child(number)
		number.global_position = combat_point()+Vector3.UP*1.75
	return applied

func on_combat_defeat() -> void:
	if is_instance_valid(sparring_duel): sparring_duel.finish(true)

func respawn() -> void:
	if is_instance_valid(sparring_duel) and sparring_duel.active: sparring_duel.finish(true,"Ember yielded after leaving the arena.")
	else: return_home()
