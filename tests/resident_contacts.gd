extends RefCounted
## Contact pairs measure real capsule penetration, independent of the nav probe.
static func depth(resident: CharacterBody3D, excluded: Array[RID]) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = resident.body_shape.shape
	query.transform = resident.body_shape.global_transform
	query.collision_mask = 1
	query.exclude = excluded
	var contacts: PackedVector3Array = resident.get_world_3d().direct_space_state.collide_shape(query,8)
	var deepest := 0.0
	for i in range(0,contacts.size(),2): deepest = maxf(deepest,contacts[i].distance_to(contacts[i+1]))
	return deepest
