extends "res://scripts/falcon_combat.gd"
const DepthMoves = preload("res://scripts/pyramid_depth_moves.gd")
const Field = preload("res://scripts/pyramid_field.gd")
var fields: Array[Node3D]=[]

func move_for(_slot: StringName, action: StringName) -> Dictionary: return DepthMoves.move(actor.enemy_kind,action)

func cancel() -> void:
	for field in fields.duplicate():
		if is_instance_valid(field): field.reclaim()
	fields.clear()
	super.cancel()

func strike(pulse: int=-1) -> void:
	if active_move.is_empty() or is_staggered(): return
	if active_move.has("ritual"):
		actor.encounter.ritual(actor,active_move.ritual)
		return
	if active_move.has("field"):
		if fields.size()>=3 or get_tree().get_nodes_in_group("pyramid_fields").size()>=8: return
		var field:=Field.new()
		field.actor=actor
		field.combat=self
		field.move=active_move.duplicate(true)
		field.move.attack_serial=attack_serial
		field.radius=float(active_move.field_radius)
		field.delay=float(active_move.field_delay)
		var at: Vector3=actor.opponent.global_position if actor.enemy_kind in ["ibis","acolyte","skeletal_scribe","charmer"] else actor.global_position
		if at.distance_to(actor.global_position)>16: at=actor.global_position+aim_direction()*10
		actor.get_parent().add_child(field)
		field.global_position=Vector3(at.x,actor.floor_y+.04,at.z)
		fields.append(field)
		return
	if active_move.get("glyph_volley",false):
		if arrows.size()>=6: return
		var venom: bool=active_move.get("venom_projectile",false)
		for spread: float in ([0.0] if venom else [-.14,0.0,.14]):
			var arrow:=Arrow.new()
			arrow.actor=actor
			arrow.combat=self
			arrow.move=active_move.duplicate(true)
			arrow.move.attack_serial=attack_serial
			arrow.glyph=true
			arrow.venom=venom
			arrow.speed=12.0
			var at: Vector3=actor.combat_point()+Vector3.UP*.1
			arrow.direction=(actor.opponent.combat_point()-at).normalized().rotated(Vector3.UP,spread)
			actor.get_parent().add_child(arrow)
			arrow.global_position=at
			arrows.append(arrow)
		return
	super.strike(pulse)

func damage_multiplier(speed: float) -> float:
	var rally: float=1.22 if actor.support_time>0 else 1.0
	if actor.traits.get("champion",false) and actor.encounter.champions_alive()<3: rally*=1.18
	return super.damage_multiplier(speed)*rally

func receive_hit(amount: float, source: Vector3, attacker: Node=null, incoming: Dictionary={}) -> float:
	var protection:=.55 if actor.ward_time>0 else .85 if actor.support_time>0 else 1.0
	return super.receive_hit(amount*protection,source,attacker,incoming)

func effective_fortitude() -> float:
	return super.effective_fortitude()+(.8 if actor.enemy_kind=="crocodile" else 0)
