extends Node
## Local map integration hook. Markers describe unclaimed death losses only.
signal changed
var markers: Dictionary = {}
var _source_ids: Dictionary = {}
var _sources: Dictionary = {}

func track(pickup: Node3D, owner_id: String, item_instance_id: String) -> void:
	if owner_id.is_empty() or not is_instance_valid(pickup): return
	var key: String = pickup.pickup_id
	markers[key] = {"pickup_id":key,"owner_id":owner_id,"item_instance_id":item_instance_id,"world_position":pickup.global_position}
	_source_ids[key] = pickup.get_instance_id()
	_sources[key] = weakref(pickup)
	pickup.tree_exited.connect(_source_exited.bind(key,pickup.get_instance_id()),CONNECT_ONE_SHOT)
	changed.emit()

func remove(pickup_id: String) -> void:
	if not markers.has(pickup_id): return
	markers.erase(pickup_id)
	_source_ids.erase(pickup_id)
	_sources.erase(pickup_id)
	changed.emit()

func for_owner(owner_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker: Dictionary in markers.values():
		if marker.owner_id == owner_id:
			var source: Node3D = _sources[marker.pickup_id].get_ref() if _sources.has(marker.pickup_id) else null
			if is_instance_valid(source): marker.world_position = source.global_position
			result.append(marker.duplicate(true))
	return result

func clear() -> void:
	if markers.is_empty(): return
	markers.clear()
	_source_ids.clear()
	_sources.clear()
	changed.emit()

func _source_exited(pickup_id: String, source_id: int) -> void:
	# An old node exiting after atomic checkpoint replacement must not erase a
	# new marker which legitimately uses the same persisted pickup identity.
	if _source_ids.get(pickup_id,0) == source_id: remove(pickup_id)
