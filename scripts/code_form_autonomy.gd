extends RefCounted
## Civilian decisions and model actions; existing pedestrian/combat systems own bodies.
const Profiles = preload("res://scripts/resident_profiles.gd")
const Neon = preload("res://scripts/neon.gd")
const Catalog = preload("res://scripts/item_catalog.gd")
const BATCH_SIZE := 12
const MAX_STATES := 8192
const GOALS := ["work","trade","eat","socialize","explore","rest","train","guild","wonder"]
var civilization: Node
var states: Dictionary = {}
var cursor := 0
var decisions := 0
var completed_actions := 0
var _sources: Dictionary = {}
var _regional_records: Dictionary = {}

func _registry(): return civilization.registry if is_instance_valid(civilization) else null
func _now() -> float: return float(_registry().world_seconds) if _registry()!=null else 0.0
func _world(): return civilization.get("world") if is_instance_valid(civilization) else null
func _economy(): return civilization.get("economy") if is_instance_valid(civilization) else null
func _interactions() -> Node:
	var world=_world()
	return world.get("civic_interactions") if is_instance_valid(world) else null

func _preferred_destination(id: String) -> String:
	var civic:=_interactions()
	return String(civic.preferred_destination(id)) if is_instance_valid(civic) and civic.has_method("preferred_destination") else ""
func _day() -> float: return float(_registry().config.day_seconds)
func _scale() -> float: return _day()/float(_registry().config.real_seconds_per_day)

func _id(source: Node) -> String:
	if not is_instance_valid(source) or not is_instance_valid(civilization): return ""
	return String(civilization.id_for_source(source))

func _state(id: String) -> Dictionary:
	if not states.has(id):
		states[id]={"next_decision":0.0,"next_action":0.0,"last_update":_now(),"hunger":.15+float(posmod(id.hash(),45))/100.0,"turn":0,"actions":0}
	return states[id]

func bind_source(source: Node) -> void:
	if not is_instance_valid(source) or _registry()==null: return
	var slot := ""
	if source.get("record") is Dictionary:
		slot=String(source.record.get("code_form_slot","region/"+str(source.record.id)))
	elif source.get("profile") is Dictionary: slot="hub/"+String(source.profile.id)
	var record: Dictionary=_registry().for_slot(slot)
	if record.is_empty(): return
	source.code_form_id=record.id
	source.profile.code_form_id=record.id
	if String(source.profile.name)!=String(record.name): _retint(source,record)
	source.profile.attitude=record.personality
	source.set_meta("code_form_id",record.id)
	source.set_meta("code_form_slot",slot)
	if source.get("record") is Dictionary:
		source.record.code_form_id=record.id
		source.record.code_form_slot=slot
		_regional_records[record.id]=source.record
	_sources[record.id]=weakref(source)

func bind_sources() -> void:
	_sources.clear()
	_regional_records.clear()
	var world=_world()
	if not is_instance_valid(world): return
	var population=world.get("population")
	if is_instance_valid(population):
		population.civilization=civilization
		for source: Node in population.residents: bind_source(source)
	var life=world.get("district_life")
	if not is_instance_valid(life): return
	life.civilization=civilization
	for record: Dictionary in life.resident_records:
		var slot: String=record.get("code_form_slot","region/"+str(record.id))
		var identity: Dictionary=_registry().for_slot(slot)
		if identity.is_empty(): continue
		var body: Node=life.people.get(record.id)
		if is_instance_valid(body) and String(record.profile.name)!=String(identity.name): _retint(body,identity)
		record.code_form_slot=slot
		record.code_form_id=identity.id
		record.profile.code_form_id=identity.id
		record.profile.name=identity.name
		record.profile.attitude=identity.personality
		_regional_records[identity.id]=record
	for vehicle: Dictionary in life.vehicle_records:
		var slot := "driver/"+str(vehicle.id)
		var identity: Dictionary=_registry().for_slot(slot)
		if identity.is_empty(): continue
		vehicle.driver.code_form_slot=slot
		vehicle.driver.code_form_id=identity.id
		vehicle.driver.name=identity.name
		vehicle.driver.attitude=identity.personality
	for source: Node in life.people.values(): bind_source(source)

