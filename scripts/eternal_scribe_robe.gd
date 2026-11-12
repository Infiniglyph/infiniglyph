extends Node3D
## Adapted from The Infinite Library's Eternal Scribe robes. Standalone cosmetic
## geometry and pooled inscriptions; no Library commands, services or saves.

const LineGeometryScript = preload("res://scripts/robe_lines.gd")

const ROBE_ID := "eternal_scribe"
const TRAIL_SPECK_COUNT := 12
const TRAIL_SYMBOL_COUNT := 9
const SYMBOL_VARIANT_COUNT := 8
const INSCRIPTION_CYCLE_SECONDS := 4.8
const SILVER := Color("d8e4ee")
const SILVER_BLUE := Color("9feaff")
const CYAN := Color("35cfff")
const VIOLET := Color("d97bff")
const GOLD := Color("ffc95c")
const FABRIC := Color("080b13")
const FABRIC_HIGHLIGHT := Color("111827")
const JACKET_LEVELS := [Vector3(0.165, -0.49, 0.105), Vector3(0.18, -0.31, 0.125), Vector3(0.22, -0.15, 0.14), Vector3(0.245, 0.03, 0.145)]

var _traveler: CharacterBody3D
var _figure: Node3D
var _upper_body: Node3D
var _back_cloak: Node3D
var _left_front_panel: Node3D
var _right_front_panel: Node3D
var _waist: Node3D
var _tails: Array[Node3D] = []
var _sleeves: Array[Dictionary] = []
var _external_pieces: Array[Node3D] = []
var _glyph_nodes: Array[Node3D] = []
var _glyph_base_positions: Array[Vector3] = []
var _glyph_base_scales: Array[float] = []
var _glyph_phases: Array[float] = []
var _glyph_colors: Array[Color] = []
var _glyph_cycles: Array[int] = []
var _glyph_surfaces: Array[Dictionary] = []
var _upper_inscription_count := 0
var _inscription_generation_count := 0
var _front_inscription_count := 0
var _trail_instance: MultiMeshInstance3D
var _trail_phases: Array[float] = []
var _trail_symbol_root: Node3D
var _trail_symbol_nodes: Array[Node3D] = []
var _trail_symbol_cycles: Array[int] = []
var _trail_symbol_colors: Array[Color] = []
var _equipped := false
var _configured := false
var _elapsed := 0.0
var _flow_amount := 0.0
var _turn_amount := 0.0
var _last_figure_yaw := 0.0
var _mounted_kind := ""
var _symbol_meshes: Dictionary = {}


func configure(
	traveler: CharacterBody3D,
	figure: Node3D,
	upper_body: Node3D,
	left_arm: Node3D,
	right_arm: Node3D
) -> bool:
	if _configured:
		return true
	if (
		not is_instance_valid(traveler)
		or not is_instance_valid(figure)
		or not is_instance_valid(upper_body)
		or not is_instance_valid(left_arm)
		or not is_instance_valid(right_arm)
	):
		return false
	_traveler = traveler
	_figure = figure
	_upper_body = upper_body
	_build_body_layers()
	_build_hood()
	_build_sleeve(left_arm, "LeftRobeSleeve", -1.0)
	_build_sleeve(right_arm, "RightRobeSleeve", 1.0)
	_build_inscriptions()
	_build_q_gnat_trail()
	_build_mathematical_symbol_trail()
	_configured = true
	process_priority = 40
	set_equipped(false)
	return true


func set_equipped(value: bool) -> void:
	_equipped = value
	visible = value
	for piece in _external_pieces:
		if is_instance_valid(piece):
			piece.visible = value
	if is_instance_valid(_trail_instance):
		_trail_instance.visible = false
	if is_instance_valid(_trail_symbol_root):
		_trail_symbol_root.visible = false
	set_process(value)
	if not value:
		_flow_amount = 0.0
		_turn_amount = 0.0
	else: _last_figure_yaw = _figure.global_rotation.y


func is_equipped() -> bool:
	return _equipped


func get_robe_id() -> String:
	return ROBE_ID


func get_flow_amount() -> float:
	return _flow_amount


func get_trail_speck_count() -> int:
	if not is_instance_valid(_trail_instance) or _trail_instance.multimesh == null:
		return 0
	return _trail_instance.multimesh.instance_count


func get_trail_symbol_count() -> int:
	return _trail_symbol_nodes.size()


func get_inscription_generation_count() -> int:
	return _inscription_generation_count


func get_front_inscription_count() -> int:
	return _front_inscription_count


func get_upper_inscription_count() -> int:
	return _upper_inscription_count


func has_back_sigil() -> bool:
	return find_child("InfiniglyphBackSigil", true, false) != null


func get_external_piece_count() -> int:
	return _external_pieces.size()


