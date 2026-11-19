extends Node3D
## Synchronous ownership transactions behind one host-validation boundary.
const Pickup = preload("res://scripts/item_pickup.gd")
const Instance = preload("res://scripts/item_instance.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Markers = preload("res://scripts/lost_item_markers.gd")
const Shields = preload("res://scripts/shield_glyphs.gd")
signal changed
signal picked_up(inventory: Node, item: Resource)
signal dropped(inventory: Node, item: Resource, pickup: Node3D)
@export var host_enabled := true
@export_range(0,1,0.01) var death_drop_probability := 0.15
@export_range(1,3600,1) var dismissed_loss_lifetime := 300.0
@export var pickup_radius := 2.6
@export var session_id := "singleplayer"
var validator: Callable
var spawn_factory: Callable
var pickups: Dictionary = {}
var markers := Markers.new()
var rng := RandomNumberGenerator.new()
var _inventories: Dictionary = {}
var _death_results: Dictionary = {}
var _shops: Dictionary = {}
var _busy := false
var _loss_timers: Dictionary = {}
var _loss_timer_clock := 0.0
var location_roots: Dictionary = {}
var respawn_glyphs: Node
var active_location: StringName = &"overworld"
var external_transaction_guard: Callable

func location_for(actor: Node3D) -> StringName:
	for id: StringName in location_roots:
		if location_roots[id].get_world_3d()==actor.get_world_3d(): return id
	return &"overworld"

func _space(location: StringName = &"") -> PhysicsDirectSpaceState3D:
	var id:=active_location if location==&"" else location
	if location_roots.has(id): return location_roots[id].get_world_3d().direct_space_state
	return get_world_3d().direct_space_state

func transaction_active() -> bool:
	return _busy or (external_transaction_guard.is_valid() and bool(external_transaction_guard.call()))

func _ready() -> void:
	name = "LootAuthority"
	rng.randomize()
	add_to_group("loot_authorities")
	markers.name = "LostItemMarkers"
	add_child(markers)
	call_deferred("_adopt_editor_pickups")

func _process(delta: float) -> void:
	if not host_enabled or _busy or _loss_timers.is_empty(): return
	_loss_timer_clock += delta
	if _loss_timer_clock<1.0: return
	_loss_timer_clock = 0.0
	_expire_dismissed_losses(Time.get_unix_time_from_system())

func _expire_dismissed_losses(now: float) -> void:
	if not host_enabled or _busy: return
	var expired := false
	for key: String in _loss_timers.keys():
		var pickup: Node3D = _loss_timers[key]
		if not is_instance_valid(pickup) or pickups.get(key)!=pickup:
			_loss_timers.erase(key)
			continue
		if pickup.loss_expires_at>now: continue
		_loss_timers.erase(key)
		pickups.erase(key)
		markers.remove(key)
		pickup.queue_free()
		expired = true
	if expired: changed.emit()

func request_dismiss_lost_gear(inventory: Node) -> bool:
	if not _authorized(&"dismiss_lost_gear",inventory,{}): return false
	var deadline := Time.get_unix_time_from_system()+clampf(dismissed_loss_lifetime,1,3600)
	var dismissed := false
	_busy = true
	for pickup: Node3D in pickups.values():
		if not is_instance_valid(pickup) or pickup.claimed or pickup.pending or pickup.is_queued_for_deletion(): continue
		if pickup.death_owner_id!=inventory.owner_id or pickup.loss_dismissed: continue
		pickup.dismiss_loss(deadline)
		_loss_timers[pickup.pickup_id] = pickup
		markers.dismiss(pickup)
		dismissed = true
	_busy = false
	if dismissed: changed.emit()
	return dismissed

func register_inventory(inventory: Node) -> bool:
	if not is_instance_valid(inventory) or not Instance.valid_text(inventory.owner_id): return false
	var key: String = inventory.owner_id
	var old: Node = _inventories[key].get_ref() if _inventories.has(key) else null
	if is_instance_valid(old) and old != inventory: return false
	_inventories[key] = weakref(inventory)
	return true

func actor_for(inventory: Node) -> Node3D:
	if not is_instance_valid(inventory): return null
	var actor = inventory.get("actor")
	if actor is Node3D and is_instance_valid(actor): return actor
	return inventory.get_parent() as Node3D

func _authorized(operation: StringName, inventory: Node, payload: Dictionary) -> bool:
	if not host_enabled or transaction_active() or not register_inventory(inventory): return false
	if not is_instance_valid(actor_for(inventory)): return false
	if actor_for(inventory).get("transition_locked")==true: return false
	return not validator.is_valid() or bool(validator.call(operation,inventory,payload))

func _transferable(item: Resource) -> bool:
	if item == null: return false
	var definition = Catalog.get_definition(item.item_type_id)
	return definition != null and definition.is_droppable and definition.is_tradeable

func _equipment_allowed(inventory: Node) -> bool:
	var actor := actor_for(inventory)
	if not is_instance_valid(actor): return false
	var combat = actor.get("weapon_combat")
	return not is_instance_valid(combat) or not combat.has_method("can_act") or bool(combat.can_act())

func request_pickup(inventory: Node, pickup: Node3D) -> bool:
	if not is_instance_valid(pickup): return false
	if not _authorized(&"pickup",inventory,{"pickup_id":pickup.get("pickup_id")}): return false
	var key: String = pickup.pickup_id
	if pickups.get(key) != pickup or pickup.claimed or pickup.pending or pickup.is_queued_for_deletion(): return false
	if pickup.loss_dismissed and pickup.loss_expires_at<=Time.get_unix_time_from_system():
		_expire_dismissed_losses(Time.get_unix_time_from_system())
		return false
	var item: Resource = pickup.item_instance
	if item == null or not str(item.owner_id).is_empty() or _held(item.instance_id): return false
	var actor := actor_for(inventory)
	if actor.global_position.distance_to(pickup.global_position)>pickup_radius or not line_of_sight(actor,pickup): return false
	# Claim before add_item emits any inventory signals: reentrant pickup/drop
	# requests cannot transfer the same instance twice during those callbacks.
	pickup.claimed = true
	_busy = true
	var notification: Resource = item.duplicate(true)
	var accepted: bool = inventory.add_item(item)
	_busy = false
	if not accepted:
		pickup.claimed = false
		return false
	notification.owner_id = inventory.owner_id
	pickups.erase(key)
	_loss_timers.erase(key)
	markers.remove(key)
	pickup.queue_free()
	picked_up.emit(inventory,notification)
	changed.emit()
	return true

func request_drop(inventory: Node, instance_id: String, quantity: int, at: Vector3) -> bool:
	if not _authorized(&"drop",inventory,{"instance_id":instance_id,"quantity":quantity,"position":at}): return false
	if inventory.equipment.values().has(instance_id) and not _equipment_allowed(inventory): return false
	var actor := actor_for(inventory)
	if not finite_point(at) or actor.global_position.distance_to(at)>3.0: return false
	return _drop(inventory,instance_id,quantity,at,"") != null

func request_equip(inventory: Node, slot: StringName, instance_id: String) -> bool:
	if not _authorized(&"equip",inventory,{"slot":slot,"instance_id":instance_id}): return false
	if not _equipment_allowed(inventory): return false
	var phase: Node = actor_for(inventory).get("dodge")
	if slot==&"body" and is_instance_valid(phase) and phase.active: return false
	_busy = true
	var accepted: bool = inventory.assign(slot,instance_id)
	_busy = false
	return accepted

func request_health_glyph(inventory: Node) -> bool:
	if not _authorized(&"health_glyph",inventory,{}): return false
	var actor := actor_for(inventory)
	var combat: Node = actor.get("weapon_combat")
	if not is_instance_valid(combat) or combat.health<=0 or combat.health>=combat.max_health: return false
	var selected: Resource
	for item: Resource in inventory.items.values():
		if item.item_type_id==&"health_glyph" and item.owner_id==inventory.owner_id and item.is_valid():
			selected = item
			break
	if selected==null: return false
	_busy = true # Inventory signals cannot reenter this transaction.
	var consumed: Resource = inventory.take_item(selected.instance_id,1)
	if consumed!=null:
		combat.health = minf(combat.max_health,combat.health+350)
		consumed.quantity = 0
		combat.changed.emit()
	_busy = false
	if consumed!=null: changed.emit()
	return consumed!=null

func request_respawn_glyph(inventory: Node, instance_id: String) -> bool:
	if not _authorized(&"respawn_glyph",inventory,{"instance_id":instance_id}) or not is_instance_valid(respawn_glyphs): return false
	if actor_for(inventory)!=respawn_glyphs.actor: return false
	var item: Resource=inventory.get_item(instance_id)
	if item==null or not item.is_valid() or item.owner_id!=inventory.owner_id: return false
	var types: Dictionary=respawn_glyphs.Data.TYPES
	if not types.has(item.item_type_id): return false
	var record: Dictionary=respawn_glyphs.placement(item.item_type_id)
	if record.is_empty(): return false
	_busy=true
	var kind: String=types[item.item_type_id]
	var consumed: Resource=inventory.take_item(instance_id,1)
	if consumed!=null:
		inventory.respawn_points[kind]=record
		consumed.quantity=0
		inventory.changed.emit()
	_busy=false
	if consumed!=null: changed.emit()
	return consumed!=null

func request_shield_glyph(inventory: Node, instance_id: String = "") -> bool:
	# Quick use selects on the authority, before the same ownership transaction
	# used by Inventory. A full stronger shield never wastes a lesser glyph.
	if instance_id.is_empty():
		var preferred := Shields.preferred_item(inventory)
		if preferred==null: return false
		instance_id=preferred.instance_id
	if not _authorized(&"shield_glyph",inventory,{"instance_id":instance_id}): return false
	var actor:=actor_for(inventory)
	if not is_instance_valid(actor) or actor.health<=0 or actor.get("transition_locked")==true: return false
	var item: Resource=inventory.get_item(instance_id)
	if item==null or not item.is_valid() or item.owner_id!=inventory.owner_id or item.item_type_id not in Shields.ITEMS: return false
	var tier: String=Shields.ITEMS[item.item_type_id]
	if float(inventory.shield_state.get("points",0))>=Shields.TIERS[tier]: return false
	_busy=true
	var consumed: Resource=inventory.take_item(instance_id,1)
	if consumed!=null:
		inventory.shield_state={"tier":tier,"points":Shields.TIERS[tier]}
		consumed.quantity=0
		inventory.changed.emit()
		actor.weapon_combat.changed.emit()
	_busy=false
	if consumed!=null: changed.emit()
	return consumed!=null

func register_shop(id: StringName, shop: Node) -> void:
	# World-authored offers, never client-supplied items or prices.
	_shops[id] = weakref(shop)

func request_shop_purchase(inventory: Node, shop_id: StringName, item_type_id: StringName) -> bool:
	if not _authorized(&"shop_purchase",inventory,{"shop_id":shop_id,"item_type_id":item_type_id}): return false
	var shop: Node = _shops[shop_id].get_ref() if _shops.has(shop_id) else null
	if not is_instance_valid(shop) or not shop.can_use(actor_for(inventory)): return false
	var offer: Dictionary = shop.offer(item_type_id)
	# Paid transactions need a future authoritative currency settlement. A
	# nonzero authored price must never accidentally issue a free item.
	if offer.is_empty() or offer.price!=0: return false
	_busy = true
	var accepted: bool = inventory.add_item(Catalog.create(item_type_id,1))
	if accepted: changed.emit()
	_busy = false
	return accepted

func request_unequip(inventory: Node, slot: StringName) -> bool:
	if not _authorized(&"unequip",inventory,{"slot":slot}): return false
	if not _equipment_allowed(inventory): return false
	_busy = true
	var accepted: bool = inventory.unequip(slot)
	_busy = false
	return accepted

func _drop(inventory: Node, instance_id: String, quantity: int, at: Vector3, death_owner: String) -> Node3D:
	var item: Resource = inventory.get_item(instance_id)
	if item == null or item.owner_id != inventory.owner_id or quantity<=0 or quantity>item.quantity or not _transferable(item): return null
	if _world_has(instance_id): return null
	var location:=location_for(actor_for(inventory))
	var floor := supported_position(at,location)
	if floor.is_empty() or not clear_volume(floor.point,location): return null
	if death_owner.is_empty() and actor_for(inventory).global_position.distance_to(floor.point)>3.0: return null
	var preview: Resource = item.duplicate(true)
	preview.quantity = quantity
	preview.owner_id = ""
	var pickup := _prepare(preview,floor.point,death_owner,Pickup.new_id(),location)
	if pickup == null: return null
	if death_owner.is_empty() and not line_of_sight(actor_for(inventory),pickup):
		pickup.queue_free()
		return null
	# Nothing has left the inventory until a real scene-tree node exists. A
	# failed factory, unsupported position or invalid spawn cannot eat gear.
	_busy = true
	var transferred: Resource = inventory.take_item(instance_id,quantity)
	_busy = false
	if transferred == null:
		pickup.queue_free()
		return null
	pickup.item_instance = transferred
	transferred.owner_id = ""
	pickup.activate()
	_record(pickup)
	dropped.emit(inventory,transferred,pickup)
	changed.emit()
	return pickup

func resolve_death(inventory: Node, death_token: String, at: Vector3) -> Dictionary:
	if death_token.is_empty() or not finite_point(at) or not _authorized(&"death",inventory,{"death_token":death_token,"position":at}): return {}
	var key: String = inventory.owner_id+"::"+death_token
	if _death_results.has(key): return (_death_results[key] as Dictionary).duplicate(true)
	var result := {"processed":true,"dropped":false,"pickup_id":"","item_instance_id":""}
	_death_results[key] = result
	var pool: Array[String] = []
	for id in inventory.eligible_equipped():
		var instance_id := str(id)
		var item: Resource = inventory.get_item(instance_id)
		if not pool.has(instance_id) and item != null and item.owner_id == inventory.owner_id and _transferable(item): pool.append(instance_id)
	var probability := clampf(death_drop_probability,0,1)
	if pool.is_empty() or probability<=0 or rng.randf()>probability: return result.duplicate(true)
	var chosen: String = pool[rng.randi_range(0,pool.size()-1)]
	var pickup := _drop(inventory,chosen,1,at,inventory.owner_id)
	if pickup != null:
		result.dropped = true
		result.pickup_id = pickup.pickup_id
		result.item_instance_id = pickup.item_instance.instance_id
	_death_results[key] = result
	return result.duplicate(true)

func nearest_pickup(actor: Node3D, max_distance: float = 2.8) -> Node3D:
	if not is_instance_valid(actor): return null
	var nearest: Node3D
	var distance := minf(max_distance,pickup_radius)
	for pickup: Node3D in pickups.values():
		if not is_instance_valid(pickup) or pickup.claimed or pickup.pending or pickup.is_queued_for_deletion(): continue
		var next := actor.global_position.distance_to(pickup.global_position)
		if next<=distance and line_of_sight(actor,pickup):
			nearest = pickup
			distance = next
	return nearest

func spawn_reward(item_type_id: StringName, at: Vector3, location: StringName = &"") -> Node3D:
	# Trusted host-authored encounter reward, never a client purchase/transfer.
	# A fresh identity leaves the NPC's original equipped item untouched.
	if not host_enabled or _busy or not finite_point(at): return null
	if location==&"": location=active_location
	if not location_roots.is_empty() and not location_roots.has(location): return null
	var item: Resource = Catalog.create(item_type_id)
	if item==null or not _transferable(item): return null
	for radius in range(4):
		for index in range(1 if radius==0 else 8):
			var angle := index*TAU/8
			var floor := supported_position(at+Vector3(cos(angle),0,sin(angle))*radius,location)
			if floor.is_empty() or not clear_volume(floor.point,location): continue
			_busy=true
			var pickup := _prepare(item,floor.point,"",Pickup.new_id(),location)
			if pickup!=null:
				pickup.activate()
				_record(pickup)
			_busy=false
			if pickup!=null: changed.emit()
			return pickup
	return null

func spawn_reward_bundle(types: Array, at: Vector3, location: StringName) -> Array:
	# Boss keepsakes commit together. A failed factory/support check leaves no
	# registered drops or claimed first-clear entitlement behind.
	if not host_enabled or _busy or not finite_point(at) or types.is_empty() or types.size()>12: return []
	if not location_roots.is_empty() and not location_roots.has(location): return []
	var prepared: Array=[]
	_busy=true
	for i in range(types.size()):
		var item: Resource=Catalog.create(StringName(types[i]))
		var angle:=i*TAU/types.size()
		var ground:=supported_position(at+Vector3(cos(angle),0,sin(angle))*2.2,location)
		var copy: Node3D
		if item!=null and _transferable(item) and not ground.is_empty() and clear_volume(ground.point,location): copy=_prepare(item,ground.point,"",Pickup.new_id(),location)
		if copy==null:
			for candidate: Node3D in prepared: candidate.queue_free()
			_busy=false
			return []
		prepared.append(copy)
	for pickup: Node3D in prepared:
		pickup.activate()
		_record(pickup)
	_busy=false
	changed.emit()
	return prepared

func line_of_sight(actor: Node3D, pickup: Node3D) -> bool:
	if not is_inside_tree() or not actor.is_inside_tree(): return false
	if actor.get_world_3d()!=pickup.get_world_3d(): return false
	var excluded: Array[RID] = []
	if actor is CollisionObject3D: excluded.append(actor.get_rid())
	if is_instance_valid(pickup.solid): excluded.append(pickup.solid.get_rid())
	var from: Vector3 = actor.combat_point() if actor.has_method("combat_point") else actor.global_position+Vector3.UP*0.9
	var query := PhysicsRayQueryParameters3D.create(from,pickup.global_position+Vector3.UP*0.45,1,excluded)
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func supported_position(at: Vector3, location: StringName = &"") -> Dictionary:
	if not is_inside_tree() or not finite_point(at): return {}
	var excluded := solid_exclusions()
	var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.35,at-Vector3.UP*512,1,excluded)
	var hit := _space(location).intersect_ray(query)
	if hit.is_empty() or hit.normal.y<0.65: return {}
	return {"point":hit.position}

