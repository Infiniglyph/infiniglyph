extends CharacterBody3D
## The same physical vehicle is used by traffic and by the player.
const Chunk = preload("res://scripts/world_chunk.gd")
const Neon = preload("res://scripts/neon.gd")
const PersonVisual = preload("res://scripts/resident_visual.gd")
const MountedPose = preload("res://scripts/mounted_rider_pose.gd")
var life: Node3D
var record: Dictionary
var kind := "car"
var player_driver: CharacterBody3D
var has_driver := false
var signed_speed := 0.0
var seat_height := 0.69
var seat_z := 0.05
var top_speed := 19.0
# Full-lock low-speed radius is about 4.5 m; bound yaw at speed so a sharp
# parking/intersection turn does not become a twitchy high-speed spin.
@export_range(0.01,0.5,0.01) var steering_turn_per_meter := 0.22
@export_range(0.1,4.0,0.1) var steering_max_yaw_rate := 2.1
var dimensions := Vector3(1.85,1.8,4.1)
var driver_visual: Node3D
var wheel_nodes: Array[Node3D] = []
var lamps: Array[SpotLight3D] = []
var _wait := 0.0
var _wheel_phase := 0.0
var _sensor_clock := 0.0
var _blocked := false
var _sensor_yaw := 0.0
var sensor_checks := 0
var _probe := PhysicsShapeQueryParameters3D.new()
var _probe_box := BoxShape3D.new()
var _pose_clock := 0.0
var _wheel_solids: MultiMesh
var _wheel_wires: MultiMesh
var _wheel_sides: Array[float] = []
static var wheel_mesh: CylinderMesh
static var rim_meshes: Dictionary = {}

func _ready() -> void:
	# Register child shapes at the real spawn, never briefly at world origin.
	global_position = record.point
	rotation.y = record.get("yaw",0.0)
	kind = record.kind
	name = kind.capitalize()+"_"+str(record.id)
	if kind=="motorcycle":
		dimensions = Vector3(0.85,1.35,2.35)
		seat_height = 0.98
		seat_z = -0.10
		top_speed = 23
	elif kind=="truck":
		dimensions = Vector3(2.25,2.5,5.4)
		seat_height = 1.02
		seat_z = 1.35
		top_speed = 15
	collision_layer = 8
	collision_mask = 13
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(38)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	shape.position.y = dimensions.y*0.5+0.06
	add_child(shape)
	build_visual()
	_probe.shape = _probe_box
	_probe.collision_mask = 13
	_probe.exclude = [get_rid()]
	_sensor_clock = float(record.id%7)*0.014
	has_driver = record.traffic and not record.taken
	driver_visual.visible = has_driver

func rider_anchors() -> Dictionary:
	# Vehicle-local +Z is forward. Contacts are shared by the player, the
	# traffic driver, the visible controls and garment fitting.
	var hip := Vector3(0,seat_height,seat_z)
	if kind=="motorcycle":
		return {"hip":hip,"left_hand":Vector3(-0.35,1.16,0.58),"right_hand":Vector3(0.35,1.16,0.58),
			"left_foot":Vector3(-0.29,0.43,-0.35),"right_foot":Vector3(0.29,0.43,-0.35),
			"chest_pitch":0.78,"knee_pole":Vector3(0,0,1),"elbow_pole":Vector3(0,-1,-0.1)}
	var foot_y := 0.65 if kind=="truck" else 0.42
	var forward := 0.67 if kind=="truck" else 0.65
	return {"hip":hip,"left_hand":hip+Vector3(-0.22,0.28,0.58),"right_hand":hip+Vector3(0.22,0.28,0.58),
		"left_foot":Vector3(-0.17,foot_y,seat_z+forward),"right_foot":Vector3(0.17,foot_y,seat_z+forward),
		"chest_pitch":0.12,"knee_pole":Vector3(0,0,1),"elbow_pole":Vector3(0,-1,-0.1)}

