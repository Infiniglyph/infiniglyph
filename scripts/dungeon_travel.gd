extends Node
## Persistent player/services; separate World3Ds hold the two environment scenes.
const Encounters = preload("res://scripts/pyramid_encounters.gd")
var encounters: Node3D
const Interior = preload("res://scripts/pyramid_interior.gd")
const Doorway = preload("res://scripts/dungeon_doorway.gd")
const Respawn = preload("res://scripts/respawn_context.gd")
const Manifest = preload("res://scripts/environment_manifest.gd")
const OUTSIDE: StringName = &"overworld"
const OUT_TIME := .7
const IN_TIME := .85
var world: Node3D
var outside_root: Node3D
var interior: Node3D
var contexts: Dictionary = {}
var active_location: StringName = OUTSIDE
var pyramid_id: StringName
var home_anchor: Marker3D
var respawns: Node
var doors: Array[Node3D] = []
var busy := false
var ready_for_travel := false
var transition_count := 0
var _viewport: Viewport
var _original_world: World3D
var _outside_camera: Camera3D
var _effect := Manifest.new()
var _phase := 0
var _clock := 0.0
var _cooldown := 0.0
var _destination: StringName
var _outside_ui: Array[Dictionary] = []

func create_worlds() -> void:
	name="DungeonTravel"
	_viewport=world.get_viewport()
	_original_world=world.get_world_3d()
	var outside_view:=SubViewport.new()
	outside_view.name="OverworldSpace"
	outside_view.size=Vector2i(2,2)
	outside_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	outside_view.world_3d=_original_world
	add_child(outside_view)
	outside_root=Node3D.new()
	outside_root.name="OverworldScene"
	# Actors formerly parented directly to World retain its shared impact pool.
	outside_root.set_meta("combat_feedback_arena",world)
	outside_view.add_child(outside_root)
	contexts[OUTSIDE]=outside_root
	# Only the main viewport renders. This camera supplies existing distance
	# culling/projection helpers inside the non-rendering outdoor viewport.
	_outside_camera=Camera3D.new()
	_outside_camera.far=1800
	outside_view.add_child(_outside_camera)
	_outside_camera.current=true

func configure() -> void:
	pyramid_id=StringName("pyramid/"+world.player.inventory.owner_id)
	var inside_view:=SubViewport.new()
	inside_view.name="PyramidInstanceSpace"
	inside_view.size=Vector2i(2,2)
	inside_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	inside_view.world_3d=World3D.new()
	add_child(inside_view)
	interior=Interior.new()
	inside_view.add_child(interior)
	interior.hide()
	interior.process_mode=Node.PROCESS_MODE_DISABLED
	contexts[pyramid_id]=interior
	if world.dungeon_enemies_enabled:
		encounters=Encounters.new()
		encounters.world=world
		encounters.interior=interior
		encounters.travel=self
		encounters.player=world.player
		interior.add_child(encounters)
	_retain_support(outside_root)
	_retain_support(interior)
	home_anchor=Marker3D.new()
	home_anchor.name="TemporaryHomeSpawn"
	home_anchor.position=world.player.spawn
	home_anchor.set_meta("temporary_player_home",true)
	outside_root.add_child(home_anchor)
	respawns=Respawn.new()
	respawns.destinations={OUTSIDE:home_anchor,pyramid_id:interior.spawn_anchor}
	respawns.minimum_heights[pyramid_id]=float(interior.definitions[0].y)-24.0
	add_child(respawns)
	world.player.respawn_context=respawns
	world.loot.location_roots=contexts
	world.loot.active_location=OUTSIDE
	var entrance:=Doorway.new()
	entrance.name="PyramidDoorInteraction"
	entrance.location_id=OUTSIDE
	entrance.destination_id=pyramid_id
	entrance.prompt="enter the pyramid"
	# The physical door is recessed behind the exterior's existing mouth marker.
	entrance.position=Vector3(65,.08,0)
	world.wider_world.pyramid.add_child(entrance)
	doors.append(entrance)
	var exit:=Doorway.new()
	exit.name="PyramidExitInteraction"
	exit.location_id=pyramid_id
	exit.destination_id=OUTSIDE
	exit.prompt="leave the pyramid"
	exit.position=interior.exit_anchor.position
	interior.add_child(exit)
	doors.append(exit)
	for ui: Node in [world.sparring_duel,world.boss_encounter,world.kyren_encounter]:
		if is_instance_valid(ui): _outside_ui.append({"node":ui,"mode":ui.process_mode,"visible":ui.visible})
	world.inventory_session.dungeon_travel=self
	ready_for_travel=true

