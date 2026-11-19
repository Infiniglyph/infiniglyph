extends SceneTree
const Registry = preload("res://scripts/code_form_registry.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func row(slot: String = "hub/ilex", id: String = "ilex") -> Dictionary:
	return {"slot":slot,"id":id,"name":"Ilex","occupation":"courier","personality":"curious","respawn":{"location":"overworld","position":[1.0,.05,2.0],"yaw":.7}}

func event(id: String, receipt: String, target: String = "landmark") -> Dictionary:
	return {"type":"discovery","actor_id":id,"target_id":target,"rarity":"rare","significance":1.0,"event_id":receipt}

func accelerated() -> RefCounted:
	var registry := Registry.new()
	registry.config.day_seconds=10.0
	registry.config.days_per_year=1
	registry.config.lifetime_years=1.0
	registry.config.level_years=1.0
	return registry

func difference(a: Variant, b: Variant, path: String = "root") -> String:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return path+": size"
		for key: Variant in a:
			if not b.has(key): return path+": missing "+str(key)
			var found := difference(a[key],b[key],path+"/"+str(key))
			if not found.is_empty(): return found
		return ""
	if a is Array and b is Array:
		if a.size()!=b.size(): return path+": array size"
		for i in range(a.size()):
			var found := difference(a[i],b[i],path+"/"+str(i))
			if not found.is_empty(): return found
		return ""
	if (a is int or a is float) and (b is int or b is float):
		return "" if absf(float(a)-float(b))<=maxf(.000000001,absf(float(a))*.0000000000001) else path+": number"
	return "" if a==b else path+": "+str(a)+" != "+str(b)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var r := Registry.new()
	check(r.bootstrap([row(),row("service/guild_receptionist","guild_receptionist"),row("region/0","region/0"),row("driver/0","driver/0")]),"Only explicit civilian slots bootstrap without bodies or economy dependencies")
	var year := 365.0*86400
	check(r.for_slot("hub/ilex").id=="ilex" and r.records.ilex.level==1 and r.records.ilex.experience==0 and r.remaining_lifetime("ilex")==100*year,"Legacy hub/service identities retain their wallets and start at level1 with100years")
	check(r.config.real_seconds_per_day==3600 and r.config.blessing_days==30 and r.config.blessing_amount==100 and r.config.offline_cap_seconds==21600,"Central configuration exposes the requested clock, blessing and offline settings")
	var excessive_blessing := Registry.new()
	excessive_blessing.config.blessing_amount=100001
	check(not excessive_blessing.bootstrap([row()]) and excessive_blessing.records.is_empty(),"Registry blessing settings share the ledger's100000-coin upper bound")
	r.advance_to(24*3600)
	check(r.remaining_lifetime("ilex")==100*year-24*3600,"One authoritative absolute world timestamp ages even unloaded identities")
	var remaining: float=r.remaining_lifetime("ilex")
	check(r.grant_xp("ilex",100)==1 and r.remaining_lifetime("ilex")==remaining+100*year,"Leveling adds exactly100years without resetting elapsed life")
	check(r.grant_xp("ilex",1000000000)==98 and r.records.ilex.level==100 and r.records.ilex.experience==495000 and r.records.ilex.expires_at==10000*year,"All99 level gains grant exactly10000years total and stop at level100")
	var state: Dictionary=r.serialize()
	check(r.grant_xp("ilex",100000)==0 and r.serialize()==state,"Maximum-level XP cannot add further life or overflow progression")
	check(r.combat_respawn("ilex")==row().respawn and r.serialize()==state,"Combat death resolves the same designated spawn without aging, XP loss or replacement")
	check(r.grant_xp("player",999999)==0 and r.record_event(event("kyren","boss-xp")).xp==0 and r.record_event(event("monster","enemy-xp")).xp==0 and r.records.size()==4,"Player, bosses and unregistered enemies cannot acquire civilian progression")
	var bad := Registry.new()
	check(not bad.bootstrap([row("boss/kyren","kyren")]) and not bad.bootstrap([row("hub/player","player")]) and bad.records.is_empty(),"Non-civilian scopes and reserved actor identities cannot bootstrap")
	var a: RefCounted=accelerated()
	var initial_rows: Array[Dictionary]=[row()]
	a.bootstrap(initial_rows)
	a.remember("ilex","discovery","site","First journey",.9)
	a.relate("ilex","friend",.7)
	var spawn_before: Dictionary=a.combat_respawn("ilex")
	var replacements: Array=a.advance_to(10)
	var born: Dictionary=a.for_slot("hub/ilex")
	check(replacements.size()==1 and replacements[0].old_id=="ilex" and replacements[0].new_id==born.id and not a.records.ilex.active and a.records.ilex.replaced_by==born.id,"Lifetime expiry creates exactly one new identity and archives the predecessor")
	check(born.id!="ilex" and born.level==1 and born.experience==0 and born.memories.is_empty() and born.relationships.is_empty() and born.personality!="curious" and born.respawn==spawn_before,"Replacement has fresh personality, XP and memory while retaining its population slot and safe spawn")
	check(a.advance_to(10).is_empty() and a.records.size()==2 and a.active_ids().size()==1,"Repeated expiration processing cannot create duplicate replacements")
	var copy := Registry.new()
	check(copy.restore(JSON.parse_string(JSON.stringify(a.serialize(),"",true,true))) and copy.advance_to(10).is_empty() and difference(copy.serialize(),a.serialize()).is_empty(),"Strict JSON roundtrip retains replacement identity, clock and dedup state")
	check(copy.bootstrap([row()]) and copy.for_slot("hub/ilex").id==born.id and copy.records.size()==2,"Rebuilding legacy physical slots cannot resurrect an expired resident")
	var before_jump: Dictionary=copy.serialize()
	check(copy.advance_to(1000000).is_empty() and not copy.last_error.is_empty() and copy.serialize()==before_jump,"An excessive multi-generation jump rejects atomically with an explicit bounded-processing error")
	check(copy.advance_to(9).is_empty() and copy.serialize()==before_jump,"Backward clock updates cannot restore spent lifetime")
	check(copy.advance_to(30).size()==2 and copy.active_ids().size()==1 and copy.records.size()==4,"A bounded multi-generation jump accounts for exact expiration boundaries without population growth")
	var x := Registry.new()
	x.bootstrap([row()])
	var first: Dictionary=x.record_event(event("ilex","receipt-1"))
	check(first.accepted and first.xp==80 and x.record_event(event("ilex","receipt-1")).xp==0,"A meaningful event rewards once and its persistent receipt rejects immediate duplicates")
	var alias: Dictionary=event("ilex","public-event-type","another-landmark")
	alias.event_type=alias.type
	alias.erase("type")
	check(x.record_event(alias).xp==80,"The public event_type spelling and internal type alias share the same reward path")
	var second: Dictionary=x.record_event(event("ilex","receipt-2"))
	var third: Dictionary=x.record_event(event("ilex","receipt-3"))
	check(second.xp==40 and third.xp==20 and x.record_event(event("ilex","receipt-4")).xp==0,"Repeated semantic achievements diminish and then stop despite unique event IDs")
	var idle: Dictionary=event("ilex","idle-event")
	idle.type="idle"
	check(x.record_event(idle).xp==0,"Idle animations and routine ticks never award XP")
	var commerce := Registry.new()
	commerce.bootstrap([row()])
	var trade: Dictionary=event("ilex","trade-1","tavern/meal")
	trade.type="economic"
	trade.rarity="common"
	trade.coins=4
	var small: int=commerce.record_event(trade).xp
	trade.event_id="trade-2"
	trade.target_id="guild/contract"
	trade.coins=100
	var large: int=commerce.record_event(trade).xp
	check(small==16 and large==80 and large>small,"Committed economic events scale XP with real circulated coin amounts without owning any balance")
	trade.event_id="trade-invalid"
	trade.coins=0
	check(commerce.record_event(trade).xp==0,"Zero or invalid circulation cannot reward economic XP")
	trade.coins=4
	trade.target_id="tavern/meal"
	for i in range(4): trade.event_id="same-day-"+str(i); commerce.record_event(trade)
	commerce.advance_to(86400)
	trade.event_id="tomorrow"
	check(commerce.record_event(trade).xp==16 and commerce.records.ilex.novelty.size()==1,"A fresh world day permits meaningful commerce while pruning expired daily counters")
	for i in range(40): x.remember("ilex","memory",str(i),"A compact experience",.5)
	x.remember("ilex","autonomy","decision","{\"need_food\":0.5}",.2)
	for i in range(40): x.remember("ilex","memory",str(i+100),"Another experience",.9)
	var decision := false
	for memory: Dictionary in x.records.ilex.memories:
		if memory.type=="autonomy" and memory.target=="decision": decision=true
	check(x.records.ilex.memories.size()==24 and decision,"Memory stays bounded while retaining the compact autonomous decision state")
	x.remember("ilex","autonomy","decision","updated",.2)
	var updated := 0
	for memory: Dictionary in x.records.ilex.memories:
		if memory.summary=="updated": updated+=1
	check(updated==1 and x.records.ilex.memories.size()==24,"Remembering the same semantic entry updates it instead of growing logs")
	for i in range(40): x.relate("ilex","person-"+str(i),.8)
	check(x.records.ilex.relationships.size()==24 and x.set_goal("ilex","explore","outer-city") and x.for_slot("hub/ilex").current_goal=="explore","Relationship and goal state are compact and independent of visual bodies")
	check(copy.restore(JSON.parse_string(JSON.stringify(x.serialize(),"",true,true))) and copy.record_event(event("ilex","receipt-1")).xp==0,"Event receipt dedup survives memory eviction, unrelated events and JSON reload")
	for i in range(150): x.record_event(event("ilex","novel-"+str(i),"place-"+str(i)))
	check(x.records.ilex.novelty.size()==128 and x.record_event(event("ilex","capacity-overflow","another-place")).xp==80,"A bounded novelty working set continues rewarding genuinely new discoveries after128 achievements")
	check(x.record_event(event("ilex","new-receipt-old-achievement","landmark")).xp==0,"Evicting an old semantic counter cannot reset its reward using a fresh event receipt")
	check(copy.restore(JSON.parse_string(JSON.stringify(x.serialize(),"",true,true))) and copy.record_event(event("ilex","new-receipt-after-reload","landmark")).xp==0 and copy.record_event(event("ilex","new-site-after-reload","a-further-discovery")).xp==80,"Retired semantic achievements stay exhausted across reload while new discoveries still progress")
	var progressed_json := JSON.stringify(x.serialize(),"",true,true)
	check(copy.restore(JSON.parse_string(progressed_json)) and JSON.stringify(copy.serialize(),"",true,true)==progressed_json,"A progressed memory-filled registry preserves exact full-precision JSON through parse, restore and serialize")
	var clean: Dictionary=x.serialize()
	var controls_rejected := true
	for code in range(1,32): controls_rejected=not x.remember("ilex","control","target","before"+String.chr(code)+"after") and controls_rejected
	check(controls_rejected and not x.remember("ilex","control","target",String.chr(127)) and x.remember("ilex","unicode","🌆","A journey through Ω city.",.6),"Native text validation still rejects every representable control character and preserves Unicode memories")
	clean=x.serialize()
	for mutation: String in ["time","xp","population","respawn","extra","receipt","receipt uppercase","receipt nonhex"]:
		var invalid: Dictionary=clean.duplicate(true)
		match mutation:
			"time": invalid.world_seconds=-1
			"xp": invalid.records.ilex.experience=-1
			"population": invalid.slots["hub/ilex"]="missing"
			"respawn": invalid.records.ilex.respawn.position=[NAN,0,0]
			"extra": invalid.unexpected=true
			"receipt": invalid.records.ilex.event_bloom="broken"
			"receipt uppercase": invalid.records.ilex.event_bloom="F".repeat(Registry.BLOOM_BYTES*2)
			"receipt nonhex": invalid.records.ilex.event_bloom="g".repeat(Registry.BLOOM_BYTES*2)
		check(not x.restore(invalid) and x.serialize()==clean,"Malformed "+mutation+" state rejects atomically")
	var too_many: Array[Dictionary]=[]
	for i in range(Registry.MAX_ACTIVE+1): too_many.append(row("region/"+str(i),"region/"+str(i)))
	check(not bad.bootstrap(too_many) and bad.records.is_empty(),"Active population cap prevents uncontrolled logical spawning")
	var history: RefCounted=accelerated()
	history.bootstrap(initial_rows)
	check(history.advance_to(Registry.MAX_REPLACEMENTS*10).size()==Registry.MAX_REPLACEMENTS and history.records.size()==Registry.MAX_REPLACEMENTS+1 and history.active_ids().size()==1,"The maximum permitted expiration batch remains finite and population-neutral")
	var census: RefCounted=accelerated()
	too_many.resize(Registry.MAX_ACTIVE)
	check(census.bootstrap(too_many) and census.advance_to(10).size()==Registry.MAX_ACTIVE and census.records.size()==Registry.MAX_ACTIVE*2 and census.active_ids().size()==Registry.MAX_ACTIVE,"One full active census can expire together without stalling the authoritative world clock")
	print("Code Form registry: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