func _source(id: String) -> Node:
	var reference: WeakRef=_sources.get(id)
	return reference.get_ref() if reference!=null else null

func _unavailable(id: String,source: Node=null) -> bool:
	if _regional_records.get(id,{}).get("combat",false): return true
	if not is_instance_valid(source): source=_source(id)
	if not is_instance_valid(source): return false
	if source.get("record") is Dictionary and source.record.get("combat",false): return true
	if source.get("indoor_left") is float and is_inf(source.indoor_left): return true
	var reactions=source.population.reactions if source.get("population")!=null else source.life.reactions
	if not is_instance_valid(reactions): return false
	var key: String=reactions.key_for(source)
	var entry: Dictionary=reactions.entries.get(key,{})
	return entry.get("dead",false) or entry.get("suspended",false) or reactions.fighters.has(key)

func _motivation(record: Dictionary,key: String) -> float:
	return clampf(float(record.get("motivations",{}).get(key,.5)),0,1)

func _balance(id: String) -> int:
	var economy=_economy()
	return economy.balance("resident:"+id) if is_instance_valid(economy) else 0

func _shop() -> Node:
	var world=_world()
	return world.get("glyphic_wonders") if is_instance_valid(world) else null

func _shop_anchor() -> Node3D:
	var world=_world()
	if not is_instance_valid(world): return null
	var regions=world.get("wider_world")
	if not is_instance_valid(regions): return null
	var exterior=regions.get("glyphic_wonders")
	return exterior.get("arrival_anchor") if is_instance_valid(exterior) else null

func shopping_position(id: String) -> Vector3:
	var source:=_source(id)
	if is_instance_valid(source): return source.global_position
	var record: Dictionary=_regional_records.get(id,{})
	return record.get("point",Vector3(INF,INF,INF))

func _shopping_interest(record: Dictionary,coins: int) -> float:
	var shop:=_shop()
	if not is_instance_valid(shop): return 0.0
	var stock=shop.get("stock")
	if stock==null or not stock.has_method("offers"): return 0.0
	var interest:=0.0
	# Inspect the currently offered subset, never the developer exchange or an
	# independent list of retail goods. Root commerce still validates the quote.
	for offer: Dictionary in stock.offers():
		if int(offer.get("price",0))<=0 or int(offer.price)>coins: continue
		var definition: Resource=Catalog.get_definition(StringName(offer.get("type_id","")))
		if definition==null: continue
		var value:=.2+_motivation(record,"novelty")*.5
		if String(definition.item_type_id).begins_with("health_glyph") or String(definition.item_type_id).begins_with("shield_glyph"):
			value+=_motivation(record,"security")*.55+_motivation(record,"survival")*.35
		elif definition.category==&"weapons": value+=_motivation(record,"mastery")*.7
		elif definition.category==&"materials": value+=_motivation(record,"knowledge")*.45+_motivation(record,"wealth")*.25
		else: value+=_motivation(record,"social")*.25+_motivation(record,"wealth")*.25
		interest=maxf(interest,value)
	return interest