func _process(delta: float) -> void:
	if not _equipped or not is_instance_valid(_traveler):
		return
	# PhaseDodge caches the exact mesh instances it fades. Do not replace
	# inscription meshes until the phase finishes and restores those materials.
	if _traveler.dodge.active:
		_flow_amount = 1.0
		return
	_elapsed += delta
	var motion_velocity := _get_visual_velocity()
	var horizontal_speed := Vector2(motion_velocity.x, motion_velocity.z).length()
	var dash_boost := 1.0 if _traveler.boost_active else 0.0
	var ride_boost := 0.46 if is_instance_valid(_traveler.world_actions) and is_instance_valid(_traveler.world_actions.vehicle) else 0.0
	var airborne_boost := 0.18 if not _traveler.is_on_floor() else 0.0
	var movement_flow := clampf(horizontal_speed / 10.2, 0.0, 1.0) * 0.72
	var target_flow := clampf(
		maxf(movement_flow + airborne_boost, maxf(dash_boost, ride_boost)),
		0.0,
		1.0
	)
	_flow_amount = move_toward(_flow_amount, target_flow, delta * 3.8)

	var figure_yaw := _figure.global_rotation.y if is_instance_valid(_figure) else 0.0
	var yaw_delta := wrapf(figure_yaw - _last_figure_yaw, -PI, PI)
	_last_figure_yaw = figure_yaw
	var target_turn := clampf(yaw_delta / maxf(delta, 0.001) * 0.08, -0.32, 0.32)
	_turn_amount = move_toward(_turn_amount, target_turn, delta * 3.2)

	_fit_tails(delta)
	_update_living_inscriptions()
	_update_trail(motion_velocity)


func _build_body_layers() -> void:
	_back_cloak = Node3D.new()
	_back_cloak.name = "FittedScholarJacket"
	_back_cloak.position.y = 1.43
	add_child(_back_cloak)
	# Open elliptical shell: a narrow waist, shaped chest and real side depth.
	# The front slit exposes the light being rather than covering it with a slab.
	var levels := JACKET_LEVELS
	var vertices := PackedVector3Array()
	for row in range(levels.size() - 1):
		for segment in range(12):
			var angle_a := lerpf(-PI + 0.30, PI - 0.30, float(segment) / 12.0)
			var angle_b := lerpf(-PI + 0.30, PI - 0.30, float(segment + 1) / 12.0)
			var a := _jacket_point(levels[row], angle_a)
			var b := _jacket_point(levels[row], angle_b)
			var c := _jacket_point(levels[row + 1], angle_b)
			var d := _jacket_point(levels[row + 1], angle_a)
			vertices.append_array(PackedVector3Array([a, b, c, a, c, d]))
	_back_cloak.add_child(_make_fabric_surface("TailoredTorsoFabric", vertices, FABRIC))
	for level in [levels[0], levels[-1]]:
		var rim := PackedVector3Array()
		for segment in range(13):
			rim.append(_jacket_point(level, lerpf(-PI + 0.30, PI - 0.30, float(segment) / 12.0)))
		_back_cloak.add_child(LineGeometryScript.polyline(rim, SILVER))
	for angle in [-PI + 0.30, -PI * 0.5, 0.0, PI * 0.5, PI - 0.30]:
		var seam := PackedVector3Array()
		for level in levels:
			seam.append(_jacket_point(level, angle) * Vector3(1.015, 1.0, 1.015))
		_back_cloak.add_child(LineGeometryScript.polyline(seam, CYAN if absf(angle) > 2.0 else SILVER_BLUE))
	for side in [-1.0, 1.0]:
		var lapel := PackedVector3Array([
			Vector3(side * 0.065, 1.49, -0.15), Vector3(side * 0.125, 1.565, -0.055),
			Vector3(side * 0.18, 1.46, -0.12), Vector3(side * 0.07, 1.255, -0.15),
		])
		var collar := Node3D.new()
		collar.name = "RaisedLapelLeft" if side < 0.0 else "RaisedLapelRight"
		add_child(collar)
		collar.add_child(_make_fabric_surface("LapelFabric", PackedVector3Array([
			lapel[0], lapel[1], lapel[2], lapel[0], lapel[2], lapel[3],
		]), FABRIC_HIGHLIGHT))
		collar.add_child(LineGeometryScript.polyline(lapel, SILVER, true))
		collar.add_child(LineGeometryScript.polyline(PackedVector3Array([
			Vector3(side * 0.18, 1.46, -0.12), Vector3(side * 0.22, 1.475, 0.0), Vector3(side * 0.18, 1.46, 0.12),
		]), SILVER_BLUE))

	_left_front_panel = _build_tail("LeftFrontTail", -1.0, true)
	_right_front_panel = _build_tail("RightFrontTail", 1.0, true)
	_build_tail("LeftRearTail", -1.0, false)
	_build_tail("RightRearTail", 1.0, false)
	_build_belt_and_tome()


func _jacket_point(level: Vector3, angle: float) -> Vector3:
	return Vector3(sin(angle) * level.x, level.y, cos(angle) * level.z)


