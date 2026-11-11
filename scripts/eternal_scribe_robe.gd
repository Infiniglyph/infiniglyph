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

var _traveler: CharacterBody3D
var _figure: Node3D
var _upper_body: Node3D
var _back_cloak: Node3D
var _left_front_panel: Node3D
var _right_front_panel: Node3D
var _external_pieces: Array[Node3D] = []
var _glyph_nodes: Array[Node3D] = []
var _glyph_base_positions: Array[Vector3] = []
var _glyph_base_scales: Array[float] = []
var _glyph_phases: Array[float] = []
var _glyph_colors: Array[Color] = []
var _glyph_cycles: Array[int] = []
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

	var breathing := sin(_elapsed * 1.15) * 0.008
	_back_cloak.rotation.x = lerpf(
		_back_cloak.rotation.x,
		-0.035 - _flow_amount * 0.22 + breathing,
		1.0 - exp(-4.4 * delta)
	)
	_back_cloak.rotation.z = lerpf(
		_back_cloak.rotation.z,
		-_turn_amount,
		1.0 - exp(-5.0 * delta)
	)
	_left_front_panel.rotation.x = lerpf(
		_left_front_panel.rotation.x,
		-0.012 - _flow_amount * 0.10,
		1.0 - exp(-4.0 * delta)
	)
	_right_front_panel.rotation.x = _left_front_panel.rotation.x
	var panel_sway := sin(_elapsed * (2.0 + _flow_amount * 4.0)) * 0.035 * _flow_amount
	_left_front_panel.rotation.z = lerpf(
		_left_front_panel.rotation.z,
		-panel_sway - _turn_amount * 0.34,
		1.0 - exp(-4.2 * delta)
	)
	_right_front_panel.rotation.z = lerpf(
		_right_front_panel.rotation.z,
		panel_sway - _turn_amount * 0.34,
		1.0 - exp(-4.2 * delta)
	)
	_update_living_inscriptions()
	_update_trail(motion_velocity)


func _build_body_layers() -> void:
	_back_cloak = Node3D.new()
	_back_cloak.name = "FlowingBackCloak"
	_back_cloak.position.y = 1.456
	add_child(_back_cloak)
	var back_vertices := PackedVector3Array([
		Vector3(-0.34, 0.0, 0.055), Vector3(0.34, 0.0, 0.055),
		Vector3(0.48, -1.30, 0.13), Vector3(-0.34, 0.0, 0.055),
		Vector3(0.48, -1.30, 0.13), Vector3(-0.48, -1.30, 0.13),
	])
	_back_cloak.add_child(_make_fabric_surface("BackFabric", back_vertices, FABRIC))
	_back_cloak.add_child(LineGeometryScript.polyline(PackedVector3Array([
		Vector3(-0.34, 0.0, 0.145), Vector3(0.34, 0.0, 0.145),
		Vector3(0.48, -1.30, 0.145), Vector3(-0.48, -1.30, 0.145),
	]), SILVER, true))
	_back_cloak.add_child(LineGeometryScript.segments(PackedVector3Array([
		Vector3(0.0, -0.08, 0.150), Vector3(0.0, -1.24, 0.150),
		Vector3(-0.31, -0.23, 0.151), Vector3(-0.42, -1.16, 0.151),
		Vector3(0.31, -0.23, 0.151), Vector3(0.42, -1.16, 0.151),
	]), FABRIC_HIGHLIGHT, 1.7))

	_left_front_panel = _build_front_panel("LeftOpenFrontPanel", -1.0)
	_right_front_panel = _build_front_panel("RightOpenFrontPanel", 1.0)
	add_child(_left_front_panel)
	add_child(_right_front_panel)

	var mantle := Node3D.new()
	mantle.name = "SilverEdgedMantle"
	mantle.position = Vector3(0.0, 1.37, 0.025)
	add_child(mantle)
	mantle.add_child(LineGeometryScript.polyline(PackedVector3Array([
		Vector3(-0.37, 0.0, 0.02), Vector3(-0.23, -0.16, -0.075),
		Vector3(0.0, -0.22, -0.09), Vector3(0.23, -0.16, -0.075),
		Vector3(0.37, 0.0, 0.02),
	]), SILVER_BLUE))


