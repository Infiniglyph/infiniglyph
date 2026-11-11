extends CharacterBody3D
const Visual = preload("res://scripts/resident_visual.gd")
const Profiles = preload("res://scripts/resident_profiles.gd")
var population: Node3D
var profile: Dictionary
var visual: Node3D
var caption: Label3D
var nameplate: Label3D
var goal: StringName
var path := PackedVector3Array()
var cursor := 0
var routine_index := 0
var arrivals := 0
var conversations := 0
var visits := 0
var wait := 0.0
var social_cooldown := 4.0
var reaction_cooldown := 0.0
var reaction_time := 0.0
var speech_time := 0.0
var reply_time := 0.0
var reply := ""
var partner_id: StringName
var last_meeting := "the central plaza"
var state := "taking a break"
var speed := 1.4
var _stuck := 0.0
var _previous := Vector3.ZERO
var _view_clock := 0.0
var _animate_clock := 0.0
var render_relevant := true
var animation_interval := -1.0
var active := false
var home_building: StringName
var indoor_left := 0.0
var transit: StringName = &"indoor"
var travel_door: Node3D
var pending_door: Node3D
var outdoor_stops := 0
var stops_before_indoor := 2
var neighbours: Array[CharacterBody3D] = []
var probe_clock := 0.0
var probe_requested := Vector3.ZERO
var probe_heading := Vector3.ZERO
var body_shape: CollisionShape3D
var light: OmniLight3D
var exits := 0
var entries := 0
var _curb_hold := 0.0
var virtualized := false

func _ready() -> void:
	name = profile.name
	collision_layer = 4 # Physical residents, separate from architecture/hurtboxes.
	collision_mask = 13
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.85
	capsule.radius = 0.27
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)
	body_shape = shape
	visual = Visual.new()
	visual.body_profile = profile.get("body_profile",&"male")
	var index: int = profile.serial
	visual.stature = 0.96+float(index%4)*0.025
	visual.tint = profile.tint
	visual.phase = index*0.7
	add_child(visual)
	if profile.color_name=="orange":
		light = OmniLight3D.new()
		light.position.y = 1.1
		light.light_color = visual.tint
		light.light_energy = 0.45
		light.omni_range = 2.0
		light.shadow_enabled = false
		add_child(light)
	nameplate = label_at(2.08,29,0.003)
	nameplate.text = profile.name+"  /  "+profile.role
	caption = label_at(2.65,30,0.0035)
	caption.width = 460
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.hide()
	speed = 1.35+float(index%5)*0.09
	wait = 1.0+float(index%4)*0.7
	social_cooldown = 0.8+float(index)*0.05
	goal = profile.home
	_previous = position
	stops_before_indoor = 2+index%3
	deactivate()

func activate(at: Vector3) -> void:
	virtualized = false
	active = true
	transit = &"outdoor"
	global_position = at
	velocity = Vector3.ZERO
	_previous = at
	path.clear()
	cursor = 0
	probe_clock = 0
	_curb_hold = 0
	floor_snap_length = 0.3
	wait = 0
	state = "walking"
	travel_door = null
	pending_door = null
	collision_layer = 4
	collision_mask = 13
	body_shape.disabled = false
	set_physics_process(true)
	show()
	if not self in population.active_residents: population.active_residents.append(self)

func deactivate() -> void:
	virtualized = false
	active = false
	transit = &"indoor"
	state = "indoors"
	collision_layer = 0
	collision_mask = 0
	body_shape.disabled = true
	velocity = Vector3.ZERO
	path.clear()
	neighbours.clear()
	speech_time = 0
	reply_time = 0
	set_physics_process(false)
	hide()

func label_at(height: float, font: int, pixels: float) -> Label3D:
	var label := Label3D.new()
	label.position.y = height
	label.font_size = font
	label.pixel_size = pixels
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.65,0.91,0.94)
	label.outline_size = 8
	add_child(label)
	return label

func say(text: String, seconds: float = 5.0) -> void:
	caption.text = text
	speech_time = seconds
	caption.visible = global_position.distance_to(population.player.global_position)<18 and (population.speaker_time<=0 or population.speaker==self)

