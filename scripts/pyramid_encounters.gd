extends Node3D
## Floor-owned rosters and per-instance defeat records. Enemies exist only in
## this World3D. Menus keep active encounters running, like the rest of the game.
const Enemy = preload("res://scripts/pyramid_enemy.gd")
const Dissolve = preload("res://scripts/monster_dissolve.gd")
const Floor = preload("res://scripts/pyramid_floor.gd")
const Types = preload("res://scripts/pyramid_bestiary.gd")
const B8 = preload("res://scripts/ahkmet_encounter.gd")
var b8: Node3D
var boss_state: Dictionary={}
const ROSTER := [
	["skeleton_01","skeleton",4,3,false], ["skeleton_02","skeleton",5,3,false],
	["jackal_01","jackal",2,3,false], ["skeleton_03","skeleton",1,4,false],
	["jackal_02","jackal",6,4,false], ["skeleton_04","skeleton",7,5,false],
	["skeleton_05","skeleton",3,6,false], ["skeleton_06","skeleton",5,6,false],
	["jackal_elite","jackal",7,7,true]]
const B2_ROSTER := [
	["b2_falcon_01","falcon",-22,-45,false], ["b2_winged_01","winged_skeleton",-12,-38,false],
	["b2_falcon_02","falcon",22,-42,false], ["b2_winged_02","winged_skeleton",12,-34,false],
	["b2_archer_01","archer",-25,4,false], ["b2_archer_02","archer",25,2,false],
	["b2_winged_03","winged_skeleton",0,-51,false], ["b2_falcon_elite","falcon",0,-63,true]]
var world: Node3D
var interior: Node3D
var travel: Node
var player: CharacterBody3D
var enemies: Array[CharacterBody3D] = []
var defeated_ids: Dictionary = {}
var spawned := false
var spawned_floors: Dictionary={}
var active := false
var _was_target := false
var _was_layer := false
var encounter_clock:=0.0
var _convergence: Dictionary={}
var _venom_time:=0.0
var _venom_tick:=0.0
var _mist_exposure:=0.0
var _venom_label: Label3D
var dormant_states: Dictionary={}
var _floor_visits: Dictionary={}
var _last_floor: StringName=&""

func _ready() -> void:
	name = "PyramidEncounters"
	player.defeated.connect(_on_player_defeated)
	player.respawned.connect(_on_player_respawned)
	_venom_label=Label3D.new()
	_venom_label.font_size=26
	_venom_label.pixel_size=.004
	_venom_label.modulate=Color("d27bff")
	_venom_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_venom_label)
	_venom_label.hide()

func set_active(value: bool) -> void:
	if value==active: return
	active = value
	if active:
		_was_target = player.is_in_group("combat_targets")
		_was_layer = player.get_collision_layer_value(2)
		player.add_to_group("combat_targets")
		player.set_collision_layer_value(2,true)
		ensure_spawned()
	else:
		if not _was_target: player.remove_from_group("combat_targets")
		player.set_collision_layer_value(2,_was_layer)
		reset_run()

func _process(_delta: float) -> void:
	if not active or not can_fight(): return
	encounter_clock+=_delta
	var floor_id: StringName=interior.floor_at(player.global_position)
	ensure_spawned(floor_id)
	if _last_floor!=floor_id:
		_last_floor=floor_id
		_floor_visits[floor_id]=encounter_clock
		_limit_loaded(floor_id)
	var in_mist:=false
	if floor_id==&"B7" and absf(player.global_position.y+112)<1:
		for feature: Dictionary in interior.floors[floor_id].dressing.features:
			if feature.kind=="venom_mist" and Vector2(player.global_position.x-feature.point.x,player.global_position.z-feature.point.z).length()<float(feature.radius): in_mist=true
	_mist_exposure=_mist_exposure+_delta if in_mist else 0.0
	if _mist_exposure>1.1: inflict_venom()
	_venom_time=maxf(0,_venom_time-_delta)
	_venom_tick=maxf(0,_venom_tick-_delta)
	if _venom_time>0 and _venom_tick<=0:
		_venom_tick=.8
		player.receive_hit(4,player.combat_point(),null,{"parryable":false,"action":"venom"})
	_venom_label.visible=_venom_time>0
	if _venom_time>0:
		_venom_label.global_position=player.global_position+Vector3.UP*2.5
		_venom_label.text="VENOM  %.1fs" % _venom_time