func choose_goal(record: Dictionary,state: Dictionary) -> String:
	var coins:=_balance(String(record.id))
	var hunger: float=state.hunger
	var lifespan: float=_day()*float(_registry().config.days_per_year)*float(_registry().config.lifetime_years)
	var urgency:=clampf(1.0-_registry().remaining_lifetime(record.id)/maxf(1.0,lifespan*.15),0,1)
	var safety:=maxf(0,-float(record.relationships.get("player",0)))
	var company:=0.0
	var unavailable_work:=false
	for affinity: float in record.relationships.values(): company=maxf(company,affinity)
	for memory: Dictionary in record.get("memories",[]):
		if memory.type=="combat" and _now()-float(memory.timestamp)<_day()*3: safety=maxf(safety,.8)
		if memory.type=="outcome" and memory.target=="work" and String(memory.summary).begins_with("Unavailable") and _now()-float(memory.timestamp)<_day(): unavailable_work=true
	var scores: Dictionary={
		"work":.25+_motivation(record,"security")*.9+_motivation(record,"wealth")*.4+(1.0 if coins<8 else 0.0),
		"trade":.1+_motivation(record,"wealth")*.65,
		"eat":.08+hunger*hunger*2.4+_motivation(record,"survival")*.2,
		"socialize":.2+_motivation(record,"social")*1.3,
		"explore":.15+_motivation(record,"knowledge")*.8+_motivation(record,"novelty")*.75,
		"rest":.15+_motivation(record,"survival")*.55,
		"train":.1+_motivation(record,"mastery")*1.4,
		"guild":.1+_motivation(record,"loyalty")*(1.1 if String(record.get("guild","")).is_empty() else .2),
		"wonder":_shopping_interest(record,coins)}
	scores.work+=urgency*.8
	scores.guild+=urgency*.9
	scores.explore+=urgency*.8
	scores.train+=urgency*.2
	scores.rest+=safety*.9
	scores.socialize+=company*.5
	scores.explore*=1.0-safety*.4
	if unavailable_work:
		scores.work*=.45
		scores.trade+=.25
		scores.guild+=.35
	var best: String="rest"
	var highest: float=-1
	for goal: String in GOALS:
		var variation:=.72+float(posmod((String(record.id)+goal+str(state.turn)).hash(),61))/100.0
		var score: float=float(scores[goal])*variation
		if goal==record.get("current_goal",""): score*=.75
		if score>highest: highest=score; best=goal
	return best

func process_batch(_delta: float) -> void:
	var registry=_registry()
	if registry==null: return
	var ids: Array=registry.active_ids()
	if ids.is_empty(): return
	# The authoritative clock advances centrally, including capped offline time.
	# One call never catches up by running an unbounded loop of old decisions.
	for offset in range(mini(BATCH_SIZE,ids.size())):
		var id: String=ids[cursor%ids.size()]
		cursor=(cursor+1)%ids.size()
		var record: Dictionary=registry.records.get(id,{})
		if record.is_empty() or not record.active: continue
		var state:=_state(id)
		var elapsed:=maxf(0,_now()-float(state.last_update))
		state.last_update=_now()
		state.hunger=minf(1,float(state.hunger)+elapsed/(_day()*6.0))
		if _now()>=float(state.next_decision):
			state.turn+=1
			registry.set_goal(id,choose_goal(record,state),"")
			state.next_decision=_now()+(45+posmod(id.hash()+int(state.turn),46))*_scale()
			decisions+=1
		if _now()<float(state.next_action): continue
		state.next_action=_now()+(60+posmod(id.hash(),61))*_scale()
		var source:=_source(id)
		if _unavailable(id,source): continue
		# Nearby visible inhabitants complete work at real arrivals. Unloaded,
		# virtual and indoor identities use the same bounded economic model.
		if is_instance_valid(source) and source.is_visible_in_tree() and source.get("virtualized")!=true: continue
		perform_action(record,state,false)

func _event(record: Dictionary,type: String,target: String,rarity: String="common",significance: float=.5) -> void:
	civilization.record_event({"event_type":type,"actor_id":record.id,"target_id":target,"rarity":rarity,"significance":significance,"event_id":type+"/"+String(record.id)+"/"+target})

