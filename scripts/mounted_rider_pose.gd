extends RefCounted
## Shared two-link contact solve. The anchors belong to the physical vehicle;
## camera orbit and frame history never participate in a rider's placement.

static func bend_point(origin: Vector3, target: Vector3, pole_direction: Vector3, upper: float, lower: float) -> Vector3:
	var offset := target-origin
	var distance := clampf(offset.length(),absf(upper-lower)+0.001,upper+lower-0.001)
	var direction := offset.normalized()
	var pole := pole_direction-direction*pole_direction.dot(direction)
	if pole.length_squared()<0.0001:
		pole = Vector3.UP-direction*Vector3.UP.dot(direction)
	pole = pole.normalized()
	var along := (upper*upper-lower*lower+distance*distance)/(2*distance)
	return origin+direction*along+pole*sqrt(maxf(0,upper*upper-along*along))

static func solve_limb(joint: Node3D, target: Vector3, pole_direction: Vector3, upper: float, lower: float) -> void:
	var hinge: Node3D = joint.get_node("Hinge")
	var bend := bend_point(joint.global_position,target,pole_direction,upper,lower)
	var direction := (target-joint.global_position).normalized()
	var pole := (bend-joint.global_position)-direction*(bend-joint.global_position).dot(direction)
	pole = pole.normalized()
	var up := -(bend-joint.global_position).normalized()
	var right := up.cross(pole).normalized()
	var desired := Basis(right,up,right.cross(up))
	# Rotate locally, rather than round-tripping origins through world floats.
	# In particular, this stays stable on distant roads after long drives.
	joint.quaternion = (joint.get_parent().global_basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
	up = -(target-bend).normalized()
	desired = Basis(right,up,right.cross(up))
	hinge.quaternion = (joint.global_basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
