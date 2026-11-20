extends Node
## Persistent player/services; independent World3Ds hold each environment.
const Encounters = preload("res://scripts/pyramid_encounters.gd")
var encounters: Node3D
const Interior = preload("res://scripts/pyramid_interior.gd")
const Doorway = preload("res://scripts/dungeon_doorway.gd")
const Respawn = preload("res://scripts/respawn_context.gd")
const Manifest = preload("res://scripts/environment_manifest.gd")
const RentalRoom = preload("res://scripts/private_room_interior.gd")
const WondersHall = preload("res://scripts/glyphic_wonders_hall.gd")
var wonders_id: StringName
var hall_content: Node3D
var hall_support: StaticBody3D
var room_ids: Array[StringName] = []
var room_contents: Dictionary = {}
var room_support: Dictionary = {}
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
	_configure_rentals()
	_configure_wonders()
	respawns.default_resolver = _rental_respawn
	ready_for_travel=true

func _configure_wonders() -> void:
	wonders_id=StringName("glyphic_wonders/"+world.player.inventory.owner_id)
	var viewport:=SubViewport.new()
	viewport.name="GlyphicWondersSpace"
	viewport.size=Vector2i(2,2)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	viewport.world_3d=World3D.new()
	add_child(viewport)
	var root:=Node3D.new()
	root.name="GlyphicWondersState"
	viewport.add_child(root)
	contexts[wonders_id]=root
	root.hide()
	root.process_mode=Node.PROCESS_MODE_DISABLED
	hall_support=WondersHall.create_support()
	root.add_child(hall_support)
	var exit:=Doorway.new()
	exit.name="GlyphicWondersExitInteraction"
	exit.location_id=wonders_id
	exit.destination_id=OUTSIDE
	exit.prompt="leave Glyphic Wonders"
	exit.position=Vector3(0,1.25,65)
	root.add_child(exit)
	doors.append(exit)
	var entrance:=Doorway.new()
	entrance.name="GlyphicWondersEntranceInteraction"
	entrance.location_id=OUTSIDE
	entrance.destination_id=wonders_id
	entrance.prompt="enter Glyphic Wonders"
	world.wider_world.glyphic_wonders.entrance_anchor.add_child(entrance)
	doors.append(entrance)
	respawns.minimum_heights[wonders_id]=-12.0

func _configure_rentals() -> void:
	var services: Node=world.get("civilian_services")
	if not is_instance_valid(services): return
	for index in range(3):
		var id:=StringName("rental/"+world.player.inventory.owner_id+"/"+str(index))
		room_ids.append(id)
		var viewport:=SubViewport.new()
		viewport.name="RentalSpace"+str(index+1)
		viewport.size=Vector2i(2,2)
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		viewport.world_3d=World3D.new()
		add_child(viewport)
		var root:=Node3D.new()
		root.name="RentalState"+str(index+1)
		viewport.add_child(root)
		contexts[id]=root
		root.hide()
		root.process_mode=Node.PROCESS_MODE_DISABLED
		# Collision-only support uses the same room recipe. Saved drops on a
		# bed or desk must validate even before that bedroom is first rendered.
		var support: StaticBody3D=RentalRoom.create_support()
		root.add_child(support)
		room_support[id]=support
		var door:=Doorway.new()
		door.location_id=id
		door.destination_id=OUTSIDE
		door.prompt="return to the guild hallway"
		door.position=Vector3(0,1.25,5.5)
		root.add_child(door)
		doors.append(door)
		var entrance:=Doorway.new()
		entrance.location_id=OUTSIDE
		entrance.destination_id=id
		entrance.prompt="enter private room "+str(index+1)
		services.establishments.room_exit[index].add_child(entrance)
		doors.append(entrance)
		respawns.minimum_heights[id]=-12.0

