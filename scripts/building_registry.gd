extends RefCounted
## Physical identity, use and owned contents are separate from generated meshes.
const Item=preload("res://scripts/item_instance.gd")
const Catalog=preload("res://scripts/item_catalog.gd")
const Inventory=preload("res://scripts/inventory.gd")
const MAX_BUILDINGS:=4096
const MAX_PLACEMENTS:=64
const USES:=["vacant","residence","shop","tavern","workshop","warehouse","guild_headquarters","office","hideout","mixed"]
var records: Dictionary={}
var revision:=0
var last_error:=""

static func owner_key(id: String) -> String: return "building:"+id
static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high
static func _point(value: Variant) -> bool:
	if not value is Array or value.size()!=3: return false
	for v: Variant in value:
		if not _number(v,-1000000,1000000): return false
	return true

func register(descriptor: Dictionary) -> bool:
	var id:=String(descriptor.get("id",""))
	if not Item.valid_text(id,false,80) or records.has(id) or records.size()>=MAX_BUILDINGS: return false
	var point: Variant=descriptor.get("point")
	var size: Variant=descriptor.get("size")
	if not point is Vector3 or not size is Vector3 or not point.is_finite() or not size.is_finite(): return false
	var layout: Dictionary=descriptor.get("layout",{})
	var floors:=int(layout.get("floor_count",1))
	var height:=float(layout.get("floor_height",3.5))
	var review: bool=bool(descriptor.get("manual_review",false)) or size.x<7 or size.z<9 or size.y<2.8
	records[id]={"id":id,"position":[point.x,point.y,point.z],"size":[size.x,size.y,size.z],"layout":{"floor_count":clampi(floors,1,512),"floor_height":clampf(height,2.8,8.0),"stair_min":layout.get("stair_min",[size.x*.5-4.0,-size.z*.5+.3]),"stair_max":layout.get("stair_max",[size.x*.5-.3,size.z*.5-2.5])},"manual_review":review,"owner":"","tenants":[],"occupants":[],"usage":"vacant","access":"public","placements":{},"storage":{"version":1,"owner_id":owner_key(id),"items":[],"equipment":{}},"renovation":0,"history":[]}
	revision+=1
	return true

func _history(row: Dictionary,kind: String,actor: String,now: float) -> void:
	row.history.append({"type":kind,"actor":actor,"timestamp":now})
	while row.history.size()>24: row.history.pop_front()

func claim(id: String,actor: String,now: float) -> bool:
	if not records.has(id) or records[id].manual_review or not records[id].owner.is_empty() or not Item.valid_text(actor) or not _number(now,0,1e15): return false
	var row: Dictionary=records[id]
	row.owner=actor; row.occupants=[actor]; row.usage="residence"
	_history(row,"claimed",actor,now); revision+=1
	return true

func allowed(id: String,actor: String) -> bool:
	return records.has(id) and actor==records[id].owner and not records[id].manual_review

func set_use(id: String,actor: String,usage: String,now: float) -> bool:
	if not allowed(id,actor) or usage not in USES or usage=="vacant": return false
	records[id].usage=usage; _history(records[id],"use/"+usage,actor,now); revision+=1
	return true

func set_access(id: String,actor: String,access: String,now: float) -> bool:
	if not allowed(id,actor) or access not in ["public","owner","tenants"]: return false
	records[id].access=access; _history(records[id],"access/"+access,actor,now); revision+=1
	return true

func admit(id: String,actor: String,tenant: String,now: float) -> bool:
	if not allowed(id,actor) or not Item.valid_text(tenant) or records[id].tenants.size()>=16: return false
	if tenant not in records[id].tenants: records[id].tenants.append(tenant)
	_history(records[id],"tenant",tenant,now); revision+=1
	return true