func roster_for(floor_id: StringName) -> Array:
	return ROSTER if floor_id==&"hub" else B2_ROSTER if floor_id==&"B2" else Types.entries(floor_id)

func ensure_spawned(floor_id: StringName = &"hub") -> void:
	if floor_id==&"B8":
		if spawned_floors.has(floor_id): return
		spawned_floors[floor_id]=true
		_floor_visits[floor_id]=encounter_clock
		if not defeated_ids.has("ahkmet_lorai"):
			b8=B8.new()
			b8.manager=self
			add_child(b8)
		return
	if spawned_floors.has(floor_id) or roster_for(floor_id).is_empty(): return
	spawned = true
	spawned_floors[floor_id]=true
	_floor_visits[floor_id]=encounter_clock
	for entry: Array in roster_for(floor_id):
		if defeated_ids.has(entry[0]): continue
		spawn_entry(entry,floor_id)

func spawn_entry(entry: Array, floor_id: StringName) -> CharacterBody3D:
	var enemy := Enemy.new()
	enemy.encounter = self
	enemy.opponent = player
	enemy.spawn_id = entry[0]
	enemy.enemy_kind = entry[1]
	enemy.elite = entry[4]
	enemy.floor_id=floor_id
	enemy.floor_y=float(interior.floors[floor_id].definition.y)
	enemy.ceiling_y=float(interior.floors[floor_id].definition.ceiling)
	enemy.reassembled=defeated_ids.has(enemy.spawn_id+"/reassembled")
	enemy.spawn = Vector3((int(entry[2])-4)*8,.06,-int(entry[3])*8) if floor_id==&"hub" else Vector3(entry[2],enemy.floor_y+.06,entry[3])
	enemy.spawn=safe_spawn(enemy.spawn,enemy.floor_id)
	interior.floors[floor_id].add_child(enemy)
	if dormant_states.has(enemy.spawn_id):
		var saved: Dictionary=dormant_states[enemy.spawn_id]
		enemy.weapon_combat.health=float(saved.hp)
		enemy.global_position=saved.position
		var away:=maxf(0,encounter_clock-float(saved.get("at",encounter_clock)))
		enemy.support_time=maxf(0,float(saved.get("support",0))-away)
		enemy.ward_time=maxf(0,float(saved.get("ward",0))-away)
		enemy.reassemble_time=maxf(0,float(saved.get("reassembly",0))-away)
		if float(saved.get("reassembly",0))>0 and enemy.reassemble_time==0: enemy.weapon_combat.health=enemy.weapon_combat.max_health*.4
		if not saved.buried and enemy.buried:
			enemy.buried=false
			enemy.visual.show()
			enemy.collision_layer=6
	enemies.append(enemy)
	return enemy

func safe_spawn(wanted: Vector3, floor_id: StringName) -> Vector3:
	var shape:=CapsuleShape3D.new()
	shape.radius=.45
	shape.height=2.7
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.collision_mask=9
	query.exclude=[player.get_rid()]
	var space:=get_world_3d().direct_space_state
	for radius in range(5):
		for sector in range(1 if radius==0 else 8):
			var candidate:=wanted+Vector3(cos(sector*TAU/8),0,sin(sector*TAU/8))*radius*1.3
			query.transform.origin=candidate+Vector3.UP*1.38
			if not space.intersect_shape(query,1).is_empty(): continue
			var ray:=PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*.15,candidate-Vector3.UP*.3,9,[player.get_rid()])
			var hit:=space.intersect_ray(ray)
			if not hit.is_empty() and hit.normal.y>.7 and interior.floor_at(candidate)==floor_id: return candidate
	return wanted