func is_pyramid() -> bool: return active_location==pyramid_id
func is_wonders(id: StringName = &"") -> bool: return (active_location if id==&"" else id)==wonders_id and not wonders_id.is_empty()
func is_rental(id: StringName = &"") -> bool: return (active_location if id==&"" else id) in room_ids
func room_number(id: StringName = &"") -> int: return room_ids.find(active_location if id==&"" else id)

func location_label(id: StringName, point: Vector3 = Vector3.ZERO) -> String:
	if id==OUTSIDE: return "OPEN WORLD"
	if is_wonders(id): return "GLYPHIC WONDERS"
	if is_rental(id): return "GUILD ROOM "+str(room_number(id)+1)
	return "PYRAMID / "+interior.floor_label(point)

func _build_room(id: StringName) -> void:
	if room_contents.has(id): return
	var content:=RentalRoom.new()
	contexts[id].add_child(content)
	room_contents[id]=content
	room_support[id].collision_layer=0
	_retain_support(content)
	for seat: Dictionary in content.seats: world.world_actions.seats.append(seat)

func _unload_room(id: StringName) -> void:
	if not room_contents.has(id): return
	var content: Node3D=room_contents[id]
	for seat: Dictionary in content.seats: world.world_actions.seats.erase(seat)
	contexts[id].remove_child(content)
	content.queue_free()
	room_contents.erase(id)
	room_support[id].collision_layer=1

func _build_hall() -> void:
	if is_instance_valid(hall_content): return
	hall_content=WondersHall.new()
	contexts[wonders_id].add_child(hall_content)
	hall_support.collision_layer=0
	_retain_support(hall_content)
	var service: Node=world.get("glyphic_wonders")
	if is_instance_valid(service): service.attach_hall(hall_content)

func _unload_hall() -> void:
	if not is_instance_valid(hall_content): return
	var service: Node=world.get("glyphic_wonders")
	if is_instance_valid(service): service.detach_hall()
	contexts[wonders_id].remove_child(hall_content)
	hall_content.queue_free()
	hall_content=null
	hall_support.collision_layer=1

func _rental_respawn() -> Variant:
	if is_wonders():
		_set_location(OUTSIDE)
		return world.wider_world.glyphic_wonders.arrival_anchor.global_position
	if not is_rental(): return null
	var index:=room_number()
	_set_location(OUTSIDE)
	return world.civilian_services.establishments.room_arrivals[index].global_position

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
	if is_rental(door.destination_id) and not world.civilian_services.economy.can_enter(room_number(door.destination_id)):
		world.inventory_session.show_notice("This private room needs an active rental. Speak to reception.")
		return true
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
	var previous:=active_location
	if through_door and (previous==pyramid_id or id==pyramid_id):
		var from: Node3D=world.wider_world.pyramid.entrance_anchor if active_location==OUTSIDE else interior.spawn_anchor
		var to: Node3D=world.wider_world.pyramid.entrance_anchor if id==OUTSIDE else interior.spawn_anchor
		var turn:=wrapf(to.global_rotation.y-from.global_rotation.y,-PI,PI)
		world.player.visual.global_basis=Basis(Vector3.UP,turn)*world.player.visual.global_basis
		world.camera_rig.yaw=wrapf(world.camera_rig.yaw+turn,-PI,PI)
	if is_rental(id): _build_room(id)
	if is_wonders(id): _build_hall()
	active_location=id
	respawns.active_location=id
	world.loot.active_location=id
	_viewport.world_3d=contexts[id].get_world_3d()
	outside_root.visible=id==OUTSIDE
	interior.visible=id==pyramid_id
	outside_root.process_mode=Node.PROCESS_MODE_INHERIT if id==OUTSIDE and not busy else Node.PROCESS_MODE_DISABLED
	interior.process_mode=Node.PROCESS_MODE_INHERIT if id==pyramid_id and not busy else Node.PROCESS_MODE_DISABLED
	for room_id in room_ids:
		contexts[room_id].visible=room_id==id
		contexts[room_id].process_mode=Node.PROCESS_MODE_INHERIT if room_id==id and not busy else Node.PROCESS_MODE_DISABLED
	if contexts.has(wonders_id):
		contexts[wonders_id].visible=is_wonders(id)
		contexts[wonders_id].process_mode=Node.PROCESS_MODE_INHERIT if is_wonders(id) and not busy else Node.PROCESS_MODE_DISABLED
	for record in _outside_ui:
		if not is_instance_valid(record.node): continue
		record.node.process_mode=record.mode if id==OUTSIDE else Node.PROCESS_MODE_DISABLED
		record.node.visible=record.visible if id==OUTSIDE else false
	var actor: CharacterBody3D=world.player
	actor.dodge.cancel()
	actor.target_lock.clear()
	actor.visual.clear_combat_pose()
	actor.global_position=world.wider_world.pyramid.arrival_anchor.global_position if id==OUTSIDE else interior.spawn_anchor.global_position
	if is_rental(id): actor.global_position=room_contents[id].spawn_anchor.global_position
	elif id==OUTSIDE and is_rental(previous): actor.global_position=world.civilian_services.establishments.room_arrivals[room_number(previous)].global_position
	elif is_wonders(id): actor.global_position=hall_content.spawn_anchor.global_position
	elif id==OUTSIDE and is_wonders(previous): actor.global_position=world.wider_world.glyphic_wonders.arrival_anchor.global_position
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
	if is_rental(previous) and previous!=id: _unload_room(previous)
	if is_wonders(previous) and previous!=id: _unload_hall()
	world.inventory_session._hint_clock=0
	world.inventory_session._refresh_losses()

