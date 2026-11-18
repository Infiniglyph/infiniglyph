extends "res://scripts/weapon_combat.gd"
const Moves = preload("res://scripts/falcon_moves.gd")
const Arrow = preload("res://scripts/pyramid_arrow.gd")
var arrows: Array[Node3D]=[]

func apply_pose(delta: float) -> void:
	super.apply_pose(delta)
	if actor.enemy_kind=="falcon" and active_move.is_empty() and not actor.combat.blocking and not is_staggered():
		rig.orient(Vector3(PI,0,-.08),Vector3(PI,PI,.08))

func move_for(_slot: StringName, action: StringName) -> Dictionary:
	return Moves.move(actor.enemy_kind,action)

func charged_move(slot: StringName, action: StringName, _strength: float) -> Dictionary:
	return move_for(slot,action)

func cancel() -> void:
	for arrow in arrows.duplicate():
		if is_instance_valid(arrow): arrow.reclaim()
	arrows.clear()
	super.cancel()

func drive_velocity(current: Vector2) -> Vector2:
	if active_move.get("dive",false) and elapsed>=.48 and elapsed<1 and not actor.is_on_floor() and not is_staggered(): actor.velocity.y=minf(actor.velocity.y,-11)
	return super.drive_velocity(current)

func strike(pulse: int = -1) -> void:
	if not active_move.get("arrow",false):
		super.strike(pulse)
		return
	if is_staggered() or arrows.size()>=2: return
	var point: Vector3=rig.right_hand.global_position
	var aim: Vector3=actor.opponent.combat_point()
	var arrow:=Arrow.new()
	arrow.combat=self
	arrow.actor=actor
	arrow.move=active_move.duplicate(true)
	arrow.move.attack_serial=attack_serial
	arrow.direction=(aim-point).normalized()
	actor.get_parent().add_child(arrow)
	arrow.global_position=point
	arrows.append(arrow)
