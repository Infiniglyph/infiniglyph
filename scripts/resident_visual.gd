extends Node3D
## Two instanced mesh batches per person, with shared primitive meshes.
## Feet remain connected by a two-bone solve; no network retrieval per pedestrian.
const Neon = preload("res://scripts/neon.gd")
static var rod_mesh: CylinderMesh
static var joint_mesh: SphereMesh
var attire: Node3D
var rods: MultiMesh
var joints: MultiMesh
var phase := 0.0
var clock := 0.0
var walking := 0.0
var stature := 1.0
var body_profile: StringName = &"male"
var tint := Color(0.12,0.82,0.9)
var sitting := false
var activity:=""
var _parcel: MeshInstance3D
var _food_meter: Label3D
var _drip_meter: Label3D
var _water_meter: Label3D
var _status_clock:=0.0

func _status(delta: float) -> void:
	_status_clock+=delta
	if _status_clock<.5: return
	_status_clock=0
	if not has_meta("civilization"): return
	var society: Node=get_meta("civilization")
	if not is_instance_valid(society): return
	var id:=String(get_meta("civilian_id",""))
	if id.is_empty(): return
	var near: bool=society.world.player.get_world_3d()==get_world_3d() and society.world.player.global_position.distance_to(global_position)<10 and is_visible_in_tree()
	if not is_instance_valid(_food_meter):
		if not near: return
		_food_meter=Label3D.new(); _water_meter=Label3D.new(); _drip_meter=Label3D.new()
		for meter: Label3D in [_food_meter,_water_meter,_drip_meter]:
			meter.billboard=BaseMaterial3D.BILLBOARD_ENABLED; meter.font_size=24; meter.pixel_size=.003
			add_child(meter)
		_food_meter.position.y=2.55; _water_meter.position.y=2.40; _drip_meter.position.y=2.25
	var bubble: Label3D=get_parent().get("caption")
	if is_instance_valid(bubble) and bubble.visible and not bubble.text.is_empty(): near=false
	_food_meter.visible=near; _water_meter.visible=near; _drip_meter.visible=near
	if not near: return
	var state: Dictionary=society.autonomy._state(id)
	var store: Node=society.economy.npc_stores.get(id)
	var drip: int=preload("res://scripts/code_form_wardrobe.gd").drip(store) if is_instance_valid(store) else 0
	_drip_meter.text="Drip %d / 100" % drip
	_drip_meter.modulate=Color(.9,.65,1)
	_food_meter.text="Food %d%%" % roundi((1-float(state.hunger))*100)
	_water_meter.text="Water %d%%" % roundi((1-float(state.thirst))*100)
	_food_meter.modulate=Color(1,.25,.12) if state.hunger>=.8 else Color(.6,1,.5)
	_water_meter.modulate=Color(1,.25,.12) if state.thirst>=.8 else Color(.3,.8,1)


func sync_clothing(store: Node) -> void:
	if not is_instance_valid(attire):
		attire=preload("res://scripts/resident_attire.gd").new()
		add_child(attire)
	attire.sync(store)
	animate(0,0,false)

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
	var ink := Neon.shared_material(tint)
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
	_status(delta)
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
	if is_instance_valid(attire):
		attire.at("body",0,pelvis+Vector3(0,.025,0))
		attire.at("head",0,chest+Vector3(0,.13,0))
	dot_at(1,pelvis,0.05)
	for i in range(2):
		var side := -1.0 if i==0 else 1.0
		var cycle: float = phase+(0.0 if i==0 else PI)
		var stride := sin(cycle)*walking
		var hip := pelvis+Vector3(side*hip_width,0,0)
		var foot := Vector3(side*(hip_width+0.015),0.052+maxf(0,cos(cycle))*0.055*walking,stride*0.24)
		if sitting: foot = pelvis+Vector3(side*(hip_width+0.04),-0.65,0.4)
		var knee := knee_between(hip,foot)
		if is_instance_valid(attire):
			attire.at("legs",i*2,hip,knee)
			attire.at("legs",i*2+1,knee,foot)
		segment(3+i*2,hip,knee)
		segment(4+i*2,knee,foot)
		dot_at(2+i*3,hip)
		dot_at(3+i*3,knee)
		dot_at(4+i*3,foot,0.04)
		var shoulder := chest+Vector3(side*0.23,0,side*sway*0.018)
		var elbow := shoulder+Vector3(side*0.035,-0.29,-stride*0.13+0.04)
		var hand := elbow+Vector3(-side*0.025,-0.27,-stride*0.10+0.03)
		if sitting or not activity.is_empty():
			elbow = shoulder+Vector3(0,-0.18,0.23)
			hand = elbow+Vector3(0,-0.12+(sin(clock*8)*.045 if activity=="work" else 0.0),0.22)
		if gesturing and i==1:
			elbow += Vector3(0.08,0.08,0.05)
			hand = elbow+Vector3(0.02,0.02+sin(clock*3)*0.045,0.25)
		if is_instance_valid(attire): attire.at("hands",i,elbow,hand)
		segment(7+i*2,shoulder,elbow)
		segment(8+i*2,elbow,hand)
		dot_at(8+i*2,elbow)
		dot_at(9+i*2,hand,0.04)
		if i==1:
			if not is_instance_valid(_parcel) and activity in ["parcel","meal"]:
				_parcel=MeshInstance3D.new()
				var box:=BoxMesh.new(); box.size=Vector3(.22,.14,.2); _parcel.mesh=box
				_parcel.material_override=Neon.shared_material(Color(.6,.35,.12)); add_child(_parcel)
			if is_instance_valid(_parcel):
				_parcel.visible=activity in ["parcel","meal"]
				_parcel.position=hand+Vector3(0,.055,0)
