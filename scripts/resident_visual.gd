extends Node3D
## Two instanced mesh batches per person, with shared primitive meshes.
## Feet remain connected by a two-bone solve; no network retrieval per pedestrian.
const Neon = preload("res://scripts/neon.gd")
static var rod_mesh: CylinderMesh
static var joint_mesh: SphereMesh
var rods: MultiMesh
var joints: MultiMesh
var phase := 0.0
var clock := 0.0
var walking := 0.0
var stature := 1.0
var body_profile: StringName = &"male"
var tint := Color(0.12,0.82,0.9)

func batch(mesh: Mesh, count: int, ink: Material) -> MultiMesh:
	var instance := MultiMeshInstance3D.new()
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.mesh = mesh
	data.instance_count = count
	instance.multimesh = data
	instance.material_override = ink
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return data

func _ready() -> void:
	if rod_mesh==null:
		rod_mesh = CylinderMesh.new()
		rod_mesh.top_radius = 1
		rod_mesh.bottom_radius = 1
		rod_mesh.height = 1
		rod_mesh.radial_segments = 6
		joint_mesh = SphereMesh.new()
		joint_mesh.radius = 1
		joint_mesh.height = 2
		joint_mesh.radial_segments = 8
		joint_mesh.rings = 4
	var ink := Neon.material(tint)
	rods = batch(rod_mesh,15 if body_profile==&"female" else 11,ink)
	joints = batch(joint_mesh,12,ink)
	scale = Vector3.ONE*stature
	animate(0.01,0,false)

func segment(index: int, a: Vector3, b: Vector3, radius: float = 0.029) -> void:
	var vector := b-a
	# Scale along the cylinder's local axes before rotating it between the joints.
	var basis := Basis(Quaternion(Vector3.UP,vector.normalized())) * Basis.from_scale(Vector3(radius,vector.length(),radius))
	rods.set_instance_transform(index,Transform3D(basis,(a+b)*0.5))

func dot_at(index: int, at: Vector3, radius: float = 0.047) -> void:
	joints.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*radius),at))

func knee_between(hip: Vector3, foot: Vector3) -> Vector3:
	var axis := foot-hip
	var length := minf(axis.length(),0.895)
	# This rig faces +Z, matching the resident's yaw, forward lean and foot swing.
	var forward := Vector3.BACK
	var pole := forward-axis.normalized()*forward.dot(axis.normalized())
	return hip+axis.normalized()*length*0.5+pole.normalized()*sqrt(maxf(0,0.45*0.45-length*length*0.25))

func animate(delta: float, speed: float, gesturing: bool) -> void:
	clock += delta
	walking = lerpf(walking,clampf(speed/1.5,0,1),1-exp(-10*delta))
	phase = fposmod(phase+delta*TAU*1.05*clampf(speed/1.5,0,1.3),TAU)
	var sway := sin(phase)*walking
	var pelvis := Vector3(sway*0.018,0.945-absf(sway)*0.018+sin(clock*1.6)*0.004,0)
	var chest := pelvis+Vector3(-sway*0.012,0.51,walking*0.045)
	var hip_width := 0.18 if body_profile==&"female" else 0.125
	segment(0,pelvis,chest,0.037)
	segment(1,pelvis+Vector3(-hip_width,0,0),pelvis+Vector3(hip_width,0,0))
	segment(2,chest+Vector3(-0.23,0,0),chest+Vector3(0.23,0,0))
	if body_profile==&"female":
		# A narrow waist between the shared shoulder line and broader hips.
		# Keep these in the rod batch so the silhouette adds no draw calls.
		var waist := pelvis.lerp(chest,0.48)
		for i in range(2):
			var side := -1.0 if i==0 else 1.0
			var waist_edge := waist+Vector3(side*0.075,0,0)
			segment(11+i*2,chest+Vector3(side*0.23,0,0),waist_edge,0.023)
			segment(12+i*2,waist_edge,pelvis+Vector3(side*hip_width,0,0),0.023)
	dot_at(0,chest+Vector3(0,0.26,0),0.128)
	dot_at(1,pelvis,0.05)
	for i in range(2):
		var side := -1.0 if i==0 else 1.0
		var cycle: float = phase+(0.0 if i==0 else PI)
		var stride := sin(cycle)*walking
		var hip := pelvis+Vector3(side*hip_width,0,0)
		var foot := Vector3(side*(hip_width+0.015),0.052+maxf(0,cos(cycle))*0.055*walking,stride*0.24)
		var knee := knee_between(hip,foot)
		segment(3+i*2,hip,knee)
		segment(4+i*2,knee,foot)
		dot_at(2+i*3,hip)
		dot_at(3+i*3,knee)
		dot_at(4+i*3,foot,0.04)
		var shoulder := chest+Vector3(side*0.23,0,side*sway*0.018)
		var elbow := shoulder+Vector3(side*0.035,-0.29,-stride*0.13+0.04)
		var hand := elbow+Vector3(-side*0.025,-0.27,-stride*0.10+0.03)
		if gesturing and i==1:
			elbow += Vector3(0.08,0.08,0.05)
			hand = elbow+Vector3(0.02,0.02+sin(clock*3)*0.045,0.25)
		segment(7+i*2,shoulder,elbow)
		segment(8+i*2,elbow,hand)
		dot_at(8+i*2,elbow)
		dot_at(9+i*2,hand,0.04)
