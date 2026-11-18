extends Node
## Destination data only; Player retains the shared death/drop/recovery sequence.
var glyphs: Node
var active_location: StringName = &"overworld"
var destinations: Dictionary = {}
var minimum_heights: Dictionary = {}
var floor_label := "ENTRY HUB"

func minimum_height() -> float:
	return float(minimum_heights.get(active_location,-12.0))

func resolve_spawn(fallback: Vector3) -> Vector3:
	if is_instance_valid(glyphs):
		var chosen: Variant=glyphs.resolve_spawn()
		if chosen is Vector3: return chosen
	var anchor: Node3D = destinations.get(active_location)
	return anchor.global_position if is_instance_valid(anchor) else fallback
