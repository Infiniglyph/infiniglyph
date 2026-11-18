extends "res://scripts/weapon_combat.gd"
## Presentation adapter; all hits, arts, guard, parry and stun use WeaponCombat.

func apply_pose(delta: float) -> void:
	super.apply_pose(delta)
	if visual_frozen(): return
	var weight: float = actor.rest_weight
	if weight>0:
		var figure: Node3D = actor.visual
		figure.combat_position(figure.pelvis,figure.pelvis.position.lerp(Vector3(0,.40,-.04),weight))
		for index in range(2):
			var side := -1.0 if index==0 else 1.0
			var id := "LeftLeg" if index==0 else "RightLeg"
			var foot := figure.to_global(Vector3(-side*.10,.055,.34+index*.055))
			var current: Vector3 = figure.joints[id].get_node("Hinge").to_global(Vector3(0,-.45,0))
			figure.combat_leg(id,current.lerp(foot,weight),figure.global_basis*Vector3(side,.2,.6))
		solve_arm("LeftArm",Vector3(-.35,.29,.22),weight)
		solve_arm("RightArm",Vector3(.35,.29,.22),weight)
	elif actor.state==&"fighting" and active_move.is_empty() and not actor.combat.blocking and not is_staggered():
		if actor.is_on_floor() and Vector2(actor.velocity.x,actor.velocity.z).length()<.4:
			# A grounded, staggered kenjutsu foundation. Travel and attacks retain
			# the shared locomotion and sampled weapon footwork immediately.
			var figure: Node3D = actor.visual
			figure.combat_position(figure.pelvis,Vector3(0,figure.REST_HIP_HEIGHT-.08,0))
			figure.combat_rotation(figure.pelvis,Quaternion.from_euler(Vector3(.05,-.18,0)),1)
			figure.combat_rotation(figure.chest,Quaternion.from_euler(Vector3(.04,.12,0)),1)
			for id: String in ["LeftLeg","RightLeg"]:
				var foot: Vector3 = figure.to_global(Vector3(-.20,.025,.34) if id=="LeftLeg" else Vector3(.20,.025,-.28))
				var support := body.floor_contact(foot)
				if not support.is_empty(): figure.combat_leg(id,support.point,figure.global_basis.z)
		if actor.combat.sheathed:
			# Quiet iai-ready posture: right hand at the hilt, left at the saya.
			solve_arm("RightArm",Vector3(-.16,1.04,.12),1)
			solve_arm("LeftArm",Vector3(-.28,1.0,.05),1)
