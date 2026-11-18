extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
const Neon = preload("res://scripts/neon.gd")
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var p: CharacterBody3D
var controls: Intent
var checks:=0
var failures:=0
var hz:=60

func check(ok: bool, message: String) -> void:
	checks+=1
	if ok: print("PASS: ",message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	call_deferred("run")

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func press(button: JoyButton) -> void:
	var event:=InputEventJoypadButton.new()
	event.button_index=button
	event.pressed=true
	controls._unhandled_input(event)
	event.pressed=false
	controls._unhandled_input(event)

func place(point: Vector3) -> void:
	controls.move=Vector2.ZERO
	p.global_position=point
	p.velocity=Vector3.ZERO
	p.fall_damage.reset()
	p.visual.rebase_after_phase()
	await frames(8)

func vehicle_at(point: Vector3, id: int, color: Color = Color.CYAN) -> CharacterBody3D:
	var car:=Vehicle.new()
	car.life=world.district_life
	car.record={"id":id,"kind":"car","point":point,"yaw":0.0,"traffic":false,"taken":false,"color":color,"driver":{"tint":Color.GOLD,"body_profile":&"male"}}
	world.district_life.add_child(car)
	world.district_life.vehicles[id]=car
	return car

func capture(label: String, point: Vector3, offset: Vector3) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.global_position=point+offset
	camera.look_at(point+Vector3.UP)
	camera.current=true
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/tweaks_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current=true

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	p=world.player
	p.visual.retrieval.enabled=false
	controls=Intent.new()
	root.add_child(controls)
	p.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	controls.interaction_context=world.inventory_session
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await frames(12)
	world.district_life.set_physics_process(false)
	world.population.set_physics_process(false)
	world.theft_reactions.set_physics_process(false)
	for car: Node in world.district_life.vehicles.values(): car.queue_free()
	world.district_life.vehicles.clear()
	for person: Node in world.district_life.people.values(): person.queue_free()
	world.district_life.people.clear()
	for person: CharacterBody3D in world.population.active_residents.duplicate(): person.deactivate()
	await frames(3)
	var a: Node=p.weapon_combat
	for tier: String in ["light","medium","heavy"]:
		var id:=StringName("shield_glyph_"+tier)
		var glyph: Resource=Catalog.create(id,3)
		check(glyph!=null and p.inventory.add_item(glyph),"Shield glyph is an owned, stackable item: "+tier)
		check(not world.inventory_session.shop.offer(id).is_empty(),"Tower Exchange offers "+tier+" shield glyphs")
		check(world.loot.request_shield_glyph(p.inventory,glyph.instance_id),"Use "+tier+" shield glyph through the authority")
		var capacity: float={"light":250,"medium":500,"heavy":1000}[tier]
		check(a.shield_points==capacity and a.shield_capacity==capacity and p.inventory.get_item(glyph.instance_id).quantity==2,"One glyph establishes exactly "+str(capacity)+" shield points")
		if tier=="heavy": await capture("shield_heavy",p.global_position,Vector3(2,1.3,2))
		check(not world.loot.request_shield_glyph(p.inventory,glyph.instance_id),"A full shield does not consume another "+tier+" glyph")
		p.combat.blocking=false
		a.receive_hit(100,p.global_position+Vector3.FORWARD,null,{"action":&"attack_right"})
		check(a.health==1000 and a.shield_points==capacity-100,"Combat damages the "+tier+" shield before HP")
	var hud: Control=world.find_child("CombatHUD",true,false)
	check(hud.shield_bar.value==900 and hud.shield_bar.max_value==1000 and hud.shield_label.text.contains("900 / 1000") and hud.shield_bar.position.y>hud.health_bar.position.y,"Heavy shield is a numbered 1,000-point bar below HP")
	p.combat.blocking=true
	a.parry_remaining=.1
	a.receive_hit(100,p.global_position+Vector3.FORWARD*2,null,{"parryable":true})
	check(a.last_parried and a.shield_points==900,"A successful parry preserves shield points")
	p.combat.blocking=false
	p.dodge.start(Vector3.RIGHT)
	p.dodge.elapsed=p.dodge.DURATION*.45
	a.receive_hit(100,p.global_position+Vector3.FORWARD,null,{})
	check(a.last_evaded and a.shield_points==900,"Dodge invulnerability preserves shield points")
	p.dodge.cancel()
	check(world.inventory_session.save_checkpoint("user://tests/tweaks_shield.json",true),"Partially depleted shield saves")
	a.receive_hit(950,p.global_position+Vector3.FORWARD,null,{"action":&"attack_right"})
	check(a.shield_points==0 and a.health==950,"Shield break spills only the remaining damage into HP")
	check(world.inventory_session.load_checkpoint("user://tests/tweaks_shield.json") and a.shield_points==900 and hud.shield_bar.value==900,"Save/load restores shield tier, remaining points and HUD")
	var snapshot:=Store.load_snapshot("user://tests/tweaks_shield.json")
	snapshot.inventory.shield_state.points=1001
	check(Store.decode(snapshot).is_empty(),"Over-capacity shield state is rejected by checkpoint validation")
	p.respawn()
	check(a.shield_points==0 and not hud.shield_bar.visible,"Death/respawn clears protection rather than refilling it")
	var ui: Node=world.inventory_session.ui
	var owned: Resource
	for item: Resource in p.inventory.items.values():
		if item.item_type_id==&"shield_glyph_heavy": owned=item
	ui.open_menu()
	ui.selected_iid=owned.instance_id
	ui.activate_selection()
	check(ui._modal_buttons[0].text=="USE SHIELD GLYPH","Inventory exposes the shield-use action")
	ui._modal_buttons[0].pressed.emit()
	check(a.shield_points==1000 and p.inventory.get_item(owned.instance_id).quantity==1,"The actual inventory action consumes one glyph and restores the shield")
	ui.close_menu()
	p.respawn()
	for family: String in ["dagger","fist","twin_blades"]:
		var id: StringName=&""
		for entry in Database.all():
			if entry.family==family:
				id=StringName(entry.id)
				break
		var item: Resource=Catalog.create(id)
		p.inventory.add_item(item)
		p.inventory.assign(&"down",item.instance_id)
		p.combat.selected_slot=&"down"
		p.combat.sheathed=false
		a.sync_rig()
		await frames(hz)
		var axis: Vector3=p.visual.chest.global_basis.inverse()*a.rig.right_hand.global_basis.y
		check(axis.y<-.8 if family=="fist" else axis.z>.8,"Ready weapon points "+("down" if family=="fist" else "forward")+": "+family)
		await capture(family,p.global_position,Vector3(2,1.3,2))
	# Test driving on a large isolated physical platform above world scenery.
	Neon.block(world.dungeon_travel.outside_root,Vector3(400,500,400),Vector3(512,2,512))
	var car:=vehicle_at(Vector3(400,501.05,400),91000,Color(.76,.12,.94))
	check(is_equal_approx(car.light_wave.trail_color.h,car.record.color.h) and is_equal_approx(car.light_wave.trail_color.s,car.record.color.s) and is_equal_approx(car.light_wave.trail_color.v,1.0),"The wall matches the vehicle's purple hue and saturation at full brightness")
	check(is_equal_approx(car.light_wave.HEIGHT,1.2),"Light wall height is halved to 1.2 metres")
	await place(car.position+Vector3.RIGHT*2)
	check(world.world_actions.board(car),"Board the actual physical vehicle")
	controls.move=Vector2.UP
	await frames(hz*3)
	var ordinary: float=car.signed_speed
	press(JOY_BUTTON_LEFT_STICK)
	await frames(hz*3)
	check(controls.boost and car.signed_speed>ordinary*1.4,"L3 increases driving speed with normal acceleration")
	print("BOOST: ordinary=",ordinary," boosted=",car.signed_speed," toggle=",controls.boost," at=",car.position)
	press(JOY_BUTTON_RIGHT_STICK)
	await frames(2)
	check(car.wave_enabled and controls.consume_lock_requests().is_empty(),"R3 toggles the light wall without locking a target")
	await frames(hz)
	check(car.light_wave.segments.size()>5 and car.health==1000 and p.health==1000,"Moving creates a visible bounded wall without self-damage")
	check(car.light_wave.segments.size()<=car.light_wave.MAX_SEGMENTS and car.light_wave.mesh.get_surface_count()==2,"One bounded light wall uses two mesh surfaces")
	if car.light_wave.segments.is_empty():
		print("NO WAVE: at=",car.position," health=",car.health," speed=",car.signed_speed," velocity=",car.velocity," input=",controls.move," active=",car.wave_enabled)
		world.queue_free()
		quit(1)
		return
	var segment: Dictionary=car.light_wave.segments[car.light_wave.segments.size()/2]
	var midpoint: Vector3=(segment.a+segment.b)*.5
	await capture("vehicle_wave_color",car.global_position,Vector3(9,4,-12))
	var above:=vehicle_at(midpoint+Vector3.UP*1.4,91003)
	above.set_physics_process(false)
	await frames(3)
	check(above.health==1000,"Passing above the shorter wall does not contact its old 2.4-metre hit region")
	above.global_position=midpoint+Vector3.UP*.9
	await frames(3)
	check(above.health==250,"Contact inside the visible 1.2-metre wall still deals normal damage")
	above.queue_free()
	var source: CharacterBody3D=world.population.residents[0]
	source.activate(midpoint)
	source.set_physics_process(false)
	await frames(3)
	check(source.health==250 and world.theft_reactions.is_annoyed(source),"A real civilian touching the wall loses 750 HP and uses existing annoyance feedback")
	await frames(ceili(hz*.15))
	check(source.health==250,"Multiple touching panels share one per-target damage cooldown")
	source.global_position+=Vector3.RIGHT*15
	var victim:=vehicle_at(midpoint,91001)
	victim.set_physics_process(false)
	await frames(4)
	check(victim.health==250,"The wall deals high damage to another physical vehicle")
	await frames(ceili(hz*.6))
	check(victim.health==0 and victim.has_node("WreckMarker") and not world.world_actions.board(victim),"A destroyed vehicle stops, shows a wreck marker and cannot be boarded")
	await capture("vehicle_wave",midpoint,Vector3(9,5,12))
	# Cross an active panel entirely between samples, rather than parking on it.
	var swept:=vehicle_at(midpoint+Vector3.LEFT*8,91002)
	swept.set_physics_process(false)
	await frames(2)
	swept.global_position=midpoint+Vector3.RIGHT*8
	await frames(2)
	check(swept.health==250,"Swept contact catches a fast vehicle crossing between physics frames")
	press(JOY_BUTTON_RIGHT_STICK)
	await frames(2)
	check(not car.wave_enabled,"A second R3 press stops emitting")
	controls.move=Vector2.ZERO
	await frames(ceili(hz*4.2))
	check(car.light_wave.segments.is_empty() and car.light_wave.mesh.get_surface_count()==0,"Old light wall geometry and hit regions expire completely")
	press(JOY_BUTTON_LEFT_STICK)
	check(not controls.boost,"L3 can toggle boosted driving off")
	car.set_wave_enabled(true)
	controls.move=Vector2.UP
	await frames(ceili(hz*.2))
	car.global_position+=Vector3.RIGHT*100
	await frames(1)
	check(car.light_wave.segments.is_empty(),"Vehicle teleporting cannot draw a damage line across the world")
	check(world.world_actions.leave() and not controls.vehicle_mode and not car.wave_enabled,"Dismount restores on-foot input and stops the emitter")
	press(JOY_BUTTON_RIGHT_STICK)
	check(controls.consume_lock_requests().size()==1,"R3 returns to ordinary target lock on foot")
	# Hold both presentation angles throughout deconstruction and reconstruction.
	await place(world.wider_world.pyramid.to_global(Vector3(65.5,.15,0)))
	p.combat.sheathed=true
	a.sync_rig()
	world.camera_rig.yaw=.42
	p.visual.rotation.y=.72
	check(world.dungeon_travel.interact(),"Pyramid entry starts normally")
	var steady:=true
	while world.dungeon_travel.busy:
		await frames(1)
		var turn: float=-PI*.5 if world.dungeon_travel.inside() else 0.0
		steady=steady and absf(wrapf(p.visual.rotation.y-(.72+turn),-PI,PI))<.001 and absf(wrapf(world.camera_rig.yaw-(.42+turn),-PI,PI))<.001
	check(steady,"The entire pyramid transition preserves doorway-relative character and camera facing")
	world.queue_free()
	controls.queue_free()
	print("Gameplay tweaks: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
