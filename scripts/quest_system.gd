extends Node
## Thin integration surface. The world supplies identity, verification, economy
## and memory adapters; neither a rendered NPC nor a dialogue is a quest engine.
const Model=preload("res://scripts/universal_quests.gd")
signal changed
var model:=Model.new()
var world: Node3D
var organizations: RefCounted:
	get: return model.organizations

func setup(callbacks: Dictionary) -> void: model.configure(callbacks)
func configure(callbacks: Dictionary) -> void: setup(callbacks)
func bootstrap_organizations(ids: Array,now: float) -> bool:
	var ok:=model.bootstrap_organizations(ids,now)
	if ok: changed.emit()
	return ok
func join_guild(id: String,key: String) -> bool:
	var ok:=model.join_guild(id,key)
	if ok: changed.emit()
	return ok
func leave_guild(id: String,key: String) -> bool:
	var ok:=model.leave_guild(id,key)
	if ok: changed.emit()
	return ok
func is_member(id: String,faction: String) -> bool: return model.is_member(id,faction)
func join(id: String,faction: String) -> bool:
	var ok:=model.join(id,faction)
	if ok: changed.emit()
	return ok
func introduce(id: String,contact: String) -> bool:
	var ok:=model.introduce(id,contact)
	if ok: changed.emit()
	return ok
func available(id: String,faction: String="",public_only: bool=false,guild_id: String="") -> Array[Dictionary]: return model.available(id,faction,public_only,guild_id)
func for_participant(id: String,include_history: bool=true) -> Array[Dictionary]: return model.for_participant(id,include_history)
func create_contract(template: String,issuer: String,source: String,terms: Dictionary,now: float) -> String:
	var id:=model.create_contract(template,issuer,source,terms,now)
	if not id.is_empty(): changed.emit()
	return id
func request_work(issuer: String,template: String,source: String,terms: Dictionary,now: float) -> String:
	var id:=model.request_work(issuer,template,source,terms,now)
	if not id.is_empty(): changed.emit()
	return id
func accept(id: String,participant: String,now: float) -> bool:
	var ok:=model.accept(id,participant,now)
	if ok: changed.emit()
	return ok
func consume_event(event: Dictionary) -> Array[String]:
	var ids:=model.consume_event(event)
	if not ids.is_empty(): changed.emit()
	return ids
func advance_to(now: float) -> bool:
	var before:=model.revision
	var ok:=model.advance_to(now)
	if before!=model.revision: changed.emit()
	return ok
func cancel(id: String,actor: String) -> bool:
	var ok:=model.cancel(id,actor)
	if ok: changed.emit()
	return ok
func fail(id: String,reason: String="") -> bool:
	var ok:=model.fail(id,reason)
	if ok: changed.emit()
	return ok
func on_replacements(changes: Array) -> void:
	for row: Dictionary in changes: model.retire(String(row.old_id))
	if not changes.is_empty(): changed.emit()
func board(faction: String,viewer: String,guild_id: String="") -> Dictionary:
	if not model.factions.has(faction) or not model.factions[faction].public: return {}
	return {"faction":model.factions[faction].duplicate(),"member":is_member(viewer,faction),"guilds":organizations.guilds_for_faction(faction),"contracts":available(viewer,faction,true,guild_id)}
func faction_account(faction: String) -> String: return "faction:"+faction if model.factions.has(faction) else ""
func obligations() -> Dictionary: return model.obligations()
func transaction_active() -> bool: return model.transaction_active() or organizations.transaction_active()
func serialize() -> Dictionary: return model.serialize()
func restore(data: Variant) -> bool:
	var ok:=model.restore(data)
	if ok: changed.emit()
	return ok
static func validate(data: Variant) -> Dictionary: return Model.validate(data)