func build_visual() -> void:
	var batch := Chunk.new()
	add_child(batch)
	var color: Color = record.color
	if kind=="motorcycle":
		batch.box(Vector3(0,0.62,0),Vector3(0.32,0.36,1.55),"Frame",color)
		batch.box(Vector3(0,0.84,-0.12),Vector3(0.42,0.14,0.8),"Saddle",color)
		batch.box(Vector3(0,1.16,0.58),Vector3(0.83,0.07,0.08),"Handlebars",color)
		# Rear-set pegs sit behind the rider's hips, outside the narrow frame.
		batch.box(Vector3(0,0.355,-0.35),Vector3(0.68,0.06,0.12),"RearSetFootPegs",color)
		# A small nose joins the lenses to the frame, rather than leaving them
		# suspended in front of the wheel beyond the bike's bodywork.
		batch.box(Vector3(0,0.91,0.67),Vector3(0.44,0.24,0.25),"HeadlightFairing",color)
		batch.box(Vector3(0,1.02,0.58),Vector3(0.10,0.25,0.10),"HandlebarStem",color)
	else:
		batch.box(Vector3(0,0.62,0),Vector3(dimensions.x,0.72,dimensions.z),"Chassis",color)
		# Open window apertures show the light-being driver inside the cabin.
		var cab_z := 0.0 if kind=="car" else 1.35
		var roof_y := 1.78 if kind=="car" else 2.1
		batch.box(Vector3(0,roof_y,cab_z-0.1),Vector3(dimensions.x*0.82,0.08,1.65),"Roof",color)
		for side in [-1,1]:
			for end in [-1,1]:
				var bottom := Vector3(side*dimensions.x*0.46,0.98,cab_z+end*0.95)
				var top := Vector3(side*dimensions.x*0.40,roof_y,cab_z+end*0.78-0.1)
				batch.line(bottom,top,color)
			batch.line(Vector3(side*dimensions.x*0.46,1.0,cab_z-0.95),Vector3(side*dimensions.x*0.46,1.0,cab_z+0.95),color)
		if kind=="truck": batch.box(Vector3(0,1.6,-0.85),Vector3(2.18,1.7,2.9),"Cargo",color)
		else:
			# Window divisions and hood seams keep the silhouette legible.
			for side in [-1,1]:
				batch.line(Vector3(side*0.84,1.45,-0.85),Vector3(side*0.84,1.45,0.85),color)
				batch.line(Vector3(side*0.85,0.95,0.93),Vector3(side*0.85,0.95,1.95),color)
		var contacts := rider_anchors()
		var foot_y: float = contacts.left_foot.y
		var foot_z: float = contacts.left_foot.z
		batch.box(Vector3(0,foot_y-0.10,foot_z-0.20),Vector3(0.68,0.06,0.65),"CabinFootwell",color)
		for side in [-1,1]:
			batch.box(Vector3(side*0.17,foot_y-0.065,foot_z),Vector3(0.12,0.04,0.13),"Pedal",color)
		var left_hand: Vector3 = contacts.left_hand
		var right_hand: Vector3 = contacts.right_hand
		batch.box((left_hand+right_hand)*0.5,Vector3(0.53,0.055,0.08),"SteeringYoke",color)
	for axle in [-1,1]:
		var z: float = axle*dimensions.z*0.31
		for side in ([0] if kind=="motorcycle" else [-1,1]):
			var wheel := Node3D.new()
			wheel.position = Vector3(side*dimensions.x*0.5,0.38,z)
			add_child(wheel)
			wheel_nodes.append(wheel)
			_wheel_sides.append(1.0 if side==0 else float(side))
	if wheel_mesh==null:
		wheel_mesh = CylinderMesh.new()
		wheel_mesh.top_radius = 0.36
		wheel_mesh.bottom_radius = 0.36
		wheel_mesh.height = 0.17
		wheel_mesh.radial_segments = 10
	var two_sided := kind=="motorcycle"
	if not rim_meshes.has(two_sided):
		var ring := PackedVector3Array()
		for face in ([-1,1] if two_sided else [1]):
			for n in range(12):
				for i in [n,n+1]: ring.append(Vector3(face*0.095,sin(i*TAU/12)*0.365,cos(i*TAU/12)*0.365))
			for direction in [-1,1]: ring.append_array([Vector3(face*0.096,0,0),Vector3(face*0.096,direction*0.32,0)])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = ring
		var rim := ArrayMesh.new()
		rim.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
		rim_meshes[two_sided] = rim
	_wheel_solids = wheel_batch(wheel_mesh,Neon.dark)
	_wheel_wires = wheel_batch(rim_meshes[two_sided],Neon.shared_material(color))
	update_wheels()
	batch.commit()
	# One envelope on this CharacterBody is the vehicle's collision authority.
	batch.remove_child(batch.body)
	batch.body.free()
	for side in [-1,1]:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(side*0.13,0.93,0.82) if kind=="motorcycle" else Vector3(side*dimensions.x*0.3,0.9,dimensions.z*0.5+0.03)
		lamp.rotation.y = PI
		lamp.light_color = Neon.ORANGE
		lamp.light_energy = 1.5
		lamp.spot_range = 13
		lamp.spot_angle = 38
		lamp.shadow_enabled = false
		add_child(lamp)
		lamps.append(lamp)
		var marker := MeshInstance3D.new()
		var lens := BoxMesh.new()
		lens.size = Vector3(0.18,0.1,0.055)
		lens.material = Neon.shared_material(Neon.ORANGE)
		marker.mesh = lens
		marker.position = lamp.position
		add_child(marker)
	driver_visual = PersonVisual.new()
	driver_visual.tint = record.driver.tint
	driver_visual.body_profile = record.driver.body_profile
	add_child(driver_visual)
	driver_visual.sitting = true
	pose_driver()