func _limit_loaded(current: StringName) -> void:
	# Keep the hub and two recent encounter floors. Primitive snapshots retain
	# living enemies' health/position without keeping every full animation rig alive.
	while spawned_floors.size()>3:
		var oldest: StringName=&""
		var stamp:=INF
		for id: StringName in spawned_floors:
			if id in [&"hub",current]: continue
			if float(_floor_visits.get(id,0))<stamp:
				oldest=id
				stamp=float(_floor_visits.get(id,0))
		if oldest==&"": return
		if oldest==&"B8" and is_instance_valid(b8):
			boss_state=b8.snapshot()
			b8.retire()
			b8=null
		for enemy in enemies.duplicate():
			if not is_instance_valid(enemy):
				enemies.erase(enemy)
				continue
			if enemy.floor_id!=oldest: continue
			if not enemy.dead: dormant_states[enemy.spawn_id]={"hp":enemy.health,"position":enemy.global_position,"buried":enemy.buried,"at":encounter_clock,"support":enemy.support_time,"ward":enemy.ward_time,"reassembly":enemy.reassemble_time}
			_retire_enemy(enemy)
			enemies.erase(enemy)
		spawned_floors.erase(oldest)

func same_floor(actor: CharacterBody3D, target: CharacterBody3D) -> bool:
	return interior.floor_at(target.global_position)==actor.floor_id

func can_fight() -> bool:
	return active and not travel.busy and not player.transition_locked and player.health>0 and player.get_world_3d()==get_world_3d()

func _on_player_defeated() -> void:
	if not active: return
	# Clear attacks immediately, including while the live respawn-choice menu is
	# open. Floors repopulate after reconstruction, rather than around a dead player.
	reset_run()
	world.inventory_session._dirty()

func _on_player_respawned() -> void:
	if not active: return
	# Also covers fall recovery, which can call respawn without a defeat signal.
	reset_run()
	ensure_spawned()
	ensure_spawned(interior.floor_at(player.global_position))
	world.inventory_session._dirty()

func reset_run() -> void:
	boss_state={}
	defeated_ids.clear()
	dormant_states.clear()
	_floor_visits.clear()
	_last_floor=&""
	encounter_clock=0
	_convergence.clear()
	_venom_time=0
	_mist_exposure=0
	_venom_tick=0
	if is_instance_valid(_venom_label): _venom_label.hide()
	_clear_enemies()

func _clear_enemies() -> void:
	if is_instance_valid(b8): b8.retire()
	b8=null
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		_retire_enemy(enemy)
	enemies.clear()
	spawned = false
	spawned_floors.clear()
	for child in get_children():
		if child is Dissolve:
			child.set_process(false)
			child.hide()
			child.queue_free()

func _retire_enemy(enemy: CharacterBody3D) -> void:
	# Retirement is immediate even inside a strike's physics callback.
	enemy.dead=true
	enemy.controls.reset()
	enemy.controls.active=false
	enemy.weapon_combat.cancel()
	enemy.target_lock.clear()
	enemy.collision_layer=0
	enemy.collision_mask=0
	enemy.set_process(false)
	enemy.set_physics_process(false)
	enemy.weapon_combat.set_physics_process(false)
	enemy.remove_from_group("combat_targets")
	enemy.hide()
	enemy.queue_free()

