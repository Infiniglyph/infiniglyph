extends Node3D
## Scriptorus-derived feather/nib and bounded local following, without companion AI.
const Lines = preload("res://scripts/robe_lines.gd")
const Robe = preload("res://scripts/eternal_scribe_robe.gd")
const Glyphs = preload("res://scripts/eturnull_hat.gd")
const TempleGlyphs = preload("res://scripts/dungeon_glyphs.gd")
const Moves = preload("res://scripts/scribe_moves.gd")
const STROKE_LIMIT := 160
const AFTERGLOW_LIMIT := 6
const TRANSITION_SECONDS := 0.46
const HIP_STOW_POSITION := Vector3(.225,.03,-.08)
var rig: Node3D
var combat: Node
var actor: CharacterBody3D
var book: Node3D
var quill: Node3D
var leaves: Array[Node3D] = []
var turning_page: Node3D
var ink_root: Node3D
var ink: MultiMeshInstance3D
var ink_material: StandardMaterial3D
var ward: Node3D
var stowed := false
var stow_amount := 1.0
var clock := 0.0
var page_phase := 0.0
var active_points := PackedVector3Array()
var active_transform := Transform3D.IDENTITY
var _query := PhysicsShapeQueryParameters3D.new()
var _capsule := CapsuleShape3D.new()
var _last_tip := Vector3.ZERO
var book_size := 1.0
var quill_size := 1.0
@export_range(.5,1.5,.05) var hover_right_distance := 1.0
@export_range(1.4,1.9,.01) var hover_height := 1.56
var hover_trail := Vector3.ZERO
@export_range(.1,2,.05) var cast_afterglow_seconds := .65
var afterglows: Array[Dictionary] = []
var _afterglow_cursor := 0
var _manuscript := false
var _hieroglyphic := false

func configure(value: Node3D, definition: Dictionary = {}) -> void:
	rig = value
	# In gameplay the weapon rig is a direct child of the figure.
	actor = rig.visual.get_parent() as CharacterBody3D
	combat = actor.get("weapon_combat")
	name = "ScribePresentation"
	var geometry: Dictionary = definition.get("geometry",{})
	_hieroglyphic=geometry.get("writing_system")=="hieroglyphic"
	book = make_book(_hieroglyphic)
	add_child(book)
	_manuscript = definition.get("id","")=="eturnull_manuscript"
	book_size = clampf(float(geometry.get("book_scale",1)),.6,1.4)
	leaves = [book.get_node("LeftLeaf"),book.get_node("RightLeaf")]
	turning_page = book.get_node("TurningPage")
	quill = make_quill(_hieroglyphic)
	add_child(quill)
	quill_size = clampf(float(geometry.get("quill_scale",1)),.6,1.4)
	ink_root = Node3D.new()
	add_child(ink_root)
	ink_material = Lines.make_material(Robe.SILVER_BLUE,1.8)
	ink_material.albedo_color = Moves.INK_COLOR if _manuscript else Color(geometry.get("tint","9feaff"))
	ink_material.emission = Moves.INK_EMISSION if _manuscript else ink_material.albedo_color
	if _manuscript: ink_material.emission_energy_multiplier = 1.5
	ink_material.vertex_color_use_as_albedo = false
	ink_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink = MultiMeshInstance3D.new()
	ink.name = "WrittenAttackGeometry"
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := CylinderMesh.new()
	mesh.top_radius = .009
	mesh.bottom_radius = .009
	mesh.height = 1
	mesh.radial_segments = 4
	mesh.material = ink_material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = STROKE_LIMIT
	batch.visible_instance_count = 0
	ink.multimesh = batch
	ink_root.add_child(ink)
	if _manuscript:
		for i in range(AFTERGLOW_LIMIT):
			var echo := MultiMeshInstance3D.new()
			echo.name = "HarmlessCastAfterglow"+str(i)
			echo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			echo.multimesh = MultiMesh.new()
			echo.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			echo.multimesh.mesh = mesh
			echo.multimesh.instance_count = STROKE_LIMIT
			echo.multimesh.visible_instance_count = 0
			var material: StandardMaterial3D = ink_material.duplicate()
			echo.material_override = material
			add_child(echo)
			echo.top_level = true
			echo.hide()
			afterglows.append({"node":echo,"material":material,"remaining":0.0})
	ward = Node3D.new()
	ink_root.add_child(ward)
	var spell_color := Moves.INK_COLOR if _manuscript else Color("ffd170") if _hieroglyphic else Robe.SILVER_BLUE
	var ring := Lines.circle(.46,32,spell_color)
	ward.add_child(ring)
	if _hieroglyphic:
		var symbol:=MeshInstance3D.new(); symbol.mesh=TempleGlyphs.mesh(0); symbol.scale=Vector3.ONE*.44
		symbol.material_override=Lines.make_material(Color("65ffff"),2.4); ward.add_child(symbol)
	else:
		ward.add_child(Lines.polyline(PackedVector3Array([Vector3(-.32,-.22,0),Vector3(.32,-.22,0),Vector3(0,.38,0)]),spell_color,true))
	ward.hide()
	_query.shape = _capsule
	_query.collision_mask = 6 # Fighter hurtboxes and physical civilians.
	_query.exclude = [actor.get_rid()]
	process_priority = 50
	# First acquisition/draw starts with the quill inside its closed book too.
	book.global_transform = rig.visual.pelvis.global_transform*Transform3D(Basis.from_euler(Vector3(0,0,-.12)),HIP_STOW_POSITION)
	quill.global_position = book.global_position
	_last_tip = quill.global_position

