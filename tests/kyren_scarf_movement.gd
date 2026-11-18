extends SceneTree
## Both actual wearers share world-space, velocity-driven ribbon flow.
const Catalog = preload("res://scripts/item_catalog.gd")
var checks := 0
var failures := 0
var hz := 60

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func settle(scarf: Node3D, duration: float = .8) -> void:
	for i in range(ceili(duration*hz)): scarf.advance(1.0/hz)

func tail(scarf: Node3D) -> Vector3:
	return (scarf.to_global(scarf.points[-1])-scarf.to_global(scarf.points[0])).normalized()

func run() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.district_life_enabled=false
	world.world_memory_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	var p: CharacterBody3D=world.player
	var kyren: CharacterBody3D=world.wider_world.kyren_home.kyren
	p.set_physics_process(false)
	p.weapon_combat.set_physics_process(false)
	kyren.set_physics_process(false)
	var item: Resource=Catalog.create(&"kyren_scarf")
	p.inventory.add_item(item)
	check(world.loot.request_equip(p.inventory,&"body",item.instance_id),"Player equips Kyren's scarf through the normal inventory")
	p.visual.sync_clothing(p.inventory)
	var copy: Node3D=p.visual.equipment_cosmetics.pieces[&"body"][0].scarf
	check(copy.motion_source==p and kyren.scarf.motion_source==kyren,"Original scarf and wearable copy bind to their actual wearer")
	# A turning/leaning chest must not rotate world-space travel into a false tail.
	p.visual.chest.rotation=Vector3(.5,1.7,.25)
	kyren.rotation.y=.8
	for wearer: CharacterBody3D in [kyren,p]:
		var scarf: Node3D=kyren.scarf if wearer==kyren else copy
		scarf.set_process(false)
		var nodes:=scarf.get_child_count()
		var mesh: Mesh=scarf.cloth.mesh
		for motion: Vector3 in [Vector3(1.4,0,0),Vector3(-8,0,0),Vector3(0,0,10),Vector3(0,0,-20),Vector3(0,8,0),Vector3(0,-15,0),Vector3(4,9,-8)]:
			wearer.velocity=motion
			settle(scarf)
			check(tail(scarf).dot(-motion.normalized())>.85,"Scarf trails actual movement "+str(motion)+" for "+wearer.name)
		var stable:=true
		for i in range(scarf.SEGMENTS): stable=stable and absf(scarf.points[i].distance_to(scarf.points[i+1])-3.0/24)<.0001
		check(stable and scarf.to_global(scarf.points[0]).distance_to(scarf.anchor.global_position)<.001,"Three-metre cloth remains pinned to the neck: "+wearer.name)
		wearer.velocity=Vector3(10,0,0)
		settle(scarf)
		var before: Vector3=tail(scarf)
		wearer.velocity=Vector3(-10,0,0)
		scarf.advance(1.0/hz)
		check(before.dot(tail(scarf))>.9,"Direction reversals ease into the new trail: "+wearer.name)
		settle(scarf)
		check(tail(scarf).x>.9,"Reversed movement settles behind the wearer: "+wearer.name)
		wearer.velocity=Vector3.ZERO
		settle(scarf)
		var quadrants: Dictionary={}
		for i in range(1200):
			scarf.advance(.05)
			var direction:=tail(scarf)
			quadrants[str(direction.x>0)+":"+str(direction.z>0)]=true
		check(quadrants.size()==4,"Stationary scarf returns to wandering wind in all quadrants: "+wearer.name)
		var direction:=tail(scarf)
		wearer.global_position+=Vector3(0,30,400)
		scarf.advance(0)
		check(tail(scarf).dot(direction)>.999 and scarf.to_global(scarf.points[0]).distance_to(scarf.anchor.global_position)<.001,"Teleport displacement never becomes false movement or a stretched trail: "+wearer.name)
		check(scarf.get_child_count()==nodes and scarf.cloth.mesh==mesh and scarf.cloth.instance_count==24 and scarf.trim.instance_count==48,"Movement flow reuses the existing cloth pools: "+wearer.name)
	var vehicle:=CharacterBody3D.new()
	world.add_child(vehicle)
	p.world_actions.vehicle=vehicle
	p.velocity=Vector3.ZERO
	vehicle.velocity=Vector3(20,0,-20)
	settle(copy)
	check(tail(copy).dot(-vehicle.velocity.normalized())>.9,"A mounted player's scarf follows the vehicle's world velocity")
	p.world_actions.vehicle=null
	world.queue_free()
	await process_frame
	print("Kyren scarf movement: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
