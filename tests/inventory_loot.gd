extends SceneTree
## Exercise real model ownership, collision LOS and authoritative transactions.
const Inventory = preload("res://scripts/inventory.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Authority = preload("res://scripts/loot_authority.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
const Neon = preload("res://scripts/neon.gd")
class Actor extends Node3D:
	var weapon_combat: Node
class ForcedGate extends Node:
	var allowed := false
	func can_act() -> bool: return allowed
var checks := 0
var failures := 0
var scene: Node3D
var loot: Node3D
var a: Node
var b: Node
var actor_a: Node3D
var actor_b: Node3D
var notified_quantity := 0
var spawn_calls := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count): await physics_frame

func first_pickup() -> Node3D:
	return loot.pickups.values()[0] if not loot.pickups.is_empty() else null

func _initialize() -> void: call_deferred("run")

func failing_factory() -> Node3D: return null

func flaky_factory() -> Node3D:
	spawn_calls += 1
	return Pickup.new() if spawn_calls == 1 else null

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	Neon.prepare()
	Neon.block(scene,Vector3(0,-0.25,0),Vector3(32,0.5,32))
	actor_a = Actor.new()
	actor_b = Actor.new()
	scene.add_child(actor_a)
	scene.add_child(actor_b)
	actor_b.position.x = 2
	a = Inventory.new()
	a.owner_id = "A"
	a.actor = actor_a
	actor_a.add_child(a)
	b = Inventory.new()
	b.owner_id = "B"
	b.actor = actor_b
	actor_b.add_child(b)
	loot = Authority.new()
	scene.add_child(loot)
	loot.picked_up.connect(func(_inventory: Node,item: Resource): notified_quantity = item.quantity)
	check(loot.register_inventory(a) and loot.register_inventory(b),"Two distinct player owners register at the authority boundary")
	await frames()
	var katana: Resource = Catalog.create(&"katana")
	katana.upgrade_level = 7
	katana.custom_properties = {"engraving":"A's unique blade","seed":33}
	var katana_id: String = katana.instance_id
	check(a.add_item(katana) and loot.request_equip(a,&"right",katana_id),"Owned unique equipment assigns through the host equipment boundary")
	check(loot.request_drop(a,katana_id,1,Vector3(1.2,0,0)),"Manual drop spawns a real world pickup before transferring the item")
	var pickup := first_pickup()
	check(a.get_item(katana_id) == null and not a.equipment.has(&"right") and pickup.item_instance == katana,"Equipped drop removes its assignment and transfers the actual unique instance")
	check(loot.markers.markers.is_empty(),"Manual trading drops never generate lost-equipment markers")
	check(loot.request_pickup(b,pickup),"Player B can acquire player A's ordinary world drop")
	var duplicate_accepts := 0
	for i in range(64):
		if loot.request_pickup(a,pickup) or loot.request_pickup(b,pickup): duplicate_accepts += 1
	check(duplicate_accepts == 0 and b.get_item(katana_id) == katana and a.get_item(katana_id) == null,"128 rapid repeated pickup attempts cannot duplicate a claimed item")
	check(katana.owner_id == "B" and katana.upgrade_level == 7 and katana.custom_properties.engraving == "A's unique blade","Ownership, upgrades and custom properties survive A-to-world-to-B transfer")
	check(not loot.request_drop(a,katana_id,1,Vector3(1,0,0)),"An old owner has no right to drop or reclaim another owner's item")
	check(loot.request_drop(b,katana_id,1,Vector3(1.3,0,0)) and loot.request_pickup(a,first_pickup()),"The same unique instance can be transferred repeatedly without restoration rights")
	await frames()
	var spare: Resource = Catalog.create(&"spear")
	a.add_item(spare)
	loot.request_equip(a,&"right",katana_id)
	loot.death_drop_probability = 1
	var death: Dictionary = loot.resolve_death(a,"life-1",Vector3(1.0,0,0))
	check(death.dropped and a.get_item(katana_id) == null and a.get_item(spare.instance_id) == spare,"Guaranteed death roll selects equipped gear and leaves stored gear untouched")
	var death_replays := true
	for i in range(64): death_replays = death_replays and loot.resolve_death(a,"life-1",Vector3(1,0,0)) == death
	check(death_replays and loot.pickups.size() == 1,"A death token produces at most one roll and one world instance")
	check(loot.markers.for_owner("A").size() == 1 and loot.markers.for_owner("B").is_empty(),"Only the losing owner receives the unclaimed death-loss marker")
	pickup = loot.pickups[death.pickup_id]
	check(loot.request_pickup(b,pickup) and loot.markers.for_owner("A").is_empty(),"Any player's successful pickup removes the original owner's marker")
	loot.request_equip(b,&"right",katana_id)
	var recovered_death: Dictionary = loot.resolve_death(b,"life-1",Vector3(1.1,0,0))
	check(recovered_death.dropped and loot.request_pickup(a,loot.pickups[recovered_death.pickup_id]) and katana.owner_id == "A","A may recover the same upgraded katana if B later loses it through the same rules")
	var empty_loss: Dictionary = loot.resolve_death(a,"unequipped-life",Vector3(1,0,0))
	check(not empty_loss.dropped and a.get_item(katana_id) != null,"Unequipped inventory items never enter the automatic death-loss pool")
	loot.request_equip(a,&"right",katana_id)
	loot.death_drop_probability = 0
	var failed_roll: Dictionary = loot.resolve_death(a,"failed-roll",Vector3(1,0,0))
	loot.death_drop_probability = 1
	check(not failed_roll.dropped and loot.resolve_death(a,"failed-roll",Vector3(1,0,0)) == failed_roll,"Changing drop chance cannot reroll an already processed death")
	var before: Dictionary = a.serialize()
	loot.spawn_factory = failing_factory
	check(not loot.request_drop(a,katana_id,1,Vector3(1,0,0)) and a.serialize() == before,"Failed world creation preserves the item and its equipped assignment")
	loot.spawn_factory = Callable()
	var gate := ForcedGate.new()
	actor_a.add_child(gate)
	actor_a.weapon_combat = gate
	check(not loot.request_equip(a,&"up",katana_id) and not loot.request_unequip(a,&"right") and not loot.request_drop(a,katana_id,1,Vector3(1,0,0)) and a.serialize() == before,"Forced combat states reject equipment reassignment, unequipping and manual equipped-item drops")
	var forced_death: Dictionary = loot.resolve_death(a,"forced-life",Vector3(1,0,0))
	check(forced_death.dropped and a.get_item(katana_id) == null,"A legitimate death loss remains possible during an existing forced combat reaction")
	check(loot.request_pickup(a,loot.pickups[forced_death.pickup_id]),"Collecting unclaimed world loot does not bypass or need an equipment action")
	gate.allowed = true
	loot.request_equip(a,&"right",katana_id)
	var key: Resource = Catalog.create(&"civic_key")
	a.add_item(key)
	check(not loot.request_drop(a,key.instance_id,1,Vector3(1,0,0)) and a.get_item(key.instance_id) == key,"Nontransferable definition flags protect exclusive gear without name checks")
	var stack: Resource = Catalog.create(&"light_shard",40)
	stack.custom_properties = {"batch":"same"}
	a.add_item(stack)
	check(loot.request_drop(a,stack.instance_id,7,Vector3(1,0,0)) and stack.quantity == 33,"Partial stack drop subtracts only the selected quantity")
	pickup = first_pickup()
	var split_id: String = pickup.item_instance.instance_id
	check(split_id != stack.instance_id and pickup.item_instance.custom_properties == stack.custom_properties,"A split stack receives its own identity while retaining matching properties")
	check(loot.request_pickup(b,pickup) and b.get_item(split_id).quantity == 7,"A second owner can collect the selected stack quantity")
	check(loot.request_drop(a,stack.instance_id,5,Vector3(1,0,0)) and loot.request_pickup(b,first_pickup()) and b.get_item(split_id).quantity == 12,"Matching property stacks merge after world transfer")
	check(notified_quantity == 5,"Pickup notification retains collected quantity even when the incoming stack is fully absorbed")
	check(not loot.request_drop(a,stack.instance_id,999,Vector3(1,0,0)) and not loot.request_drop(a,stack.instance_id,1,Vector3(10,0,0)),"Invalid quantities and remote drop requests leave inventory unchanged")
	# Real world collision blocks interaction; distance and host validation do too.
	loot.request_drop(a,stack.instance_id,1,Vector3(1.5,0,0))
	pickup = first_pickup()
	actor_a.position = Vector3(10,0,0)
	check(not loot.request_pickup(a,pickup) and loot.nearest_pickup(actor_a) == null,"Distant actors cannot collect or target a remote pickup")
	actor_a.position = Vector3.ZERO
	var wall := StaticBody3D.new()
	scene.add_child(wall)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12,2,2)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0.7,1,0)
	await frames()
	check(not loot.request_pickup(a,pickup) and loot.nearest_pickup(actor_a) == null,"Physical walls prevent both pickup requests and nearest-pickup interaction hints")
	before = a.serialize()
	check(not loot.request_drop(a,stack.instance_id,1,Vector3(0.7,0,0)) and a.serialize() == before,"A failed drop inside solid geometry preserves the full inventory")
	check(not loot.request_drop(a,stack.instance_id,1,Vector3(1.5,0,0)) and a.serialize() == before,"Manual drops cannot pass through a solid wall to a remote floor")
	wall.queue_free()
	await frames()
	actor_a.position = Vector3(0,20,0)
	before = a.serialize()
	check(not loot.request_drop(a,stack.instance_id,1,Vector3(1,20,0)) and a.serialize()==before,"A manual airborne drop cannot teleport an item to distant ground")
	actor_a.position = Vector3.ZERO
	loot.host_enabled = false
	check(not loot.request_pickup(a,pickup) and not loot.request_drop(a,katana_id,1,Vector3(1,0,0)) and not loot.request_equip(a,&"up",katana_id) and not loot.request_unequip(a,&"right") and loot.resolve_death(a,"client",Vector3.ZERO).is_empty(),"Non-host callers cannot mutate pickups, drops, equipment or death rolls")
	loot.host_enabled = true
	loot.validator = func(_op: StringName,_inventory: Node,_payload: Dictionary) -> bool: return false
	check(not loot.request_pickup(a,pickup) and not loot.request_equip(a,&"up",katana_id),"A future session validator can deny ownership operations centrally")
	loot.validator = Callable()
	loot.request_pickup(a,pickup)
	# A checkpoint contains the actual unowned instances and derived markers.
	loot.request_drop(a,stack.instance_id,3,Vector3(1,0,0))
	loot.request_equip(a,&"right",katana_id)
	var persisted_death: Dictionary = loot.resolve_death(a,"persisted-life",Vector3(-1,0,0))
	var snapshot: Array = loot.serialize_world()
	check(snapshot.size() == 2 and persisted_death.dropped,"World snapshot encodes both manual drops and unclaimed death gear")
	check(loot.restore_world(snapshot),"A fully validated world snapshot restores atomically")
	await frames()
	check(loot.serialize_world() == snapshot and loot.markers.for_owner("A").size() == 1,"Old nodes exiting after restoration cannot erase replacement pickups or death markers")
	var bad: Array = snapshot.duplicate(true)
	bad.append(snapshot[0].duplicate(true))
	check(not loot.restore_world(bad) and loot.serialize_world() == snapshot,"Duplicate pickup or instance identities reject the whole snapshot without world changes")
	bad = snapshot.duplicate(true)
	bad[0].item = spare.to_dict()
	bad[0].item.owner_id = ""
	check(not loot.restore_world(bad),"A checkpoint cannot recreate a world instance already owned by a registered inventory")
	bad = snapshot.duplicate(true)
	bad[0].position = [NAN,0,0]
	check(not loot.restore_world(bad) and loot.serialize_world() == snapshot,"Nonfinite checkpoint coordinates reject without deleting existing world items")
	spawn_calls = 0
	loot.spawn_factory = flaky_factory
	check(not loot.restore_world(snapshot) and loot.serialize_world() == snapshot,"Failure on a later candidate spawn leaves the previous world transaction intact")
	loot.spawn_factory = Callable()
	await frames()
	pickup = loot.pickups[persisted_death.pickup_id]
	pickup.position += Vector3(0,0,1)
	check(loot.markers.for_owner("A")[0].world_position == pickup.global_position,"The map hook reports the current location of an unclaimed item")
	pickup.queue_free()
	await frames()
	check(loot.markers.for_owner("A").is_empty() and not loot.pickups.has(persisted_death.pickup_id),"Legitimate removal of unclaimed loot removes its marker and authority entry")
	var editor_pickup: Node3D = load("res://scenes/item_pickup.tscn").instantiate()
	editor_pickup.item_type_id = &"twin_blades"
	editor_pickup.upgrade_level = 2
	editor_pickup.custom_properties = {"origin":"editor"}
	scene.add_child(editor_pickup)
	editor_pickup.position = Vector3(0,0,1.5)
	check(loot.register_pickup(editor_pickup) and editor_pickup.item_instance.upgrade_level == 2 and editor_pickup.item_instance.custom_properties.origin == "editor","Editor-placed pickup scene creates configured native item data")
	check(loot.request_pickup(a,editor_pickup),"Configured editor loot uses the same authoritative interaction path")
	var shadow_owner: Node = Inventory.new()
	shadow_owner.owner_id = "A"
	shadow_owner.actor = actor_a
	scene.add_child(shadow_owner)
	check(not loot.register_inventory(shadow_owner),"A second live inventory cannot impersonate an already registered owner ID")
	scene.queue_free()
	await process_frame
	print("Inventory loot verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
