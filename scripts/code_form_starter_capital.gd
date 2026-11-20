extends RefCounted
## One-time rollout policy, evaluated against current authoritative positions.
## These are additive grants, never wallet targets or recurring salaries.
const RESIDENT:=500
const WORKER:=800
const MERCHANT:=1200
const BUSINESS_OWNER:=1800
const GUILD_LEADER:=2400
const FACTION_LEADER:=3200
const EXPERIENCE_STEP:=50
const EXPERIENCE_CAP:=500
const ROUTINE_JOBS:=["courier","lamp tender","gardener","driver","patrol officer","security officer"]
const TRADE_JOBS:=["merchant","trader","bartender","shopkeeper","innkeeper","guild clerk"]

static func amount(person: Dictionary,positions: Dictionary={}) -> int:
	var role:=String(person.get("occupation","resident")).to_lower()
	var base:=RESIDENT
	if role in ROUTINE_JOBS or positions.get("employed",false): base=WORKER
	if role in TRADE_JOBS or positions.get("merchant",false) or String(person.get("slot","")) in ["service/guild_receptionist","service/tavern_bartender"]: base=maxi(base,MERCHANT)
	if positions.get("business_owner",false): base=maxi(base,BUSINESS_OWNER)
	if positions.get("guild_leader",false): base=maxi(base,GUILD_LEADER)
	if positions.get("faction_leader",false): base=maxi(base,FACTION_LEADER)
	return base+mini(EXPERIENCE_CAP,maxi(0,int(person.get("level",1))-1)*EXPERIENCE_STEP)

static func payouts(people: Dictionary,active: Array,organizations: RefCounted,careers: RefCounted) -> Dictionary:
	# Build role indexes once. Do not scan all jobs/businesses for each citizen.
	var positions: Dictionary={}
	for id: String in active: positions[id]={}
	for guild: Dictionary in organizations.guilds.values():
		if guild.status=="active" and positions.has(guild.leader): positions[guild.leader].guild_leader=true
	for faction: Dictionary in organizations.factions.values():
		if positions.has(faction.leader): positions[faction.leader].faction_leader=true
	for business: Dictionary in careers.businesses.values():
		if business.status=="active" and positions.has(business.owner): positions[business.owner].business_owner=true
	for job: Dictionary in careers.employments.values():
		if job.status=="ended" or not positions.has(job.employee): continue
		positions[job.employee].employed=true
		if job.career in ["merchant","trader","tavern_keeper","shopkeeper"]: positions[job.employee].merchant=true
	var result: Dictionary={}
	for id: String in active:
		if not people.get(id,{}).get("active",false): return {}
		result[id]=amount(people[id],positions[id])
	return result
