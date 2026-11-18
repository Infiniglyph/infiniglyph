extends "res://scripts/weapon_combat.gd"
## Creature presentation adapter; shared defense, exhaustion and damage remain authoritative.
const Moves = preload("res://scripts/lorai_moves.gd")
const Arrow = preload("res://scripts/pyramid_arrow.gd")
const Field = preload("res://scripts/pyramid_field.gd")
const Wave = preload("res://scripts/lorai_wave.gd")
class SerpentWeight extends "res://scripts/combat_body.gd":
	func begin(_facing: Vector3) -> void: phase_label="load"
var arrows: Array[Node3D]=[]
var fields: Array[Node3D]=[]
var contact_checks:=0
var _shape:=CapsuleShape3D.new()
var _query:=PhysicsShapeQueryParameters3D.new()
var _released: Dictionary={}

func _build_presentation() -> void:
	body=SerpentWeight.new()
	body.actor=actor
	rig=actor.visual
	trail=Trail.new()
	actor.add_child(trail)
	_query.shape=_shape
	_query.collision_mask=2
	_query.exclude=[actor.get_rid()]

func sync_rig() -> void: pass
func loadout(_slot: StringName) -> Dictionary:
	return {"id":&"lorai","name":"Ahkmet & Lorai","short":"Lorai","color":Color("ffc943"),"guard":.60}
func aim_direction() -> Vector3: return actor.facing
func damage_multiplier(_speed: float) -> float: return 1.0
func effective_fortitude() -> float: return 2.6

func _begin(move: Dictionary) -> void:
	_released.clear()
	super._begin(move)

func cancel() -> void:
	for effect in arrows.duplicate()+fields.duplicate():
		if is_instance_valid(effect): effect.reclaim()
	arrows.clear()
	fields.clear()
	super.cancel()

func apply_pose(delta: float) -> void:
	rig.pose(active_move,elapsed,actor.phase,actor.union_time,delta)
	actor.sync_hurtboxes()

func advance_strikes(previous: float) -> void:
	if actor.phase==0 or actor.dead or is_staggered(): return
	var move:=active_move.duplicate(true)
	for pulse in range(move.hits.size()):
		var window:=Moves.window(move,pulse)
		if elapsed<window.x or previous>window.y: continue
		if not _released.has(pulse) and elapsed>=float(move.hits[pulse]):
			_released[pulse]=true
			release_attack(move,pulse)
		if active_move.is_empty(): break
		var start:=maxf(previous,window.x)
		var finish:=minf(elapsed,window.y)
		var count:=maxi(1,ceili((finish-start)*120))
		for sample in range(count+1):
			rig.pose(move,lerpf(start,finish,float(sample)/count),actor.phase,0)
			for segment: Dictionary in rig.attack_segments(move,pulse):
				var span: Vector3=segment.b-segment.a
				_shape.radius=segment.radius
				_shape.height=span.length()+_shape.radius*2
				_query.transform=Transform3D(Basis(Quaternion(Vector3.UP,span.normalized())),(segment.a+segment.b)*.5)
				var hits: Array=actor.get_world_3d().direct_space_state.intersect_shape(_query,8)
				contact_checks+=1
				resolve_strike(move,pulse,segment.a,hits,false)
				if active_move.is_empty(): break
			if active_move.is_empty(): break
		if active_move.is_empty(): break
	rig.pose(active_move,elapsed,actor.phase,actor.union_time)
	actor.sync_hurtboxes()

func strike(pulse: int=-1) -> void:
	if active_move.is_empty() or pulse<0: return
	release_attack(active_move.duplicate(true),pulse)

func release_attack(move: Dictionary, pulse: int) -> void:
	var style: String=move.lorai_style
	if style in ["spit","storm","judgment"] or style=="command" and pulse==1 or style=="inherited" and pulse==2:
		var venom: bool=style in ["spit","storm"]
		var at: Vector3=rig.mouth() if venom else rig.staff_tip.global_position
		var goal: Vector3=actor.attack_goal
		var spreads: Array=[-.20,0.0,.20] if style=="storm" else [-.10,.10] if style=="spit" else [0.0]
		for spread: float in spreads:
			if arrows.size()>=8: break
			var bolt:=Arrow.new()
			bolt.actor=actor
			bolt.combat=self
			bolt.move=move.duplicate(true)
			bolt.move.attack_serial=attack_serial
			bolt.move.venom_projectile=venom
			bolt.glyph=true
			bolt.venom=venom
			bolt.speed=17.0 if venom else 24.0
			bolt.max_life=2.8
			bolt.visual_scale=2.0
			bolt.direction=(goal-at).normalized().rotated(Vector3.UP,spread)
			actor.get_parent().add_child(bolt)
			bolt.global_position=at
			arrows.append(bolt)
		if venom:
			for offset: float in ([-4.5,0.0,4.5] if style=="storm" else [0.0]):
				if fields.size()>=4: break
				var field:=Field.new()
				field.actor=actor
				field.combat=self
				field.move=move.duplicate(true)
				field.move.field="venom"
				field.move.damage=18
				field.move.attack_serial=attack_serial
				field.radius=3.4
				field.delay=1.25
				actor.get_parent().add_child(field)
				field.global_position=Vector3(goal.x+offset,actor.floor_y+.05,goal.z)
				fields.append(field)
	elif style=="coil" and fields.size()<4:
		var wave:=Wave.new()
		wave.actor=actor
		wave.combat=self
		wave.move=move.duplicate(true)
		wave.move.attack_serial=attack_serial
		actor.get_parent().add_child(wave)
		wave.global_position=Vector3(rig.head.global_position.x,actor.floor_y+.08,rig.head.global_position.z)
		fields.append(wave)
		emit_effect("slam",4,360,Color("ffc943"),wave.global_position,actor.facing,.7)

func _physics_process(delta: float) -> void:
	if actor.dead or not actor.encounter.can_fight() or not actor.encounter.same_floor(actor,actor.opponent): return
	if actor.phase==0:
		apply_pose(delta)
		return
	super._physics_process(delta)
