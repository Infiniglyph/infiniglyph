extends SceneTree
const Needs=preload("res://scripts/code_form_needs.gd")
const Wardrobe=preload("res://scripts/code_form_wardrobe.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
const Inventory=preload("res://scripts/inventory.gd")
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run():
	var state={"hunger":.5,"thirst":.5,"vitality":1000.0}
	Needs.advance(state,100)
	check(state.vitality==1000 and state.hunger>.5 and state.thirst>state.hunger,"Food and water decay independently without HP loss before red")
	state={"hunger":.8,"thirst":.8,"vitality":1000.0}
	Needs.advance(state,10)
	check(state.vitality==970,"Red food and water apply bounded, analytic survival damage")
	state={"hunger":.79,"thirst":.79,"vitality":1000.0}
	Needs.advance(state,20)
	check(is_equal_approx(state.vitality,996),"Crossing into red damages only the elapsed time actually spent there")
	Needs.consume(state,true)
	check(state.thirst==0 and state.hunger>.79,"A drink restores water without satisfying hunger")
	Needs.consume(state,false,60)
	check(state.hunger==0 and state.vitality==1000,"An owned meal satisfies food and heals within normal HP bounds")
	var store=Inventory.new(); store.owner_id="resident:fixture"; root.add_child(store)
	state={"attire_issued":false,"uniform_issued":false}
	check(Wardrobe.issue(store,state) and store.items.size()==4 and store.equipment.size()==4,"A native receives four actual equipped Civic starter items")
	var civic:=true
	for item: Resource in store.items.values(): civic=civic and Wardrobe.Equipment.get_item(item.item_type_id).name.begins_with("Civic ") and item.custom_properties.issue=="civic_starter"
	check(civic,"Every issued starter piece comes from the Civic collection")
	check(not Wardrobe.issue(store,state) and store.items.size()==4,"Revisiting the issuer cannot duplicate starter clothes")
	var initial=Wardrobe.drip(store)
	check(initial>0 and initial<100,"Clothing Drip is derived from the real equipped catalog items")
	check(Wardrobe.issue(store,state,true) and store.items.size()==8 and store.equipped_item(&"body").item_type_id==StringName(Wardrobe.UNIFORM.body),"Dark Box issues a distinct real uniform using the shared wardrobe")
	check(not Wardrobe.issue(store,state,true),"Uniform issuance is durable rather than a free resupply")
	var body_types: Dictionary={}
	var stable:=true
	for i in range(16):
		var resident=Inventory.new(); resident.owner_id="resident:body_pool/"+str(i); root.add_child(resident)
		var issued={"attire_issued":false,"uniform_issued":false}
		Wardrobe.issue(resident,issued)
		var body: Resource=resident.equipped_item(&"body")
		body_types[body.item_type_id]=true
		var saved_outfit=resident.serialize()
		stable=stable and resident.restore(JSON.parse_string(JSON.stringify(saved_outfit))) and not Wardrobe.issue(resident,issued) and resident.equipped_item(&"body").instance_id==body.instance_id
		resident.free()
	check(body_types.size()==4 and body_types.keys().all(func(type): return type in Wardrobe.BODY_STARTERS),"Residents receive all four requested Civic body designs")
	check(stable,"Each resident keeps the same issued body and item identity after reload")
	var fixed=Inventory.new(); fixed.owner_id="resident:fixed_civic"; root.add_child(fixed)
	var old_body: Resource=Wardrobe.Catalog.create(StringName(Wardrobe.STARTERS.body))
	old_body.custom_properties={"issued_to":fixed.owner_id,"issue":"civic_starter","quality":1.2}
	fixed.add_item(old_body); fixed.assign(&"body",old_body.instance_id)
	var fixed_state={"attire_issued":true,"uniform_issued":false}
	check(Wardrobe.issue(fixed,fixed_state) and fixed.items.size()==1 and fixed.equipped_item(&"body").item_type_id==Wardrobe.starter_type("body",fixed.owner_id) and fixed.equipped_item(&"body").custom_properties.quality==1.2,"Existing identical Civic starters join the pool once while preserving quality")
	check(not Wardrobe.issue(fixed,fixed_state),"The existing starter migration does not keep rerolling or granting items")
	fixed.free()
	var legacy=Inventory.new(); legacy.owner_id="resident:legacy"; root.add_child(legacy)
	for slot: String in Wardrobe.LEGACY_STARTERS:
		var old: Resource=Wardrobe.Catalog.create(StringName(Wardrobe.LEGACY_STARTERS[slot]))
		old.custom_properties={"issued_to":legacy.owner_id,"issue":"braided_starter","quality":1.2}
		legacy.add_item(old); legacy.assign(StringName(slot),old.instance_id)
	var sold: Resource=legacy.take_item(legacy.equipped_item(&"head").instance_id)
	var earned: Resource=Wardrobe.Catalog.create(StringName(Wardrobe.UNIFORM.body)); legacy.add_item(earned); legacy.assign(&"body",earned.instance_id)
	var purchased: Resource=Wardrobe.Catalog.create(StringName(Wardrobe.LEGACY_STARTERS.hands)); legacy.add_item(purchased)
	var issued_state={"attire_issued":true,"uniform_issued":false}
	check(Wardrobe.issue(legacy,issued_state) and legacy.items.size()==5,"Older issued Braided pieces exchange one-for-one without duplicating inventory")
	check(legacy.equipped_item(&"legs").item_type_id==StringName(Wardrobe.STARTERS.legs) and legacy.equipped_item(&"legs").custom_properties.quality==1.2,"An existing resident wears the Civic replacement with its owned quality preserved")
	check(legacy.equipped_item(&"body")==earned and legacy.get_item(purchased.instance_id)==purchased and legacy.equipped_item(&"head")==null,"Migration preserves purchased outfits, unissued Braided pieces and sold-piece losses")
	var migrated=legacy.serialize()
	check(legacy.restore(JSON.parse_string(JSON.stringify(migrated))) and not Wardrobe.issue(legacy,issued_state),"Reloading a Civic wardrobe cannot repeat the exchange or refill sold clothes")
	var uniform_body: Resource=store.equipped_item(&"body")
	check(not Wardrobe.issue(store,state) and store.equipped_item(&"body")==uniform_body and uniform_body.item_type_id==StringName(Wardrobe.UNIFORM.body),"Dark Box keeps the approved uniform after ordinary starter migration")
	check(not legacy.serialize().is_empty() and sold.owner_id.is_empty(),"The exchange leaves normal inventory ownership and persistence valid")
	legacy.free()
	var economy=Economy.new(); root.add_child(economy); economy.configure("human",["native"]); economy.bless_cycle(0,["native"])
	economy.register_faction("exploration")
	var funds={"business:guild":20000,"business:tavern":10000,"faction:exploration":15000}
	var before=economy.issued_total
	check(economy.issue_institution_influx(funds) and economy.issued_total==before+45000,"The explicit institutional influx adds real audited spendable capital")
	check(economy.balance("business:guild")==20000 and economy.balance(economy.player_account)==0,"Guild funding does not enter the visiting player's wallet")
	var saved=JSON.parse_string(JSON.stringify(economy.serialize()))
	check(economy.restore(saved) and not economy.issue_institution_influx(funds),"JSON reload cannot repeat institutional funding")
	for i in range(140): economy.transfer("business:guild","business:tavern",1,"Fixture transfer")
	saved=JSON.parse_string(JSON.stringify(economy.serialize()))
	check(saved.audit_base.institution_influx and economy.restore(saved) and not economy.issue_institution_influx(funds),"Compacted audit history preserves the one-time institutional receipt")
	var legacy_ledger=saved.duplicate(true); legacy_ledger.version=5; legacy_ledger.audit_base.erase("institution_influx")
	# This synthetic legacy contains the already-folded grant in supply/balances;
	# clearing its receipt models a real older ledger, which can receive its first rollout.
	check(economy.restore(legacy_ledger) and economy.issue_institution_influx(funds),"Version-five economies migrate and receive the new institutional rollout")
	var pantry=economy.npc_store("native")
	economy.warm_capture()
	var prior=economy.capture_values()
	check(economy.npc_buy_food("native",&"electron_meal") and prior.npc_stores.native.items.is_empty(),"A cached inventory capture stays frozen while a real purchase changes live goods")
	check(economy.capture_values()==economy.serialize(),"A committed inventory change invalidates its cache before the next checkpoint")
	var Registry=load("res://scripts/code_form_registry.gd")
	var registry=Registry.new()
	var rows: Array[Dictionary]=[{"slot":"hub/native","id":"native","name":"Native","occupation":"courier","personality":"friendly","respawn":{"location":"overworld","position":[0.0,.2,0.0],"yaw":0.0}}]
	registry.bootstrap(rows)
	registry.warm_capture()
	var frozen=registry.capture_values()
	registry.remember("native","work","fixture","Completed a real errand.",.5)
	registry.relate("native","friend",.4)
	registry.set_goal("native","eat","tavern")
	registry.grant_xp("native",125)
	check(frozen.records.native.memories.is_empty() and frozen.records.native.relationships.is_empty() and frozen.records.native.experience==0,"A frozen registry capture retains its pre-mutation memories, relationships and XP")
	check(registry.capture_values()==registry.serialize(),"Every normal registry mutation refreshes its frozen snapshot before the next capture")
	registry.restore(registry.serialize())
	check(registry.capture_values()==registry.serialize(),"Checkpoint restoration invalidates all old frozen row copies")
	var raw=store.capture_values()
	check(raw==store.serialize(),"The fast item capture and strict serializer produce the same owned values")
	var item: Resource=store.items.values()[0]
	item.custom_properties.quality=2.0
	check(not raw.items[0].custom_properties.has("quality"),"Nested item properties are privately copied before worker handoff")
	var Visual=load("res://scripts/resident_visual.gd")
	var first=Visual.new(); var second=Visual.new(); root.add_child(first); root.add_child(second)
	first.sync_clothing(store); second.sync_clothing(store)
	check(first.attire.figure.mesh.get_surface_count()==2 and first.attire.skeleton.get_bone_count()==11,"The fitted civilian outfit stays within two skinned surfaces and eleven rigid mounts")
	check(first.attire.figure.mesh==second.attire.figure.mesh,"Repeated civilian outfits share their native GPU geometry")
	check(first.attire.skeleton.get_bone_pose(4).origin.y>.8 and first.attire.skeleton.get_bone_pose(1).origin.y>.8 and first.attire.skeleton.get_bone_pose(8).origin.y>1.4,"Fitted headwear uses the torso frame and sleeves follow the real shoulder contacts")
	first.free(); second.free()
	store.free(); economy.free()
	print("CIVILIAN NEEDS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