func solid_exclusions() -> Array[RID]:
	var excluded: Array[RID] = []
	for pickup: Node3D in pickups.values():
		if is_instance_valid(pickup) and is_instance_valid(pickup.solid): excluded.append(pickup.solid.get_rid())
	for ref: WeakRef in _inventories.values():
		var actor := actor_for(ref.get_ref())
		if actor is CollisionObject3D: excluded.append(actor.get_rid())
	return excluded

func clear_volume(point: Vector3, location: StringName = &"") -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.46,0.78,0.46)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point+Vector3.UP*0.41
	query.collision_mask = 1
	query.exclude = solid_exclusions()
	return _space(location).intersect_shape(query,1).is_empty()

func register_pickup(pickup: Node3D) -> bool:
	if not host_enabled or _busy or not is_instance_valid(pickup) or pickup.item_instance == null: return false
	var item: Resource = pickup.item_instance
	if item.owner_id != "" or _held(item.instance_id) or _world_has(item.instance_id) or pickups.has(pickup.pickup_id): return false
	if Instance.from_dict(item.to_dict()) == null: return false
	_record(pickup)
	changed.emit()
	return true

func _record(pickup: Node3D) -> void:
	pickups[pickup.pickup_id] = pickup
	if pickup.loss_dismissed: _loss_timers[pickup.pickup_id] = pickup
	pickup.tree_exited.connect(_pickup_exited.bind(pickup.pickup_id,pickup.get_instance_id()),CONNECT_ONE_SHOT)
	if not pickup.death_owner_id.is_empty(): markers.track(pickup,pickup.death_owner_id,pickup.item_instance.instance_id)

