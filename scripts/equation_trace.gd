extends MultiMeshInstance3D
## One bounded batch per wielder. Each section owns its actual mathematical
## strokes, lifetime and allegiance; no per-character nodes or physics bodies.
const Persistence = preload("res://scripts/persistent_trail.gd")
const Settings = preload("res://scripts/equation_trace_settings.gd")
const Glyphs = preload("res://scripts/eturnull_hat.gd")
const Moves = preload("res://scripts/scribe_moves.gd")
const EXPRESSIONS := ["x²+y²=r²","∫f(x)dx","e^(iπ)+1=0","∇·F=0"]
static var glyph_strokes: Dictionary = {}
var settings: Resource = Settings.new()
var combat: Node
var actor: CharacterBody3D
var sections: Array[Dictionary] = []
var action: StringName = &""
var desired_tip := Vector3.ZERO
var age := 0.0
var time := 0.0
var reflected_count := 0
var _last := Vector3.ZERO
var _has_last := false
var _sample_clock := 0.0
var _draw_clock := 0.0
var _pen_down := true
var _was_down := true
var _stroke_id := 0
var _last_stroke_id := -1
var _character := 0
var _expression := 0
var _distance := 0.0
var _ink: StandardMaterial3D
var _hit_until: Dictionary = {}
var _previous: Dictionary = {}
var _serial := 0
var _dirty := true
var last_contact_microseconds := 0
var _targets: Array[Node3D] = []
var _seen: Dictionary = {}

func _ready() -> void:
	name = "PersistentEquationTrace"
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ink = StandardMaterial3D.new()
	_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ink.vertex_color_use_as_albedo = true
	_ink.emission_enabled = true
	_ink.emission = Moves.INK_EMISSION
	_ink.emission_energy_multiplier = 1.5
	var stroke := CylinderMesh.new()
	# Contact tolerance matches the vehicle wall, while thin calligraphic ink
	# leaves operators and counters readable instead of filling each glyph in.
	stroke.top_radius = settings.thickness*.12
	stroke.bottom_radius = stroke.top_radius
	stroke.height = 1
	stroke.radial_segments = 4
	stroke.rings = 0
	stroke.material = _ink
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = stroke
	multimesh.instance_count = settings.maximum_strokes
	multimesh.visible_instance_count = 0
	for expression: String in EXPRESSIONS:
		for character: String in expression:
			if not glyph_strokes.has(character):
				glyph_strokes[character] = Glyphs.glyph_mesh(character).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	set_physics_process(false)

func begin(value: StringName) -> void:
	action = value
	age = 0
	_sample_clock = 0
	_has_last = false
	_was_down = true
	_last_stroke_id = -1
	_character = 0
	_expression = 0 if value==&"special_rt_x" else 1
	_distance = 0
	prepare(0)
	# An input can be pressed and released inside one simulation sample. Write
	# the tiny mark now; holding adds a path rather than scaling this mark up.
	var tip: Vector3 = combat.rig.left_hand.global_position-Vector3.UP*.16
	var frame := Moves.writing_basis(combat.trace_aim_direction())
	var points := PackedVector3Array()
	var radius: float = settings.minimum_mark_size
	if value==&"special_rt_x":
		for point: Vector2 in [Vector2(-1,-1),Vector2(1,1),Vector2(-1,1),Vector2(1,-1)]:
			points.append(tip+frame*Vector3(point.x,point.y,0)*radius)
	else:
		for i in range(8):
			for j in [i,i+1]: points.append(tip+frame*Vector3(cos(j*TAU/8),sin(j*TAU/8),0)*radius)
	append_section(points)
	set_physics_process(true)

func stop() -> void:
	action = &""
	_has_last = false

func clear() -> void:
	stop()
	sections.clear()
	_hit_until.clear()
	_previous.clear()
	if multimesh!=null: multimesh.visible_instance_count = 0
	set_physics_process(false)