func _build_tail(label: String, side: float, front: bool) -> Node3D:
	var panel := Node3D.new()
	panel.name = label
	panel.position.y = 0.946
	panel.set_meta("side", side)
	panel.set_meta("front", front)
	add_child(panel)
	_tails.append(panel)
	var facing := -1.0 if front else 1.0
	var points := PackedVector3Array()
	for row in range(3):
		for column in range(3):
			var amount := float(row) / 2.0
			var top_x: float = [0.045, 0.115, 0.185][column]
			var hem_x: float = [0.085, 0.205, 0.315][column]
			var hem_y: float = [-0.69, -0.79, -0.71][column]
			var top_z: float = [0.132, 0.115, 0.018][column]
			var hem_z: float = [0.15, 0.135, 0.012][column]
			points.append(Vector3(side * lerpf(top_x, hem_x, amount), amount * hem_y, facing * lerpf(top_z, hem_z, amount)))
	var vertices := PackedVector3Array()
	for row in range(2):
		for column in range(2):
			var i := row * 3 + column
			vertices.append_array(PackedVector3Array([points[i], points[i + 1], points[i + 4], points[i], points[i + 4], points[i + 3]]))
	panel.add_child(_make_fabric_surface("Fabric", vertices, FABRIC))
	panel.add_child(LineGeometryScript.polyline(PackedVector3Array([
		points[0], points[1], points[2], points[5], points[8], points[7], points[6], points[3],
	]), SILVER, true))
	panel.add_child(LineGeometryScript.polyline(PackedVector3Array([points[1], points[4], points[7]]), SILVER_BLUE))
	return panel


func _build_belt_and_tome() -> void:
	_waist = Node3D.new()
	_waist.name = "ScholarBeltAndTome"
	_waist.position.y = 0.946
	add_child(_waist)
	_add_tube(_waist, "Belt", 0.037, -0.037, Vector2(0.192, 0.145), Vector2(0.192, 0.145), FABRIC_HIGHLIGHT)
	var buckle := LineGeometryScript.box(Vector3(0.15, 0.085, 0.026), SILVER)
	buckle.position = Vector3(0.0, 0.0, -0.156)
	_waist.add_child(buckle)
	var buckle_core := LineGeometryScript.box(Vector3(0.064, 0.043, 0.028), CYAN)
	buckle_core.position = buckle.position + Vector3(0.0, 0.0, -0.003)
	_waist.add_child(buckle_core)
	var tome := Node3D.new()
	tome.name = "HipBoundTome"
	tome.position = Vector3(0.235, -0.065, -0.055)
	tome.rotation.z = -0.12
	_waist.add_child(tome)
	var cover := PackedVector3Array([
		Vector3(-0.067, 0.092, -0.03), Vector3(0.067, 0.092, -0.03), Vector3(0.067, -0.092, -0.03),
		Vector3(-0.067, 0.092, -0.03), Vector3(0.067, -0.092, -0.03), Vector3(-0.067, -0.092, -0.03),
	])
	tome.add_child(_make_fabric_surface("TomeCover", cover, FABRIC_HIGHLIGHT))
	tome.add_child(LineGeometryScript.box(Vector3(0.134, 0.184, 0.06), VIOLET))
	tome.add_child(LineGeometryScript.segments(PackedVector3Array([
		Vector3(-0.049, 0.085, -0.033), Vector3(-0.049, -0.085, -0.033),
		Vector3(-0.057, 0.082, 0.01), Vector3(0.056, 0.082, 0.01),
		Vector3(-0.057, 0.082, 0.02), Vector3(0.056, 0.082, 0.02),
	]), SILVER))
	var tome_glyph := _make_living_glyph(2, CYAN)
	tome_glyph.scale = Vector3.ONE * 0.36
	tome_glyph.position.z = -0.034
	tome.add_child(tome_glyph)


func _fit_tails(delta: float) -> void:
	# The jacket follows the animated chest; the belt and split tails follow hips.
	# Rebuild local bases from those anchors, never accumulate global transforms.
	var hip: Node3D = _figure.pelvis
	var source_basis := hip.global_basis * Basis(Vector3.UP, PI)
	var anchor := to_local(hip.global_position)
	var relative_basis := global_basis.inverse() * source_basis
	_waist.position = anchor
	_waist.basis = relative_basis
	var mounted: bool = is_instance_valid(_traveler.world_actions) and is_instance_valid(_traveler.world_actions.vehicle)
	var mounted_kind: String = _traveler.world_actions.vehicle.kind if mounted else ""
	var changed_mount := mounted_kind != _mounted_kind
	_mounted_kind = mounted_kind
	# Long hems are inside the enclosed cabin. Stop drawing those occluded parts
	# rather than letting a hanging tail protrude through its solid floor.
	var stowed := mounted and mounted_kind != "motorcycle"
	var hem_scale := 1.0
	if _traveler.is_on_floor() and not mounted:
		hem_scale = clampf((hip.global_position.y - _traveler.global_position.y - 0.10) / 0.82, 0.42, 1.0)
	for index in range(_tails.size()):
		var tail := _tails[index]
		tail.visible = not stowed
		var side: float = tail.get_meta("side")
		var front: bool = tail.get_meta("front")
		var leg: Node3D = _figure.joints.LeftLeg if side > 0.0 else _figure.joints.RightLeg
		var thigh := source_basis.inverse() * (leg.global_basis * Vector3.DOWN)
		var leg_pitch := atan2(-thigh.z, -thigh.y)
		var pose_pitch := maxf(leg_pitch, 0.0) * 0.82 if front else minf(leg_pitch, 0.0) * 0.72
		var sway := sin(_elapsed * (2.0 + _flow_amount * 4.0) + float(index) * 1.7) * (0.008 + _flow_amount * 0.045)
		var target := Vector3(pose_pitch - _flow_amount * (0.13 if front else 0.28) + sway, -_turn_amount * 0.45, side * (0.018 + _flow_amount * 0.045) + sway * 0.4)
		if mounted:
			# A sport-bike's rear-set pegs leave no room for hems beside the shins.
			# Stream all four behind the saddle, above the rear wheel, even at rest.
			# Speed adds a little lift and flutter, without changing rider geometry.
			target = Vector3(-1.50 - _flow_amount * 0.10 + sway * 0.28, -_turn_amount * 0.15, side * 0.025 + sway * 0.15)
		var previous: Vector3 = tail.get_meta("cloth_angles", Vector3.ZERO)
		var angles := target if changed_mount else previous.lerp(target, 1.0 - exp(-10.0 * delta))
		tail.set_meta("cloth_angles", angles)
		tail.position = anchor
		var cloth_basis := Basis.from_euler(angles).scaled(Vector3(1.0, hem_scale, 1.0))
		if mounted:
			# Rotate about each panel's own belt attachment, keeping the seam on
			# the hips instead of rotating the front tails down through the saddle.
			var seam := Vector3(side * 0.115, 0.0, -0.115 if front else 0.115)
			tail.position += relative_basis * (seam - cloth_basis * seam)
			# Fold the seam over the belt before trailing behind the saddle;
			# a flat waist-height fold would cut through the top of the thigh.
			tail.position += relative_basis * Vector3(0.0, 0.055, 0.0)
		tail.basis = relative_basis * cloth_basis


