extends SceneTree
## Actual actor, inventory authority, rig, collision, UI and named moves.
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Target = preload("res://scripts/practice_target.gd")
const Motion = preload("res://scripts/weapon_motion.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void:
		if not gameplay_enabled: move = Vector2.ZERO
class Observer extends Node:
	signal finished
	func _process(_delta: float) -> void: finished.emit()
var world: Node3D
var p: CharacterBody3D
var w: Node
var controls: Intent
var observer: Observer
var camera: Camera3D
var hz := 60
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await observer.finished
func own(id: StringName,slot: StringName) -> Resource:
	var item: Resource = Catalog.create(id)
	if not p.inventory.add_item(item): return null
	if not world.loot.request_equip(p.inventory,slot,item.instance_id): return null
	return item
func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/equipment_"+name+".png")
	print("CAPTURE: ",name)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")
func run() -> void:
	observer = Observer.new()
	observer.process_priority = 10000
	root.add_child(observer)
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	p = world.player
	w = p.weapon_combat
	p.visual.retrieval.enabled = false
	world.population.set_physics_process(false)
	controls = Intent.new()
	root.add_child(controls)
	p.controls = controls
	world.camera_rig.controls = controls
	world.inventory_session.controls = controls
	controls.interaction_context = world.inventory_session
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p.position = Vector3(0,.1,8)
	await frames(hz/2)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.global_position = p.position+Vector3(2.8,1.9,3.2)
	camera.look_at(p.position+Vector3.UP)
	camera.current = true
	var original_pace := Vector3(p.walk_speed,p.run_speed,p.boost_speed)
	var owned: Dictionary = {}
	for id: StringName in [&"fractured_moon",&"event_horizon",&"last_argument"]:
		owned[id] = own(id,&"right")
		check(owned[id]!=null,String(id)+" equips through existing authoritative ownership")
		p.combat.selected_slot = &"right"
		p.combat.sheathed = false
		w.sync_rig()
		check(w.rig.selected==id and w.loadout(&"right").item_id==id,"Equipping resolves item identity through to geometry and combat")
		w._on_action(&"attack_right",&"right")
		check(w.active_move.get("combo_index")==0 and not w.active_move.get("aerial",true),"First grounded press starts the first named combo stage")
		var first_name: String = w.active_move.name
		await frames(ceili(float(w.active_move.duration)*hz)+1)
		w._on_action(&"attack_left",&"right")
		check(w.active_move.get("combo_index")==1 and w.active_move.name!=first_name,"Alternating hands advances the named combo")
		await frames(ceili(float(w.active_move.duration)*hz)+1)
		w._on_action(&"attack_right",&"right")
		check(w.active_move.get("combo_index")==2,"Third press reaches the individual combo finisher")
		await frames(ceili(float(w.active_move.duration)*hz)+1)
		w.cancel()
		p.set_physics_process(false)
		w.set_physics_process(false)
		w._on_action(&"special_y",&"right")
		for i in range(18):
			p.visual.animate(1.0/hz,Vector3.ZERO,true)
			w.elapsed = float(w.active_move.hits[0])
			w.apply_pose(1.0/hz)
		check(w.body.hips.value.is_finite() and not w.body.hips.value.is_zero_approx(),"Named motion drives the actual hip rig, with supported feet")
		var authored: Dictionary = Motion.sample(w.active_move,w.elapsed)
		check(absf(angle_difference(w.body.hips.value.y,authored.hip.y))<0.2,"Authored hip yaw takes precedence over generic spin presets")
		await shot(String(id))
		w.cancel()
		check(w.active_move.is_empty() and w._combo_remaining==0,"Cancellation clears active attacks and combo state")
		p.global_position.y += 4
		p.velocity = Vector3.ZERO
		p.move_and_slide()
		var air: Dictionary = w.move_for(&"right",&"attack_right")
		check(air.get("aerial",false),"Airborne actors select the separate aerial attack data")
		p.global_position.y -= 4
		p.set_physics_process(true)
		w.set_physics_process(true)
		await frames(hz/2)
	# A named strike still resolves real hurtboxes and actual velocity damage.
	var target := Target.new()
	target.max_health = 100000
	world.add_child(target)
	target.position = p.position+Vector3(0,.0,-1.2)
	await frames(3)
	w._facing = Vector3.FORWARD
	var damage: Array[float] = []
	for speed: float in [0,30]:
		w.active_move = w.move_for(&"right",&"attack_right")
		w._pulse_targets.clear()
		p.velocity = Vector3(0,0,-speed)
		var before: float = target.health
		w.strike(0)
		damage.append(before-target.health)
	check(damage[0]>0 and damage[1]>damage[0]*2,"Named attacks hit actual hurtboxes and retain uncapped velocity-based impact damage")
	w.cancel()
	p.velocity = Vector3.ZERO
	target.queue_free()
	check(own(&"eternal_scribe_robes",&"body")!=null,"Existing Scribe robe remains an owned Body cosmetic")
	for family: String in ["head","hands","legs","shield","ring"]:
		var slot := StringName("ring1" if family=="ring" else family)
		for entry: Dictionary in Database.all():
			if entry.family!=family: continue
			check(own(StringName(entry.id),slot)!=null,"Wear "+family+" alongside the original robe")
			break
	await frames(hz)
	check(p.visual.robe.is_equipped() and not p.visual.robe.get_node("OpenScholarHood").visible,"Helmet hides the overlapping robe hood while retaining the fitted robe")
	check(Vector3(p.walk_speed,p.run_speed,p.boost_speed)==original_pace and p.weapon_combat.max_health==1000,"Armor and rings add no movement restrictions or combat stats")
	await shot("cosmetics")
	var snapshot: Dictionary = p.inventory.serialize()
	check(p.inventory.restore(snapshot) and p.inventory.serialize()==snapshot,"Named items and all new equipment slots round-trip without changing save version")
	var shop: CanvasLayer = world.inventory_session.shop
	p.position = shop.anchor()+Vector3(0,.1,3.2)
	p.velocity = Vector3.ZERO
	await frames(hz/2)
	shop.open_menu()
	shop.open_browser()
	check(shop.is_open and shop.browser.ids.size()==Database.all().size() and shop.browser.buttons.size()<=9 and not paused,"The live shop browses the complete catalog with a bounded row count")
	await frames(3)
	check(root.get_visible_rect().encloses(shop.browser.buttons[-1].get_global_rect()),"A complete browser page fits the viewport")
	shop.browser.query.text = "The Fractured Moon"
	shop.browser.refresh()
	var matches: bool = shop.browser.ids==[&"fractured_moon"]
	shop.browser.query.text = "no-such-item-xyz"
	shop.browser.refresh()
	var empty: bool = shop.browser.ids.is_empty() and not shop.browser.model.visible
	shop.browser.query.text = "The Fractured Moon"
	shop.browser.refresh()
	check(matches and empty,"Search finds a specific named item and clears unmatched previews")
	var before: int = p.inventory.count_type(&"fractured_moon")
	check(shop.buy(&"fractured_moon") and p.inventory.count_type(&"fractured_moon")==before+1,"The browser acquires one owned item through existing shop authority")
	shop.browser.buttons[0].grab_focus()
	shop._accept()
	shop._accept()
	check(p.inventory.count_type(&"fractured_moon")==before+3,"Repeated controller confirmation keeps focus and acquires exactly one item per press")
	check(not shop.buy(&"forged_equipment"),"Unknown equipment cannot be minted through the expanded shop")
	shop.browser.filter.select(1)
	shop.browser.query.text = ""
	shop.browser.refresh()
	await shot("shop")
	shop.close_menu()
	var ui: CanvasLayer = world.inventory_session.ui
	ui.open_menu()
	ui.select_tab(1)
	check(ui.equipment_buttons.size()==11 and not paused,"The live inventory exposes cosmetic and ring slots alongside all four directions")
	await frames(3)
	check(ui._help.global_position.y+ui._help.size.y<=695,"Equipment scrolling keeps the footer within the 720p viewport")
	await shot("inventory")
	ui.close_menu()
	check(w.rig.models.size()<=5 and Geometry.cache.size()<=Geometry.CACHE_LIMIT,"Repeated named equips retain bounded rig models and mesh cache")
	print("EQUIPMENT INTEGRATION: ",checks," checks, ",failures," failures at ",hz," Hz")
	world.queue_free()
	controls.queue_free()
	await frames(2)
	quit(1 if failures else 0)