func _pickup_exited(pickup_id: String, source_id: int) -> void:
	var current: Node3D = pickups.get(pickup_id)
	if is_instance_valid(current) and current.get_instance_id() != source_id: return
	if pickups.has(pickup_id):
		pickups.erase(pickup_id)
		_loss_timers.erase(pickup_id)
		markers.remove(pickup_id)
		changed.emit()

func _adopt_editor_pickups() -> void:
	for pickup: Node3D in get_tree().get_nodes_in_group("item_pickups"):
		if not pickups.has(pickup.pickup_id): register_pickup(pickup)

func _prepare(item: Resource, point: Vector3, death_owner: String, pickup_id: String, location: StringName = &"overworld") -> Node3D:
	var candidate = spawn_factory.call() if spawn_factory.is_valid() else Pickup.new()
	if not candidate is Pickup:
		if candidate is Node: candidate.queue_free()
		return null
	candidate.item_instance = item
	candidate.pickup_id = pickup_id
	candidate.death_owner_id = death_owner
	candidate.location_id = location
	candidate.pending = true
	if location!=&"overworld" and location_roots.has(location):
		var root: Node3D=location_roots[location]
		var parent: Node3D=root.pickup_parent_for(point) if root.has_method("pickup_parent_for") else root
		parent.add_child(candidate)
	else: add_child(candidate)
	candidate.global_position = point
	if not is_instance_valid(candidate) or not candidate.is_inside_tree() or candidate.is_queued_for_deletion():
		if is_instance_valid(candidate): candidate.queue_free()
		return null
	return candidate