static func make_book(hieroglyphic: bool=false) -> Node3D:
	var ink_color:=Color("ffd170") if hieroglyphic else Robe.SILVER_BLUE
	var result := Node3D.new()
	result.name = "OpenGrimoire"
	for side in [-1,1]:
		var hinge := Node3D.new()
		hinge.name = "LeftLeaf" if side<0 else "RightLeaf"
		result.add_child(hinge)
		var surface := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.21,.29,.024)
		mesh.material = Lines.make_material(Robe.FABRIC,0)
		surface.mesh = mesh
		surface.position.x = side*.107
		hinge.add_child(surface)
		var edge := Lines.box(Vector3(.21,.29,.026),ink_color)
		edge.position.x = side*.107
		hinge.add_child(edge)
		for i in range(3):
			var glyph := MeshInstance3D.new()
			glyph.mesh = TempleGlyphs.mesh(i+(0 if side<0 else 3)) if hieroglyphic else Glyphs.glyph_mesh(["∫","π","="][i])
			glyph.position = Vector3(side*.107,.075-i*.075,.016)
			glyph.scale = Vector3.ONE*(.085 if hieroglyphic else .32)
			if hieroglyphic: glyph.material_override=Lines.make_material(Color("65ffff"),1.8)
			hinge.add_child(glyph)
	var page := Node3D.new()
	page.name = "TurningPage"
	var sheet := MeshInstance3D.new()
	var sheet_mesh := BoxMesh.new()
	sheet_mesh.size = Vector3(.195,.275,.003)
	sheet_mesh.material = Lines.make_material(Robe.FABRIC_HIGHLIGHT,0)
	sheet.mesh = sheet_mesh
	sheet.position = Vector3(.10,0,.020)
	page.add_child(sheet)
	var outline := Lines.box(Vector3(.195,.275,.004),Robe.SILVER)
	outline.position = sheet.position
	page.add_child(outline)
	var notation := MeshInstance3D.new()
	notation.mesh = TempleGlyphs.mesh(1) if hieroglyphic else Glyphs.glyph_mesh("∑")
	notation.position = Vector3(.10,0,.025)
	notation.scale = Vector3.ONE*(.13 if hieroglyphic else .5)
	if hieroglyphic: notation.material_override=Lines.make_material(Color("65ffff"),1.8)
	page.add_child(notation)
	result.add_child(page)
	return result