func can_place(id: String,item: Dictionary,position: Array,yaw: float,ignore: String="") -> bool:
	last_error=""
	if not records.has(id) or records[id].manual_review or not _point(position) or not is_finite(yaw): last_error="This shell is not available."; return false
	if absf(wrapf(yaw-roundf(yaw/(PI*.5))*PI*.5,-PI,PI))>.0001: last_error="Rotate in quarter turns to keep the snapped footprint clear."; return false
	var row: Dictionary=records[id]
	var definition: Resource=Catalog.get_definition(StringName(item.get("item_type_id","")))
	if definition==null or not definition.custom_properties.get("placeable",false): last_error="This item cannot be installed."; return false
	var props: Dictionary=definition.custom_properties
	var dimensions: Array=props.get("size",[1.0,1.0,1.0])
	if dimensions.size()!=3: return false
	var x:=float(position[0]); var y:=float(position[1]); var z:=float(position[2])
	var floor:=floori((y+.05)/float(row.layout.floor_height))
	if floor<0 or floor>=int(row.layout.floor_count): last_error="No interior floor supports that position."; return false
	var surface:=String(props.get("placement_surface","floor"))
	var base_y:=floor*float(row.layout.floor_height)
	if surface in ["floor","surface"] and absf(y-base_y)>.12 and surface!="surface": last_error="Snap to a floor."; return false
	var rotated:=posmod(roundi(yaw/(PI*.5)),2)==1
	var half_x:=float(dimensions[2] if rotated else dimensions[0])*.5
	var half_z:=float(dimensions[0] if rotated else dimensions[2])*.5
	var bound_x:=float(row.size[0])*.5-.45; var bound_z:=float(row.size[2])*.5-.45
	if absf(x)+half_x>bound_x or absf(z)+half_z>bound_z: last_error="The object crosses a wall."; return false
	if y+float(dimensions[1])>base_y+float(row.layout.floor_height)-.2: last_error="The object crosses the ceiling."; return false
	if x-half_x<1.5 and x+half_x> -1.5 and z+half_z>bound_z-.5 and y-base_y<2.9: last_error="Keep the doorway unobstructed."; return false
	# Keep a continuous exit aisle and every stair landing usable on all floors.
	if x-half_x<1.1 and x+half_x> -1.1 and surface not in ["wall","ceiling"]: last_error="Keep the central exit aisle clear."; return false
	var stair_min: Array=row.layout.stair_min; var stair_max: Array=row.layout.stair_max
	if x+half_x>float(stair_min[0]) and x-half_x<float(stair_max[0]) and z+half_z>float(stair_min[1]) and z-half_z<float(stair_max[1]): last_error="Keep the stairs and landing clear."; return false
	if surface=="wall" and minf(bound_x-half_x-absf(x),bound_z-half_z-absf(z))>.2: last_error="Snap wall objects against an interior wall."; return false
	if surface=="ceiling" and absf(y+float(dimensions[1])-(base_y+float(row.layout.floor_height)-.25))>.15: last_error="Snap hanging objects below the ceiling."; return false
	var supported:=surface!="surface" or absf(y-base_y)<.12
	for other: Dictionary in row.placements.values():
		if other.id==ignore: continue
		var other_def: Resource=Catalog.get_definition(StringName(other.item.item_type_id))
		var other_size: Array=other_def.custom_properties.get("size",[1,1,1])
		var other_rotated:=posmod(roundi(float(other.yaw)/(PI*.5)),2)==1
		var ox:=float(other_size[2] if other_rotated else other_size[0])*.5
		var oz:=float(other_size[0] if other_rotated else other_size[2])*.5
		var overlap:=absf(x-float(other.position[0]))<half_x+ox-.03 and absf(z-float(other.position[2]))<half_z+oz-.03
		var top:=float(other.position[1])+float(other_size[1])
		if surface=="surface" and absf(y-top)<.12 and absf(x-float(other.position[0]))+half_x<=ox and absf(z-float(other.position[2]))+half_z<=oz: supported=true
		if overlap and y<top-.03 and y+float(dimensions[1])>float(other.position[1])+.03: last_error="Another object occupies that space."; return false
	if not supported: last_error="This object needs a supporting surface."; return false
	return true

func install(id: String,actor: String,item: Dictionary,position: Array,yaw: float,now: float) -> bool:
	if not allowed(id,actor) or records[id].placements.size()>=MAX_PLACEMENTS or item.get("owner_id")!=owner_key(id) or item.get("quantity")!=1 or not can_place(id,item,position,yaw): return false
	var resource:=Item.from_dict(item)
	if resource==null or records[id].placements.has(resource.instance_id): return false
	records[id].placements[resource.instance_id]={"id":resource.instance_id,"item":resource.to_dict(),"position":position.duplicate(),"yaw":wrapf(yaw,-PI,PI)}
	records[id].renovation+=1; _history(records[id],"furnished",actor,now); revision+=1
	return true

func remove(id: String,actor: String,placement: String,now: float) -> Dictionary:
	if not allowed(id,actor) or not records[id].placements.has(placement): return {}
	var row: Dictionary=records[id].placements[placement]
	# A surface cannot be pulled out from beneath another installed object.
	var def: Resource=Catalog.get_definition(StringName(row.item.item_type_id))
	var top:=float(row.position[1])+float(def.custom_properties.get("size",[1,1,1])[1])
	for other: Dictionary in records[id].placements.values():
		if other.id!=placement and absf(float(other.position[1])-top)<.12 and Vector2(float(other.position[0])-float(row.position[0]),float(other.position[2])-float(row.position[2])).length()<2: return {}
	records[id].placements.erase(placement); records[id].renovation+=1; _history(records[id],"removed",actor,now); revision+=1
	return row.item.duplicate(true)

func serialize() -> Dictionary:
	var occupied: Dictionary={}
	for id: String in records:
		var row: Dictionary=records[id]
		if not row.owner.is_empty() or not row.placements.is_empty() or not row.storage.items.is_empty() or not row.history.is_empty(): occupied[id]=row.duplicate(true)
	return {"version":1,"records":occupied}
