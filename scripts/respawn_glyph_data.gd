extends RefCounted
## Two owned destinations, represented only by bounded JSON data.
const TYPES := {&"respawn_glyph":"respawn",&"home_respawn_glyph":"home"}

static func valid(points: Variant) -> bool:
	if not points is Dictionary or points.size()>2: return false
	for key: Variant in points:
		if key not in ["respawn","home"]: return false
		var record: Variant=points[key]
		if not record is Dictionary or record.size()!=5: return false
		if not record.get("location") is String or record.location.is_empty() or record.location.length()>128: return false
		if not record.get("position") is Array or record.position.size()!=3: return false
		for number: Variant in record.position:
			if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number))>1000000: return false
		for angle: String in ["yaw","camera_yaw","camera_pitch"]:
			var number: Variant=record.get(angle)
			if not (number is float or number is int) or not is_finite(float(number)): return false
		if absf(float(record.camera_pitch))>1.2 or absf(float(record.yaw))>PI+.00001 or absf(float(record.camera_yaw))>PI+.00001: return false
	return true

static func point(record: Dictionary) -> Vector3:
	return Vector3(record.position[0],record.position[1],record.position[2])
