extends Node3D
## Shared contextual actions. Seats use the Library's claim/anchor/exit pattern.
const Neon = preload("res://scripts/neon.gd")
const MountedPose = preload("res://scripts/mounted_rider_pose.gd")
const SEATED_HIP_LIFT := 0.08
const SEATED_FORWARD_OFFSET := 0.12
var actor: CharacterBody3D
var session: Node
var life: Node3D
var seats: Array[Dictionary] = []
var seat: Dictionary = {}
var vehicle: CharacterBody3D
var glyph_count: Label
var _layer := 1
var _mask := 5
var _attachment_pose: Dictionary = {}

func _ready() -> void:
	name = "WorldActions"
	actor.world_actions = self
	session.world_actions = self
	var overlay := CanvasLayer.new()
	overlay.layer = 2
	add_child(overlay)
	glyph_count = Label.new()
	glyph_count.name = "HealthGlyphCount"
	glyph_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	glyph_count.position = Vector2(24,-50)
	glyph_count.size = Vector2(280,28)
	glyph_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_count.add_theme_color_override("font_color",Color(0.4,1,0.72))
	glyph_count.add_theme_color_override("font_outline_color",Color.BLACK)
	glyph_count.add_theme_constant_override("outline_size",4)
	glyph_count.add_theme_font_size_override("font_size",18)
	overlay.add_child(glyph_count)
	actor.inventory.changed.connect(refresh_count)
	refresh_count()
	call_deferred("register_seats")

func refresh_count() -> void:
	glyph_count.text = "Health Glyphs  %d" % actor.inventory.count_type(&"health_glyph")

func register_seats() -> void:
	var metro: Node3D = get_parent().find_child("Metropolis",true,false)
	if is_instance_valid(metro):
		for volume: Dictionary in metro.solids:
			if volume.tag in ["BenchSeat","QuarterBenchSeat"]:
				var entry := volume.duplicate()
				entry.kind = volume.tag
				for back: Dictionary in metro.solids:
					if back.tag in ["BenchBack","QuarterBenchBack"] and back.transform.origin.distance_to(volume.transform.origin)<0.8:
						entry.forward = Vector3(volume.transform.origin.x-back.transform.origin.x,0,0).normalized()
						break
				add_seat(entry)
	var regions: Node3D = get_parent().get("wider_world")
	if is_instance_valid(regions):
		for chunk: Node3D in regions.chunks.values():
			for volume: Dictionary in chunk.volumes:
				if volume.kind=="ParkSeat": add_seat(volume)

func add_seat(volume: Dictionary) -> void:
	var shape: BoxShape3D = volume.collider.shape
	var at: Vector3 = volume.transform.origin
	# Hub bench backs face the avenue; park seats face the open center.
	var forward := Vector3(-signf(at.x),0,0)
	if volume.kind=="ParkSeat":
		var center_x := floorf(at.x/64)*64+32
		forward = Vector3(-signf(at.x-center_x),0,0)
	if forward.is_zero_approx(): forward = Vector3.RIGHT
	forward = volume.get("forward",forward)
	seats.append({"point":at+Vector3.UP*(shape.size.y*0.5+0.045+SEATED_HIP_LIFT)+forward*SEATED_FORWARD_OFFSET,"forward":forward,"occupant":null})

func attached() -> bool:
	return not seat.is_empty() or is_instance_valid(vehicle)

func allowed() -> bool:
	return actor.health>0 and not actor.dodge.active and not actor.weapon_combat.is_staggered() and actor.weapon_combat.active_move.is_empty() and actor.combat.charge_action==&""

func nearest() -> Dictionary:
	if attached(): return {"kind":"exit","label":"exit vehicle" if is_instance_valid(vehicle) else "stand up"}
	if not allowed() or not actor.is_on_floor(): return {}
	var best := 2.6
	var result: Dictionary = {}
	if is_instance_valid(life):
		for candidate: CharacterBody3D in life.vehicles.values():
			var d := actor.global_position.distance_to(candidate.global_position)
			if d<best and absf(candidate.signed_speed)<2.5 and visible_between(actor.combat_point(),candidate.global_position+Vector3.UP):
				best = d
				result = {"kind":"vehicle","target":candidate,"label":("take " if candidate.has_driver else "drive ")+candidate.kind}
	for candidate: Dictionary in seats:
		var d: float = actor.combat_point().distance_to(candidate.point)
		if d<best and candidate.occupant==null and visible_between(actor.combat_point(),candidate.point+candidate.forward*0.5+Vector3.UP*0.5):
			best = d
			result = {"kind":"seat","target":candidate,"label":"sit on bench"}
	return result

