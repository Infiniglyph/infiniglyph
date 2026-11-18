extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Preview = preload("res://scripts/equipment_preview.gd")
const Database = preload("res://scripts/equipment_database.gd")
const ItemType = preload("res://scripts/inventory_item_type.gd")
var world: Node3D
var p: CharacterBody3D
var boss: CharacterBody3D
var encounter: Node
var loot: Node3D
var hz := 60
var checks := 0
var failures := 0
var serial := 800
var rewards: Array[Resource] = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)
func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func seconds(time: float) -> void: await frames(ceili(time*hz))
func failing_factory() -> Node3D: return null
func select_roll(wanted: StringName) -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1000):
		rng.seed=seed_value
		if encounter.REWARDS[rng.randi_range(0,2)]==wanted:
			encounter.reward_rng.seed=seed_value
			return
func new_drop(previous: Dictionary) -> Node3D:
	for key: String in loot.pickups:
		if not previous.has(key): return loot.pickups[key]
	return null
func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/kyren_loot_"+label+".png")
func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	root.add_child(world)
	p=world.player
	boss=world.wider_world.kyren_home.kyren
	encounter=world.kyren_encounter
	loot=world.loot
	p.visual.retrieval.enabled=false
	p.set_physics_process(false)
	await frames(8)
	var original: Resource=boss.inventory.equipped_item(&"right")
	var original_id: String=original.instance_id
	var home: Vector3=boss.home_point
	for wanted: StringName in encounter.REWARDS:
		check(Catalog.get_definition(wanted)!=null and Catalog.get_definition(wanted).is_equippable,"Reward is registered and equippable: "+String(wanted))
		var at := home+Vector3(10,.06,8)
		p.global_position=at+Vector3(0,0,2)
		check(encounter.start(true),"A fresh challenge can start before the "+String(wanted)+" roll")
		boss.controls.stop()
		boss.global_position=at
		select_roll(wanted)
		var before: Dictionary=loot.pickups.duplicate()
		serial+=1
		var dealt: float=boss.receive_combat_hit(boss.health+1000,p.combat_point(),p,{"attack_serial":serial,"pulse":0,"item_id":"katana","action":"attack_right","parryable":true})
		var pickup := new_drop(before)
		check(dealt>0 and not encounter.active and loot.pickups.size()==before.size()+1 and pickup!=null,"A genuine Kyren defeat produces exactly one world pickup")
		if pickup==null:
			quit(1)
			return
		var key: String=pickup.pickup_id
		check(pickup.item_instance.item_type_id==wanted and pickup.item_instance.quantity==1 and pickup.item_instance.owner_id=="","The selected reward is one fresh unowned copy")
		check(pickup.global_position.distance_to(at)<.4 and boss.global_position.is_equal_approx(home),"Loot stays at the defeat location while Kyren teleports home")
		check(pickup.death_owner_id.is_empty() and loot.markers.for_owner(p.inventory.owner_id).is_empty(),"Boss loot is an ordinary pickup, not a lost-player-item marker")
		encounter.finish(true)
		check(loot.pickups.size()==before.size()+1,"A repeated lethal/finish notification cannot duplicate the reward")
		if wanted==&"kyren_hat":
			var path := "user://tests/kyren_unclaimed_loot.json"
			check(world.inventory_session.save_checkpoint(path) and world.inventory_session.load_checkpoint(path),"An unclaimed boss reward survives the existing inventory/world checkpoint")
			pickup=loot.pickups[key]
			check(pickup.item_instance.item_type_id==wanted and pickup.item_instance.owner_id=="","Reload preserves the same unclaimed reward identity")
		rewards.append(pickup.item_instance)
		check(loot.request_pickup(p.inventory,pickup) and rewards[-1].owner_id==p.inventory.owner_id,"G / RT pickup transfers the reward through normal ownership rules")
		check(not loot.request_pickup(p.inventory,pickup),"A claimed boss reward cannot be collected twice")
		await seconds(3.2)
	check(boss.inventory.equipped_item(&"right").instance_id==original_id and original.owner_id=="kyren" and boss.rest_visual.hat.get_parent()==boss.rest_visual.head_anchor,"Copies leave Kyren's original sword and costume intact for rematches")
	var unique: Dictionary={}
	for item: Resource in rewards: unique[item.instance_id]=true
	check(unique.size()==3 and not unique.has(original_id),"All reward copies have independent identities from Kyren and one another")
	var count: int=loot.pickups.size()
	p.global_position=home+Vector3(0,.1,3)
	encounter.start(true)
	boss.controls.stop()
	encounter.finish(false)
	check(loot.pickups.size()==count,"Kyren winning does not drop a reward")
	encounter.start(true)
	boss.controls.stop()
	encounter.disengage()
	check(loot.pickups.size()==count,"Disengaging does not farm boss rewards")
	for item: Resource in rewards:
		var slot: StringName=&"head" if item.item_type_id==&"kyren_hat" else &"body" if item.item_type_id==&"kyren_scarf" else &"right"
		check(loot.request_equip(p.inventory,slot,item.instance_id),"The reward equips in its existing slot: "+String(slot))
	p.combat.selected_slot=&"right"
	p.combat.sheathed=false
	p.weapon_combat.sync_rig()
	await frames()
	var cosmetics: Node3D=p.visual.equipment_cosmetics
	var hat: Node3D=cosmetics.pieces[&"head"][0]
	var scarf: Node3D=cosmetics.pieces[&"body"][0]
	check(hat.hat.embers.multimesh.instance_count==36 and hat.get_parent()==p.visual.chest and is_equal_approx(hat.position.y,.78),"The wearable hat uses Kyren's exact ember pool and attaches to the player's head")
	check(scarf.scarf.cloth.instance_count==24 and scarf.scarf.trim.instance_count==48 and scarf.get_parent()==p.visual.chest,"The wearable scarf reuses the original pooled cloth and neck attachment")
	scarf.scarf.advance(.1)
	var length := 0.0
	for i in range(scarf.scarf.SEGMENTS): length+=scarf.scarf.points[i].distance_to(scarf.scarf.points[i+1])
	check(absf(length-3)<.001,"The player's flowing scarf retains three metres of cloth")
	check(ItemType.label(Catalog.get_definition(&"kyren_scarf"))=="Flowing Scarf / Body" and ItemType.label(Catalog.get_definition(&"kyren_hat"))=="Straw Hat / Head","Inventory describes the two copies by their actual cosmetic types")
	p.dodge.start(Vector3.RIGHT)
	await frames()
	check(not hat.visible and not scarf.visible,"Hat and scarf hide coherently during the player's teleport without stretched light trails")
	p.dodge.cancel()
	await frames()
	check(hat.visible and scarf.visible and p.visual.scale==Vector3.ONE,"Cancelling a teleport restores both player-size cosmetic copies")
	var path := "user://tests/kyren_owned_loot.json"
	check(world.inventory_session.save_checkpoint(path),"Collected and equipped reward copies save with normal inventory ownership")
	loot.request_unequip(p.inventory,&"head")
	loot.request_unequip(p.inventory,&"body")
	check(world.inventory_session.load_checkpoint(path) and p.inventory.equipped_item(&"head").item_type_id==&"kyren_hat" and p.inventory.equipped_item(&"body").item_type_id==&"kyren_scarf","Loading restores the equipped hat and scarf, including their rendered attachments")
	await frames()
	for id: StringName in [&"kyren_hat",&"kyren_scarf"]:
		var preview := Preview.model(Database.get_item(id))
		world.add_child(preview)
		await frames()
		check(preview.find_child("KyrenHatCopy" if id==&"kyren_hat" else "KyrenScarfCopy",true,false)!=null,"Equipment Archive uses the actual cosmetic renderer: "+String(id))
		preview.queue_free()
	await frames()
	var old_count: int=loot.pickups.size()
	loot.host_enabled=false
	check(loot.spawn_reward(&"kyren_hat",home)==null and loot.pickups.size()==old_count,"Non-host loot authority cannot mint boss copies")
	loot.host_enabled=true
	loot.spawn_factory=failing_factory
	check(loot.spawn_reward(&"kyren_hat",home)==null and loot.pickups.size()==old_count,"Failed world creation cannot register a phantom reward")
	loot.spawn_factory=Callable()
	check(loot.spawn_reward(&"missing_reward",home)==null and loot.spawn_reward(&"kyren_hat",Vector3(INF,0,0))==null,"Unknown items and invalid reward positions are rejected")
	p.global_position=home+Vector3(0,.1,3)
	encounter.start(true)
	boss.controls.stop()
	boss.global_position=home-Vector3.UP*50
	var before_fallback: Dictionary=loot.pickups.duplicate()
	encounter.finish(true)
	var fallback := new_drop(before_fallback)
	check(fallback!=null and fallback.global_position.distance_to(home)<3.5,"A void defeat falls back to a safe reward position at Kyren's tree")
	await seconds(3.2)
	p.global_position=home+Vector3(0,.06,2)
	var fallback_id: String=fallback.pickup_id
	check(encounter.can_talk(),"Kyren can offer a rematch beside an unclaimed reward after recovery")
	await seconds(.3)
	check(world.inventory_session.hint.text.contains("collect"),"The nearby reward's pickup hint takes priority over Kyren's rematch prompt")
	world.inventory_session.interact()
	check(not loot.pickups.has(fallback_id) and not encounter.dialogue_open,"G / RT collects a reward at Kyren's feet instead of reopening his challenge")
	if "--capture" in OS.get_cmdline_user_args():
		p.global_position=home+Vector3(0,.06,5)
		p.visual.animate(.2,Vector3.ZERO,true)
		p.weapon_combat.apply_pose(.2)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.fov=55
		camera.position=p.global_position+Vector3(3,1.8,4)
		camera.look_at(p.global_position+Vector3.UP*.9)
		camera.current=true
		await capture("equipped")
	world.queue_free()
	await process_frame
	print("KYREN LOOT: ",checks," checks, ",failures," failures at ",hz," Hz")
	quit(1 if failures else 0)
