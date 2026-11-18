extends Marker3D
## Reusable, explicitly activated doorway; no automatic proximity teleport.
var location_id: StringName = &"overworld"
var destination_id: StringName
var prompt := "Enter"
@export var interaction_distance := 3.2

func in_reach(actor: CharacterBody3D) -> bool:
	if absf(actor.global_position.y-global_position.y)>1.8: return false
	if actor.global_position.distance_to(global_position)>interaction_distance: return false
	var query:=PhysicsRayQueryParameters3D.create(actor.combat_point(),global_position+Vector3.UP,1,[actor.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