func line_of_sight(from: CharacterBody3D, to: CharacterBody3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from.combat_point(),to.combat_point(),9,[from.get_rid(),to.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func reserve_attack(actor: CharacterBody3D) -> bool:
	var committed := 0
	for other in enemies:
		if is_instance_valid(other) and other.floor_id==actor.floor_id and other!=actor and not other.dead and not other.weapon_combat.active_move.is_empty(): committed += 1
	return committed<2

func nearest_cell(point: Vector3) -> Vector2i:
	var best := Vector2i(4,0)
	var distance := INF
	for row in range(8):
		for x in range(9):
			if not Floor.hub_open(x,row): continue
			var next := Vector3((x-4)*8,0,-row*8).distance_squared_to(Vector3(point.x,0,point.z))
			if next<distance:
				distance = next
				best = Vector2i(x,row)
	return best

func next_waypoint(from: Vector3, goal: Vector3, floor_id: StringName = &"hub") -> Vector3:
	if floor_id!=&"hub":
		# The two courts share a 16 m central portal. Approach its centre on
		# our own side first, so neither ground nor aerial pursuit cuts a wall.
		var data: Dictionary=interior.floors[floor_id].definition
		var half:=Floor.half_at(data.ceiling)-1.5
		var partitions: Array=[]
		var opening:=12.0
		if data.branch=="lower":
			opening=24.0 if data.number>=4 else 16.0
			if data.number in [2,4,6]: partitions=[Floor.CENTER.z+half*.1]
			elif data.number in [3,5,7]:
				opening=28
				partitions=[Floor.CENTER.z-half*.48,Floor.CENTER.z+half*.48]
		elif data.number in [2,4,5]: partitions=[Floor.CENTER.z]
		if goal.z<from.z: partitions.reverse()
		for partition: float in partitions:
			if (from.z-partition)*(goal.z-partition)<0:
				if absf(from.x)>opening*.5-2: return Vector3(0,from.y,from.z)
				return Vector3(0,from.y,partition+signf(goal.z-partition)*4)
		return goal
	var start := nearest_cell(from)
	var end := nearest_cell(goal)
	if start==end: return goal
	var frontier: Array[Vector2i] = [start]
	var previous: Dictionary = {start:start}
	var cursor := 0
	while cursor<frontier.size():
		var cell := frontier[cursor]
		cursor += 1
		if cell==end: break
		for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next := cell+offset
			if previous.has(next) or not Floor.hub_open(next.x,next.y): continue
			previous[next] = cell
			frontier.append(next)
	if not previous.has(end): return from
	var step := end
	while previous[step]!=start: step = previous[step]
	return Vector3((step.x-4)*8,from.y,-step.y*8)

static func glyph_for(difficulty: int) -> StringName:
	return &"monster_glyph_rare" if difficulty>=3 else &"monster_glyph_uncommon" if difficulty>=2 else &"monster_glyph_common"

func defeat(enemy: CharacterBody3D) -> void:
	if defeated_ids.has(enemy.spawn_id): return
	defeated_ids[enemy.spawn_id] = true
	var effect := Dissolve.new()
	effect.victim = enemy
	add_child(effect)
	var difficulty := 3 if enemy.elite else 2 if enemy.enemy_kind in ["jackal","falcon"] else 1
	var choices: Array = [&"warden_khopesh",&"warden_wraps",&"jackal_pendant"] if enemy.enemy_kind=="jackal" else [&"tomb_blade",&"linen_bindings"]
	if enemy.enemy_kind=="falcon": choices=[&"horuswing_blades",&"sentinel_spear",&"falcon_sentinel_mantle",&"skyguard_tassets",&"eye_of_horus_seal"]
	elif enemy.enemy_kind=="winged_skeleton": choices=[&"tomb_blade",&"skyguard_tassets"]
	var gear: StringName = choices[absi(enemy.spawn_id.hash())%choices.size()]
	if enemy.enemy_kind=="falcon": gear=choices.pick_random()
	if not enemy.traits.is_empty():
		difficulty=int(enemy.traits.tier)
		gear=StringName(enemy.traits.drops.pick_random())
	# Airborne kills leave loot on supported ground in their own floor.
	var support: Dictionary=world.loot.supported_position(Vector3(enemy.global_position.x,enemy.floor_y+.08,enemy.global_position.z),travel.pyramid_id)
	var point: Vector3=support.point if not support.is_empty() else enemy.spawn
	call_deferred("leave_rewards",point,difficulty,gear)
	if enemy.floor_id==&"B6" and not defeated_ids.has("b6_trio_reward") and defeated_ids.has("b6_renu") and defeated_ids.has("b6_tefet") and defeated_ids.has("b6_sakhra"):
		defeated_ids["b6_trio_reward"]=true
		call_deferred("leave_rewards",Vector3(0,-95.92,-76),3,&"sekhmet_sigil")

func leave_rewards(point: Vector3, difficulty: int, gear: StringName) -> void:
	world.loot.spawn_reward(glyph_for(difficulty),point,travel.pyramid_id)
	world.loot.spawn_reward(gear,point+Vector3(.65,0,0),travel.pyramid_id)
	if difficulty==1: world.loot.spawn_reward(&"bone_shards",point+Vector3(-.65,0,0),travel.pyramid_id)
	world.inventory_session._dirty()

func restore_defeats(ids: Array) -> void:
	defeated_ids.clear()
	dormant_states.clear()
	for floor_id: StringName in interior.floors:
		for entry: Array in roster_for(floor_id):
			for key: String in [String(entry[0]),String(entry[0])+"/summoned",String(entry[0])+"/reassembled"]:
				if ids.has(key): defeated_ids[key]=true
	if ids.has("b6_trio_reward"): defeated_ids["b6_trio_reward"]=true
	if ids.has("ahkmet_lorai"): defeated_ids["ahkmet_lorai"]=true
	# Checkpoints inside the dungeon retain progress for that run. A reset or exit
	# clears it; restoring an older checkpoint rebuilds its original surviving roster.
	var loaded_floors:=spawned_floors.keys()
	_clear_enemies()
	if active:
		for floor_id: StringName in loaded_floors: ensure_spawned(floor_id)

func champions_alive() -> int:
	var count:=0
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and enemy.traits.get("champion",false): count+=1
	return count

func champion_turn(actor: CharacterBody3D) -> bool:
	return champions_alive()<3 or ["renu","tefet","sakhra"].find(actor.enemy_kind)!=int(encounter_clock/5)%3

func convergence_ready(actor: CharacterBody3D) -> bool:
	if encounter_clock-float(_convergence.get(actor.spawn_id,0))<14: return false
	_convergence[actor.spawn_id]=encounter_clock
	return true

func inflict_venom() -> void: _venom_time=4.0

func ritual(actor: CharacterBody3D, kind: String) -> void:
	if kind=="ward": actor.ward_time=4.5
	elif kind=="summon":
		var key: String=actor.spawn_id+"/summoned"
		if not defeated_ids.has(key):
			defeated_ids[key]=true
			var revived:=0
			for entry: Array in roster_for(actor.floor_id):
				if entry[1] not in ["asp","cobra","horned_viper","burial_serpent"] or not defeated_ids.has(entry[0]): continue
				defeated_ids.erase(entry[0])
				var snake:=spawn_entry(entry,actor.floor_id)
				snake.controls.aggro=true
				snake.support_time=5
				revived+=1
				if revived>=2: break
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.floor_id!=actor.floor_id or enemy.global_position.distance_to(actor.global_position)>15: continue
		if not line_of_sight(actor,enemy): continue
		if kind in ["chant","summon"]:
			enemy.support_time=5
			enemy.weapon_combat.health=minf(enemy.weapon_combat.max_health,enemy.health+12)
			enemy.controls.aggro=true
	actor.weapon_combat.emit_effect("orbit",3.0,360,Color("6bfff4"),actor.combat_point(),Vector3.FORWARD,.7)
	world.inventory_session._dirty()
