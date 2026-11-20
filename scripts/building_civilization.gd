extends Node3D
## Sparse occupancy and renovation authority; streamed geometry is a view.
const Model=preload("res://scripts/building_registry.gd")
const Inventory=preload("res://scripts/inventory.gd")
const Item=preload("res://scripts/item_instance.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Menu=preload("res://scripts/civilian_menu.gd")
const Regions=preload("res://scripts/world_regions.gd")
var world: Node3D
var model:=Model.new()
var descriptors: Dictionary={}
var menu: CanvasLayer
var current:=""
var ready_for_use:=false
var _busy:=false
var _clock:=0.0
var _rendered: Dictionary={}
var _render_revision: Dictionary={}
var _placement: Dictionary={}
var _npc_cursor:=0
var _guild_premises_ready:=false
var _guild_signs: Dictionary={}
var _cells: Dictionary={}
var _homes: Dictionary={}
var _local_shells: Dictionary={}
var _descriptor_order: Dictionary={}
var inspected_shells:=0
signal changed

func _ready() -> void:
	name="BuildingCivilization"
	menu=Menu.new(); add_child(menu)
	menu.opened.connect(world.inventory_session._opened)
	menu.closed.connect(world.inventory_session._closed)
	changed.connect(world.inventory_session._dirty)
	call_deferred("_register")

func _register() -> void:
	while is_inside_tree() and (not world.civilization.ready_for_simulation or not world.wider_world.has_method("building_records")): await get_tree().physics_frame
	if not is_inside_tree(): return
	for descriptor: Dictionary in world.wider_world.building_records():
		if model.register(descriptor):
			_descriptor_order[descriptor.id]=descriptors.size()
			descriptors[descriptor.id]=descriptor
			var cell:=Vector2i(floori(descriptor.point.x/128),floori(descriptor.point.z/128))
			if not _cells.has(cell): _cells[cell]=[]
			_cells[cell].append(String(descriptor.id))
	ready_for_use=true

func transaction_active() -> bool: return _busy

func local_candidates() -> Array[String]:
	var result: Array[String]=[]
	var point: Vector3=world.player.global_position
	var cell:=Vector2i(floori(point.x/128),floori(point.z/128))
	for x in range(-1,2):
		for z in range(-1,2): result.append_array(_cells.get(cell+Vector2i(x,z),[]))
	# Preserve manifest tie breaking if building footprints overlap.
	result.sort_custom(func(a: String,b: String): return int(_descriptor_order[a])<int(_descriptor_order[b]))
	return result
func _now() -> float: return float(world.civilization.world_seconds)
func _actor() -> String: return "player"
func _allowed() -> bool:
	return ready_for_use and not _busy and not world.inventory_session.networked() and world.player.health>0 and not world.player.transition_locked and world.dungeon_travel.active_location==world.dungeon_travel.OUTSIDE

func nearest() -> String:
	if not _allowed(): return ""
	var point: Vector3=world.player.global_position
	for id: String in local_candidates():
		var row: Dictionary=model.records[id]
		if row.manual_review: continue
		var base:=Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
		var delta: Vector3=point-base
		if absf(delta.x)<float(row.size[0])*.5-.3 and absf(delta.z)<float(row.size[2])*.5-.3 and delta.y>=-.2 and delta.y<float(row.size[1]): return id
	return ""

func _near(id: String) -> bool: return nearest()==id
func interact() -> bool:
	current=nearest()
	if current.is_empty(): return false
	world.inventory_session._close_communication("building")
	_home(); return true

func _choice(text: String,action: Callable,enabled: bool=true) -> Dictionary: return {"text":text,"call":action,"enabled":enabled}
func _home() -> void:
	if not _near(current): menu.close_menu(); return
	var row: Dictionary=model.records[current]
	var options: Array=[]
	if String(row.owner).begins_with("guild/") or String(row.owner).begins_with("faction/"):
		options.append(_choice("Guild membership and contracts",_guild_terminal))
	if row.owner.is_empty(): options.append(_choice("Occupy this vacant shell",_claim))
	elif model.allowed(current,"player"):
		options.append(_choice("Install owned furniture or equipment",_owned_items))
		options.append(_choice("Inspect / remove installed objects",_installed))
		options.append(_choice("Change building use",_uses))
		options.append(_choice("Property storage",_storage.bind(false)))
		options.append(_choice("Store an owned item",_storage.bind(true)))
		options.append(_choice("Access: "+String(row.access),_access))
	else: options.append(_choice("Inspect installed objects",_installed))
	var owner_name:=String(world.civic_interactions.identity(String(row.owner)).get("name",row.owner)) if not row.owner.is_empty() else "Vacant"
	menu.show_page("BUILDING · "+Regions.grid_label(Regions.grid_at(descriptors[current].point)),"Use: "+String(row.usage).replace("_"," ").capitalize()+"\nOwner: "+owner_name+"\nInstalled objects: "+str(row.placements.size())+" / 64\nKeep doorways, stairs and exit routes clear.",options)

func _guild_terminal() -> void:
	menu.close_menu()
	world.civic_interactions.open_guild_premises(current)

func _assign_starter_guilds() -> void:
	if _guild_premises_ready or not world.civic_interactions.initialized: return
	var organizations: RefCounted=world.quest_system.organizations
	if organizations.guilds.is_empty(): return
	var targets:={"cartographers":Vector3(-224,0,-160),"relic_seekers":Vector3(-352,0,-288),"lit_mob":Vector3(288,0,224),"veil":Vector3(352,0,96),"black_ledger":Vector3(224,0,352),"dark_box":Vector3(160,0,-288),"iron_wardens":Vector3(352,0,-224),"inquest":Vector3(288,0,-352),"trade_united":Vector3(-224,0,160),"artificers":Vector3(-352,0,288),"wayfarer_logistics":Vector3(-96,0,352)}
	for guild: Dictionary in organizations.guilds.values():
		if not targets.has(guild.id) or guild.status!="active": continue
		if not String(guild.headquarters).is_empty(): continue
		var target: Vector3=targets[guild.id]
		var chosen:=""; var best:=INF
		for id: String in descriptors:
			var row: Dictionary=model.records[id]
			if row.manual_review or not String(row.owner).is_empty() or descriptors[id].region!="city": continue
			var distance: float=descriptors[id].point.distance_squared_to(target)
			if distance<best: chosen=id; best=distance
		if chosen.is_empty(): continue
		var owner:="guild/"+String(guild.id)
		if not model.claim(chosen,owner,_now()): continue
		model.set_use(chosen,owner,"guild_headquarters",_now())
		organizations.set_headquarters(String(guild.id),chosen)
		if chosen not in organizations.guilds[guild.id].assets: organizations.guilds[guild.id].assets.append(chosen)
	var faction_targets:={"exploration":Vector3(-160,0,-352),"security":Vector3(224,0,-160),"commerce":Vector3(-288,0,224),"underworld":Vector3(352,0,352)}
	for key: String in organizations.factions:
		if not String(organizations.factions[key].get("headquarters","")).is_empty(): continue
		var chosen:=""; var best:=INF
		for id: String in descriptors:
			var row: Dictionary=model.records[id]
			if row.manual_review or not String(row.owner).is_empty() or descriptors[id].region!="city": continue
			var distance: float=descriptors[id].point.distance_squared_to(faction_targets[key])
			if distance<best: chosen=id; best=distance
		if chosen.is_empty(): continue
		var owner:="faction/"+key
		if model.claim(chosen,owner,_now()):
			model.set_use(chosen,owner,"office",_now())
			organizations.set_faction_headquarters(key,chosen)
	_guild_premises_ready=true
	_refresh_guild_signs()
	changed.emit()

func _refresh_guild_signs() -> void:
	for node: Node in _guild_signs.values():
		if is_instance_valid(node): node.queue_free()
	_guild_signs.clear()
	for guild: Dictionary in world.quest_system.organizations.guilds.values():
		if guild.status!="active": continue
		var id:=String(guild.headquarters)
		if not descriptors.has(id): continue
		var label:=Label3D.new()
		label.name="GuildHeadquartersSign"
		label.text="PRIVATE OFFICES" if guild.faction=="underworld" else String(guild.name).to_upper()
		label.modulate=Color.html(String(world.quest_system.model.factions[guild.faction].color))
		label.font_size=40; label.pixel_size=.012; label.outline_size=8
		label.visibility_range_end=90
		add_child(label)
		label.global_position=descriptors[id].point+Vector3(0,3.4,float(model.records[id].size[2])*.5+.04)
		_guild_signs[id]=label
	for faction: Dictionary in world.quest_system.organizations.factions.values():
		var id:=String(faction.get("headquarters",""))
		if not descriptors.has(id): continue
		var label:=Label3D.new()
		label.name="FactionHeadquartersSign"
		label.text="PRIVATE OFFICES" if faction.id=="underworld" else String(faction.name).to_upper()+"\nFACTION HEADQUARTERS"
		label.modulate=Color.html(String(world.quest_system.model.factions[faction.id].color))
		label.font_size=34; label.pixel_size=.012; label.outline_size=8; label.visibility_range_end=90
		add_child(label)
		label.global_position=descriptors[id].point+Vector3(0,4.0,float(model.records[id].size[2])*.5+.04)
		_guild_signs[id]=label

func _claim() -> void:
	if not _near(current) or _busy: return
	_busy=true
	var ok:=model.claim(current,"player",_now())
	_busy=false
	if ok: changed.emit()
	_home()

func _uses() -> void:
	var options: Array=[]
	for use: String in Model.USES:
		if use!="vacant": options.append(_choice(use.capitalize().replace("_"," "),_set_use.bind(use)))
	menu.show_page("BUILDING USE","The physical structure and owned contents stay with the property.",options,_home)
func _set_use(use: String) -> void:
	if _near(current) and model.set_use(current,"player",use,_now()): changed.emit()
	_home()
func _access() -> void:
	if not _near(current): return
	var values: Array=["public","owner","tenants"]
	if model.set_access(current,"player",values[(values.find(model.records[current].access)+1)%3],_now()): changed.emit()
	_home()

func _owned_items() -> void:
	var options: Array=[]
	for item: Resource in world.player.inventory.items.values():
		var definition: Resource=Catalog.get_definition(item.item_type_id)
		if definition.custom_properties.get("placeable",false): options.append(_choice(definition.display_name+" ×"+str(item.quantity),begin_placement.bind(String(item.instance_id))))
	menu.show_page("OWNED FURNISHINGS","Buy furnishings in-world or obtain them from the developer Tower Exchange. Installing transfers one real owned item into this property.",options,_home)

func begin_placement(iid: String) -> bool:
	if not _allowed(): return false
	current=nearest()
	if current.is_empty() or not model.allowed(current,"player"): return false
	var item: Resource=world.player.inventory.get_item(iid)
	if item==null: return false
	var props: Dictionary=Catalog.get_definition(item.item_type_id).custom_properties
	if not props.get("placeable",false): return false
	world.inventory_session._close_communication("renovation")
	if world.inventory_session.ui.is_open: world.inventory_session.ui.close_menu()
	var base: Array=model.records[current].position
	var local: Vector3=world.player.global_position-Vector3(float(base[0]),float(base[1]),float(base[2]))
	local+=world.player.visual.global_basis.z*1.5
	var floor_height:=float(model.records[current].layout.floor_height)
	var floor:=clampi(floori(local.y/floor_height),0,int(model.records[current].layout.floor_count)-1)
	local.y=floor*floor_height
	_placement={"iid":iid,"position":[snappedf(local.x,.5),local.y,snappedf(local.z,.5)],"yaw":0.0}
	_snap_mount(props)
	_placement_menu(); return true

func _snap_mount(props: Dictionary) -> void:
	var row: Dictionary=model.records[current]
	var position: Array=_placement.position
	var size: Array=props.get("size",[1,1,1])
	var floor_height:=float(row.layout.floor_height)
	var base:=floorf((float(position[1])+.01)/floor_height)*floor_height
	match String(props.get("placement_surface","floor")):
		"wall":
			position[2]=float(row.size[2])*.5-.45-float(size[2])*.5; position[1]=base+1.2
		"ceiling": position[1]=base+floor_height-.25-float(size[1])
		"surface":
			for object: Dictionary in row.placements.values():
				if Vector2(float(position[0])-float(object.position[0]),float(position[2])-float(object.position[2])).length()<1.5:
					position[1]=float(object.position[1])+float(Catalog.get_definition(StringName(object.item.item_type_id)).custom_properties.get("size",[1,1,1])[1]); break

func _placement_menu() -> void:
	var item: Resource=world.player.inventory.get_item(String(_placement.get("iid","")))
	if item==null or not _near(current): menu.close_menu(); return
	var valid:=model.can_place(current,item.to_dict(),_placement.position,float(_placement.yaw))
	var at: Array=_placement.position
	menu.show_page("PLACE · "+Catalog.get_definition(item.item_type_id).display_name,"Snapped position: %.1f / %.1f / %.1f\nRotation: %.0f°\n%s" % [at[0],at[1],at[2],rad_to_deg(float(_placement.yaw)),"Clear and supported" if valid else model.last_error],[ _choice("Install here",_install,valid),_choice("Rotate 90°",_move.bind(0.0,0.0,true)),_choice("Left 0.5 m",_move.bind(-.5,0.0,false)),_choice("Right 0.5 m",_move.bind(.5,0.0,false)),_choice("Forward 0.5 m",_move.bind(0.0,-.5,false)),_choice("Back 0.5 m",_move.bind(0.0,.5,false))],_owned_items)
func _move(x: float,z: float,rotate: bool) -> void:
	_placement.position[0]+=x; _placement.position[2]+=z
	if rotate: _placement.yaw=wrapf(float(_placement.yaw)+PI*.5,-PI,PI)
	_placement_menu()
func _install() -> void:
	var ok:=install(current,"player",world.player.inventory,String(_placement.get("iid","")),_placement.get("position",[]),float(_placement.get("yaw",0)))
	if ok: _owned_items()
	else: _placement_menu()

func install(id: String,actor: String,source: Node,iid: String,position: Array,yaw: float) -> bool:
	if _busy or not ready_for_use or not _can_manage(id,actor) or not _identity(actor) or source==null: return false
	if actor=="player" and source!=world.player.inventory: return false
	if actor!="player" and source!=world.civilian_services.economy.npc_store(actor): return false
	if actor=="player" and not _near(id): return false
	if actor!="player" and world.civic_interactions.position_for(actor).distance_to(Vector3(float(model.records[id].position[0]),float(model.records[id].position[1]),float(model.records[id].position[2])))>40: return false
	var original: Resource=source.get_item(iid)
	if original==null or not model.can_place(id,original.to_dict(),position,yaw): return false
	_busy=true
	var before: Dictionary=source.serialize()
	var shadow:=Inventory.new(); var ok:=shadow.restore(before)
	var item: Resource=shadow.take_item(iid,1) if ok else null
	if item!=null: item.owner_id=Model.owner_key(id)
	var row_before: Dictionary=model.records[id].duplicate(true)
	ok=item!=null and model.install(id,String(model.records[id].owner),item.to_dict(),position,yaw,_now()) and source.restore(shadow.serialize())
	shadow.free()
	if not ok: model.records[id]=row_before; source.restore(before)
	_busy=false
	if ok:
		changed.emit(); _render_revision.erase(id)
		if actor!="player": world.civic_interactions._queue_career_event({"event_id":"renovation/"+String(item.instance_id)+"/"+id,"actor_id":actor,"service":"furnishing_installation"})
	return ok

func _can_manage(id: String,actor: String) -> bool:
	if not model.records.has(id) or model.records[id].manual_review: return false
	var owner:=String(model.records[id].owner)
	if owner==actor: return true
	var organizations: RefCounted=world.quest_system.organizations
	if owner.begins_with("guild/"): return organizations.guilds.get(owner.trim_prefix("guild/"),{}).get("leader")==actor
	if owner.begins_with("faction/"): return organizations.factions.get(owner.trim_prefix("faction/"),{}).get("leader")==actor
	return false

func _identity(id: String) -> bool: return world.civic_interactions.identity(id).get("active",false)

func _installed() -> void:
	var options: Array=[]
	for entry: Dictionary in model.records[current].placements.values():
		options.append(_choice(Catalog.get_definition(StringName(entry.item.item_type_id)).display_name,_object.bind(String(entry.id))))
	menu.show_page("INSTALLED OBJECTS","Inspect an object to use or remove it.",options,_home)
func _object(id: String) -> void:
	var entry: Dictionary=model.records[current].placements.get(id,{})
	if entry.is_empty(): _installed(); return
	var definition: Resource=Catalog.get_definition(StringName(entry.item.item_type_id))
	var interaction:=String(definition.custom_properties.get("interaction","decoration"))
	var options: Array=[]
	if interaction in ["storage","archive","wardrobe"]: options.append(_choice("Open property storage",_storage.bind(false)))
	if interaction in ["seat","rest"]: options.append(_choice("Use "+interaction,_use_object.bind(id,interaction)))
	if interaction in ["contracts","guild","trade"]: options.append(_choice("Open shared civic services",_civic_terminal.bind(interaction)))
	options.append(_choice("Remove and reclaim owned item",_remove.bind(id),model.allowed(current,"player")))
	menu.show_page(definition.display_name,definition.description+"\n\nInteraction: "+interaction+". "+("This equipment is ready for its future production system." if interaction in ["craft","cook","repair","security","lighting"] else ""),options,_installed)
func _remove(id: String) -> void:
	if not _near(current) or _busy: return
	_busy=true
	var before: Dictionary=model.records[current].duplicate(true)
	var result:=model.remove(current,"player",id,_now())
	var item:=Item.from_dict(result)
	if item!=null: item.owner_id=""
	var ok: bool=item!=null and world.player.inventory.add_item(item)
	if not ok: model.records[current]=before
	_busy=false
	if ok: changed.emit(); _render_revision.erase(current)
	_installed()
func _storage(deposit: bool) -> void:
	if not _near(current) or not model.allowed(current,"player"): return
	var entries: Array=world.player.inventory.serialize().items if deposit else model.records[current].storage.items
	var options: Array=[]
	for item: Dictionary in entries: options.append(_choice(Catalog.get_definition(StringName(item.item_type_id)).display_name+" ×"+str(item.quantity),_transfer.bind(String(item.instance_id),deposit)))
	menu.show_page("DEPOSIT" if deposit else "PROPERTY STORAGE","Items retain their actual identity and properties.",options,_home)
func _transfer(iid: String,deposit: bool) -> void:
	if _busy or not _near(current) or not model.allowed(current,"player"): return
	_busy=true
	var owned:=Inventory.new(); var store:=Inventory.new()
	var ok:=owned.restore(world.player.inventory.serialize()) and store.restore(model.records[current].storage)
	var source: Node=owned if deposit else store; var recipient: Node=store if deposit else owned
	var item: Resource=source.take_item(iid,1) if ok else null
	ok=item!=null and recipient.add_item(item)
	if ok:
		ok=world.player.inventory.restore(owned.serialize())
		if ok: model.records[current].storage=store.serialize()
	owned.free(); store.free(); _busy=false
	if ok: changed.emit()
	_storage(deposit)

func _use_object(id: String,kind: String) -> void:
	if not _near(current): return
	var row: Dictionary=model.records[current].placements[id]
	var point: Array=row.position; var base: Array=model.records[current].position
	var at:=Vector3(float(base[0])+float(point[0]),float(base[1])+float(point[1]),float(base[2])+float(point[2]))
	if world.player.global_position.distance_to(at)>3: menu.set_status("Move closer to this object.",true); return
	menu.close_menu()
	world.world_actions.seat={"point":at+Vector3.UP*.95,"forward":Vector3(sin(float(row.yaw)),0,cos(float(row.yaw))),"occupant":world.player,"world":world.player.get_world_3d(),"bed":kind=="rest"}
	world.world_actions.begin_attachment(); world.world_actions.anchor()
	if kind=="rest": world.civilian_services.food_effect={"remaining":5.0,"rate":12.0,"rest":true}
func _civic_terminal(kind: String) -> void:
	menu.close_menu()
	world.civic_interactions.open_remote_terminal(kind,current)

func serialize() -> Dictionary: return model.serialize()
func restore(input: Variant) -> bool:
	if _busy or not ready_for_use: return false
	menu.close_menu(); var ok:=model.restore(input)
	if ok: _render_revision.clear(); _guild_premises_ready=false; _homes.clear(); changed.emit()
	return ok

func _render(id: String) -> void:
	var shell: Node=descriptors[id].get("shell")
	if not is_instance_valid(shell): return
	if _render_revision.get(id,-1)==int(model.records[id].renovation): return
	if _rendered.has(id) and is_instance_valid(_rendered[id]): _rendered[id].queue_free()
	var parent:=Node3D.new(); parent.name="InstalledFurnishings"; shell.furniture_parent().add_child(parent)
	_rendered[id]=parent
	var geometry: Script=load("res://scripts/furniture_geometry.gd")
	for entry: Dictionary in model.records[id].placements.values():
		var object: Node3D=geometry.for_id(StringName(entry.item.item_type_id),true)
		parent.add_child(object); object.position=Vector3(float(entry.position[0]),float(entry.position[1]),float(entry.position[2])); object.rotation.y=float(entry.yaw)
	_render_revision[id]=int(model.records[id].renovation)

func _process(delta: float) -> void:
	_clock-=delta
	if _clock>0 or not ready_for_use: return
	_clock=.5
	_assign_starter_guilds()
	if menu.is_open and not _near(current): menu.close_menu()
	var inside_id:=nearest()
	var candidates:=local_candidates()
	for id: String in _local_shells:
		if id not in candidates: candidates.append(id)
	_local_shells.clear()
	inspected_shells=candidates.size()
	for id: String in candidates:
		var descriptor: Dictionary=descriptors[id]
		var shell: Node=descriptor.get("shell")
		if not is_instance_valid(shell): continue
		var row: Dictionary=model.records[id]
		var relative: Vector3=world.player.global_position-descriptor.point
		var outside_x:=maxf(0,absf(relative.x)-float(row.size[0])*.5)
		var outside_z:=maxf(0,absf(relative.z)-float(row.size[2])*.5)
		var near: bool=world.dungeon_travel.active_location==world.dungeon_travel.OUTSIDE and outside_x*outside_x+outside_z*outside_z<64 and relative.y>=-8 and relative.y<float(row.size[1])+8
		if shell.has_method("set_accessible"):
			var permitted: bool=row.access=="public" or row.owner=="player" or row.access=="tenants" and "player" in row.tenants or inside_id==id
			shell.set_accessible(permitted)
		shell.set_nearby(near,world.player.global_position.y-descriptor.point.y)
		if near:
			_local_shells[id]=true
			_render(id)
		elif _rendered.has(id):
			if is_instance_valid(_rendered[id]): _rendered[id].queue_free()
			_rendered.erase(id); _render_revision.erase(id)

func npc_step(record: Dictionary) -> bool:
	if not ready_for_use or _busy or not world.civic_interactions.initialized: return false
	var id:=String(record.id)
	_request_workplace_visit(record)
	var home:=String(_homes.get(id,""))
	if home.is_empty():
		var owned: Array[String]=model.properties_for(id)
		if not owned.is_empty(): home=owned[0]; _homes[id]=home
	var location: Vector3=world.civic_interactions.position_for(id)
	if not location.is_finite(): return false
	if home.is_empty() and float(record.motivations.get("security",.5))>.55:
		# A bounded local opportunity, not a global search for the best property.
		var keys: Array[String]=[]
		var cell:=Vector2i(floori(location.x/128),floori(location.z/128))
		for x in range(-1,2):
			for z in range(-1,2): keys.append_array(_cells.get(cell+Vector2i(x,z),[]))
		keys.sort_custom(func(a: String,b: String): return descriptors[a].point.distance_squared_to(location)<descriptors[b].point.distance_squared_to(location))
		for offset in range(mini(12,keys.size())):
			var key:=keys[offset]
			if model.records[key].manual_review or not model.records[key].owner.is_empty() or descriptors[key].point.distance_to(location)>64: continue
			_busy=true
			var claimed:=model.claim(key,id,_now())
			_busy=false
			if claimed:
				world.civilization.registry.remember(id,"property",key,"Occupied a vacant architectural shell.",.7)
				changed.emit(); home=key; _homes[id]=home; break
	if float(record.motivations.get("loyalty",.5))>.75:
		for group: Dictionary in [world.quest_system.organizations.guilds,world.quest_system.organizations.factions]:
			for institution: Dictionary in group.values():
				var place:=String(institution.get("headquarters",""))
				if institution.leader==id and model.records.has(place) and descriptors[place].point.distance_to(location)<40: home=place; break
	if home.is_empty(): return false
	var source: Node=world.civilian_services.economy.npc_store(id)
	for item: Resource in source.items.values():
		var definition: Resource=Catalog.get_definition(item.item_type_id)
		if not definition.custom_properties.get("placeable",false): continue
		var dimensions: Array=definition.custom_properties.get("size",[1,1,1])
		var row: Dictionary=model.records[home]
		for offset in range(6):
			var x: float=-float(row.size[0])*.5+float(dimensions[0])*.5+.8
			var z: float=-float(row.size[2])*.5+2.0+offset*2.0
			if install(home,id,source,item.instance_id,[x,0.0,z],0):
				world.civilization.registry.remember(id,"renovation",home,"Installed an actually purchased furnishing.",.6)
				return true
	return false

func _request_workplace_visit(record: Dictionary) -> void:
	if not is_instance_valid(world.get("careers")) or world.get("career_commute")==null or record.current_goal not in ["work","trade"]: return
	var id:=String(record.id)
	var regional: Dictionary=world.civilization.autonomy._regional_records.get(id,{})
	if regional.is_empty(): return
	var worker: Dictionary=world.careers.model.workers.get(id,{})
	var employment: Dictionary=world.careers.model.employments.get(String(worker.get("primary","")),{})
	var workplace:=String(employment.get("workplace",""))
	if not descriptors.has(workplace) or not world.careers.definitions.has(employment.get("career","")): return
	var capability:=String(world.careers.definitions[employment.career].capabilities[0])
	var interaction: String={"production":"craft","food_preparation":"cooking","trade":"trade","administration":"guild"}.get(capability,"")
	if interaction.is_empty(): return
	var row: Dictionary=model.records[workplace]
	var base: Vector3=descriptors[workplace].point
	for placement: Dictionary in row.placements.values():
		if Catalog.get_definition(StringName(placement.item.item_type_id)).custom_properties.get("interaction")!=interaction: continue
		var local: Array=placement.position
		if absf(float(local[1]))>.1: continue
		var point:=base+Vector3(float(local[0]),float(local[1]),float(local[2]))
		world.career_commute.request(regional,descriptors[workplace],point)
		break