func visible_between(from: Vector3, to: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from,to,1,[actor.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func interact() -> bool:
	var context := nearest()
	if context.is_empty(): return false
	if context.kind=="exit": return leave()
	if context.kind=="vehicle": return board(context.target)
	seat = context.target
	seat.occupant = actor
	begin_attachment()
	actor.visual.rotation.y = atan2(seat.forward.x,seat.forward.z)
	anchor()
	return true

func begin_attachment() -> void:
	_layer = actor.collision_layer
	_mask = actor.collision_mask
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.dodge.cancel()
	actor.target_lock.clear()
	actor.weapon_combat.cancel()
	actor.combat.reset()
	actor.combat.sheathed = true
	actor.weapon_combat.sync_rig()
	actor.controls.reset_combat_input()
	actor.velocity = Vector3.ZERO
	actor.boost_active = false
	actor.visual.clear_combat_pose()
	actor.visual.rebase_after_phase()
	# Vehicle IK writes all three rotation axes. Keep the complete local pose
	# so locomotion cannot inherit elbow/shoulder twist after dismounting.
	_attachment_pose.clear()
	for node: Node3D in [actor.visual.pelvis,actor.visual.chest]:
		_attachment_pose[node] = node.transform
	for joint: Node3D in actor.visual.joints.values():
		_attachment_pose[joint] = joint.transform
		var hinge: Node3D = joint.get_node("Hinge")
		_attachment_pose[hinge] = hinge.transform
	actor.fall_damage.reset()

func board(candidate: CharacterBody3D) -> bool:
	if attached() or not allowed() or not is_instance_valid(candidate) or actor.global_position.distance_to(candidate.global_position)>3 or absf(candidate.signed_speed)>=2.5: return false
	var theft: bool = not candidate.record.get("taken",false)
	var displaced: CharacterBody3D
	if candidate.has_driver:
		var exit := exit_point(candidate.global_position,candidate.global_basis.x,candidate.get_rid())
		if exit.is_empty():
			session.show_notice("No clear place for the driver to step out.")
			return false
		displaced = life.eject_driver(candidate,exit.point)
	vehicle = candidate
	vehicle.player_driver = actor
	vehicle.has_driver = false
	vehicle.record.taken = true
	begin_attachment()
	actor.camera_rig.arm.add_excluded_object(vehicle.get_rid())
	actor.camera_rig.set_vehicle_mode(true)
	# Start behind the +Z-facing vehicle, then leave orbit entirely to look input.
	actor.camera_rig.yaw = wrapf(vehicle.rotation.y+PI,-PI,PI)
	anchor()
	actor.camera_rig.reset_follow()
	if theft and is_instance_valid(life) and is_instance_valid(life.get("reactions")): life.reactions.observe_theft(vehicle,displaced)
	return true

func exit_point(origin: Vector3, right: Vector3, excluded: RID = RID()) -> Dictionary:
	var exclude: Array[RID] = [actor.get_rid()]
	if excluded.is_valid(): exclude.append(excluded)
	for offset: Vector3 in [right*1.9,-right*1.9,right*3.1,-right*3.1,Vector3(0,0,3.4),Vector3(0,0,-3.4)]:
		var ray := PhysicsRayQueryParameters3D.create(origin+offset+Vector3.UP*2,origin+offset-Vector3.UP*3,1,exclude)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<0.7 or hit.collider is CharacterBody3D: continue
		var point: Vector3 = hit.position+Vector3.UP*0.04
		var query: PhysicsShapeQueryParameters3D = actor.unstuck.query_at(point)
		query.collision_mask = 13 # Other vehicles are occupied exit space too.
		query.exclude = exclude
		if get_world_3d().direct_space_state.intersect_shape(query,1).is_empty() and actor.unstuck.broad_support(point): return {"point":point}
	return {}

func vehicle_exit_point(car: CharacterBody3D) -> Dictionary:
	# Keep the capsule outside the whole vehicle, and sweep its route through
	# nearby scenery. A far-side point must not let an exit cross a solid wall.
	var origin: Vector3 = car.to_global(Vector3(0,0.12,car.seat_z))
	var right: Vector3 = car.global_basis.x
	var forward: Vector3 = car.global_basis.z
	var end_clearance: float = car.dimensions.z*0.5+0.8
	var offsets: Array[Vector3] = [right*1.9,-right*1.9,right*3.1,-right*3.1,forward*(end_clearance-car.seat_z),-forward*(end_clearance+car.seat_z)]
	var space := get_world_3d().direct_space_state
	var excluded: Array[RID] = [actor.get_rid(),car.get_rid()]
	for offset: Vector3 in offsets:
		var point := origin+offset
		if car.is_on_floor():
			var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*3,1,excluded)
			var hit := space.intersect_ray(ray)
			if not hit.is_empty() and hit.normal.y>=0.7 and not hit.collider is CharacterBody3D:
				var grounded: Vector3 = hit.position+Vector3.UP*0.04
				if actor.unstuck.broad_support(grounded): point = grounded
		# Airborne vehicles and a door beside an edge may have no floor. Exit
		# at the current height instead of snapping to distant ground below.
		var query: PhysicsShapeQueryParameters3D = actor.unstuck.query_at(point)
		query.collision_mask = 13
		query.exclude = [actor.get_rid()]
		if not space.intersect_shape(query,1).is_empty(): continue
		query.transform = actor.unstuck.query_at(origin).transform
		query.exclude = excluded
		query.motion = point-origin
		var sweep := space.cast_motion(query)
		if sweep[0]>=0.99999: return {"point":point}
	return {}

func leave() -> bool:
	if not attached(): return false
	var leaving_vehicle := is_instance_valid(vehicle)
	var result := vehicle_exit_point(vehicle) if leaving_vehicle else exit_point(seat.point,seat.forward)
	if result.is_empty():
		session.show_notice("Exit blocked. Move the vehicle or clear the space.")
		return false
	detach(leaving_vehicle)
	actor.global_position = result.point
	actor.fall_damage.reset()
	actor.camera_rig.reset_follow()
	return true

func detach(carry_momentum: bool = false) -> void:
	var inherited := Vector3.ZERO
	if not seat.is_empty(): seat.occupant = null
	seat = {}
	if is_instance_valid(vehicle):
		if carry_momentum: inherited = vehicle.velocity
		vehicle.player_driver = null
		if not carry_momentum: vehicle.signed_speed = 0
		vehicle.record.taken = true
		actor.camera_rig.arm.remove_excluded_object(vehicle.get_rid())
	vehicle = null
	actor.camera_rig.set_vehicle_mode(false)
	actor.collision_layer = _layer
	actor.collision_mask = _mask
	actor.velocity = inherited
	actor.visual.clear_combat_pose()
	for node: Node3D in _attachment_pose:
		if is_instance_valid(node): node.transform = _attachment_pose[node]
	_attachment_pose.clear()
	actor.visual.position = Vector3.ZERO
	actor.visual.rotation.x = 0
	actor.visual.rebase_after_phase()
	actor.visual._initialized = false
	actor.fall_damage.reset()
	actor.controls.reset_combat_input()

func anchor() -> void:
	if is_instance_valid(vehicle):
		var contacts: Dictionary = vehicle.rider_anchors()
		actor.global_position = vehicle.to_global(contacts.hip-Vector3.UP*0.946)
		actor.visual.rotation.y = vehicle.rotation.y
		actor.velocity = vehicle.velocity
	elif not seat.is_empty():
		actor.global_position = seat.point-Vector3.UP*0.946
		actor.velocity = Vector3.ZERO

func step(_delta: float) -> bool:
	if not attached(): return false
	if not is_instance_valid(vehicle) and (actor.controls.move.length()>0.15 or actor.controls.consume_jump()):
		leave()
		return true
	actor.controls.consume_jump()
	actor.controls.consume_dodge()
	actor.controls.consume_combat_requests()
	actor.controls.consume_lock_requests()
	actor.controls.boost = false
	anchor()
	return true

func apply_pose() -> void:
	if not attached(): return
	anchor()
	var visual: Node3D = actor.visual
	visual.clear_combat_pose()
	visual.pelvis.position = Vector3(0,0.946,0)
	visual.pelvis.rotation = Vector3.ZERO
	visual.chest.rotation = Vector3(-0.06,0,0)
	if is_instance_valid(vehicle):
		var contacts: Dictionary = vehicle.rider_anchors()
		visual.chest.rotation.x = contacts.chest_pitch
		for side: String in ["Left","Right"]:
			var key := side.to_lower()
			MountedPose.solve_limb(visual.joints[side+"Leg"],vehicle.to_global(contacts[key+"_foot"]),vehicle.global_basis*contacts.knee_pole,0.45,0.45)
			# Elbows bend down/out while both hands remain on the controls.
			var elbow_pole: Vector3 = contacts.elbow_pole
			elbow_pole.x = -0.35 if side=="Left" else 0.35
			MountedPose.solve_limb(visual.joints[side+"Arm"],vehicle.to_global(contacts[key+"_hand"]),vehicle.global_basis*elbow_pole,0.30,0.29)
		return
	# Preserve the existing bench pose, independently of vehicle contacts.
	for side: String in ["Left","Right"]:
		var leg: Node3D = visual.joints[side+"Leg"]
		leg.rotation = Vector3(-1.14,0,0)
		leg.get_node("Hinge").rotation = Vector3(1.14,0,0)
		var arm: Node3D = visual.joints[side+"Arm"]
		arm.rotation = Vector3(-0.3,0,0)
		arm.get_node("Hinge").rotation = Vector3(-0.65,0,0)