func _held(instance_id: String) -> bool:
	for ref: WeakRef in _inventories.values():
		var inventory: Node = ref.get_ref()
		if is_instance_valid(inventory) and inventory.items.has(instance_id): return true
	return false

func _world_has(instance_id: String) -> bool:
	for pickup: Node3D in pickups.values():
		if is_instance_valid(pickup) and not pickup.claimed and pickup.item_instance != null and pickup.item_instance.instance_id == instance_id: return true
	return false

static func finite_point(point: Vector3) -> bool:
	return point.is_finite() and maxf(absf(point.x),maxf(absf(point.y),absf(point.z)))<=1000000

func validate_snapshot(snapshot: Array) -> bool:
	var pickup_ids: Dictionary = {}
	var instance_ids: Dictionary = {}
	for row in snapshot:
		if not row is Dictionary or not row.get("pickup_id") is String or row.pickup_id.is_empty() or pickup_ids.has(row.pickup_id): return false
		if not row.get("item") is Dictionary or not row.get("death_owner_id","") is String: return false
		if Pickup.loss_timer_from_row(row).is_empty(): return false
		if not row.get("position") is Array or row.position.size()!=3: return false
		if not Instance.valid_text(row.get("location_id","overworld")): return false
		var location:=StringName(row.get("location_id","overworld"))
		if location!=&"overworld" and not location_roots.has(location): return false
		for coordinate in row.position:
			if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)): return false
		var point := Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
		if not finite_point(point): return false
		var item: Resource = Instance.from_dict(row.item)
		if item == null or item.owner_id != "" or _held(item.instance_id) or instance_ids.has(item.instance_id): return false
		pickup_ids[row.pickup_id] = true
		instance_ids[item.instance_id] = true
	return true