func _build_hood() -> void:
	var hood := Node3D.new()
	hood.name = "OpenScholarHood"
	add_child(hood)
	var levels := [
		Vector3(0.20, 1.49, 0.015),
		Vector3(0.23, 1.73, 0.015),
		Vector3(0.18, 1.89, 0.025),
		Vector3(0.035, 1.98, 0.05),
	]
	var vertices := PackedVector3Array()
	const SEGMENTS := 10
	for level_index in range(levels.size() - 1):
		for segment in range(SEGMENTS):
			var first_angle := PI * float(segment) / float(SEGMENTS)
			var second_angle := PI * float(segment + 1) / float(SEGMENTS)
			var a := _hood_point(levels[level_index], first_angle)
			var b := _hood_point(levels[level_index], second_angle)
			var c := _hood_point(levels[level_index + 1], second_angle)
			var d := _hood_point(levels[level_index + 1], first_angle)
			vertices.append_array(PackedVector3Array([a, b, c, a, c, d]))
	hood.add_child(_make_fabric_surface("HoodFabric", vertices, FABRIC))
	for angle in [0.0, PI * 0.5, PI]:
		var seam := PackedVector3Array()
		for level in levels:
			seam.append(_hood_point(level, angle) + Vector3(0.0, 0.0, 0.012))
		hood.add_child(LineGeometryScript.polyline(seam, SILVER_BLUE))
	var face_rim := PackedVector3Array([
		_hood_point(levels[0], 0.0), _hood_point(levels[1], 0.0),
		_hood_point(levels[2], 0.0), _hood_point(levels[3], 0.0),
		_hood_point(levels[2], PI), _hood_point(levels[1], PI),
		_hood_point(levels[0], PI),
	])
	hood.add_child(LineGeometryScript.polyline(face_rim, SILVER))


func _hood_point(level: Vector3, angle: float) -> Vector3:
	return Vector3(
		cos(angle) * level.x,
		level.y,
		sin(angle) * level.x + level.z
	)


func _build_sleeve(arm: Node3D, label: String, side: float) -> void:
	# Fitted fabric tubes articulate at the existing elbow. The wrist and hand
	# remain exposed, so the garment does not obscure weapon grips.
	for part in range(2):
		var sleeve := Node3D.new()
		sleeve.name = label+("Upper" if part==0 else "Lower")
		var joint: Node3D = arm if part==0 else arm.get_node("Hinge")
		joint.add_child(sleeve)
		sleeve.rotation.y = PI
		_external_pieces.append(sleeve)
		var length_value := 0.30 if part==0 else 0.25
		_sleeves.append({"node": sleeve, "joint": joint, "length": length_value})
		_add_tube(sleeve, "SleeveFabric", 0.018, -length_value, Vector2(0.069, 0.069), Vector2(0.056, 0.056), FABRIC)
		sleeve.add_child(LineGeometryScript.polyline(PackedVector3Array([
			Vector3(side * 0.072, 0.016, 0.0), Vector3(side * 0.059, -length_value, 0.0),
		]), SILVER_BLUE))
		if part == 0:
			_add_tube(sleeve, "ShoulderCap", 0.04, -0.07, Vector2(0.09, 0.086), Vector2(0.092, 0.082), FABRIC_HIGHLIGHT)
		else:
			_add_tube(sleeve, "SilverCuff", -length_value + 0.045, -length_value, Vector2(0.068, 0.068), Vector2(0.066, 0.066), FABRIC_HIGHLIGHT)


func _add_tube(parent: Node3D, label: String, top: float, bottom: float, upper_radius: Vector2, lower_radius: Vector2, color: Color) -> void:
	var vertices := PackedVector3Array()
	var upper := PackedVector3Array()
	var lower := PackedVector3Array()
	for segment in range(8):
		var angle := TAU * float(segment) / 8.0
		upper.append(Vector3(cos(angle) * upper_radius.x, top, sin(angle) * upper_radius.y))
		lower.append(Vector3(cos(angle) * lower_radius.x, bottom, sin(angle) * lower_radius.y))
	for segment in range(8):
		var next := (segment + 1) % 8
		vertices.append_array(PackedVector3Array([upper[segment], upper[next], lower[next], upper[segment], lower[next], lower[segment]]))
	parent.add_child(_make_fabric_surface(label, vertices, color))
	parent.add_child(LineGeometryScript.polyline(upper, SILVER, true))
	parent.add_child(LineGeometryScript.polyline(lower, SILVER, true))