func prepare(delta: float) -> void:
	if action==&"": return
	age += delta
	var frame := Moves.writing_basis(combat.trace_aim_direction())
	var period: float = settings.x_frequency if action==&"special_rt_x" else settings.y_frequency
	var phase := fposmod(age/maxf(.08,period),1)
	_stroke_id = floori(age/maxf(.08,period))*2+(1 if phase>=.5 else 0) if action==&"special_rt_x" else 0
	var radius := lerpf(float(settings.minimum_mark_size),.23,smoothstep(0,.15,age))
	var pattern := Vector2.ZERO
	_pen_down = true
	if action==&"special_rt_x":
		if phase<.45: pattern = Vector2(-1,-1).lerp(Vector2(1,1),phase/.45)
		elif phase<.5:
			pattern = Vector2(1,1).lerp(Vector2(-1,1),(phase-.45)/.05)
			_pen_down = false
		elif phase<.95: pattern = Vector2(-1,1).lerp(Vector2(1,-1),(phase-.5)/.45)
		else:
			pattern = Vector2(1,-1).lerp(Vector2(-1,-1),(phase-.95)/.05)
			_pen_down = false
	else: pattern = Vector2(cos(phase*TAU),sin(phase*TAU))
	var target: Vector3 = actor.combat_point()+frame*Vector3(-.27+pattern.x*radius,.25+pattern.y*radius,.42)
	var shoulder: Vector3 = actor.visual.joints.LeftArm.global_position
	# The nib is below the grip. Reach-limit the actual hand before recording
	# the nib: writing, solved wrist, visible quill and collision share one path.
	var hand: Vector3 = shoulder+(target+Vector3.UP*.16-shoulder).limit_length(.565)
	desired_tip = hand-Vector3.UP*.16

func sample(delta: float, tip: Vector3) -> void:
	if action==&"": return
	_sample_clock += delta
	if _sample_clock<settings.sampling_interval: return
	_sample_clock = fmod(_sample_clock,settings.sampling_interval)
	# A 30-Hz sample can skip the brief pen lift entirely. Keep the two X
	# diagonals separate even when both sampled endpoints have the pen down.
	if _has_last and _pen_down and _was_down and _stroke_id==_last_stroke_id:
		var length := tip.distance_to(_last)
		# Teleports must never write a line across the map. Ordinary fast aerial
		# movement is sampled into bounded pieces, without a movement speed cap.
		if length<maxf(3,actor.velocity.length()*delta*3):
			var count := clampi(ceili(length/.16),1,16)
			for i in range(count):
				var a := _last.lerp(tip,float(i)/count)
				var b := _last.lerp(tip,float(i+1)/count)
				if a.distance_squared_to(b)<.000004: continue
				var points := PackedVector3Array([a,b])
				_distance += a.distance_to(b)
				if _distance>=settings.equation_spacing:
					_distance = fmod(_distance,settings.equation_spacing)
					var tangent := (b-a).normalized()
					var up := Moves.writing_basis(combat.trace_aim_direction()).y
					up = (up-tangent*up.dot(tangent)).normalized()
					if up.is_zero_approx(): up = Vector3.RIGHT
					var expression: String = EXPRESSIONS[_expression]
					var character := expression[_character]
					for point: Vector3 in glyph_strokes[character]:
						points.append((a+b)*.5+(tangent*point.x+up*(point.y+.055))*float(settings.glyph_scale))
					_character += 1
					if _character>=expression.length():
						_character = 0
						_expression = (_expression+1)%EXPRESSIONS.size()
				append_section(points)
	_last = tip
	_has_last = true
	_was_down = _pen_down
	_last_stroke_id = _stroke_id

func append_section(points: PackedVector3Array) -> void:
	if points.size()<2: return
	_serial += 1
	var bounds := AABB(points[0],Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	Persistence.append(sections,{"points":points,"bounds":bounds.grow(settings.thickness),"born":time,"owner":weakref(actor),"source":actor.combat_point(),"offset":Vector3.ZERO,"before":Vector3.ZERO,"velocity":Vector3.ZERO,"reflected":false,"serial":_serial},settings.maximum_sections)
	var strokes := 0
	for section in sections: strokes += section.points.size()/2
	while strokes>settings.maximum_strokes and not sections.is_empty(): strokes -= sections.pop_front().points.size()/2
	_dirty = true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.health<=0 or actor.get("transition_locked")==true:
		clear()
		return
	time += delta
	if Persistence.expire(sections,time,settings.lifetime): _dirty = true
	for section in sections:
		section.before = section.offset
		if section.reflected:
			var motion: Vector3 = section.velocity*delta
			var a: Vector3 = section.bounds.get_center()+section.offset
			var owner: Node = section.owner.get_ref()
			var excluded: Array[RID] = [actor.get_rid()]
			if owner is CollisionObject3D: excluded.append(owner.get_rid())
			var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,a+motion,9,excluded))
			if not wall.is_empty(): section.born = time-settings.lifetime
			else: section.offset += motion
			_dirty = true
	resolve_contacts()
	_draw_clock -= delta
	if _draw_clock<=0 or _dirty and multimesh.visible_instance_count==0:
		redraw()
		_draw_clock = 1.0/30.0
		_dirty = false
	if action==&"" and sections.is_empty(): clear()