func go_to(destination: StringName) -> void:
	if is_instance_valid(travel_door): travel_door.release(self)
	travel_door = null
	transit = &"outdoor"
	pending_door = population.entrances.get(destination)
	goal = destination
	path = population.route(global_position,destination,virtualized)
	if not virtualized and pending_door==null and not path.is_empty():
		var last := path[path.size()-1]
		var angle := float(profile.serial%8)*TAU/8
		var floor: Dictionary = population.floor_at(last+Vector3(cos(angle),0,sin(angle))*0.85)
		if not floor.is_empty() and population.segment_clear(last,floor.point): path.append(floor.point)
	cursor = 0
	state = "walking"
	wait = 0
	_stuck = 0
	if path.is_empty(): wait = 3.0

func next_stop() -> void:
	routine_index += 1
	go_to(population.choose_destination(self))

func arrived() -> void:
	path.clear()
	cursor = 0
	if transit==&"exiting":
		travel_door.exits += 1
		population.indoor_exits += 1
		exits += 1
		travel_door.release(self)
		travel_door = null
		transit = &"outdoor"
		wait = 0.2
		state = "walking"
		return
	if transit in [&"entering",&"waiting_hidden"]:
		transit = &"waiting_hidden"
		state = "inside the lobby"
		if population.finish_indoor(self): entries += 1
		return
	if is_instance_valid(pending_door):
		if pending_door.claim(self):
			travel_door = pending_door
			pending_door = null
			transit = &"entering"
			state = "entering a building"
			path = travel_door.passage(true)
			wait = 0
		else:
			state = "waiting at the doorway"
			wait = 1.5
		return
	arrivals += 1
	outdoor_stops += 1
	wait = population.rng.randf_range(2.5,7)
	state = "checking lamps" if profile.role=="lamp tender" else ("tending the court" if profile.role=="gardener" else "taking a break")

func talk() -> String:
	visits += 1
	reply_time = 0
	population.speaker = self
	population.speaker_time = 5.5
	for resident: CharacterBody3D in population.residents:
		if resident!=self: resident.caption.hide()
	var text: String
	if reaction_time>0: text = "Give us room. Take the fighting away from the walkway."
	elif visits==1: text = Profiles.VOICES.get(profile.id,Profiles.GREETINGS[profile.attitude])
	elif visits==2: text = Profiles.AGAIN[profile.attitude]
	elif visits%3==0:
		var contact: Node3D = population.by_id[profile.contacts[0]]
		text = "%s? %s %s." % [contact.profile.name,"We last spoke near" if partner_id==contact.profile.id else "I usually catch up with them near",last_meeting if partner_id==contact.profile.id else population.place_name(profile.meeting)]
	elif visits%3==1:
		text = "I'm heading to %s. %s" % [population.place_name(goal),"The lamps need checking." if profile.role=="lamp tender" else ("I like having a familiar route." if profile.role=="resident" else "There is always something to do.")]
	else: text = "Ember spars by the eastern sentries. Ask first. The rest of us need the street."
	wait = maxf(wait,5.5)
	state = "talking"
	face(population.player.global_position,1)
	say(text,5.5)
	return profile.name+": "+text

func face(point: Vector3, weight: float) -> void:
	var direction := point-global_position
	if Vector2(direction.x,direction.z).length()>0.05:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(direction.x,direction.z),weight)

func react_to_fight(source: Vector3) -> void:
	if reaction_cooldown>0: return
	reaction_cooldown = 14
	reaction_time = 3.5
	wait = 0
	state = "making room"
	say("Keep your fighting away from us!" if profile.attitude=="dismissive" else "Careful! Give them some room.",3.5)
	# Pick an existing reachable destination away from what was actually observed.
	var escape: StringName = population.escape_stop(global_position,source)
	go_to(escape)
	state = "making room"

func set_virtualized(value: bool) -> bool:
	if not active or virtualized==value: return true
	if not value:
		var floor: Dictionary = population.floor_at(global_position)
		if floor.is_empty() or not population.spawn_space_free(self,floor.point): return false
		global_position = floor.point
	virtualized = value
	collision_layer = 0 if value else 4
	collision_mask = 0 if value else 13
	body_shape.disabled = value
	velocity = Vector3.ZERO
	_previous = global_position
	probe_clock = 0
	_curb_hold = 0
	set_physics_process(not value)
	visible = not value
	return true