func perform_action(record: Dictionary,state: Dictionary,physical: bool) -> bool:
	if not record.get("active",false) or _unavailable(String(record.id)): return false
	var registry=_registry()
	var economy=_economy()
	var id: String=record.id
	var success:=false
	var civic:=_interactions()
	if is_instance_valid(civic) and civic.has_method("npc_step") and String(record.current_goal) in ["work","guild","explore","socialize","trade"]:
		success=bool(civic.npc_step(record,state,physical))
	if not success:
		match String(record.current_goal):
			"work":
				if is_instance_valid(economy) and (not is_instance_valid(_world()) or not is_instance_valid(_world().get("careers"))):
					var tavern: bool=String(record.slot).begins_with("service/tavern") or String(record.occupation).to_lower().contains("tavern") or String(record.occupation).to_lower().contains("bartender")
					var key: String="tavern_work" if tavern else "guild_work"
					success=economy.npc_service_wage(id,key,floori(_now()/_day()))
					if success: registry.remember(id,"work",key,"Completed paid civilian work.",.4)
			"eat":
				if is_instance_valid(economy):
					var pantry: Node=economy.npc_store(id) if economy.has_method("npc_store") else null
					# Owned meals and desserts take priority over drinks and buying
					# another meal; the same authority consumes the real item.
					for drinks: bool in [false,true]:
						if success or not is_instance_valid(pantry): break
						for item: Resource in pantry.items.values():
							var definition: Resource=Catalog.get_definition(item.item_type_id)
							if definition==null or not definition.custom_properties.get("civilian_food",false) or (definition.custom_properties.get("cuisine_kind")=="drink")!=drinks: continue
							if economy.npc_consume_food(id,item.item_type_id): success=true; break
					if not success and economy.npc_buy_food(id,&"electron_meal"): success=economy.npc_consume_food(id,&"electron_meal")
					if success: state.hunger=0.0; registry.remember(id,"meal","cuisine","Enjoyed some owned Electron cuisine.",.3)
			"trade":
				if is_instance_valid(economy):
					var inventory: Node=economy.npc_store(id)
					if inventory==null: return false
					for item: Resource in inventory.items.values():
						if economy.crystal_price(item.item_type_id)>0:
							success=economy.npc_sell_crystal(id,item.instance_id,1)
							break
			"wonder":
				var shop:=_shop()
				if is_instance_valid(shop): success=shop.npc_shop(record,physical)
				if success: registry.remember(id,"shop","glyphic_wonders","Purchased an offered wonder with my own Glyph Coins.",.6)
			"guild":
				if not is_instance_valid(civic) and String(record.get("guild","")).is_empty():
					record.guild="adventurers_guild"
					registry.remember(id,"guild",record.guild,"I joined the Adventurers Guild.",.8)
					_event(record,"guild",record.guild,"uncommon",.8)
					success=true
			"socialize":
				if not physical and not is_instance_valid(civic):
					var peers: Array=registry.active_ids()
					if peers.size()>1:
						var other: String=peers[posmod(id.hash()+int(state.turn),peers.size())]
						if other!=id:
							_social(record,registry.records[other])
							success=true
			"rest","train":
				# These change plans/memory, never generate XP from a repeated idle.
				registry.remember(id,"routine",String(record.current_goal),"Took time for "+String(record.current_goal)+".",.15)
	if success:
		state.actions+=1
		completed_actions+=1
	if String(record.current_goal) in ["work","eat","trade","wonder"]:
		registry.remember(id,"outcome",String(record.current_goal),("Completed " if success else "Unavailable ")+String(record.current_goal)+" opportunity.",.35)
	return success

