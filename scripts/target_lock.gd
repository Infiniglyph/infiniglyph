extends Node3D
## Target selection and facing only; the player still owns acceleration/velocity.
const Neon = preload("res://scripts/neon.gd")
const RANGE := 32.0
const OBSTRUCTION_GRACE := 0.35
signal changed
var actor: CharacterBody3D
var opponent: Node3D
var _obstructed := 0.0
var marker: MeshInstance3D
var show_marker := true

func _ready() -> void:
	name = "TargetLock"
	Neon.prepare()
	var points := PackedVector3Array()
	for side in [-1.0,1.0]:
		for height in [-1.0,1.0]:
			var corner := Vector3(side*0.43,height*0.48,0)
			points.append_array([corner,corner-Vector3(side*0.16,0,0),corner,corner-Vector3(0,height*0.16,0)])
	marker = Neon.lines(points,Neon.material(Color(0.75,1,1)))
	add_child(marker)
	marker.top_level = true
	marker.visible = false

func is_locked() -> bool:
	return is_instance_valid(opponent) and not opponent.is_queued_for_deletion()

func point(target: Node3D) -> Vector3:
	return target.combat_point() if target.has_method("combat_point") else target.global_position+Vector3.UP*0.95

func facing() -> Vector3:
	var direction: Vector3 = point(opponent)-actor.global_position if is_locked() else actor.visual.global_basis.z
	direction.y = 0
	return direction.normalized() if direction.length_squared()>0.001 else actor.visual.global_basis.z.normalized()

func movement(input: Vector2) -> Vector3:
	var forward := facing()
	return forward.cross(Vector3.UP)*input.x-forward*input.y

func living(target: Node3D) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or target == actor: return false
	if not target.is_visible_in_tree(): return false
	if not target.is_in_group("combat_targets") or not target.has_method("receive_hit"): return false
	if actor.has_method("can_attack_target") and not actor.can_attack_target(target): return false
	var hp = target.get("health")
	return hp == null or float(hp)>0

func in_range(target: Node3D) -> bool:
	return actor.global_position.distance_to(target.global_position)<=RANGE

func visible_target(target: Node3D) -> bool:
	var excluded: Array[RID] = [actor.get_rid()]
	if target is CollisionObject3D: excluded.append(target.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*1.35,point(target),1,excluded)
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func screen_point(target: Node3D) -> Vector2:
	return actor.camera_rig.camera.unproject_position(point(target))/get_viewport().get_visible_rect().size

func selectable(target: Node3D) -> bool:
	if not living(target) or not in_range(target): return false
	var camera: Camera3D = actor.camera_rig.camera
	if camera.is_position_behind(point(target)): return false
	var screen := screen_point(target)
	if screen.x<0 or screen.x>1 or screen.y<0 or screen.y>1: return false
	return visible_target(target)

func select(target: Node3D) -> void:
	opponent = target
	_obstructed = 0
	marker.visible = show_marker and is_locked()
	changed.emit()

func clear() -> void:
	if opponent != null or marker.visible: select(null)

func toggle() -> void:
	if is_locked():
		clear()
		return
	var best: Node3D
	var score := INF
	for candidate: Node3D in get_tree().get_nodes_in_group("combat_targets"):
		if not selectable(candidate): continue
		var rank := screen_point(candidate).distance_to(Vector2(0.5,0.5))+actor.global_position.distance_to(candidate.global_position)/RANGE*0.12
		if rank<score:
			best = candidate
			score = rank
	select(best)

func switch_target(direction: Vector2) -> void:
	if not is_locked() or direction.is_zero_approx(): return
	var origin := screen_point(opponent)
	var best: Node3D
	var score := INF
	for candidate: Node3D in get_tree().get_nodes_in_group("combat_targets"):
		if candidate == opponent or not selectable(candidate): continue
		var offset := screen_point(candidate)-origin
		if offset.length()<0.015: continue
		var alignment := offset.normalized().dot(direction.normalized())
		if alignment<0.55: continue
		var rank := offset.length()/(alignment*alignment)
		if rank<score:
			best = candidate
			score = rank
	if best != null: select(best)

func update(delta: float, controls: Node) -> void:
	# Consume each press/flick once. Test and replay inputs may omit lock commands.
	if controls.has_method("consume_lock_requests"):
		for request: Vector2 in controls.consume_lock_requests():
			if request.is_zero_approx(): toggle()
			else: switch_target(request)
	if is_locked():
		if not living(opponent) or not in_range(opponent): clear()
		else:
			_obstructed = 0 if visible_target(opponent) else _obstructed+delta
			if _obstructed>=OBSTRUCTION_GRACE: clear()
	elif opponent != null: clear()
	marker.visible = show_marker and is_locked() and _obstructed == 0
	if marker.visible:
		marker.global_position = point(opponent)
		marker.global_basis = actor.camera_rig.camera.global_basis

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(marker): clear()
