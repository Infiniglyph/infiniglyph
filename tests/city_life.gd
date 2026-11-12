extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Vehicle = preload("res://scripts/traffic_vehicle.gd")
const Regions = preload("res://scripts/world_regions.gd")
class Intent:
	extends "res://scripts/player_input.gd"
	func sample() -> void:
		if not gameplay_enabled: move = Vector2.ZERO
var world: Node3D
var actor: CharacterBody3D
var controls: Node
var actions: Node3D
var life: Node3D
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func button(code: int, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = pressed
	controls._unhandled_input(event)

func shot(label: String, from: Vector3, to: Vector3) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	if "--parking-only" in OS.get_cmdline_user_args() and not label.begins_with("parking_"): return
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = from
	camera.look_at(to)
	camera.current = true
	await frames(3)
	if "--performance" in OS.get_cmdline_user_args() and label in ["urban","suburbs","country"]:
		var times: Array[float] = []
		var calls := 0.0
		for i in range(45):
			var before := Time.get_ticks_usec()
			await process_frame
			times.append((Time.get_ticks_usec()-before)/1000.0)
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		times.sort()
		print("LIFE PERFORMANCE: ",label," median_ms=",times[22]," p95_ms=",times[42]," draw_calls=",calls/45," people=",life.people.size()," vehicles=",life.vehicles.size())
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/life_"+label+".png")
	camera.queue_free()
	world.camera_rig.camera.current = true
	print("CAPTURE: ",label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	actor = world.player
	actor.visual.retrieval.enabled = false
	world.greefer.think_enabled = false
	world.theft_reactions.max_fighters = 0 # Handling/interaction fixture; retaliation has its own combat suite.
	actions = world.world_actions
	life = world.district_life
	await frames(5)
	controls = Intent.new()
	root.add_child(controls)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	actor.controls = controls
	world.inventory_session.controls = controls
	controls.interaction_context = world.inventory_session
	world.camera_rig.controls = controls
	check(actor.inventory.count_type(&"health_glyph")==3,"Three owned Health Glyphs granted once")
	actor.inventory.introduce_health_glyphs()
	check(actor.inventory.count_type(&"health_glyph")==3,"Grant is idempotent")
	var copy := Inventory.new()
	check(copy.restore(actor.inventory.serialize()),"Glyph ownership and migration flag serialize")
	copy.introduce_health_glyphs()
	check(copy.count_type(&"health_glyph")==3,"Reload does not refill glyphs")
	copy.free()
	check(not world.loot.request_health_glyph(actor.inventory) and actor.inventory.count_type(&"health_glyph")==3,"Full health does not consume a glyph")
	actor.weapon_combat.health = 400
	controls.set_right_trigger(1)
	button(JOY_BUTTON_B)
	check(controls.heal_requested and not controls.dodge_requested,"RT+B requests healing without dodge")
	button(JOY_BUTTON_B) # Duplicate down event is not a second use.
	controls.set_right_trigger(0)
	await frames(2)
	check(actor.health==750 and actor.inventory.count_type(&"health_glyph")==2,"One chord heals 350 HP and consumes one owned glyph")
	button(JOY_BUTTON_B,false)
	button(JOY_BUTTON_B)
	check(controls.consume_dodge() and not controls.consume_heal(),"B alone still dodges")
	button(JOY_BUTTON_B,false)
	actor.weapon_combat.health = 950
	check(world.loot.request_health_glyph(actor.inventory) and actor.health==1000,"Healing caps at maximum HP")
	world.loot.host_enabled = false
	actor.weapon_combat.health = 500
	check(not world.loot.request_health_glyph(actor.inventory),"Non-authoritative client cannot consume or heal")
	world.loot.host_enabled = true
	var reentered := [false]
	var callback := func():
		if world.loot.request_health_glyph(actor.inventory): reentered[0] = true
	actor.inventory.changed.connect(callback)
	check(world.loot.request_health_glyph(actor.inventory) and actor.health==850 and actor.inventory.count_type(&"health_glyph")==0,"Last glyph is removed and restores HP")
	actor.inventory.changed.disconnect(callback)
	check(not reentered[0] and not world.loot.request_health_glyph(actor.inventory),"Empty inventory and reentrant notifications cannot duplicate healing")
	actor.inventory.add_item(Catalog.create(&"health_glyph",4))
	var clear_pickups := true
	for pickup: Node3D in world.loot.pickups.values():
		if not world.loot.clear_volume(pickup.global_position):
			print("BLOCKED PICKUP: ",pickup.item_instance.item_type_id," at ",pickup.global_position)
			clear_pickups = false
	check(clear_pickups,"Starter world pickups have clear physical volumes")
	check(world.inventory_session.save_checkpoint("user://life_inventory_test.json"),"Consumed glyph inventory saves through existing checkpoint")
	for item: Resource in actor.inventory.items.values():
		if item.item_type_id==&"health_glyph": actor.inventory.take_item(item.instance_id,1)
	check(actor.inventory.count_type(&"health_glyph")==3,"Checkpoint restore fixture changes the saved quantity")
	check(world.inventory_session.load_checkpoint("user://life_inventory_test.json") and actor.inventory.count_type(&"health_glyph")==4,"Saved quantities restore without reminting")
	check(actions.glyph_count.text.contains("4") and root.get_visible_rect().encloses(actions.glyph_count.get_global_rect()),"Bottom-left glyph count reflects inventory and fits viewport")
	check(actions.seats.size()>20,"Hub, quarter and expanded park benches are registered")
	var chosen: Dictionary = actions.seats[0]
	actor.global_position = chosen.point+chosen.forward*1.1
	actor.global_position.y = 0.05
	actor.velocity = Vector3.ZERO
	await frames(10)
	check(actions.nearest().get("kind")=="seat","Bench is contextually reachable from its front")
	controls.set_right_trigger(1)
	button(JOY_BUTTON_B)
	controls.set_right_trigger(0)
	check(not controls.consume_interaction(),"Healing near a bench cannot also sit")
	await frames(2)
	button(JOY_BUTTON_B,false)
	controls.set_right_trigger(1)
	controls.set_right_trigger(0)
	await frames(3)
	check(actions.attached() and not actions.seat.is_empty() and chosen.occupant==actor,"RT tap claims a bench")
	check(actor.collision_layer==0 and actor.velocity.length()<0.01,"Seating suppresses walking and bench collision snagging")
	check(absf(actor.visual.joints.LeftLeg.rotation.x)>0.8 and actor.weapon_combat.rig.sheathed,"Seated pose bends thighs forward with weapons stowed")
	actor.weapon_combat.health = 900
	controls.set_right_trigger(1)
	button(JOY_BUTTON_B)
	controls.set_right_trigger(0)
	await frames(2)
	button(JOY_BUTTON_B,false)
	check(actions.attached() and actor.health==1000,"RT+B heals while seated without also standing")
	await shot("bench",actor.global_position+Vector3(3.4,2.1,3),chosen.point+Vector3.UP*0.4)
	check(actions.leave() and chosen.occupant==null and actor.collision_layer==1 and actor.collision_mask==13,"Stand releases claim and restores original collision")
	await frames(8)
	check(actor.unstuck.clear_at(actor.global_position+Vector3.UP*0.08) and actor.unstuck.broad_support(actor.global_position+Vector3.UP*0.065),"Bench exit uses clear supported footing")
	actor.global_position = chosen.point+chosen.forward*1.1
	actor.global_position.y = 0.05
	await frames(6)
	actions.interact()
	controls.move = Vector2.LEFT
	await frames(3)
	check(not actions.attached() and chosen.occupant==null,"Movement stands up and releases the bench claim")
	controls.move = Vector2.ZERO
	check(life.resident_records.size()>700 and life.vehicle_records.size()>100,"Expanded city has distributed resident and vehicle rosters")
	var women := 0
	var colors: Dictionary = {}
	for record: Dictionary in life.resident_records:
		if record.profile.body_profile==&"female": women += 1
		colors[record.profile.tint] = true
	check(women*2==life.resident_records.size() and colors.size()==11,"Additional population preserves 50/50 silhouettes and all eleven colors")
	var parked: Dictionary = {}
	for record: Dictionary in life.vehicle_records:
		if not record.traffic and maxf(absf(record.point.x),absf(record.point.z))<Regions.SUBURB_EDGE:
			parked = record
			break
	check(not parked.is_empty(),"Parked vehicles occupy checked physical driveways")
	actor.global_position = Vector3(192,0.05,128)
	actor.velocity = Vector3.ZERO
	await frames(hz)
	life.refresh_active()
	await frames(2)
	check(life.people.size()>0 and life.vehicles.size()>0 and life.people.size()<=life.resident_budget and life.vehicles.size()<=life.vehicle_budget,"Urban population and traffic activate within fixed budgets")
	await shot("urban",Vector3(178,4.5,135),Vector3(211,1.5,128))
	# Isolated road fixtures test every body type through the same action pipeline.
	life.set_physics_process(false)
	for vehicle: CharacterBody3D in life.vehicles.values(): vehicle.queue_free()
	life.vehicles.clear()
	for person: CharacterBody3D in life.people.values(): person.queue_free()
	life.people.clear()
	await frames(2)
	var n := 0
	for kind: String in ["motorcycle","car","truck"]:
		# Each handling fixture uses open road. Driver materialization is checked
		# above; keep its roster but release its live body before the next test.
		for person: CharacterBody3D in life.people.values(): person.queue_free()
		life.people.clear()
		await frames(2)
		var record := {"id":10000+n,"kind":kind,"point":Vector3(192,0.05,128),"yaw":PI*0.5,"traffic":false,"taken":false,"route":PackedVector3Array(),"cursor":0,"color":Color(0.3,0.9,1),"driver":life.profile_for(n,true)}
		var vehicle := Vehicle.new()
		vehicle.record = record
		vehicle.life = life
		life.add_child(vehicle)
		life.vehicles[record.id] = vehicle
		actor.global_position = vehicle.global_position+Vector3(0,0,2.1)
		actor.velocity = Vector3.ZERO
		await frames(8)
		if kind=="car": vehicle.has_driver = true
		var previous_people: int = life.resident_records.size()
		check(actions.board(vehicle),"Enter "+kind+" through contextual vehicle action")
		if kind=="car": check(life.resident_records.size()==previous_people+1 and not vehicle.has_driver,"Taking an occupied car places its driver safely in the world")
		controls.move = Vector2(0,-1)
		var before: Vector3 = vehicle.global_position
		await frames(hz*2)
		print("DRIVE: ",kind," from=",before," to=",vehicle.global_position," speed=",vehicle.signed_speed," anchor_error=",actor.global_position.distance_to(vehicle.to_global(Vector3(0,vehicle.seat_height-0.946,vehicle.seat_z))))
		if vehicle.signed_speed<3:
			for index in range(vehicle.get_slide_collision_count()): print("DRIVE CONTACT: ",vehicle.get_slide_collision(index).get_collider()," normal=",vehicle.get_slide_collision(index).get_normal())
		check(vehicle.global_position.distance_to(before)>5 and vehicle.signed_speed>3 and actor.global_position.distance_to(vehicle.to_global(Vector3(0,vehicle.seat_height-0.946,vehicle.seat_z)))<0.05,"Drive "+kind+" with continuous camera-following attachment")
		check(not actions.leave(),"Moving "+kind+" prevents unsafe exit")
		if kind=="car":
			controls.move = Vector2(0.5,-0.5)
			var yaw: float = vehicle.rotation.y
			await frames(hz)
			check(absf(wrapf(vehicle.rotation.y-yaw,-PI,PI))>0.2,"Steering turns the physical vehicle")
		controls.move = Vector2.ZERO
		await frames(hz*2)
		await shot(kind,vehicle.global_position+Vector3(5,2.7,5),vehicle.global_position+Vector3.UP)
		check(actions.leave() and actor.collision_mask==13 and actor.unstuck.clear_at(actor.global_position),"Stop and exit "+kind+" onto clear ground")
		# Enter a real generated driveway from the street, across its 5 cm lip.
		# The same body, driver and attachment are retained after the road test.
		var parking: Vector3 = parked.point-Vector3.UP*0.12
		vehicle.global_position = parking+Vector3(0,0.12,9)
		vehicle.rotation.y = PI
		vehicle.velocity = Vector3.ZERO
		vehicle.signed_speed = 0
		actor.global_position = vehicle.global_position+Vector3(2,0,0)
		actor.velocity = Vector3.ZERO
		await frames(ceili(hz*0.25))
		check(actions.board(vehicle),"Board "+kind+" at an actual suburban driveway")
		controls.move = Vector2(0,-0.25)
		controls.look = Vector2(0.5,0)
		for index in range(hz*5):
			await frames(1)
			if vehicle.global_position.z<parking.z+0.6: break
		controls.move = Vector2.ZERO
		controls.look = Vector2.ZERO
		await frames(hz)
		var parked_on_slab: Vector3 = vehicle.global_position-parking
		check(absf(parked_on_slab.x)<0.1 and absf(parked_on_slab.z)<1.4 and parked_on_slab.y> -0.02 and parked_on_slab.y<0.02,"Park "+kind+" on the raised physical driveway with free camera orbit")
		print("PARKING: ",kind," at=",vehicle.global_position," slab=",parking," offset=",parked_on_slab)
		await shot("parking_"+kind,vehicle.global_position+Vector3(5,2.7,5),vehicle.global_position+Vector3.UP)
		check(actions.leave() and actor.unstuck.clear_at(actor.global_position),"Leave parked "+kind+" onto checked clear footing")
		vehicle.queue_free()
		life.vehicles.erase(record.id)
		await frames(3)
		n += 1
	controls.set_gameplay_enabled(false)
	controls._unhandled_input(InputEventKey.new())
	controls.set_gameplay_enabled(true)
	controls.set_right_trigger(1)
	button(JOY_BUTTON_B)
	check(not controls.consume_heal() and not controls.special_modified(),"Menu close requires trigger neutral before a healing chord")
	button(JOY_BUTTON_B,false)
	controls.set_right_trigger(0)
	actor.global_position = Vector3(10,0.05,-512)
	actor.velocity = Vector3.ZERO
	life.set_physics_process(true)
	await frames(hz)
	check(life.people.size()>0 and life.vehicles.size()>0,"Suburbs populate when approached")
	await shot("suburbs",Vector3(23,5,-505),Vector3(15,1,-553))
	actor.global_position = Vector3(10,0.05,-930)
	actor.velocity = Vector3.ZERO
	await frames(hz)
	check(life.people.size()>0 and life.people.size()<=life.resident_budget and life.vehicles.size()<=life.vehicle_budget,"Country residents activate within dynamic budgets")
	await shot("country",Vector3(17,5,-930),Vector3(0,1,-975))
	print("CITY LIFE: ",checks," checks, ",failures," failures at ",hz," Hz; seats=",actions.seats.size()," roster=",life.resident_records.size()," vehicles=",life.vehicle_records.size())
	world.queue_free()
	controls.queue_free()
	await frames(2)
	quit(1 if failures else 0)
