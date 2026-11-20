extends Node
## Local contextual services; money and item ownership stay in the authority.
const Economy = preload("res://scripts/civilian_economy.gd")
const Menu = preload("res://scripts/civilian_menu.gd")
const Resident = preload("res://scripts/resident_visual.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const Profiles = preload("res://scripts/resident_profiles.gd")
var world: Node3D
var establishments: Node3D
var economy: Node
var menu: CanvasLayer
var initial_state: Dictionary
var current: Dictionary = {}
var food_effect: Dictionary = {}
var _people: Array[Node3D] = []
var _clock := 0.0
@export var rest_duration := 5.0
@export var rest_healing := 60.0
@export var sleep_duration := 10.0
@export var sleep_healing := 180.0

func _ready() -> void:
	name="CivilianServices"
	establishments=world.wider_world.establishments
	economy=Economy.new()
	economy.player_inventory=world.player.inventory
	add_child(economy)
	var natural: Array = []
	# Resident bodies are built after the first physics frame. Use their stable
	# census now so checkpoint startup never saves a partial opening blessing.
	for profile: Dictionary in Profiles.all(world.population.resident_count): natural.append(String(profile.id))
	natural.append_array(["guild_receptionist","tavern_bartender","guild_adventurer","tavern_adventurer"])
	economy.configure(world.player.inventory.owner_id,natural)
	economy.bless_cycle(0,natural)
	economy.transfer(economy.resident_account("guild_receptionist"),economy.guild_account,100,"Opening guild capital")
	economy.transfer(economy.resident_account("tavern_bartender"),economy.tavern_account,100,"Opening tavern capital")
	initial_state=economy.serialize()
	economy.validator=_authorize
	economy.food_consumed.connect(_start_food)
	economy.changed.connect(world.inventory_session._dirty)
	world.loot.external_transaction_guard=economy.transaction_active
	economy.external_transaction_guard=func(): return world.loot.get("_busy")==true
	menu=Menu.new()
	menu.services=self
	add_child(menu)
	menu.opened.connect(world.inventory_session._opened)
	menu.closed.connect(world.inventory_session._closed)
	world.inventory_session.civilian_services=self
	_make_keeper("guild_receptionist","Guild Reception","Rooms & crystal exchange",establishments.receptionist_anchor,Color(.35,1,.8))
	_make_keeper("tavern_bartender","Tavern Keeper","Electron meals & drinks",establishments.bartender_anchor,Color(1,.45,.8))
	_make_adventurer("guild_adventurer",establishments.seats[0],Color(1,.7,.18),"The board is quiet today. Reception still buys monster crystals, if its treasury can cover them.")
	_make_adventurer("tavern_adventurer",establishments.seats[6],Color(.65,.4,1),"A meal, a seat, and a moment before the next journey. The keeper can sell you something for the road.")
	for entry: Dictionary in establishments.seats: world.world_actions.seats.append(entry)
	world.player.defeated.connect(func(): menu.close_menu(); food_effect.clear())
	world.player.respawned.connect(func(): food_effect.clear())

func _make_keeper(id: String, title: String, role: String, anchor: Node3D, tint: Color) -> void:
	var person:=Node3D.new()
	person.name=id
	person.set_meta("natural_resident_id",id)
	person.set_meta("role",role)
	establishments.add_child(person)
	person.global_position=anchor.global_position
	var visual:=Resident.new()
	visual.tint=tint
	person.add_child(visual)
	var caption:=Label3D.new()
	caption.text=title+"\n"+role
	caption.position.y=2.12
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size=24
	caption.pixel_size=.003
	caption.modulate=tint
	person.add_child(caption)
	_people.append(person)

func _make_adventurer(id: String, seat: Dictionary, tint: Color, greeting: String) -> void:
	# Seated residents keep their real seat while their persistent identity can
	# pursue lightweight background goals outside this visible interaction.
	var anchor:=Marker3D.new()
	establishments.add_child(anchor)
	anchor.global_position=seat.point-Vector3.UP*.946
	_make_keeper(id,"Resting Adventurer","",anchor,tint)
	var person: Node3D=_people[-1]
	person.rotation.y=atan2(seat.forward.x,seat.forward.z)
	person.get_child(0).sitting=true
	seat.occupant=person
	establishments.points.append({"id":StringName(id),"kind":&"adventurer","label":"Talk to adventurer","anchor":anchor,"greeting":greeting})

func _points() -> Array:
	var travel: Node=world.dungeon_travel
	if travel.is_rental():
		var content: Node=travel.room_contents.get(travel.active_location)
		return content.points if is_instance_valid(content) else []
	return establishments.points if travel.active_location==travel.OUTSIDE else []

func near(point: Dictionary) -> bool:
	var actor: Node3D=world.player
	var anchor: Node3D=point.get("anchor")
	if not is_instance_valid(anchor) or actor.get_world_3d()!=anchor.get_world_3d(): return false
	if actor.global_position.distance_to(anchor.global_position)>3.1: return false
	var target:=anchor.global_position
	target.y=maxf(target.y,actor.global_position.y+1.15)
	var ray:=PhysicsRayQueryParameters3D.create(actor.combat_point(),target,1,[actor.get_rid()])
	return actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func nearest() -> Dictionary:
	var actor: Node=world.player
	if not world.controls.gameplay_enabled or actor.transition_locked or actor.health<=0 or not actor.is_on_floor(): return {}
	if world.world_actions.attached() or actor.dodge.active or actor.weapon_combat.is_staggered() or not actor.weapon_combat.active_move.is_empty(): return {}
	var chosen: Dictionary={}
	var distance:=INF
	for point: Dictionary in _points():
		if point.kind in [&"room",&"exit",&"chair"]: continue
		if near(point):
			var d: float=actor.combat_point().distance_to(point.anchor.global_position)
			if d<distance: chosen=point; distance=d
	# Tables and computer terminals sit beside usable chairs. The closest
	# physical interaction wins, rather than a nearby service stealing a seat.
	var furniture: Dictionary=world.world_actions.nearest()
	if furniture.get("kind")=="seat" and actor.combat_point().distance_to(furniture.target.point)<distance: return {}
	return chosen

func interact() -> bool:
	current=nearest()
	if current.is_empty(): return false
	var society: Node=world.get("civilization")
	var id:=_speaker_id()
	if is_instance_valid(world.get("civic_interactions")) and (not id.is_empty() or current.kind=="board"):
		if world.civic_interactions.begin_service(current,id): return true
		if current.kind=="board": return false
	if is_instance_valid(society) and not id.is_empty(): society.record_interaction(id,"conversation","player")
	_home()
	return true

func _speaker_id() -> String:
	var legacy:=""
	match String(current.get("kind","")):
		"reception": legacy="guild_receptionist"
		"bartender": legacy="tavern_bartender"
		"adventurer": legacy=String(current.get("id",""))
	var society: Node=world.get("civilization")
	if legacy.is_empty() or not is_instance_valid(society) or not society.ready_for_simulation: return ""
	return String(society.registry.slots.get("service/"+legacy,""))

func _choice(text: String, call: Callable, enabled: bool = true) -> Dictionary:
	return {"text":text,"call":call,"enabled":enabled}

func _wallet() -> String:
	return "Your wallet: %d Glyph Coins" % economy.balance(economy.player_account)

func _home() -> void:
	if current.is_empty(): return
	var options: Array=[]
	var body:=_wallet()
	match String(current.kind):
		"reception":
			body+="\nWelcome to the Guild. A private room costs %d coins for %d minutes.\nGuild treasury: %d coins. Crystal purchases are limited by our funds." % [economy.rental_price,int(economy.rental_duration/60),economy.balance(economy.guild_account)]
			for index in range(3): options.append(_choice("Rent / renew room "+str(index+1)+"  |  "+str(economy.rental_price)+" coins",_rent.bind(index)))
			options.append(_choice("Sell monster crystals",_crystals))
		"board": body+="\nCONTRACT BOARD\nRegistration is open. No active contracts have been posted yet.\nBring monster crystals to reception for a treasury-funded sale."
		"adventurer": body+="\n"+String(current.greeting)
		"bartender":
			body+="\nElectron cuisine, prepared here. Tavern treasury: %d coins." % economy.balance(economy.tavern_account)
			options.append(_choice("Browse Electron meals, drinks and desserts",_food_catalog))
			options.append(_choice("Eat / drink from inventory",_food_list))
		"storage":
			body+="\nPrivate room storage. Equipment and stacks transfer between their actual owners.\nStored gear remains here after the room deconstructs or the rental expires."
			options.append(_choice("Deposit owned items",_storage_list.bind(true)))
			options.append(_choice("Withdraw stored items",_storage_list.bind(false)))
		"bed":
			body+="\nA quiet place to recover. Rest restores %.0f HP over %.0f seconds.\nSleep restores %.0f HP over %.0f seconds; world time continues normally." % [rest_healing,rest_duration,sleep_healing,sleep_duration]
			options.append(_choice("Rest on the bed",_rest.bind(false)))
			options.append(_choice("Sleep on the bed",_rest.bind(true)))
		"table":
			body+="\nA shared table for meals and conversation. Food placement is reserved for a later update."
			options.append(_choice("Eat / drink from inventory",_food_list))
	if not _speaker_id().is_empty(): options.append(_choice("Ask about their plans",_plans))
	menu.show_page(String(current.label).to_upper(),body,options)

func _plans() -> void:
	var society: Node=world.get("civilization")
	var id:=_speaker_id()
	if not is_instance_valid(society) or id.is_empty(): return
	var record: Dictionary=society.registry.records[id]
	var plans:="I'm taking time for "+String(record.current_goal).replace("_"," ")+"."
	if record.current_goal=="idle": plans="I'm deciding what to do next."
	if float(record.relationships.get("player",0))<-.2: plans="I remember our trouble. Keep your distance."
	var text:=String(record.name)+"\n\n"+plans
	if not String(record.guild).is_empty(): text+="\nI have ties with the Adventurers Guild."
	for memory: Dictionary in record.memories:
		if memory.type in ["work","meal","guild","social","combat"]: text+="\n"+String(memory.summary); break
	menu.show_page("CONVERSATION",text,[],_home)

func _rent(index: int) -> void:
	var ok: bool=economy.rent(index)
	_home()
	menu.set_status("Room %d rented. Use its upstairs door; access lasts %d minutes." % [index+1,int(economy.rental_duration/60)] if ok else "Rental unavailable. Check your wallet and existing room reservation.",not ok)

func _crystals() -> void:
	var options: Array=[]
	for item: Resource in world.player.inventory.items.values():
		var price: int=economy.crystal_price(item.item_type_id)
		if price>0:
			options.append(_choice("Sell one "+Catalog.get_definition(item.item_type_id).display_name+"  |  "+str(price)+" coins  (owned "+str(item.quantity)+")",_sell.bind(item.instance_id)))
	menu.show_page("GUILD CRYSTAL EXCHANGE",_wallet()+"\nGuild treasury: "+str(economy.balance(economy.guild_account))+" coins.",options,_home)

func _sell(iid: String) -> void:
	var ok: bool=economy.sell_crystal(iid,1,world.player.inventory)
	_crystals()
	menu.set_status("Crystal sold. Payment transferred from the Guild." if ok else "Sale unavailable: the Guild may not have enough coins.",not ok)

func _buy(id: StringName) -> void:
	var ok: bool=economy.buy_food(id,world.player.inventory)
	_food_catalog()
	menu.set_status("Added to your inventory. Eat here or use it later." if ok else "Purchase unavailable. Check your wallet and inventory space.",not ok)

func _food_catalog() -> void:
	var options: Array=[]
	for id: StringName in Catalog.food_ids():
		var offer: Dictionary=economy.food_offer(id)
		if offer.is_empty(): continue
		var effect:="%.0f shield" % offer.shield_restore if offer.shield_restore>0 else "%.0f HP" % offer.hp_restore
		options.append(_choice(Catalog.get_definition(id).display_name+"  |  "+str(offer.price)+" coins  |  "+effect,_buy.bind(id)))
	menu.show_page("ELECTRON CUISINE",_wallet()+"\nMeals and desserts restore HP. Drinks replenish shields. Quality, rarity and recipe complexity improve recovery.",options,_home)

func _food_list() -> void:
	var options: Array=[]
	for item: Resource in world.player.inventory.items.values():
		if not economy.food_offer(item.item_type_id).is_empty():
			options.append(_choice("Consume "+Catalog.get_definition(item.item_type_id).display_name+"  (owned "+str(item.quantity)+")",_eat.bind(item.instance_id)))
	menu.show_page("ELECTRON MEALS & DRINKS",_wallet()+"\nRecovery takes time. Another meal can be started after the current one finishes.",options,_home)

func _eat(iid: String) -> void:
	var ok: bool=consume_food(iid)
	_food_list()
	menu.set_status("Enjoy your meal. Recovery has begun." if ok else "Cannot consume that now.",not ok)

func consume_food(iid: String) -> bool: return economy.consume_food(iid,world.player.inventory)

func _storage_list(deposit: bool) -> void:
	var index: int=world.dungeon_travel.room_number()
	if index<0: menu.close_menu(); return
	var inventory: Node=world.player.inventory if deposit else economy.room_stores[index]
	var options: Array=[]
	for item: Resource in inventory.items.values():
		var definition: Resource=Catalog.get_definition(item.item_type_id)
		if not definition.is_droppable or not definition.is_tradeable: continue
		options.append(_choice(("Store " if deposit else "Take ")+definition.display_name+"  x"+str(item.quantity),_store.bind(item.instance_id,item.quantity,deposit)))
	menu.show_page("DEPOSIT ITEMS" if deposit else "WITHDRAW ITEMS","Room %d storage only. Select a stack to move it in full; unique gear keeps its identity." % (index+1),options,_home)

func _store(iid: String, amount: int, deposit: bool) -> void:
	var ok: bool=economy.transfer_storage(world.dungeon_travel.room_number(),iid,amount,deposit,world.player.inventory)
	_storage_list(deposit)
	menu.set_status("Items transferred." if ok else "Transfer unavailable. Nothing was moved.",not ok)

func _authorize(operation: StringName, payload: Dictionary) -> bool:
	if operation==&"intent_trade":
		return is_instance_valid(world.get("civic_interactions")) and world.civic_interactions.trade.authorized(payload)
	if operation==&"deliver_item":
		return is_instance_valid(world.get("civic_interactions")) and world.civic_interactions.delivery_authorized(payload)
	var actor: Node=world.player
	if not world.loot.host_enabled or world.loot.get("_busy")==true or world.inventory_session.networked() or actor.health<=0 or actor.transition_locked: return false
	if operation==&"consume_food":
		return food_effect.is_empty() and not actor.dodge.active and actor.weapon_combat.active_move.is_empty() and not actor.weapon_combat.is_staggered() and economy.can_consume_food(String(payload.get("instance_id","")),world.player.inventory)
	if not menu.is_open or not near(current): return false
	if operation in [&"rent",&"sell_crystal"]: return current.kind==&"reception"
	if operation==&"buy_food": return current.kind==&"bartender"
	if operation==&"storage": return current.kind==&"storage" and world.dungeon_travel.is_rental() and int(payload.get("room",-1))==world.dungeon_travel.room_number()
	return false

func _start_food(inventory: Node, effects: Dictionary) -> void:
	var duration:=float(effects.duration)
	food_effect={"remaining":duration,"hp_rate":float(effects.hp_restore)/duration,"shield_rate":float(effects.shield_restore)/duration}
	if effects.shield_restore>0:
		var shields=preload("res://scripts/shield_glyphs.gd")
		if float(effects.shield_capacity)>shields.capacity(inventory.shield_state):
			inventory.shield_state={"tier":String(effects.shield_tier),"points":float(inventory.shield_state.get("points",0))}

func _rest(sleeping: bool) -> void:
	if not menu.is_open or current.get("kind")!=&"bed" or world.player.health<=0 or world.player.transition_locked: return
	if not economy.can_enter(world.dungeon_travel.room_number()) or not near(current) or not food_effect.is_empty(): return
	var content: Node=world.dungeon_travel.room_contents.get(world.dungeon_travel.active_location)
	if not is_instance_valid(content): return
	menu.close_menu()
	world.world_actions.seat={"point":content.to_global(Vector3(-5.3,1.03,-3.6)),"forward":content.global_basis.z,"occupant":world.player,"world":content.get_world_3d(),"bed":true}
	world.world_actions.begin_attachment()
	world.player.visual.rotation.y=atan2(content.global_basis.z.x,content.global_basis.z.z)
	world.world_actions.anchor()
	var duration:=maxf(.1,sleep_duration if sleeping else rest_duration)
	food_effect={"remaining":duration,"rate":maxf(0,sleep_healing if sleeping else rest_healing)/duration,"rest":true}
	world.inventory_session.show_notice("Sleeping. Move, jump or interact to get up." if sleeping else "Resting. Move, jump or interact to get up.")

func _process(delta: float) -> void:
	if not food_effect.is_empty():
		if world.player.health<=0 or world.player.transition_locked or (food_effect.get("rest",false) and (not world.world_actions.attached() or not world.world_actions.seat.get("bed",false))): food_effect.clear()
		else:
			var step:=minf(delta,float(food_effect.remaining))
			var combat: Node=world.player.weapon_combat
			combat.health=minf(combat.max_health,combat.health+step*float(food_effect.get("hp_rate",food_effect.get("rate",0))))
			var shield_rate:=float(food_effect.get("shield_rate",0))
			if shield_rate>0:
				var inventory: Node=world.player.inventory
				var capacity: float=preload("res://scripts/shield_glyphs.gd").capacity(inventory.shield_state)
				inventory.shield_state.points=minf(capacity,float(inventory.shield_state.get("points",0))+step*shield_rate)
			food_effect.remaining-=step
			combat.changed.emit()
			if food_effect.remaining<=0:
				food_effect.clear()
				if shield_rate>0: world.player.inventory.changed.emit()
	_clock-=delta
	if _clock>0: return
	_clock=.1
	if menu.is_open and (world.player.health<=0 or world.player.transition_locked or not near(current)): menu.close_menu()
	for person: Node3D in _people:
		person.visible=world.dungeon_travel.active_location==world.dungeon_travel.OUTSIDE and person.global_position.distance_to(world.player.global_position)<70
		if person.visible: person.get_child(0).animate(.1,0,menu.is_open)

func reset_state() -> bool:
	var before: Dictionary=economy.serialize()
	if not economy.restore(initial_state): return false
	var society: Node=world.get("civilization")
	if is_instance_valid(society) and not society.restore(null):
		economy.restore(before)
		return false
	if is_instance_valid(world.get("civic_interactions")):
		world.quest_system.restore(null)
		world.communication.restore(null)
		world.law.restore(null)
		world.civic_interactions.bootstrap()
	return true
