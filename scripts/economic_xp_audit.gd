extends RefCounted
## Bounded economic provenance. Legality is informational; only substance and
## corroborated asset loops affect civilian XP. This model contains values only.
const Registry = preload("res://scripts/code_form_registry.gd")
const MAX_TRANSACTIONS := 2048
const ASSET_HISTORY := 16
const REVIEW_BATCH := 16
const DEFAULT_CONFIG := {"xp_per_sqrt_coin":8.0,"max_xp_per_transaction":128,"review_window_days":7.0,"circular_window_hours":1.0,"min_loop_sales":4,"artificial_price_ratio":4.0}
var config: Dictionary=DEFAULT_CONFIG.duplicate()
var owner_id := ""
var last_sequence := 0
var review_cursor := 0
var transactions: Dictionary={}
var order: Array[String]=[]
var _asset_index: Dictionary={}
var _capture_rows: Dictionary={}
var _capture_dirty: Dictionary={}

func warm_capture() -> void:
	var began:=Time.get_ticks_usec()
	var count:=0
	for id: String in _capture_dirty.keys():
		_capture_rows[id]=transactions[id].duplicate(true)
		_capture_dirty.erase(id)
		count+=1
		if count>=24 or Time.get_ticks_usec()-began>=2000: break

func capture_values() -> Dictionary:
	for id: String in _capture_dirty.keys(): _capture_rows[id]=transactions[id].duplicate(true)
	_capture_dirty.clear()
	return {"version":1,"owner_id":owner_id,"config":config.duplicate(),"last_sequence":last_sequence,"review_cursor":review_cursor,"transactions":_capture_rows.duplicate(),"order":order.duplicate()}