func choose_destination(resident: CharacterBody3D) -> StringName:
	var id:=_id(resident)
	if id.is_empty() or _registry()==null: return &""
	var record: Dictionary=_registry().records.get(id,{})
	if record.is_empty() or not record.active or resident.transit!=&"outdoor" or resident.reaction_time>0: return &""
	if resident.state in ["talking","annoyed","furious"]: return &""
	var population: Node3D=resident.population
	var neighborhood: StringName=population.place_neighborhood.get(population.nearest_id(resident.position),&"hub")
	var options: Array=population.neighborhood_places.get(neighborhood,[])
	var selected: StringName=&""
	var highest: float=-INF
	var goal: String=record.current_goal
	var shop_anchor:=_shop_anchor() if goal=="wonder" else null
	var requested:=_preferred_destination(id)
	for target: StringName in options:
		if target==resident.goal or population.goal_load(target)>=3 or population.entrances.has(target): continue
		var distance: float=population.points[target].distance_to(resident.position)
		if distance<5: continue
		var score:=float(posmod((id+String(target)+str(_state(id).turn)).hash(),100))/100.0
		var title: String=population.place_name(target)
		if requested=="place/"+String(target): score+=8.0
		if goal=="explore":
			score+=minf(distance/40.0,2.0)
			if not _has_memory(record,"discovery","place/"+String(target)): score+=3
		elif goal=="work":
			if String(record.occupation).contains("garden") and ("garden" in title or "court" in title): score+=3
			elif String(record.occupation).contains("lamp") and ("avenue" in title or "court" in title): score+=3
		elif goal=="rest": score+=2 if target==resident.profile.home else maxf(0,1-distance/50.0)
		elif goal=="socialize":
			for peer: CharacterBody3D in population.active_residents:
				if peer==resident or peer.goal!=target: continue
				score+=maxf(0,float(record.relationships.get(_id(peer),0)))+(_motivation(record,"social")*.5)
		elif goal=="wonder" and is_instance_valid(shop_anchor):
			# Stay on this resident's existing connected graph. A hub resident
			# cannot invent a direct journey through locked progression gates.
			var storefront: Vector3=population.to_local(shop_anchor.global_position)
			score+=clampf(2.0-population.points[target].distance_to(storefront)/80.0,0,2)
		elif goal in ["trade","eat","guild"]: score+=clampf(-population.points[target].z/80.0,0,2)
		if score>highest: highest=score; selected=target
	if not selected.is_empty(): _registry().set_goal(id,goal,String(selected))
	return selected

func _has_memory(record: Dictionary,type: String,target: String) -> bool:
	for memory: Dictionary in record.get("memories",[]):
		if memory.type==type and memory.target==target: return true
	return false

func _arrive(id: String,target: String,source: Node=null) -> void:
	if id.is_empty() or _registry()==null: return
	var record: Dictionary=_registry().records.get(id,{})
	if record.is_empty() or not record.active: return
	if _unavailable(id,source): return
	var civic:=_interactions()
	if is_instance_valid(civic) and civic.has_method("arrived"):
		civic.arrived(id,target)
		var requested:=_preferred_destination(id)
		if not requested.is_empty() and requested!=target:
			# Regional routes remain on their existing safe graph; the runtime
			# accepts a quest arrival only if this real position is near its target.
			civic.arrived(id,requested)
	if not _has_memory(record,"discovery",target):
		_registry().remember(id,"discovery",target,"Visited "+target.trim_prefix("place/")+".",.6)
		_event(record,"exploration",target,"common",.35)
	var state:=_state(id)
	if _now()<float(state.next_action): return
	state.next_action=_now()+60*_scale()
	# A public waypoint is suitable for local work, rest and conversations.
	# Real vendor visits need reachable merchant geometry; model purchases are
	# performed only while the inhabitant is offscreen/indoors instead.
	if String(record.current_goal) in ["work","guild","explore","rest","train"]: perform_action(record,state,true)

func on_arrival(source: Node) -> void:
	if source.get("record") is Dictionary:
		on_regional_arrival(source.record)
	else: _arrive(_id(source),"place/"+String(source.goal),source)

func on_regional_arrival(record: Dictionary) -> void:
	var world=_world()
	var commute=world.get("career_commute") if is_instance_valid(world) else null
	if is_instance_valid(commute) and commute.on_arrival(record): return
	var id: String=record.get("code_form_id","")
	var slot: String=record.get("code_form_slot","region/"+str(record.id))
	var anchor:=_shop_anchor()
	if not id.is_empty() and is_instance_valid(anchor) and record.point.distance_to(anchor.global_position)<1.5:
		var individual: Dictionary=_registry().records.get(id,{}) if _registry()!=null else {}
		if individual.is_empty() or not individual.get("active",false) or _unavailable(id): return
		_registry().remember(id,"visit","glyphic_wonders","Visited the small storefront of Glyphic Wonders.",.6)
		var state:=_state(id)
		if individual.current_goal=="wonder" and _now()>=float(state.next_action):
			state.next_action=_now()+60*_scale()
			var source:=_source(id)
			perform_action(individual,state,is_instance_valid(source) and not source.get("virtualized")==true)
		return # Commerce alone awards shopping XP; passing a doorway does not.
	_arrive(id,"place/"+slot+"/"+str(record.cursor))