func _build_inscriptions() -> void:
	_build_back_sigil()
	var colors := [SILVER_BLUE, VIOLET, SILVER, GOLD, CYAN, SILVER_BLUE]
	for panel_index in range(2):
		var tail := _tails[panel_index + 2]
		var side: float = tail.get_meta("side")
		for row in range(3):
			var index := panel_index * 3 + row
			_register_living_inscription(
				tail, "LivingInscription%02d" % (index + 1),
				Vector3(side * (0.12 + float(row) * 0.04), -0.13 - float(row) * 0.235, 0.15),
				colors[index], index, 0.43 + float(row) * 0.025, float(index) * 1.047
			)
	_build_front_inscriptions()
	_build_upper_inscriptions()


func _build_front_inscriptions() -> void:
	var panels := [_left_front_panel, _right_front_panel]
	var sides := [-1.0, 1.0]
	var row_x := [0.12, 0.16, 0.20]
	var row_y := [-0.13, -0.365, -0.60]
	var colors := [SILVER_BLUE, VIOLET, GOLD, CYAN, SILVER, SILVER_BLUE]
	for panel_index in range(panels.size()):
		for row in range(row_y.size()):
			var inscription_index := panel_index * row_y.size() + row
			var side: float = sides[panel_index]
			_register_living_inscription(
				panels[panel_index],
				"Front%sInscription%02d" % [
					"Left" if panel_index == 0 else "Right",
					row + 1,
				],
				Vector3(side * row_x[row], row_y[row], -0.15),
				colors[inscription_index],
				inscription_index + 2,
				0.43 + float(row) * 0.025,
				float(inscription_index + 6) * 0.91
			)
			_front_inscription_count += 1


func _build_upper_inscriptions() -> void:
	var colors := [CYAN, VIOLET, SILVER_BLUE, GOLD, SILVER, CYAN]
	# Flow around the fitted shell, leaving the front opening and central back
	# sigil clear. Each stream stays on the curved cloth as it falls.
	for lane in range(6):
		var angle: float = [-2.48,2.48,-1.50,1.50,-1.15,1.15][lane]
		for row in range(2):
			var index := lane*2+row
			_register_living_inscription(
				_back_cloak,"UpperTorsoInscription%02d" % (index+1),
				Vector3(0,-0.09-row*0.19,0),colors[lane],index+3,
				0.34,float(index)*0.77,{"kind":"jacket","angle":angle}
			)
	# Both faces of each articulated sleeve carry a smaller falling stream.
	# Their paths stop short of the shoulder caps, cuffs and exposed hands.
	for index in range(_sleeves.size()):
		var sleeve: Dictionary = _sleeves[index]
		for face in [-1,1]:
			_register_living_inscription(
				sleeve.node,"SleeveInscription%s" % ("Front" if face<0 else "Back"),
				Vector3.ZERO,colors[(index+2)%colors.size()],index+face+5,
				0.28,float(index)*1.1+face*0.8,
				{"kind":"sleeve","angle":face*PI*0.5,"length":sleeve.length,
				"top":-0.10 if sleeve.length>0.29 else -0.05,
				"bottom":-0.24 if sleeve.length>0.29 else -0.17}
			)


func _register_living_inscription(
	parent: Node3D,
	label: String,
	placement: Vector3,
	color: Color,
	symbol_index: int,
	base_scale: float,
	phase: float,
	surface: Dictionary = {}
) -> void:
	var glyph := _make_living_glyph(symbol_index, color)
	glyph.name = label
	glyph.position = placement
	glyph.scale = Vector3.ONE * base_scale
	parent.add_child(glyph)
	_glyph_nodes.append(glyph)
	_glyph_base_positions.append(placement)
	_glyph_base_scales.append(base_scale)
	_glyph_phases.append(phase)
	_glyph_colors.append(color)
	_glyph_cycles.append(-1)
	_glyph_surfaces.append(surface)
	if not surface.is_empty(): _upper_inscription_count += 1


