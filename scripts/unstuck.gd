extends Node
## Local recovery uses the real player capsule and supported walkable ground.
var actor: CharacterBody3D
var last_safe := Vector3.ZERO
var has_safe := false
var _sample_clock := 0.0
var _body: CollisionShape3D

func _ready() -> void:
	for child: Node in actor.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			_body = child
			break

func reset_history() -> void:
	has_safe = false
	_sample_clock = 0

func query_at(point: Vector3, margin: float = 0.005) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body.shape
	var transform := actor.global_transform
	transform.origin = point
	query.transform = transform*_body.transform
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	query.margin = margin
	return query

func clear_at(point: Vector3) -> bool:
	return actor.get_world_3d().direct_space_state.intersect_shape(query_at(point),1).is_empty()

func broad_support(point: Vector3) -> bool:
	var space := actor.get_world_3d().direct_space_state
	var lowest := INF
	var highest := -INF
	# Thin rails and post tops must never become a recovery destination.
	for offset: Vector3 in [Vector3.ZERO,Vector3(0.32,0,0),Vector3(-0.32,0,0),Vector3(0,0,0.32),Vector3(0,0,-0.32)]:
		var ray := PhysicsRayQueryParameters3D.create(point+offset+Vector3.UP*0.14,point+offset-Vector3.UP*0.30,1,[actor.get_rid()])
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<0.7 or hit.collider is CharacterBody3D: return false
		lowest = minf(lowest,hit.position.y)
		highest = maxf(highest,hit.position.y)
	return highest-lowest<0.19

func remember_safe(delta: float) -> void:
	_sample_clock -= delta
	if _sample_clock>0 or not actor.is_on_floor() or actor.dodge.active: return
	_sample_clock = 0.25
	var point := actor.global_position+Vector3.UP*0.08
	if clear_at(point) and broad_support(point):
		last_safe = point
		has_safe = true

func needs_recovery() -> bool:
	if not clear_at(actor.global_position+Vector3.UP*0.08): return true
	if actor.is_on_floor() and not broad_support(actor.global_position+Vector3.UP*0.065): return true
	# A capsule resting against a bar can be trapped without penetrating it.
	# This narrow tolerance also catches wedges at wall/railing corners.
	if actor.velocity.length()<0.8:
		return not actor.get_world_3d().direct_space_state.intersect_shape(query_at(actor.global_position+Vector3.UP*0.08,0.05),1).is_empty()
	return false

func supported_candidate(point: Vector3, up: float = 0.65, down: float = 2.6) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*up,point-Vector3.UP*down,1,[actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<0.7 or hit.collider is CharacterBody3D: return {}
	var candidate: Vector3 = hit.position+Vector3.UP*0.045
	if not clear_at(candidate) or not broad_support(candidate): return {}
	return {"point":candidate}

func recover() -> Dictionary:
	var actions: Node = actor.get("world_actions")
	if is_instance_valid(actions) and actions.attached():
		return {"ok":actions.leave(),"message":"Left the seat." if not actions.attached() else "Clear an exit before leaving."}
	if _body == null or actor.health<=0: return {"ok":false,"message":"Recovery is unavailable right now."}
	if not needs_recovery(): return {"ok":false,"message":"You have room to move. Unstick is for blocked positions."}
	var origin := actor.global_position
	var destination := Vector3.ZERO
	var found := false
	var used_history := false
	var best := INF
	for radius: float in [0.55,0.85,1.2,1.7,2.4,3.2]:
		for i in range(16):
			var angle := i*TAU/16
			var result := supported_candidate(origin+Vector3(cos(angle),0,sin(angle))*radius)
			if result.is_empty(): continue
			var point: Vector3 = result.point
			var cost := origin.distance_to(point)+absf(point.y-origin.y)*0.3
			if cost<best:
				best = cost
				destination = point
				found = true
		if found: break
	if not found and has_safe and clear_at(last_safe) and broad_support(last_safe):
		destination = last_safe
		found = true
		used_history = true
	if not found: return {"ok":false,"message":"No safe space found nearby. Try a different direction."}
	# Recovery is a relocation, never a respawn: health, gear, ownership and
	# forced combat recovery remain unchanged, with no death/drop callbacks.
	actor.dodge.cancel()
	actor.weapon_combat.cancel()
	actor.combat.reset()
	actor._jump_after_dodge = false
	actor.velocity = Vector3.ZERO
	actor.global_position = destination
	actor.fall_damage.reset()
	actor.visual.clear_combat_pose()
	actor.visual.rebase_after_phase()
	actor.visual._initialized = false
	actor.camera_rig.reset_follow()
	last_safe = destination
	has_safe = true
	return {"ok":true,"message":"Returned to your last clear footing." if used_history else "Moved to nearby clear ground.","from":origin,"position":destination}
