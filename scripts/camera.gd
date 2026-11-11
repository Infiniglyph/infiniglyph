extends Node3D
const DEFAULT_FOLLOW_DISTANCE := 4.2
const MIN_FOLLOW_DISTANCE := 2.4
const MAX_FOLLOW_DISTANCE := 9.0
const VEHICLE_DISTANCE_SCALE := 1.45
@export var mouse_sensitivity := 0.0025
@export var stick_sensitivity := 2.3
@export var follow_speed := 14.0
var yaw := 0.0
var pitch := -0.22
var target: CharacterBody3D
var controls: Node
var arm: SpringArm3D
var camera: Camera3D
var _lock_shoulder := 0.0
var _impact := Vector2.ZERO
var _impact_age := 0.0
var _follow_distance := DEFAULT_FOLLOW_DISTANCE
var _vehicle_mode := false

func get_follow_distance() -> float:
	return _follow_distance

func set_follow_distance(value: float) -> void:
	if not is_finite(value): return
	_follow_distance = clampf(value,MIN_FOLLOW_DISTANCE,MAX_FOLLOW_DISTANCE)
	_apply_follow_distance()

func set_vehicle_mode(value: bool) -> void:
	# Keep the saved on-foot distance while leaving room around the vehicle.
	_vehicle_mode = value
	_apply_follow_distance()

func _apply_follow_distance() -> void:
	if not is_instance_valid(arm): return
	var distance := _follow_distance*(VEHICLE_DISTANCE_SCALE if _vehicle_mode else 1.0)
	if _vehicle_mode and is_instance_valid(target):
		var actions: Node = target.get("world_actions")
		if is_instance_valid(actions):
			var vehicle: Node3D = actions.get("vehicle")
			if is_instance_valid(vehicle):
				# The vehicle is excluded from spring-arm collision. Keep the
				# camera outside its footprint even around the long truck cargo
				# body, whose driver sits well forward of the vehicle center.
				var size: Vector3 = vehicle.dimensions
				var radius := Vector2(size.x*0.5,size.z*0.5+absf(vehicle.seat_z)).length()
				distance = maxf(distance,radius+0.35)
	arm.spring_length = distance

func impact_impulse(direction: Vector3, strength: float) -> void:
	var local := global_basis.inverse()*direction
	_impact = (_impact+Vector2(local.x,0.45+absf(local.z)*0.35)*strength).limit_length(0.1)
	_impact_age = 0

func _ready() -> void:
	arm = SpringArm3D.new()
	_apply_follow_distance()
	arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.22
	arm.shape = probe
	add_child(arm)
	arm.add_excluded_object(target.get_rid())
	camera = Camera3D.new()
	camera.fov = 72
	camera.far = 350
	arm.add_child(camera)
	camera.current = true
	reset_follow()

func reset_follow() -> void:
	_lock_shoulder = 0
	_impact = Vector2.ZERO
	if is_instance_valid(camera):
		camera.h_offset = 0
		camera.v_offset = 0
	global_position = target.global_position + Vector3(0,1.35,0)

func _physics_process(delta: float) -> void:
	_impact_age += delta
	_impact *= exp(-22*delta)
	var shake: bool = target.weapon_combat.rules.camera_shake_enabled
	camera.h_offset = _impact.x*cos(_impact_age*55) if shake else 0.0
	camera.v_offset = _impact.y*cos(_impact_age*48) if shake else 0.0
	var locked: bool = is_instance_valid(target.target_lock) and target.target_lock.is_locked()
	_lock_shoulder = lerpf(_lock_shoulder,0.8 if locked else 0.0,1-exp(-8*delta))
	if locked:
		# Keep the existing collision-aware spring arm. Orbit behind the player
		# toward the opponent; right-stick flicks now select rather than orbit.
		var offset: Vector3 = target.target_lock.point(target.target_lock.opponent)-(target.global_position+Vector3.UP*1.35)
		var planar := Vector2(offset.x,offset.z).length()
		yaw = lerp_angle(yaw,atan2(-offset.x,-offset.z),1-exp(-9*delta))
		var target_pitch := clampf(atan2(offset.y-0.75,planar+2.0),-0.65,0.45)
		pitch = lerpf(pitch,target_pitch,1-exp(-7*delta))
	else:
		yaw -= controls.mouse_look.x * mouse_sensitivity + controls.look.x * stick_sensitivity * delta
		pitch = clampf(pitch-controls.mouse_look.y*mouse_sensitivity-controls.look.y*stick_sensitivity*delta,-1.15,0.65)
	controls.mouse_look = Vector2.ZERO
	rotation = Vector3(pitch,yaw,0)
	# An over-shoulder anchor separates the two silhouettes. Its spring-arm probe
	# still sweeps against structures, including walls beside the player.
	var anchor := target.global_position+Vector3(0,1.35,0)+Basis(Vector3.UP,yaw).x*_lock_shoulder
	if _lock_shoulder>0.001:
		var base := target.global_position+Vector3(0,1.35,0)
		var sweep := PhysicsShapeQueryParameters3D.new()
		sweep.shape = arm.shape
		sweep.transform = Transform3D(Basis.IDENTITY,base)
		sweep.motion = anchor-base
		sweep.margin = 0.03
		sweep.collision_mask = arm.collision_mask
		sweep.exclude = [target.get_rid()]
		var fraction := get_world_3d().direct_space_state.cast_motion(sweep)
		anchor = base+sweep.motion*fraction[0]
	global_position = global_position.lerp(anchor,1.0-exp(-follow_speed*delta))
	# Uncapped aerial speeds must not leave the player outside the camera framing.
	if global_position.distance_to(anchor) > 2.0:
		global_position = anchor+(global_position-anchor).normalized()*2.0