static func make_quill(hieroglyphic: bool=false) -> Node3D:
	var primary:=Color("ffd170") if hieroglyphic else Robe.SILVER_BLUE
	var secondary:=Color("65ffff") if hieroglyphic else Robe.SILVER
	var nib_ink:=Color("65ffff") if hieroglyphic else Robe.VIOLET
	# Preserve Scriptorus' recognizable feather outline, six paired barbs and
	# violet diamond nib. Tip is the origin, so writing has no invisible offset.
	var result := Node3D.new()
	result.name = "ScriptorusStyleFloatingQuill"
	var outline := PackedVector3Array()
	var profile := [Vector2(0,-.78),Vector2(-.10,-.43),Vector2(-.17,-.06),Vector2(-.21,.36),Vector2(-.14,.70),Vector2(0,.92),Vector2(.14,.70),Vector2(.21,.36),Vector2(.17,-.06),Vector2(.10,-.43),Vector2(0,-.78)]
	for i in range(profile.size()-1):
		for j in [i,i+1]: outline.append(Vector3(profile[j].x,profile[j].y+1.16,0)*.26)
	result.add_child(Lines.segments(outline,primary,1.8))
	var barbs := PackedVector3Array()
	for i in range(6):
		var y := -.30+i*.18
		var width := .10+sin(i*.62)*.05
		for side in [-1,1]:
			barbs.append(Vector3(0,y-.05+1.16,.015)*.26)
			barbs.append(Vector3(side*width,y+.10+1.16,.015)*.26)
	result.add_child(Lines.segments(barbs,secondary,1.6))
	var nib := PackedVector3Array([Vector3(0,.80+1.16,.025),Vector3(0,-.78+1.16,.025),Vector3(0,-.78+1.16,.025),Vector3(-.12,-1.02+1.16,.025),Vector3(-.12,-1.02+1.16,.025),Vector3(0,0,.025),Vector3(0,0,.025),Vector3(.12,-1.02+1.16,.025),Vector3(.12,-1.02+1.16,.025),Vector3(0,-.78+1.16,.025)])
	for i in range(nib.size()): nib[i] *= .26
	result.add_child(Lines.segments(nib,nib_ink,2.0))
	return result

func set_sheathed(value: bool) -> void:
	stowed = value
	if value: clear_writing()

func clear_writing(include_afterglows: bool = true) -> void:
	active_points = PackedVector3Array()
	if is_instance_valid(ink): ink.multimesh.visible_instance_count = 0
	if is_instance_valid(ward): ward.hide()
	if include_afterglows:
		for echo in afterglows:
			echo.remaining = 0.0
			echo.node.hide()
			echo.node.multimesh.visible_instance_count = 0

func retain_writing(move: Dictionary, time: float) -> void:
	if afterglows.is_empty() or StringName(move.get("action",&"")) not in [&"attack_left",&"attack_right",&"special_x",&"special_y"]: return
	var echo := afterglows[_afterglow_cursor]
	_afterglow_cursor = (_afterglow_cursor+1)%afterglows.size()
	echo.remaining = maxf(0,float(move.duration)-time)+cast_afterglow_seconds
	echo.node.global_transform = active_transform
	echo.material.albedo_color = Moves.INK_COLOR
	draw_strokes(echo.node.multimesh,active_points,ink.multimesh.visible_instance_count)
	echo.node.show()