func serialize_world() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pickup: Node3D in pickups.values():
		if not is_instance_valid(pickup) or pickup.claimed or pickup.pending or pickup.is_queued_for_deletion(): continue
		var point := pickup.global_position
		var row: Dictionary={"pickup_id":pickup.pickup_id,"item":pickup.item_instance.to_dict(),"position":[point.x,point.y,point.z],"death_owner_id":pickup.death_owner_id}
		if pickup.location_id!=&"overworld": row.location_id=String(pickup.location_id)
		if pickup.loss_dismissed:
			row.loss_dismissed = true
			row.loss_expires_at = pickup.loss_expires_at
		result.append(row)
	return result

func restore_world(snapshot: Array) -> bool:
	if not host_enabled or _busy or not validate_snapshot(snapshot): return false
	var candidates: Array[Node3D] = []
	for row: Dictionary in snapshot:
		var timer := Pickup.loss_timer_from_row(row)
		if timer.dismissed and timer.expires_at<=Time.get_unix_time_from_system(): continue
		var point := Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
		var location:=StringName(row.get("location_id","overworld"))
		var floor := supported_position(point,location)
		if floor.is_empty() or absf(floor.point.y-point.y)>0.4 or not clear_volume(point,location):
			for pending in candidates: pending.queue_free()
			return false
		var candidate := _prepare(Instance.from_dict(row.item),point,row.get("death_owner_id",""),row.pickup_id,location)
		if candidate == null:
			for pending in candidates: pending.queue_free()
			return false
		if timer.dismissed: candidate.dismiss_loss(timer.expires_at)
		candidates.append(candidate)
	var previous: Array = pickups.values()
	_busy = true
	pickups.clear()
	_loss_timers.clear()
	markers.clear()
	for candidate in candidates:
		candidate.activate()
		_record(candidate)
	for old: Node3D in previous: old.queue_free()
	_busy = false
	changed.emit()
	return true