func _retain_support(scene: Node3D) -> void:
	# Dormant scripts/AI stop, but saved drops must still validate against their
	# own world's static floors. Godot otherwise removes disabled colliders.
	for body: StaticBody3D in scene.find_children("*","StaticBody3D",true,false):
		body.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE

func inside() -> bool: return active_location!=OUTSIDE

func can_load_location(id: StringName) -> bool:
	return ready_for_travel and contexts.has(id) and not busy

func focused_door() -> Node3D:
	if not ready_for_travel or busy or _cooldown>0 or world.inventory_session.networked(): return null
	var actor: CharacterBody3D=world.player
	if actor.controls.get("gameplay_enabled")!=true or actor.health<=0 or not actor.is_on_floor() or actor.dodge.active: return null
	if world.start_menu.is_open or world.inventory_session.ui.is_open or world.inventory_session.shop.is_open: return null
	if not actor.weapon_combat.active_move.is_empty() or actor.combat.blocking or actor.combat.charge_action!=&"": return null
	if world.world_actions.attached(): return null
	for encounter: Node in [world.sparring_duel,world.boss_encounter,world.kyren_encounter]:
		if is_instance_valid(encounter) and (encounter.active or encounter.dialogue_open): return null
	for door in doors:
		if door.location_id==active_location and door.in_reach(actor): return door
	return null

func interact() -> bool:
	var door:=focused_door()
	if door==null: return false
	busy=true
	_destination=door.destination_id
	_phase=0
	_clock=0
	var actor: CharacterBody3D=world.player
	actor.transition_locked=true
	actor.controls.set_gameplay_enabled(false)
	actor.weapon_combat.cancel()
	actor.combat.cancel_charge()
	actor.combat.blocking=false
	actor.target_lock.clear()
	actor.velocity=Vector3.ZERO
	actor._jump_after_dodge=false
	_retain_support(contexts[active_location])
	contexts[active_location].process_mode=Node.PROCESS_MODE_DISABLED
	_effect.capture(contexts[active_location],actor.global_position)
	return true

func _set_location(id: StringName, through_door: bool = false) -> void:
	if through_door:
		var from: Node3D=world.wider_world.pyramid.entrance_anchor if active_location==OUTSIDE else interior.spawn_anchor
		var to: Node3D=world.wider_world.pyramid.entrance_anchor if id==OUTSIDE else interior.spawn_anchor
		var turn:=wrapf(to.global_rotation.y-from.global_rotation.y,-PI,PI)
		world.player.visual.global_basis=Basis(Vector3.UP,turn)*world.player.visual.global_basis
		world.camera_rig.yaw=wrapf(world.camera_rig.yaw+turn,-PI,PI)
	active_location=id
	respawns.active_location=id
	world.loot.active_location=id
	_viewport.world_3d=contexts[id].get_world_3d()
	outside_root.visible=id==OUTSIDE
	interior.visible=id==pyramid_id
	outside_root.process_mode=Node.PROCESS_MODE_INHERIT if id==OUTSIDE and not busy else Node.PROCESS_MODE_DISABLED
	interior.process_mode=Node.PROCESS_MODE_INHERIT if id==pyramid_id and not busy else Node.PROCESS_MODE_DISABLED
	for record in _outside_ui:
		if not is_instance_valid(record.node): continue
		record.node.process_mode=record.mode if id==OUTSIDE else Node.PROCESS_MODE_DISABLED
		record.node.visible=record.visible if id==OUTSIDE else false
	var actor: CharacterBody3D=world.player
	actor.dodge.cancel()
	actor.target_lock.clear()
	actor.visual.clear_combat_pose()
	actor.global_position=world.wider_world.pyramid.arrival_anchor.global_position if id==OUTSIDE else interior.spawn_anchor.global_position
	actor.velocity=Vector3.ZERO
	actor.fall_damage.reset()
	actor.unstuck.reset_history()
	actor.visual.rebase_after_phase()
	for step in actor._glass_steps:
		if is_instance_valid(step): step.queue_free()
	actor._glass_steps.clear()
	# The doorway frame has already mapped facing and orbit together. Checkpoint
	# and respawn relocations instead retain their own recorded headings.
	world.camera_rig.reset_follow()
	if id==pyramid_id:
		interior.update_visibility(actor.global_position,true)
		respawns.floor_label=interior.floor_label(actor.global_position)
	if is_instance_valid(encounters): encounters.set_active(id==pyramid_id)
	world.inventory_session._hint_clock=0
	world.inventory_session._refresh_losses()

