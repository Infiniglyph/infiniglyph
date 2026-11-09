extends "res://scripts/weapon_combat.gd"
## Presentation adapter only. All impact/guard/parry/exhaustion resolution is inherited.
class GriffinWeight extends "res://scripts/combat_body.gd":
	func begin(facing: Vector3) -> void:
		_stance_origin = actor.global_position
		_stance_basis = Basis(Vector3.UP,atan2(facing.x,facing.z))
		phase_label = "load"
		support_feet.clear()
		for foot: Vector3 in actor.visual.foot_points():
			var contact := floor_contact(foot)
			if not contact.is_empty(): support_feet[support_feet.size()] = contact

func _build_presentation() -> void:
	body = GriffinWeight.new()
	body.actor = actor
	rig = actor.visual
	trail = Trail.new()
	actor.add_child(trail)
	trail.top_level = true
	trail.global_transform = Transform3D.IDENTITY

func loadout(_slot: StringName) -> Dictionary:
	return {"id":&"griffin","name":"Talons and Wings","short":"Greefer","guard":0.70,"color":Color(0.88,0.08,1)}

func aim_direction() -> Vector3:
	return actor.facing

func strike(pulse: int = -1) -> void:
	if actor.encounter.has_authority(): super.strike(pulse)

func _physics_process(delta: float) -> void:
	if actor.encounter.has_authority(): super._physics_process(delta)

func apply_pose(delta: float) -> void:
	if visual_frozen(): return
	var phase := "rest"
	if not active_move.is_empty(): phase = "load" if elapsed<active_move.windup else "follow-through"
	body.phase_label = phase
	actor.visual.animate(delta,actor,active_move,elapsed,recoil_amount())