func restore(input: Variant) -> bool:
	if input==null:
		for row: Dictionary in records.values():
			row.owner=""; row.occupants=[]; row.tenants=[]; row.usage="vacant"; row.access="public"; row.placements={}; row.storage={"version":1,"owner_id":owner_key(row.id),"items":[],"equipment":{}}; row.history=[]; row.renovation=0
		revision+=1; return true
	var clean:=validate(input)
	if clean.is_empty(): return false
	# Geometry manifests are authoritative. A checkpoint cannot move or resize a building.
	for id: String in clean.records:
		if not records.has(id): return false
		for key: String in ["position","size","layout","manual_review"]:
			if not _geometry_matches(records[id][key],clean.records[id][key]): return false
	for row: Dictionary in records.values():
		row.owner=""; row.occupants=[]; row.tenants=[]; row.usage="vacant"; row.access="public"; row.placements={}; row.storage={"version":1,"owner_id":owner_key(row.id),"items":[],"equipment":{}}; row.history=[]; row.renovation=0
	for id: String in clean.records: records[id]=clean.records[id]
	revision+=1; return true

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=2 or input.get("version")!=1 or not input.get("records") is Dictionary or input.records.size()>MAX_BUILDINGS: return {}
	var model: RefCounted=load("res://scripts/building_registry.gd").new()
	var ids: Dictionary={}
	for id: Variant in input.records:
		var row: Variant=input.records[id]
		if not Item.valid_text(id,false,80) or not row is Dictionary or row.size()!=14 or row.get("id")!=id or not _point(row.get("position")) or not _point(row.get("size")) or not row.get("manual_review") is bool: return {}
		for dimension: Variant in row.size:
			if not _number(dimension,.1,2000): return {}
		if not row.get("layout") is Dictionary or row.layout.size()!=4 or not Item.whole_number(row.layout.get("floor_count"),1,512) or not _number(row.layout.get("floor_height"),2.8,8): return {}
		for key: String in ["stair_min","stair_max"]:
			if not row.layout.get(key) is Array or row.layout[key].size()!=2: return {}
			for axis: Variant in row.layout[key]:
				if not _number(axis,-2000,2000): return {}
		if not Item.valid_text(row.get("owner"),true) or row.get("usage") not in USES or row.get("access") not in ["public","owner","tenants"] or not Item.whole_number(row.get("renovation"),0,1000000000): return {}
		if row.manual_review or row.owner.is_empty(): return {}
		for key: String in ["tenants","occupants"]:
			if not row.get(key) is Array or row[key].size()>16: return {}
			var seen: Dictionary={}
			for actor: Variant in row[key]:
				if not Item.valid_text(actor) or seen.has(actor): return {}
				seen[actor]=true
		if not row.get("history") is Array or row.history.size()>24 or not row.get("placements") is Dictionary or row.placements.size()>MAX_PLACEMENTS: return {}
		for event: Variant in row.history:
			if not event is Dictionary or event.size()!=3 or not Item.valid_text(event.get("type")) or not Item.valid_text(event.get("actor")) or not _number(event.get("timestamp"),0,1e15): return {}
		var store:=Inventory.new()
		if not store.restore(row.get("storage")): store.free(); return {}
		var stored: Dictionary=store.serialize(); store.free()
		if stored.owner_id!=owner_key(id) or not stored.equipment.is_empty() or not stored.get("respawn_points",{}).is_empty() or not stored.get("shield_state",{}).is_empty() or not stored.get("boss_reward_claims",{}).is_empty(): return {}
		for item: Dictionary in stored.items:
			if ids.has(item.instance_id): return {}
			ids[item.instance_id]=true
		model.records[id]=row.duplicate(true); model.records[id].placements={}; model.records[id].storage=stored
		for pid: Variant in row.placements:
			var placement: Variant=row.placements[pid]
			if not placement is Dictionary or placement.size()!=4 or placement.get("id")!=pid or not _point(placement.get("position")) or not _number(placement.get("yaw"),-PI,PI): return {}
			var item:=Item.from_dict(placement.get("item"))
			if item==null or item.instance_id!=pid or ids.has(pid) or item.owner_id!=owner_key(id) or item.quantity!=1: return {}
			ids[pid]=true; model.records[id].placements[pid]=placement.duplicate(true)
		for placement: Dictionary in model.records[id].placements.values():
			if not model.can_place(id,placement.item,placement.position,float(placement.yaw),placement.id): return {}
	return model.serialize()

static func _geometry_matches(a: Variant,b: Variant) -> bool:
	# JSON's decimal round trip can change the last few bits of mesh dimensions.
	if (a is int or a is float) and (b is int or b is float): return absf(float(a)-float(b))<=.00001
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i: int in a.size():
			if not _geometry_matches(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _geometry_matches(a[key],b[key]): return false
		return true
	return a==b