func on_talk(source: Node) -> void:
	var id:=_id(source)
	if id.is_empty(): return
	var reactions=source.population.reactions if source.get("population")!=null else source.life.reactions
	var positive: bool=not is_instance_valid(reactions) or not reactions.is_annoyed(source)
	civilization.record_interaction(id,"conversation","player",positive)

func _social(a: Dictionary,b: Dictionary,physical: bool = false) -> void:
	var civic:=_interactions()
	if is_instance_valid(civic) and civic.has_method("socialize"):
		civic.socialize(String(a.id),String(b.id),physical)
		return
	for pair: Array in [[a,b],[b,a]]:
		var before: float=pair[0].relationships.get(pair[1].id,0.0)
		_registry().relate(pair[0].id,pair[1].id,.04)
		_registry().remember(pair[0].id,"social",pair[1].id,"Spent time with "+String(pair[1].name)+".",.45)
		if before<.2 and float(pair[0].relationships.get(pair[1].id,0))>=.2:
			_event(pair[0],"social","friendship/"+String(pair[1].id),"uncommon",.7)

func on_converse(a: Node,b: Node) -> void:
	var left:=_id(a)
	var right:=_id(b)
	if left.is_empty() or right.is_empty() or _registry()==null: return
	if not _registry().records.has(left) or not _registry().records.has(right): return
	_social(_registry().records[left],_registry().records[right],true)

func on_combat(source: Node,kind: String) -> void:
	var id:=_id(source)
	if id.is_empty() or _registry()==null: return
	if kind in ["assault","defeated"]:
		_registry().relate(id,"player",-.08 if kind=="assault" else -.25)
		_registry().remember(id,"combat","player","A human attacked me." if kind=="assault" else "I returned after a combat defeat.",.85)
	elif kind=="theft":
		_registry().relate(id,"player",-.1)
		_registry().remember(id,"theft","player","I witnessed a human stealing a vehicle.",.7)
	elif kind=="victory":
		_registry().remember(id,"combat","victory","I survived a fight with a human.",.85)
		_event(_registry().records[id],"combat","player/victory","common",.8)

func dialogue_line(source: Node) -> String:
	var id:=_id(source)
	if id.is_empty() or _registry()==null: return ""
	var record: Dictionary=_registry().records.get(id,{})
	if record.is_empty(): return ""
	if float(record.relationships.get("player",0))<-.2: return "I remember the fighting. Give me some space, human."
	if record.current_goal=="work" and _balance(id)<8: return "I've work to find. Coins don't circulate by themselves."
	if record.current_goal=="explore": return "I'm looking for a route I haven't learned yet."
	if record.current_goal=="socialize" and not record.relationships.is_empty(): return "I've people of my own to catch up with."
	return ""

func _retint(source: Node,record: Dictionary) -> void:
	source.profile.name=record.name
	source.profile.attitude=record.personality
	source.profile.code_form_id=record.id
	var colors: Array=Profiles.PALETTE.values()
	var tint: Color=colors[posmod(String(record.id).hash(),colors.size())]
	source.profile.tint=tint
	if is_instance_valid(source.get("visual")):
		source.visual.tint=tint
		for child: Node in source.visual.get_children():
			if child is MultiMeshInstance3D: child.material_override=Neon.shared_material(tint)
	if is_instance_valid(source.get("light")): source.light.light_color=tint
	if is_instance_valid(source.get("nameplate")): source.nameplate.text=record.name+"  /  "+String(source.profile.role)
	if is_instance_valid(source.get("caption")): source.caption.text=""; source.caption.hide()