func _build_back_sigil() -> void:
	var sigil := Node3D.new()
	sigil.name = "InfiniglyphBackSigil"
	sigil.position = Vector3(0.0, -0.24, 0.142)
	sigil.scale = Vector3.ONE * 0.60
	sigil.set_meta("visual_reference", "infiniglyph-geometric-overlay")
	_back_cloak.add_child(sigil)
	var orbit := LineGeometryScript.circle(0.235, 24, SILVER_BLUE)
	orbit.name = "BackSigilHorizontalOrbit"
	orbit.scale.y = 0.52
	sigil.add_child(orbit)
	var vertical_orbit := LineGeometryScript.circle(0.235, 24, CYAN)
	vertical_orbit.name = "BackSigilVerticalOrbit"
	# Keep both sigil orbits printed on the cloak plane. Rotating this ring into
	# the YZ plane made the cyan mark protrude behind the Traveler like geometry.
	vertical_orbit.position.z = 0.008
	vertical_orbit.scale = Vector3(0.52, 1.0, 1.0)
	sigil.add_child(vertical_orbit)
	sigil.add_child(LineGeometryScript.polyline(PackedVector3Array([
		Vector3(0.0, 0.25, 0.012), Vector3(0.20, 0.0, 0.012),
		Vector3(0.0, -0.25, 0.012), Vector3(-0.20, 0.0, 0.012),
	]), VIOLET, true))
	sigil.add_child(LineGeometryScript.polyline(PackedVector3Array([
		Vector3(0.0, 0.16, 0.018), Vector3(0.065, 0.045, 0.018),
		Vector3(0.18, 0.035, 0.018), Vector3(0.09, -0.045, 0.018),
		Vector3(0.115, -0.16, 0.018), Vector3(0.0, -0.095, 0.018),
		Vector3(-0.115, -0.16, 0.018), Vector3(-0.09, -0.045, 0.018),
		Vector3(-0.18, 0.035, 0.018), Vector3(-0.065, 0.045, 0.018),
	]), GOLD, true))
	var core := LineGeometryScript.circle(0.038, 12, GOLD)
	core.position.z = 0.024
	sigil.add_child(core)
	# Offset squares and connecting corners echo the projected-cube motif in the
	# supplied Infiniglyph visual language without importing a heavy texture.
	sigil.add_child(LineGeometryScript.polyline(PackedVector3Array([
		Vector3(-0.10, -0.10, 0.020), Vector3(0.10, -0.10, 0.020),
		Vector3(0.10, 0.10, 0.020), Vector3(-0.10, 0.10, 0.020),
	]), SILVER, true))
	sigil.add_child(LineGeometryScript.polyline(PackedVector3Array([
		Vector3(-0.065, -0.065, 0.035), Vector3(0.135, -0.065, 0.035),
		Vector3(0.135, 0.135, 0.035), Vector3(-0.065, 0.135, 0.035),
	]), SILVER, true))
	sigil.add_child(LineGeometryScript.segments(PackedVector3Array([
		Vector3(-0.10, -0.10, 0.020), Vector3(-0.065, -0.065, 0.035),
		Vector3(0.10, -0.10, 0.020), Vector3(0.135, -0.065, 0.035),
		Vector3(0.10, 0.10, 0.020), Vector3(0.135, 0.135, 0.035),
		Vector3(-0.10, 0.10, 0.020), Vector3(-0.065, 0.135, 0.035),
	]), SILVER, 3.0))


func _make_living_glyph(index: int, color: Color) -> Node3D:
	var glyph := Node3D.new()
	_set_living_glyph_shape(glyph, index, color)
	return glyph


func _set_living_glyph_shape(glyph: Node3D, index: int, color: Color) -> void:
	# Keep mesh instances stable for PhaseDodge's fade/restore cache. Share
	# the finite symbol shapes instead of freeing/creating geometry each cycle.
	var variant_index := posmod(index,SYMBOL_VARIANT_COUNT)
	var key := str(variant_index)+"/"+color.to_html()
	if not _symbol_meshes.has(key):
		var sample := LineGeometryScript.segments(_get_symbol_points(variant_index),color,3.1)
		_symbol_meshes[key] = sample.mesh
		sample.free()
	var surface: MeshInstance3D
	if glyph.get_child_count()==0:
		surface = MeshInstance3D.new()
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glyph.add_child(surface)
	else: surface = glyph.get_child(0)
	surface.mesh = _symbol_meshes[key]
	glyph.set_meta("mathematical_symbol_index", variant_index)