func pose_driver() -> void:
	# Traffic uses the same contact anchors as the player. Write the existing
	# two mesh batches directly, so this adds no driver nodes or draw calls.
	var contacts := rider_anchors()
	var hip: Vector3 = contacts.hip
	var lean := Basis(Vector3.RIGHT,contacts.chest_pitch)
	var chest := hip+lean*Vector3.UP*0.51
	var hip_width := 0.18 if driver_visual.body_profile==&"female" else 0.125
	driver_visual.segment(0,hip,chest,0.037)
	driver_visual.segment(1,hip+Vector3(-hip_width,0,0),hip+Vector3(hip_width,0,0))
	driver_visual.segment(2,chest+Vector3(-0.23,0,0),chest+Vector3(0.23,0,0))
	driver_visual.dot_at(0,chest+lean*Vector3.UP*0.26,0.128)
	driver_visual.dot_at(1,hip,0.05)
	for i in range(2):
		var side := -1.0 if i==0 else 1.0
		var key := "left" if i==0 else "right"
		var leg_hip := hip+Vector3(side*hip_width,0,0)
		var foot: Vector3 = contacts[key+"_foot"]
		var knee := MountedPose.bend_point(leg_hip,foot,contacts.knee_pole,0.45,0.45)
		driver_visual.segment(3+i*2,leg_hip,knee)
		driver_visual.segment(4+i*2,knee,foot)
		driver_visual.dot_at(2+i*3,leg_hip)
		driver_visual.dot_at(3+i*3,knee)
		driver_visual.dot_at(4+i*3,foot,0.04)
		var shoulder := chest+Vector3(side*0.23,0,0)
		var hand: Vector3 = contacts[key+"_hand"]
		var elbow_pole: Vector3 = contacts.elbow_pole
		elbow_pole.x = side*0.35
		var elbow := MountedPose.bend_point(shoulder,hand,elbow_pole,0.30,0.29)
		driver_visual.segment(7+i*2,shoulder,elbow)
		driver_visual.segment(8+i*2,elbow,hand)
		driver_visual.dot_at(8+i*2,elbow)
		driver_visual.dot_at(9+i*2,hand,0.04)
		if driver_visual.body_profile==&"female":
			var waist: Vector3 = hip.lerp(chest,0.48)+Vector3(side*0.075,0,0)
			driver_visual.segment(11+i*2,chest+Vector3(side*0.23,0,0),waist,0.023)
			driver_visual.segment(12+i*2,waist,leg_hip,0.023)

func wheel_batch(mesh: Mesh, ink: Material) -> MultiMesh:
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.mesh = mesh
	data.instance_count = wheel_nodes.size()
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = data
	instance.material_override = ink
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return data