func _build_front_panel(label: String, side: float) -> Node3D:
	var panel := Node3D.new()
	panel.name = label
	panel.position.y = 1.31
	var inner_top := 0.085 * side
	var outer_top := 0.32 * side
	var inner_bottom := 0.13 * side
	var outer_bottom := 0.43 * side
	var vertices := PackedVector3Array([
		Vector3(inner_top, 0.0, -0.065), Vector3(outer_top, 0.0, -0.065),
		Vector3(outer_bottom, -1.25, -0.035), Vector3(inner_top, 0.0, -0.065),
		Vector3(outer_bottom, -1.25, -0.035), Vector3(inner_bottom, -1.25, -0.035),
	])
	panel.add_child(_make_fabric_surface("Fabric", vertices, FABRIC))
	panel.add_child(LineGeometryScript.polyline(PackedVector3Array([
		Vector3(inner_top, 0.0, -0.075), Vector3(outer_top, 0.0, -0.075),
		Vector3(outer_bottom, -1.25, -0.045), Vector3(inner_bottom, -1.25, -0.045),
	]), SILVER, true))
	panel.add_child(LineGeometryScript.segments(PackedVector3Array([
		Vector3(inner_top, -0.10, -0.080), Vector3(inner_bottom, -1.18, -0.050),
	]), VIOLET if side < 0.0 else GOLD, 2.5))
	return panel


func _build_hood() -> void:
	var hood := Node3D.new()
	hood.name = "OpenScholarHood"
	add_child(hood)
	var levels := [
		Vector3(0.32, 1.42, 0.01),
		Vector3(0.35, 1.69, 0.02),
		Vector3(0.26, 1.91, 0.035),
		Vector3(0.055, 2.01, 0.07),
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
	# The Library sleeve follows one arm pivot. Here the elbow articulates:
	# separate upper and lower fabric panels follow the existing two links.
	for part in range(2):
		var sleeve := Node3D.new()
		sleeve.name = label+("Upper" if part==0 else "Lower")
		var joint: Node3D = arm if part==0 else arm.get_node("Hinge")
		joint.add_child(sleeve)
		sleeve.rotation.y = PI
		_external_pieces.append(sleeve)
		var length_value := 0.30 if part==0 else 0.26
		var inside := -0.10*side
		var outside := 0.14*side
		var cuff := 0.18*side
		var vertices := PackedVector3Array([
			Vector3(inside,0.02,0.045),Vector3(outside,0.02,0.045),
			Vector3(cuff,-length_value,0.07),Vector3(inside,0.02,0.045),
			Vector3(cuff,-length_value,0.07),Vector3(inside,-length_value,0.07),
		])
		sleeve.add_child(_make_fabric_surface("SleeveFabric",vertices,FABRIC))
		sleeve.add_child(LineGeometryScript.polyline(PackedVector3Array([
			Vector3(inside,0.02,0.078),Vector3(outside,0.02,0.078),
			Vector3(cuff,-length_value,0.085),Vector3(inside,-length_value,0.085),
		]),SILVER,true))

func _build_inscriptions() -> void:
	_build_back_sigil()
	var placements := [
		Vector3(-0.23, -0.30, 0.158), Vector3(0.24, -0.34, 0.158),
		Vector3(-0.27, -0.83, 0.158), Vector3(0.28, -0.88, 0.158),
		Vector3(-0.12, -1.11, 0.158), Vector3(0.13, -1.12, 0.158),
	]
	var colors := [SILVER_BLUE, VIOLET, SILVER, GOLD, CYAN, SILVER_BLUE]
	for index in range(placements.size()):
		_register_living_inscription(
			_back_cloak,
			"LivingInscription%02d" % (index + 1),
			placements[index],
			colors[index],
			index,
			0.62 + float(index % 3) * 0.08,
			float(index) * 1.047
		)
	_build_front_inscriptions()


func _build_front_inscriptions() -> void:
	var panels := [_left_front_panel, _right_front_panel]
	var sides := [-1.0, 1.0]
	var row_x := [0.18, 0.245, 0.31]
	var row_y := [-0.24, -0.62, -0.99]
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
				Vector3(side * row_x[row], row_y[row], -0.092),
				colors[inscription_index],
				inscription_index + 2,
				0.52 + float(row) * 0.055,
				float(inscription_index + 6) * 0.91
			)
			_front_inscription_count += 1


func _register_living_inscription(
	parent: Node3D,
	label: String,
	placement: Vector3,
	color: Color,
	symbol_index: int,
	base_scale: float,
	phase: float
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


func _build_back_sigil() -> void:
	var sigil := Node3D.new()
	sigil.name = "InfiniglyphBackSigil"
	sigil.position = Vector3(0.0, -0.61, 0.166)
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
			sin(_elapsed * 0.43 + phase) * 0.025,
			lerpf(0.12, -0.19, descent),
			0.0
		)
		glyph.rotation.z = sin(_elapsed * 0.27 + phase) * 0.08
		var pulse := 0.88 + (0.5 + 0.5 * sin(_elapsed * 1.15 + phase)) * 0.18
		glyph.scale = Vector3.ONE * (
			_glyph_base_scales[index] * pulse * maxf(0.04, edge_visibility)
		)


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
