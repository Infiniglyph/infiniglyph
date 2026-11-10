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

func _ready() -> void:
	profile = record.profile
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
	global_position = record.point

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
	_pose_clock += delta
	var distance := global_position.distance_to(life.actor.global_position)
	if is_instance_valid(light): light.visible = distance<24
	if _pose_clock> (0.033 if distance<28 else 0.15):
		visual.animate(_pose_clock,Vector2(velocity.x,velocity.z).length(),wait>0 and record.meetings>0)
		_pose_clock = 0
	caption.visible = wait>0 and record.meetings>0 and distance<8