func advance_afterglows(delta: float) -> void:
	for echo in afterglows:
		if echo.remaining<=0: continue
		echo.remaining = maxf(0,float(echo.remaining)-delta)
		echo.material.albedo_color.a = clampf(float(echo.remaining)/.35,0,1)
		if echo.remaining<=0:
			echo.node.hide()
			echo.node.multimesh.visible_instance_count = 0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		clear_writing()
		return
	var phase: Node = actor.get("dodge")
	if is_instance_valid(phase) and phase.active:
		# Keep the book and quill in the same local phase transform as the body.
		# World-space attachment updates would counteract its temporary squash.
		clear_writing()
		_last_tip = quill.global_position
		return
	advance_afterglows(delta)
	clock += delta
	stow_amount = move_toward(stow_amount,1 if stowed else 0,delta/TRANSITION_SECONDS)
	# The +Z-facing figure's positive-X arm is its anatomical left, despite
	# the historical RightArm node name. Keep this correction Scribe-local.
	var hand_transform: Transform3D = rig.right_hand.global_transform
	hand_transform.origin += rig.visual.chest.global_basis*Vector3(.03,.08,.05)
	# Closing the leaves already turns their covers into the YZ plane. Keep
	# that plane against the hip: the spine trails and the page edges face +Z.
	# Seat the closed thickness against the belt, centered along the waist's side.
	var hip_transform: Transform3D = rig.visual.pelvis.global_transform*Transform3D(Basis.from_euler(Vector3(0,0,-.12)),HIP_STOW_POSITION)
	book.global_transform = hand_transform.interpolate_with(hip_transform,smoothstep(.45,1,stow_amount))
	book.scale *= book_size
	var charging: bool = is_instance_valid(combat) and actor.combat.charge_action!=&""
	var guarding: bool = is_instance_valid(combat) and actor.combat.blocking
	var holding_quill: bool = is_instance_valid(combat) and combat.is_writing_stance()
	var move: Dictionary = combat.active_move if is_instance_valid(combat) else {}
	if not stowed and not move.is_empty():
		# Fresh attacks accelerate the draw so its contact can never precede the
		# visible quill leaving the book. No extra gameplay action lock is added.
		stow_amount = minf(stow_amount,1-clampf(combat.elapsed/maxf(.04,float(move.windup)*.7),0,1))
	var activity := float(move.get("page_energy",.35)) if not move.is_empty() else .04
	if charging: activity = .65+actor.combat.charge_elapsed/actor.combat.CHARGE_FULL*.35
	elif guarding: activity = .25
	elif holding_quill: activity = .3 if combat.tracing_active() else .08
	page_phase += delta*(1.0+activity*5.5)
	var opening := (1-smoothstep(.5,1,stow_amount))
	leaves[0].rotation.y = lerpf(PI*.49,.24,opening)
	leaves[1].rotation.y = -leaves[0].rotation.y
	turning_page.rotation.y = sin(page_phase)*(.10+activity*1.25)*opening
	turning_page.rotation.x = sin(clock*13)*.035*activity*opening
	turning_page.visible = opening>.1
	# A fresh parry window produces a distinct, sharp page snap.
	if guarding and combat.parry_remaining>0: turning_page.rotation.y += sin(combat.parry_remaining/combat.PARRY_WINDOW*PI)*.65
	# Hover in a yaw-only owner frame, independently of the relaxed arm and
	# torso lean. A bounded world-velocity offset trails actual travel, including
	# strafing/backpedalling. The anchor itself always follows the player.
	var forward: Vector3 = rig.visual.global_basis.z
	var hover_basis := Basis(Vector3.UP,atan2(forward.x,forward.z))
	var desired_trail := -actor.velocity.limit_length(20)*.018
	desired_trail.y = clampf(desired_trail.y,-.10,.10)
	hover_trail = hover_trail.lerp(desired_trail.limit_length(.30),1-exp(-8*delta))
	var target: Vector3 = actor.global_position+hover_basis*Vector3(-hover_right_distance,hover_height+sin(clock*1.6)*.018,-.08)+hover_trail
	var writing := false
	if not stowed and stow_amount<.5 and is_instance_valid(combat) and not actor.dodge.active and not combat.is_staggered():
		if not move.is_empty():
			write(move,combat.elapsed,combat._facing)
			writing = true
		elif charging:
			var held: Dictionary = combat.move_for(actor.combat.charge_slot,actor.combat.charge_action)
			write(held,float(held.hits[0])*clampf(actor.combat.charge_elapsed/.7,0,1),combat.aim_direction())
			ink_material.albedo_color.a = .45
			writing = true
		else: clear_writing(false)
		ward.visible = guarding
		if guarding:
			ink_root.global_transform = Transform3D(Basis(Vector3.UP,atan2(combat.aim_direction().x,combat.aim_direction().z)),actor.combat_point())
			ward.position = Vector3(0,.22,.55)
			ward.rotation.z = clock*.5
			ward.scale = Vector3.ONE*(1.2 if combat.parry_remaining>0 else 1.0)
			target = ward.to_global(Vector3(cos(clock*6)*.46,sin(clock*6)*.46,0))
	else: clear_writing(false)
	if writing and not active_points.is_empty():
		var count := ink.multimesh.visible_instance_count
		if count>0: target = active_transform*active_points[mini(active_points.size()-1,count*2-1)]
	if holding_quill:
		clear_writing(false)
		target = rig.left_hand.global_position-Vector3.UP*.16
	var local_target := to_local(target)
	# Like Scriptorus, follow in the owner's local frame. Fast travel cannot
	# leave the quill across the map; only the gesture has bounded smoothing.
	if writing or holding_quill:
		quill.position = local_target
	else:
		quill.position = quill.position.lerp(local_target,1-exp(-24*delta))
	var dive := smoothstep(0,.52,stow_amount)
	quill.global_position = quill.global_position.lerp(book.global_position,dive)
	quill.visible = stow_amount<.58
	var movement := quill.global_position-_last_tip
	if holding_quill:
		quill.global_basis = Basis(Vector3.UP,atan2(forward.x,forward.z))*Basis.from_scale(Vector3.ONE*quill_size)
	elif movement.length()>.001:
		var direction := (-movement.normalized()+Vector3.UP*1.5).normalized()
		quill.global_basis = Basis(Quaternion(Vector3.UP,direction)).scaled(Vector3.ONE*quill_size)
	else: quill.rotation = Vector3(0,0,-.22+sin(clock*.72)*.06)
	_last_tip = quill.global_position

