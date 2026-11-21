extends SceneTree
const Economy=preload("res://scripts/civilian_economy.gd")
const Policy=preload("res://scripts/code_form_starter_capital.gd")
class Positions extends RefCounted:
	var guilds: Dictionary={}
	var factions: Dictionary={}
	var businesses: Dictionary={}
	var employments: Dictionary={}
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func coins(economy: Node) -> int:
	var total:=0
	for amount: int in economy.balances.values(): total+=amount
	return total
func run() -> void:
	check(Policy.amount({})==500 and Policy.amount({"occupation":"courier"})==800 and Policy.amount({"occupation":"merchant"})==1200,"Residents, routine workers and merchants have distinct starter grants")
	check(Policy.amount({}, {"business_owner":true})==1800 and Policy.amount({}, {"guild_leader":true})==2400 and Policy.amount({}, {"faction_leader":true})==3200,"Actual ownership and offices determine higher grants")
	check(Policy.amount({"level":4},{"employed":true})==950 and Policy.amount({"level":100},{"faction_leader":true,"guild_leader":true,"business_owner":true})==3700,"Experience adds a capped bonus; overlapping offices do not stack grants")
	check(Policy.amount({"id":"replacement","slot":"service/tavern_bartender"})==1200,"Service roles work for replacement identities as well as original names")
	var people: Dictionary={}
	var ids: Array=["citizen","worker","merchant","owner","guild_head","faction_head"]
	for id: String in ids: people[id]={"id":id,"active":true,"occupation":"resident","level":1}
	people.merchant.occupation="merchant"
	var positions:=Positions.new()
	positions.guilds={"g":{"status":"active","leader":"guild_head"},"old":{"status":"dissolved","leader":"citizen"}}
	positions.factions={"f":{"leader":"faction_head"}}
	positions.businesses={"b":{"status":"active","owner":"owner"},"ended":{"status":"closed","owner":"citizen"}}
	positions.employments={"j":{"status":"active","employee":"worker","career":"courier"},"old":{"status":"ended","employee":"citizen","career":"merchant"}}
	var payouts:=Policy.payouts(people,ids,positions,positions)
	check(payouts=={"citizen":500,"worker":800,"merchant":1200,"owner":1800,"guild_head":2400,"faction_head":3200},"One indexed allocation uses only current roles, businesses and governance")
	var economy:=Economy.new(); root.add_child(economy)
	check(economy.configure("visitor",ids) and economy.bless_cycle(0,ids),"Fixture starts with the regular equal blessing")
	var before:=economy.serialize()
	var bad:=payouts.duplicate(); bad.erase("citizen"); bad.visitor=500
	check(not economy.issue_starter_influx(bad) and economy.serialize()==before,"Outsiders and incomplete censuses cannot receive an influx")
	bad=payouts.duplicate(); bad.worker=.5
	check(not economy.issue_starter_influx(bad) and economy.serialize()==before,"Malformed amounts reject the entire batch before any balance changes")
	economy.host_enabled=false
	check(not economy.issue_starter_influx(payouts),"Only the host may issue starter capital")
	economy.host_enabled=true; economy.external_transaction_guard=func(): return true
	check(not economy.issue_starter_influx(payouts),"An in-progress external transaction blocks issuance")
	economy.external_transaction_guard=Callable()
	var commerce: Array=[]; var reentrant: Array=[]
	economy.commerce_committed.connect(func(event: Dictionary): commerce.append(event))
	economy.changed.connect(func(): reentrant.append(economy.issue_starter_influx(payouts)))
	check(economy.issue_starter_influx(payouts) and economy.starter_influx_applied,"The authorized influx commits once for all current citizens")
	check(economy.issued_total==10500 and coins(economy)==10500 and economy.balance("resident:citizen")==600 and economy.balance("resident:faction_head")==3300 and economy.balance(economy.player_account)==0,"Different grants add spendable coins and accurately increase the audited supply")
	check(commerce.is_empty() and reentrant==[false],"Grants cannot farm economic XP or reenter the issuer")
	check(not economy.issue_starter_influx(payouts),"Repeated ticks cannot repeat the influx")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(economy.serialize()))
	check(not Economy.validate(saved).is_empty() and economy.restore(saved) and not economy.issue_starter_influx(payouts),"JSON save/load retains the one-time receipt without replaying payouts")
	bad=saved.duplicate(true); bad.journal.append(bad.journal[-1].duplicate(true)); bad.sequence+=1; bad.journal[-1].sequence=bad.sequence
	check(Economy.validate(bad).is_empty(),"Strict replay rejects a second influx receipt")
	bad=saved.duplicate(true); bad.journal[-1].payouts.worker+=1
	check(Economy.validate(bad).is_empty(),"Strict replay rejects payouts inconsistent with saved balances")
	# Bound journal history, then prove its compacted base still prevents minting.
	for i in range(140): economy.transfer("resident:faction_head","resident:citizen",1,"Fixture transfer")
	saved=JSON.parse_string(JSON.stringify(economy.serialize()))
	check(saved.audit_base.starter_influx and economy.restore(saved) and not economy.issue_starter_influx(payouts) and coins(economy)==10500,"Compaction preserves the durable receipt and total supply")
	var legacy:=before.duplicate(true); legacy.version=4; legacy.audit_base.erase("starter_influx"); legacy.audit_base.erase("institution_influx")
	var upgraded:=Economy.validate(legacy)
	check(not upgraded.is_empty() and upgraded.version==6 and not upgraded.audit_base.starter_influx and economy.restore(legacy) and economy.issue_starter_influx(payouts),"Existing v4 saves migrate and receive their missing grant exactly once")
	check(economy.retire_code_form("citizen") and economy.enroll_code_form("successor",0) and economy.balance("resident:successor")==0 and not economy.issue_starter_influx(payouts),"The rollout is global; later births keep ordinary blessing rules")
	check(economy.bless_cycle(1,economy.active_ids) and coins(economy)==11100 and not Economy.validate(economy.serialize()).is_empty(),"Regular equal blessings and strict validation continue after the influx")
	economy.queue_free(); await process_frame
	print("Starter capital: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