func targets() -> Array[Node3D]:
	_targets.clear()
	_seen.clear()
	_targets.append(actor)
	_seen[actor.get_instance_id()] = true
	for group: StringName in [&"combat_targets",&"vehicle_wave_targets"]:
		for target: Node in get_tree().get_nodes_in_group(group):
			if target is Node3D and not _seen.has(target.get_instance_id()):
				_seen[target.get_instance_id()] = true
				_targets.append(target)
	return _targets

func resolve_contacts() -> void:
	var started := Time.get_ticks_usec()
	var live := {}
	var all_bounds := AABB()
	var has_bounds := false
	for section in sections:
		if time-float(section.born)>=settings.lifetime: continue
		var bound: AABB = section.bounds
		bound.position += section.offset
		var prior: AABB = section.bounds
		prior.position += section.before
		bound = bound.merge(prior)
		all_bounds = all_bounds.merge(bound) if has_bounds else bound
		has_bounds = true
	for target in targets():
		if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_visible_in_tree() or target.get_world_3d()!=get_world_3d(): continue
		var id := target.get_instance_id()
		live[id] = true
		var before: Transform3D = _previous.get(id,target.global_transform)
		_previous[id] = target.global_transform
		if not has_bounds or not target is CollisionObject3D: continue
		# Prepare actual compound hurt volumes once per target, not once per
		# written section. Far-away residents never enter the stroke loops.
		var shapes := hurt_shapes(target,before)
		var nearby := false
		for shape: Dictionary in shapes:
			if all_bounds.intersects(shape.bounds):
				nearby = true
				break
		if not nearby: continue
		for section in sections:
			if time-float(section.born)>=settings.lifetime: continue
			var owner: Node = section.owner.get_ref()
			if not is_instance_valid(owner) or owner==target: continue
			if owner.has_method("can_attack_target") and not owner.can_attack_target(target): continue
			var key := str(owner.get_instance_id())+":"+str(id)
			if float(_hit_until.get(key,0))>time: continue
			var contact := contact_with(section,shapes)
			if contact.is_empty(): continue
			var point: Vector3 = contact.point
			# A written section cannot damage through intervening architecture.
			var excluded: Array[RID] = [target.get_rid()]
			if owner is CollisionObject3D: excluded.append(owner.get_rid())
			var source: Vector3 = section.source+section.offset
			if not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(source,point,9,excluded)).is_empty(): continue
			_hit_until[key] = time+settings.contact_interval
			var move := {"name":"Reflected Equation" if section.reflected else "Equation Trace","action":&"equation_trace","damage":settings.damage,"parryable":not section.reflected,"reflected":section.reflected,"hit_stun_level":0.0,"hit_stagger":0.0,"attack_serial":get_instance_id()+int(section.serial),"pulse":int(time/settings.contact_interval),"contact":point,"hurtbox_shape":contact.shape}
			if target.has_method("receive_combat_hit"): target.receive_combat_hit(settings.damage,source,owner,move)
			elif target.has_method("receive_hit"): target.receive_hit(settings.damage,source)
			var weapon: Node = target.get("weapon_combat")
			if is_instance_valid(weapon) and weapon.last_parried and not section.reflected:
				reflect_at(point,target)
				break
	for id in _previous.keys():
		if not live.has(id): _previous.erase(id)
	for key: String in _hit_until.keys():
		if float(_hit_until[key])+settings.lifetime<time: _hit_until.erase(key)
	last_contact_microseconds = Time.get_ticks_usec()-started

