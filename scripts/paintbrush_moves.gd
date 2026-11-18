extends RefCounted
const Settings = preload("res://scripts/paintbrush_settings.gd")
const TIP := Vector3(0,.45,0)
const ART_NAMES := ["Square Tracing","Triangle Tracing","Cross Tracing","Circle Tracing"]

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
	rig.orient_hand(rig.left_hand,Basis.IDENTITY)