func _get_symbol_points(index: int) -> PackedVector3Array:
	var points: PackedVector3Array
	match index % SYMBOL_VARIANT_COUNT:
		0:
			# Sigma.
			points = PackedVector3Array([
				Vector3(-0.07, 0.07, 0.0), Vector3(0.055, 0.07, 0.0),
				Vector3(0.055, 0.07, 0.0), Vector3(-0.045, 0.0, 0.0),
				Vector3(-0.045, 0.0, 0.0), Vector3(0.07, -0.07, 0.0),
				Vector3(0.07, -0.07, 0.0), Vector3(-0.055, -0.07, 0.0),
			])
		1:
			# Integral.
			points = PackedVector3Array([
				Vector3(0.04, 0.08, 0.0), Vector3(-0.015, 0.045, 0.0),
				Vector3(-0.015, 0.045, 0.0), Vector3(0.015, -0.045, 0.0),
				Vector3(0.015, -0.045, 0.0), Vector3(-0.04, -0.08, 0.0),
			])
		2:
			# Plus and multiplication overlay.
			points = PackedVector3Array([
				Vector3(-0.07, 0.0, 0.0), Vector3(0.07, 0.0, 0.0),
				Vector3(0.0, -0.07, 0.0), Vector3(0.0, 0.07, 0.0),
				Vector3(-0.05, -0.05, 0.0), Vector3(0.05, 0.05, 0.0),
			])
		3:
			# Delta / geometric diamond.
			points = PackedVector3Array([
				Vector3(0.0, 0.085, 0.0), Vector3(0.07, 0.0, 0.0),
				Vector3(0.07, 0.0, 0.0), Vector3(0.0, -0.085, 0.0),
				Vector3(0.0, -0.085, 0.0), Vector3(-0.07, 0.0, 0.0),
				Vector3(-0.07, 0.0, 0.0), Vector3(0.0, 0.085, 0.0),
			])
		4:
			# Equals.
			points = PackedVector3Array([
				Vector3(-0.075, 0.035, 0.0), Vector3(0.075, 0.035, 0.0),
				Vector3(-0.075, -0.035, 0.0), Vector3(0.075, -0.035, 0.0),
			])
		5:
			# Pi.
			points = PackedVector3Array([
				Vector3(-0.08, 0.07, 0.0), Vector3(0.08, 0.07, 0.0),
				Vector3(-0.045, 0.07, 0.0), Vector3(-0.045, -0.075, 0.0),
				Vector3(0.045, 0.07, 0.0), Vector3(0.045, -0.075, 0.0),
			])
		6:
			# Infinity.
			points = PackedVector3Array([
				Vector3(-0.085, 0.0, 0.0), Vector3(-0.045, 0.045, 0.0),
				Vector3(-0.045, 0.045, 0.0), Vector3(0.045, -0.045, 0.0),
				Vector3(0.045, -0.045, 0.0), Vector3(0.085, 0.0, 0.0),
				Vector3(0.085, 0.0, 0.0), Vector3(0.045, 0.045, 0.0),
				Vector3(0.045, 0.045, 0.0), Vector3(-0.045, -0.045, 0.0),
				Vector3(-0.045, -0.045, 0.0), Vector3(-0.085, 0.0, 0.0),
			])
		_:
			# Radical.
			points = PackedVector3Array([
				Vector3(-0.085, -0.01, 0.0), Vector3(-0.045, -0.065, 0.0),
				Vector3(-0.045, -0.065, 0.0), Vector3(0.0, 0.07, 0.0),
				Vector3(0.0, 0.07, 0.0), Vector3(0.085, 0.07, 0.0),
			])
	return points


func _build_q_gnat_trail() -> void:
	_trail_instance = MultiMeshInstance3D.new()
	_trail_instance.name = "RobeInscriptionSwarmTrail"
	_trail_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_instance.custom_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 6.0))
	_trail_instance.set_meta("q_gnat_visual_grammar", true)
	var speck_mesh := SphereMesh.new()
	speck_mesh.radius = 0.018
	speck_mesh.height = 0.036
	speck_mesh.radial_segments = 5
	speck_mesh.rings = 2
	speck_mesh.material = LineGeometryScript.make_material(SILVER_BLUE, 3.4)
	var trail := MultiMesh.new()
	trail.transform_format = MultiMesh.TRANSFORM_3D
	trail.use_colors = true
	trail.mesh = speck_mesh
	trail.instance_count = TRAIL_SPECK_COUNT
	_trail_instance.multimesh = trail
	add_child(_trail_instance)
	for index in range(TRAIL_SPECK_COUNT):
		_trail_phases.append(float(index) * 2.399963229728653)
		trail.set_instance_color(index, [SILVER_BLUE, CYAN, VIOLET, GOLD][index % 4])
		trail.set_instance_transform(
			index,
			Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), Vector3.ZERO)
		)


func _build_mathematical_symbol_trail() -> void:
	_trail_symbol_root = Node3D.new()
	_trail_symbol_root.name = "RobeMathematicalSymbolTrail"
	_trail_symbol_root.set_meta("living_manuscript_trail", true)
	add_child(_trail_symbol_root)
	for index in range(TRAIL_SYMBOL_COUNT):
		var color := [SILVER_BLUE, CYAN, VIOLET, GOLD][index % 4] as Color
		var symbol := _make_living_glyph(index + 2, color)
		symbol.name = "TrailingMathSymbol%02d" % (index + 1)
		_trail_symbol_root.add_child(symbol)
		_trail_symbol_nodes.append(symbol)
		_trail_symbol_colors.append(color)
		_trail_symbol_cycles.append(-1)
	_trail_symbol_root.visible = false


func _update_living_inscriptions() -> void:
	for index in range(_glyph_nodes.size()):
		var glyph := _glyph_nodes[index]
		var phase := _glyph_phases[index]
		var base := _glyph_base_positions[index]
		var stream_time := _elapsed / INSCRIPTION_CYCLE_SECONDS + phase / TAU
		var stream_cycle := int(floor(stream_time))
		var descent := fposmod(stream_time, 1.0)
		if stream_cycle != _glyph_cycles[index]:
			_glyph_cycles[index] = stream_cycle
			_set_living_glyph_shape(
				glyph,
				index + stream_cycle * 3,
				_glyph_colors[index]
			)
			_inscription_generation_count += 1
		var edge_visibility := minf(
			clampf(descent / 0.10, 0.0, 1.0),
			clampf((1.0 - descent) / 0.14, 0.0, 1.0)
		)
		glyph.position = base + Vector3(
			sin(_elapsed * 0.43 + phase) * 0.010,
			lerpf(0.04, -0.09, descent),
			0.0
		)
		glyph.rotation.z = sin(_elapsed * 0.27 + phase) * 0.08
		if not _glyph_surfaces[index].is_empty():
			_fit_inscription_surface(glyph,_glyph_surfaces[index],base,descent,phase)
		var pulse := 0.88 + (0.5 + 0.5 * sin(_elapsed * 1.15 + phase)) * 0.18
		glyph.scale = Vector3.ONE * (
			_glyph_base_scales[index] * pulse * maxf(0.04, edge_visibility)
		)