func advance_virtual(delta: float) -> void:
	if not active or not virtualized: return
	wait = maxf(0,wait-delta)
	social_cooldown = maxf(0,social_cooldown-delta)
	reaction_cooldown = maxf(0,reaction_cooldown-delta)
	reaction_time = maxf(0,reaction_time-delta)
	speech_time = maxf(0,speech_time-delta)
	reply_time = maxf(0,reply_time-delta)
	if wait>0: return
	if path.is_empty():
		if transit==&"waiting_hidden" or is_instance_valid(pending_door): arrived()
		else: next_stop()
	if not active: return
	var remaining := speed*delta
	# All segments belong to the validated pedestrian graph/door passages.
	# Preserve journeys and building visits without movement/ground probes.
	while cursor<path.size() and remaining>0:
		var distance := global_position.distance_to(path[cursor])
		if distance<=remaining:
			global_position = path[cursor]
			remaining -= distance
			cursor += 1
			if cursor==path.size():
				arrived()
				break
		else:
			global_position = global_position.move_toward(path[cursor],remaining)
			remaining = 0

func _physics_process(delta: float) -> void:
	if not active: return
	_curb_hold = maxf(0,_curb_hold-delta)
	probe_clock -= delta
	wait = maxf(0,wait-delta)
	social_cooldown = maxf(0,social_cooldown-delta)
	reaction_cooldown = maxf(0,reaction_cooldown-delta)
	reaction_time = maxf(0,reaction_time-delta)
	speech_time = maxf(0,speech_time-delta)
	if reply_time>0:
		reply_time -= delta
		if reply_time<=0 and reaction_time==0: say(reply,3.5)
	var desired := Vector3.ZERO
	if wait<=0:
		if path.is_empty():
			if transit==&"waiting_hidden" or is_instance_valid(pending_door): arrived()
			else: next_stop()
		if not active: return
		if cursor<path.size():
			if transit==&"outdoor": state = "making room" if reaction_time>0 else "walking"
			var target := path[cursor]
			var flat := Vector3(target.x-global_position.x,0,target.z-global_position.z)
			if flat.length()<0.28:
				cursor += 1
				if cursor==path.size():
					arrived()
					if not active: return
			else: desired = flat.normalized()*speed*(1.45 if reaction_time>0 else 1.0)
	else:
		if state=="talking": face(population.player.global_position,1-exp(-6*delta))
		elif is_instance_valid(population.by_id.get(partner_id)) and social_cooldown>20:
			face(population.by_id[partner_id].global_position,1-exp(-5*delta))
	desired = population.steer(self,desired)
	velocity.x = move_toward(velocity.x,desired.x,5*delta)
	velocity.z = move_toward(velocity.z,desired.z,5*delta)
	if _curb_hold>0: velocity.y = 0
	elif not is_on_floor(): velocity.y -= 22*delta
	else: velocity.y = 0
	var motion := Vector3(velocity.x,0,velocity.z)*delta
	if is_on_floor() and motion.length()>0.001 and test_move(global_transform,motion):
		var raised := global_transform.translated(Vector3.UP*0.22)
		var landing := KinematicCollision3D.new()
		if not test_move(global_transform,Vector3.UP*0.22) and not test_move(raised,motion):
			raised.origin += motion.normalized()*0.28
			if test_move(raised,Vector3.DOWN*0.24,landing) and landing.get_normal().y>0.8:
				var rise := 0.22-landing.get_travel().length()
				if rise>0:
					move_and_collide(Vector3.UP*rise)
					# Let the leading foot clear the curb before floor snap can pull
					# the capsule down to the lower paving behind the rounded heel.
					_curb_hold = 0.3
	floor_snap_length = 0.0 if _curb_hold>0 else 0.3
	move_and_slide()
	var planar := Vector2(velocity.x,velocity.z).length()
	if planar>0.1: face(global_position+Vector3(velocity.x,0,velocity.z),1-exp(-8*delta))
	if desired.length()>0.5 and position.distance_to(_previous)<0.003: _stuck += delta
	else: _stuck = maxf(0,_stuck-delta*0.5)
	# Retry from actual footing; never teleport through a building or rail.
	if _stuck>2.5 and transit==&"outdoor":
		path = population.route(global_position,goal)
		cursor = 0
		wait = 0.8
		_stuck = 0
	_previous = position
	_animate_clock += delta
	var distance := global_position.distance_to(population.player.global_position)
	var interval := 1.0/15.0 if distance>55 else (1.0/30.0 if distance>25 else 0.0)
	if animation_interval>=0: interval = animation_interval
	if render_relevant and _animate_clock>=interval:
		visual.animate(_animate_clock,planar,speech_time>0 and planar<0.25)
		_animate_clock = 0
	_view_clock -= delta
	if _view_clock<=0:
		_view_clock = 0.2
		nameplate.visible = distance<8
		caption.visible = speech_time>0 and distance<18 and (population.speaker_time<=0 or population.speaker==self)
		if light!=null: light.visible = distance<16