func replace_source(slot: String,old_id: String,new_id: String) -> void:
	states.erase(old_id)
	_sources.erase(old_id)
	_regional_records.erase(old_id)
	var world=_world()
	if not is_instance_valid(world) or _registry()==null: return
	var record: Dictionary=_registry().records.get(new_id,{})
	if record.is_empty(): return
	if slot.begins_with("hub/"):
		var population: Node3D=world.population
		for source: CharacterBody3D in population.residents:
			if "hub/"+String(source.profile.id)!=slot: continue
			if is_instance_valid(population.reactions): population.reactions.retire_source(source)
			for door: Node3D in [source.travel_door,source.pending_door]:
				if is_instance_valid(door): door.release(source)
			population.active_residents.erase(source)
			source.deactivate()
			source.code_form_id=new_id
			source.set_meta("code_form_id",new_id)
			_retint(source,record)
			source.visits=0; source.conversations=0; source.arrivals=0
			source.partner_id=&""; source.reply=""; source.reaction_time=0; source.social_cooldown=4
			source.indoor_left=.5
			_sources[new_id]=weakref(source)
			return
	var life=world.get("district_life")
	if not is_instance_valid(life): return
	for vehicle: Dictionary in life.vehicle_records:
		if slot!="driver/"+str(vehicle.id): continue
		vehicle.driver.code_form_id=new_id
		vehicle.driver.code_form_slot=slot
		vehicle.driver.name=record.name
		vehicle.driver.attitude=record.personality
	for resident: Dictionary in life.resident_records:
		if String(resident.get("code_form_slot","region/"+str(resident.id)))!=slot: continue
		var source: Node=life.people.get(resident.id)
		if is_instance_valid(source):
			if is_instance_valid(life.reactions): life.reactions.retire_source(source)
			life.people.erase(resident.id)
			source.queue_free()
		resident.code_form_id=new_id
		resident.code_form_slot=slot
		resident.profile.name=record.name
		resident.profile.attitude=record.personality
		resident.profile.code_form_id=new_id
		resident.profile.tint=Profiles.PALETTE.values()[posmod(new_id.hash(),Profiles.PALETTE.size())]
		_regional_records[new_id]=resident
		resident.meetings=0; resident.combat=false; resident.anger=0.0; resident.wait=1.0
		var point: Array=record.respawn.position
		resident.point=Vector3(float(point[0]),float(point[1]),float(point[2]))

func serialize() -> Dictionary:
	var active: Dictionary={}
	if _registry()!=null:
		for id: String in _registry().active_ids():
			if states.has(id): active[id]=states[id].duplicate(true)
	return {"version":1,"cursor":cursor,"states":active}

static func validate(data: Variant,active_ids: Array) -> Dictionary:
	if not data is Dictionary or data.get("version")!=1 or not data.get("states") is Dictionary: return {}
	if data.states.size()>MAX_STATES or not _whole(data.get("cursor"),1000000): return {}
	var result: Dictionary={}
	for id: Variant in data.states:
		if not id is String or not active_ids.has(id): return {}
		var state: Variant=data.states[id]
		if not state is Dictionary or state.size()!=6: return {}
		for key: String in ["next_decision","next_action","last_update","hunger"]:
			if not (state.get(key) is int or state.get(key) is float) or not is_finite(float(state[key])) or float(state[key])<0 or float(state[key])>1e15: return {}
		if state.hunger>1: return {}
		for key: String in ["turn","actions"]:
			if not _whole(state.get(key),1000000000): return {}
		result[id]=state.duplicate(true)
		result[id].turn=int(state.turn)
		result[id].actions=int(state.actions)
	return {"version":1,"cursor":int(data.cursor),"states":result}

static func _whole(value: Variant,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=maximum and float(value)==floorf(float(value))

func restore(data: Variant) -> bool:
	if _registry()==null: return false
	if data is Dictionary and data.is_empty(): states.clear(); cursor=0; return true
	var decoded:=validate(data,_registry().active_ids())
	if decoded.is_empty(): return false
	states=decoded.states
	cursor=decoded.cursor
	return true