func write(move: Dictionary, time: float, facing: Vector3) -> void:
	var points := Moves.strokes(move)
	active_points = points
	active_transform = Transform3D(Basis(Vector3.UP,atan2(facing.x,facing.z)),actor.combat_point())*Moves.stroke_transform(move,time)
	ink_root.global_transform = active_transform
	var count := mini(STROKE_LIMIT,int(points.size()/2))
	var written := mini(count,ceili(count*Moves.progress(move,time)))
	ink.multimesh.visible_instance_count = written
	var last := float(move.hits[-1])
	ink_material.albedo_color.a = 1-smoothstep(last+.08,float(move.duration),time)
	draw_strokes(ink.multimesh,points,written)

func draw_strokes(batch: MultiMesh, points: PackedVector3Array, written: int) -> void:
	batch.visible_instance_count = written
	for index in range(written):
		var a := points[index*2]
		var b := points[index*2+1]
		var direction := b-a
		var basis := Basis(Quaternion(Vector3.UP,direction.normalized()))
		basis = basis*Basis.from_scale(Vector3(1,maxf(.001,direction.length()),1))
		batch.set_instance_transform(index,Transform3D(basis,(a+b)*.5))

func hit_candidates(move: Dictionary, time: float, facing: Vector3) -> Array:
	write(move,time,facing)
	var candidates: Array = []
	var space := actor.get_world_3d().direct_space_state
	for index in range(ink.multimesh.visible_instance_count):
		var a: Vector3 = active_transform*active_points[index*2]
		var b: Vector3 = active_transform*active_points[index*2+1]
		var direction := b-a
		_capsule.radius = float(move.get("stroke_radius",.10))
		_capsule.height = direction.length()+_capsule.radius*2
		_query.transform = Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized())),(a+b)*.5)
		for candidate: Dictionary in space.intersect_shape(_query,16):
			candidate.contact = Geometry3D.get_closest_point_to_segment(candidate.collider.global_position+Vector3.UP*.95,a,b)
			candidates.append(candidate)
	return candidates
