extends RefCounted
## Civilian identities only. Bodies, wallets and host event validation belong to
## adapters; this model never creates currency, combatants or player progression.
const MAX_ACTIVE := 2048
const MAX_RECORDS := 16384
const MAX_REPLACEMENTS := MAX_ACTIVE
const MAX_MEMORIES := 24
const MAX_RELATIONSHIPS := 24
const MAX_NOVELTY := 128
const BLOOM_BYTES := 1024
const MAX_TIME := 1.0e15
const PERSONALITIES := ["curious","friendly","pragmatic","dismissive","indifferent"]
const MOTIVATIONS := ["survival","security","wealth","social","knowledge","mastery","novelty","loyalty"]
const EVENT_TYPES := ["combat","exploration","discovery","crafting","economic","social","guild","construction","organization"]
const DEFAULT_CONFIG := {"real_seconds_per_day":3600.0,"day_seconds":86400.0,"days_per_year":365,"lifetime_years":100.0,"level_years":100.0,"max_level":100,"blessing_days":30,"blessing_amount":100,"offline_cap_seconds":21600.0,"xp_step":100,"rarity_xp":{"common":8,"uncommon":24,"rare":80,"epic":240,"legendary":800,"unique":2400}}
static var _control_chars: RegEx = _pattern("[\\x00-\\x1f\\x7f]")
static var _bloom_hex: RegEx = _pattern("\\A[0-9a-f]*\\z")
var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
var records: Dictionary = {}
var slots: Dictionary = {}
var world_seconds := 0.0
var replacement_serial := 0
var last_error := ""
var _active_census: Array[String] = []
var _census_dirty := true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and float(value)==floorf(float(value))

static func _pattern(expression: String) -> RegEx:
	var pattern := RegEx.new()
	pattern.compile(expression)
	return pattern

static func _text(value: Variant, limit: int, empty: bool = false) -> bool:
	if not value is String or value.length()>limit or (not empty and value.is_empty()): return false
	return _control_chars.search(value)==null

static func _id(value: Variant) -> bool:
	return _text(value,64) and not ":" in value and value.to_lower() not in ["player","boss","enemy","monster","kyren","greefer","ahkmet","lorai","sparring_partner"]

static func _slot(value: Variant) -> bool:
	if not _text(value,80): return false
	var pieces: PackedStringArray = value.split("/",false)
	return pieces.size()==2 and pieces[0] in ["hub","region","driver","service"] and _id(pieces[1])

static func _initial_id(slot: String) -> String:
	return slot.get_slice("/",1) if slot.begins_with("hub/") or slot.begins_with("service/") else slot