func update_wheels() -> void:
	for i in range(wheel_nodes.size()):
		var wheel: Node3D = wheel_nodes[i]
		wheel.rotation.x = _wheel_phase
		_wheel_solids.set_instance_transform(i,wheel.transform*Transform3D(Basis(Vector3.FORWARD,PI*0.5),Vector3.ZERO))
		_wheel_wires.set_instance_transform(i,wheel.transform*Transform3D(Basis.from_scale(Vector3(_wheel_sides[i],1,1)),Vector3.ZERO))

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steering := 0.0
	var desired := 0.0
	if is_instance_valid(player_driver):
		var controls: Node = player_driver.controls
		throttle = -controls.move.y
		steering = controls.move.x
		desired = throttle*(top_speed if throttle>=0 else 6.0)
		# The vehicle's nose is +Z. Its physical right is therefore -X:
		# subtract yaw to steer right, reversing naturally when backing up.
		# Camera yaw/look never participates in either throttle or steering.
		var turn_rate := clampf(signed_speed*steering_turn_per_meter,-steering_max_yaw_rate,steering_max_yaw_rate)
		rotation.y -= steering*turn_rate*delta
	elif has_driver:
		var route: PackedVector3Array = record.route
		var goal: Vector3 = route[record.cursor]
		var offset := goal-global_position
		offset.y = 0
		if offset.length()<4:
			record.cursor = (record.cursor+1)%route.size()
			_wait = 0.85+float(record.id%3)*0.15
			goal = route[record.cursor]
			offset = goal-global_position
		var turn := wrapf(atan2(offset.x,offset.z)-rotation.y,-PI,PI)
		rotation.y += clampf(turn,-1.8*delta,1.8*delta)
		desired = minf(top_speed*0.47,4.0 if absf(turn)>0.38 else top_speed)
		# Pause at each corner; deterministic stagger avoids synchronized convoys.
		_wait = maxf(0,_wait-delta)
		if _wait>0: desired = 0
		_sensor_clock -= delta
		if _sensor_clock<=0 or absf(wrapf(rotation.y-_sensor_yaw,-PI,PI))>0.15:
			_sensor_clock = 0.1
			_sensor_yaw = rotation.y
			# Include travel until the next sensor refresh. Swept body collision
			# remains full-rate and authoritative even if an obstacle appears late.
			_probe_box.size = Vector3(dimensions.x+0.25,1.25,2.0+absf(signed_speed)*0.45)
			_probe.transform = Transform3D(global_basis,global_position+Vector3.UP*0.9+global_basis.z*(dimensions.z*0.5+_probe_box.size.z*0.5+0.3))
			_blocked = not get_world_3d().direct_space_state.intersect_shape(_probe,1).is_empty()
			sensor_checks += 1
		if _blocked: desired = 0
	var rate := 16.0 if desired*signed_speed<0 or absf(desired)<absf(signed_speed) else 7.0
	signed_speed = move_toward(signed_speed,desired,rate*delta)
	velocity.x = global_basis.z.x*signed_speed
	velocity.z = global_basis.z.z*signed_speed
	velocity.y = -0.4 if is_on_floor() else maxf(-30,velocity.y-22*delta)
	move_and_slide()
	if is_on_wall():
		# A sideways brush still permits forward sliding; only lost forward
		# motion slows the vehicle. This avoids sticking beside a pedestrian.
		var forward_speed := velocity.dot(global_basis.z)
		if absf(forward_speed)<absf(signed_speed): signed_speed = move_toward(signed_speed,forward_speed,20*delta)
	record.point = global_position
	record.yaw = rotation.y
	_wheel_phase += signed_speed*delta/0.36
	driver_visual.visible = has_driver
	_pose_clock += delta
	var distance := global_position.distance_squared_to(life.actor.global_position)
	var interval := 0.033 if distance<784 else 0.125
	if life.has_method("pose_interval"): interval = life.pose_interval(global_position)
	if _pose_clock>=interval:
		if absf(signed_speed)>0.01: update_wheels()
		if has_driver and interval<INF: pose_driver()
		_pose_clock = 0
	for lamp: SpotLight3D in lamps: lamp.visible = global_position.distance_squared_to(life.actor.global_position)<6400
	if is_instance_valid(player_driver): player_driver.world_actions.anchor()
