extends RefCounted
const Settings = preload("res://scripts/paintbrush_settings.gd")
const TIP := Vector3(0,.45,0)
const FORWARD_TILT := PI/4
const ART_NAMES := ["Square Tracing","Triangle Tracing","Cross Tracing","Circle Tracing"]

static func brush_basis(yaw: float = 0, roll: float = 0) -> Basis:
	# The figure faces +Z. Tilt the bristles forward from the vertical grip.
	return Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,FORWARD_TILT)*Basis(Vector3.FORWARD,roll)

static func guard_basis(yaw: float) -> Basis:
	return Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,PI/2)

static func guard_frame(actor: Node3D,facing: Vector3) -> Transform3D:
	var basis:=Basis(Vector3.UP,atan2(facing.x,facing.z))
	return Transform3D(basis,actor.combat_point()+basis*Vector3(-.20,.38,.68))

static func guard_pen(time: float) -> Vector3:
	# Three concentric strokes, with a smooth inward/outward transition at
	# each completed revolution. The actual arm and nib draw this same path.
	var cycle:=fposmod(time*.7,3)
	var phase:=fmod(cycle,1)
	var radii: Array[float]=[.29,.21,.13]
	var index:=floori(cycle)
	var radius:=lerpf(radii[index],radii[(index+1)%3],smoothstep(.8,1,phase))
	return Vector3(cos(phase*TAU)*radius,sin(phase*TAU)*radius,0)

static func move(item: Dictionary, action: StringName, tuning: Resource = null) -> Dictionary:
	if tuning==null: tuning = Settings.new()
	var basic := action in [&"attack_left",&"attack_right"]
	var index := [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"].find(action)
	if not basic and index<0: return {}
	return {"name":("Descending Brushstroke" if action==&"attack_left" else "Rising Brushstroke") if basic else ART_NAMES[index],"action":String(action),"item_id":item.id,"weapon_family":"paintbrush","duration":tuning.light_duration,"windup":.08,"hits":[float(tuning.light_duration)*.46],"damage":tuning.light_damage if basic else tuning.damage,"reach":tuning.light_stroke_length,"arc":95.0,"profile":"paint","side":-1 if action==&"attack_left" else 1,"parryable":true,"hit_stun_level":0.0,"hit_stagger":0.0,"body_profile":[.10,.52,.23,.21,.12]}

static func ready_pose(figure: Node3D, rig: Node3D) -> void:
	# Preview uses the same anatomical right hand as combat: historical LeftArm.
	figure.chest.rotation.x = .18
	for arm: String in ["RightArm","LeftArm"]:
		figure.joints[arm].rotation.x = -.38
		figure.joints[arm].get_node("Hinge").rotation.x = -.65 if arm=="LeftArm" else -.18
	rig.orient_hand(rig.left_hand,brush_basis(figure.global_rotation.y))