func location_state() -> Dictionary:
	var state: Dictionary=interior.saved_state(world.player,world.camera_rig.yaw) if inside() else {}
	if inside() and is_instance_valid(encounters) and not encounters.defeated_ids.is_empty(): state.enemy_defeats=encounters.defeated_ids.keys()
	if inside() and is_instance_valid(encounters):
		var boss: Dictionary=encounters.b8.snapshot() if is_instance_valid(encounters.b8) else encounters.boss_state
		if not boss.is_empty(): state.ahkmet=boss
	return state

func restore_location(id: StringName, state: Dictionary = {}) -> bool:
	if not can_load_location(id): return false
	if is_instance_valid(encounters):
		if id==pyramid_id:
			encounters.boss_state=state.get("ahkmet",{}).duplicate()
			encounters.restore_defeats(state.get("enemy_defeats",[]))
		else: encounters.reset_run() # Discard legacy clears saved after an exit too.
	if active_location!=id: _set_location(id)
	if id==pyramid_id:
		var actor: CharacterBody3D=world.player
		actor.dodge.cancel()
		actor.global_position=interior.resolve_saved_position(state,actor)
		actor.velocity=Vector3.ZERO
		actor.fall_damage.reset()
		actor.unstuck.reset_history()
		actor.visual.rebase_after_phase()
		world.camera_rig.yaw=float(state.get("yaw",0))
		world.camera_rig.reset_follow()
		interior.update_visibility(actor.global_position,true)
		respawns.floor_label=interior.floor_label(actor.global_position)
	return true

func _process(delta: float) -> void:
	if not ready_for_travel: return
	_cooldown=maxf(0,_cooldown-delta)
	if not inside(): _outside_camera.global_transform=world.camera_rig.camera.global_transform
	elif not busy:
		if interior.update_visibility(world.player.global_position): world.inventory_session._dirty()
		respawns.floor_label=interior.floor_label(world.player.global_position)
	if not busy: return
	_clock+=delta
	if _phase==0:
		_effect.advance(1-_clock/OUT_TIME)
		if _clock<OUT_TIME: return
		_effect.restore()
		_set_location(_destination,true)
		_effect.capture(contexts[active_location],world.player.global_position)
		_effect.advance(0)
		_phase=1
		_clock=0
	else:
		_effect.advance(_clock/IN_TIME)
		if _clock<IN_TIME: return
		_effect.restore()
		busy=false
		contexts[active_location].process_mode=Node.PROCESS_MODE_INHERIT
		world.player.transition_locked=false
		world.player.controls.set_gameplay_enabled(true)
		_cooldown=.5
		transition_count+=1
		world.inventory_session._dirty()

func _exit_tree() -> void:
	_effect.restore()
	if is_instance_valid(_viewport) and _original_world!=null: _viewport.world_3d=_original_world
