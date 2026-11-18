extends CharacterBody3D
## One combatant, one health pool and one controller throughout the willing union.
const Visual = preload("res://scripts/lorai_visual.gd")
const Combat = preload("res://scripts/lorai_combat.gd")
const Intent = preload("res://scripts/combat_intent.gd")
const Dodge = preload("res://scripts/phase_dodge.gd")
const Lock = preload("res://scripts/target_lock.gd")
const Moves = preload("res://scripts/lorai_moves.gd")
class BrainInterface extends Node:
	var actor: CharacterBody3D
	func on_forced_reaction() -> void: actor.decision_clock=.7
class AimFrame extends Node3D:
	var yaw:=0.0
	func reset_follow() -> void: pass
@export var base_health:=2400.0
@export_range(.2,.8) var phase_two_threshold:=.52
@export var arena_roam_radius:=26.0
var encounter: Node3D
var opponent: CharacterBody3D
var visual: Node3D
var weapon_combat: Node
var combat: Node
var dodge: Node
var target_lock: Node3D
var camera_rig: Node3D
var controls: Node
var inventory: Node # No inventory on the creature; common shield interface remains optional.
var transition_locked:=false
var boost_active:=false
var dead:=false
var engaged:=false
var think_enabled:=true
var floor_id: StringName=&"B8"
var floor_y: float=-144.0
var phase:=1 # 0 = union, 1 = mounted, 2 = ascendant.
var union_time:=0.0
var facing:=Vector3.BACK
var attack_goal:=Vector3.ZERO
var home:=Vector3(0,-143.94,-48)
var decision_clock:=1.3
var cursor:=0
var cooldowns: Dictionary={}
var hurtboxes: Array[CollisionShape3D]=[]
var _last_shape_update: int=-1
var health: float:
	get: return weapon_combat.health if is_instance_valid(weapon_combat) else base_health

func _ready() -> void:
	name="AhkmetAndLorai"
	position=home
	collision_layer=6
	collision_mask=0 # Controlled arena locomotion; no unrestricted 26-link rigid-body chain.
	visual=Visual.new()
	add_child(visual)
	controls=BrainInterface.new()
	controls.actor=self
	add_child(controls)
	camera_rig=AimFrame.new()
	add_child(camera_rig)
	combat=Intent.new()
	add_child(combat)
	combat.sheathed=false
	dodge=Dodge.new()
	dodge.actor=self
	add_child(dodge)
	target_lock=Lock.new()
	target_lock.actor=self
	target_lock.show_marker=false
	add_child(target_lock)
	weapon_combat=Combat.new()
	weapon_combat.actor=self
	weapon_combat.max_health=base_health
	weapon_combat.health=base_health
	add_child(weapon_combat)
	weapon_combat.hit_landed.connect(_on_hit)
	for i in range(Visual.LINK_COUNT+1):
		var shape:=CollisionShape3D.new()
		var volume:=CapsuleShape3D.new()
		volume.radius=1
		volume.height=2
		shape.shape=volume
		add_child(shape)
		hurtboxes.append(shape)
	add_to_group("combat_targets")
	sync_hurtboxes()

func combat_name() -> String: return "AHKMET THE VILE & LORAI" if phase!=2 else "LORAI — THE SERPENT ASCENDANT"

func combat_point() -> Vector3:
	# Lock and melee arc tests use the nearest REAL part of the continuous body,
	# not a head 8m above a grounded swordsman or an empty root-centered sphere.
	if not is_instance_valid(visual) or visual.points.is_empty(): return global_position+Vector3.UP*2
	var from: Vector3=opponent.combat_point() if is_instance_valid(opponent) else global_position+Vector3(0,1.2,10)
	return nearest_surface(from)

func nearest_surface(from: Vector3) -> Vector3:
	var best: Vector3=visual.head.global_position
	var distance:=INF
	for i in range(visual.points.size()-1):
		var a: Vector3=visual.to_global(visual.points[i])
		var b: Vector3=visual.to_global(visual.points[i+1])
		var center:=Geometry3D.get_closest_point_to_segment(from,a,b)
		var point:=center+(from-center).normalized()*float(visual.radii[i])
		var d:=from.distance_squared_to(point)
		if d<distance:
			distance=d
			best=point
	return best

func body_impact_point(point: Vector3) -> Vector3: return nearest_surface(point)
func camera_focus_point() -> Vector3:
	var point:=combat_point()
	point.y=maxf(point.y,global_position.y+visual.head.position.y*.65)
	return point
func can_attack_target(target: Node) -> bool: return engaged and not dead and phase!=0 and target==opponent and encounter.can_fight()
func receive_combat_hit(amount: float, source: Vector3, attacker: Node, incoming: Dictionary={}) -> float: return receive_hit(amount,source,attacker,incoming)

func receive_hit(amount: float, source: Vector3, attacker: Node=null, incoming: Dictionary={}) -> float:
	if dead or phase==0 or attacker!=opponent or not encounter.can_fight() or not encounter.same_floor(self,opponent): return 0
	engaged=true
	# The threshold is crossed without a lethal callback, health refill or loot.
	if phase==1: amount=minf(amount,maxf(0,health-base_health*phase_two_threshold))
	var dealt: float=weapon_combat.receive_hit(amount,source,attacker,incoming)
	if not dead and phase==1 and health<=base_health*phase_two_threshold+.001: begin_union()
	return dealt

