extends RefCounted
## Shared bounded, world-space trail storage and end-of-life fade. Geometry and
## contact shape remain specific to a vehicle wall or three-dimensional writing.
static func expire(segments: Array[Dictionary], time: float, lifetime: float) -> bool:
	var changed := false
	while not segments.is_empty() and time-float(segments[0].born)>=lifetime:
		segments.pop_front()
		changed = true
	return changed

static func append(segments: Array[Dictionary], segment: Dictionary, limit: int) -> void:
	while segments.size()>=maxi(1,limit): segments.pop_front()
	segments.append(segment)

static func opacity(born: float, time: float, lifetime: float, fade: float) -> float:
	return clampf((lifetime-(time-born))/maxf(.001,fade),0,1)