static func _settings(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=DEFAULT_CONFIG.size(): return {}
	for key: String in DEFAULT_CONFIG:
		if not input.has(key): return {}
	var result: Dictionary={}
	for key: String in ["xp_per_sqrt_coin","review_window_days","circular_window_hours","artificial_price_ratio"]:
		var low:=1.0 if key=="artificial_price_ratio" else .001
		if not Registry._number(input[key],low,10000): return {}
		result[key]=float(input[key])
	if not Registry._integer(input.max_xp_per_transaction,1,1000000) or not Registry._integer(input.min_loop_sales,4,ASSET_HISTORY) or int(input.min_loop_sales)%2!=0: return {}
	result.max_xp_per_transaction=int(input.max_xp_per_transaction)
	result.min_loop_sales=int(input.min_loop_sales)
	return result

func configure(owner: String,sequence_floor: int = 0,settings: Dictionary = DEFAULT_CONFIG) -> bool:
	var accepted:=_settings(settings)
	if not Registry._text(owner,64) or not Registry._integer(sequence_floor,0,1000000000) or accepted.is_empty(): return false
	owner_id=owner; last_sequence=sequence_floor; config=accepted
	transactions.clear(); order.clear(); _asset_index.clear(); review_cursor=0
	_capture_rows.clear(); _capture_dirty.clear()
	return true

static func _canonical_receipt(input: Variant,owner: String,known: Dictionary,now: float) -> Dictionary:
	if not input is Dictionary or not Registry._integer(input.get("sequence"),1,1000000000): return {}
	var identity:=owner+":commerce:"+str(int(input.sequence))
	if input.get("id")!=identity or input.get("transaction_id")!=identity or not Registry._number(input.get("world_timestamp"),0,now) or not Registry._integer(input.get("amount"),1,1000000000): return {}
	if input.get("substance") not in ["goods","service","retail_sink"] or input.get("legality") not in ["legal","illegal","unknown"] or not input.get("participants") is Array or input.participants.size()>8: return {}
	var people: Array[String]=[]
	for id: Variant in input.participants:
		if not id is String or not known.has(id) or people.has(id): return {}
		people.append(id)
	if people.is_empty(): return {}
	var result: Dictionary={"id":identity,"transaction_id":identity,"sequence":int(input.sequence),"world_timestamp":float(input.world_timestamp),"amount":int(input.amount),"participants":people,"substance":String(input.substance),"legality":String(input.legality)}
	for key: String in ["context","transaction_type","counterpart","sender_account","receiver_account","asset_id","delivered_asset_id","asset_type","asset_sender_id","asset_receiver_id","related_event_id"]:
		var empty:=key in ["asset_id","delivered_asset_id","asset_type","asset_sender_id","asset_receiver_id","related_event_id"]
		if not Registry._text(input.get(key),128,empty): return {}
		result[key]=String(input[key])
	if result.sender_account==result.receiver_account: return {}
	if not Registry._integer(input.get("quantity"),0,999999) or not Registry._integer(input.get("reference_price"),0,1000000000): return {}
	result.quantity=int(input.quantity); result.reference_price=int(input.reference_price)
	if result.substance in ["goods","retail_sink"] and (result.asset_id.is_empty() or result.delivered_asset_id.is_empty() or result.asset_type.is_empty() or result.asset_sender_id==result.asset_receiver_id or result.quantity<1): return {}
	return result

func _index(row: Dictionary) -> void:
	if row.asset_id.is_empty(): return
	if not _asset_index.has(row.asset_id): _asset_index[row.asset_id]=[]
	var recent: Array=_asset_index[row.asset_id]
	recent.append(row.id)
	if recent.size()>ASSET_HISTORY: recent.pop_front()

func record_transaction(receipt: Dictionary,registry: RefCounted) -> Dictionary:
	if owner_id.is_empty() or int(receipt.get("sequence",0))<=last_sequence: return {}
	var row:=_canonical_receipt(receipt,owner_id,registry.records,float(registry.world_seconds))
	if row.is_empty(): return {}
	var awards: Dictionary={}
	var requested:=mini(int(config.max_xp_per_transaction),maxi(1,roundi(sqrt(float(row.amount))*float(config.xp_per_sqrt_coin))))
	for id: String in row.participants:
		if not registry.records[id].active: continue
		var before:=int(registry.records[id].experience)
		registry.grant_xp(id,requested)
		awards[id]=int(registry.records[id].experience)-before
	row.xp_awards=awards; row.xp_status="awarded"; row.reversal_reason=""; row.reversed_at=0.0
	_capture_dirty[row.id]=true
	transactions[row.id]=row; order.append(row.id); last_sequence=int(row.sequence)
	_index(row)
	if order.size()>MAX_TRANSACTIONS:
		var expired: String=order.pop_front()
		var asset: String=transactions[expired].asset_id
		transactions.erase(expired)
		_capture_rows.erase(expired); _capture_dirty.erase(expired)
		if _asset_index.has(asset):
			_asset_index[asset].erase(expired)
			if _asset_index[asset].is_empty(): _asset_index.erase(asset)
		review_cursor=maxi(0,review_cursor-1)
	return row.duplicate(true)

func _circular_asset(row: Dictionary,now: float,day_seconds: float) -> Array[String]:
	var found: Dictionary={}
	if row.asset_id.is_empty(): return []
	var history: Array=_asset_index.get(row.asset_id,[])
	# Check small repeated owner cycles inside one asset's sixteen-entry index,
	# never an all-to-all comparison of the society's wallets or history.
	for cycle_size in range(2,5):
		var count:=cycle_size*maxi(2,ceili(float(config.min_loop_sales)/float(cycle_size)))
		for ending in range(count,history.size()+1):
			var tail: Array=history.slice(ending-count,ending)
			var first: Dictionary=transactions[tail[0]]
			var last: Dictionary=transactions[tail[-1]]
			if now-float(last.world_timestamp)>float(config.review_window_days)*day_seconds or float(last.world_timestamp)-float(first.world_timestamp)>float(config.circular_window_hours)*day_seconds/24.0: continue
			var owners: Dictionary={}
			var valid:=true
			for i in range(tail.size()):
				var candidate: Dictionary=transactions[tail[i]]
				var model: Dictionary=transactions[tail[i%cycle_size]]
				var next: Dictionary=transactions[tail[(i+1)%tail.size()]]
				if i<cycle_size: owners[candidate.asset_sender_id]=true
				if candidate.transaction_type!="item_sale" or candidate.asset_id!=candidate.delivered_asset_id or candidate.amount!=first.amount or candidate.quantity!=first.quantity or candidate.asset_type!=first.asset_type or candidate.context!=first.context or candidate.asset_sender_id!=model.asset_sender_id or candidate.asset_receiver_id!=model.asset_receiver_id or candidate.asset_receiver_id!=next.asset_sender_id or candidate.reference_price<1 or float(candidate.amount)<float(candidate.reference_price)*float(candidate.quantity)*float(config.artificial_price_ratio): valid=false; break
			if valid and owners.size()==cycle_size:
				for id: String in tail: found[id]=true
	var result: Array[String]=[]
	for id: String in history:
		if found.has(id): result.append(id)
	return result

func find_reversals(now: float,day_seconds: float,budget: int = REVIEW_BATCH) -> Array[String]:
	var found: Dictionary={}
	if order.is_empty() or budget<1: return []
	for i in range(mini(budget,REVIEW_BATCH)):
		if review_cursor>=order.size(): review_cursor=0
		var row: Dictionary=transactions[order[review_cursor]]
		review_cursor+=1
		if now-float(row.world_timestamp)>float(config.review_window_days)*day_seconds: continue
		for id: String in _circular_asset(row,now,day_seconds):
			if transactions[id].xp_status!="reversed": found[id]=true
		if row.xp_status=="awarded":
			row.xp_status="confirmed"; _capture_dirty[row.id]=true
	var result: Array[String]=[]
	for id: String in order:
		if found.has(id): result.append(id)
	return result

func apply_reversals(ids: Array,registry: RefCounted,reason: String = "Repeated unchanged-asset buybacks at an artificial price") -> Dictionary:
	if not Registry._text(reason,256) or ids.size()>ASSET_HISTORY*REVIEW_BATCH: return {}
	var totals: Dictionary={}
	var selected: Array[String]=[]
	for id: Variant in ids:
		if not id is String or not transactions.has(id) or selected.has(id): return {}
		var row: Dictionary=transactions[id]
		if row.xp_status=="reversed": continue
		selected.append(id)
		for actor_id: String in row.xp_awards:
			totals[actor_id]=int(totals.get(actor_id,0))+int(row.xp_awards[actor_id])
	for id: String in totals:
		if not registry.records.has(id): return {}
		if registry.records[id].active and totals[id]>int(registry.records[id].experience): return {}
	var corrected: Dictionary={}
	for id: String in totals:
		if not registry.records[id].active: continue
		var result: Dictionary=registry.reconcile_xp(id,int(registry.records[id].experience)-int(totals[id]))
		if not result.get("accepted",false): return {}
		corrected[id]=result
	for id: String in selected:
		_capture_dirty[id]=true
		transactions[id].xp_status="reversed"; transactions[id].reversal_reason=reason; transactions[id].reversed_at=float(registry.world_seconds)
	return {"transactions":selected,"corrections":corrected,"removed_xp":totals}

func serialize() -> Dictionary:
	return {"version":1,"owner_id":owner_id,"config":config.duplicate(),"last_sequence":last_sequence,"review_cursor":review_cursor,"transactions":transactions.duplicate(true),"order":order.duplicate()}

static func validate(input: Variant,registry: Dictionary) -> Dictionary:
	if not input is Dictionary or input.size()!=7 or input.get("version")!=1 or not Registry._text(input.get("owner_id"),64) or not Registry._integer(input.get("last_sequence"),0,1000000000): return {}
	var settings:=_settings(input.get("config"))
	if settings.is_empty() or not input.get("transactions") is Dictionary or not input.get("order") is Array or input.order.size()>MAX_TRANSACTIONS or input.transactions.size()!=input.order.size() or not Registry._integer(input.get("review_cursor"),0,input.order.size()): return {}
	var rows: Dictionary={}
	var sequence_floor:=0
	var identities: Array[String]=[]
	var outstanding: Dictionary={}
	for id: Variant in input.order:
		if not id is String or rows.has(id) or not input.transactions.has(id): return {}
		var raw: Variant=input.transactions[id]
		if not raw is Dictionary or raw.size()!=25: return {}
		var row:=_canonical_receipt(raw,input.owner_id,registry.records,float(registry.world_seconds))
		if row.is_empty() or row.id!=id or row.sequence<=sequence_floor or row.sequence>input.last_sequence or raw.get("xp_status") not in ["awarded","under_review","confirmed","reversed"] or not raw.get("xp_awards") is Dictionary: return {}
		var awards: Dictionary={}
		for actor_id: Variant in raw.xp_awards:
			if not actor_id is String or actor_id not in row.participants or not Registry._integer(raw.xp_awards[actor_id],0,mini(int(settings.max_xp_per_transaction),maxi(1,roundi(sqrt(float(row.amount))*float(settings.xp_per_sqrt_coin))))): return {}
			awards[actor_id]=int(raw.xp_awards[actor_id])
		if not Registry._text(raw.get("reversal_reason"),256,true) or not Registry._number(raw.get("reversed_at"),0,registry.world_seconds): return {}
		if raw.xp_status=="reversed":
			if raw.reversal_reason.is_empty() or float(raw.reversed_at)<float(row.world_timestamp): return {}
		elif raw.reversal_reason!="" or raw.reversed_at!=0: return {}
		if raw.xp_status!="reversed":
			for actor_id: String in awards: outstanding[actor_id]=int(outstanding.get(actor_id,0))+int(awards[actor_id])
		row.xp_awards=awards; row.xp_status=String(raw.xp_status); row.reversal_reason=String(raw.reversal_reason); row.reversed_at=float(raw.reversed_at)
		rows[id]=row; identities.append(id); sequence_floor=int(row.sequence)
	for actor_id: String in outstanding:
		if int(outstanding[actor_id])>int(registry.records[actor_id].experience): return {}
	return {"version":1,"owner_id":String(input.owner_id),"config":settings,"last_sequence":int(input.last_sequence),"review_cursor":int(input.review_cursor),"transactions":rows,"order":identities}

func restore(input: Variant,registry: Dictionary) -> bool:
	var accepted:=validate(input,registry)
	if accepted.is_empty(): return false
	owner_id=accepted.owner_id; config=accepted.config; last_sequence=accepted.last_sequence; review_cursor=accepted.review_cursor; transactions=accepted.transactions; order.assign(accepted.order)
	_asset_index.clear(); _capture_rows.clear(); _capture_dirty.clear()
	for id: String in order:
		_index(transactions[id]); _capture_dirty[id]=true
	return true