func hurt_shapes(target: CollisionObject3D, before: Transform3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for owner_id: int in target.get_shape_owners():
		if target.is_shape_owner_disabled(owner_id): continue
		var local: Transform3D = target.shape_owner_get_transform(owner_id)
		var at := target.global_transform*local
		var old := before*local
		for index in range(target.shape_owner_get_shape_count(owner_id)):
			var shape: Shape3D = target.shape_owner_get_shape(owner_id,index)
			var radius := .3
			var half_axis := 0.0
			var box := Vector3.ZERO
			if shape is CapsuleShape3D:
				radius = shape.radius*maxf(at.basis.x.length(),at.basis.z.length())
				half_axis = maxf(0,shape.height*.5-shape.radius)*at.basis.y.length()
			elif shape is SphereShape3D:
				var scale := at.basis.get_scale().abs()
				radius = shape.radius*scale[scale.max_axis_index()]
			elif shape is BoxShape3D:
				box = shape.size*.5
				radius = (at.basis*box).length()
			else: continue
			var bound := AABB(old.origin-Vector3.ONE*(radius+half_axis),Vector3.ONE*(radius+half_axis)*2).expand(at.origin-Vector3.ONE*(radius+half_axis)).expand(at.origin+Vector3.ONE*(radius+half_axis))
			result.append({"at":at,"old":old,"radius":radius,"half_axis":half_axis,"box":box,"bounds":bound,"index":target.shape_owner_get_shape_index(owner_id,index)})
	return result

func contact_with(section: Dictionary, shapes: Array[Dictionary]) -> Dictionary:
	# Use the actor's real compound hurt shapes, including Lorai's body links.
	# Swept shape interpolation catches fast crossings between physics samples.
	var trail_bounds: AABB = section.bounds
	trail_bounds.position += section.offset
	var prior_bounds: AABB = section.bounds
	prior_bounds.position += section.before
	trail_bounds = trail_bounds.merge(prior_bounds)
	for shape: Dictionary in shapes:
		if not trail_bounds.intersects(shape.bounds): continue
		var at: Transform3D = shape.at
		var old: Transform3D = shape.old
		var radius: float = shape.radius
		var box: Vector3 = shape.box
		var motion: Vector3 = at.origin-old.origin-(section.offset-section.before)
		var samples := clampi(ceili(motion.length()/maxf(.04,minf(radius,.25)))+1,1,128)
		for sample_index in range(samples):
			var ratio := float(sample_index)/maxi(1,samples-1)
			var pose := old.interpolate_with(at,ratio)
			var offset: Vector3 = section.before.lerp(section.offset,ratio)
			for stroke in range(0,section.points.size(),2):
				var a: Vector3 = section.points[stroke]+offset
				var b: Vector3 = section.points[stroke+1]+offset
				if box!=Vector3.ZERO:
					var inverse := pose.affine_inverse()
					var scale := pose.basis.get_scale().abs()
					var grow: float = settings.thickness/maxf(.01,scale[scale.min_axis_index()])
					if not segment_box(inverse*a,inverse*b,box+Vector3.ONE*grow): continue
				else:
					var axis: Vector3 = pose.basis.y.normalized()*float(shape.half_axis)
					var closest := Geometry3D.get_closest_points_between_segments(a,b,pose.origin-axis,pose.origin+axis)
					if closest[0].distance_to(closest[1])>radius+settings.thickness: continue
				return {"point":Geometry3D.get_closest_point_to_segment(pose.origin,a,b),"shape":shape.index}
	return {}

static func segment_box(a: Vector3, b: Vector3, half: Vector3) -> bool:
	var low := 0.0
	var high := 1.0
	var direction := b-a
	for axis in range(3):
		if absf(direction[axis])<.000001:
			if absf(a[axis])>half[axis]: return false
		else:
			var entry: float = (-half[axis]-a[axis])/direction[axis]
			var exit: float = (half[axis]-a[axis])/direction[axis]
			low = maxf(low,minf(entry,exit))
			high = minf(high,maxf(entry,exit))
			if low>high: return false
	return true

func reflect_at(point: Vector3, defender: Node3D) -> void:
	var weapon: Node = defender.get("weapon_combat")
	var direction: Vector3 = weapon.aim_direction() if is_instance_valid(weapon) else defender.global_basis.z
	direction.y = 0
	if direction.is_zero_approx(): direction = Vector3.FORWARD
	direction = direction.normalized()
	for section in sections:
		if section.reflected: continue
		var bound: AABB = section.bounds.grow(.75)
		bound.position += section.offset
		if not bound.has_point(point): continue
		section.reflected = true
		section.owner = weakref(defender)
		section.source = defender.combat_point() if defender.has_method("combat_point") else defender.global_position
		section.offset += direction*.75
		section.before = section.offset
		section.velocity = direction*float(settings.reflection_speed)
		reflected_count += 1
	_dirty = true

func redraw() -> void:
	var count := 0
	var bounds := AABB()
	for section in sections:
		var alpha := section_opacity(section)
		if alpha<=0: continue
		var color := Color("9feaff") if section.reflected else Moves.INK_COLOR
		color.a = alpha
		for index in range(0,section.points.size(),2):
			if count>=multimesh.instance_count: break
			var a: Vector3 = section.points[index]+section.offset
			var b: Vector3 = section.points[index+1]+section.offset
			var direction := b-a
			var frame := Basis(Quaternion(Vector3.UP,direction.normalized())) if direction.length_squared()>.000001 else Basis.IDENTITY
			multimesh.set_instance_transform(count,Transform3D(frame*Basis.from_scale(Vector3(1,maxf(.001,direction.length()),1)),(a+b)*.5))
			multimesh.set_instance_color(count,color)
			bounds = AABB(a,Vector3.ZERO) if count==0 else bounds.expand(a)
			bounds = bounds.expand(b)
			count += 1
	multimesh.visible_instance_count = count
	if count>0: custom_aabb = bounds.grow(settings.thickness)

func section_opacity(section: Dictionary) -> float:
	return Persistence.opacity(section.born,time,settings.lifetime,settings.fade_duration)
