extends SceneTree
## Real ownership, persistent dismissal and authority-owned expiry across spaces.
const Authority = preload("res://scripts/loot_authority.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Store = preload("res://scripts/inventory_store.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Pickup = preload("res://scripts/item_pickup.gd")
const Neon = preload("res://scripts/neon.gd")
var checks := 0
var failures := 0
var scene: Node3D
var loot: Node3D
var a: Node
var b: Node

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func owner_inventory(id: String) -> Node:
	var actor := Node3D.new()
	scene.add_child(actor)
	var inventory := Inventory.new()
	inventory.owner_id = id
	inventory.actor = actor
	actor.add_child(inventory)
	return inventory

func lose(inventory: Node,type: StringName,at: Vector3,token: String) -> Node3D:
	var item: Resource = Catalog.create(type)
	inventory.add_item(item)
	loot.request_equip(inventory,&"right",item.instance_id)
	var result: Dictionary = loot.resolve_death(inventory,token,at)
	return loot.pickups.get(result.get("pickup_id",""))

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("Lost gear expiry test timed out"); quit(1))
	scene = Node3D.new()
	root.add_child(scene)
	Neon.prepare()
	Neon.block(scene,Vector3(0,-.25,0),Vector3(40,.5,40))
	loot = Authority.new()
	scene.add_child(loot)
	a = owner_inventory("A")
	b = owner_inventory("B")
	loot.register_inventory(a)
	loot.register_inventory(b)
	loot.death_drop_probability = 1
	await frames()
	var first := lose(a,&"katana",Vector3(1,0,0),"first")
	var second := lose(a,&"spear",Vector3(-1,0,0),"second")
	var foreign := lose(b,&"katana",Vector3(3,0,0),"foreign")
	var manual: Resource = Catalog.create(&"health_glyph")
	a.add_item(manual)
	check(loot.request_drop(a,manual.instance_id,1,Vector3(0,0,2)),"An ordinary manual drop is present alongside actual death losses")
	check(is_instance_valid(first) and is_instance_valid(second) and is_instance_valid(foreign),"Real death transactions create two local losses and another owner's loss")
	if not is_instance_valid(first) or not is_instance_valid(second) or not is_instance_valid(foreign):
		quit(1)
		return
	check(not first.loss_dismissed and first.loss_expires_at==0 and not first.has_node("LossExpiry"),"Undismissed death gear has no automatic timer or world countdown")
	loot.host_enabled = false
	check(not loot.request_dismiss_lost_gear(a) and not first.loss_dismissed,"A non-host cannot dismiss or expire gear")
	loot.host_enabled = true
	loot.validator = func(_operation: StringName,_inventory: Node,_payload: Dictionary) -> bool: return false
	check(not loot.request_dismiss_lost_gear(a) and not first.loss_dismissed,"The central session validator can reject loss dismissal")
	loot.validator = Callable()
	var impostor := owner_inventory("A")
	check(not loot.request_dismiss_lost_gear(impostor) and not first.loss_dismissed,"A duplicate inventory cannot impersonate the registered loss owner")
	var before := Time.get_unix_time_from_system()
	check(loot.request_dismiss_lost_gear(a),"The host accepts the registered owner's dismissal")
	var deadline: float = first.loss_expires_at
	check(first.loss_dismissed and second.loss_dismissed and first.loss_expires_at==second.loss_expires_at and deadline>=before+299.9 and deadline<=Time.get_unix_time_from_system()+300.1,"All current local death losses start the same five-minute deadline")
	check(not foreign.loss_dismissed and foreign.loss_expires_at==0,"Dismissing local losses leaves another player's death gear untouched")
	var ordinary_untimed := true
	for pickup: Node3D in loot.pickups.values():
		if pickup.death_owner_id.is_empty(): ordinary_untimed = ordinary_untimed and not pickup.loss_dismissed
	check(ordinary_untimed,"Manual drops never receive a lost-gear expiry timer")
	check(first.has_node("LossExpiry") and first.get_node("LossExpiry").text.begins_with("DISAPPEARS IN 5:") or first.has_node("LossExpiry") and first.get_node("LossExpiry").text.begins_with("DISAPPEARS IN 4:"),"Dismissed gear displays a billboard countdown in the world")
	var markers: Array = loot.markers.for_owner("A")
	check(markers.size()==2 and markers[0].dismissed and markers[1].dismissed and markers[0].expires_at==deadline,"Marker metadata suppresses HUD guidance without discarding recoverable gear")
	check(not loot.request_dismiss_lost_gear(a) and first.loss_expires_at==deadline,"Repeated dismissal cannot extend the timer or consume another action")
	var snapshot := Store.encode(a,loot.serialize_world())
	check(not snapshot.is_empty() and snapshot.world_drops.size()==4,"A validated checkpoint retains dismissed and ordinary world drops")
	var first_row: Dictionary = {}
	for row: Dictionary in snapshot.world_drops:
		if row.pickup_id==first.pickup_id: first_row = row
	check(first_row.get("loss_dismissed",false) and first_row.get("loss_expires_at")==deadline,"Checkpoint data preserves the original absolute dismissal deadline")
	var invalid := snapshot.duplicate(true)
	invalid.world_drops[0].loss_expires_at = "soon"
	check(Store.decode(invalid).is_empty() and not loot.validate_snapshot(invalid.world_drops),"Malformed timer data is rejected before any world mutation")
	invalid = snapshot.duplicate(true)
	invalid.world_drops[0].loss_dismissed = false
	invalid.world_drops[0].loss_expires_at = deadline
	check(Store.decode(invalid).is_empty(),"A deadline cannot be restored without its dismissed ownership state")
	check(Store.store("user://tests/lost_gear_expiration.json",snapshot)==OK,"Dismissed gear can be written through the real atomic checkpoint store")
	var loaded := Store.load_snapshot("user://tests/lost_gear_expiration.json")
	check(loot.restore_world(loaded.world_drops),"The saved world restores with dismissed losses still recoverable")
	await frames()
	first = loot.pickups[first_row.pickup_id]
	second = loot.pickups[markers[1].pickup_id]
	check(first.loss_expires_at==deadline and first.loss_dismissed and loot.markers.for_owner("A")[0].dismissed,"Reload preserves the countdown and HUD dismissal without restarting either")
	a.actor.global_position = first.global_position+Vector3(0,0,1)
	await frames()
	check(loot.request_pickup(a,first) and a.items.has(first_row.item.instance_id),"Dismissed gear remains normally recoverable before its deadline")
	check(loot.markers.for_owner("A").size()==1,"Early recovery removes only the recovered timer and marker")
	# Simulate an unloaded floor: expiry belongs to the live authority, rather
	# than a process callback on the hidden/disabled pickup itself.
	second.process_mode = Node.PROCESS_MODE_DISABLED
	var second_id: String = second.pickup_id
	loot.active_location = &"pyramid"
	loot._expire_dismissed_losses(deadline-.001)
	check(loot.pickups.has(second_id),"Gear remains present until its exact deadline even outside the active area")
	loot.host_enabled = false
	loot._expire_dismissed_losses(deadline)
	check(loot.pickups.has(second_id),"Only the host is permitted to execute timer expiry")
	loot.host_enabled = true
	loot._expire_dismissed_losses(deadline)
	check(not loot.pickups.has(second_id) and loot.markers.for_owner("A").is_empty() and second.is_queued_for_deletion(),"The authority expires a disabled pickup and removes its marker at the deadline")
	check(loot.pickups.size()==2,"Expiry preserves foreign death gear and ordinary world loot")
	await frames()
	# A snapshot restored after its absolute deadline must not resurrect gear.
	var expired := loaded.duplicate(true)
	expired.world_drops = [first_row.duplicate(true)]
	expired.world_drops[0].loss_expires_at = Time.get_unix_time_from_system()-1
	# The old identity has been recovered above: use a fresh world identity to
	# isolate expiry from the independent no-duplicate-ownership validation.
	expired.world_drops[0].item = Catalog.create(&"katana").to_dict()
	check(loot.restore_world(expired.world_drops) and loot.pickups.is_empty(),"An expired saved drop is skipped instead of resurrected on load")
	await frames()
	loot.active_location = &"overworld"
	a.actor.global_position = Vector3.ZERO
	var later := lose(a,&"spear",Vector3(1,0,0),"later")
	check(is_instance_valid(later) and not later.loss_dismissed and not loot.markers.for_owner("A")[0].get("dismissed",false),"A later death creates fresh visible guidance without inheriting an older dismissal")
	check(not paused,"Dismissal and timer expiry keep the world simulation running")
	scene.queue_free()
	await process_frame
	print("Lost gear expiry verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