func _fit_inscription_surface(glyph: Node3D, surface: Dictionary, base: Vector3, descent: float, phase: float) -> void:
	var angle: float = surface.angle+sin(_elapsed*0.43+phase)*0.035
	var point: Vector3
	var normal: Vector3
	if surface.kind=="jacket":
		var height := base.y+lerpf(0.04,-0.09,descent)
		var profile: Vector3 = JACKET_LEVELS[0]
		for row in range(JACKET_LEVELS.size()-1):
			var low: Vector3 = JACKET_LEVELS[row]
			var high: Vector3 = JACKET_LEVELS[row+1]
			if height>high.y: continue
			profile = low.lerp(high,clampf((height-low.y)/(high.y-low.y),0.0,1.0))
			break
		point = _jacket_point(profile,angle)
		normal = Vector3(sin(angle)/profile.x,0,cos(angle)/profile.z).normalized()
	else:
		var height := lerpf(surface.top,surface.bottom,descent)
		var radius := lerpf(0.069,0.056,clampf((0.018-height)/(0.018+surface.length),0.0,1.0))
		normal = Vector3(cos(angle),0,sin(angle))
		point = normal*radius+Vector3.UP*height
	# The plane's +Z points away from the cloth. A small offset keeps thin lines
	# clear of the faceted fabric without turning inscriptions into floating props.
	glyph.position = point+normal*0.008
	var tangent := Vector3(normal.z,0,-normal.x)
	glyph.basis = Basis(tangent,Vector3.UP,normal)*Basis(Vector3.BACK,sin(_elapsed*0.27+phase)*0.08)


func _update_trail(motion_velocity: Vector3) -> void:
	if not is_instance_valid(_trail_instance) or _trail_instance.multimesh == null:
		return
	_trail_instance.visible = _flow_amount > 0.035
	var local_motion := global_transform.basis.inverse() * motion_velocity
	local_motion.y = 0.0
	var trail_direction := Vector3(0.0, 0.0, 1.0)
	if local_motion.length_squared() > 0.01:
		trail_direction = -local_motion.normalized()
	var intensity := smoothstep(0.02, 1.0, _flow_amount)
	for index in range(TRAIL_SPECK_COUNT):
		var phase := _trail_phases[index]
		var rank := float(index + 1) / float(TRAIL_SPECK_COUNT)
		var spread := Vector3(
			sin(phase + _elapsed * 1.4) * (0.12 + rank * 0.22),
			0.42 + cos(phase * 1.7 + _elapsed * 1.1) * 0.30 + rank * 0.55,
			0.0
		)
		var trail_distance := (0.22 + rank * 1.55) * intensity
		var point := spread + trail_direction * trail_distance
		point.y += sin(_elapsed * 2.2 + phase) * 0.08 * intensity
		var pulse := (
			0.35 + 0.45 * (0.5 + 0.5 * sin(_elapsed * 2.0 + phase))
		) * intensity
		_trail_instance.multimesh.set_instance_transform(
			index,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * maxf(0.001, pulse)),
				point
			)
		)
	_update_mathematical_symbol_trail(trail_direction, intensity)


func _update_mathematical_symbol_trail(
	trail_direction: Vector3,
	intensity: float
) -> void:
	if not is_instance_valid(_trail_symbol_root):
		return
	_trail_symbol_root.visible = _flow_amount > 0.055
	for index in range(_trail_symbol_nodes.size()):
		var symbol := _trail_symbol_nodes[index]
		var rank := float(index + 1) / float(TRAIL_SYMBOL_COUNT)
		var phase := float(index) * 2.399963229728653
		var generation_cycle := int(floor(_elapsed * 1.35 - rank * 2.0))
		if generation_cycle != _trail_symbol_cycles[index]:
			_trail_symbol_cycles[index] = generation_cycle
			_set_living_glyph_shape(
				symbol,
				index * 3 + generation_cycle,
				_trail_symbol_colors[index]
			)
		var trail_distance := (0.34 + rank * 1.95) * intensity
		symbol.position = (
			trail_direction * trail_distance
			+ Vector3(
				sin(phase + _elapsed * 1.1) * (0.10 + rank * 0.24),
				0.34 + rank * 0.92 + sin(phase * 1.4 + _elapsed) * 0.12,
				0.0
			)
		)
		symbol.rotation.z = sin(phase + _elapsed * 1.7) * 0.42
		var tail_fade := (1.0 - rank * 0.58) * intensity
		var pulse := 0.72 + 0.28 * sin(_elapsed * 2.1 + phase)
		symbol.scale = Vector3.ONE * maxf(0.001, tail_fade * pulse)


func _get_visual_velocity() -> Vector3:
	var result := _traveler.velocity
	if is_instance_valid(_traveler.world_actions) and is_instance_valid(_traveler.world_actions.vehicle): result = _traveler.world_actions.vehicle.velocity
	return result


func _make_fabric_surface(
	label: String,
	vertices: PackedVector3Array,
	color: Color
) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color.lightened(0.025)
	material.emission_energy_multiplier = 0.55
	mesh.surface_set_material(0, material)
	var surface := MeshInstance3D.new()
	surface.name = label
	surface.mesh = mesh
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return surface