func begin_union() -> void:
	if phase!=1 or dead: return
	phase=0
	union_time=0
	weapon_combat.cancel()
	weapon_combat.clear_stagger()
	velocity=Vector3.ZERO
	encounter.union_started()

func on_parried(source: Vector3) -> void:
	if phase!=0 and not dead: weapon_combat.stagger(source)

func on_combat_defeat() -> void:
	if dead or phase!=2: return
	dead=true
	weapon_combat.cancel()
	remove_from_group("combat_targets")
	set_deferred("collision_layer",0)
	encounter.finish()

func _on_hit(target: Node, _amount: float, title: String) -> void:
	if target!=opponent: return
	if title in ["Venom Spit","Venom Storm"]: encounter.manager.inflict_venom()
	# Existing Warden grab convention: only an accepted hit can toss. No input lock.
	if title=="Serpent Grasp": opponent.velocity=facing*8+Vector3.UP*6

func sync_hurtboxes() -> void:
	if hurtboxes.is_empty(): return
	# Shape resources are cached. Their dimensions only change at this bounded
	# physics update, independently of the temporal contact samples in combat.
	if _last_shape_update==Engine.get_physics_frames(): return
	_last_shape_update=Engine.get_physics_frames()
	for i in range(Visual.LINK_COUNT):
		var a: Vector3=visual.points[i]
		var b: Vector3=visual.points[mini(i+1,Visual.LINK_COUNT-1)]
		var span:=b-a
		var volume: CapsuleShape3D=hurtboxes[i].shape
		volume.radius=visual.radii[i]
		volume.height=maxf(volume.radius*2,span.length()+volume.radius*2)
		hurtboxes[i].transform=Transform3D(Basis(Quaternion(Vector3.UP,span.normalized() if span.length()>.001 else Vector3.UP)),(a+b)*.5)
	var skull: CapsuleShape3D=hurtboxes[-1].shape
	skull.radius=1.4
	skull.height=5.0
	hurtboxes[-1].transform=Transform3D(Basis(Quaternion(Vector3.UP,visual.head.basis.z)),visual.head.position+visual.head.basis.z*.3)

func choose_attack(distance: float, elevation: float) -> String:
	var choices: Array=Moves.PHASE_ONE if phase==1 else Moves.PHASE_TWO
	var preferred: Array=["judgment","spit","command"] if elevation>4 or distance>21 else ["sweep","lunge","command","spit","judgment"]
	if phase==2: preferred=["storm","inherited","annihilation"] if elevation>4 or distance>22 else ["bite","grasp","coil","annihilation","inherited","storm"]
	for i in range(preferred.size()):
		var style: String=preferred[(cursor+i)%preferred.size()]
		if choices.has(style) and float(cooldowns.get(style,0))<=0:
			cursor+=1
			return style
	return ""

func start_attack(style: String) -> bool:
	if dead or phase==0 or not weapon_combat.active_move.is_empty() or weapon_combat.is_staggered(): return false
	var move:=Moves.move(style)
	if move.is_empty(): return false
	attack_goal=opponent.combat_point() # Commit to observed position; no input reading/homing.
	var toward:=attack_goal-global_position
	toward.y=0
	facing=toward.normalized() if toward.length()>.1 else facing
	visual.rotation.y=atan2(facing.x,facing.z)
	weapon_combat._begin(move)
	cooldowns[style]=8.0 if style in ["command","inherited","storm","coil"] else 4.8
	decision_clock=float(move.duration)+.75
	return true

func _physics_process(delta: float) -> void:
	if dead or not encounter.can_fight() or not encounter.same_floor(self,opponent):
		velocity=Vector3.ZERO
		return
	if not engaged:
		if global_position.distance_to(opponent.global_position)<38 and encounter.manager.line_of_sight(self,opponent):
			engaged=true
		else: return
	if phase==0:
		union_time+=delta
		if union_time>=8.4:
			phase=2
			decision_clock=1.2
			encounter.union_finished()
		return
	for key in cooldowns: cooldowns[key]=maxf(0,float(cooldowns[key])-delta)
	decision_clock=maxf(0,decision_clock-delta)
	if not think_enabled or weapon_combat.is_staggered():
		velocity=Vector3.ZERO
		return
	if not weapon_combat.active_move.is_empty():
		velocity=Vector3.ZERO
		if phase==1 and weapon_combat.active_move.lorai_style=="judgment":
			# Lorai carries the independently gesturing Pharaoh through a slow
			# lateral coil shift. The committed projectile goal never homes.
			var tangent:=facing.cross(Vector3.UP).normalized()
			var next:=global_position+tangent*delta
			if Vector2(next.x-home.x,next.z-home.z).length()<arena_roam_radius:
				global_position=next
				velocity=tangent
		return
	var toward:=opponent.global_position-global_position
	toward.y=0
	var distance:=toward.length()
	velocity=Vector3.ZERO
	if distance>.1:
		visual.rotation.y=lerp_angle(visual.rotation.y,atan2(toward.x,toward.z),1-exp(-3*delta))
	if distance>11:
		var next:=global_position+toward.normalized()*4.2*delta
		var planar:=Vector2(next.x-home.x,next.z-home.z).limit_length(arena_roam_radius)
		global_position=Vector3(home.x+planar.x,floor_y+.06,home.z+planar.y)
		velocity=toward.normalized()*4.2
	if distance<58 and decision_clock<=0:
		var style:=choose_attack(distance,opponent.global_position.y-floor_y)
		if not style.is_empty(): start_attack(style)
