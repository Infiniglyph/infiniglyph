extends "res://scripts/player.gd"
const Brain = preload("res://scripts/pyramid_enemy_brain.gd")
const Appearance = preload("res://scripts/pyramid_enemy_visual.gd")
const NeonInk = preload("res://scripts/neon.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const FalconBrain = preload("res://scripts/falcon_brain.gd")
const FalconCombat = preload("res://scripts/falcon_combat.gd")
const Context = preload("res://scripts/respawn_context.gd")
const Types = preload("res://scripts/pyramid_bestiary.gd")
const DepthBrain = preload("res://scripts/pyramid_depth_brain.gd")
const DepthCombat = preload("res://scripts/pyramid_depth_combat.gd")
class AimFrame extends Node3D:
	var yaw := 0.0
	var camera: Camera3D
	func reset_follow() -> void: pass
var encounter: Node3D
var opponent: CharacterBody3D
var enemy_kind := "skeleton"
var spawn_id := ""
var elite := false
var floor_id: StringName=&"hub"
var floor_y := 0.0
var ceiling_y := 7.0
var dead := false
var label: Label3D
var _awake := true
var traits: Dictionary={}
var support_time:=0.0
var ward_time:=0.0
var reassemble_time:=0.0
var reassembled:=false
var buried:=false
var emergence:=0.0
var aura: Node3D

func create_visual() -> Node3D:
	var result := Appearance.new()
	result.enemy_kind = enemy_kind
	return result

func create_weapon_combat() -> Node:
	if Types.TYPES.has(enemy_kind): return DepthCombat.new()
	return FalconCombat.new() if enemy_kind in ["falcon","winged_skeleton","archer"] else super.create_weapon_combat()

func _ready() -> void:
	live_motion_retrieval = false
	inventory_owner_id = "pyramid_enemy/"+encounter.player.inventory.owner_id+"/"+spawn_id
	traits=Types.get_type(enemy_kind)
	controls = DepthBrain.new() if not traits.is_empty() else FalconBrain.new() if enemy_kind in ["falcon","winged_skeleton","archer"] else Brain.new()
	controls.actor = self
	add_child(controls)
	camera_rig = AimFrame.new()
	camera_rig.camera = opponent.camera_rig.camera
	add_child(camera_rig)
	super._ready()
	respawn_context=Context.new()
	respawn_context.active_location=floor_id
	respawn_context.minimum_heights[floor_id]=floor_y-6
	add_child(respawn_context)
	name = combat_name().replace(" ","")+"_"+spawn_id
	collision_layer = 6
	collision_mask = 9 # Architecture/vehicles; allies don't form doorway wedges.
	if enemy_kind=="jackal":
		for child: Node in get_children():
			if child is CollisionShape3D and child.shape is CapsuleShape3D:
				child.shape.height = 2.30
				child.shape.radius = .30
				child.position.y = 1.15
	walk_speed = 2.4 if enemy_kind=="jackal" else 2.0
	run_speed = walk_speed
	weapon_combat.max_health = (320.0 if elite else 180.0) if enemy_kind=="jackal" else 65.0
	weapon_combat.health = weapon_combat.max_health
	if enemy_kind in ["falcon","winged_skeleton","archer"]:
		walk_speed=5.0 if enemy_kind=="falcon" else 3.8 if enemy_kind=="winged_skeleton" else 2.8
		run_speed=7.6 if enemy_kind=="falcon" else 5.3
		sky_jump_lift=6.4 if enemy_kind=="falcon" else 5.8
		sky_jump_push=1.8
		weapon_combat.max_health=(340.0 if elite else 240.0) if enemy_kind=="falcon" else 90.0 if enemy_kind=="winged_skeleton" else 80.0
		weapon_combat.health=weapon_combat.max_health
	if not traits.is_empty():
		walk_speed=float(traits.speed)
		run_speed=walk_speed*1.1
		weapon_combat.max_health=float(traits.hp)
		weapon_combat.health=weapon_combat.max_health
		weapon_combat.hit_landed.connect(_on_depth_hit)
		if float(traits.get("scale",1))>1.2 and not traits.get("beast",false):
			for child in get_children():
				if child is CollisionShape3D and child.shape is CapsuleShape3D:
					child.shape.height=1.85*minf(float(traits.scale),1.4)
					child.shape.radius=.28*minf(float(traits.scale),1.3)
					child.position.y=child.shape.height*.5
	weapon_combat.momentum_damage_gain = 0
	var weapon: Resource = Catalog.create(StringName(traits.weapon) if not traits.is_empty() else &"horuswing_blades" if enemy_kind=="falcon" else &"warden_khopesh" if enemy_kind=="jackal" else &"tomb_blade")
	inventory.add_item(weapon)
	inventory.assign(&"down",weapon.instance_id)
	combat.selected_slot = &"down"
	combat.sheathed = false
	weapon_combat.sync_rig()
	if enemy_kind=="archer":
		var held: Node3D=weapon_combat.rig.models[weapon.item_type_id].right
		for mesh in held.get_children(): mesh.hide()
		var bow:=PackedVector3Array()
		for i in range(12):
			var a: float=-PI*.5+i*PI/12
			var b: float=-PI*.5+(i+1)*PI/12
			bow.append_array([Vector3(cos(a)*.24,sin(a)*.58,0),Vector3(cos(b)*.24,sin(b)*.58,0)])
		bow.append_array([Vector3(0,-.58,0),Vector3(0,.58,0)])
		held.add_child(NeonInk.lines(bow,NeonInk.shared_material(Color("ffe09a"))))
		weapon_combat.trail.hide()
	if enemy_kind=="jackal" or traits.get("guard",false) and not traits.get("beast",false):
		# NPC guard equipment does not reintroduce the retired player shield slot.
		var shield: Node3D = weapon_combat.rig.model(&"shield",Color("ffc65e"))
		weapon_combat.rig.models[weapon.item_type_id].left.add_child(shield)
		var ornament := PackedVector3Array()
		for i in range(16):
			var a := i*TAU/16
			var b := (i+1)*TAU/16
			ornament.append_array([Vector3(cos(a)*.08,.27+sin(a)*.10,.055),Vector3(cos(b)*.08,.27+sin(b)*.10,.055)])
		ornament.append_array([Vector3(0,.17,.055),Vector3(0,-.20,.055),Vector3(-.11,.09,.055),Vector3(.11,.09,.055)])
		shield.add_child(NeonInk.lines(ornament,NeonInk.shared_material(Color("64ffff"))))
	target_lock.show_marker = false
	add_to_group("combat_targets")
	dodge.set_tint(Color("ffd170"))
	dodge.cache_geometry()
	label = Label3D.new()
	label.position.y = 2.65 if enemy_kind=="jackal" else 2.2
	label.font_size = 28
	label.pixel_size = .004
	label.modulate = Color("ffd170")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	controls.active = true
	if traits.get("beast",false):
		for child in get_children():
			if child is CollisionShape3D and child.shape is CapsuleShape3D:
				child.shape.height=.85 if enemy_kind!="charm_obelisk" else 2.7
				child.shape.radius=.30 if enemy_kind!="burial_serpent" else .44
				child.shape.height=maxf(child.shape.height,child.shape.radius*2)
				child.position.y=child.shape.height*.5
		for model: Dictionary in weapon_combat.rig.models.values():
			model.right.hide()
			model.left.hide()
		weapon_combat.trail.hide()
	if not traits.is_empty():
		aura=Node3D.new()
		add_child(aura)
		var marks:=PackedVector3Array()
		for i in range(32): marks.append_array([Vector3(cos(i*TAU/32),.035,sin(i*TAU/32))*.65,Vector3(cos((i+1)*TAU/32),.035,sin((i+1)*TAU/32))*.65])
		aura.add_child(NeonInk.lines(marks,NeonInk.shared_material(Color("64ffff"))))
		aura.hide()
		if floor_id==&"B5" and enemy_kind in ["tomb_walker","skeletal_mummy"]:
			buried=true
			visual.hide()
			collision_layer=0
			set_physics_process(false)
			weapon_combat.set_physics_process(false)
			_awake=false

func _process(_delta: float) -> void:
	if dead: return
	if buried:
		if not encounter.can_fight() or not encounter.same_floor(self,opponent) or global_position.distance_to(opponent.global_position)>12 or not encounter.line_of_sight(self,opponent): return
		buried=false
		emergence=.65
		visual.show()
		collision_layer=6
	if emergence>0:
		emergence=maxf(0,emergence-_delta)
		visual.position.y=-emergence
		controls.decision=maxf(controls.decision,.5)
	if support_time>0: support_time=maxf(0,support_time-_delta)
	if ward_time>0: ward_time=maxf(0,ward_time-_delta)
	if is_instance_valid(aura): aura.visible=support_time>0 or ward_time>0 or reassemble_time>0
	if reassemble_time>0:
		reassemble_time=maxf(0,reassemble_time-_delta)
		visual.chest.rotation.x=.8
		if reassemble_time==0: weapon_combat.health=weapon_combat.max_health*.4
	var awake: bool = encounter.can_fight() and encounter.same_floor(self,opponent) and opponent.global_position.distance_squared_to(global_position)<1600
	if awake!=_awake:
		_awake = awake
		set_physics_process(awake)
		weapon_combat.set_physics_process(awake)
		if not awake:
			controls.reset()
			weapon_combat.cancel()
	label.visible = awake and controls.aggro and opponent.global_position.distance_squared_to(global_position)<225
	label.text = combat_name()+"\n%d / %d" % [ceili(health),ceili(weapon_combat.max_health)]

func combat_name() -> String:
	if not traits.is_empty(): return traits.name
	if enemy_kind=="falcon": return "Exalted Falcon Sentinel" if elite else "Falcon Sentinel"
	if enemy_kind=="winged_skeleton": return "Winged Skeleton"
	if enemy_kind=="archer": return "Skeletal Archer"
	return ("Exalted Jackal Guardian" if elite else "Jackal Guardian") if enemy_kind=="jackal" else "Restless Skeleton"

func can_attack_target(target: Node) -> bool:
	return not dead and target==opponent and encounter.can_fight() and encounter.same_floor(self,opponent)

func receive_hit(amount: float, source: Vector3, attacker: Node = null, incoming: Dictionary = {}) -> float:
	if dead or not encounter.can_fight(): return 0
	controls.aggro = true
	var before := health
	return minf(before,super.receive_hit(amount,source,attacker,incoming))

func on_combat_defeat() -> void:
	if dead: return
	if traits.get("reassemble",false) and not reassembled:
		reassembled=true
		encounter.defeated_ids[spawn_id+"/reassembled"]=true
		encounter.world.inventory_session._dirty()
		reassemble_time=2.0
		weapon_combat.health=1
		weapon_combat.cancel()
		return
	dead = true
	controls.reset()
	controls.active = false
	weapon_combat.cancel()
	target_lock.clear()
	remove_from_group("combat_targets")
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	weapon_combat.set_physics_process(false)
	label.hide()
	encounter.defeat(self)

func _on_depth_hit(target: Node, _amount: float, move_name: String) -> void:
	if dead or target!=opponent or not encounter.can_fight() or target.weapon_combat.last_blocked: return
	if traits.get("venom",false) or move_name=="Venom Cloud": encounter.inflict_venom()
	if move_name in ["Grab and Toss","Shield Slam"]:
		var away: Vector3=(target.global_position-global_position).normalized()
		target.velocity+=away*7+Vector3.UP*3
	if move_name=="Grave Grasp": weapon_combat.health=minf(weapon_combat.max_health,health+6)

func respawn() -> void: on_combat_defeat()

func reset_encounter() -> void:
	if dead: return
	controls.reset()
	weapon_combat.reset()
	weapon_combat.cancel()
	target_lock.clear()
	global_position = spawn
	velocity = Vector3.ZERO
	fall_damage.reset()
	visual.rebase_after_phase()
