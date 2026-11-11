extends CharacterBody3D
## Identity and journey live in the regional roster, outside animation lifetime.
const Visual = preload("res://scripts/resident_visual.gd")
const Profiles = preload("res://scripts/resident_profiles.gd")
var life: Node3D
var record: Dictionary
var profile: Dictionary
var visual: Node3D
var caption: Label3D
var light: OmniLight3D
var state := "walking the neighborhood"
var wait := 0.0
var _pose_clock := 0.0
var _stalled := 0.0
var virtualized := false
var _render_offset := Vector3.ZERO
var _render_clock := 0.0
var _render_duration := 0.2
var _virtual_speed := 0.0
var _virtual_yaw := 0.0

func _ready() -> void:
	global_position = record.point
	profile = record.profile
	wait = float(record.get("wait",0))
	name = profile.name
	collision_layer = 4
	collision_mask = 13
	floor_snap_length = 0.35
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.85
	capsule.radius = 0.27
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)
	visual = Visual.new()
	visual.tint = profile.tint
	visual.body_profile = profile.body_profile
	visual.phase = float(record.id)*0.43
	add_child(visual)
	if profile.tint==Profiles.PALETTE.orange:
		light = OmniLight3D.new()
		light.position.y = 1.1
		light.light_color = profile.tint
		light.light_energy = 0.45
		light.omni_range = 2.0
		light.shadow_enabled = false
		add_child(light)
	caption = Label3D.new()
	caption.position.y = 2.2
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size = 32
	caption.pixel_size = 0.004
	caption.outline_size = 7
	add_child(caption)
	set_process(false)

func set_virtualized(value: bool) -> bool:
	if virtualized==value or record.get("combat",false): return true
	if not value:
		var at := global_position
		at.y = life.regions.surface_at(at.x,at.z)+0.04
		var excluded: Array[RID] = [get_rid()]
		if not life.pedestrian_clear(at,false,excluded): return false
		global_position = at
		record.point = at
	virtualized = value
	collision_layer = 0 if value else 4
	collision_mask = 0 if value else 13
	velocity = Vector3.ZERO
	set_physics_process(not value)
	set_process(value)
	visual.position = Vector3.ZERO
	_render_offset = Vector3.ZERO
	_virtual_yaw = visual.rotation.y
	return true

func advance_virtual(delta: float) -> void:
	if not virtualized or record.get("combat",false): return
	record.wait = wait
	var before := global_position
	var shown_at := visual.global_position
	life.advance_journey(record,delta)
	wait = record.wait
	global_position = record.point
	_render_offset = to_local(shown_at)
	visual.position = _render_offset
	_render_clock = 0
	_render_duration = delta
	var direction := global_position-before
	_virtual_speed = direction.length()/delta
	if direction.length_squared()>0.00001:
		_virtual_yaw = atan2(direction.x,direction.z)
		state = "walking the neighborhood"

func _process(delta: float) -> void:
	if not virtualized: return
	_render_clock += delta
	_pose_clock += delta
	var interval: float = life.pose_interval(global_position)
	if interval==INF: return
	# Cheap interpolation keeps distant route-record movement smooth, while
	# articulated poses still obey the shared 8-20 Hz attention policy.
	visual.position = _render_offset*(1-clampf(_render_clock/maxf(_render_duration,0.001),0,1))
	visual.rotation.y = lerp_angle(visual.rotation.y,_virtual_yaw,1-exp(-10*delta))
	if _pose_clock>=interval:
		visual.animate(_pose_clock,_virtual_speed,false)
		_pose_clock = 0

func talk() -> void:
	record.meetings += 1
	caption.text = Profiles.GREETINGS[profile.attitude] if record.meetings==1 else Profiles.AGAIN[profile.attitude]
	wait = 6
	state = "talking"

func _physics_process(delta: float) -> void:
	wait = maxf(0,wait-delta)
	var route: PackedVector3Array = record.route
	var goal: Vector3 = route[record.cursor]
	var offset := goal-global_position
	offset.y = 0
	if offset.length()<0.6 and wait<=0:
		record.cursor = (record.cursor+1)%route.size()
		wait = 1.0+float(record.id%5)
		state = "taking a break"
	var direction := offset.normalized() if wait==0 else Vector3.ZERO
	var speed := 1.25+float(record.id%4)*0.12
	velocity.x = direction.x*speed
	velocity.z = direction.z*speed
	velocity.y = -0.3 if is_on_floor() else maxf(-20,velocity.y-22*delta)
	var before := global_position
	move_and_slide()
	if direction.length()>0.1:
		state = "walking the neighborhood"
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(direction.x,direction.z),1-exp(-10*delta))
	_stalled = _stalled+delta if direction.length()>0.1 and before.distance_to(global_position)<delta*0.2 else 0.0
	if _stalled>2:
		record.cursor = (record.cursor+1)%route.size()
		wait = 1
		_stalled = 0
	record.point = global_position
	record.wait = wait
	_pose_clock += delta
	var distance := global_position.distance_to(life.actor.global_position)
	if is_instance_valid(light): light.visible = distance<24
	if _pose_clock>=life.pose_interval(global_position):
		visual.animate(_pose_clock,Vector2(velocity.x,velocity.z).length(),wait>0 and record.meetings>0)
		_pose_clock = 0
	caption.visible = wait>0 and record.meetings>0 and distance<8
