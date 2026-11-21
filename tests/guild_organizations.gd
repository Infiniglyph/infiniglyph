extends SceneTree
const Model=preload("res://scripts/universal_quests.gd")
const Organizations=preload("res://scripts/guild_organizations.gd")
const Economy=preload("res://scripts/civilian_economy.gd")
var checks:=0
var failures:=0
var model: RefCounted
var economy: Node
var people: Dictionary={"player":{"kind":"player","active":true}}
var allow_politics:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func setup(target: RefCounted) -> void:
	target.configure({"identity":func(id: String): return people.get(id,{}),"authorize":func(_op: String,_row: Dictionary): return true,"finance":finance,"organization_finance":economy.organization_operation,"organization_authorize":func(_op: String,_row: Dictionary): return allow_politics})
func finance(row: Dictionary) -> bool:
	match row.operation:
		"reserve": return economy.reserve_contract(row.quest_id,row.source,int(row.amount))
		"pay": return economy.settle_contract(row.quest_id,"human" if row.beneficiary=="player" else row.beneficiary,row.service,row.legality)
		"refund": return economy.refund_contract(row.quest_id)
	return false
func run() -> void:
	var ids: Array=[]
	for n in range(24):
		var id:="native_"+str(n).pad_zeros(2)
		ids.append(id); people[id]={"active":true,"kind":"code_form","level":n+1,"motivations":{"wealth":.6,"knowledge":.8,"duty":.7}}
	economy=Economy.new(); root.add_child(economy)
	check(economy.configure("human",ids) and economy.bless_cycle(0,ids),"Real finite economy initializes")
	for faction: String in Organizations.GENERALISTS:
		economy.register_faction(faction); economy.transfer("resident:"+ids[0],"faction:"+faction,20,"Seed funds")
	model=Model.new(); setup(model)
	model.join("player","exploration")
	var total: int=economy.issued_total
	check(model.bootstrap_organizations(ids,0),"Twelve guilds bootstrap using existing coins")
	var org: RefCounted=model.organizations
	check(org.factions.size()==4 and org.guilds.size()==12 and economy.guilds.size()==12,"Exactly four factions and twelve finite treasuries exist")
	for faction: String in org.factions:
		var rows: Array=org.guilds_for_faction(faction)
		var generalists:=0
		var coins:=0
		for row: Dictionary in rows:
			if row.classification=="generalist": generalists+=1
			coins+=economy.balance(row.treasury)
		check(rows.size()==3 and generalists==1 and coins==20,"One generalist and two specialists share real "+faction+" capital")
	check(org.is_member("player","adventurers_guild") and model.is_member("player","exploration"),"Legacy faction membership migrates into its generalist")
	check(org.guild("dark_box").name=="Dark Box" and org.guild("lit_mob").name=="Lit Mob" and org.guild("wayfarer_logistics").name=="Wayfarer Logistics","Founding stable IDs retain specified names")
	check(org.set_faction_headquarters("security","city/security_hall") and org.factions.security.headquarters=="city/security_hall" and org.guild("dark_box").headquarters.is_empty(),"Faction headquarters are independent of their affiliated guild headquarters")
	var prior_halls: Dictionary=org.serialize()
	for faction: Dictionary in prior_halls.factions.values(): faction.erase("headquarters")
	check(Organizations.validate(prior_halls).factions.security.headquarters.is_empty(),"Older nine-field faction records migrate to an unassigned headquarters")
	var q: String=model.create_contract("exploration_discovery","guild/cartographers","guild:cartographers",{"guild_id":"cartographers","target_id":"city/roof","reward":4},0)
	check(not q.is_empty() and model.available("player","exploration",true).size()==1,"Nonmembers can inspect funded specialist contracts")
	check(not model.accept(q,"player",0) and model.join_guild("player","cartographers") and model.accept(q,"player",0),"Issuer guild membership is required despite existing faction membership")
	check(model.leave_guild("player","cartographers") and org.is_member("player","adventurers_guild"),"Leaving one guild preserves independent memberships")
	var founding_history: Dictionary=org.guild("adventurers_guild").history[0].duplicate()
	for n in range(80): model.leave_guild("player","adventurers_guild"); model.join_guild("player","adventurers_guild")
	check(org.guild("adventurers_guild").history[0]==founding_history,"Repeated minor membership changes cannot erase founding history")
	check(not model.join_guild("player","veil") and model.available("player","underworld",true).is_empty(),"Private guild membership and contracts remain concealed")
	check(model.introduce("player",ids[3]) and model.join_guild("player","veil"),"Verified private introduction grants a specific Underworld membership")
	var row: Dictionary=org.guild("dark_box")
	var old: String=row.leader
	var candidate: String=ids[20]
	model.join_guild(candidate,"dark_box")
	var state_before: Dictionary=economy.serialize()
	check(org.change_leader("dark_box",candidate,old) and org.guild("dark_box").leader==candidate and economy.serialize()==state_before,"Guild resignation changes only leadership and retains treasury")
	var faction_leader: String=org.factions.security.leader
	check(faction_leader!=candidate,"Faction leadership is independent of guild leadership")
	allow_politics=true
	check(org.change_faction_leader("security",candidate,faction_leader) and org.guild("dark_box").leader==candidate,"Faction leadership can change independently")
	people[candidate].active=false; model.retire(candidate)
	check(org.guild("dark_box").leader!=candidate and org.factions.security.leader!=candidate and not org.guild("dark_box").history.is_empty(),"Lifetime retirement immediately succeeds both positions with history")
	people[candidate].active=true
	var founder: String=ids[18]
	check(org.found(founder,"Unfunded","commerce","logistics").is_empty(),"A random unsupported founding attempt cannot create a guild")
	for supporter: String in [ids[19],ids[21],ids[22]]: org.support(founder,supporter,"commerce","logistics")
	var founded: String=org.found(founder,"The New Route","commerce","logistics",30)
	check(not founded.is_empty() and economy.balance("guild:"+founded)==30 and org.guild(founded).members.size()==4,"Three committed active supporters and real funds establish an independent guild")
	model.advance_to(1)
	var restored:=Model.new(); setup(restored)
	check(restored.restore(JSON.parse_string(JSON.stringify(model.serialize()))) and restored.organizations.guild(founded).name=="The New Route","Dynamic guild, memberships, leaders and history survive strict JSON restore")
	var corrupt: Dictionary=model.serialize(); corrupt.organizations.guilds[founded].leader="unknown"
	check(not restored.restore(corrupt),"Invalid leadership references reject atomically")
	check(org.merge(founded,"trade_united",founder) and org.guild(founded).status=="merged" and economy.balance("guild:"+founded)==0,"Compatible authorized merger moves finite assets and preserves old identity")
	model.advance_to(2)
	check(not org.guild(founded).history.is_empty() and org.guild("trade_united").members.has(founder),"Merger history and surviving membership are retained")
	check(org.dissolve("cartographers",org.guild("cartographers").leader),"A founding guild may dissolve")
	model.advance_to(3)
	check(model.instances[q].status=="failed" and economy.contracts[q].status=="refunded","Dissolution refunds outstanding member contracts without a payout")
	org.review_cursor=org.guilds.keys().find("cartographers"); org.next_review=3
	model.advance_to(4)
	check(economy.balance("guild:cartographers")==0 and economy.balance("faction:exploration")>0,"A bounded later review sweeps refunded obligations from a dissolved historical treasury")
	var snapshot: Dictionary=economy.serialize()
	check(snapshot.version==6 and not Economy.validate(snapshot).is_empty() and snapshot.issued_total==total,"Economy v5 validates the unchanged finite coin supply")
	var legacy: Dictionary=snapshot.duplicate(true)
	# Build a genuine empty-org legacy ledger before account registration.
	var old_economy:=Economy.new(); root.add_child(old_economy); old_economy.configure("human",ids); old_economy.bless_cycle(0,ids)
	legacy=old_economy.serialize(); legacy.version=3; legacy.erase("guilds"); legacy.audit_base.erase("starter_influx"); legacy.audit_base.erase("institution_influx")
	check(Economy.validate(legacy).version==6 and Economy.validate(legacy).guilds.is_empty(),"Existing v3 ledgers migrate without inventing balances")
	var before_failed: Dictionary=economy.serialize()
	check(not economy.organization_operation({"operation":"found","guild_id":"unfunded","source":"resident:"+ids[0],"amount":100000}) and economy.serialize()==before_failed,"Failed founding leaves no partial account, transfer or audit mutation")
	var legacy_model:=Model.new(); setup(legacy_model)
	legacy_model.join("player","security")
	var legacy_quest: Dictionary=legacy_model.serialize()
	legacy_quest.version=1; legacy_quest.erase("organizations")
	var migrated: Dictionary=Model.validate(legacy_quest)
	check(not migrated.is_empty() and migrated.version==2 and migrated.memberships.player==["security"],"V1 faction state migrates without silently dropping memberships")
	var corrupt_org: Dictionary=org.serialize(); corrupt_org.guilds.dark_box.treasury="guild:other"
	check(Organizations.validate(corrupt_org).is_empty(),"An organization cannot redirect its treasury reference")
	check(org.relate("dark_box","iron_wardens",.8) and org.guild("dark_box").history.back().type=="alliance","Persistent major alliances have compact institutional history")
	var begin:=Time.get_ticks_usec()
	for tick in range(2000): org.advance_to(3+float(tick))
	print("Two thousand bounded organization ticks: ",(Time.get_ticks_usec()-begin)/1000.0," ms")
	check(org.guilds.size()==13,"Lightweight background review does not spontaneously multiply guilds")
	old_economy.free(); economy.free()
	print("Guild organizations: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