func location_state() -> Dictionary:
	var state: Dictionary=interior.saved_state(world.player,world.camera_rig.yaw) if is_pyramid() else {}
	if is_rental() or is_wonders():
		var at: Vector3=world.player.global_position
		state={"position":[at.x,at.y,at.z],"yaw":world.camera_rig.yaw}
	if is_pyramid() and is_instance_valid(encounters) and not encounters.defeated_ids.is_empty(): state.enemy_defeats=encounters.defeated_ids.keys()
	if is_pyramid() and is_instance_valid(encounters):
		var boss: Dictionary=encounters.b8.snapshot() if is_instance_valid(encounters.b8) else encounters.boss_state
		if not boss.is_empty(): state.ahkmet=boss
	return state

func restore_location(id: StringName, state: Dictionary = {}) -> bool:
	if not can_load_location(id): return false
	if is_rental(id) and not world.civilian_services.economy.can_enter(room_number(id)):
		var index:=room_number(id)
		_set_location(OUTSIDE)
		world.player.global_position=world.civilian_services.establishments.room_arrivals[index].global_position
		world.player.visual.rebase_after_phase()
		world.camera_rig.reset_follow()
		return true
	if is_instance_valid(encounters):
		if id==pyramid_id:
			encounters.boss_state=state.get("ahkmet",{}).duplicate()
			encounters.restore_defeats(state.get("enemy_defeats",[]))
		else: encounters.reset_run() # Discard legacy clears saved after an exit too.
	if active_location!=id: _set_location(id)
	if is_rental(id):
		world.camera_rig.yaw=float(state.get("yaw",world.camera_rig.yaw))
		world.camera_rig.reset_follow()
	if is_wonders(id):
		var actor: CharacterBody3D=world.player
		actor.dodge.cancel()
		actor.global_position=hall_content.resolve_saved_position(state,actor)
		actor.velocity=Vector3.ZERO
		actor.fall_damage.reset()
		actor.unstuck.reset_history()
		actor.visual.rebase_after_phase()
		world.camera_rig.yaw=float(state.get("yaw",world.camera_rig.yaw))
		world.camera_rig.reset_follow()
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
	if active_location==OUTSIDE: _outside_camera.global_transform=world.camera_rig.camera.global_transform
	elif is_pyramid() and not busy:
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