static func _respawn(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=3 or not _text(input.get("location"),128): return {}
	if not input.get("position") is Array or input.position.size()!=3 or not _number(input.get("yaw"),-1.0e6,1.0e6): return {}
	var position: Array[float] = []
	for value: Variant in input.position:
		if not _number(value,-1000000,1000000): return {}
		position.append(float(value))
	return {"location":String(input.location),"position":position,"yaw":float(input.yaw)}

static func _settings(input: Variant) -> Dictionary:
	if not input is Dictionary: return {}
	var result := DEFAULT_CONFIG.duplicate(true)
	for key: Variant in input:
		if not key is String or not result.has(key): return {}
		result[key] = input[key]
	for key: String in ["real_seconds_per_day","day_seconds","lifetime_years","level_years"]:
		if not _number(result[key],0.000000001,1.0e9): return {}
		result[key] = float(result[key])
	for key: String in ["days_per_year","blessing_days","blessing_amount","xp_step","max_level"]:
		var limit := 100 if key=="max_level" else (100000 if key=="blessing_amount" else 1000000)
		if not _integer(result[key],1,limit): return {}
		result[key] = int(result[key])
	if not _number(result.offline_cap_seconds,0,604800): return {}
	result.offline_cap_seconds = float(result.offline_cap_seconds)
	if result.day_seconds*result.days_per_year*(result.lifetime_years+result.level_years*(result.max_level-1))>MAX_TIME*.1: return {}
	if not result.rarity_xp is Dictionary or result.rarity_xp.size()!=DEFAULT_CONFIG.rarity_xp.size(): return {}
	var rewards: Dictionary = {}
	for rarity: String in DEFAULT_CONFIG.rarity_xp:
		if not _integer(result.rarity_xp.get(rarity),0,1000000): return {}
		rewards[rarity] = int(result.rarity_xp[rarity])
	result.rarity_xp = rewards
	return result

func _prepare() -> bool:
	var settings := _settings(config)
	if settings.is_empty(): last_error="Invalid Code Form configuration"; return false
	config = settings
	last_error = ""
	return true

func _year() -> float: return float(config.day_seconds)*float(config.days_per_year)
func _initial_life() -> float: return _year()*float(config.lifetime_years)
static func _threshold(level: int, settings: Dictionary) -> int: return int(settings.xp_step)*level*(level-1)/2

func _new_record(row: Dictionary, born: float, generation: int = 0, serial: int = 0) -> Dictionary:
	var weights: Dictionary = {}
	for key: String in MOTIVATIONS: weights[key] = float(150+absi((String(row.id)+key).hash())%850)/1000.0
	return {"id":String(row.id),"slot":String(row.slot),"name":String(row.name),"occupation":String(row.occupation),"personality":String(row.personality),"respawn":row.respawn.duplicate(true),"motivations":weights,"current_goal":"idle","goal_target":"","guild":"","level":1,"experience":0,"expires_at":born+_initial_life(),"born_at":born,"retired_at":0.0,"active":true,"memories":[],"relationships":{},"novelty":{},"event_bloom":"","generation":generation,"serial":serial,"replaced_by":""}

func bootstrap(rows: Array[Dictionary]) -> bool:
	if not _prepare(): return false
	var seen: Dictionary = {}
	var additions: Array[Dictionary] = []
	for row: Dictionary in rows:
		if row.size()!=6 or not _slot(row.get("slot")) or not _id(row.get("id")) or row.id!=_initial_id(row.slot) or not _text(row.get("name"),80) or not _text(row.get("occupation"),64) or not _text(row.get("personality"),32) or _respawn(row.get("respawn")).is_empty() or seen.has(row.slot):
			last_error="Invalid or duplicate civilian bootstrap row"; return false
		seen[row.slot] = true
		if slots.has(row.slot):
			if not records.has(row.id) or records[row.id].slot!=row.slot: last_error="Civilian slot identity conflict"; return false
			continue # Loading or rebuilding a body cannot resurrect its predecessor.
		if records.has(row.id): last_error="Duplicate civilian identity"; return false
		var clean := row.duplicate(true)
		clean.respawn = _respawn(row.respawn)
		additions.append(clean)
	if slots.size()+additions.size()>MAX_ACTIVE or records.size()+additions.size()>MAX_RECORDS: last_error="Civilian registry capacity reached"; return false
	if not additions.is_empty() and world_seconds+_initial_life()<=world_seconds: last_error="Lifetime is below clock precision"; return false
	for row: Dictionary in additions:
		records[row.id] = _new_record(row,world_seconds)
		slots[row.slot] = row.id
	if not additions.is_empty(): _census_dirty=true
	return true

func active_ids() -> Array[String]:
	if _census_dirty:
		_active_census.assign(slots.values())
		_active_census.sort()
		_census_dirty=false
	# Callers may sort/shuffle a census without mutating this shared index.
	return _active_census.duplicate()

func for_slot(slot: String) -> Dictionary: return records.get(slots.get(slot,""),{})
func remaining_lifetime(id: String) -> float:
	var row: Dictionary = records.get(id,{})
	return maxf(0,float(row.expires_at)-world_seconds) if row.get("active",false) else 0.0

func advance_to(target: float) -> Array[Dictionary]:
	var replacements: Array[Dictionary] = []
	if not _prepare(): return replacements
	if not _number(target,world_seconds,MAX_TIME): last_error="World clock must advance monotonically"; return replacements
	var required := 0
	var order: Array[String] = []
	for slot: String in slots:
		var row: Dictionary = for_slot(slot)
		if row.expires_at<=target:
			# A correction discovered today may revoke lifetime that was already
			# spent. Retire once today; never invent retroactive generations.
			var effective_expiry:=maxf(world_seconds,float(row.expires_at))
			var count: float = 1+floor((target-effective_expiry)/_initial_life())
			if count>MAX_REPLACEMENTS-required or float(row.expires_at)+_initial_life()<=float(row.expires_at): last_error="World advance exceeds the %d-replacement batch limit" % MAX_REPLACEMENTS; return []
			required += int(count)
			order.append(slot)
			if required>MAX_REPLACEMENTS: last_error="World advance exceeds the %d-replacement batch limit" % MAX_REPLACEMENTS; return []
	if records.size()+required>MAX_RECORDS: last_error="Civilian historical capacity reached"; return []
	order.sort_custom(func(a: String,b: String): return for_slot(a).expires_at<for_slot(b).expires_at if for_slot(a).expires_at!=for_slot(b).expires_at else a<b)
	for slot: String in order:
		var old: Dictionary = for_slot(slot)
		while old.expires_at<=target:
			replacement_serial += 1
			var id := "cf_%d_%d" % [absi(slot.hash()),replacement_serial]
			var personality: String = PERSONALITIES[absi(id.hash())%PERSONALITIES.size()]
			if personality==old.personality: personality=PERSONALITIES[(PERSONALITIES.find(personality)+1)%PERSONALITIES.size()]
			var row := {"id":id,"slot":slot,"name":["Aster","Vela","Prism","Coda","Lumen","Nacre","Wren","Opal"][replacement_serial%8]+" "+str(replacement_serial),"occupation":old.occupation,"personality":personality,"respawn":old.respawn}
			var retirement:=maxf(world_seconds,float(old.expires_at))
			var next := _new_record(row,retirement,int(old.generation)+1,replacement_serial)
			old.retired_at=retirement
			old.active = false
			old.current_goal = "expired"
			old.goal_target = ""
			old.replaced_by = id
			old.novelty = {}
			old.event_bloom = ""
			old.memories.sort_custom(func(a: Dictionary,b: Dictionary): return a.importance>b.importance if a.importance!=b.importance else a.timestamp>b.timestamp)
			old.memories.resize(mini(4,old.memories.size()))
			records[id] = next
			slots[slot] = id
			replacements.append({"slot":slot,"old_id":String(old.id),"new_id":id})
			old = next
	world_seconds = target
	if not replacements.is_empty(): _census_dirty=true
	return replacements

func grant_xp(id: String, amount: int) -> int:
	if not _prepare() or not records.has(id) or not records[id].active or amount<=0 or amount>1000000000000: return 0
	var row: Dictionary = records[id]
	var before: int = row.level
	row.experience = mini(_threshold(config.max_level,config),int(row.experience)+amount)
	while row.level<config.max_level and row.experience>=_threshold(int(row.level)+1,config): row.level += 1
	var gained: int = row.level-before
	row.expires_at += gained*float(config.level_years)*_year()
	return gained

func reconcile_xp(id: String, legitimate_experience: int) -> Dictionary:
	var rejected:={"accepted":false,"xp_delta":0,"level_delta":0,"expires_at":0.0,"expired":false}
	if not _prepare() or not records.has(id) or not records[id].active or legitimate_experience<0 or legitimate_experience>_threshold(config.max_level,config): return rejected
	var row: Dictionary=records[id]
	var level:=1
	while level<int(config.max_level) and legitimate_experience>=_threshold(level+1,config): level+=1
	var xp_delta:=legitimate_experience-int(row.experience)
	var level_delta:=level-int(row.level)
	var expiry:=float(row.expires_at)+level_delta*float(config.level_years)*_year()
	if not _number(expiry,0,MAX_TIME): return rejected
	row.experience=legitimate_experience
	row.level=level
	row.expires_at=expiry
	# The owning civilization commits any due retirement and ledger replacement
	# before persisting or exposing this intermediate, already-expired record.
	return {"accepted":true,"xp_delta":xp_delta,"level_delta":level_delta,"expires_at":expiry,"expired":expiry<=world_seconds}

static func _bloom_positions(event_id: String) -> Array[int]:
	var digest := event_id.sha256_text()
	var result: Array[int] = []
	for i in range(4): result.append(digest.substr(i*8,8).hex_to_int()%(BLOOM_BYTES*8))
	return result

static func _bloom_has(bits: PackedByteArray, positions: Array[int]) -> bool:
	for position: int in positions:
		if (bits[position/8]&(1<<(position%8)))==0: return false
	return true

static func _bloom_mark(bits: PackedByteArray, positions: Array[int]) -> PackedByteArray:
	for position: int in positions: bits[position/8] = bits[position/8]|(1<<(position%8))
	return bits

func record_event(event: Dictionary) -> Dictionary:
	var rejected := {"accepted":false,"xp":0,"levels_gained":0,"reason":"Invalid or non-civilian event"}
	if event.has("event_type"):
		if event.has("type") and event.type!=event.event_type: return rejected
		event = event.duplicate()
		event.type = event.event_type
	if not _prepare() or not _text(event.get("actor_id"),64) or not records.has(event.actor_id) or not records[event.actor_id].active: return rejected
	if not _text(event.get("event_id"),128) or not _text(event.get("target_id"),128) or event.get("type") not in EVENT_TYPES or event.get("rarity") not in config.rarity_xp or not _number(event.get("significance"),-1000000,1000000): return rejected
	if event.type=="economic" and not _integer(event.get("coins"),1,1000000000): return rejected
	var row: Dictionary = records[event.actor_id]
	var bits: PackedByteArray = String(row.event_bloom).hex_decode()
	if bits.is_empty(): bits.resize(BLOOM_BYTES); bits.fill(0)
	var positions := _bloom_positions("receipt/"+String(event.event_id))
	if _bloom_has(bits,positions): rejected.reason="Duplicate event receipt"; return rejected
	bits = _bloom_mark(bits,positions)
	var key := String(event.type)+"/"+String(event.target_id).sha256_text()
	var day := floori(world_seconds/float(config.day_seconds))
	# Daily commerce may become meaningful again; expired daily counters need no
	# permanent tombstone because the authoritative clock cannot revisit their day.
	for previous: String in row.novelty.keys():
		if previous.begins_with("economic/") and previous.get_slice("/",1)!=str(day): row.novelty.erase(previous)
	if event.type=="economic": key="economic/"+str(day)+"/"+String(event.target_id).sha256_text()
	if not row.novelty.has(key):
		if _bloom_has(bits,_bloom_positions("semantic/"+key)):
			row.event_bloom = bits.hex_encode()
			rejected.reason="Previously retired semantic achievement"
			return rejected
		if row.novelty.size()>=MAX_NOVELTY:
			# The bounded working set can admit new discoveries without making
			# evicted achievements farmable through newly minted receipt IDs.
			var retired: String = row.novelty.keys()[0]
			bits = _bloom_mark(bits,_bloom_positions("semantic/"+retired))
			row.novelty.erase(retired)
	row.event_bloom = bits.hex_encode()
	var repeats := int(row.novelty.get(key,0))
	row.novelty[key] = mini(3,repeats+1)
	var factor: float = [1.0,.5,.25,0.0][mini(3,repeats)]
	var base := float(config.rarity_xp[event.rarity])
	if event.type=="economic": base*=sqrt(minf(10000,float(event.coins)))
	var significance := clampf(float(event.significance),0,1)
	var reward := roundi(base*significance*factor)
	var before: int = row.experience
	var levels := grant_xp(event.actor_id,reward)
	remember(event.actor_id,event.type,event.target_id,String(event.type)+" / "+String(event.rarity),significance)
	return {"accepted":true,"xp":int(row.experience)-before,"levels_gained":levels,"reason":"Recorded" if reward>0 else "Repetitive event"}

func remember(id: String, type: String, target: String, summary: String, importance: float = .5) -> bool:
	if not records.has(id) or not records[id].active or not _text(type,32) or not _text(target,128,true) or not _text(summary,512) or not _number(importance,0,1): return false
	var memories: Array = records[id].memories
	var entry := {"type":type,"target":target,"summary":summary,"importance":importance,"timestamp":world_seconds}
	for i in range(memories.size()):
		if memories[i].type==type and memories[i].target==target: memories[i]=entry; return true
	if memories.size()>=MAX_MEMORIES:
		var lowest := 0
		for i in range(1,memories.size()):
			var a: Dictionary=memories[i]
			var b: Dictionary=memories[lowest]
			var a_rank: float=float(a.importance)+(2 if a.type=="autonomy" and a.target=="decision" else 0)
			var b_rank: float=float(b.importance)+(2 if b.type=="autonomy" and b.target=="decision" else 0)
			if a_rank<b_rank or a_rank==b_rank and a.timestamp<b.timestamp: lowest=i
		memories.remove_at(lowest)
	memories.append(entry)
	return true

func relate(id: String, target: String, delta: float) -> bool:
	if not records.has(id) or not records[id].active or not _text(target,128) or target==id or not is_finite(delta): return false
	var relations: Dictionary=records[id].relationships
	if not relations.has(target) and relations.size()>=MAX_RELATIONSHIPS: return false
	relations[target]=clampf(float(relations.get(target,0))+delta,-1,1)
	return true

func set_goal(id: String, goal: String, target: String = "") -> bool:
	if not records.has(id) or not records[id].active or not _text(goal,64) or not _text(target,128,true): return false
	records[id].current_goal=goal
	records[id].goal_target=target
	return true

func combat_respawn(id: String) -> Dictionary:
	return records[id].respawn.duplicate(true) if records.has(id) and records[id].active else {}

func serialize() -> Dictionary:
	return {"version":1,"config":config.duplicate(true),"world_seconds":world_seconds,"replacement_serial":replacement_serial,"records":records.duplicate(true),"slots":slots.duplicate(true)}

static func validate(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size()!=6 or not _integer(data.get("version"),1,1) or not _number(data.get("world_seconds"),0,MAX_TIME) or not _integer(data.get("replacement_serial"),0,MAX_RECORDS): return {}
	var settings := _settings(data.get("config"))
	if settings.is_empty() or not data.get("records") is Dictionary or data.records.size()>MAX_RECORDS or not data.get("slots") is Dictionary or data.slots.size()>MAX_ACTIVE: return {}
	var allowed := ["id","slot","name","occupation","personality","respawn","motivations","current_goal","goal_target","guild","level","experience","expires_at","born_at","active","memories","relationships","novelty","event_bloom","generation","serial","replaced_by"]
	var clean: Dictionary={}
	var serials: Dictionary={}
	var groups: Dictionary={}
	var year: float=float(settings.day_seconds)*float(settings.days_per_year)
	for id: Variant in data.records:
		var row: Variant=data.records[id]
		if not _id(id) or not row is Dictionary or row.size()!=allowed.size()+(1 if row.has("retired_at") else 0): return {}
		for key: Variant in row:
			if key not in allowed and key!="retired_at": return {}
		if row.id!=id or not _slot(row.slot) or not _text(row.name,80) or not _text(row.occupation,64) or not _text(row.personality,32) or _respawn(row.respawn).is_empty() or not _text(row.current_goal,64) or not _text(row.goal_target,128,true) or not _text(row.guild,64,true): return {}
		if not row.active is bool or not _integer(row.level,1,settings.max_level) or not _integer(row.experience,0,_threshold(settings.max_level,settings)) or not _integer(row.generation,0,MAX_RECORDS) or not _integer(row.serial,0,data.replacement_serial): return {}
		if row.experience<_threshold(int(row.level),settings) or row.level<settings.max_level and row.experience>=_threshold(int(row.level)+1,settings): return {}
		if not _number(row.born_at,0,data.world_seconds) or not _number(row.expires_at,0,MAX_TIME): return {}
		var expected: float=float(row.born_at)+year*(float(settings.lifetime_years)+(int(row.level)-1)*float(settings.level_years))
		if absf(float(row.expires_at)-expected)>maxf(.000001,absf(expected)*1.0e-12): return {}
		if row.active and row.expires_at<=data.world_seconds or not row.active and row.expires_at>data.world_seconds: return {}
		var retired: Variant=row.get("retired_at",0.0 if row.active else row.expires_at)
		if not _number(retired,0,data.world_seconds) or (row.active and retired!=0) or (not row.active and retired<row.expires_at): return {}
		if row.generation==0:
			if row.serial!=0 or id!=_initial_id(row.slot): return {}
		else:
			if row.serial==0 or serials.has(int(row.serial)) or id!="cf_%d_%d" % [absi(String(row.slot).hash()),int(row.serial)]: return {}
			serials[int(row.serial)]=true
		if not row.motivations is Dictionary or row.motivations.size()!=MOTIVATIONS.size(): return {}
		for motive: String in MOTIVATIONS:
			if not _number(row.motivations.get(motive),0,1): return {}
		if not row.memories is Array or row.memories.size()>MAX_MEMORIES: return {}
		var memory_keys: Dictionary={}
		for memory: Variant in row.memories:
			if not memory is Dictionary or memory.size()!=5 or not _text(memory.get("type"),32) or not _text(memory.get("target"),128,true) or not _text(memory.get("summary"),512) or not _number(memory.get("importance"),0,1) or not _number(memory.get("timestamp"),0,data.world_seconds): return {}
			var key: String=JSON.stringify([memory.type,memory.target])
			if memory_keys.has(key): return {}
			memory_keys[key]=true
		if not row.relationships is Dictionary or row.relationships.size()>MAX_RELATIONSHIPS: return {}
		for target: Variant in row.relationships:
			if not _text(target,128) or target==id or not _number(row.relationships[target],-1,1): return {}
		if not row.novelty is Dictionary or row.novelty.size()>MAX_NOVELTY: return {}
		for key: Variant in row.novelty:
			if not _text(key,128) or not _integer(row.novelty[key],1,3): return {}
		if not row.event_bloom is String or row.event_bloom.length() not in [0,BLOOM_BYTES*2]: return {}
		# A cached native expression validates the bounded lowercase hex buffer;
		# avoid thousands of GDScript character iterations per active identity.
		if _bloom_hex.search(row.event_bloom)==null: return {}
		if not _text(row.replaced_by,64,true) or row.active and not row.replaced_by.is_empty() or not row.active and row.replaced_by.is_empty(): return {}
		if not groups.has(row.slot): groups[row.slot]={}
		if groups[row.slot].has(int(row.generation)): return {}
		groups[row.slot][int(row.generation)]=id
		clean[id]=row.duplicate(true)
		clean[id].respawn=_respawn(row.respawn)
		for key: String in ["level","experience","generation","serial"]: clean[id][key]=int(row[key])
		clean[id].born_at=float(row.born_at)
		clean[id].expires_at=float(row.expires_at)
		clean[id].retired_at=float(retired)
		for motive: String in MOTIVATIONS: clean[id].motivations[motive]=float(row.motivations[motive])
		for memory: Dictionary in clean[id].memories:
			memory.importance=float(memory.importance)
			memory.timestamp=float(memory.timestamp)
		for target: String in row.relationships: clean[id].relationships[target]=float(row.relationships[target])
		for key: String in row.novelty: clean[id].novelty[key]=int(row.novelty[key])
	if serials.size()!=int(data.replacement_serial) or groups.size()!=data.slots.size(): return {}
	for slot: Variant in data.slots:
		var id: Variant=data.slots[slot]
		if not _slot(slot) or not _id(id) or not clean.has(id) or not clean[id].active or clean[id].slot!=slot: return {}
		var group: Dictionary=groups[slot]
		if group.size()!=int(clean[id].generation)+1: return {}
		for generation: int in range(group.size()):
			if not group.has(generation): return {}
			var row: Dictionary=clean[group[generation]]
			if generation==group.size()-1:
				if not row.active: return {}
			else:
				var next: Dictionary=clean[group[generation+1]]
				if row.active or row.replaced_by!=next.id or row.retired_at!=next.born_at: return {}
	return {"version":1,"config":settings,"world_seconds":float(data.world_seconds),"replacement_serial":int(data.replacement_serial),"records":clean,"slots":data.slots.duplicate(true)}

func restore(data: Variant) -> bool:
	var decoded := validate(data)
	if decoded.is_empty(): last_error="Invalid civilian registry snapshot"; return false
	config=decoded.config
	world_seconds=decoded.world_seconds
	replacement_serial=decoded.replacement_serial
	records=decoded.records
	slots=decoded.slots
	_census_dirty=true
	last_error=""
	return true
